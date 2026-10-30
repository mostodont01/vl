#pragma once
#include "vl/runtime.hpp"
#include "lidar_scan.hpp"

// Distance in millimetres at the given angle (degrees) of a scan.
class LidarDistance : public vl::Node {
public:
    vl::Input<LidarScan> scan;
    vl::Input<int32_t> angle;
    vl::Output<int32_t> distance;

    void process() override;
};
