APP=	        LoadingWindow
SRCS=           LoadingWindow.m
RESOURCES=      ${ROOT_SOURCE_DIR}/Logo_Assets/splash-1.png

MK_WERROR=	no
MK_PIE=		no
WARNS=	        1
OBJCFLAGS= -fobjc-runtime=gnustep-2.0 -fobjc-nonfragile-abi -fPIC \
	   -Wno-missing-method-return-type -Wno-macro-redefined -fobjc-arc
# Same fixes as LoginWindow/SystemUIServer: drop the nonexistent
# --sysroot=${OBJTOP}/tmp / -B${OBJTOP}/tmp/usr/bin, resolve frameworks with
# -F/-framework instead of -L/-l, and replace the ld64-rejected -Wl,-R with
# -Wl,-rpath.
CFLAGS+=	-O3 -I${.CURDIR} -I${MAKEOBJDIR} \
		${OBJCFLAGS} -I${ROOT_SOURCE_DIR}/Frameworks -D__MACH__ \
		-I${MAKEOBJDIR}/../SystemUIServer -D__RAVYNOS__ \
		-I${ROOT_SOURCE_DIR}/Frameworks/AppKit/Headers -I${ROOT_SOURCE_DIR}/CoreServices \
		-I${OBJTOP}/Frameworks/Foundation/Headers -I${ROOT_SOURCE_DIR}/gnu/lib/libobjc2 \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks
LDFLAGS+=	-Wl,-rpath,'$$ORIGIN/../Resources' \
		-L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/lib/system \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
                -framework AppKit -framework Foundation -framework CoreGraphics -lobjc -lSystem

.include <rvn.app.mk>
${OBJS}: obj
