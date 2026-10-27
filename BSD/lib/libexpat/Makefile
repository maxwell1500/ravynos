# expat, built as /usr/lib/libexpat.1.dylib.
#
# The SDK used to carry a prebuilt libexpat.dylib whose LC_ID_DYLIB had
# compatibility_version 0.0.0 and an unversioned name.  Every macOS client
# that links expat records /usr/lib/libexpat.1.dylib at compatibility 1.0.0,
# and dyld2 refuses an image whose library reports less than the client
# recorded (Libraries/dyld/src/ImageLoader.cpp:745).  So the library is built
# here from the in-tree 2.6 sources with Apple's name and ABI versions.
LIB=		expat
MK_WERROR=	no
SRCS=		xmlparse.c xmlrole.c xmltok.c
INCS=		expat.h expat_external.h

EXPAT=		${ROOT_SOURCE_DIR}/contrib/expat
.PATH:		${EXPAT}

CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${EXPAT} -DHAVE_EXPAT_CONFIG_H=1

.include <bsd.lib.mk>

all: ${.OBJDIR}/lib${LIB}.a ${.OBJDIR}/lib${LIB}.1.dylib

${.OBJDIR}/lib${LIB}.1.dylib: ${.OBJDIR}/lib${LIB}.a
	${CC} -shared -dylib -o ${.TARGET} \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a -nodefaultlibs \
	  -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libexpat.1.dylib \
	  -Wl,-current_version,2.6.0 -Wl,-compatibility_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include"; \
	  cp -f ${.TARGET} "$$sdk/usr/lib/libexpat.1.dylib"; \
	  ln -sf libexpat.1.dylib "$$sdk/usr/lib/libexpat.dylib"; \
	  cp -f ${EXPAT}/expat.h "$$sdk/usr/include/expat.h"; \
	  cp -f ${EXPAT}/expat_external.h "$$sdk/usr/include/expat_external.h"; \
	done
