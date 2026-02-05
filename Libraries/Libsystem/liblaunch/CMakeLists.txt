add_library(liblaunch SHARED libbootstrap.c liblaunch.c libvproc.c)

set_target_properties(liblaunch PROPERTIES PREFIX "lib" OUTPUT_NAME "launch"
    SUFFIX ".dylib" NO_SONAME true)

set(CFLAGS --sysroot=${RAVYN_SDKROOT} -g -DPRIVATE -mmacos-version-min=10.15)
set(MIG_FLAGS ${CFLAGS} -D__MigTypeCheck)
target_compile_options(liblaunch PRIVATE ${CFLAGS})
target_compile_definitions(liblaunch PRIVATE _MACH_PORT_T)
target_include_directories(liblaunch PRIVATE
    .
    ../libdispatch/config
    ../libsystem_pthread
    ../private
    ${RAVYN_SDKROOT}/usr/local/include
    ${RAVYN_SDKROOT}/usr/local/include/kernel
    ${RAVYN_SDKROOT}/System/Library/Frameworks/Kernel.framework/Versions/A/PrivateHeaders)

add_custom_target(helperMIG
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/helper.defs
    COMMAND ${MIG} ${MIG_FLAGS} -header helper.h -sheader helperServer.h
        ${CMAKE_CURRENT_SOURCE_DIR}/helper.defs
    BYPRODUCTS helper.h helperServer.h launchd_helperUser.c launchd_helperServer.c
)
add_custom_target(jobMIG
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/job.defs
    COMMAND ${MIG} ${MIG_FLAGS} -sheader jobServer.h
        ${CMAKE_CURRENT_SOURCE_DIR}/job.defs
    BYPRODUCTS jobServer.h jobUser.c job.h
)
target_sources(liblaunch PRIVATE job.h jobServer.h jobUser.c helper.h
    helperServer.h launchd_helperUser.c launchd_helperServer.c)
add_dependencies(liblaunch jobMIG helperMIG)

target_link_options(liblaunch PRIVATE
    -Wl,-current_version,1738.0.17 -Wl,-compatibility_version,1.0.0
    -Wl,-install_name,/usr/lib/system/liblaunch.dylib -umbrella System
    -L${RAVYN_SDKROOT}/usr/lib -mmacos-version-min=10.15)

add_dependencies(liblaunch libsystem_darwin)