MK_WERROR = no
FRAMEWORK = CFNetwork
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.0.0
FMWK_CURRENT_VERSION = 1493.0.3
INFO_PLIST = Info.plist

# Apple's CFNetwork sources in this tree (the CFHTTPConnection stream stack,
# SPNEGO/NTLM filters, CFNetServices, CFFTPStream, CFNetDiagnostics) do not
# build here and duplicate transport work this tree already does in
# Foundation.  CFNetworkRuntime.m implements the surface a bundled application
# links against -- proxy queries, CFHost resolution, CFHTTPMessage -- and the
# public header declares only that, so nothing links that is not implemented.
SRCS = CFNetworkRuntime.m
HEADERS = Headers/CFNetwork.h

CFLAGS += -I${.CURDIR}/Headers -I${ROOT_SOURCE_DIR}/Frameworks/CoreFoundation \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
	-I${RAVYN_SDKROOT}/usr/include

LDFLAGS += -F${RAVYN_SDKROOT}/System/Library/Frameworks \
	-Wl,-framework,CoreFoundation -lSystem

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
