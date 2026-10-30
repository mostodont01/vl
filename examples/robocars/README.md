# RoboCars example nodes

Nodes for the RoboCars robot. They are not built into VL: import them into a
project with **File → Import Node…** and pick one of the `.json` files. Each
JSON lists its code files (`"code"`), which are copied into the project.

The C++ files use the VL runtime interface (see runtime/vl/runtime.hpp). The
LiDAR is simulated and the motor only prints, until real drivers are written.
