# The Darwin branch used to `touch` a 0-byte ${RAVYN_SDKROOT}/usr/lib/
# libncurses.dylib and libncurses.6.dylib. That is the same defect that
# destroyed libCrashReporterClient (see Libraries/check_sdk_stubs.sh, which
# exists because of it) and the same one the sibling libedit/ and libutil/
# Makefiles already had removed: `touch` on a populated tree is invisible,
# because it does not even truncate, but in a fresh or wiped tree it CREATES
# a zero-byte dylib -- and unlike a zero-byte .a, which ld64 rejects outright,
# a zero-byte dylib LINKS and LOADS. Anything reaching it gets a silent no-op.
#
# It must never touch again. The real build is the .else branch, which runs
# ncurses' own configure and gmake; this branch cannot fake it, and the one
# thing it must not do is pretend it did. So it fails loudly instead, naming
# the real prerequisite -- exactly the tradeoff Libraries/require_real_archive.sh
# makes for libcxx and compiler-rt.
#
# Nothing in the current closure needs these: measured 2026-10-02, zero
# LC_LOAD_DYLIB references to libncurses.dylib or libncurses.6.dylib exist
# anywhere in the SDK or the staged bootlab closure. (The one reference in the
# tree, assets/bin/ls -> /usr/lib/libncurses.5.4.dylib, is a THIRD name that
# neither stub ever provided, and that file is not in the clean closure.)
.if "${.MAKE.OS}" == "Darwin"
all:
	@echo "FATAL: BSD/lib/ncurses was not built." >&2
	@echo "       This target no longer touches 0-byte stub dylibs into" >&2
	@echo "       \$$RAVYN_SDKROOT/usr/lib. A 0-byte dylib links and loads" >&2
	@echo "       but does nothing, which is a silent failure at run time." >&2
	@echo "       Build it for real -- the .else branch below runs ncurses'" >&2
	@echo "       own configure and gmake -- or, if nothing links -lncurses," >&2
	@echo "       drop ncurses from the SUBDIR list in BSD/lib/Makefile." >&2
	@echo "       A loud failure here beats a silent stub. See" >&2
	@echo "       Libraries/check_sdk_stubs.sh." >&2
	@false
.else
all: ${.OBJDIR}/lib/libncurses.6.dylib
	CFLAGS="--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN}" \
	CXXFLAGS="--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN}" \
	LDFLAGS="--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} -fuse-ld=${LD}" \
	${.CURDIR}/configure --prefix=/usr \
        --sysconfdir=/private/etc \
        --localstatedir=/private/var \
        --target=${CpuArch}-apple-darwin19 \
        --host=${CpuArch}-apple-darwin19 \
	--with-strip-program=${TOOLS}/strip \
        --without-ada --without-tests --enable-pc-files \
        --with-shared --with-normal --with-debug \
        --enable-rpath --without-dlsym --disable-lib-suffixes \
        --enable-termcap --enable-symlinks --enable-ext-colors \
        --enable-rgb-color --with-pthread --enable-pthreads-eintr \
        --enable-reentrant
	MAKEFLAGS="" ${TOOLS}/gmake
	MAKEFLAGS="" ${TOOLS}/gmake install DESTDIR=${RAVYN_SDKROOT}
	MAKEFLAGS="" ${TOOLS}/gmake install DESTDIR=${SYSROOT_DIR}
	ln -sf ${CpuArch}-apple-darwin19-${prog} ${SYSROOT_DIR}/usr/bin/${prog}
.endif
