APP=	        SystemUIServer
SRCS=           SystemUIServer.m \
                AppDelegate.m \
                ClockView.m \
                MenuView.m \
                ExtrasView.m \
                MenuBarWindow.m \
		NSMenuWindow.m \
		NSMainMenuView.m \
		SubmenuView.m \
                Label.m \
                AboutWindow.m
RELEASE_LOGO=	hyena.png
RESOURCES=	${.CURDIR}/../Icon.png ${.CURDIR}/ravynos-mark-64.png \
		${ROOT_SOURCE_DIR}/Logo_Assets/${RELEASE_LOGO} \
		${.CURDIR}/kickSession

MK_WERROR=	no
MK_PIE=		no
WARNS=	        1
OBJCFLAGS= -fobjc-runtime=gnustep-2.0 -fobjc-nonfragile-abi -fPIC \
	   -Wno-missing-method-return-type -Wno-macro-redefined
# Same fixes as CoreServices/Dock/Makefile (and WindowServer's precedent):
# ${SRCTOP} -> ${ROOT_SOURCE_DIR}, drop the nonexistent -L${OBJTOP}/tmp/usr/lib,
# resolve frameworks with -F/-framework instead of -L, and replace the
# ld64-rejected -Wl,-R with -Wl,-rpath. -I BSD/include is dropped: it shadows
# the SDK's mach/ headers (BSD/include/mach/mach_types.h pulls in
# <sys/mach/mach_types.h>, which does not exist).
CFLAGS+=	-g -fobjc-arc ${OBJCFLAGS} -D__RAVYNOS__ -D__MACH__ \
		-I${ROOT_SOURCE_DIR}/gnu/lib/libobjc2 \
		-I${.CURDIR} -I${MAKEOBJDIR} \
		-I${ROOT_SOURCE_DIR}/Frameworks/AppKit/Headers -I${ROOT_SOURCE_DIR}/CoreServices \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-I${ROOT_SOURCE_DIR}/Frameworks -I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/Foundation -F${OBJTOP}/Frameworks/CoreGraphics \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/CoreServices/LaunchServices \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks \
		-DRELEASE_LOGO="@\"${RELEASE_LOGO}\""
LDFLAGS+=	-Wl,-rpath,'$$ORIGIN/../Resources' \
		-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics -framework CoreGraphics \
		-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
		-F${OBJTOP}/Frameworks/CoreServices/LaunchServices -framework LaunchServices \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-Wl,-rpath,/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/LaunchServices.framework/Versions/A \
		-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem -lm

# Need this to find gl.h before toolchain supports -framework
${MAKEOBJDIR}/OpenGL:
	ln -sf ${ROOT_SOURCE_DIR}/Frameworks/OpenGL/include ${.TARGET}

${.CURDIR}/kickSession: kickSession.m
	${CC} -D__RAVYNOS__ -D__MACH__ -o ${.TARGET} ${.ALLSRC} \
		${OBJCFLAGS} -I${ROOT_SOURCE_DIR}/Frameworks -I${MAKEOBJDIR} \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/Foundation \
		-I${ROOT_SOURCE_DIR}/Frameworks/AppKit/Headers \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/lib/system \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks \
		-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/A \
		-framework AppKit -framework Foundation -framework CoreFoundation -llaunch -lSystem -lobjc

.include <rvn.app.mk>

${OBJS}: ${MAKEOBJDIR}/OpenGL
