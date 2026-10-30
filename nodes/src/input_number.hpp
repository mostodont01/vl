#pragma once
#include <string>
#include "vl/runtime.hpp"
#include "vl/widgets.hpp"

// A number the user can change in the app widget. Sends the initial value
// at the start and every changed value after that.
class InputNumber : public vl::Node {
public:
    std::string label;
    int32_t initial = 0;
    vl::Output<int32_t> value;

    void setup() override { current_ = initial; }
    void process() override { value.set(current_); }

#ifdef VL_GUI
    void drawWidget() override {
        int v = current_;
        ImGui::SetNextItemWidth(-1);
        if (ImGui::InputInt("##value", &v)) {
            current_ = v;
            requestProcess();
        }
    }
#endif

private:
    int32_t current_ = 0;
};
