#pragma once
#include "vl/runtime.hpp"

// Passes the speed through while active; sends 0 otherwise.
class SafetyGate : public vl::Node {
public:
    vl::Input<bool> active;
    vl::Input<int32_t> speed_in;
    vl::Output<int32_t> speed_out;

    void process() override { speed_out.set(active.get() ? speed_in.get() : 0); }
};
