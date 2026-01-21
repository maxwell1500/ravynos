# ------------------------------------------------------------------------
#  RAVYNOS BUILD SYSTEM - Darwin Base System
# ------------------------------------------------------------------------

cmake_minimum_required(VERSION 4.0.0)
project(Libraries LANGUAGES C CXX ASM)

include(${ROOT_SOURCE_DIR}/Developer/cmake/Version.cmake)
include(${ROOT_SOURCE_DIR}/Developer/cmake/Paths.cmake)
include(${ROOT_SOURCE_DIR}/Developer/cmake/Tools.cmake)

set(ENV{DERIVED_DATA_DIR} ${CMAKE_CURRENT_BINARY_DIR})

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_C_COMPILER ${CC})
set(CMAKE_ASM_COMPILER ${CC})
set(CMAKE_CXX_COMPILER ${CXX})
set(CMAKE_LINK_DEPENDS_USE_LINKER OFF)

add_subdirectory(libfirehose_kernel)
add_subdirectory(dyld)
add_subdirectory(Libsystem)

# ------------------------------------------------------------------------
#                  LLVM BUILTINS AND RUNTIME
# ------------------------------------------------------------------------

set(RUNTIME_FLAGS
    "-target ${CpuArch}-apple-darwin -isysroot${RAVYN_SDKROOT_MACOSX} \
    -nostdinc -nobuiltininc --sysroot=${RAVYN_SDKROOT_MACOSX} \
    -I${RAVYN_SDKROOT_MACOSX}/usr/include/c++/v1 \
    -I${RAVYN_SDKROOT_MACOSX}/usr/include \
    -I${RAVYN_SDKROOT_MACOSX}/usr/local/include \
    -I${RAVYN_SDKROOT_MACOSX}/usr/local/include/kernel \
    -I../../Libsystem/private \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/mach \
    -I${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
    -Wno-incompatible-sysroot -Wno-user-defined-literals \
    -Wno-nullability-completeness -Wno-expansion-to-defined \
    -Wno-unused-command-line-argument \
    -mmacosx-version-min=10.13"
)
ExternalProject_Add(runtime DEPENDS xnu_headers
    SOURCE_DIR ${DEVEL}/Default.xctoolchain/llvm/compiler-rt
    BINARY_DIR llvm_target/compiler-rt
    USES_TERMINAL_BUILD
    CONFIGURE_ENVIRONMENT_MODIFIFCATION
        PATH=path_list_prepend:${TOOLS}
        DEVELOPER_DIR=set:${ROOT_BINARY_DIR}/Developer
        SDKROOT=set:${RAVYN_SDKROOT_MACOSX}
    CMAKE_ARGS -Wno-dev
        -C${DEVEL}/Default.xctoolchain/llvm/compiler-rt/cmake/caches/Apple.cmake
        -DROOT_SOURCE_DIR=${ROOT_SOURCE_DIR} -DDEVEL=${DEVEL}
        -DROOT_BINARY_DIR=${ROOT_BINARY_DIR}
        -DCMAKE_C_FLAGS=${RUNTIME_FLAGS} -DCMAKE_CXX_FLAGS=${RUNTIME_FLAGS}
        -DCMAKE_C_COMPILER=${CC} -DCMAKE_CXX_COMPILER=${CXX}
        -DCMAKE_ASM_COMPILER_TARGET=${CpuArch}-apple-darwin
        -DCMAKE_C_COMPILER_TARGET=${CpuArch}-apple-darwin
        -DCMAKE_CXX_COMPILER_TARGET=${CpuArch}-apple-darwin
        -DCMAKE_INSTALL_PREFIX=${RAVYN_SDKROOT}/usr
        -DCMAKE_SYSROOT=${RAVYN_SDKROOT_MACOSX}
        -DCMAKE_BUILD_TYPE=Release
        -DLLVM_TARGETS_TO_BUILD=${BuildArch}
        -DLLVM_ENABLE_RUNTIMES=compiler-rt   #builtins$<SEMICOLON>
        -DLLVM_RUNTIME_TARGETS=${CpuArch}-apple-darwin
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_BUILD_CRT=OFF
        -DLLVM_USE_LINKER=lld
        -DCOMPILER_RT_BUILD_BUILTINS=ON -DCOMPILER_RT_BUILD_SANITIZERS=OFF
        -DCOMPILER_RT_BUILD_PROFILE=ON -DCOMPILER_RT_BUILD_XRAY=OFF
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_MEMPROF=OFF
        -DCOMPILER_RT_BUILD_ORC=OFF
        -DCOMPILER_RT_EXTERNALIZE_DEBUGINFO=OFF
)

