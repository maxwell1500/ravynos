APP=	Filer
SRCS=	FilerMain.m
RESOURCES= ${.CURDIR}/filer.png

MK_WERROR=	no
MK_PIE=		no
WARNS=		1
# Same fixes as CoreServices/Dock/Makefile (and WindowServer's precedent):
# ${SRCTOP} -> ${ROOT_SOURCE_DIR} (SRCTOP is the BSD subtree in a standalone
# bmake run), drop the nonexistent -L${OBJTOP}/tmp/usr/lib, resolve frameworks
# with -F/-framework instead of -L, and replace the ld64-rejected -Wl,-R with
# -Wl,-rpath. FilerMain.m includes <Cocoa/Cocoa.h> (only in the source tree)
# and <CoreServices/CoreServices.h> (SDK, which imports CFNetwork.h from the
# source tree), so -I${ROOT_SOURCE_DIR}/Frameworks is load-bearing.
CFLAGS+=	-g -O0 -fobjc-arc -D__MACH__ -D__RAVYNOS__ -fPIC -pthread \
		-I${.CURDIR} -I${MAKEOBJDIR} \
		-I${ROOT_SOURCE_DIR}/Frameworks \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-I${OBJTOP}/Frameworks/AppKit/Headers \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics \
		-F${OBJTOP}/Frameworks/CoreServices/LaunchServices \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks

LDFLAGS+=	-Wl,-rpath,'$$ORIGIN/../Resources' \
		-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
		-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics -framework CoreGraphics \
		-F${OBJTOP}/Frameworks/CoreServices/LaunchServices -framework LaunchServices \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/LaunchServices.framework/Versions/A \
		-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem

.include <rvn.app.mk>

all: obj
