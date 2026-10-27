# /usr/lib/libiconv.2.dylib and /usr/lib/libcharset.1.dylib.
#
# macOS clients record libiconv.2 at compatibility 7.0.0 (GNU libiconv's ABI
# since 2009) and libcharset.1 at 2.0.0.  Neither existed here, which is why
# Transmission, Blender and VLC failed at load time.  The implementation in
# iconv.c covers the encodings applications actually use directly and hands
# the rest to ICU's converter engine.
MK_WERROR=	no
SRCS=		iconv.c
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${.CURDIR} -Wno-unused-function -Wno-sign-conversion

all: libiconv.2.dylib libcharset.1.dylib

iconv.o: iconv.c iconv.h
	${CC} ${CFLAGS} -c -o ${.OBJDIR}/iconv.o ${.CURDIR}/iconv.c

charset.o: charset.c localcharset.h
	${CC} ${CFLAGS} -c -o ${.OBJDIR}/charset.o ${.CURDIR}/charset.c

libiconv.2.dylib: ${.OBJDIR}/iconv.o
	${CC} -shared -dylib -o ${.OBJDIR}/$@ ${.OBJDIR}/iconv.o \
	  -nodefaultlibs -undefined dynamic_lookup \
	  -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libiconv.2.dylib \
	  -Wl,-compatibility_version,7.0.0 -Wl,-current_version,8.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include"; \
	  cp -f ${.OBJDIR}/libiconv.2.dylib "$$sdk/usr/lib/libiconv.2.dylib"; \
	  ln -sf libiconv.2.dylib "$$sdk/usr/lib/libiconv.dylib"; \
	  cp -f ${.CURDIR}/iconv.h "$$sdk/usr/include/iconv.h"; \
	  cp -f ${.CURDIR}/localcharset.h "$$sdk/usr/include/localcharset.h"; \
	done

libcharset.1.dylib: ${.OBJDIR}/charset.o
	${CC} -shared -dylib -o ${.OBJDIR}/$@ ${.OBJDIR}/charset.o \
	  -nodefaultlibs -undefined dynamic_lookup \
	  -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libcharset.1.dylib \
	  -Wl,-compatibility_version,2.0.0 -Wl,-current_version,2.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib"; \
	  cp -f ${.OBJDIR}/libcharset.1.dylib "$$sdk/usr/lib/libcharset.1.dylib"; \
	  ln -sf libcharset.1.dylib "$$sdk/usr/lib/libcharset.dylib"; \
	done
