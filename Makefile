
MACHINE!=	uname -m
MACHINE_ARCH!=	uname -p
TARGET?=	${MACHINE}.${MACHINE_ARCH}
TARGET_ARCH?=	${MACHINE_ARCH}
.export MACHINE MACHINE_CPUARCH TARGET TARGET_ARCH

SRCTOP=		   ${.CURDIR}
MACTOP=		   ${SRCTOP}/_distribution-macOS
BSDTOP=		   ${SRCTOP}/_FreeBSD
CONTRIB=	   ${SRCTOP}/contrib
OBJTOP?=	   /usr/obj/ravynOS/${TARGET}
BUILDROOT=	   ${OBJTOP}/release/dist/ravynOS
RAVYNOS_VERSION!=  sed -e '1q;d' ${SRCTOP}/version.txt
RAVYNOS_CODENAME!= sed -e '2q;d' ${SRCTOP}/version.txt
.ifndef CORES
CORES!=		   sysctl -n hw.ncpu
.endif
DESTDIR=
.export DESTDIR SRCTOP OBJTOP BUILDROOT RAVYNOS_VERSION RAVYNOS_CODENAME CORES

MK_WERROR=      no
WARNS=          1
BMAKE?=		bmake
GMAKE?=		gmake

.include <rvn.common.mk>

buildworld: _bootstrap

_BOOTSTRAP_OBJDIRS=	\
			${OBJTOP}/_bootstrap/clang \
			${OBJTOP}/tmp/obj-tools

${_BOOTSTRAP_OBJDIRS}:
.for d in ${.TARGET}
	mkdir -p ${d}
.endfor

_bootstrap-clang:
	cd ${OBJTOP}/${.TARGET:S/-/\//}; \
	cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release \
		-DLLVM_ENABLE_PROJECTS='clang;lldb' \
		-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
		-DLLVM_TARGETS_TO_BUILD="X86" \
		-DLLVM_BUILD_LLVM_DYLIB=ON -DLLVM_LINK_LLVM_DYLIB=ON \
		-DLLVM_CREATE_XCODE_TOOLCHAIN=ON \
		-DLLVM_DEFAULT_TARGET_TRIPLE="${MACHINE:S/amd64/x86_64/}-apple-darwin" \
		-DLLDB_BUILD_SERVER=OFF -G "Unix Makefiles" \
		${CONTRIB}/llvm-project/llvm
	${MAKE} -C ${OBJTOP}/${.TARGET:S/-/\//} all install \
		DESTDIR=${OBJTOP}/tmp/obj-tools

_bootstrap: 	${_BOOTSTRAP_OBJDIRS} \
		.WAIT \
		_bootstrap-clang
