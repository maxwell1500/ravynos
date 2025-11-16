add_subdirectory(cctools)
add_subdirectory(mig)
add_subdirectory(unifdef)
add_subdirectory(ravynOS.sdk)
add_subdirectory(Default.xctoolchain)

ExternalProject_Add(host_xcbuild
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/Developer/xcbuild
    CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/Developer/Default.xctoolchain
)

ExternalProject_Add(dtrace_ctf_host
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/Developer/dtrace_ctf
    BINARY_DIR ${CMAKE_BINARY_DIR}/Developer/dtrace_ctf_host
    INSTALL_COMMAND ""
)

if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "x86_64|amd64")
    set(BuildArch "X86")
    set(CpuArch "x86_64")
elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(BuildArch "AArch64")
    set(CpuArch "aarch64")
endif()
ExternalProject_Add(host_clang
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/Developer/llvm-project/llvm
    BINARY_DIR ${CMAKE_BINARY_DIR}/Developer/clang
    CMAKE_ARGS 
        -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/Developer/Default.xctoolchain/usr
        -DCMAKE_BUILD_TYPE=Release
        -DLLVM_ENABLE_PROJECTS=clang
        -DLLVM_ENABLE_RUNTIMES=compiler-rt
        -DLLVM_TARGETS_TO_BUILD=${BuildArch}
        -DLLVM_DEFAULT_TARGET_TRIPLE=${CpuArch}-ravynOS-darwin-macho
        -DLLVM_BUILD_TOOLS=OFF
        -DLLVM_BUILD_DOCS=OFF
)