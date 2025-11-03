
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
			${SRCTOP}/Library/SystemVersion.plist.in | \
			tail -1 | sed -e 's/<\/*string>//'
RAVYNOS_CODENAME!= grep -A1 ProductFamily \
			${SRCTOP}/Library/SystemVersion.plist.in | \
			tail -1 | sed -e 's/<\/*string>//'
.ifndef CORES
.if ${OSNAME} == Linux
CORES!=		grep -c ^processor /proc/cpuinfo
.else
CORES!=		sysctl -n hw.ncpu
.endif
.endif

DESTDIR=
.export DESTDIR SRCTOP OBJTOP BUILDROOT RAVYNOS_VERSION RAVYNOS_CODENAME CORES

.if ${OSNAME} == Darwin
SDKROOT?=	/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
.export SDKROOT
.endif

MK_WERROR=      no
WARNS=          1
BMAKE?=		bmake
GMAKE?=		gmake

.if "${CIRRUS_CI}"
SHA!= echo ${CIRRUS_CHANGE_IN_REPO}|cut -c1-7|tr '[a-z]' '[A-Z]'
.else
SHA!= cd ${.CURDIR} && git log -1|head -1|cut -c8-14|tr '[a-z]' '[A-Z]'
.endif

.include <rvn.common.mk>

_BOOTSTRAP?=		_bootstrap-clang _bootstrap-xcbuild \
			_bootstrap-cctools _bootstrap-mig
_BOOTSTRAP_OBJDIRS=	${_BOOTSTRAP:S/-/\//:C/^.*$$/${OBJTOP}\/&/}

${_BOOTSTRAP_OBJDIRS}:
.for d in ${.TARGET}
	mkdir -pv ${d}
.endfor

buildworld: _bootstrap
buildkernel: kernel

# ------------------------------------------------------------------------
#                           BOOTSTRAP TARGETS
#  These targets are used to build the host toolchain that will be used
#  to build everything else
# ------------------------------------------------------------------------
_bootstrap: 	${_BOOTSTRAP_OBJDIRS} \
		${OBJTOOLS} ${BUILDROOT} \
		.WAIT \
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

${BUILDROOT}/System/Library/SystemVersion.plist: ${.CURDIR}/Library/SystemVersion.plist.in
	sed -e 's/BUILD_STAMP/${SHA}/' <${.ALLSRC} >${.TARGET}

${OBJTOOLS}: .EXEC
	mkdir -pv ${OBJTOOLS}

${BUILDROOT}: .EXEC
	mkdir -pv ${BUILDROOT}/System/Library


# ------------------------------------------------------------------------
#                               OS TARGETS
#  These targets are used to build the ravynOS components
# ------------------------------------------------------------------------

kernel: .PHONY
	mkdir -pv ${OBJTOP}/Kernel
	cd ${OBJTOP}/Kernel; export PATH="${OBJTOOLS}/usr/bin:${PATH}" \
		PLATFORM=MacOSX; \
		cmake -Wno-dev -DCMAKE_INSTALL_PREFIX=/usr \
		-DSRCTOP=${SRCTOP} -DOBJTOOLS=${OBJTOOLS} -DMAKE=${GMAKE} \
		-DCMAKE_BUILD_TYPE=Debug -G"Unix Makefiles" \
		${SRCTOP}/Kernel && VERBOSE=1 \
		MAKE=${GMAKE} MAKEFLAGS="-DVERBOSE" ${GMAKE} -C ${OBJTOP}/Kernel