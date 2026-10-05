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
# LoginWindow.app and SystemUIServer.app are built by their own Makefiles
# (CoreServices/WindowServer/{LoginWindow,SystemUIServer}) and looked up by
# WindowServer.m through -[[NSBundle mainBundle] pathForResource:... ofType:@"app"]
# ("LoadingWindow" at WindowServer.m:432, "LoginWindow" at :457, "SystemUIServer"
# at :565), so they must sit in this bundle's Contents/Resources. They are built
# first (build-libraries.sh --frameworks .../LoginWindow .../SystemUIServer
# .../WindowServer). A comment cannot sit inside a continued variable assignment
# in bmake, so this note lives above RESOURCES rather than beside the entries.
RESOURCES=	${.CURDIR}/Icon.png
.if defined(__linux__)
RESOURCES+=	${MAKEOBJDIR}/libinput.so.1 \
		${MAKEOBJDIR}/libinput.so \
		${MAKEOBJDIR}/libevdev.so.2 \
		${MAKEOBJDIR}/libevdev.so
.endif
RESOURCES+=	${.CURDIR}/Cursors/arrowCursor.png \
		${.CURDIR}/Cursors/resizeCursor.png \
		${.CURDIR}/Decorations/close.png \
		${.CURDIR}/Decorations/closeHover.png \
		${.CURDIR}/Decorations/mini.png \
		${.CURDIR}/Decorations/miniHover.png \
		${.CURDIR}/Decorations/zoom.png \
		${.CURDIR}/Decorations/zoomUpHover.png \
		${.CURDIR}/Decorations/zoomDownHover.png \

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
                -Wl,-rpath,/System/Library/Frameworks/CoreText.framework/Versions/A
.if defined(__linux__)
LDFLAGS+=	${MAKEOBJDIR}/libinput.a ${MAKEOBJDIR}/libevdev.a \
		${MAKEOBJDIR}/libinput-util.a ${MAKEOBJDIR}/libfilter.a \
		${MAKEOBJDIR}/libmtdev.a
.endif
LDFLAGS+=	${MAKEOBJDIR}/libxkbcommon.a ${MAKEOBJDIR}/libquirks.a \
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

# LoginWindow.app and SystemUIServer.app are built by their own Makefiles
# (CoreServices/WindowServer/{LoginWindow,SystemUIServer}) before this one runs.
# WindowServer.m looks them up with -[[NSBundle mainBundle] pathForResource:...
# ofType:@"app"] -- "LoginWindow" at WindowServer.m:457 and "SystemUIServer" at
# :565 -- and mainBundle is this bundle, so they must sit in
# Contents/Resources/. (WindowServer.m:432 also looks for "LoadingWindow.app",
# which has no source in this tree; WindowServer logs "missing LoginWindow.app!"
# and falls through to the login shell without it.)
#
# These are deliberately NOT in RESOURCES: a directory named in RESOURCES makes
# bmake treat it as a target it must build, and the sub-app objdir tree is not
# present at that point. An explicit copy rule keyed on the built bundle is the
# form that works.
# The sub-app objdir is $BUILD$abs-source-path, i.e. .../ravynos/CoreServices/
# WindowServer/<app> -- NOT .../ravynos/Frameworks/CoreServices/... (there is no
# Frameworks/ component; $BUILD$base already ends at the app directory).
LOGINWINDOW_APP= ${MAKEOBJDIR}/LoginWindow/LoginWindow.app
SYSTEMUISERVER_APP= ${MAKEOBJDIR}/SystemUIServer/SystemUIServer.app

# A shell loop, not a bmake prerequisite: bmake stats the source path to decide
# whether the target is out of date, and on this host the sub-app objdir path is
# intermittently invisible to stat (readdir still lists it), which makes bmake
# abort with "don't know how to make". Copying inside the recipe with retries
# sidesteps that.
all: stage-subapps
stage-subapps:
	@for app in LoadingWindow LoginWindow SystemUIServer; do \
		src=${MAKEOBJDIR}/$$app/$$app.app; \
		dst=${APP_DIR}/Contents/Resources/$$app.app; \
		rm -rf $$dst; \
		ok=0; \
		for i in 1 2 3 4 5 6 7 8 9 10; do \
			if cp -Rfp "$$src" $$dst 2>/dev/null; then ok=1; break; fi; \
			sleep 1; \
		done; \
		if [ $$ok -ne 1 ]; then \
			echo "stage-subapps: cannot copy $$app from $$src" >&2; \
			exit 1; \
		fi; \
		echo "staged $$app.app"; \
	done

${OBJS}: ${MAKEOBJDIR}/Resources

client: client.m message.h
	mkdir -p ${.CURDIR}/client.app/Contents/ravynOS
	cd ${.CURDIR}; ${CC} -g -fobjc-arc -fobjc-runtime=gnustep-2.0 -fobjc-nonfragile-abi \
		-fPIC -o ${.CURDIR}/client.app/Contents/ravynOS/client client.m \
		-framework Foundation -framework CoreFoundation \
		-framework CoreGraphics -framework AppKit -lSystem

