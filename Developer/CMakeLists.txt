add_subdirectory(cctools)
add_subdirectory(mig)
add_subdirectory(unifdef)
add_subdirectory(ravynOS.sdk)
add_subdirectory(XcodeDefault.xctoolchain)

ExternalProject_Add(host_xcbuild
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/Developer/xcbuild
    CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/Developer/XcodeDefault.xctoolchain/
)

ExternalProject_Add(dtrace_ctf_host
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/Developer/dtrace_ctf
    INSTALL_COMMAND ""
)