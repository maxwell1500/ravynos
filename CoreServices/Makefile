THISDIR:= ${.CURDIR}

all: clean build
clean:
# BUILDROOT is the staging rootfs. It is supplied by the release build wrapper
# (tools/build.sh / Makefile.ravynOS) and is NOT defined by the top-level
# Makefile. Without this guard an unset BUILDROOT turns the line below into
# `rm -rf /System/Library/CoreServices`, i.e. it deletes the host's own
# CoreServices whenever this directory is visited by a bare `make`.
.if defined(BUILDROOT) && !empty(BUILDROOT)
	rm -rf ${BUILDROOT}/System/Library/CoreServices
.endif
	rm -rf /usr/obj/${TOPDIR}/${MACHINE}.${MACHINE_CPUARCH}/CoreServices/Dock
	rm -rf /usr/obj/${TOPDIR}/${MACHINE}.${MACHINE_CPUARCH}/CoreServices/WindowServer

DMIHelper: ${.CURDIR}/DMIHelper.c
	mkdir -p ${BUILDROOT}/System/Library/CoreServices
	$(CC) -o ${BUILDROOT}/System/Library/CoreServices/DMIHelper ${.CURDIR}/DMIHelper.c
	${SUDO} chown 0:0 ${BUILDROOT}/System/Library/CoreServices/DMIHelper
	${SUDO} chmod 4755 ${BUILDROOT}/System/Library/CoreServices/DMIHelper

build: buildWindowServer DMIHelper buildDock buildFiler
	mkdir -p ${BUILDROOT}/System/Library/CoreServices/
	mkdir -p ${BUILDROOT}/Applications/Utilities/
	cp -av ${OBJTOP}/CoreServices/WindowServer/WindowServer.app ${BUILDROOT}/System/Library/CoreServices
	cp -av ${OBJTOP}/CoreServices/Dock/Dock.app ${BUILDROOT}/System/Library/CoreServices
	cp -av ${OBJTOP}/CoreServices/Filer/Filer.app ${BUILDROOT}/System/Library/CoreServices
.for f in ${.CURDIR}/askpass 
	cp -fv ${f} ${BUILDROOT}/System/Library/CoreServices/
	chmod 755 ${BUILDROOT}/System/Library/CoreServices/$$(basename ${f})
.endfor

buildFiler:
	${MAKE} -C ${.CURDIR}/Filer obj all

buildDock:
	mkdir -p ${MAKEOBJDIR}/Dock/Trash
	mkdir -p ${MAKEOBJDIR}/Dock/Downloads
	${MAKE} -C ${.CURDIR}/Dock obj all

buildWindowServer:
	${MAKE} -C ${.CURDIR}/WindowServer make-obj-dirs obj all
	${MAKE} -C ${.CURDIR}/WindowServer/SystemUIServer
	${MAKE} -C ${.CURDIR}/WindowServer/LoadingWindow
	${MAKE} -C ${.CURDIR}/WindowServer/LoginWindow
	cp -afv ${OBJTOP}/CoreServices/WindowServer/SystemUIServer/SystemUIServer.app \
	        ${OBJTOP}/CoreServices/WindowServer/LoadingWindow/LoadingWindow.app \
	        ${OBJTOP}/CoreServices/WindowServer/LoginWindow/LoginWindow.app \
                ${OBJTOP}/CoreServices/WindowServer/WindowServer.app/Contents/Resources/

