
add_library(ravynOS_sdk STATIC stub.c)
foreach(file SDKSettings.plist SDKSettings.json Entitlements.plist)
    file(COPY_FILE ${CMAKE_CURRENT_SOURCE_DIR}/${file}
        ${CMAKE_CURRENT_BINARY_DIR}/${file} ONLY_IF_DIFFERENT)
endforeach()
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/System/Library/Frameworks)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/local/include)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/local/lib)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/local/bin)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/include)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/lib)
file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/usr/bin)
add_custom_command(TARGET ravynOS_sdk
    POST_BUILD
    COMMENT "SDK post-build cleanup"
    COMMAND ${CMAKE_COMMAND} -E rm $<TARGET_FILE_DIR:ravynOS_sdk>/libravynOS_sdk.a
    COMMAND ${CMAKE_COMMAND} -E rm $<TARGET_FILE_DIR:ravynOS_sdk>/cmake_install.cmake
    COMMAND ${CMAKE_COMMAND} -E rm -rf $<TARGET_FILE_DIR:ravynOS_sdk>/CMakeFiles
)
