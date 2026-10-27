# /usr/lib/libpam.2.dylib: handles, items, conversation, environment.  See
# pam.c for why pam_authenticate() reports PAM_AUTHINFO_UNAVAIL.
MK_WERROR=	no
SRCS=		pam.c
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${.CURDIR} -Wno-unused-parameter

all: libpam.2.dylib

pam.o: pam.c pam.h
	${CC} ${CFLAGS} -c -o ${.OBJDIR}/pam.o ${.CURDIR}/pam.c

libpam.2.dylib: ${.OBJDIR}/pam.o
	${CC} -shared -dylib -o ${.OBJDIR}/$@ ${.OBJDIR}/pam.o \
	  -nodefaultlibs -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libpam.2.dylib \
	  -Wl,-compatibility_version,3.0.0 -Wl,-current_version,3.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include/security"; \
	  cp -f ${.OBJDIR}/libpam.2.dylib "$$sdk/usr/lib/libpam.2.dylib"; \
	  ln -sf libpam.2.dylib "$$sdk/usr/lib/libpam.dylib"; \
	  cp -f ${.CURDIR}/pam.h "$$sdk/usr/include/security/pam_appl.h"; \
	  cp -f ${.CURDIR}/pam.h "$$sdk/usr/include/pam.h"; \
	done
