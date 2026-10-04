# ------------------------------------------------------------------------
#  RAVYNOS BUILD SYSTEM - Frameworks
# ------------------------------------------------------------------------

SUBDIR = CoreFoundation
# CFNetwork is disabled: it does not build. It is blocked on two frameworks that
# do not exist in this tree and have no framework Makefile --
#   * Security.framework, for AuthorizationRef, reached via
#     SystemConfiguration/SCPreferences.h:196 (which includes <Security/Security.h>
#     when !TARGET_OS_IPHONE), and
#   * SystemConfiguration.framework, for SCNetworkReachability, reached via
#     CFNetwork/Host/CFHost.c:86.
# Leaving it in SUBDIR makes every full Frameworks build attempt it and fail.
# Re-enable it once Security.framework and SystemConfiguration.framework exist.
#SUBDIR += CFNetwork
SUBDIR += Foundation
SUBDIR += CoreServices
SUBDIR += Onyx2D
SUBDIR += CoreGraphics
SUBDIR += CoreText
SUBDIR += AppKit

all: ${SUBDIR}

Foundation: CoreFoundation

.include <bsd.subdir.mk>
