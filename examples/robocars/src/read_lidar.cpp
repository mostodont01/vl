#include "read_lidar.hpp"

#include <cmath>

void ReadLidar::setup() {
    runEvery(1.0 / frequency);
}

void ReadLidar::process() {
    // TODO: read from the real sensor. Until then: a simulated room whose
    // walls slowly move, so downstream nodes get changing data.
    LidarScan s;
    s.ranges.resize(360);
    for (int deg = 0; deg < 360; ++deg)
        s.ranges[deg] = 2.0f + std::sin((deg + frame_) * 3.14159f / 180.0f);
    ++frame_;
    scan.set(s);
}
