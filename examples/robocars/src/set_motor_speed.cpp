#include "set_motor_speed.hpp"

#include <cstdio>

void SetMotorSpeed::process() {
    // TODO: talk to the real motor controller.
    std::printf("[motor] speed %d\n", speed.get());
}
