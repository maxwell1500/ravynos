file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu_header_install)
externalproject_add(xnu_headers.extproj
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/xnu_header_build
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}
    CONFIGURE_COMMAND true # disable auto CMake configure
    BUILD_COMMAND
        cmake
            -D XNU_SRC=${CMAKE_CURRENT_SOURCE_DIR}
            -D XNU_OBJ=<BINARY_DIR>
            -D AVAILABILITY_PL_PATH=${SRCTOP}/Kernel/availability.pl
            -P ${CMAKE_CURRENT_SOURCE_DIR}/preprocess_files.cmake
    COMMAND
        ${MAKE} -C <SOURCE_DIR> installhdrs ARCH_CONFIGS=X86_64 BUILD_LTO=0
            BUILD_WERROR=0 DO_CTFMERGE=0 KERNEL_CONFIGS=RELEASE
            CODESIGN_ALLOCATE=${OBJTOP}/tmp/obj-tools/usr/bin/codesign_allocate
            CTFCONVERT=${OBJTOP}/tmp/obj-tools/usr/bin/ctfconvert
            CTFMERGE=${OBJTOP}/tmp/obj-tools/usr/bin/ctfmerge
            CTFINSERT=${OBJTOP}/tmp/obj-tools/usr/bin/ctfinsert
            MIG=${OBJTOP}/tmp/obj-tools/usr/bin/mig
            MIGCOM=${OBJTOP}/tmp/obj-tools/usr/libexec/migcom
            STRIP=${OBJTOP}/tmp/obj-tools/usr/bin/strip
            LIPO=${OBJTOP}/tmp/obj-tools/usr/bin/lipo
            NM=${OBJTOP}/tmp/obj-tools/usr/bin/nm
            NMEDIT=${OBJTOP}/tmp/obj-tools/usr/bin/nmedit
            LIBTOOL=${OBJTOP}/tmp/obj-tools/usr/bin/libtool
            UNIFDEF=${OBJTOP}/tmp/obj-tools/usr/bin/unifdef
            DSYMUTIL=${OBJTOP}/tmp/obj-tools/usr/bin/dsymutil
            SRCROOT=${CMAKE_CURRENT_SOURCE_DIR} OBJROOT=<BINARY_DIR>
            DSTROOT=${CMAKE_CURRENT_BINARY_DIR}
    INSTALL_COMMAND true # installed during build
    USES_TERMINAL_CONFIGURE TRUE
    USES_TERMINAL_BUILD TRUE
)

add_library(xnu_headers INTERFACE)
add_dependencies(xnu_headers xnu_headers.extproj)
target_include_directories(xnu_headers INTERFACE
    ${CMAKE_CURRENT_BINARY_DIR}/xnu_header_install/usr/include
)
add_library(xnu_private_headers INTERFACE)
add_dependencies(xnu_private_headers xnu_headers.extproj)
target_include_directories(xnu_private_headers INTERFACE
    ${CMAKE_CURRENT_BINARY_DIR}/xnu_header_install/usr/local/include
    ${CMAKE_CURRENT_BINARY_DIR}/xnu_header_install/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders
)
target_compile_options(xnu_private_headers INTERFACE
    -F${CMAKE_CURRENT_BINARY_DIR}/xnu_header_install/System/Library/Frameworks
)
add_library(xnu_kernel_headers INTERFACE)
add_dependencies(xnu_kernel_headers xnu_headers.extproj)
target_include_directories(xnu_kernel_headers INTERFACE
    ${CMAKE_CURRENT_BINARY_DIR}/xnu_header_install/System/Library/Frameworks/Kernel.framework/Versions/A/Headers
)
add_library(xnu_kernel_private_headers INTERFACE)
add_dependencies(xnu_kernel_private_headers xnu_headers.extproj)
target_include_directories(xnu_kernel_private_headers INTERFACE
    ${CMAKE_CURRENT_BINARY_DIR}/xnu_header_install/System/Library/Frameworks/Kernel.framework/Versions/A/PrivateHeaders
)

