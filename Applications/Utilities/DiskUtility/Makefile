APP=	Disk_Utility
SRCS=	main.m DiskBackend.m DiskUtilityController.m CapacityBarView.m

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
		-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem -lm

.include <rvn.app.mk>

all: ${APP_DIR} ${PROG} installresources ${APP_DIR}/${APP}
	rm -rf "${MAKEOBJDIR}/Disk Utility.app"
	mv -f "${MAKEOBJDIR}/Disk_Utility.app" "${MAKEOBJDIR}/Disk Utility.app"
	mv -f "${MAKEOBJDIR}/Disk Utility.app/Contents/ravynOS/Disk_Utility" "${MAKEOBJDIR}/Disk Utility.app/Contents/ravynOS/Disk Utility"
	rm -f "${MAKEOBJDIR}/Disk Utility.app/Disk_Utility"
	ln -s "Contents/ravynOS/Disk Utility" "${MAKEOBJDIR}/Disk Utility.app/Disk Utility"
	cp -fv ${.CURDIR}/Info.plist "${MAKEOBJDIR}/Disk Utility.app/Contents/"
	cp -fv ${.CURDIR}/PkgInfo "${MAKEOBJDIR}/Disk Utility.app/Contents/"