APP=	Trash
SRCS=	main.m Trash.m
RESOURCES=	${.CURDIR}/Trash.png ${.CURDIR}/Trash_full.png

Trash.o: Trash.m Trash.h

MK_WERROR=	no
MK_PIE=		no
CFLAGS+=	-g -fPIC -fobjc-arc -D__RAVYNOS__ \
		-I${.CURDIR} -I${MAKEOBJDIR} -I${ROOT_SOURCE_DIR}/Frameworks \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreServices/LaunchServices \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks

# Same fixes as CoreServices/Dock/Makefile: -F/-framework instead of -L for
# frameworks, -Wl,-rpath instead of the ld64-rejected -Wl,-R, and
# ${ROOT_SOURCE_DIR} instead of the standalone-run ${SRCTOP} (the BSD subtree).
LDFLAGS+=	-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
		-F${OBJTOP}/Frameworks/CoreServices/LaunchServices -framework LaunchServices \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-Wl,-rpath,/System/Library/Frameworks/LaunchServices.framework/Versions/A \
		-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem


.include <rvn.app.mk>

all:
	cp -fv ${.CURDIR}/Info.plist ${APP_DIR}/Contents/
