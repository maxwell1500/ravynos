# /usr/lib/libsandbox.1.dylib: the sandbox calls macOS helpers make at
# startup.  See sandbox.h for what the implementation does and does not do.
MK_WERROR=	no
SRCS=		sandbox.c
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${.CURDIR} -Wno-unused-parameter

all: ${.OBJDIR}/libsandbox.1.dylib

${.OBJDIR}/sandbox.o: ${.CURDIR}/sandbox.c ${.CURDIR}/sandbox.h
	${CC} ${CFLAGS} -c -o ${.TARGET} ${.CURDIR}/sandbox.c

${.OBJDIR}/libsandbox.1.dylib: ${.OBJDIR}/sandbox.o
	${CC} -shared -dylib -o ${.TARGET} ${.OBJDIR}/sandbox.o \
	  -nodefaultlibs -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libsandbox.1.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include"; \
	  cp -f ${.TARGET} "$$sdk/usr/lib/libsandbox.1.dylib"; \
	  ln -sf libsandbox.1.dylib "$$sdk/usr/lib/libsandbox.dylib"; \
	  cp -f ${.CURDIR}/sandbox.h "$$sdk/usr/include/sandbox.h"; \
	done
