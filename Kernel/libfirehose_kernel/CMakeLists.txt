cmake_policy(SET CMP0114 NEW)

set(CMAKE_INSTALL_PREFIX "")
set(CMAKE_MACOSX_MIN_VERSION 11.0)

add_darwin_static_library(libfirehose_kernel)
set_property(TARGET libfirehose_kernel PROPERTY OUTPUT_NAME "firehose_kernel")
target_sources(libfirehose_kernel PRIVATE
    ${CMAKE_SOURCE_DIR}/Libraries/libdispatch/src/firehose/firehose_buffer.c
)
    
target_compile_definitions(libfirehose_kernel PRIVATE
    KERNEL=1 DISPATCH_USE_DTRACE=0 OS_ATOMIC_CONFIG_MEMORY_ORDER_DEPENDENCY=1
    OS_ATOMIC_CONFIG_MEMORY_ORDER_DEPENDENCY=1 OS_ATOMIC_CONFIG_STARVATION_FREE_ONLY=0)

file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/sysroot/usr/include/mach/)
file(COPY ${CMAKE_SOURCE_DIR}/Kernel/xnu/osfmk/mach/vm_statistics.h 
    DESTINATION ${CMAKE_BINARY_DIR}/sysroot/usr/include/mach/)
target_compile_options(libfirehose_kernel PRIVATE -mkernel -Wno-packed
    --sysroot=${CMAKE_BINARY_DIR}/sysroot
    -I${CMAKE_BINARY_DIR}/sysroot/usr/include
    -I${CMAKE_SOURCE_DIR}/Libraries/libdispatch
    -I${CMAKE_SOURCE_DIR}/Libraries/libdispatch/src/firehose
    -I${CMAKE_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/libkern/firehose
    -I${CMAKE_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/libkern
    -I${CMAKE_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk
    -I${CMAKE_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/bsd
    -I${CMAKE_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS
    -I${CMAKE_SOURCE_DIR}/Libraries/libplatform/private/os
    -I${CMAKE_SOURCE_DIR}/Libraries/libpthread
    -Wno-error=implicit-function-declaration -Wno-implicit-function-declaration
    -Wno-sign-conversion
)
add_dependencies(libfirehose_kernel xnu_headers)
target_link_libraries(libfirehose_kernel PRIVATE AvailabilityHeaders xnu_private_headers)
target_link_libraries(libfirehose_kernel PRIVATE xnu_kernel_headers xnu_kernel_private_headers)
target_link_libraries(libfirehose_kernel PRIVATE libplatform_headers libplatform_private_headers)
target_link_libraries(libfirehose_kernel PRIVATE pthread_common_headers pthread_common_private_headers)
