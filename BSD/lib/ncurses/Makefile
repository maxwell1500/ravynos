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
# Darwin-host build: ncurses' own configure and gmake, with the ravynOS
# compiler.  The previous branch touched zero-byte stubs; this one produces a
# real libncurses.6.dylib (ncurses 6 ABI).  It is installed under its own ABI
# name: presenting a 6.x library as libncurses.5.4.dylib would claim an ABI
# this build does not implement.
BUILD=		${.OBJDIR}/build
STAGE=		${.OBJDIR}/stage

all: ${.OBJDIR}/libncurses.6.dylib

${.OBJDIR}/libncurses.6.dylib:
	mkdir -p ${BUILD} ${STAGE}
	cd ${BUILD} && \
	  env -i PATH=$$PATH HOME=$$HOME CC=${CC} CPP="${CC} -E" CFLAGS="--sysroot=${RAVYN_SDKROOT} -arch x86_64 -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-incompatible-sysroot" \
	  /bin/sh ${.CURDIR}/configure --host=x86_64-apple-darwin --prefix=/usr \
	    --without-ada --without-tests --with-shared --without-normal \
	    --without-debug --disable-lib-suffixes --enable-termcap \
	    --enable-symlinks --with-pthread --enable-pthreads-eintr \
	    --enable-reentrant
	env -i PATH=$$PATH HOME=$$HOME ${MAKE} -C ${BUILD}
	env -i PATH=$$PATH HOME=$$HOME ${MAKE} -C ${BUILD} DESTDIR=${STAGE} install
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib"; \
	  cp -f ${BUILD}/lib/libncurses.6.dylib "$$sdk/usr/lib/libncurses.6.dylib"; \
	  ln -sf libncurses.6.dylib "$$sdk/usr/lib/libncurses.dylib"; \
	  ln -sf libncurses.6.dylib "$$sdk/usr/lib/libcurses.dylib"; \
	  cp -f ${BUILD}/lib/libtic.6.dylib "$$sdk/usr/lib/libtic.6.dylib" 2>/dev/null || true; \
	  cp -f ${BUILD}/lib/libtic.dylib "$$sdk/usr/lib/libtic.dylib" 2>/dev/null || true; \
	  mkdir -p "$$sdk/usr/include"; \
	  cp -f ${.CURDIR}/include/curses.h "$$sdk/usr/include/curses.h" 2>/dev/null || true; \
	  cp -f ${.CURDIR}/include/unctrl.h "$$sdk/usr/include/unctrl.h" 2>/dev/null || true; \
	done
	touch ${.TARGET}
