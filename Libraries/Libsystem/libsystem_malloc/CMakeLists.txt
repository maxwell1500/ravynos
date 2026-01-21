add_library(libsystem_malloc SHARED)
set_target_properties(libsystem_malloc PROPERTIES
    OUTPUT_NAME "system_malloc" SUFFIX ".dylib" PREFIX "lib" NO_SONAME true
    MACHO_CURRENT_VERSION 283)

add_library(libmalloc STATIC)
set_target_properties(libmalloc PROPERTIES
    OUTPUT_NAME "malloc" PREFIX "lib")

set(libmalloc_sources
    bitarray.c empty.s frozen_malloc.c legacy_malloc.c
    magazine_large.c magazine_malloc.c magazine_medium.c
    magazine_rack.c magazine_small.c magazine_tiny.c
    malloc_common.c malloc_printf.c malloc.c nano_malloc.c
    msl_lite_support.c nano_malloc_common.c nanov2_malloc.c
    purgeable_malloc.c vm.c resolver/resolver.c
)
set(libmalloc_incs
    ${SDK_SOURCE_DIR}/usr/include
    ../../../Kernel/xnu/EXTERNAL_HEADERS
    ../private internal resolver
    ../libsystem_c/darwin
    ../../../Kernel/xnu/libsyscall/mach
    ../libsystem_c/gen
    ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders
    ${RAVYN_SDKROOT}/System/Library/Frameworks/Kernel.framework/Versions/A/Headers
)
set(libmalloc_defs
    DISPATCH_USE_DTRACE=0 OSATOMIC_DEPRECATED=0 OSATOMIC_USE_INLINED=0
    OS_UNFAIR_LOCK_INLINE=0 _FORTIFY_SOURCE=0 NDEBUG
)
set(libmalloc_opts
    --sysroot=${RAVYN_SDKROOT} -isysroot=${RAVYN_SDKROOT} -w
    --target=${TARGET_TRIPLE} -F${RAVYN_SDKROOT}/System/Library/Frameworks
    -Wno-implicit-function-declaration -momit-leaf-frame-pointer
    -Wno-int-conversion -Wno-implicit-int
    $<$<COMPILE_LANGUAGE:ASM>:-x assembler-with-cpp>
)

target_sources(libsystem_malloc PRIVATE ${libmalloc_sources})
target_include_directories(libsystem_malloc PRIVATE ${libmalloc_incs})
target_compile_definitions(libsystem_malloc PRIVATE ${libmalloc_defs})
target_compile_options(libsystem_malloc PRIVATE ${libmalloc_opts})

target_sources(libmalloc PRIVATE ${libmalloc_sources})
target_include_directories(libmalloc PRIVATE ${libmalloc_incs})
target_compile_definitions(libmalloc PRIVATE ${libmalloc_defs})
target_compile_options(libmalloc PRIVATE ${libmalloc_opts})

target_link_options(libsystem_malloc PRIVATE
    -mmacos-version-min=10.15 -undefined warning
    -Wl,-install_name,/usr/lib/system/libsystem_malloc.dylib
    -rdynamic -nodefaultlibs -Wl,-search_paths_first -all_load
    -L${RAVYN_SDKROOT}/usr/lib/system -umbrella System
    #-lCrashReporterClient -lcompiler-rt
    -lsystem_platform -Wl,-upward-lsystem_c
    -Wl,-interposable_list,${CMAKE_CURRENT_SOURCE_DIR}/xcodeconfig/interposable.list
)
