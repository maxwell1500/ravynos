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

add_darwin_static_library(libfirehose_kernel)
set_property(TARGET libfirehose_kernel PROPERTY OUTPUT_NAME "firehose_kernel")
target_sources(libfirehose_kernel PRIVATE
    ${SRCTOP}/Libraries/libdispatch/src/firehose/firehose_buffer.c
)

target_include_directories(libfirehose_kernel PUBLIC
    ${SRCTOP}/Libraries/libdispatch/src/firehose/include)
target_compile_definitions(libfirehose_kernel PRIVATE
    KERNEL=1 DISPATCH_USE_DTRACE=0 OS_ATOMIC_CONFIG_MEMORY_ORDER_DEPENDENCY=1
    OS_ATOMIC_CONFIG_MEMORY_ORDER_DEPENDENCY=1 OS_ATOMIC_CONFIG_STARVATION_FREE_ONLY=0)
target_compile_options(libfirehose_kernel PRIVATE -mkernel -Wno-packed
     -I${OBJTOP}/Kernel/xnu/EXPORT_HDRS/osfmk
     -I${OBJTOP}/release/usr/include
     -I${SRCTOP}/Kernel/xnu/libkern/firehose -I${SRCTOP}/Kernel/xnu/libkern
     -I${SRCTOP}/Libraries/libpthread -I${SRCTOP}/Kernel/xnu/EXTERNAL_HEADERS
     -I${SRCTOP}/Libraries/libplatform/private/os
     -I${SRCTOP}/Libraries/libdispatch
    -Wno-error=implicit-function-declaration -Wno-implicit-function-declaration)
target_link_libraries(libfirehose_kernel PRIVATE AvailabilityHeaders xnu_private_headers)
target_link_libraries(libfirehose_kernel PRIVATE xnu_kernel_headers xnu_kernel_private_headers)
target_link_libraries(libfirehose_kernel PRIVATE libplatform_headers libplatform_private_headers)
target_link_libraries(libfirehose_kernel PRIVATE pthread_common_headers pthread_common_private_headers)
