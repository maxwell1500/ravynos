add_library(libkmod STATIC c_start.c c_stop.c)
set_property(TARGET libkmod PROPERTY OUTPUT_NAME "kmod")
add_dependencies(libkmod xnu_headers xnu)
target_compile_options(libkmod PRIVATE
     --sysroot=${RAVYN_SDKROOT}
     -I${RAVYN_SDKROOT}/usr/local/include/kernel
     -I${CMAKE_SOURCE_DIR}/Frameworks
     -I${ROOT_SOURCE_DIR}/Frameworks
)
