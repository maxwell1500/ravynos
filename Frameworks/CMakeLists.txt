# ------------------------------------------------------------------------
#  RAVYNOS BUILD SYSTEM - Frameworks
# ------------------------------------------------------------------------

cmake_minimum_required(VERSION 4.0.0)
project(Libraries LANGUAGES C CXX ASM)

include(${ROOT_SOURCE_DIR}/Developer/cmake/Version.cmake)
include(${ROOT_SOURCE_DIR}/Developer/cmake/Paths.cmake)
include(${ROOT_SOURCE_DIR}/Developer/cmake/Tools.cmake)

set(ENV{DERIVED_DATA_DIR} ${CMAKE_CURRENT_BINARY_DIR})

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_C_COMPILER ${CC})
set(CMAKE_ASM_COMPILER ${CC})
set(CMAKE_CXX_COMPILER ${CXX})
set(CMAKE_LINK_DEPENDS_USE_LINKER OFF)

add_custom_target(BUILD_PHASE_FRAMEWORKS)
add_dependencies(BUILD_PHASE_FRAMEWORKS libSystem)

add_subdirectory(Foundation)