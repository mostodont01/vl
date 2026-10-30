#pragma once
#include <string>
#include "vl/runtime.hpp"

// result = value <comparison> threshold
class Threshold : public vl::Node {
public:
    std::string comparison = ">=";
    vl::Input<int32_t> value;
    vl::Input<int32_t> threshold;
    vl::Output<bool> result;

    void process() override {
        const int32_t v = value.get();
        const int32_t t = threshold.get();
        bool r;
        if (comparison == ">")
            r = v > t;
        else if (comparison == "<=")
            r = v <= t;
        else if (comparison == "<")
            r = v < t;
        else if (comparison == "==")
            r = v == t;
        else
            r = v >= t;
        result.set(r);
    }
};
