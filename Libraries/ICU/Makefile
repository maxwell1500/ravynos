MK_WERROR = no
GMAKE ?= gmake

CFLAGS =--sysroot=${RAVYN_SDKROOT} -fuse-ld=${LD} \
	-mmacos-version-min=${MACOS_VERSION_MIN}
CXXFLAGS =-std=gnu++17 --sysroot=${RAVYN_SDKROOT} -fuse-ld=${LD} \
	-mmacos-version-min=${MACOS_VERSION_MIN}
# Flags that belong on the link of the ICU-derived dylibs ONLY, and must never
# reach configure.  -licudata names the data library this very build has not
# produced yet, and autoconf appends LDFLAGS to the line of its "can this
# compiler make an executable" probe, so configure dies before compiling a
# single ICU source:
#   configure:3528: .../isysroot-cc ... conftest.c
#   ld: library 'icudata' not found
#   configure: error: C compiler cannot create executables
# The two flag sets are therefore separate variables, and only the final
# libicucore link below uses this one.  -L is needed because the object tree is
# not on ld64's default search path.
ICU_LINK_FLAGS =-L${.OBJDIR}/target/lib -licudata -lc++

# The compiler-rt archive, when it has actually been built.  The path is
# unconditional in this Makefile (and in CoreFoundation's), but the file is a
# 0-byte placeholder until Libraries/llvm_target/compiler-rt is built, and
# ld64 rejects an empty archive outright rather than ignoring it:
#   ld: file is empty in
#     .../Libraries/llvm_target/compiler-rt/lib/ravynos/libclang_rt.osx.a
# So the archive is passed only when it has content.  Nothing is lost when it
# is absent: this link carries -undefined dynamic_lookup, so a runtime symbol
# the compiler emits would be resolved at load time regardless, and the
# placeholder never had any to contribute.
CLANGRT_OSX_A =${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Libraries/llvm_target/compiler-rt/lib/ravynos/libclang_rt.osx.a
CLANGRT_OSX_A !=test -s ${CLANGRT_OSX_A} && echo ${CLANGRT_OSX_A}
.if !empty(CLANGRT_OSX_A)
ICU_LINK_FLAGS += ${CLANGRT_OSX_A}
.endif
LDFLAGS =--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-fuse-ld=${LD}
# ld64 refuses to emit a dylib that links neither libSystem nor libdyld
# ("dynamic executables or dylibs must link with libSystem.dylib"), which is
# exactly how ICU's own libicudata link died once the build got that far.  The
# explicit -L is required because ld64 does not search
# <sysroot>/usr/lib/system by default.  Same remedy, and same reason, as
# BSD/share/mk/rvn.framework.mk; the SDK's libSystem.B.dylib is assembled FROM
# the Libraries sub-dylibs, so linking it here would be circular.
LDFLAGS += -L${RAVYN_SDKROOT}/usr/lib/system -ldyld

# Without this the whole ICU build -- a few thousand objects plus configure --
# lands in the source tree at Libraries/ICU/target.  Inert unless MK_AUTO_OBJ
# is set, so an ordinary `bmake` here behaves exactly as before.
.include <auto.obj.mk>

EXTRA_FLAGS = --prefix=/usr --localstatedir=/var --sysconfdir=/etc

# The sample, test, extra and tool programs are HOST executables, not part of
# the ICU libraries.  They are compiled with the same compiler as everything
# else, so with the ravynOS sysroot on the command line they come out as
# ravynOS Mach-O and then fail to link -- nothing in the SDK links a host
# program, and libc++'s runtime symbols (__gxx_personality_v0,
# ___clang_call_terminate) are not there either:
#   ld: symbol(s) not found for architecture x86_64
#     ___clang_call_terminate in makeconv.o
#   gmake[3]: *** [Makefile:81: ../../bin/makeconv] Error 1
# --disable-tools is configure's own switch for this (configure.ac:957).  The
# native build below keeps its tools, because that is where the answers for the
# target's run-tests come from.
EXTRA_FLAGS += --disable-samples --disable-tests --disable-extras \
	--disable-tools

# ---------------------------------------------------------------------------
# This build ALWAYS cross-compiles -- on a Darwin host exactly as much as on any
# other.  "Host" here means the machine running configure, which is macOS,
# while every compiler invocation below is pointed at the ravynOS sysroot, so
# what it produces are ravynOS Mach-O images.  The `.MAKE.OS != "Darwin"` guard
# this replaces assumed those were the same thing.
#
# It matters because autoconf answers most questions by COMPILING A PROGRAM AND
# RUNNING IT, and a ravynOS binary run on macOS does not merely fail its
# feature test -- it links against the SDK's libdyld.dylib and then aborts in
# the host loader, so a passing test is reported as a failing one:
#   configure:7721: ./conftest
#   dyld[5913]: Symbol not found: _fprintf
#     Referenced from: .../Libraries/ICU/target/conftest
#     Expected in:     /usr/lib/system/libdyld.dylib
#   configure: error: There is wchar.h but the size of wchar_t is 0
# (ld64 accepted the link precisely because LDFLAGS names libdyld, which is
# what the "must link with libSystem" rule requires, and libdyld exports no
# libc symbols.)
#
# --with-cross-build is autoconf's own remedy, and ICU supports it directly: a
# native ICU is configured and built in ${.OBJDIR}/native first, and its
# answers are then handed to the target configure.  Both halves are therefore
# unconditional now.
# ---------------------------------------------------------------------------
CFG_GUESS != sh ${.CURDIR}/source/config.guess
EXTRA_FLAGS += --with-cross-build=${.OBJDIR}/native \
	--host=${CpuArch}-apple-darwin --build=${CFG_GUESS}

all: libicucore.A.dylib

lib${LIB}.a: ${.CURDIR}/Makefile
	mkdir -p ${.OBJDIR}/native
	cd ${.OBJDIR}/native; \
	  CC= CXX= CPP= CFLAGS= CXXFLAGS= CPPFLAGS= LDFLAGS= LIBS= \
	  SDKROOT= MAKEFLAGS="" MAKELEVEL= \
	  ${.CURDIR}/source/configure --disable-samples --disable-tests \
	    --disable-extras \
	  && MAKEFLAGS="" ${GMAKE}
	mkdir -p ${.OBJDIR}/target
	cd ${.OBJDIR}/target; ICU_CROSS_BUILD=1 SDKROOT=${RAVYN_SDKROOT} \
	  CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" LDFLAGS="${LDFLAGS}" \
	  CC=${CC} CXX=${CXX} LD=${LD} AR=${AR} STRIP=${STRIP} MAKEFLAGS="" \
	  ${.CURDIR}/source/runConfigureICU MacOSX ${EXTRA_FLAGS}
	# TOOLS= is load-bearing.  ICU's own generated Makefile defines its tools
	# subdirectory as
	#   #TOOLS = tools
	#   SUBDIRS = stubdata common i18n ... $(TOOLS) ...
	# i.e. --disable-tools comments the assignment out rather than setting it
	# empty, so $(TOOLS) falls through to the ENVIRONMENT.  build-libraries.sh
	# exports TOOLS as its bin directory of tool symlinks, and gmake then
	# recurses into it as if it were a source subdirectory:
	#   gmake[2]: Entering directory '/Users/max/Projects/build/Tools/bin'
	#   gmake[2]: *** No rule to make target 'all'.  Stop.
	MAKEFLAGS="" TOOLS= ${GMAKE} -C ${.OBJDIR}/target

libicucore.A.dylib: lib${LIB}.a
	${TOOLS}/install_name_tool -id /usr/lib/libicudata.dylib \
	  ${.OBJDIR}/target/lib/libicudata.dylib
	${CC} -v -o ${.TARGET} -shared -dylib -Wl,-all_load \
	  -Wl,-install_name,/usr/lib/${.TARGET} \
	  -Wl,-current_version,78.3 -Wl,-compatibility_version,1 \
	  $$(find ${.OBJDIR}/target/common ${.OBJDIR}/target/i18n \
	  ${.OBJDIR}/target/io -name '*.o') ${LDFLAGS} ${ICU_LINK_FLAGS}
	# ravynOS: RAVYN_REPO_SDKROOT is the in-repo SDK that
# tools/bootlab/make_gui_manifest.py stages from and PREFERS over the build
# tree. It is distinct from RAVYN_SDKROOT/SYSROOT_DIR, which build-libraries.sh:78
# sets to the SAME build-tree path -- so the loop below iterated the build tree
# twice and never touched the SDK the image actually stages from.
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	mkdir -p ${dir}/usr/lib ${dir}/usr/include
	cp -fp ${.OBJDIR}/${.TARGET} ${dir}/usr/lib/
	ln -sf ${.TARGET} ${dir}/usr/lib/libicucore.dylib
	# "d" is a GNU coreutils spelling of -R --no-dereference; BSD cp, which is
	# what this host has, does not have it:
	#   cp: illegal option -- d
	# -p is already here and preserves mode, ownership and timestamps, which is
	# everything this copy of the data library needs.
	cp -fp ${.OBJDIR}/target/lib/libicudata* ${dir}/usr/lib/
	cp -Rfp ${.CURDIR}/source/i18n/unicode ${.CURDIR}/source/i18n/*.h \
	  ${dir}/usr/include
.endfor
