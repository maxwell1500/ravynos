MK_WERROR = no
LIB = bz2

MAJOR = 1
MINOR = 0
PATCH = 5

SRCS = ./src/blocksort.c \
	./src/bzlib.c \
	./src/compress.c \
	./src/crctable.c \
	./src/decompress.c \
	./src/huffman.c \
	./src/randtable.c

.if "${CpuArch}" == "aarch64"
SRCS +=	./src/arm64/crc32vec.s
.elif "${CpuArch}" == "x86_64"
SRCS +=	./src/x86_64/crc32vec.s
.else
.error Unsupported CPU architecture ${CpuArch}
.endif

MAJMIN = ${MAJOR}.${MINOR}
VERSION = ${MAJOR}.${MINOR}.${PATCH}

CFLAGS += --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -I${.CURDIR}/src -Wno-nullability-completeness
ACFLAGS += --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN}
LDFLAGS += --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -Wl,-unexported_symbols_list,${.CURDIR}/unexports -fuse-ld=${LD} -lSystem
PROG_LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -fuse-ld=${LD} -L${.OBJDIR} -lbz2 -lSystem -Wl,-undefined,dynamic_lookup

SUBDIR =
MAN = src/bzip2.1
MLINKS = src/bzip2.1 bunzip2.1 bzcat.1 bzip2recover.1
MLINKS += src/bzdiff.1 bzcmp.1
MLINKS += src/bzmore.1 bzless.1

all: lib${LIB}.${MAJMIN}.dylib bzip2 bzip2recover bzdiff bzmore
bzip2: ${.CURDIR}/src/bzip2.c
	mkdir -p ${SYSROOT_DIR}/usr/bin
	${CC} ${CFLAGS} -o ${.TARGET}.o -c ${.CURDIR}/src/bzip2.c
	${CC} ${PROG_LDFLAGS} -o ${SYSROOT_DIR}/usr/bin/${.TARGET} bzip2.o
	ln -f ${SYSROOT_DIR}/usr/bin/bzip2 ${SYSROOT_DIR}/usr/bin/bunzip2
	ln -f ${SYSROOT_DIR}/usr/bin/bzip2 ${SYSROOT_DIR}/usr/bin/bzcat

bzdiff: ${.CURDIR}/src/bzdiff
	mkdir -p ${SYSROOT_DIR}/usr/bin
	cp -f ${.ALLSRC} ${SYSROOT_DIR}/usr/bin/${.TARGET}
	chmod +x ${SYSROOT_DIR}/usr/bin/bzdiff
	ln -sf bzdiff ${SYSROOT_DIR}/usr/bin/bzcmp

bzmore: ${.CURDIR}/src/bzmore
	mkdir -p ${SYSROOT_DIR}/usr/bin
	cp -f ${.ALLSRC} ${SYSROOT_DIR}/usr/bin/${.TARGET}
	chmod +x ${SYSROOT_DIR}/usr/bin/bzmore
	ln -sf bzmore ${SYSROOT_DIR}/usr/bin/bzless

bzip2recover: ${.CURDIR}/src/bzip2recover.c
	${CC} ${CFLAGS} -o ${.TARGET}.o -c ${.CURDIR}/src/bzip2recover.c
	${CC} ${PROG_LDFLAGS} -o ${SYSROOT_DIR}/usr/bin/${.TARGET} \
	    ${.CURDIR}/src/bzip2recover.c

# The Darwin branch of this Makefile used to `touch` a 0-byte libbz2.a and
# libbz2.dylib.  A zero-byte dylib links and loads and then does nothing, which
# is how a client that records /usr/lib/libbz2.1.0.dylib (Chrome, Blender, VLC)
# ends up with silent failures instead of a load error.  It also left
# compatibility_version at 0.0.0, which dyld2 rejects for a client that
# requests 1.0.0.  Both are fixed here: the archive is built by bsd.lib.mk on
# every host, and the dylib carries Apple's versioned name and ABI versions.
LIBBZ2 = lib${LIB}.${MAJMIN}.dylib

${LIBBZ2}: lib${LIB}.a
	${CC} -shared -dylib -o ${.TARGET} \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a -nodefaultlibs \
	  -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/${LIBBZ2} \
	  -Wl,-current_version,${VERSION} -Wl,-compatibility_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include"; \
	  cp -f ${.OBJDIR}/lib${LIB}.a "$$sdk/usr/lib/lib${LIB}.a"; \
	  cp -f ${.TARGET} "$$sdk/usr/lib/${LIBBZ2}"; \
	  ln -sf ${LIBBZ2} "$$sdk/usr/lib/lib${LIB}.dylib"; \
	  ln -sf ${LIBBZ2} "$$sdk/usr/lib/lib${LIB}.${VERSION}.dylib"; \
	  cp -f ${.CURDIR}/src/bzlib.h "$$sdk/usr/include/bzlib.h"; \
	done

.include <bsd.lib.mk>