set(XNU_CFLAGS "\
        --sysroot=${OBJTOP}/Kernel/xnu -nostdinc \
        -isystem ${OBJTOP}/Kernel/xnu \
        -I${SRCTOP}/Kernel/xnu/libsyscall/wrappers \
        -I${SRCTOP}/Kernel/xnu/EXTERNAL_HEADERS \
        -I${OBJTOP}/release/usr/include \
        -I${OBJTOP}/Kernel/xnu/xnu_build/src/xnu-build/SETUP/config \
        -I${SRCTOP}/Kernel/xnu/SETUP/config \
        -I${SRCTOP}/Libraries/libpthread/pthread \
        -I${SRCTOP}/Libraries/libpthread \
        -I${SRCTOP}/Kernel/xnu/libkern -I${SRCTOP}/Kernel/xnu/libsyscall \
        -I${SRCTOP}/Libraries/Libc/locale \
        -I${SRCTOP}/Libraries/Libc/locale/FreeBSD \
        -I${SRCTOP}/Libraries/Libc/stdtime/FreeBSD \
        -I${SRCTOP}/Libraries/Libc/darwin \
        -I${SRCTOP}/Libraries/Libc/include \
        -I${SRCTOP}/contrib/cctools/include/foreign \
        -I${SRCTOP}/Kernel/xnu/osfmk \
        -DXSRCROOT=${SRCTOP}/Kernel/xnu \
        -I${SRCTOP}/Libraries/libplatform/include/ \
        -DOS_WARN_RESULT='__attribute__((__warn_unused_result__))' \
        -DOS_ALWAYS_INLINE='__attribute__((__always_inline__))' \
        -DKERNEL -DKERNEL_PRIVATE -D__swift_nonisolated_unsafe='' \
        -Wno-error=implicit-function-declaration \
        -Wno-deprecated-declarations -Wno-reserved-identifier"
)
externalproject_add(xnu
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/xnu_build
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}
    CONFIGURE_COMMAND true # disable auto CMake configure
    BUILD_COMMAND
        cmake
            -DCMAKE_C_COMPILER=${OBJTOP}/tmp/obj-tools/usr/bin/cc
            -DCMAKE_CXX_COMPILER=${OBJTOP}/tmp/obj-tools/usr/bin/c++
            -DCMAKE_C_LINKER=${OBJTOP}/tmp/obj-tools/usr/bin/ld64
            -DCMAKE_CXX_LINKER=${OBJTOP}/tmp/obj-tools/usr/bin/ld64
            -D AVAILABILITY_PL_PATH=${SRCTOP}/Kernel/availability.pl
            -D FIREHOSE_KERNEL_LIBRARY_PATH=${SRCTOP}/Kernel/libfirehose_kernel/src
            -D FIREHOSE_KERNEL_HEADER_PATH=${SRCTOP}/Kernel/libfirehose_kernel/include
            -D PTHREAD_HEADER_PATH=${SRCTOP}/contrib/libpthread/pthread
            -D XNU_SRC=${CMAKE_CURRENT_SOURCE_DIR}
            -D XNU_OBJ=<BINARY_DIR>
            -P ${CMAKE_CURRENT_SOURCE_DIR}/preprocess_files.cmake
    COMMAND
        ${MAKE} -C <SOURCE_DIR> install ARCH_CONFIGS=X86_64 BUILD_LTO=0
            BUILD_WERROR=0 DO_CTFMERGE=0 KERNEL_CONFIGS=RELEASE
            CODESIGN_ALLOCATE=${OBJTOP}/tmp/obj-tools/usr/bin/codesign_allocate
            CTFCONVERT=${OBJTOP}/tmp/obj-tools/usr/bin/ctfconvert
            CTFMERGE=${OBJTOP}/tmp/obj-tools/usr/bin/ctfmerge
            CTFINSERT=${OBJTOP}/tmp/obj-tools/usr/bin/ctfinsert
            MIG=${OBJTOP}/tmp/obj-tools/usr/bin/mig
            MIGCOM=${OBJTOP}/tmp/obj-tools/usr/libexec/migcom
            STRIP=${OBJTOP}/tmp/obj-tools/usr/bin/strip
            LIPO=${OBJTOP}/tmp/obj-tools/usr/bin/lipo
            NM=${OBJTOP}/tmp/obj-tools/usr/bin/nm
            NMEDIT=${OBJTOP}/tmp/obj-tools/usr/bin/nmedit
            LIBTOOL=${OBJTOP}/tmp/obj-tools/usr/bin/libtool
            UNIFDEF=${OBJTOP}/tmp/obj-tools/usr/bin/unifdef
            DSYMUTIL=${OBJTOP}/tmp/obj-tools/usr/bin/dsymutil
            SRCROOT=${CMAKE_CURRENT_SOURCE_DIR} OBJROOT=<BINARY_DIR>
            SYMROOT=${CMAKE_CURRENT_BINARY_DIR}/xnu_sym
            DSTROOT=${OBJTOP}/release
    INSTALL_COMMAND true # installed during build
    USES_TERMINAL_CONFIGURE TRUE
    USES_TERMINAL_BUILD TRUE
)
add_dependencies(xnu
    xnu_headers libfirehose_kernel
    #dyld_availability_headers
)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/Kernel.framework/Versions/A/Resources DESTINATION System/Library/Frameworks/Kernel.framework/Versions/A COMPONENT BaseSystem)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/Kernel.framework/Versions/A/Headers DESTINATION System/Library/Frameworks/Kernel.framework/Versions/A COMPONENT DeveloperTools)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/Kernel.framework/Versions/A/PrivateHeaders DESTINATION System/Library/Frameworks/Kernel.framework/Versions/A COMPONENT DeveloperInternal)

