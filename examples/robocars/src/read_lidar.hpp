#pragma once
#include "vl/runtime.hpp"
#include "lidar_scan.hpp"

// Produces a LiDAR scan `frequency` times per second.
class ReadLidar : public vl::Node {
public:
    float frequency = 10;
    vl::Output<LidarScan> scan;

    void setup() override;
    void process() override;

private:
    int frame_ = 0;
};
