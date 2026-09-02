.if "${.MAKE.OS}" == "Darwin"
all:
	@echo "stub ncurses for Darwin host"
	mkdir -p ${RAVYN_SDKROOT}/usr/lib ${SYSROOT_DIR}/usr/lib ${RAVYN_SDKROOT}/usr/bin ${SYSROOT_DIR}/usr/bin
	touch ${RAVYN_SDKROOT}/usr/lib/libncurses.dylib ${SYSROOT_DIR}/usr/lib/libncurses.dylib
	touch ${RAVYN_SDKROOT}/usr/lib/libncurses.6.dylib ${SYSROOT_DIR}/usr/lib/libncurses.6.dylib
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
.endfor
.endif
