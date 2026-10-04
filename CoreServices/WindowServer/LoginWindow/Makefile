APP=	        LoginWindow
SRCS=           LoginWindow.m \
                DesktopWindow.m \
                LoginBox.m \
                Label.m 
RELEASE_LOGO=	hyena.png
RESOURCES=      ${ROOT_SOURCE_DIR}/Logo_Assets/ravynos-full.png \
		${ROOT_SOURCE_DIR}/Logo_Assets/${RELEASE_LOGO}

MK_WERROR=	no
MK_PIE=		no
WARNS=	        1
OBJCFLAGS= -fobjc-runtime=gnustep-2.0 -fobjc-nonfragile-abi -fPIC \
	   -Wno-missing-method-return-type -Wno-macro-redefined
# Same fixes as CoreServices/Dock/Makefile (and WindowServer's precedent):
# ${SRCTOP} -> ${ROOT_SOURCE_DIR} (SRCTOP is the BSD subtree in a standalone
# bmake run), drop the nonexistent -L${OBJTOP}/tmp/usr/lib, resolve frameworks
# with -F/-framework instead of -L, and replace the ld64-rejected -Wl,-R with
# -Wl,-rpath. -I${RAVYN_SDKROOT}/usr/local/include/kernel is what WindowServer
# carries for the #include_next <os/object.h> chain.
CFLAGS+=	-g -fobjc-arc -I${.CURDIR} -I${MAKEOBJDIR} \
		${OBJCFLAGS} -I${ROOT_SOURCE_DIR}/Frameworks -D__MACH__ \
		-I${ROOT_SOURCE_DIR}/CoreServices/WindowServer/SystemUIServer -D__RAVYNOS__ \
		-I${ROOT_SOURCE_DIR}/Frameworks/AppKit/Headers -I${ROOT_SOURCE_DIR}/CoreServices \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-I${ROOT_SOURCE_DIR}/gnu/lib/libobjc2 \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks \
		-DRELEASE_LOGO="@\"${RELEASE_LOGO}\""
LDFLAGS+=	-Wl,-rpath,'$$ORIGIN/../Resources' \
		-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
		-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics -framework CoreGraphics \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
		-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem -lm

.include <rvn.app.mk>
${OBJS}: obj
