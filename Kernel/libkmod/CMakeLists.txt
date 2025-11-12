cmake_minimum_required(VERSION 3.15.1)
project(Kernel)

cmake_policy(SET CMP0114 NEW)

set(CMAKE_INSTALL_PREFIX "")
set(CMAKE_MACOSX_MIN_VERSION 11.0)

include(ExternalProject)
include(${SRCTOP}/contrib/cmake/asm.cmake)
include(${SRCTOP}/contrib/cmake/bundle_resources.cmake)
include(${SRCTOP}/contrib/cmake/circular.cmake)
include(${SRCTOP}/contrib/cmake/crosscompile.cmake)
include(${SRCTOP}/contrib/cmake/get_target_dependencies.cmake)
include(${SRCTOP}/contrib/cmake/install_helpers.cmake)
include(${SRCTOP}/contrib/cmake/kext.cmake)
include(${SRCTOP}/contrib/cmake/mig.cmake)
include(${SRCTOP}/contrib/cmake/suppress_warnings.cmake)

add_darwin_static_library(libkmod)
set_property(TARGET libkmod PROPERTY OUTPUT_NAME "kmod")
target_sources(libkmod PRIVATE c_start.c c_stop.c)
target_link_libraries(libkmod PRIVATE xnu_kernel_headers AvailabilityHeaders
    xnu_private_headers xnu_kernel_private_headers)
target_compile_definitions(libkmod PRIVATE TARGET_OS_OSX)
target_compile_options(libkmod PRIVATE
     -I${SRCTOP}/Kernel/xnu/EXTERNAL_HEADERS
     -I${OBJTOP}/release/usr/include
     -I${OBJTOP}/Kernel/xnu/EXPORT_HDRS/libkern
     -I${OBJTOP}/Kernel/xnu/EXPORT_HDRS/osfmk
     -I${SRCTOP}/Libraries/Libc/include
     -I${SRCTOP}/Libraries/Libc/locale
     -I${SRCTOP}/Libraries/Libc/darwin
     -I${SRCTOP}/Libraries/libpthread
     -I${SRCTOP}/Libraries/libpthread/pthread
     -I${SRCTOP}/Libraries/libpthread/private
     -I${OBJTOP}/Kernel/libkmod/include
     -I${SRCTOP}/Kernel/xnu/libsyscall
     -I${SRCTOP}/Kernel/xnu/libsyscall/mach
     -I${SRCTOP}/Kernel/xnu/libsyscall/wrappers
     -I${SRCTOP}/Libraries/libmalloc/include
     -I${SRCTOP}/Libraries/libplatform/include
     -I${SRCTOP}/Libraries/libdispatch/src/BlocksRuntime
     -I${SRCTOP}/Libraries/libdispatch
     -I${OBJTOP}/tmp/obj-tools/usr/include/c++/v1
     -I${SRCTOP}/Frameworks
     -F${OBJTOP}/release/System/Library/Frameworks)
# cplus_start.c and cplus_stop.c are empty, thus no libkmodc++.
