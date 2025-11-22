set(TOOLS ${TOOLCHAIN}/usr/bin)
set(PATH "${TOOLS}:$ENV{PATH}")
set(GMAKE /usr/bin/make)

set(CC ${TOOLS}/cc)
set(CXX ${TOOLS}/c++)
set(LD ${TOOLS}/ld64)
set(AR ${TOOLS}/ar)
set(RANLIB ${TOOLS}/ranlib)
set(NM ${TOOLS}/nm)
set(CODESIGN_ALLOCATE ${TOOLS}/codesign_allocate)
set(CTFCONVERT ${TOOLS}/ctfconvert)
set(CTFMERGE ${TOOLS}/ctfmerge)
set(CTFINSERT ${TOOLS}/ctfinsert)
set(IIG /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/iig)
set(MIG ${TOOLS}/mig)
set(MIGCOM ${TOOLS}/../libexec/migcom)
set(STRIP ${TOOLS}/strip)
set(LIPO ${TOOLS}/lipo)
set(NM ${TOOLS}/nm)
set(NMEDIT ${TOOLS}/nmedit)
set(LIBTOOL ${TOOLS}/libtool)
set(UNIFDEF ${TOOLS}/unifdef)
set(DSYMUTIL ${TOOLS}/dsymutil)
set(XCRUN ${TOOLS}/xcrun)
set(XCBUILD ${TOOLS}/xcbuild)
set(XCODEBUILD ${TOOLS}/xcodebuild)

set(MACHINE uppercase(${CMAKE_SYSTEM_PROCESSOR}))
set(KERNEL_CONFIGS RELEASE)
set(ARCH_CONFIGS X86_64)
set(AVAILABILITY_PL ${CMAKE_SOURCE_DIR}/Kernel/availability.pl)
set(AVAILABILITY_PL_PATH ${CMAKE_SOURCE_DIR}/Kernel/availability.pl)
set(SEED_DEFINES 
	-DRC_ENABLE_XNU_PRODUCT_INFO_FILTER
	-DTARGET_OS_IPHONE=0
	-DTARGET_OS_WIN32=0
	-DTARGET_OS_OSX=1
	-DTARGET_OS_MAC=1
	-DTARGET_OS_SIMULATOR=0
)

ExternalProject_Add(xnu_headers
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/Kernel/xnu
    CONFIGURE_COMMAND
		${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/Libraries/Libc/include/limits.h ${CMAKE_BINARY_DIR}/sysroot/usr/include/
    BUILD_COMMAND
    	${GMAKE} -C ${CMAKE_SOURCE_DIR}/Kernel/xnu
			MAKE=${GMAKE} PLATFORM=MacOSX BUILD_LTO=0 BUILD_WERROR=0 DO_CTFMERGE=0 
			XCRUN=${XCRUN} XCBUILD=${XCBUILD} XCODEBUILD=${XCODEBUILD} PATH=${PATH}
			MIGCOM=${MIGCOM} MIG=${MIG} IIG=${IIG} SDKROOT=${RAVYN_SDKROOT}
		    SRCROOT=${CMAKE_SOURCE_DIR}/Kernel/xnu OBJROOT=${CMAKE_BINARY_DIR}/Kernel/xnu
		    DSTROOT=${CMAKE_BINARY_DIR}/sysroot installhdrs
    INSTALL_COMMAND ""
	DEPENDS BootstrapTools
)

add_subdirectory(libfirehose_kernel)
add_dependencies(libfirehose_kernel CarbonHeaders)

file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/sysroot/usr/include ${CMAKE_BINARY_DIR}/sysroot/usr/local/include/kernel)
file(COPY ${CMAKE_SOURCE_DIR}/Libraries/Libc/include/limits.h 
	DESTINATION ${CMAKE_BINARY_DIR}/sysroot/usr/include/)
file(COPY ${CMAKE_SOURCE_DIR}/Libraries/libdispatch/os
	DESTINATION ${CMAKE_BINARY_DIR}/sysroot/usr/local/include/kernel/)

ExternalProject_Add(xnu
    SOURCE_DIR ${CMAKE_SOURCE_DIR}/Kernel/xnu
    CONFIGURE_COMMAND ""
    BUILD_COMMAND
    	${GMAKE} -C ${CMAKE_SOURCE_DIR}/Kernel/xnu
			MAKE=${GMAKE} PLATFORM=MacOSX BUILD_LTO=0 BUILD_WERROR=0 DO_CTFMERGE=0
			XCRUN=${XCRUN} XCBUILD=${XCBUILD} XCODEBUILD=${XCODEBUILD} "PATH=${PATH}"
			MIGCOM=${MIGCOM} MIG=${MIG} IIG=${IIG}
		    SRCROOT=${CMAKE_SOURCE_DIR}/Kernel/xnu OBJROOT=${CMAKE_BINARY_DIR}/Kernel/xnu
		    DSTROOT=${CMAKE_BINARY_DIR}/sysroot install
    INSTALL_COMMAND ""
	DEPENDS xnu_headers CarbonHeaders libfirehose_kernel BootstrapTools
)


