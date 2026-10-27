# /usr/lib/libffi.dylib (+ libffi.8.dylib alias) for ravynOS.
#
# libffi's own configure is used because its configuration header is
# generated, not shipped; --host makes it a cross build, so no test program is
# run on the host.  The static archive it produces is linked into a dylib
# here with Apple's install name and ABI versions.
MK_WERROR=	no
BUILD=		${.OBJDIR}/build
LIBFFI=		${BUILD}/.libs/libffi.a

all: ${.OBJDIR}/libffi.dylib

# libffi's configure generates fficonfig.h, which the sources require; the
# library itself is compiled here rather than through libtool, because
# libtool's Darwin static-only mode writes .lo files that name objects it
# never produces (.libs/x86/unix64.o), so its archive step fails.  The compile
# list is libtool's own list minus the Windows-only PE sources.
${.OBJDIR}/fficonfig.h:
	mkdir -p ${.OBJDIR}/build
	cd ${.OBJDIR}/build && \
	  CC=${CC} CXX=${ROOT_SOURCE_DIR}/tools/sdk/bin/ravynos-c++ \
	  CFLAGS="--sysroot=${RAVYN_SDKROOT} -arch x86_64 -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-incompatible-sysroot" \
	  ${.CURDIR}/configure --host=x86_64-apple-darwin --prefix=/usr \
	    --disable-shared --enable-static --disable-docs \
	    --disable-multi-os-directory
	cp -f ${.OBJDIR}/build/fficonfig.h ${.OBJDIR}/fficonfig.h

FFI_CFLAGS = --sysroot=${RAVYN_SDKROOT} -arch x86_64 \
	-mmacos-version-min=${MACOS_VERSION_MIN} -Wno-incompatible-sysroot \
	-I${.OBJDIR} -I${.OBJDIR}/build/include -I${.CURDIR}/include -I${.CURDIR}/src \
	-I${.CURDIR}/src/x86 -fexceptions -fPIC

FFI_OBJS = ${.OBJDIR}/prep_cif.o ${.OBJDIR}/types.o ${.OBJDIR}/raw_api.o \
	${.OBJDIR}/java_raw_api.o ${.OBJDIR}/closures.o ${.OBJDIR}/tramp.o \
	${.OBJDIR}/ffi64.o ${.OBJDIR}/unix64.o ${.OBJDIR}/ffi_efi64_stubs.o

${.OBJDIR}/prep_cif.o: ${.CURDIR}/src/prep_cif.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/prep_cif.c
${.OBJDIR}/types.o: ${.CURDIR}/src/types.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/types.c
${.OBJDIR}/raw_api.o: ${.CURDIR}/src/raw_api.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/raw_api.c
${.OBJDIR}/java_raw_api.o: ${.CURDIR}/src/java_raw_api.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/java_raw_api.c
${.OBJDIR}/closures.o: ${.CURDIR}/src/closures.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/closures.c
${.OBJDIR}/tramp.o: ${.CURDIR}/src/tramp.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/tramp.c
${.OBJDIR}/ffi64.o: ${.CURDIR}/src/x86/ffi64.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/x86/ffi64.c
${.OBJDIR}/unix64.o: ${.CURDIR}/src/x86/unix64.S ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/src/x86/unix64.S

${.OBJDIR}/ffi_efi64_stubs.o: ${.CURDIR}/ffi_efi64_stubs.c ${.OBJDIR}/fficonfig.h
	${CC} ${FFI_CFLAGS} -c -o $@ ${.CURDIR}/ffi_efi64_stubs.c

${.OBJDIR}/libffi.dylib: ${FFI_OBJS}
	${CC} -shared -dylib -o ${.OBJDIR}/libffi.body.dylib ${FFI_OBJS} \
	  -nodefaultlibs -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libffi.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,30.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	cp -f ${.OBJDIR}/libffi.body.dylib ${.TARGET}
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include"; \
	  cp -f ${.TARGET} "$$sdk/usr/lib/libffi.dylib"; \
	  ln -sf libffi.dylib "$$sdk/usr/lib/libffi.8.dylib"; \
	  cp -f ${.OBJDIR}/build/include/ffi.h "$$sdk/usr/include/ffi.h" 2>/dev/null || true; \
	  cp -f ${.OBJDIR}/build/include/ffitarget.h "$$sdk/usr/include/ffitarget.h" 2>/dev/null || true; \
	done
