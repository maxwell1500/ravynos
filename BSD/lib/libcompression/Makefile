# /usr/lib/libcompression.dylib.  See compression.c for which algorithms are
# implemented and why the others answer COMPRESSION_STATUS_ERROR.
MK_WERROR=	no
LZVN=		${ROOT_SOURCE_DIR}/Developer/Default.xctoolchain/lzvndecode
SRCS=		compression.c ${LZVN}/lzvn_decode.c
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${.CURDIR} -I${LZVN} -I${RAVYN_SDKROOT}/usr/include \
		-Wno-unused-parameter -Wno-implicit-function-declaration

all: libcompression.dylib

${.OBJDIR}/compression.o: ${.CURDIR}/compression.c ${.CURDIR}/compression.h
	${CC} ${CFLAGS} -c -o ${.OBJDIR}/compression.o ${.CURDIR}/compression.c

${.OBJDIR}/lzvn_decode.o: ${LZVN}/lzvn_decode.c ${LZVN}/lzvn_decode.h
	${CC} ${CFLAGS} -c -o ${.OBJDIR}/lzvn_decode.o ${LZVN}/lzvn_decode.c

libcompression.dylib: ${.OBJDIR}/compression.o ${.OBJDIR}/lzvn_decode.o
	${CC} -shared -dylib -o ${.OBJDIR}/$@ ${.OBJDIR}/compression.o ${.OBJDIR}/lzvn_decode.o \
	  -nodefaultlibs -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libcompression.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib \
	  -L${RAVYN_REPO_SDKROOT}/usr/lib -lz -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include"; \
	  cp -f ${.OBJDIR}/libcompression.dylib "$$sdk/usr/lib/libcompression.dylib"; \
	  cp -f ${.CURDIR}/compression.h "$$sdk/usr/include/compression.h"; \
	done
