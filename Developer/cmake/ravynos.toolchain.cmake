# CMake Toolchain file for cross-compiling software to ravynOS (x86_64-apple-darwin24).
# Usage:
#   cmake -S <src> -B <build> -DCMAKE_TOOLCHAIN_FILE=<repo>/Developer/cmake/ravynos.toolchain.cmake

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_VERSION 24.0.0)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_OSX_ARCHITECTURES "x86_64" CACHE STRING "Target architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Deployment target" FORCE)

get_filename_component(_RAVYN_REPO "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
if(DEFINED ENV{RAVYN_SDKROOT} AND EXISTS "$ENV{RAVYN_SDKROOT}")
    set(RAVYN_SDKROOT "$ENV{RAVYN_SDKROOT}" CACHE PATH "ravynOS SDK root" FORCE)
else()
    set(RAVYN_SDKROOT "${_RAVYN_REPO}/Developer/ravynOS.sdk" CACHE PATH "ravynOS SDK root" FORCE)
endif()

set(CMAKE_SYSROOT "${RAVYN_SDKROOT}")
set(CMAKE_OSX_SYSROOT "${RAVYN_SDKROOT}" CACHE PATH "macOS/ravynOS sysroot" FORCE)

set(CMAKE_C_COMPILER "${_RAVYN_REPO}/tools/sdk/bin/ravynos-cc" CACHE FILEPATH "C compiler" FORCE)
set(CMAKE_CXX_COMPILER "${_RAVYN_REPO}/tools/sdk/bin/ravynos-c++" CACHE FILEPATH "C++ compiler" FORCE)
set(CMAKE_OBJC_COMPILER "${_RAVYN_REPO}/tools/sdk/bin/ravynos-cc" CACHE FILEPATH "ObjC compiler" FORCE)
set(CMAKE_OBJCXX_COMPILER "${_RAVYN_REPO}/tools/sdk/bin/ravynos-c++" CACHE FILEPATH "ObjC++ compiler" FORCE)

set(PKG_CONFIG_EXECUTABLE "${_RAVYN_REPO}/tools/sdk/bin/ravynos-pkg-config" CACHE FILEPATH "pkg-config" FORCE)
set(SDL2_CONFIG "${_RAVYN_REPO}/tools/sdk/bin/sdl2-config" CACHE FILEPATH "sdl2-config" FORCE)

set(CMAKE_FIND_ROOT_PATH
    "${RAVYN_SDKROOT}"
    "${RAVYN_SDKROOT}/usr"
    "${RAVYN_SDKROOT}/System/Library/Frameworks"
)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