# ${SRCTOP}/Libraries/Libc/include/libc-features.h:
# 	mkdir -p ${OBJTOP}/tmp/include
# 	cmake -E env ARCHS="x86_64 arm64" \
# 		SRCROOT=${SRCTOP}/Libraries/Libc \
# 		DERIVED_FILES_DIR=${OBJTOP}/tmp/include \
# 		VARIANT_PLATFORM_NAME=macosx \
# 		perl ${SRCTOP}/Libraries/Libc/xcodescripts/generate_features.pl
# 	cp -fv ${OBJTOP}/tmp/include/${MACHINE}/libc-features.h ${.TARGET}

# Libc: ${SRCTOP}/Libraries/Libc/include/libc-features.h
# 	mkdir -pv ${OBJTOP}/Libc ${BUILDROOT}/usr/include
# 	cd ${OBJTOP}/Libc; \
# 	RUNTIME_SPEC_PATH=${SRCTOP}/contrib/xcbuild/Specifications \
# 		${OBJTOOLS}/usr/bin/xcbuild \
# 		-project ${SRCTOP}/Libraries/Libc/Libc.xcodeproj
# #.for f in limits.h
# #	cp -Rfv $$HOME/Library/Developer/Xcode/DerivedData/Build/Products/Release/usr/include/${f} ${BUILDROOT}/usr/include/
# #.endfor

# libkmod: xnu_headers
# 	mkdir -pv ${OBJTOP}/Kernel/libkmod/include/pthread
# 	cp -fv ${SRCTOP}/Libraries/libpthread/private/{spinlock,tsd}_private.h \
# 		${OBJTOP}/Kernel/libkmod/include/pthread/
# 	cp -fv ${SRCTOP}/Libraries/Libc/locale/FreeBSD/{collate,lmessages,lmonetary,lnumeric,setlocale}.h \
# 		${OBJTOP}/Kernel/libkmod/include/
# 	cp -fv ${SRCTOP}/Libraries/Libc/stdtime/FreeBSD/timelocal.h \
# 		${OBJTOP}/Kernel/libkmod/include/
# 	ln -sfv B ${OBJTOP}/release/System/Library/Frameworks/System.framework/Versions/Current
# 	ln -sfv Versions/Current/Headers \
# 		${OBJTOP}/release/System/Library/Frameworks/System.framework/Headers
# 	ln -sfv Versions/Current/PrivateHeaders \
# 		${OBJTOP}/release/System/Library/Frameworks/System.framework/PrivateHeaders
# 	mkdir -pv ${BUILDROOT}/usr/include/os
# 	cp -fv ${CONTRIB}/os/availability.h ${BUILDROOT}/usr/include/os
# 	cd ${OBJTOP}/Kernel/libkmod; cmake -Wno-dev \
# 		-DCMAKE_INSTALL_PREFIX=/ -DCMAKE_BUILD_TYPE=Release \
# 		-DSRCTOP=${SRCTOP} -DOBJTOP=${OBJTOP} \
# 		-G"Unix Makefiles" ${SRCTOP}/Kernel/libkmod
# 	export PATH PLATFORM=MacOSX MAKEFLAGS="" MAKE=${GMAKE}; \
# 		${GMAKE} DESTDIR=${BUILDROOT} -C ${OBJTOP}/Kernel/libkmod

# kext: libkmod
# 	mkdir -pv ${OBJTOP}/Kernel/Extensions/include/pthread
# 	mkdir -pv ${OBJTOP}/Kernel/Extensions/include/IOKit/{storage,ata}
# 	cp -fv ${SRCTOP}/Libraries/libpthread/private/qos_private.h \
# 		${OBJTOP}/Kernel/Extensions/include/pthread/
# 	cp -fv ${SRCTOP}/Kernel/Extensions/IOATAFamily/IOATARegI386.h \
# 		${OBJTOP}/Kernel/Extensions/include/IOKit/ata/
# 	cp -fv ${SRCTOP}/Kernel/Extensions/IOStorageFamily/*.h \
# 		${OBJTOP}/Kernel/Extensions/include/IOKit/storage/
# 	cd ${OBJTOP}/Kernel/Extensions;	cmake -Wno-dev \
# 		-DCMAKE_INSTALL_PREFIX=/System/Library/Extensions \
# 		-DCMAKE_BUILD_TYPE=Release -DSRCTOP=${SRCTOP} -DOBJTOP=${OBJTOP} \
# 		-G"Unix Makefiles" ${SRCTOP}/Kernel/Extensions
# 	export PATH PLATFORM=MacOSX MAKEFLAGS="" MAKE=${GMAKE}; \
# 		${GMAKE} DESTDIR=${BUILDROOT} -C ${OBJTOP}/Kernel/Extensions \
# 		install

# KMUTIL?= /usr/bin/kmutil
# prelink:
# 	${KMUTIL} create --allow-missing-kdk -n boot -z \
# 		--boot-path ${OBJTOP}/Kernel/kernelcache \
# 		-f 'OSBundleRequired == Local-Root'  \
# 		--kernel ${OBJTOP}/Kernel/xnu/RELEASE_${MACHINE:S/x/X/}/kernel \
# 		-r ${BUILDROOT}/System/Library/Extensions/ \
# 		-r ${SRCTOP}/Kernel/xnu/config/System.kext/PlugIns \
# 		--bundle-path ${SRCTOP}/Kernel/xnu/config/System.kext
