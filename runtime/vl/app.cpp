#include "vl/runtime.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <thread>

#ifdef VL_GUI
#include <SDL.h>
#include "imgui.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_sdlrenderer2.h"
#endif

namespace vl {

namespace {

double secondsNow() {
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
}

}  // namespace

// -- Node ---------------------------------------------------------------------

void Node::runEvery(double seconds) {
    vlInterval_ = seconds > 0 ? seconds : 0;
}

void Node::requestProcess() {
    if (vlApp_)
        vlApp_->schedule(*this);
}

bool Node::vlReady() const {
    for (const InputBase* input : vlInputs_) {
        if (!input->hasValue())
            return false;
    }
    return true;
}

// -- App ----------------------------------------------------------------------

App::App(std::string name, bool fullscreen, bool gui)
    : name_(std::move(name)), fullscreen_(fullscreen), gui_(gui) {}

void App::watch(Node& node, const InputBase& input) {
    node.vlInputs_.push_back(&input);
}

void App::setWidget(Node& node, bool visible, const std::string& title) {
    node.vlHasWidget_ = true;
    node.vlWidgetVisible_ = visible;
    node.vlWidgetTitle_ = title;
}

void App::schedule(Node& node) {
    if (!node.vlQueued_) {
        node.vlQueued_ = true;
        queue_.push_back(&node);
    }
}

void App::runTimers() {
    double now = secondsNow();
    for (auto& node : nodes_) {
        if (node->vlInterval_ > 0 && now >= node->vlNextRun_) {
            node->vlNextRun_ += node->vlInterval_;
            if (node->vlNextRun_ < now)  // Fell behind: don't try to catch up.
                node->vlNextRun_ = now + node->vlInterval_;
            schedule(*node);
        }
    }
}

void App::processQueue() {
    // Feedback wires never schedule a node, so this always ends; the limit is
    // only a safety net.
    for (int i = 0; i < 100000 && !queue_.empty(); ++i) {
        Node* node = queue_.front();
        queue_.pop_front();
        node->vlQueued_ = false;
        if (node->vlReady())
            node->process();
    }
}

double App::nextTimer() const {
    double next = INFINITY;
    for (const auto& node : nodes_) {
        if (node->vlInterval_ > 0)
            next = std::min(next, node->vlNextRun_);
    }
    return next;
}

int App::run() {
    // Show prints from nodes right away, also when piped into a log.
    std::setvbuf(stdout, nullptr, _IOLBF, 0);

    for (auto& node : nodes_)
        node->setup();

    // Every node gets one chance to run at the start (sources, constants...).
    double now = secondsNow();
    for (auto& node : nodes_) {
        if (node->vlInterval_ > 0)
            node->vlNextRun_ = now + node->vlInterval_;
        schedule(*node);
    }

#ifdef VL_GUI
    if (gui_)
        return runGui();
#endif
    return runHeadless();
}

int App::runHeadless() {
    for (;;) {
        processQueue();
        runTimers();
        if (!queue_.empty())
            continue;

        double next = nextTimer();
        if (std::isinf(next))
            return 0;  // Nothing can happen any more.
        double wait = next - secondsNow();
        if (wait > 0)
            std::this_thread::sleep_for(std::chrono::duration<double>(wait));
    }
}

#ifdef VL_GUI

int App::runGui() {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) != 0) {
        std::fprintf(stderr, "vl: no display (%s), running without widgets\n", SDL_GetError());
        return runHeadless();
    }

    Uint32 flags = SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI;
    if (fullscreen_)
        flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    SDL_Window* window = SDL_CreateWindow(name_.c_str(), SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                          1280, 720, flags);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_PRESENTVSYNC | SDL_RENDERER_ACCELERATED);
    if (!window || !renderer) {
        std::fprintf(stderr, "vl: could not open a window (%s)\n", SDL_GetError());
        SDL_Quit();
        return runHeadless();
    }

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr;  // Layout is automatic; nothing to remember.
    ImGui::StyleColorsDark();
    ImGui_ImplSDL2_InitForSDLRenderer(window, renderer);
    ImGui_ImplSDLRenderer2_Init(renderer);

    bool running = true;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            ImGui_ImplSDL2_ProcessEvent(&event);
            if (event.type == SDL_QUIT)
                running = false;
            if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)
                running = false;
        }

        runTimers();
        processQueue();

        ImGui_ImplSDLRenderer2_NewFrame();
        ImGui_ImplSDL2_NewFrame();
        ImGui::NewFrame();
        drawWidgets(io.DisplaySize.x, io.DisplaySize.y);
        ImGui::Render();

        SDL_RenderSetScale(renderer, io.DisplayFramebufferScale.x, io.DisplayFramebufferScale.y);
        SDL_SetRenderDrawColor(renderer, 23, 25, 29, 255);
        SDL_RenderClear(renderer);
        ImGui_ImplSDLRenderer2_RenderDrawData(ImGui::GetDrawData(), renderer);
        SDL_RenderPresent(renderer);

        processQueue();  // Values changed by widgets.
    }

    ImGui_ImplSDLRenderer2_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    ImGui::DestroyContext();
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}

// Arrange every shown widget in a grid that fills the window. The column
// count is chosen so cells are as close to 16:10 as possible, and all
// widgets share one text size, scaled to the cell size.
void App::drawWidgets(float width, float height) {
    std::vector<Node*> shown;
    for (auto& node : nodes_) {
        if (node->vlHasWidget_ && node->vlWidgetVisible_)
            shown.push_back(node.get());
    }

    if (shown.empty()) {
        const char* text = "No widgets to show.";
        ImVec2 size = ImGui::CalcTextSize(text);
        ImGui::SetNextWindowPos(ImVec2((width - size.x) / 2, (height - size.y) / 2));
        ImGui::Begin("##empty", nullptr, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoBackground);
        ImGui::TextDisabled("%s", text);
        ImGui::End();
        return;
    }

    const int count = static_cast<int>(shown.size());
    const float margin = 8;
    int columns = 1;
    double bestScore = INFINITY;
    for (int c = 1; c <= count; ++c) {
        int rows = (count + c - 1) / c;
        double aspect = (width / c) / (height / rows);
        double score = std::fabs(std::log(aspect / 1.6));
        if (score < bestScore) {
            bestScore = score;
            columns = c;
        }
    }
    const int rows = (count + columns - 1) / columns;
    const float cellWidth = (width - margin * (columns + 1)) / columns;
    const float cellHeight = (height - margin * (rows + 1)) / rows;

    ImGui::GetIO().FontGlobalScale = std::clamp(std::min(cellWidth / 320.0f, cellHeight / 200.0f), 1.0f, 4.0f);

    const ImGuiWindowFlags flags = ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize
        | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoSavedSettings;
    for (int i = 0; i < count; ++i) {
        Node* node = shown[i];
        int row = i / columns;
        int column = i % columns;
        ImGui::SetNextWindowPos(ImVec2(margin + column * (cellWidth + margin), margin + row * (cellHeight + margin)));
        ImGui::SetNextWindowSize(ImVec2(cellWidth, cellHeight));
        std::string title = node->vlWidgetTitle_ + "##" + node->vlId_;
        ImGui::Begin(title.c_str(), nullptr, flags);
        node->drawWidget();
        ImGui::End();
    }
}

#endif  // VL_GUI

}  // namespace vl
