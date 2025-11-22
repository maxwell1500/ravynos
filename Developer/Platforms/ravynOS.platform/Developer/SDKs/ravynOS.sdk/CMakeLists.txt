file(COPY ${CMAKE_SOURCE_DIR}/Developer/Platforms/ravynOS.platform/Info.plist
    DESTINATION ${CMAKE_BINARY_DIR}/Developer/Platforms/ravynOS.platform/)
file(CREATE_LINK ravynOS.platform
    ${CMAKE_BINARY_DIR}/Developer/Platforms/MacOSX.platform SYMBOLIC)

add_library(ravynOS_sdk OBJECT stub.c)
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
file(COPY ${CMAKE_SOURCE_DIR}/Developer/CarbonHeaders/TargetConditionals.h
    ${CMAKE_SOURCE_DIR}/Developer/CarbonHeaders/ConditionalMacros.h
    ${CMAKE_SOURCE_DIR}/Developer/CarbonHeaders/MacTypes.h
    ${CMAKE_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS/Availability.h
    ${CMAKE_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS/AvailabilityInternal.h
    ${CMAKE_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS/AvailabilityVersions.h
    ${CMAKE_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS/AvailabilityInternalLegacy.h
    DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/usr/include/)

add_dependencies(ravynOS_sdk CarbonHeaders)