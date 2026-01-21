add_library(libsystem_pthread SHARED)
set_target_properties(libsystem_pthread PROPERTIES
    OUTPUT_NAME "system_pthread" SUFFIX ".dylib" PREFIX "lib" NO_SONAME true
    MACHO_CURRENT_VERSION 416.0.6)


add_library(libpthread_dyld STATIC)
set_target_properties(libpthread_dyld PROPERTIES
    OUTPUT_NAME "pthread_dyld" PREFIX "lib")

set(libpthread_sources
    pthread.c pthread_asm.s pthread_atfork.c pthread_cancelable.c
    pthread_cond.c pthread_cwd.c pthread_dependency.c pthread_mutex.c
    pthread_rwlock.c pthread_tsd.c qos.c resolver/resolver.c
    variants/pthread_cancelable_cancel.c variants/pthread_cancelable_legacy.c
    variants/pthread_cond_legacy.c variants/pthread_mutex_legacy.c
    variants/pthread_rwlock_legacy.c
)
set(libpthread_incs
    ${SDK_SOURCE_DIR}/usr/include
    ${SDK_SOURCE_DIR}/usr/local/include/pthread
    ${SDK_SOURCE_DIR}/usr/local/include
    ../private/pthread ../private .. resolver ../libsystem_c/darwin
    ../../../Kernel/xnu/libsyscall/mach
    ../../../Kernel/xnu/libsyscall/wrappers/spawn
    ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders
    ${SDK_SOURCE_DIR}/usr/include/pthread
    ${RAVYN_SDKROOT}/System/Library/Frameworks/Kernel.framework/Versions/A/Headers
    ../../../Kernel/Extensions/pthread
)
set(libpthread_defs
    DISPATCH_USE_DTRACE=0 __LIBC__ __DARWIN_UNIX03 __DARWIN_64_BIT_INO_T
    __DARWIN_NON_CANCELABLE __DARWIN_VERS_1050 _FORTIFY_SOURCE=0
    __PTHREAD_BUILDING_PTHREAD__ __PTHREAD_EXPOSE_INTERNALS__
    memory_order_dependency=os_atomic_memory_order_dependency
    memory_order_acquire=os_atomic_memory_order_acquire
    memory_order_release=os_atomic_memory_order_release
    memory_order_relaxed=os_atomic_memory_order_relaxed
    OS_ATOMIC_CONFIG_MEMORY_ORDER_DEPENDENCY=1
)
set(libpthread_opts
    --target=${TARGET_TRIPLE} -w
    --sysroot=${RAVYN_SDKROOT} -isysroot=${RAVYN_SDKROOT}
    -isystem ${RAVYN_SDKROOT}/usr/include
    -isystem ${RAVYN_SDKROOT}/usr/local/include
    -iframework ${RAVYN_SDKROOT}/System/Library/Frameworks
    -Wno-implicit-function-declaration
    -Wno-int-conversion -Wno-implicit-int
    -fno-stack-protector -fno-stack-check -fno-builtin
    -momit-leaf-frame-pointer
    $<$<COMPILE_LANGUAGE:ASM>:-x assembler-with-cpp>
)

target_sources(libsystem_pthread PRIVATE ${libpthread_sources})
target_include_directories(libsystem_pthread PRIVATE ${libpthread_incs})
target_compile_definitions(libsystem_pthread PRIVATE ${libpthread_defs})
target_compile_options(libsystem_pthread PRIVATE ${libpthread_opts})

target_sources(libpthread_dyld PRIVATE ${libpthread_sources})
target_include_directories(libpthread_dyld PRIVATE ${libpthread_incs})
target_compile_definitions(libpthread_dyld PRIVATE ${libpthread_defs}
    VARIANT_DYLD VARIANT_STATIC)
target_compile_options(libpthread_dyld PRIVATE ${libpthread_opts})

target_link_options(libsystem_pthread PRIVATE
    --sysroot=${RAVYN_SDKROOT} -isysroot=${RAVYN_SDKROOT}
    -mmacos-version-min=10.15
    -Wl,-install_name,/usr/lib/system/libsystem_pthread.dylib
    -rdynamic -nodefaultlibs -Wl,-search_paths_first -undefined warning
    -all_load -L${RAVYN_SDKROOT}/usr/lib/system -umbrella System
    -L${CMAKE_CURRENT_BINARY_DIR}/../../dyld -ldyld
    -L${CMAKE_CURRENT_BINARY_DIR}/../libsystem_platform -lplatform
    -L${CMAKE_CURRENT_BINARY_DIR}/../libsystem_c -lsystem_c
    -L${CMAKE_CURRENT_BINARY_DIR}/../libsystem_kernel -lsystem_kernel
    -lcompiler_rt -lc++ -lc++abi -lunwind
    -Wl,-dirty_data_list,${CMAKE_CURRENT_SOURCE_DIR}/xcodescripts/pthread.dirty
    -Wl,-alias_list,${CMAKE_CURRENT_SOURCE_DIR}/xcodescripts/pthread.aliases
)
