# /usr/lib/libcurl.4.dylib.  See curl.c for the covered surface: HTTP/1.1
# over BSD sockets, easy + multi, chunked and Content-Length bodies.
MK_WERROR=	no
SRCS=		curl.c
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${.CURDIR} -Wno-unused-parameter -Wno-sign-conversion

all: libcurl.4.dylib

curl.o: curl.c curl.h
	${CC} ${CFLAGS} -c -o ${.OBJDIR}/curl.o ${.CURDIR}/curl.c

libcurl.4.dylib: ${.OBJDIR}/curl.o
	${CC} -shared -dylib -o ${.OBJDIR}/$@ ${.OBJDIR}/curl.o \
	  -nodefaultlibs -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libcurl.4.dylib \
	  -Wl,-compatibility_version,7.0.0 -Wl,-current_version,9.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include/curl"; \
	  cp -f ${.OBJDIR}/libcurl.4.dylib "$$sdk/usr/lib/libcurl.4.dylib"; \
	  ln -sf libcurl.4.dylib "$$sdk/usr/lib/libcurl.dylib"; \
	  cp -f ${.CURDIR}/curl.h "$$sdk/usr/include/curl/curl.h"; \
	done