# ------------------------------------------------------------------------
#                           LIBUNWIND
# ------------------------------------------------------------------------

set(LIBUNWIND_FLAGS
    "-target ${CpuArch}-apple-darwin -isysroot${RAVYN_SDKROOT} \
    -isystem${SDK_SOURCE_DIR}/usr/include/c++/v1 \
    -isystem${RAVYN_SDKROOT}/usr/include \
    -I${SDK_SOURCE_DIR}/usr/include/c++/v1 -I${SDK_SOURCE_DIR}/usr/include \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/darwin \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/locale \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/locale/FreeBSD \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/stdtime/FreeBSD \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/private \
    -I${RAVYN_SDKROOT}/usr/include/pthread \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/mach \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
    -I${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
    -Wno-incompatible-sysroot -Wno-user-defined-literals \
    -Wno-nullability-completeness -Wno-expansion-to-defined \
    -mmacosx-version-min=10.15"
)

ExternalProject_Add(libunwind DEPENDS xnu_headers runtime
    SOURCE_DIR ${DEVEL}/Default.xctoolchain/llvm/runtimes
    BINARY_DIR llvm_target/libunwind
    USES_TERMINAL_BUILD
    CMAKE_ARGS -Wno-dev
        "-DCMAKE_C_FLAGS=${LIBUNWIND_FLAGS}"
        "-DCMAKE_CXX_FLAGS=${LIBUNWIND_FLAGS}"
        -DCMAKE_SYSROOT=${RAVYN_SDKROOT} -DCMAKE_SYSTEM_NAME=Darwin
        -DCMAKE_C_COMPILER=${CC} -DCMAKE_CXX_COMPILER=${CXX}
        -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON
        -DCMAKE_LINKER=${LD} -DCMAKE_ASM_COMPILER=${CC}
        -DCMAKE_LINK_DEPENDS_USE_LINKER=OFF
        -DCMAKE_INSTALL_PREFIX=${RAVYN_SDKROOT}/usr -DCMAKE_BUILD_TYPE=Release

        -DLLVM_ENABLE_LTO=OFF -DLLVM_INCLUDE_TESTS=OFF
        -DLLVM_ENABLE_WARNINGS=OFF
        -DLLVM_ENABLE_RUNTIMES=libunwind

        -DLIBUNWIND_USE_COMPILER_RT=ON -DLIBUNWIND_INCLUDE_DOCS=OFF
        -DLIBUNWIND_INCLUDE_TESTS=OFF -DLIBUNWIND_USE_FRAME_HEADER_CACHE=OFF
        -DLIBUNWIND_REMEMBER_HEAP_ALLOC=OFF
        -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_WEAK_PTHREAD_LIB=ON
        -DLIBUNWIND_LIBCXX_PATH=${DEVEL}/Default.xctoolchain/llvm/libcxx
)

# ------------------------------------------------------------------------
#                             LIBC++
# ------------------------------------------------------------------------

set(LIBCXX_FLAGS
    "-target ${CpuArch}-apple-darwin -isysroot${RAVYN_SDKROOT} \
    -isystem ${SDK_SOURCE_DIR}/usr/include/c++/v1 \
    -stdlib++-isystem ${SDK_SOURCE_DIR}/usr/include/c++/v1 \
    --include=${RAVYN_SDKROOT}/usr/include/xlocale/_stdlib.h \
    --include=${RAVYN_SDKROOT}/usr/include/xlocale/_stdio.h \
    --include=${RAVYN_SDKROOT}/usr/include/xlocale/_string.h \
    --include=${RAVYN_SDKROOT}/usr/include/c++/v1/limits \
    -I${SDK_SOURCE_DIR}/usr/include \
    -I${DEVEL}/Default.xctoolchain/llvm/libcxxabi/include \
    -I${DEVEL}/Default.xctoolchain/llvm/libcxx/include \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/darwin \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/locale \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/locale/FreeBSD \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/libsystem_c/stdtime/FreeBSD \
    -I${CMAKE_CURRENT_SOURCE_DIR}/Libsystem/private \
    -I${RAVYN_SDKROOT}/usr/include/pthread \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/mach \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
    -I${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
    -I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
    -DFP_NAN=0 -DFP_INFINITE=1 -DFP_ZERO=2 -DFP_SUBNORMAL=3 -DFP_NORMAL=4 \
    -DINFINITY='__builtin_huge_val()' \
    -Wno-incompatible-sysroot -Wno-user-defined-literals \
    -Wno-nullability-completeness -Wno-expansion-to-defined"
)

ExternalProject_Add(libcxx DEPENDS xnu_headers libunwind
    SOURCE_DIR ${DEVEL}/Default.xctoolchain/llvm/runtimes
    BINARY_DIR llvm_target/libcxx
    USES_TERMINAL_BUILD
    CMAKE_ARGS -Wno-dev
        "-DCMAKE_C_FLAGS=${LIBCXX_FLAGS}"
        "-DCMAKE_CXX_FLAGS=${LIBCXX_FLAGS}"
        -DCMAKE_SYSROOT=${RAVYN_SDKROOT} -DCMAKE_SYSTEM_NAME=Darwin
        -DCMAKE_C_COMPILER=${CC} -DCMAKE_CXX_COMPILER=${CXX}
        -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON
        -DCMAKE_LINKER=${LD} -DCMAKE_ASM_COMPILER=${CC}
        -DCMAKE_C_USING_LINKER_APPLE=${CC} -DCMAKE_CXX_USING_LINKER_APPLE=${CXX}
        -DCMAKE_LINK_DEPENDS_USE_LINKER=OFF
        -DCMAKE_INSTALL_PREFIX=${RAVYN_SDKROOT}/usr -DCMAKE_BUILD_TYPE=Release

        -DLLVM_ENABLE_LIBCXX=ON
        -DLLVM_APPEND_VC_REV=OFF -DLLVM_TARGETS_TO_BUILD=${BuildArch}
        -DLLVM_ENABLE_LTO=OFF -DLLVM_BUILD_DOCS=OFF -DLLVM_INCLUDE_TESTS=OFF
        -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_ENABLE_WARNINGS=OFF
        -DLLVM_ENABLE_RUNTIMES=libcxx$<SEMICOLON>libcxxabi

        -DLIBCXX_ENABLE_EXCEPTIONS=ON -DLIBCXX_INCLUDE_TESTS=OFF
        -DLIBCXX_ENABLE_TIME_ZONE_DATABASE=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF
        -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_ENABLE_SHARED=ON
        -DLIBCXX_INCLUDE_DOCS=OFF -DLIBCXX_HAS_PTHREAD_API=ON
        -DLIBCXX_HAS_ATOMIC_LIB=OFF

        -DLIBCXXABI_USE_LLVM_UNWINDER=ON
        -DLIBCXXABI_HAS_PTHREAD_API=ON -DLIBCXXABI_USE_COMPILER_RT=ON
        -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXXABI_ENABLE_SHARED=ON
        -DLIBCXXABI_SILENT_TERMINATE=ON
)


add_custom_target(compiler_rt)
add_dependencies(compiler_rt libcxx libunwind runtime)

add_dependencies(libSystem
    xnu_headers libsystem_c libsystem_platform libsystem_pthread
    libsystem_malloc libdyld libkernel libsystem_darwin
    compiler_rt
)

# add_dependencies(Darwin libSystem libcxx)
