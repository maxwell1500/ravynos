APP=	TextEdit
SRCS=	main.m TextDocument.m TextWindowController.m MarkdownHighlighter.m

MK_WERROR=	no
MK_PIE=		no
WARNS=		1
CFLAGS+=	-g -O0 -fobjc-arc -D__MACH__ -D__RAVYNOS__ -fPIC -pthread \
		-Wno-missing-method-return-type -Wno-macro-redefined \
		-I${.CURDIR} -I${MAKEOBJDIR} \
		-I${ROOT_SOURCE_DIR}/Frameworks \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-I${OBJTOP}/Frameworks/AppKit/Headers \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks

LDFLAGS+=	-Wl,-rpath,'$$ORIGIN/../Resources' \
		-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
		-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics -framework CoreGraphics \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
		-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem

.include <rvn.app.mk>

all: obj
	cp -fv ${.CURDIR}/Info.plist ${APP_DIR}/Contents/