#include "lidar_distance.hpp"

void LidarDistance::process() {
    const auto& ranges = scan.get().ranges;
    if (ranges.empty())
        return;
    int deg = ((angle.get() % 360) + 360) % 360;
    int index = deg * static_cast<int>(ranges.size()) / 360;
    distance.set(static_cast<int32_t>(ranges[index] * 1000.0f));
}
