# Helper macro for building macOS/ravynOS .framework bundles in CMake
include(CMakeParseArguments)

function(add_framework_bundle target_name)
    set(options PRIVATE_FRAMEWORK)
    set(oneValueArgs VERSION INFO_PLIST)
    set(multiValueArgs HEADERS PRIVATE_HEADERS SOURCES)
    cmake_parse_arguments(FMWK "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT FMWK_VERSION)
        set(FMWK_VERSION "A")
    endif()

    if(FMWK_PRIVATE_FRAMEWORK)
        set(_install_dir "/System/Library/PrivateFrameworks")
    else()
        set(_install_dir "/System/Library/Frameworks")
    endif()

    add_library(${target_name} SHARED ${FMWK_SOURCES} ${FMWK_HEADERS} ${FMWK_PRIVATE_HEADERS})
    set_target_properties(${target_name} PROPERTIES
        FRAMEWORK TRUE
        FRAMEWORK_VERSION "${FMWK_VERSION}"
        MACOSX_FRAMEWORK_IDENTIFIER "com.ravynos.${target_name}"
        PUBLIC_HEADER "${FMWK_HEADERS}"
        PRIVATE_HEADER "${FMWK_PRIVATE_HEADERS}"
        INSTALL_NAME_DIR "${_install_dir}/${target_name}.framework/Versions/${FMWK_VERSION}"
    )
    if(FMWK_INFO_PLIST AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${FMWK_INFO_PLIST}")
        set_target_properties(${target_name} PROPERTIES
            MACOSX_FRAMEWORK_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/${FMWK_INFO_PLIST}"
        )
    endif()
endfunction()
