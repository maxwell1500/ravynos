MK_WERROR = no
FRAMEWORK = ApplicationServices
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.0.0
FMWK_CURRENT_VERSION = 262.1
INFO_PLIST = Info.plist

# ApplicationServices is the umbrella over CoreGraphics, CoreText and the
# Carbon-era process/accessibility/printing calls.  CoreGraphics and CoreText
# are separate frameworks in this tree and are linked (not copied) here;
# ApplicationServicesRuntime.c supplies the process, accessibility, PrintCore
# and HIShape entry points a bundled application calls while foregrounding
# itself and probing accessibility.
SRCS = ApplicationServicesRuntime.m
HEADERS = ApplicationServices.h

CFLAGS += -I${.CURDIR} \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreGraphics.framework/Headers \
	-I${RAVYN_SDKROOT}/usr/include \
	-F${RAVYN_SDKROOT}/System/Library/Frameworks

LDFLAGS += -F${RAVYN_SDKROOT}/System/Library/Frameworks \
	-Wl,-framework,CoreFoundation \
	-Wl,-framework,CoreGraphics

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
