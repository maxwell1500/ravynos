add_subdirectory(parsers)
add_subdirectory(passes)

find_package(OpenSSL REQUIRED)

add_executable(host_ld)
target_sources(host_ld PRIVATE
    debugline.c
    InputFiles.cpp
    ld.cpp
    libcodedirectory.c
    Options.cpp
    OutputFile.cpp
    Resolver.cpp
    ResponseFiles.cpp
    Snapshot.cpp
    SymbolTable.cpp
    PlatformSupport.cpp
    code-sign-blobs/blob.cpp
)
file(COPY ${CMAKE_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS/corecrypto
    DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/)

target_compile_definitions(host_ld PRIVATE __DARWIN_UNIX03)
target_compile_options(host_ld PRIVATE 
    "-Wno-#warnings" -Wno-deprecated -Wno-macro-redefined)
target_link_libraries(host_ld PRIVATE
    host_libxar host_ld_helper host_ld_BlocksRuntime host_ld_libparsers host_ld_libpasses host_libstuff
    OpenSSL::SSL OpenSSL::Crypto
)
set_property(TARGET host_ld PROPERTY OUTPUT_NAME ld)
set_property(TARGET host_ld PROPERTY CXX_STANDARD 11)

target_include_directories(host_ld PRIVATE
    .
    ..
    ../..
    ../abstraction
    ../3rd
    ../../../../../Libraries/CommonCrypto/include
    ../../../../../Libraries/CommonCrypto/include/Private
    parsers passes
    ${OPENSSL_INCLUDE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)


    # ../../../include
    # ../../../include/foreign
    # ..
    # ../..
    # ../abstraction
    # ../3rd
    # ../3rd/BlocksRuntime
    # ../3rd/include
    # ${CMAKE_CURRENT_SOURCE_DIR}
    # parsers passes
    # ${OPENSSL_INCLUDE_DIR}
