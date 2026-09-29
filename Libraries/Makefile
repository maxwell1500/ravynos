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

# Also formerly `touch`.  See the note at the libcxx target: the stub is
# removed rather than kept, so an absent compiler-rt is a loud error instead of
# a zero-byte archive.  libcc_kext.a in particular is a KERNEL-side runtime and
# a 0-byte one there is indistinguishable from a successful build.
runtime:
	mkdir -p ${RAVYN_SDKROOT}/usr/lib
	mkdir -p ${RAVYN_SDKROOT}/usr/local/lib/kernel
	@sh ${.CURDIR}/require_real_archive.sh \
		${RAVYN_SDKROOT}/usr/lib/libclang_rt.osx.a compiler-rt
	@echo "verified real compiler-rt archive"
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

# This recipe USED to be:
#       touch ${RAVYN_SDKROOT}/usr/lib/libunwind.a
#       @echo "stubbed libunwind for Darwin host"
# which is the defect this project exists to eliminate, in its load-bearing
# form.  `touch` does not truncate an existing file, so it looked harmless
# against a populated tree -- but in a FRESH or wiped build tree it creates a
# ZERO-BYTE archive, and ld64 accepts a zero-byte archive.  Nothing fails.
# The MH_DYLINKER links this by explicit intent (Libraries/dyld/dyld/Makefile
# `-L${RAVYN_SDKROOT}/usr/lib -lunwind`), so a wiped tree yields a loader with
# no unwinder, and six of its imports came out of this file.
#
# The source is tracked and present (Developer/Default.xctoolchain/llvm/libunwind,
# 67 files, Apache-2.0 + LLVM exception) and cmake is available, so this builds
# it for real instead.  It also FIXES a latent mismatch: the archive that had
# been sitting in the build tree was compiled when the SDK still spelled these
# three symbols with the $UNIX2003 suffix, and referenced
# _pthread_rwlock_{rd,wr}lock/unlock$UNIX2003 -- names nothing on this platform
# defines.  Rebuilt against the current SDK it emits the unsuffixed names, which
# libpthread.a does define.  Measured: UNIX2003 refs 3 -> 0.
#
# Installed only after a successful build and a non-empty result, so a failed
# build leaves the previous archive alone rather than replacing it with a stub.
LLVM_SRC_DIR = ${ROOT_SOURCE_DIR}/Developer/Default.xctoolchain/llvm
# Out-of-source, and deliberately under ROOT_BINARY_DIR rather than in the
# repo: a cmake build tree inside the source checkout is untracked noise that
# nothing ignores, and this round may not add ignore rules.
LIBUNWIND_BUILD_DIR = ${ROOT_BINARY_DIR}/libunwind_build
LIBUNWIND_INSTALLED = ${RAVYN_SDKROOT}/usr/lib/libunwind.a

libunwind: runtime
	@mkdir -p ${RAVYN_SDKROOT}/usr/lib ${LIBUNWIND_BUILD_DIR}
	@if [ ! -f ${LLVM_SRC_DIR}/libunwind/CMakeLists.txt ]; then \
		echo "FATAL: libunwind source missing at ${LLVM_SRC_DIR}/libunwind" >&2; \
		echo "       (previously this target wrote a 0-byte stub here, which" >&2; \
		echo "        ld64 accepts -- failing loudly instead)" >&2; \
		exit 1; \
	fi
	cmake -S ${LLVM_SRC_DIR}/libunwind -B ${LIBUNWIND_BUILD_DIR} -G Ninja \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_OSX_ARCHITECTURES=${CpuArch} \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOS_VERSION_MIN} \
		-DCMAKE_C_COMPILER=$${CC:-clang} -DCMAKE_CXX_COMPILER=$${CXX:-clang++} \
		-DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON \
		-DLIBUNWIND_ENABLE_TESTS=OFF -DLIBUNWIND_INCLUDE_TESTS=OFF \
		-DLIBUNWIND_INCLUDE_BENCHMARKS=OFF
	cmake --build ${LIBUNWIND_BUILD_DIR} -j 4
	@if [ ! -s ${LIBUNWIND_BUILD_DIR}/lib/libunwind.a ]; then \
		echo "FATAL: libunwind build produced no archive" >&2; exit 1; \
	fi
	cp -f ${LIBUNWIND_BUILD_DIR}/lib/libunwind.a ${LIBUNWIND_INSTALLED}
	@mkdir -p ${.OBJDIR}/../llvm_target/libunwind/lib
	@cp -f ${LIBUNWIND_BUILD_DIR}/lib/libunwind.a ${.OBJDIR}/../llvm_target/libunwind/lib/libunwind.a

	@echo "built libunwind.a from tracked source -> ${LIBUNWIND_INSTALLED}"
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

# These two used to `touch` their outputs too.  Same defect as libunwind above,
# and it is NOT fixed here: a real libc++ / compiler-rt build against a custom
# ravynOS target is a substantially larger job than libunwind was, and
# half-done is worse than loud.  So the stub is REMOVED rather than kept, and a
# missing archive is now an error naming its real prerequisite instead of a
# zero-byte file that ld64 silently accepts.
#
# The MH_DYLINKER links -lc++ -lc++abi by explicit intent
# (Libraries/dyld/dyld/Makefile), so these are load-bearing, not cosmetic.
libcxx: libunwind
	@mkdir -p ${RAVYN_SDKROOT}/usr/lib
	@sh ${.CURDIR}/require_real_archive.sh ${RAVYN_SDKROOT}/usr/lib/libc++.a libcxx
	@sh ${.CURDIR}/require_real_archive.sh ${RAVYN_SDKROOT}/usr/lib/libc++abi.a libcxxabi
	@echo "verified real libc++.a / libc++abi.a"
RTOBJ = ${.OBJDIR}/llvm_target/compiler-rt/lib/ravynos/libclang_rt.osx.a
compiler_rt: runtime libunwind libcxx
	@mkdir -p ${RTLIB:H} ${RTOBJ:H} ${RTLIB2:H}
	@sh ${.CURDIR}/require_real_archive.sh ${RTOBJ} compiler-rt
	@echo "verified real compiler-rt archive"

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
