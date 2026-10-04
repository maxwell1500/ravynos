APP=	Dock
SRCS=	main.m Dock.m DockItem.m DesktopWindow.m DockTileData.m
RESOURCES=	${.CURDIR}/Dock.png ${.CURDIR}/running.png \
		${.CURDIR}/window.png Trash.app \
		Downloads.app

Dock.o: Dock.m Dock.h 
DockItem.o: DockItem.m DockItem.h

MK_WERROR=	no
MK_PIE=		no
WARNS=		1
# Explicit -I/-F paths, no --sysroot: this is how CoreServices/WindowServer
# builds. ${SRCTOP} is the BSD subtree in a standalone bmake run
# (src.sys.env.mk derives it from the share/mk location), so every
# ${SRCTOP}/... path here resolved to BSD/... and found nothing; the
# repository root is ${ROOT_SOURCE_DIR}.
CFLAGS+=	-g -O0 -fobjc-arc -D__MACH__ -D__RAVYNOS__ -fPIC -pthread \
		-Wno-missing-method-return-type -Wno-macro-redefined \
		-I${.CURDIR} -I${MAKEOBJDIR} \
		-I${ROOT_SOURCE_DIR}/CoreServices -I${ROOT_SOURCE_DIR}/Frameworks \
		-I${ROOT_SOURCE_DIR}/gnu/lib/libobjc2 \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-I${OBJTOP}/Frameworks/AppKit/Headers \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-I${MAKEOBJDIR}/../WindowServer/SystemUIServer \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics \
		-F${OBJTOP}/Frameworks/CoreServices/LaunchServices \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks

# Three defects, all fixed the way CoreServices/WindowServer/Makefile fixed
# them: (a) -L${OBJTOP}/tmp/usr/lib named a directory that does not exist;
# (b) ld64 cannot resolve a framework binary through -L ("library
# 'LaunchServices' not found") -- a framework must be named -F<dir> -framework
# <name>; (c) -Wl,-R is an ELF/Solaris flag that ld64 rejects ("unknown
# options: -R"). The Darwin spelling is -Wl,-rpath.
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

# build-libraries.sh exports MAKEOBJDIR=$BUILD<abs source path> for the whole
# build, and a sub-make inherits it, so Trash.app/Downloads.app were built
# beside Dock.app instead of next to their own sources. Point each sub-make at
# this directory's object dir: recipes run in ${.OBJDIR}, so that is also where
# RESOURCES (Trash.app, Downloads.app) is looked up.
Trash.app::
	rm -rf ${.TARGET}
	${MAKE} -C ${.CURDIR}/Trash MAKEOBJDIR=${.OBJDIR}

Downloads.app::
	rm -rf ${.TARGET}
	${MAKE} -C ${.CURDIR}/Downloads MAKEOBJDIR=${.OBJDIR}

.include <rvn.app.mk>

all: Trash.app Downloads.app
	cp -fv ${.CURDIR}/Info.plist ${APP_DIR}/Contents/
