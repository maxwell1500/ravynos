cmake_minimum_required(VERSION 3.15.1)
project(ravynOS)

set(CMAKE_INSTALL_PREFIX "/usr")
set(CMAKE_MACOSX_MIN_VERSION 12.0)

include(ExternalProject)
include(Developer/cmake/asm.cmake)
include(Developer/cmake/bundle_resources.cmake)
include(Developer/cmake/circular.cmake)
include(Developer/cmake/crosscompile.cmake)
include(Developer/cmake/get_target_dependencies.cmake)
include(Developer/cmake/install_helpers.cmake)
include(Developer/cmake/kext.cmake)
include(Developer/cmake/mig.cmake)
include(Developer/cmake/suppress_warnings.cmake)

# Bootstrap our SDK if needed
add_subdirectory(Developer)