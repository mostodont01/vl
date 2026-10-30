#pragma once
#include <string>
#include "vl/runtime.hpp"
#include "vl/widgets.hpp"

// Shows the last number it received in its app widget.
class ShowNumber : public vl::Node {
public:
    std::string label;
    vl::Input<int32_t> value;

    void process() override {
        shown_ = value.get();
        received_ = true;
    }

#ifdef VL_GUI
    void drawWidget() override {
        if (received_)
            ImGui::Text("%d", shown_);
        else
            ImGui::TextDisabled("waiting...");
    }
#endif

private:
    int32_t shown_ = 0;
    bool received_ = false;
};
