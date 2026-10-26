MK_WERROR = no
FRAMEWORK = Security
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.0.0
FMWK_CURRENT_VERSION = 60156.40.4
INFO_PLIST = Info.plist

# The tree carries Apple's full Security sources (Trieste, SOS, CMS, keychain
# sync) under OSX/, sectask/, KeychainCircle/ and friends.  None of that builds
# here -- it needs secd, the Keychain framework, trustd and a mach service
# namespace -- and none of it is what a bundled application links against at
# launch.  What it does link against is SecTaskCreateFromSelf, SecItem*,
# SecTrust*, SecCode* and SecRandomCopyBytes, so this framework implements
# exactly that surface and refuses the rest:
#     errSecUnimplemented  where no implementation exists,
#     errSecItemNotFound   where there is no keychain,
#     NULL                 where there is no entitlement.
SRCS = SecurityRuntime.c

HEADERS = Headers/Security.h

CFLAGS += -I${.CURDIR} -I${.CURDIR}/header_symlinks \
	-I${ROOT_SOURCE_DIR}/Frameworks/CoreFoundation \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
	-I${RAVYN_SDKROOT}/usr/include

LDFLAGS += -F${RAVYN_SDKROOT}/System/Library/Frameworks \
	-Wl,-framework,CoreFoundation

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
