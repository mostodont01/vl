#pragma once
#include "vl/runtime.hpp"

// result = a + b
class Add : public vl::Node {
public:
    vl::Input<int32_t> a;
    vl::Input<int32_t> b;
    vl::Output<int32_t> result;

    void process() override { result.set(a.get() + b.get()); }
};
