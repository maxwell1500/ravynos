MK_WERROR = no
LIB = icu

CFLAGS =--sysroot=${RAVYN_SDKROOT} -fuse-ld=${LD} \
	-mmacos-version-min=${MACOS_VERSION_MIN}
CXXFLAGS =-std=gnu++17 --sysroot=${RAVYN_SDKROOT} -fuse-ld=${LD} \
	-mmacos-version-min=${MACOS_VERSION_MIN}
LDFLAGS =--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN}

EXTRA_FLAGS = --prefix=/usr --localstatedir=/var --sysconfdir=/etc

.if "${.MAKE.OS}" != "Darwin"
CFG_GUESS != sh ${.CURDIR}/source/config.guess
EXTRA_FLAGS += --with-cross-build=${.OBJDIR}/native \
	--host=${CpuArch}-apple-darwin --build=${CFG_GUESS} \
	--disable-samples --disable-tests --disable-extras
.endif

all: lib${LIB}.a

lib${LIB}.a: ${.CURDIR}/Makefile
.if "${.MAKE.OS}" != "Darwin"
	mkdir -p ${.OBJDIR}/native
	cd ${.OBJDIR}/native; ${.CURDIR}/source/configure \
	  && MAKEFLAGS="" ${GMAKE}
.endif
	mkdir -p ${.OBJDIR}/target
	cd ${.OBJDIR}/target; ICU_CROSS_BUILD=1 SDKROOT=${RAVYN_SDKROOT} \
	  CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" LDFLAGS="${LDFLAGS}" \
	  CC=${CC} CXX=${CXX} LD=${LD} AR=${AR} STRIP=${STRIP} MAKEFLAGS="" \
	  ${.CURDIR}/source/runConfigureICU MacOSX ${EXTRA_FLAGS}
	MAKEFLAGS="" ${GMAKE} -C ${.OBJDIR}/target
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR}
	mkdir -p ${dir}/usr/lib ${dir}/usr/include
	cp -fvp ${.OBJDIR}/target/lib/libicu* ${dir}/usr/lib/
	cp -Rfpv ${.CURDIR}/source/i18n/unicode ${.CURDIR}/source/i18n/*.h \
	  ${dir}/usr/include
.endfor
