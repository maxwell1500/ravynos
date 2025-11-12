
MACHINE!=	uname -m
MACHINE_ARCH!=	uname -p
OSNAME!=	uname -s
TARGET?=	${MACHINE}.${MACHINE_ARCH}
TARGET_ARCH?=	${MACHINE_ARCH}
.export MACHINE MACHINE_CPUARCH TARGET TARGET_ARCH

SRCTOP=		${.CURDIR}
MACTOP=		${SRCTOP}/_distribution-macOS
BSDTOP=		${SRCTOP}/_FreeBSD
CONTRIB=	${SRCTOP}/contrib
OBJTOP?=	/usr/obj/ravynOS/${TARGET}
OBJTOOLS=	${OBJTOP}/tmp/obj-tools
BUILDROOT=	${OBJTOP}/release
RAVYNOS_VERSION!=  grep -A1 ProductVersion \
			${SRCTOP}/SystemLibrary/SystemVersion.plist.in | \
			tail -1 | sed -e 's/<\/*string>//'
RAVYNOS_CODENAME!= grep -A1 ProductFamily \
			${SRCTOP}/SystemLibrary/SystemVersion.plist.in | \
			tail -1 | sed -e 's/<\/*string>//'
.ifndef CORES
.if ${OSNAME} == Linux
CORES!=		grep -c ^processor /proc/cpuinfo
.else
CORES!=		sysctl -n hw.ncpu
.endif
.endif

DESTDIR=
LOGCOLORS= n
.export DESTDIR SRCTOP OBJTOP BUILDROOT RAVYNOS_VERSION RAVYNOS_CODENAME CORES
.export LOGCOLORS

.if ${OSNAME} == Darwin
SDKROOT?=	/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
.export SDKROOT
.endif

MK_WERROR=      no
WARNS=          0
BMAKE?=		bmake
GMAKE?=		gmake

.if "${CIRRUS_CI}"
SHA!= echo ${CIRRUS_CHANGE_IN_REPO}|cut -c1-7|tr '[a-z]' '[A-Z]'
.else
SHA!= cd ${.CURDIR} && git log -1|head -1|cut -c8-14|tr '[a-z]' '[A-Z]'
.endif

.include <rvn.common.mk>

_BOOTSTRAP?=		_bootstrap-clang _bootstrap-xcbuild \
			_bootstrap-cctools _bootstrap-mig \
			_bootstrap-unifdef
