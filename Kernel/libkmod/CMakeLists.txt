cmake_policy(SET CMP0114 NEW)

set(CMAKE_INSTALL_PREFIX "")

add_darwin_static_library(libkmod)
set_property(TARGET libkmod PROPERTY OUTPUT_NAME "kmod")
add_dependencies(libkmod xnu)
target_sources(libkmod PRIVATE c_start.c c_stop.c)
#target_link_libraries(libkmod PRIVATE xnu_kernel_headers AvailabilityHeaders
#    xnu_private_headers xnu_kernel_private_headers)
target_compile_options(libkmod PRIVATE
     -F${CMAKE_BINARY_DIR}/sysroot/System/Library/Frameworks
     -I${CMAKE_BINARY_DIR}/sysroot/System/Library/Frameworks/Kernel.framework/Headers
     -I${CMAKE_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS
     -I${CMAKE_SOURCE_DIR}/Frameworks
)
# cplus_start.c and cplus_stop.c are empty, thus no libkmodc++.
