add_library(BootstrapTools STATIC stub.c)
add_dependencies(BootstrapTools
    host_libmacho host_libstuff
    host_checksyms host_lipo host_size host_strings host_nm host_libtool
    host_redo_prebinding host_seg_addr_table host_seg_hack host_install_name_tool
    host_indr host_strip host_segedit host_pagestuff host_codesign_allocate
    host_bitcode_strip host_ctf_insert host_check_dylib host_cmpdylib host_inout
    host_vtool host_nmedit host_ranlib host_migcom host_xcbuild dtrace_ctf_host
    host_clang host_ld host_xar host_libxar
)

file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/libexec)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/include)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/lib)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/bin)
file(COPY_FILE ${CMAKE_SOURCE_DIR}/Developer/mig/mig.sh
    ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/mig ONLY_IF_DIFFERENT)
file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/ToolchainInfo.plist
    DESTINATION ${CMAKE_CURRENT_BINARY_DIR})
file(CREATE_LINK Default.xctoolchain
    ${CMAKE_CURRENT_BINARY_DIR}/../XcodeDefault.xctoolchain SYMBOLIC)

add_custom_command(TARGET BootstrapTools
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_xar> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_libxar> ${CMAKE_CURRENT_BINARY_DIR}/usr/lib/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_ld> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_checksyms> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_lipo> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_size> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_strings> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_nm> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_libtool> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_redo_prebinding> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_seg_addr_table> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_seg_hack> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_install_name_tool> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_indr> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_strip> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_segedit> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_pagestuff> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_codesign_allocate> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_bitcode_strip> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_ctf_insert> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_check_dylib> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_cmpdylib> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_inout> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_vtool> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_nmedit> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_ranlib> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:unifdef> ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:host_migcom> ${CMAKE_CURRENT_BINARY_DIR}/usr/libexec/migcom
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/Developer/dtrace_ctf_host/tools/ctfconvert ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/Developer/dtrace_ctf_host/tools/ctfdump ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/Developer/dtrace_ctf_host/tools/ctfmerge ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/
    COMMAND ${CMAKE_COMMAND} -E create_symlink llvm-otool ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/otool
    COMMAND ${CMAKE_COMMAND} -E create_symlink llvm-as ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/as
    COMMAND ${CMAKE_COMMAND} -E create_symlink ld ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/ld64
    COMMAND ${CMAKE_COMMAND} -E create_symlink clang ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/cc
    COMMAND ${CMAKE_COMMAND} -E create_symlink clang++ ${CMAKE_CURRENT_BINARY_DIR}/usr/bin/c++
    COMMAND ${CMAKE_COMMAND} -E rm ${CMAKE_CURRENT_BINARY_DIR}/cmake_install.cmake
    COMMAND ${CMAKE_COMMAND} -E rm -rf ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles
    COMMAND ${CMAKE_COMMAND} -E rm -rf ${CMAKE_CURRENT_BINARY_DIR}/libBootstrapTools.a
)