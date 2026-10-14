APP=Install_ravynOS
SRCS=Source/main.m Source/AppDelegate.m Source/GSGeomDisk.m
MK_DEBUG_FILES=no
RESOURCES=${.CURDIR}/MarmosetLogo.tiff ${.CURDIR}/header.rtf ${.CURDIR}/terms.rtf \
        ${.CURDIR}/Icon.png
RAVYNOS_VERSION!= head -1 ${.CURDIR}/../../version.txt

MK_WERROR= no
WARNS= 1
CFLAGS= -g -DRAVYNOS_VERSION=\"${RAVYNOS_VERSION}\" \
	-D__MACH__ -D__RAVYNOS__ -I${RAVYN_SDKROOT}/usr/include -I${RAVYN_SDKROOT}/usr/local/include/kernel \
	-Wno-missing-method-return-type \
	-I${OBJTOP}/CoreServices/WindowServer/SystemUIServer \
	-I${ROOT_SOURCE_DIR}/Frameworks -I${OBJTOP}/Frameworks/Foundation/Headers \
	-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
	-I${ROOT_SOURCE_DIR}/Frameworks/AppKit/Headers
LDFLAGS= -Wl,-rpath,'$$ORIGIN/../Resources' \
	-F${OBJTOP}/Frameworks/Cocoa -framework Cocoa \
	-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
	-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
	-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
	-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
	-Wl,-rpath,/System/Library/Frameworks/Cocoa.framework/Versions/A \
	-Wl,-rpath,/System/Library/Frameworks/OpenGL.framework/Versions/A \
	-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem

clean:
	rm -rf ${APP_DIR} "${APP_DIR:S/_/ /}"
	rm -f Source/*.o

makedirs:
	mkdir -p ${MAKEOBJDIR}/Source

build: clean makedirs obj all
	rm -f ${APP_DIR}/${APP}
	ln -sf "Contents/ravynOS/${APP:S/_/ /}" "${APP_DIR}/${APP:S/_/ /}"
	mv -f ${APP_DIR}/Contents/ravynOS/${APP} "${APP_DIR}/Contents/ravynOS/${APP:S/_/ /}"
	mv -f ${APP_DIR} "${APP_DIR:S/_/ /}"

.include <rvn.app.mk>
