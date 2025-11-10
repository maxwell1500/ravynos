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
     -I${OBJTOP}/Kernel/xnu/xnu_header_build/src/xnu_headers.extproj-build/EXPORT_HDRS/osfmk
     -I${OBJTOP}/Kernel/xnu/usr/include
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
