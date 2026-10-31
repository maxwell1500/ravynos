ROOT_SOURCE_DIR ?= ${.CURDIR}/../../..
HOST_CC ?= /usr/bin/clang
HOST_CXX ?= /usr/bin/clang++
CC := ${HOST_CC}
CXX := ${HOST_CXX}
BUILD_DIR ?= ${RAVYN_BUILD_DIR:U/Users/max/Projects/build}
TOOLCHAIN := ${BUILD_DIR}/Developer/Platforms/ravynOS.platform/Developer/Toolchains/Default.xctoolchain
TOOLS := ${TOOLCHAIN}/usr/bin

.PATH: ${.CURDIR} ${ROOT_SOURCE_DIR}/Kernel/IOKitUser

SRCS =	plktool.c \
	macho.c \
	kext.c \
	IOCFSerialize.c
OBJS = ${SRCS:%.c=%.o}

.if "${.MAKE.OS}" == "Darwin"
CFLAGS = -I${ROOT_SOURCE_DIR}/Kernel/kext_tools/FILES/3rd \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern/libkern \
	-I${ROOT_SOURCE_DIR}/Kernel/IOKitUser/kext.subproj \
	-I${ROOT_SOURCE_DIR}/Kernel/IOKitUser \
	-D__APPLE_CPP__ -D__LITTLE_ENDIAN__ -DPRIVATE=1 -w -g -O2

LDFLAGS = -L${TOOLCHAIN}/usr/lib \
	  -lkxld -framework CoreFoundation -lz
all: ${TOOLS}/plktool

${TOOLCHAIN}/usr/lib/libkxld.a: .PHONY
	mkdir -p ${TOOLCHAIN}/usr/lib /tmp/kxld_obj
	for f in kxld.c kxld_array.c kxld_copyright.c kxld_demangle.c kxld_dict.c \
	  kxld_kext.c kxld_object.c kxld_reloc.c kxld_sect.c kxld_seg.c \
	  kxld_srcversion.c kxld_splitinfolc.c kxld_sym.c kxld_symtab.c \
	  kxld_util.c kxld_uuid.c kxld_vtable.c kxld_versionmin.c; do \
	  ${CC} -arch x86_64 -O2 -c ${ROOT_SOURCE_DIR}/Kernel/xnu/libkern/kxld/$$f \
	    -I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern/kxld \
	    -I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
	    -I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern/libkern \
	    -I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk \
	    -I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
	    -DPRIVATE=1 -Wno-deprecated-declarations -Wno-availability \
	    -o /tmp/kxld_obj/$${f%.c}.o || exit 1; \
	done
	ar rcs ${TOOLCHAIN}/usr/lib/libkxld.a /tmp/kxld_obj/*.o
	rm -rf /tmp/kxld_obj
IOCFSerialize.o: ${ROOT_SOURCE_DIR}/Kernel/IOKitUser/IOCFSerialize.c
	mkdir -p /tmp/plk_inc/System/libkern
	ln -sf ${ROOT_SOURCE_DIR}/Kernel/xnu/libkern/libkern/OSSerializeBinary.h /tmp/plk_inc/System/libkern/OSSerializeBinary.h
	${CC} -I/tmp/plk_inc ${CFLAGS} -c ${.ALLSRC} -o ${.TARGET}

${TOOLS}/plktool: ${TOOLCHAIN}/usr/lib/libkxld.a ${OBJS} ${.CURDIR}/Makefile
	mkdir -p ${TOOLS}
	${HOST_CXX} -arch x86_64 -o ${.TARGET} ${OBJS} ${LDFLAGS}

.elif "${.MAKE.OS}" == "Linux"
LDFLAGS = -L${TOOLCHAIN}/usr/lib \
	  -lkxld -lmacho -lstuff -lCoreFoundation -luuid -lssl -lcrypto \
	  -lz -lbsd 
all: ${TOOLS}/plktool

${TOOLCHAIN}/usr/lib/libkxld.a: .PHONY
	${MAKE} -C ${ROOT_SOURCE_DIR}/Kernel/xnu/libkern/kxld all

${TOOLS}/plktool: ${TOOLCHAIN}/usr/lib/libkxld.a ${OBJS} ${.CURDIR}/Makefile
	${HOST_CXX} -o ${.TARGET} ${OBJS} ${LDFLAGS}
.else
all: .PHONY
${TOOLS}/plktool: .PHONY
.endif

