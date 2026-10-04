#
# FIXME: zoe 2/11/26 This should live in SkyLight now. See
# https://eclecticlight.co/2020/06/08/windowserver-display-compositor-and-input-event-router/
# "In Catalina, it's to be found in /System/Library/PrivateFrameworks/SkyLight.framework/Resources,
# alongside pointer/cursor support."
# Plist goes in /Library/Preferences/com.apple.windowserver.plist
#
MK_AUTO_OBJ=    yes
APP=	        WindowServer
.PATH:          ${.CURDIR}
SRCS=           WindowServer.m \
                BSDFramebuffer.m \
		WSInput.m \
		WSAppRecord.m \
		WSWindowRecord.m \
		WSDisplay.m \
		main.m

# The vendored libinput/libevdev Makefiles build into ${MAKEOBJDIR} itself (their
# .PATH is ${.CURDIR}, and this tree's objdir is flat), so the shared objects
# are ${MAKEOBJDIR}/libinput.so.1, not ${MAKEOBJDIR}/libinput/libinput.so.1.
RESOURCES=	${.CURDIR}/Icon.png \
		${MAKEOBJDIR}/libinput.so.1 \
		${MAKEOBJDIR}/libinput.so \
		${MAKEOBJDIR}/libevdev.so.2 \
		${MAKEOBJDIR}/libevdev.so \
		${.CURDIR}/Cursors/arrowCursor.png \
		${.CURDIR}/Cursors/resizeCursor.png \
		${.CURDIR}/Decorations/close.png \
		${.CURDIR}/Decorations/closeHover.png \
		${.CURDIR}/Decorations/mini.png \
		${.CURDIR}/Decorations/miniHover.png \
		${.CURDIR}/Decorations/zoom.png \
		${.CURDIR}/Decorations/zoomUpHover.png \
		${.CURDIR}/Decorations/zoomDownHover.png

MK_WERROR=	no
MK_PIE=		no
WARNS=	        1
SYSROOT=        --sysroot=${RAVYN_SDKROOT} -B${OBJTOP}/tmp/usr/bin
CFLAGS+=	-fobjc-arc -g -D__RAVYNOS__ -D__MACH__ -D__WSRPC -pthread \
		-I${.CURDIR} -I${MAKEOBJDIR} -I${.CURDIR}/libinput/src \
		-I${.CURDIR}/libinput/include -I${ROOT_SOURCE_DIR}/Frameworks \
		-I${.CURDIR}/libxkbcommon/include -I${ROOT_SOURCE_DIR}/CoreServices \
		-I${ROOT_SOURCE_DIR}/BSD/lib/libudev-devd \
		-I${ROOT_SOURCE_DIR}/Libraries/Libsystem/liblaunch \
		-I${OBJTOP}/Frameworks/Foundation/Headers -I${RAVYN_SDKROOT}/usr/include \
		-I${ROOT_SOURCE_DIR}/gnu/lib/libobjc2 -I${SRCTOP}/sys/sys -I${SRCTOP}/sys \
		-I${ROOT_SOURCE_DIR}/Kernel/xnu -I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
		-I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-I${RAVYN_SDKROOT}/System/Library/Frameworks/Kernel.framework/Versions/A/Headers \
		-I${OBJTOP}/Frameworks/AppKit/Headers

# The ravynOS frameworks live under ${OBJTOP}/Frameworks/<F>/<F>.framework.
# ld64 does NOT resolve "-L<...>.framework -l<F>" against a framework bundle --
# it searches that directory as a plain library directory, finds no
# libCoreText.*/CoreText.* and fails with "library 'CoreText' not found".
# Frameworks must be named with -F<dir> -framework <name>, which is what the
# Frameworks/ Makefiles (AppKit, Foundation, ...) already do.
# -R is an ELF/Solaris linker flag; ld64 spells the same thing -rpath and
# rejects -R outright ("ld: unknown options: -R$ORIGIN/../Resources ...").
# The Frameworks/ Makefiles already use -Wl,-rpath,<path>.
LDFLAGS+=	-Wl,-rpath,'$$ORIGIN/../Resources' \
		-L${MAKEOBJDIR} -L${RAVYN_SDKROOT}/usr/lib \
		-F${OBJTOP}/Frameworks/CoreText -framework CoreText \
		-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
		-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics -framework CoreGraphics \
		-F${OBJTOP}/Frameworks/CoreFoundation -framework CoreFoundation \
		-F${OBJTOP}/Frameworks/Onyx2D -framework Onyx2D \
                -Wl,-rpath,/System/Library/Frameworks/OpenGL.framework/Versions/A \
                -Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/A \
                -Wl,-rpath,/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
                -Wl,-rpath,/System/Library/Frameworks/CoreFoundation.framework/Versions/A \
                -Wl,-rpath,/System/Library/Frameworks/Onyx2D.framework/Versions/A \
                -Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
                -Wl,-rpath,/System/Library/Frameworks/CoreText.framework/Versions/A \
		${MAKEOBJDIR}/libinput.a ${MAKEOBJDIR}/libevdev.a \
		${MAKEOBJDIR}/libxkbcommon.a ${MAKEOBJDIR}/libquirks.a \
		${MAKEOBJDIR}/libinput-util.a ${MAKEOBJDIR}/libfilter.a \
		${MAKEOBJDIR}/libmtdev.a \
		-lutil -pthread -lobjc -lm

# The vendored libinput/libevdev/libxkbcommon/mtdev trees build their objects
# straight into ${MAKEOBJDIR} (see the libinput/libxkbcommon Makefiles' .PATH),
# not into ${MAKEOBJDIR}/<subdir>/, so the archives are named here directly
# rather than through the old libxkbcommon/src/*.pico globs, which matched
# nothing and made the link command fail with "no such file or directory".
#
# -ludev / -lkvm / -lcrypt / -llaunch are gone: kvm(3) was replaced by sysctl
# in WindowServer.m, and the other three have no Darwin equivalent that
# WindowServer references.
#.export SYSROOT

#SUBDIR+=        libevdev .WAIT
#SUBDIR+=	mtdev .WAIT
#SUBDIR+=        libinput .WAIT
#SUBDIR+=	libxkbcommon

${MAKEOBJDIR}/Resources:
	cp -fv ${.CURDIR}/libinput/quirks/* ${APP_DIR}/Contents/Resources/

make-obj-dirs: .EXEC
	mkdir -p ${MAKEOBJDIR}
.for subdir in ${SUBDIR}
	mkdir -p ${MAKEOBJDIR}/${subdir}
.endfor
	mkdir -p ${MAKEOBJDIR}/LoadingWindow
	mkdir -p ${MAKEOBJDIR}/LoginWindow
	mkdir -p ${MAKEOBJDIR}/SystemUIServer
	mkdir -p ${MAKEOBJDIR}/libxkbcommon/src/xkbcomp
	mkdir -p ${MAKEOBJDIR}/libxkbcommon/src/compose

clean: .PHONY
	rm -rf ${MAKEOBJDIR}

.include <sys.mk>
.include <bsd.subdir.mk>
.include <rvn.app.mk>

${OBJS}: ${MAKEOBJDIR}/Resources

client: client.m message.h
	mkdir -p ${.CURDIR}/client.app/Contents/ravynOS
	cd ${.CURDIR}; ${CC} -g -fobjc-arc -fobjc-runtime=gnustep-2.0 -fobjc-nonfragile-abi \
		-fPIC -o ${.CURDIR}/client.app/Contents/ravynOS/client client.m \
		-framework Foundation -framework CoreFoundation \
		-framework CoreGraphics -framework AppKit -lSystem

