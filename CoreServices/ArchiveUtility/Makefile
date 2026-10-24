APP=	Archive_Utility
SRCS=	main.m ArchiveEngine.m ArchiveController.m

MK_WERROR=	no
MK_PIE=		no
WARNS=		1
CFLAGS+=	-g -O0 -fobjc-arc -D__MACH__ -D__RAVYNOS__ -fPIC -pthread \
		-Wno-missing-method-return-type -Wno-macro-redefined \
		-I${.CURDIR} -I${MAKEOBJDIR} \
		-I${ROOT_SOURCE_DIR}/Frameworks \
		-I${ROOT_SOURCE_DIR}/Libraries/zlib \
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
		-L${RAVYN_SDKROOT}/usr/lib -lz -lobjc -lSystem -lm

.include <rvn.app.mk>

all: obj
	cp -fv ${.CURDIR}/Info.plist ${APP_DIR}/Contents/
	rm -f ${APP_DIR}/${APP}
	ln -sf "Contents/ravynOS/${APP:S/_/ /}" "${APP_DIR}/${APP:S/_/ /}"
	mv -f ${APP_DIR}/Contents/ravynOS/${APP} "${APP_DIR}/Contents/ravynOS/${APP:S/_/ /}"
	rm -rf "${APP_DIR:S/_/ /}"
	mv -f ${APP_DIR} "${APP_DIR:S/_/ /}"

clean:
	rm -rf ${APP_DIR} "${APP_DIR:S/_/ /}"
	rm -f *.o

makedirs:
	mkdir -p ${MAKEOBJDIR}

build: clean makedirs obj all