APP= System_Preferences
SRCS= main.m SysPrefs.m
MK_DEBUG_FILES= no
MK_WERROR= no
RESOURCES= ${.CURDIR}/Info.plist ${.CURDIR}/Icon.png

WARNS= 1
CFLAGS= -g -fobjc-arc -D__MACH__ -D__RAVYNOS__ -I${RAVYN_SDKROOT}/usr/include -I${RAVYN_SDKROOT}/usr/local/include/kernel \
	-Wno-missing-method-return-type \
	-I${ROOT_SOURCE_DIR}/Frameworks -I${OBJTOP}/Frameworks/Foundation/Headers \
	-I${ROOT_SOURCE_DIR}/Frameworks/AppKit/Headers -F${OBJTOP}/Frameworks/OpenGL -F${RAVYN_SDKROOT}/System/Library/Frameworks
LDFLAGS= -Wl,-rpath,'$$ORIGIN/../Resources' \
	-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
	-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
	-F${OBJTOP}/Frameworks/PreferencePanes -framework PreferencePanes \
	-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
	-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
	-Wl,-rpath,/System/Library/Frameworks/PreferencePanes.framework/Versions/A \
	-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem

clean:
	rm -rf ${APP_DIR} "${APP_DIR:S/_/ /}"
	rm -f *.o

makedirs:
	mkdir -p ${MAKEOBJDIR}

build: clean makedirs obj all
	rm -f ${APP_DIR}/${APP}
	ln -sf "Contents/ravynOS/${APP:S/_/ /}" "${APP_DIR}/${APP:S/_/ /}"
	mv -f ${APP_DIR}/Contents/ravynOS/${APP} "${APP_DIR}/Contents/ravynOS/${APP:S/_/ /}"
	mv -f ${APP_DIR} "${APP_DIR:S/_/ /}"

.include <rvn.app.mk>