_BOOTSTRAP_OBJDIRS=	${_BOOTSTRAP:S/-/\//:C/^.*$$/${OBJTOP}\/&/}

${_BOOTSTRAP_OBJDIRS}:
.for d in ${.TARGET}
	mkdir -pv ${d}
.endfor

cleandir: .PHONY
	rm -rf ${OBJTOP}

cleanbuild: .PHONY
	rm -rf ${BUILDROOT}

buildworld: _bootstrap .WAIT
buildkernel: _bootstrap .WAIT kernel

# ------------------------------------------------------------------------
#                           BOOTSTRAP TARGETS
#  These targets are used to build the host toolchain that will be used
#  to build everything else
# ------------------------------------------------------------------------
_bootstrap: 	${_BOOTSTRAP_OBJDIRS} \
		.WAIT \
		${OBJTOOLS} ${BUILDROOT} .WAIT \
		${BUILDROOT}/System/Library/SystemVersion.plist \
		${_BOOTSTRAP}

_bootstrap-clang: DIR=${OBJTOP}/${.TARGET:S/-/\//}
	cd ${DIR}; \
	cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
		-DLLVM_ENABLE_PROJECTS='clang;lldb;lld' \
		-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
		-DLLVM_TARGETS_TO_BUILD="X86" \
		-DLLVM_BUILD_LLVM_DYLIB=ON -DLLVM_LINK_LLVM_DYLIB=ON \
		-DLLVM_CREATE_XCODE_TOOLCHAIN=ON \
		-DLLVM_DEFAULT_TARGET_TRIPLE="${MACHINE:S/amd64/x86_64/}-apple-darwin" \
		-G "Unix Makefiles" -Wno-dev \
		${CONTRIB}/llvm-project/llvm
	${MAKE} -C ${OBJTOP}/${.TARGET:S/-/\//} all install \
		DESTDIR=${OBJTOOLS}
	ln -sf ld64.lld ${OBJTOOLS}/usr/bin/ld64
	ln -sf ld.lld ${OBJTOOLS}/usr/bin/ld

_bootstrap-xcbuild: DIR=${OBJTOP}/${.TARGET:S/-/\//}
	cd ${DIR}; \
	cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
		-Wno-dev -G "Unix Makefiles" ${CONTRIB}/xcbuild
	${MAKE} -C ${OBJTOP}/${.TARGET:S/-/\//}
	mkdir -p ${OBJTOOLS}/usr/bin
	cp -fv ${OBJTOP}/${.TARGET:S/-/\//}/Libraries/xcdriver/xcbuild \
		${OBJTOP}/${.TARGET:S/-/\//}/Libraries/plist/plutil \
		${OBJTOP}/${.TARGET:S/-/\//}/Libraries/xcsdk/xcode-select \
		${OBJTOP}/${.TARGET:S/-/\//}/Libraries/xcsdk/xcrun \
		${OBJTOP}/${.TARGET:S/-/\//}/Libraries/acdriver/actool \
		${OBJTOOLS}/usr/bin/
	ln -sfv xcbuild ${OBJTOOLS}/usr/bin/xcodebuild

_bootstrap-cctools: DIR=${OBJTOP}/${.TARGET:S/-/\//}
	cd ${DIR}; \
	cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
		-G "Unix Makefiles" ${CONTRIB}/cctools
	${MAKE} -C ${DIR}
	mkdir -p ${OBJTOOLS}/usr/bin ${OBJTOOLS}/usr/lib
	cp -fv \
		${DIR}/libmacho/libmacho.a ${DIR}/libstuff/libstuff.a \
		${OBJTOOLS}/usr/lib/
.for f in bitcode_strip check_dylib checksyms cmpdylib codesign_allocate \
		ctf_insert host_nmedit host_ranlib indr inout libtool lipo \
		nm pagestuff redo_prebinding seg_addr_table seg_hack segedit \
		size strings strip vtool
	cp -fv ${DIR}/misc/${f} ${OBJTOOLS}/usr/bin/
.endfor

_bootstrap-mig: DIR=${OBJTOP}/${.TARGET:S/-/\//}
	cd ${DIR}; \
	cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
		-G "Unix Makefiles" ${CONTRIB}/mig
	${MAKE} -C ${DIR}
	mkdir -p ${OBJTOOLS}/usr/libexec ${OBJTOOLS}/usr/bin
	cp -fv ${DIR}/migcom ${OBJTOOLS}/usr/libexec/
	cp -fv ${CONTRIB}/mig/mig.sh ${OBJTOOLS}/usr/bin/mig
	chmod 755 ${OBJTOOLS}/usr/bin/mig

_bootstrap-dtracectf: DIR=${OBJTOP}/${.TARGET:S/-/\//}
	cd ${DIR}; \
	cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
		-G "Unix Makefiles" ${CONTRIB}/dtrace_ctf
	${MAKE} -C ${DIR}
	mkdir -p ${OBJTOOLS}/usr/lib ${OBJTOOLS}/usr/bin
	cp -fv \
		${DIR}/libdwarf/libdwarf.a ${DIR}/libelf/libelf.a \
		${DIR}/libctf/libctf.a \
		${OBJTOOLS}/usr/lib/
.for f in ctfmerge ctfconvert ctfdump
	cp -fv ${DIR}/tools/${f} ${OBJTOOLS}/usr/bin/
.endfor

_bootstrap-unifdef: DIR=${OBJTOP}/${.TARGET:S/-/\//}
	cd ${DIR}; \
	cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
		-G "Unix Makefiles" ${CONTRIB}/unifdef
	${MAKE} -C ${DIR}
	mkdir -p ${OBJTOOLS}/usr/lib ${OBJTOOLS}/usr/bin
	cp -fv ${DIR}/unifdef ${OBJTOOLS}/usr/bin/

${BUILDROOT}/System/Library/SystemVersion.plist: ${.CURDIR}/SystemLibrary/SystemVersion.plist.in
	sed -e 's/BUILD_STAMP/${SHA}/' <${.ALLSRC} >${.TARGET}

${OBJTOOLS}: .EXEC
	mkdir -pv ${OBJTOOLS}

${BUILDROOT}: .EXEC
	mkdir -pv ${BUILDROOT}/System/Library


# ------------------------------------------------------------------------
#                           KERNEL TARGETS
#  These targets build the ravynOS kernel (xnu) components
# ------------------------------------------------------------------------

# use our tools from the matching macOS
CODESIGN_ALLOCATE=${OBJTOOLS}/usr/bin/codesign_allocate
CTFCONVERT=${OBJTOOLS}/usr/bin/ctfconvert
CTFMERGE=${OBJTOOLS}/usr/bin/ctfmerge
CTFINSERT=${OBJTOOLS}/usr/bin/ctfinsert
IIG?=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/iig #${OBJTOOLS}/usr/bin/iig
MIG=${OBJTOOLS}/usr/bin/mig
MIGCOM=${OBJTOOLS}/usr/libexec/migcom
STRIP=${OBJTOOLS}/usr/bin/strip
LIPO=${OBJTOOLS}/usr/bin/lipo
NM=${OBJTOOLS}/usr/bin/nm
NMEDIT=${OBJTOOLS}/usr/bin/nmedit
LIBTOOL=${OBJTOOLS}/usr/bin/libtool
UNIFDEF=${OBJTOOLS}/usr/bin/unifdef
DSYMUTIL=${OBJTOOLS}/usr/bin/dsymutil
XCRUN=${OBJTOOLS}/usr/bin/xcrun
XCBUILD=${OBJTOOLS}/usr/bin/xcbuild
.export CODESIGN_ALLOCATE CTFCONVERT CTFMERGE CTFINSERT # IIG
.export MIG MIGCOM STRIP LIPO NM NMEDIT UNIFDEF DSYMUTIL XCRUN XCBUILD

CarbonHeaders: .PHONY
	${GMAKE} DSTROOT=${BUILDROOT} SRCROOT=${CONTRIB}/CarbonHeaders \
		-C ${CONTRIB}/CarbonHeaders
	cp -fv ${CONTRIB}/CarbonHeaders/{ConditionalMacros,MacTypes}.h \
		${BUILDROOT}/usr/include
	cp -fv Kernel/xnu/EXTERNAL_HEADERS/Availability*.h \
		${BUILDROOT}/usr/include/

${SRCTOP}/Libraries/Libc/include/libc-features.h:
	mkdir -p ${OBJTOP}/tmp/include
	cmake -E env ARCHS="x86_64 arm64" \
		SRCROOT=${SRCTOP}/Libraries/Libc \
		DERIVED_FILES_DIR=${OBJTOP}/tmp/include \
		VARIANT_PLATFORM_NAME=macosx \
		perl ${SRCTOP}/Libraries/Libc/xcodescripts/generate_features.pl
	cp -fv ${OBJTOP}/tmp/include/${MACHINE}/libc-features.h ${.TARGET}

Libc: ${SRCTOP}/Libraries/Libc/include/libc-features.h
	mkdir -pv ${OBJTOP}/Libc ${BUILDROOT}/usr/include
	cd ${OBJTOP}/Libc; \
	RUNTIME_SPEC_PATH=${SRCTOP}/contrib/xcbuild/Specifications \
		${OBJTOOLS}/usr/bin/xcbuild \
		-project ${SRCTOP}/Libraries/Libc/Libc.xcodeproj
#.for f in limits.h
#	cp -Rfv $$HOME/Library/Developer/Xcode/DerivedData/Build/Products/Release/usr/include/${f} ${BUILDROOT}/usr/include/
#.endfor

libSystem_malloc:
	# We just need the headers for now
	mkdir -p ${BUILDROOT}/usr
	cp -R ${SRCTOP}/Libraries/libmalloc/include ${BUILDROOT}/usr/

copyfile.h: .PHONY
	mkdir -p ${BUILDROOT}/usr/include
	cp -fv ${CONTRIB}/copyfile/copyfile.h ${BUILDROOT}/usr/include/

architecture: .PHONY
	SRCROOT=${SRCTOP}/contrib/architecture DSTROOT=${BUILDROOT} \
		${GMAKE} -C contrib/architecture

libfirehose_kernel: CarbonHeaders xnu_headers
	mkdir -pv ${BUILDROOT}/usr/include
	cp -fv ${SRCTOP}/Libraries/Libc/include/limits.h ${BUILDROOT}/usr/include/
	mkdir -pv ${OBJTOP}/Kernel/libfirehose_kernel
	export PATH PLATFORM=MacOSX; \
		cd ${OBJTOP}/Kernel/libfirehose_kernel; cmake -Wno-dev \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
		-DSRCTOP=${SRCTOP} -DOBJTOP=${OBJTOP} \
		-G"Unix Makefiles" ${SRCTOP}/Kernel/libfirehose_kernel
	export PATH PLATFORM=MacOSX MAKEFLAGS="" MAKE=${GMAKE}; \
		${GMAKE} DESTDIR=${BUILDROOT} -C ${OBJTOP}/Kernel/libfirehose_kernel


xnu_headers:
	mkdir -pv ${OBJTOP}/Kernel/xnu
	export PATH PLATFORM=MacOSX; \
	${GMAKE} -C ${SRCTOP}/Kernel/xnu MAKE=${GMAKE} \
		ARCH_CONFIGS=X86_64 BUILD_LTO=0 \
		AVAILABILITY_PL_PATH=${SRCTOP}/Kernel/availability.pl \
		BUILD_WERROR=0 DO_CTFMERGE=0 KERNEL_CONFIGS=RELEASE \
		SRCROOT=${SRCTOP}/Kernel/xnu OBJROOT=${OBJTOP}/Kernel/xnu \
		DSTROOT=${BUILDROOT} CODESIGN_ALLOCATE=${CODESIGN_ALLOCATE} \
		CTFCONVERT=${CTFCONVERT} CTFMERGE=${CTFMERGE} CTFINSERT=${CTFINSERT} \
		IIG=${IIG} MIG=${MIG} MIGCOM=${MIGCOM} STRIP=${STRIP} LIPO=${LIPO} NM=${NM} \
		NMEDIT=${NMEDIT} LIBTOOL=${LIBTOOL} UNIFDEF=${UNIFDEF} \
		DSYMUTIL=${DSYMUTIL} XCRUN=${XCRUN} XCBUILD=${XCBUILD} installhdrs

kernel: libfirehose_kernel
	export PATH PLATFORM=MacOSX; \
	${GMAKE} -C ${SRCTOP}/Kernel/xnu MAKE=${GMAKE} \
		ARCH_CONFIGS=X86_64 BUILD_LTO=0 \
		AVAILABILITY_PL_PATH=${SRCTOP}/Kernel/availability.pl \
		BUILD_WERROR=0 DO_CTFMERGE=0 KERNEL_CONFIGS=RELEASE \
		SRCROOT=${SRCTOP}/Kernel/xnu OBJROOT=${OBJTOP}/Kernel/xnu \
		DSTROOT=${BUILDROOT} CODESIGN_ALLOCATE=${CODESIGN_ALLOCATE} \
		CTFCONVERT=${CTFCONVERT} CTFMERGE=${CTFMERGE} CTFINSERT=${CTFINSERT} \
		IIG=${IIG} MIG=${MIG} MIGCOM=${MIGCOM} STRIP=${STRIP} LIPO=${LIPO} NM=${NM} \
		NMEDIT=${NMEDIT} LIBTOOL=${LIBTOOL} UNIFDEF=${UNIFDEF} \
		DSYMUTIL=${DSYMUTIL} XCRUN=${XCRUN} XCBUILD=${XCBUILD}

libkmod: xnu_headers
	mkdir -pv ${OBJTOP}/Kernel/libkmod/include/pthread
	cp -fv ${SRCTOP}/Libraries/libpthread/private/{spinlock,tsd}_private.h \
		${OBJTOP}/Kernel/libkmod/include/pthread/
	cp -fv ${SRCTOP}/Libraries/Libc/locale/FreeBSD/{collate,lmessages,lmonetary,lnumeric,setlocale}.h \
		${OBJTOP}/Kernel/libkmod/include/
	cp -fv ${SRCTOP}/Libraries/Libc/stdtime/FreeBSD/timelocal.h \
		${OBJTOP}/Kernel/libkmod/include/
	ln -sfv B ${OBJTOP}/release/System/Library/Frameworks/System.framework/Versions/Current
	ln -sfv Versions/Current/Headers \
		${OBJTOP}/release/System/Library/Frameworks/System.framework/Headers
	ln -sfv Versions/Current/PrivateHeaders \
		${OBJTOP}/release/System/Library/Frameworks/System.framework/PrivateHeaders
	mkdir -pv ${BUILDROOT}/usr/include/os
	cp -fv ${CONTRIB}/os/availability.h ${BUILDROOT}/usr/include/os
	cmake -Wno-dev -DCMAKE_INSTALL_PREFIX=/ -DCMAKE_BUILD_TYPE=Release \
		-DSRCTOP=${SRCTOP} -DOBJTOP=${OBJTOP} \
		-G"Unix Makefiles" ${SRCTOP}/Kernel/libkmod
	export PATH PLATFORM=MacOSX MAKEFLAGS="" MAKE=${GMAKE}; \
		${GMAKE} DESTDIR=${BUILDROOT} -C ${OBJTOP}/Kernel/libkmod

kext: libkmod
	mkdir -pv ${OBJTOP}/Kernel/Extensions/include/pthread
	cp -fv ${SRCTOP}/Libraries/libpthread/private/qos_private.h \
		${OBJTOP}/Kernel/Extensions/include/pthread/
	cd ${OBJTOP}/Kernel/Extensions; cmake -Wno-dev \
		-DCMAKE_INSTALL_PREFIX=/System/Library/Extensions \
		-DCMAKE_BUILD_TYPE=Release -DSRCTOP=${SRCTOP} -DOBJTOP=${OBJTOP} \
		-G"Unix Makefiles" ${SRCTOP}/Kernel/Extensions
	export PATH PLATFORM=MacOSX MAKEFLAGS="" MAKE=${GMAKE}; \
		${GMAKE} DESTDIR=${BUILDROOT} -C ${OBJTOP}/Kernel/Extensions


