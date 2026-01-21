add_library(libSystem SHARED)
target_sources(libSystem PRIVATE init.c CompatibilityHacks.c)
set_target_properties(libSystem PROPERTIES
    OUTPUT_NAME "System.B" SUFFIX ".dylib" PREFIX "lib" NO_SONAME true
    MACHO_COMPATIBILITY_VERSION 1.0.0
    MACHO_CURRENT_VERSION 1281)

# Library versions within libsystem were taken from Mavericks System.tbd
# libcache.dylib 83
# libcommonCrypto.dylib 60165
# libcompiler_rt.dylib 101.2
# libcorecrypto.dylib 866.0.10
# libdispatch.dylib 1173.0.3
# libdyld.dylib 732.2
# libkeymgr.dylib 30
# liblaunch.dylib 1738.0.17
# libmacho.dylib 949.0.1
# libquarantine.dylib 110.0.3
# libremovefile.dylib 48
# libsystem_asl.dylib 377.0.1
# libsystem_blocks.dylib 74
# libsystem_c.dylib 1353.0.10
# libsystem_configuration.dylib 1061.0.2
# libsystem_coreservices.dylib 114
# libsystem_dnssd.dylib 1096.0.2
# libsystem_featureflags.dylib 17
# libsystem_kernel.dylib 6153.0.168
# libsystem_m.dylib 3178
# libsystem_malloc.dylib 283
# libsystem_notify.dylib 241
# libsystem_platform.dylib 220
# libsystem_pthread.dylib 416.0.6
# libsystem_sandbox.dylib 1217.0.27
# libsystem_secinit.dylib 62.0.2
# libsystem_trace.dylib 1147.0.3
# libunwind.dylib 35.4
# libxpc.dylib 1738.0.17
# libSystem.B.dylib 1281

add_subdirectory(libsystem_blocks)
add_subdirectory(libsystem_kernel)
add_subdirectory(libsystem_platform)
add_subdirectory(libsystem_malloc)
add_subdirectory(libsystem_pthread)
#add_subdirectory(libsystem_notify)
add_subdirectory(libsystem_c)
add_subdirectory(libsystem_darwin)
#add_subdirectory(CommonCrypto)

target_include_directories(libSystem PRIVATE
    libsystem_c/darwin ../../Kernel/xnu/EXTERNAL_HEADERS
    ${RAVYN_SDKROOT}/usr/include/pthread private
    ../../Kernel/xnu/bsd ../../Kernel/xnu/libsyscall/mach
    ../../Kernel/xnu/libsyscall/wrappers
    ${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk
)

target_compile_definitions(libSystem PRIVATE
    __DARWIN_UNIX03 DYLD_MACOSX_VERSION_10_11=0x000A0B00
)

target_compile_options(libSystem PRIVATE
    --sysroot=${RAVYN_SDKROOT} -isysroot=${RAVYN_SDKROOT} -w
    --target=${TARGET_TRIPLE} -isystem ${RAVYN_SDKROOT}/usr/include
    -iframework ${RAVYN_SDKROOT}/System/Library/Frameworks
    -Wno-implicit-function-declaration
    -Wno-int-conversion -Wno-implicit-int
    $<$<COMPILE_LANGUAGE:ASM>:-x assembler-with-cpp>
)

add_dependencies(libsystem_c libsystem_malloc libsystem_platform)
#add_dependencies(libsystem_pthread libsystem_platform)
#add_dependencies(libsystem_malloc libsystem_platform)
#add_dependencies(libsystem_platform compiler_rt)
#add_dependencies(libsystem_notify xnu_headers)
#add_dependencies(libcommonCrypto xnu_headers)
add_dependencies(libSystem 
    libsystem_c libsystem_malloc libsystem_pthread libsystem_platform
    #libsystem_notify libcommonCrypto
)

target_link_options(libSystem PRIVATE
    -mmacos-version-min=10.15 -undefined warning
    -rdynamic -nodefaultlibs -Wl,-search_paths_first -Wl,-reexport-lsystem_c
    -Wl,-reexport-lsystem_malloc -Wl,-reexport-lsystem_platform -Wl,-reexport-lsystem_pthread
)
