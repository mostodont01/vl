# Cross-compile for 64-bit ARM Linux (Raspberry Pi OS, Jetson...) with Zig,
# which ships the C and C++ libraries for the target. See the zig-* scripts.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER ${CMAKE_CURRENT_LIST_DIR}/zig-aarch64-cc)
set(CMAKE_CXX_COMPILER ${CMAKE_CURRENT_LIST_DIR}/zig-aarch64-c++)
set(CMAKE_AR ${CMAKE_CURRENT_LIST_DIR}/zig-ar CACHE FILEPATH "")
set(CMAKE_RANLIB ${CMAKE_CURRENT_LIST_DIR}/zig-ranlib CACHE FILEPATH "")
# Zig keeps debug info even in release builds; strip it there.
set(CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT "-s")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
