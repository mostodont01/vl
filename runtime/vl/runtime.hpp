// VL runtime: the small library every compiled VL program is built on.
//
// A node is a C++ class derived from vl::Node, with one member per socket
// and setting in its JSON, named after their ids:
//
//     inputs    vl::Input<T>     read with get()
//     outputs   vl::Output<T>    write with set(value)
//     settings  plain members    (assigned before setup())
//
// The generated main() creates the nodes, assigns their values, connects
// outputs to inputs and runs vl::App.
//
// When a node runs: whenever one of its inputs receives a new value, using
// the latest value of every other input, and only once every input has had
// a value. Wires that close a feedback loop don't start a run; they only
// update the stored value, so loops can't run forever.
#pragma once

#include <cstdint>
#include <deque>
#include <memory>
#include <string>
#include <vector>

namespace vl {

class App;
class Node;

// The part of every input the runtime needs to see.
class InputBase {
public:
    bool hasValue() const { return hasValue_; }

protected:
    bool hasValue_ = false;
};

template <typename T>
class Input : public InputBase {
public:
    const T& get() const { return value_; }
    operator const T&() const { return value_; }

    // Called by the runtime (and the generated code for initial values).
    void receive(const T& value) {
        value_ = value;
        hasValue_ = true;
    }

private:
    T value_{};
};

class Node {
public:
    virtual ~Node() = default;

    // Called once, after settings are assigned and before anything runs.
    virtual void setup() {}
    // Called whenever the node runs (see above).
    virtual void process() {}
    // Draw the node's app widget with Dear ImGui. Only called for nodes with
    // an app widget that is shown; wrap the body in #ifdef VL_GUI.
    virtual void drawWidget() {}

protected:
    // Call from setup(): additionally run process() every `seconds`
    // (for sources such as sensors).
    void runEvery(double seconds);
    // Run process() again soon, e.g. after the user changed a widget.
    void requestProcess();

private:
    friend class App;
    template <typename T> friend class Output;

    bool vlReady() const;

    App* vlApp_ = nullptr;
    std::string vlId_;
    std::string vlTitle_;
    std::vector<const InputBase*> vlInputs_;
    bool vlQueued_ = false;
    double vlInterval_ = 0;
    double vlNextRun_ = 0;
    bool vlHasWidget_ = false;
    bool vlWidgetVisible_ = false;
    std::string vlWidgetTitle_;
};

template <typename T>
class Output {
public:
    // Send a value to every connected input.
    void set(const T& value) {
        for (auto& link : links_) {
            link.input->receive(value);
            if (link.triggers)
                link.node->requestProcess();
        }
    }

    Output& operator=(const T& value) {
        set(value);
        return *this;
    }

    // Used by the generated code. Feedback wires have triggers = false.
    void connect(Input<T>& input, Node& node, bool triggers) {
        links_.push_back({&input, &node, triggers});
    }

private:
    struct Link {
        Input<T>* input;
        Node* node;
        bool triggers;
    };
    std::vector<Link> links_;
};

class App {
public:
    // gui: open a window for app widgets (only built with VL_GUI).
    App(std::string name, bool fullscreen, bool gui);

    template <typename N>
    N& add(const std::string& id, const std::string& title) {
        auto node = std::make_unique<N>();
        N& ref = *node;
        ref.vlApp_ = this;
        ref.vlId_ = id;
        ref.vlTitle_ = title;
        nodes_.push_back(std::move(node));
        return ref;
    }

    // Inputs the node needs a value on before it can run.
    void watch(Node& node, const InputBase& input);
    void setWidget(Node& node, bool visible, const std::string& title);

    int run();

private:
    friend class Node;

    void schedule(Node& node);
    void runTimers();
    void processQueue();
    double nextTimer() const;
    int runHeadless();
#ifdef VL_GUI
    int runGui();
    void drawWidgets(float width, float height);
#endif

    std::string name_;
    bool fullscreen_;
    bool gui_;
    std::vector<std::unique_ptr<Node>> nodes_;
    std::deque<Node*> queue_;
};

}  // namespace vl
