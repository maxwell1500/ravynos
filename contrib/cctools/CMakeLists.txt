cmake_minimum_required(VERSION 3.15.1)
project(ravynOS)

cmake_policy(SET CMP0114 NEW)

set(CMAKE_INSTALL_PREFIX "")
set(CMAKE_MACOSX_MIN_VERSION 11.0)

include(ExternalProject)
include(../cmake/asm.cmake)
include(../cmake/bundle_resources.cmake)
include(../cmake/circular.cmake)
include(../cmake/crosscompile.cmake)
include(../cmake/get_target_dependencies.cmake)
include(../cmake/install_helpers.cmake)
include(../cmake/kext.cmake)
include(../cmake/mig.cmake)
include(../cmake/suppress_warnings.cmake)

add_subdirectory(libmacho)
add_subdirectory(libstuff)
add_subdirectory(misc)
# add_subdirectory(otool) # disabled - doesn't build
#add_subdirectory(ld64/src) # we use LLVM's ld64.lld