# Note: This really ought to be associated with a custom build command like 'install_framework_symlinks' or something
install_symlink(System/Library/Frameworks/Kernel.framework/Versions/Current Versions/A COMPONENT BaseSystem)
install_symlink(System/Library/Frameworks/Kernel.framework/Resources Versions/Current/Resources COMPONENT BaseSystem)
install_symlink(System/Library/Frameworks/Kernel.framework/Headers Versions/Current/Headers COMPONENT DeveloperTools)
install_symlink(System/Library/Frameworks/Kernel.framework/PrivateHeaders Versions/Current/PrivateHeaders COMPONENT DeveloperInternal)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders DESTINATION System/Library/Frameworks/System.framework/Versions/B COMPONENT DeveloperInternal)

install_symlink(System/Library/Frameworks/System.framework/Versions/Current Versions/B COMPONENT BaseSystem)
install_symlink(System/Library/Frameworks/System.framework/PrivateHeaders Versions/Current/PrivateHeaders COMPONENT DeveloperInternal)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/DriverKit.framework/Versions/A/Headers DESTINATION System/Library/Frameworks/DriverKit.framework/Versions/A COMPONENT DeveloperTools)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/DriverKit.framework/Versions/A/PrivateHeaders DESTINATION System/Library/Frameworks/DriverKit.framework/Versions/A COMPONENT DeveloperInternal)

install_symlink(System/Library/Frameworks/DriverKit.framework/Versions/Current Versions/A COMPONENT BaseSystem)
install_symlink(System/Library/Frameworks/DriverKit.framework/Headers Versions/Current/Headers COMPONENT DeveloperTools)
install_symlink(System/Library/Frameworks/DriverKit.framework/PrivateHeaders Versions/Current/PrivateHeaders COMPONENT DeveloperInternal)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/IOKit.framework/Versions/A/Headers DESTINATION System/Library/Frameworks/IOKit.framework/Versions/A COMPONENT DeveloperTools)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Frameworks/IOKit.framework/Versions/A/PrivateHeaders DESTINATION System/Library/Frameworks/IOKit.framework/Versions/A COMPONENT DeveloperInternal)

install_symlink(System/Library/Frameworks/IOKit.framework/Versions/Current Versions/A COMPONENT BaseSystem)
install_symlink(System/Library/Frameworks/IOKit.framework/Headers Versions/Current/Headers COMPONENT DeveloperTools)
install_symlink(System/Library/Frameworks/IOKit.framework/PrivateHeaders Versions/Current/PrivateHeaders COMPONENT DeveloperInternal)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Kernels DESTINATION System/Library COMPONENT BaseSystem)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/System/Library/Extensions DESTINATION System/Library COMPONENT BaseSystem)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/usr/include DESTINATION usr COMPONENT DeveloperTools)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/usr/lib DESTINATION usr COMPONENT BaseSystem)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/usr/libexec DESTINATION usr COMPONENT BaseSystem)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/usr/share/man DESTINATION usr/share COMPONENT BaseSystem)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/usr/share/misc DESTINATION usr/share COMPONENT BaseSystem)
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xnu/usr/local DESTINATION usr COMPONENT DeveloperInternal)
