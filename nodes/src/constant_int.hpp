#pragma once
#include "vl/runtime.hpp"

// Sends its number once at the start.
class ConstantInt : public vl::Node {
public:
    int32_t number = 0;
    vl::Output<int32_t> value;

    void process() override { value.set(number); }
};
