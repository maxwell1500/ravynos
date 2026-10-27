# /usr/lib/libcups.2.dylib.  See cups.c: IPP objects are real, delivery is
# not, and the library says so through cupsGetDests() and cupsDoRequest().
MK_WERROR=	no
SRCS=		cups.c
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${.CURDIR} -Wno-unused-parameter

all: libcups.2.dylib

cups.o: cups.c cups/cups.h
	${CC} ${CFLAGS} -c -o ${.OBJDIR}/cups.o ${.CURDIR}/cups.c

libcups.2.dylib: ${.OBJDIR}/cups.o
	${CC} -shared -dylib -o ${.OBJDIR}/$@ ${.OBJDIR}/cups.o \
	  -nodefaultlibs -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libcups.2.dylib \
	  -Wl,-compatibility_version,2.0.0 -Wl,-current_version,2.14.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include/cups"; \
	  cp -f ${.OBJDIR}/libcups.2.dylib "$$sdk/usr/lib/libcups.2.dylib"; \
	  ln -sf libcups.2.dylib "$$sdk/usr/lib/libcups.dylib"; \
	  cp -f ${.CURDIR}/cups/cups.h "$$sdk/usr/include/cups/cups.h"; \
	done
