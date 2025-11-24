cmake_minimum_required(VERSION 3.15.1)
project(ravynOS)

# ------------------------------------------------------------------------
#                        PRODUCT VERSION KNOBS
# ------------------------------------------------------------------------
set(PROD_VERSION 0.6.1)
set(PROD_FAMILY "Hyperpop Hyena")

set(CMAKE_MACOSX_MIN_VERSION 12.0)

# ------------------------------------------------------------------------

set(CMAKE_INSTALL_PREFIX "/usr")

set(RAVYN_SDKROOT ${CMAKE_BINARY_DIR}/Developer/Platforms/ravynOS.platform/Developer/SDKs/ravynOS.sdk)
set(TOOLCHAIN ${CMAKE_BINARY_DIR}/Developer/Toolchains/Default.xctoolchain)
set(RUNTIME_SPEC_PATH ${CMAKE_SOURCE_DIR}/Developer/xcbuild/Specifications)

if("${GMAKE}" STREQUAL "")
    if(CMAKE_HOST_BSD)
        set(GMAKE gmake)
        set(BMAKE make)
    else()
        set(GMAKE make)
        set(BMAKE bmake)
    endif()
endif()

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

if($ENV{CI})
    execute_process(OUTPUT_VARIABLE BUILD_STAMP
        COMMAND /bin/sh -c "echo ${CIRRUS_CHANGE_IN_REPO}|cut -c1-7|tr '[a-z]' '[A-Z]'"
    )
else()
    execute_process(OUTPUT_VARIABLE BUILD_STAMP
        COMMAND /bin/sh -c "cd ${CMAKE_SOURCE_DIR} && git log -1|head -1|cut -c8-14|tr '[a-z]' '[A-Z]'"
    )
endif()


# Bootstrap our SDK if needed
add_subdirectory(Developer)

add_subdirectory(Libraries)
add_subdirectory(Kernel)

string(STRIP "${BUILD_STAMP}" BUILD_STAMP)
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/sysroot/System/Library/CoreServices")
configure_file(${CMAKE_SOURCE_DIR}/SystemLibrary/SystemVersion.plist.in
    ${CMAKE_BINARY_DIR}/sysroot/System/Library/CoreServices/SystemVersion.plist
    @ONLY
)
