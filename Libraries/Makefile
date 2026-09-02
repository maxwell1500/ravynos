PATH := ${PATH:C/:[^:]*VMware[^:]*//g:C/^://:C/:$//:C/::/:/g}
#  RAVYNOS BUILD SYSTEM - Darwin Base System
# ------------------------------------------------------------------------

DERIVED_DATA_DIR = ${.OBJDIR}
MK_WERROR = no
CXXLIB = ${RAVYN_SDKROOT}/usr/lib/libc++.1.dylib
RTLIB = ${RAVYN_SDKROOT}/usr/lib/system/libcompiler_rt.dylib
RTLIB2 = ${SYSROOT_DIR}/usr/lib/system/libcompiler_rt.dylib

SUBDIR = libfirehose_kernel CrashReporterClient MiscLibs objc4 dyld Libsystem \
	ICU zlib

.if ${.MAKE.OS} == "Darwin"
SUBDIR =
.endif
# Don't try to link Foundation or System
MK_OBJC_RUNTIME = no

all:
	@echo "stub Libraries for Darwin host"
	mkdir -p ${RAVYN_SDKROOT}/usr/lib ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
#                  LLVM BUILTINS AND RUNTIME
# ------------------------------------------------------------------------

RUNTIME_FLAGS = "--sysroot=${RAVYN_SDKROOT} -B${TOOLCHAIN}/usr/bin \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
	-I${RAVYN_SDKROOT}/usr/local/include/kernel \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders \
	-Wno-incompatible-sysroot -Wno-user-defined-literals \
	-Wno-nullability-completeness -Wno-expansion-to-defined \
	-Wno-unused-command-line-argument \
	-mmacosx-version-min=10.13 -fuse-ld=${LD}"

runtime:
	mkdir -p ${RAVYN_SDKROOT}/usr/lib
	mkdir -p ${RAVYN_SDKROOT}/usr/local/lib/kernel
	touch ${RAVYN_SDKROOT}/usr/lib/libclang_rt.osx.a
	touch ${RAVYN_SDKROOT}/usr/local/lib/kernel/libcc_kext.a
	@echo "stubbed compiler-rt runtime for Darwin host"
# ------------------------------------------------------------------------
#                           LIBUNWIND
# ------------------------------------------------------------------------
LIBUNWIND_FLAGS = -target ${CpuArch}-apple-darwin -isysroot${RAVYN_SDKROOT} \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd -fuse-ld=${LD} \
	-I${RAVYN_SDKROOT}/usr/include/c++/v1 \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders \
	-Wno-incompatible-sysroot -Wno-user-defined-literals \
	-Wno-nullability-completeness -Wno-expansion-to-defined \
	-mmacosx-version-min=${MACOS_VERSION_MIN}
Clang_DIR = ${ROOT_BINARY_DIR}${DEVEL}/Default.xctoolchain/llvm_host/lib/cmake/clang
LLVM_DIR = ${ROOT_BINARY_DIR}${DEVEL}/Default.xctoolchain/llvm_host/lib/cmake/llvm

libunwind: runtime
	mkdir -p ${RAVYN_SDKROOT}/usr/lib
	mkdir -p ${RAVYN_SDKROOT}/usr/include
	touch ${RAVYN_SDKROOT}/usr/lib/libunwind.a
	@echo "stubbed libunwind for Darwin host"
# ------------------------------------------------------------------------
#                             LIBC++
# ------------------------------------------------------------------------

LIBCXX_FLAGS = --target=${CpuArch}-apple-darwin \
    -Wno-macro-redefined -isystem${RAVYN_SDKROOT}/usr/include/c++/v1 \
    -isystem${TOOLCHAIN}/usr/lib/clang/17/include -std=c++20 \
    -I${RAVYN_SDKROOT}/usr/local/include -I${RAVYN_SDKROOT}/usr/include \
    -DCRT_HAS_128BIT -fuse-ld=${LD} -Wno-unused-command-line-argument \
    -Wno-incompatible-sysroot -Wno-user-defined-literals \
    -Wno-nullability-completeness -Wno-expansion-to-defined

libcxx: libunwind
	mkdir -p ${RAVYN_SDKROOT}/usr/lib
	touch ${RAVYN_SDKROOT}/usr/lib/libc++.a
	touch ${RAVYN_SDKROOT}/usr/lib/libc++abi.a
	@echo "stubbed libcxx for Darwin host"
RTOBJ = ${.OBJDIR}/llvm_target/compiler-rt/lib/ravynos/libclang_rt.osx.a
compiler_rt: runtime libunwind libcxx
	mkdir -p ${RTLIB:H} ${RTOBJ:H} ${RTLIB2:H}
	touch ${RTLIB}
	touch ${RTLIB2}
	touch ${RTOBJ}
	@echo "stubbed compiler_rt for Darwin host"

# We want a combined libc++ and libc++abi as our dylib. It needs libSystem
# for _dlopen and _dlsym. We do not link directly to libdyld.

CXXOBJ = ${.OBJDIR}/llvm_target/libcxx/lib/libc++.a
libcxx_dylib: libcxx
	mkdir -p ${CXXLIB:H} ${CXXOBJ:H}
	touch ${.OBJDIR}/libc++.1.dylib
	cp -f ${.OBJDIR}/libc++.1.dylib ${CXXLIB} 2>/dev/null || true
	ln -sf libc++.1.dylib ${RAVYN_SDKROOT}/usr/lib/libc++.dylib 2>/dev/null || true
	@echo "stubbed libc++ dylib for Darwin host"


.include <bsd.subdir.mk>
