add_library(libxpc SHARED)
target_sources(libxpc PRIVATE
    mpack.c
    xpc_array.c
    xpc_connection.c
    xpc_dictionary.c
    xpc_misc.c
    xpc_type.c
    transports/unix.c
    transports/mach.c
)

target_sources(libxpc INTERFACE
    activity.h
    base.h
    connection.h
    debug.h
    endpoint.h
    launchd.h
    xpc.h
)

target_compile_definitions(libxpc PRIVATE XPC_DEBUG MACH __APPLE__)
target_compile_options(libxpc PRIVATE -g -O0 -fblocks --sysroot=${RAVYN_SDKROOT})
target_include_directories(libxpc PRIVATE
    .
    ../liblaunch
    ${RAVYN_SDKROOT}/usr/local/include
    ${RAVYN_SDKROOT}/usr/local/include/kernel
)
add_dependencies(libxpc libsystem_darwin)
