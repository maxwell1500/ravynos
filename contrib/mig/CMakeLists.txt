cmake_minimum_required(VERSION 3.15.1)
project(ravynOS)

cmake_policy(SET CMP0114 NEW)

set(CMAKE_INSTALL_PREFIX "")
set(CMAKE_MACOSX_MIN_VERSION 11.0)

include(ExternalProject)
include(../cmake/asm.cmake)
include(../cmake/bundle_resources.cmake)
include(../cmake/circular.cmake)
include(../cmake/crosscompile.cmake)
include(../cmake/get_target_dependencies.cmake)
include(../cmake/install_helpers.cmake)
include(../cmake/kext.cmake)
include(../cmake/mig.cmake)
include(../cmake/suppress_warnings.cmake)

add_executable(migcom)
target_sources(migcom PRIVATE
    error.c
    global.c
    header.c
    mig.c
    routine.c
    server.c
    routine.c
    server.c
    statement.c
    string.c
    type.c
    user.c
    utils.c

    ${CMAKE_CURRENT_BINARY_DIR}/y.tab.c
    ${CMAKE_CURRENT_BINARY_DIR}/lexxer.yy.c
)
target_compile_definitions(migcom PRIVATE MIG_VERSION=\"\")
target_include_directories(migcom PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/y.tab.c
    COMMAND yacc -d -b "${CMAKE_CURRENT_BINARY_DIR}/y" ${CMAKE_CURRENT_SOURCE_DIR}/parser.y
    COMMENT "Yacc parser.y" VERBATIM
)
add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/lexxer.yy.c
    COMMAND lex -o "${CMAKE_CURRENT_BINARY_DIR}/lexxer.yy.c" ${CMAKE_CURRENT_SOURCE_DIR}/lexxer.l
    COMMENT "Lex lexxer.l" VERBATIM
)

add_executable(mig IMPORTED)
set_property(TARGET mig PROPERTY IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/mig.sh)
add_dependencies(mig migcom)
