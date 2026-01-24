add_library(libsystem_darwin SHARED)
set_target_properties(libsystem_darwin PROPERTIES 
    OUTPUT_NAME "system_darwin" SUFFIX ".dylib" PREFIX "lib" NO_SONAME true)

target_sources(libsystem_darwin PRIVATE
    bsd.c
    ctl.c
    dirstat.c
    dirstat_collection.c
    err.c
    exception.c
    init.c
    mach.c
    stdio.c
    stdlib.c
    string.c
    variant.c
)

target_include_directories(libsystem_darwin PRIVATE
    ${ROOT_SOURCE_DIR}/Kernel/xnu/bsd

    ../libsystem_c/include ../libsystem_c/locale
    ../libsystem_c/locale/FreeBSD ../libsystem_c/stdtime/FreeBSD
    ../libsystem_c ../liblaunch ../libdispatch/private ../private h ../../openbsm

    ${CMAKE_CURRENT_BINARY_DIR}/../libsystem_kernel/mig_hdr/include
    ${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/wrappers/spawn
    ${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/wrappers/libproc
    ${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/libkern
    ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders
)

target_compile_definitions(libsystem_darwin PRIVATE
    TARGET_OS_BRIDGE=0 __DARWIN_UNIX03 guardid_t=uint64_t
    mach_right_recv_t=mach_port_t mach_right_send_t=mach_port_t
    _COMM_PAGE_ATM_DIAGNOSTIC_CONFIG=0x00007fffffe00048ULL
    _LIBC_NO_FEATURE_VERIFICATION DARWIN_BUILDING_LIBSYSTEM_DARWIN
    OS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE MAC_OS_X_VERSION_MIN_REQUIRED=1150
)

target_compile_options(libsystem_darwin PRIVATE
    --sysroot=${RAVYN_SDKROOT} -isysroot${RAVYN_SDKROOT}
    -include${RAVYN_SDKROOT}/usr/include/os/availability.h
    -include${CMAKE_CURRENT_SOURCE_DIR}/../../openbsm/sys/bsm/audit.h
    -Wno-implicit-function-declaration -Wno-nullability-completeness
    -Wno-int-conversion -Wno-implicit-int
    $<$<COMPILE_LANGUAGE:ASM>:-x assembler-with-cpp>
)

target_link_options(libsystem_darwin PRIVATE
    --target=${CpuArch}-apple-darwin
    -mmacos-version-min=10.15 -flat_namespace -undefined warning
    -rdynamic -nostdlib -nodefaultlibs
    -Wl,-syslibroot,${RAVYN_SDKROOT} -Wl,-search_paths_first
    -Wl,-install_name,/usr/lib/system/libsystem_darwin.dylib
    -Wl,-all_load -L${RAVYN_SDKROOT}/usr/lib/system -umbrella System
    -lsystem_kernel -L${CMAKE_CURRENT_BINARY_DIR}/../../dyld -ldyld
    -lsystem_malloc -lsystem_platform -lsystem_pthread -lsystem_c
    -lunwind -ldyld # -lm -ldispatch -lxpc
)

file(GLOB darwinpvthdrs h/*.h)
file(COPY ${darwinpvthdrs} DESTINATION ${RAVYN_SDKROOT}/usr/local/include/os/)
file(COPY AppleFactoryVariant.plist AppleInternalVariant.plist
    DESTINATION ${RAVYN_SDKROOT}/System/Library/CoreServices/)

install(FILES AppleFactoryVariant.plist AppleInternalVariant.plist
    DESTINATION ${SYSROOT_DIR}/System/Library/CoreServices/)
