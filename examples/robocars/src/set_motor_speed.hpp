#pragma once
#include "vl/runtime.hpp"

// Sends a speed to the drive controller.
class SetMotorSpeed : public vl::Node {
public:
    vl::Input<int32_t> speed;

    void process() override;
};
