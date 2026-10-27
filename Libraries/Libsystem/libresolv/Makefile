# /usr/lib/libresolv.9.dylib from the in-tree Apple libresolv sources.
#
# Chrome records this library explicitly (three symbols: res_9_init,
# res_9_query, res_9_search) and macOS applications expect the versioned name
# with compatibility 1.0.0.  The sources were already here but had no build
# recipe and nothing descended into them.
LIB=		resolv
MK_WERROR=	no
SRCS=		res_init.c res_query.c res_send.c res_sendsigned.c res_comp.c \
		res_data.c res_debug.c res_findzonecut.c res_mkquery.c \
		res_mkupdate.c res_update.c dns.c dns_async.c dns_util.c \
		dst_api.c dst_hmac_link.c dst_support.c ns_date.c ns_name.c \
		ns_netint.c ns_parse.c ns_print.c ns_samedomain.c ns_sign.c \
		ns_ttl.c ns_verify.c base64.c dns_compat.c
INCS=		resolv.h dns.h dns_util.h
CFLAGS+=	-Wno-incompatible-sysroot \
		--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
		-I${.CURDIR} -I${ROOT_SOURCE_DIR}/BSD/usr.sbin/configd/dnsinfo \
		-I${ROOT_SOURCE_DIR}/BSD/usr.sbin/configd \
		-I${RAVYN_SDKROOT}/usr/include/arpa \
		-I${ROOT_SOURCE_DIR}/BSD/usr.sbin/mDNSResponder/mDNSShared -DPRIVATE=1 \
		-Wno-deprecated-declarations -Wno-implicit-function-declaration \
		-Wno-int-conversion -Wno-sign-conversion

.include <bsd.lib.mk>

all: ${.OBJDIR}/lib${LIB}.a ${.OBJDIR}/lib${LIB}.9.dylib

${.OBJDIR}/lib${LIB}.9.dylib: ${.OBJDIR}/lib${LIB}.a
	${CC} -shared -dylib -o ${.TARGET} \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a -nodefaultlibs \
	  -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache \
	  -Wl,-install_name,/usr/lib/libresolv.9.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,65.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -L${RAVYN_SDKROOT}/usr/lib -ldyld
	for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include"; \
	  cp -f ${.TARGET} "$$sdk/usr/lib/lib${LIB}.9.dylib"; \
	  ln -sf lib${LIB}.9.dylib "$$sdk/usr/lib/lib${LIB}.dylib"; \
	  cp -f ${.CURDIR}/resolv.h ${.CURDIR}/dns.h ${.CURDIR}/dns_util.h "$$sdk/usr/include/"; \
	done
