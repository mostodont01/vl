#pragma once
#include <vector>

// One LiDAR revolution: ranges[i] is the distance in metres at i degrees.
struct LidarScan {
    std::vector<float> ranges;
};
