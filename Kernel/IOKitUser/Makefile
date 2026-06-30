MK_WERROR = no
FRAMEWORK = IOKit
FMWK_VERSION = A
INFO_PLIST = Info.plist
INSTALL_NAME_DIR = /System/Library/Frameworks/IOKit.framework/Versions/A

.PATH: ${.OBJDIR}
SRCS = \
	iokitmig64.c \
	hid.subproj/IOHIDEventObjc.m \
	hid.subproj/IOHIDServiceObjc.m \
	hid.subproj/IOHIDSessionObjc.m \
	hid.subproj/IOHIDConnectionObjc.m \
	hid.subproj/IOHIDElementObjc.m \
	hid.subproj/IOHIDServiceClientObjc.m \
	hid.subproj/IOHIDDeviceObjc.m \
	hid.subproj/HIDEventBase.m \
	hid.subproj/HIDServiceBase.m \
	hid.subproj/HIDSessionBase.m \
	hid.subproj/HIDConnectionBase.m \
	hid.subproj/HIDElementBase.m \
	hid.subproj/HIDServiceClientBase.m \
	hid.subproj/HIDDeviceBase.m \
	kext.subproj/cross_link.c \
	IOCFSerialize.c \
	IOCFUnserialize.tab.c \
	IOKitLib.c \
	IOCFURLAccess.c \
	hid.subproj/IOHIDAnalytics.c \
	IODataQueueClient.c \
	IOCFPlugIn.c \
	IOTrap.s \
	pwr_mgt.subproj/IOPMLib.c \
	pwr_mgt.subproj/IOPMEnergyPrefs.c \
	pwr_mgt.subproj/IOPMAutoWake.c \
	pwr_mgt.subproj/IOPMRepeatingPower.c \
	pwr_mgt.subproj/IOPMUPSPrefs.c \
	usb.subproj/IOUSBLib.c \
	network.subproj/IONetworkLib.c \
	graphics.subproj/IOAccelSurfaceControl.c \
	graphics.subproj/IOGraphicsLib.c \
	graphics.subproj/IODisplayLib.c \
	hidsystem.subproj/IOEventStatusAPI.c \
	kext.subproj/AdjustForNewSegmentLocation.cpp \
	hidsystem.subproj/IOHIDLib.c \
	kext.subproj/KextManager.c \
	ps.subproj/IOPowerSources.c \
	hid.subproj/IOHIDServiceConnectionCache.c \
	ps.subproj/IOPowerSourcesPrivate.c \
	pwr_mgt.subproj/IOPMLibPrivate.c \
	IOSystemConfiguration.c \
	hid.subproj/IOHIDValue.c \
	hid.subproj/IOHIDSessionFilter.c \
	hid.subproj/IOHIDElement.c \
	kext.subproj/fat_util.c \
	kext.subproj/macho_util.c \
	hid.subproj/IOHIDDevice.c \
	hid.subproj/IOHIDServiceKeys.c \
	hid.subproj/IOHIDLibPrivate.c \
	hid.subproj/IOHIDManager.c \
	hid.subproj/IOHIDQueue.c \
	hid.subproj/IOHIDTransaction.c \
	hid.subproj/IOHIDEvent.c \
	hid.subproj/IOHIDEventSystem.c \
	hid.subproj/IOHIDConnectionFilter.c \
	hid.subproj/IOHIDEventSystemClient.c \
	hid.subproj/IOHIDNotification.c \
	hid.subproj/IOHIDService.c \
	hid.subproj/IOHIDSession.c \
	hid.subproj/IOHIDEventQueue.c \
	pwr_mgt.subproj/IOPMPowerNotifications.c \
	kext.subproj/OSKextVersion.c \
	kext.subproj/misc_util.c \
	kext.subproj/printPList_new.c \
	IOMIGMachPort.c \
	kext.subproj/OSKext.c \
	hid.subproj/IOHIDEventSystemPrivate.c \
	kext.subproj/kextsplit.h \
	hid.subproj/IOHIDServiceFilter.c \
	hid.subproj/IOHIDServiceClient.c \
	hid.subproj/IOHIDEventSystemConnection.c \
	hid.subproj/IOHIDEventServer.c \
	pwr_mgt.subproj/IOPMAssertions.c \
	network.subproj/IOUserEthernetController.c \
	hid.subproj/IOHIDUserDevice.c \
	hid.subproj/IOHIDPlugins.c \
	platform.subproj/IOPlatformSupport.c

DEFS = -DAPPLE -DPRIVATE -D_ANSI_C_SOURCE -Dvolatile=__volatile \
	-DNO_SECURITY_FRAMEWORK \
	-DAVAILABLE_MAC_OS_X_VERSION_10_13_AND_LATER="" \
	-DAVAILABLE_MAC_OS_X_VERSION_10_15_AND_LATER="" \
	-DIOKIT -DTYPE_LONGLONG -DTARGET_OS_IOSMAC=0 \
	-DDISPATCH_MACH_SPI \
	-DOS_CRASH_ENABLE_EXPERIMENTAL_LIBTRACE \
	-DOS_OBJECT_USE_OBJC
#HAVE_CFPLUGIN HAVE_CFURLACCESS

SLF = /System/Library/Frameworks

CSTD = gnu11
CXXSTD = gnu++17

CFLAGS = ${DEFS} -fblocks --sysroot=${RAVYN_SDKROOT} \
	-mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wno-nullability-completeness \
	-Wno-implicit-function-declaration \
	-Wno-elaborated-enum-base -Wno-int-conversion
# CF_ENUM, rdar://121475724

CFLAGS += -x objective-c \
	-I${.CURDIR}/../xnu/osfmk \
	-I${.CURDIR}/../xnu/libkern -I${.CURDIR}/../xnu/iokit \
	-I${.OBJDIR} \
	-I${RAVYN_SDKROOT}/usr/local/include \
	-I${.CURDIR}/../../Libraries/Libsystem/private \
	-I${.CURDIR}/../../Libraries/Libsystem/libdispatch/private \
	-I${.CURDIR}/../../Libraries/Libsystem/liblaunch \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/san \
	-I${RAVYN_SDKROOT}${SLF}/System.framework/PrivateHeaders \
	-I${RAVYN_SDKROOT}${SLF}/Kernel.framework/Headers \
	-UKERNEL \
	-include${RAVYN_SDKROOT}/usr/include/i386/endian.h \
	-include${.CURDIR:H}/xnu/libkern/libkern/OSTypes.h \
	-include${RAVYN_SDKROOT}/usr/include/MacTypes.h \
	-include${RAVYN_SDKROOT}/usr/local/include/kernel/os/object.h \
	-I${ROOT_SOURCE_DIR}/Frameworks \
	-I${ROOT_SOURCE_DIR}/Frameworks/Security/header_symlinks \
	-I${ROOT_SOURCE_DIR}/Frameworks/Security/header_symlinks/macOS \
	${CFLAGS.${.TARGET:T}}

ACFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN}

CFLAGS.IOMIGMachPort.o = -include${RAVYN_SDKROOT}/usr/include/mach/error.h

MIG_DEFS = -DIOKIT -DPRIVATE -DNO_SECURITY_FRAMEWORK
MIGFLAGS = -cc ${CC} -novouchers -server /dev/null ${MIG_DEFS} \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk \
	-mmacos-version-min=${MACOS_VERSION_MIN}

iokitPrivateHdrs = ${RAVYN_SDKROOT}/System/Library/Frameworks/IOKit.framework/Versions/A/PrivateHeaders
iokitHdrs = ${RAVYN_SDKROOT}/System/Library/Frameworks/IOKit.framework/Versions/A/Headers

LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wl,-compatibility_version,1.0.0 -Wl,-current_version,275.0.0

all: copy_headers

copy_headers: .PHONY
	mkdir -p ${RAVYN_SDKROOT}/usr/local/include
	cp -f ${.CURDIR}/kext.subproj/bootfiles.h ${RAVYN_SDKROOT}/usr/local/include/
	mkdir -p ${iokitPrivateHdrs}/hidobjc
	cp -f \
		${.CURDIR}/hid.subproj/HIDDeviceBase.h \
		${.CURDIR}/hid.subproj/HIDDeviceIvar.h  \
		${.CURDIR}/hid.subproj/HIDServiceClientIvar.h \
		${.CURDIR}/hid.subproj/HIDServiceClientBase.h \
		${.CURDIR}/hid.subproj/HIDElementBase.h \
		${.CURDIR}/hid.subproj/HIDElementIvar.h \
		${.CURDIR}/hid.subproj/HIDConnectionBase.h \
		${.CURDIR}/hid.subproj/HIDConnectionIvar.h \
		${.CURDIR}/hid.subproj/HIDSessionIvar.h \
		${.CURDIR}/hid.subproj/HIDSessionBase.h \
		${.CURDIR}/hid.subproj/HIDEventBase.h \
		${.CURDIR}/hid.subproj/HIDServiceBase.h \
		${.CURDIR}/hid.subproj/HIDServiceIvar.h \
		${.CURDIR}/hid.subproj/hidobjcbase.h \
		${iokitPrivateHdrs}/hidobjc/
	mkdir -p ${RAVYN_SDKROOT}/usr/local/include/IOKit/kext
	cp -f \
		${.CURDIR}/kext.subproj/OSKext.h \
		${.CURDIR}/kext.subproj/OSKextPrivate.h \
		${.CURDIR}/kext.subproj/misc_util.h \
		${.CURDIR}/kext.subproj/fat_util.h \
		${.CURDIR}/kext.subproj/macho_util.h \
		${.CURDIR}/kext.subproj/KextManager.h \
		${.CURDIR}/kext.subproj/KextManagerPriv.h \
		${.CURDIR}/kext.subproj/kextmanager_types.h \
		${.CURDIR}/kext.subproj/kextmanager_mig.defs \
		${RAVYN_SDKROOT}/usr/local/include/IOKit/kext/
	mkdir -p ${iokitHdrs}/audio
	cp -f ${.CURDIR}/audio.subproj/IOAudioLib.h ${iokitHdrs}/audio/
	mkdir -p ${iokitHdrs}/hidsystem
	cp -f \
		${.CURDIR}/hidsystem.subproj/IOHIDUserDevice.h \
		${.CURDIR}/hidsystem.subproj/IOHIDServiceClient.h \
		${.CURDIR}/hidsystem.subproj/IOHIDEventSystemClient.h \
		${.CURDIR}/hidsystem.subproj/IOHIDLib.h \
		${.CURDIR}/hidsystem.subproj/event_status_driver.h \
		${iokitHdrs}/hidsystem/
	mkdir -p ${iokitHdrs}/hid
	cp -f \
		${.CURDIR}/hid.subproj/IOHIDAnalytics.h \
		${.CURDIR}/hid.subproj/IOHIDEventPrivate.h \
		${.CURDIR}/hid.subproj/IOHIDConnectionFilterPlugin.h \
		${.CURDIR}/hid.subproj/IOHIDServiceConnectionCache.h \
		${.CURDIR}/hid.subproj/IOHIDEventSystemClientPrivate.h \
		${.CURDIR}/hid.subproj/IOHIDEventSystemConnection.h \
		${.CURDIR}/hid.subproj/IOHIDEventSystemPrivate.h \
		${.CURDIR}/hid.subproj/IOHIDEventSystemKeysPrivate.h \
		${.CURDIR}/hid.subproj/IOHIDServiceClient.h \
		${.CURDIR}/hid.subproj/IOHIDServiceKeys.h \
		${.CURDIR}/hid.subproj/IOHIDServicePlugIn.h \
		${.CURDIR}/hid.subproj/IOHIDEventQueue.h \
		${.CURDIR}/hid.subproj/IOHIDEventSystem.h \
		${.CURDIR}/hid.subproj/IOHIDEventSystemClient.h \
		${.CURDIR}/hid.subproj/IOHIDEventSystemKeys.h \
		${.CURDIR}/hid.subproj/IOHIDNotification.h \
		${.CURDIR}/hid.subproj/IOHIDServicePrivate.h \
		${.CURDIR}/hid.subproj/IOHIDService.h \
		${.CURDIR}/hid.subproj/IOHIDTypes.h \
		${.CURDIR}/hid.subproj/IOHIDServiceFilterPlugIn.h \
		${.CURDIR}/hid.subproj/IOHIDSessionFilterPlugIn.h \
		${.CURDIR}/hid.subproj/IOHIDUserDevice.h \
		${.CURDIR}/hid.subproj/IOHIDBase.h \
		${.CURDIR}/hid.subproj/IOHIDDevice.h \
		${.CURDIR}/hid.subproj/IOHIDDevicePlugIn.h \
		${.CURDIR}/hid.subproj/IOHIDElement.h \
		${.CURDIR}/hid.subproj/IOHIDManager.h \
		${.CURDIR}/hid.subproj/IOHIDQueue.h \
		${.CURDIR}/hid.subproj/IOHIDTransaction.h \
		${.CURDIR}/hid.subproj/IOHIDValue.h \
		${.CURDIR}/hid.subproj/IOHIDLibPrivate.h \
		${iokitHdrs}/hid/
	mkdir -p ${iokitHdrs}/network
	cp -f \
		${.CURDIR}/network.subproj/IOUserEthernetController.h \
		${.CURDIR}/network.subproj/IONetworkLib.h \
		${iokitHdrs}/network/
	mkdir -p ${iokitHdrs}/ps
	cp -f \
		${.CURDIR}/ps.subproj/IOPowerSourcesPrivate.h \
		${.CURDIR}/ps.subproj/IOPSKeysPrivate.h \
		${iokitHdrs}/ps/
	mkdir -p ${iokitHdrs}/pwr_mgt
	cp -f \
		${.CURDIR}/pwr_mgt.subproj/IOPMUPSPrivate.h \
		${.CURDIR}/pwr_mgt.subproj/powermanagement_mig.h \
		${.CURDIR}/pwr_mgt.subproj/powermanagement.defs \
		${iokitHdrs}/pwr_mgt/
	cp -f \
		${.CURDIR}/IOKitLibPrivate.h \
		${.CURDIR}/IOCFSerialize.h \
		${.CURDIR}/IOCFUnserialize.h \
		${.CURDIR}/IOKitLib.h \
		${.CURDIR}/IOCFURLAccess.h \
		${.CURDIR}/IODataQueueClient.h \
		${iokitHdrs}/
	rm -f ${RAVYN_SDKROOT}${SLF}/IOKit.framework/Headers
	rm -f ${RAVYN_SDKROOT}${SLF}/IOKit.framework/PrivateHeaders
	ln -sf Versions/A/Headers ${RAVYN_SDKROOT}${SLF}/IOKit.framework/Headers
	ln -sf Versions/A/PrivateHeaders \
	  ${RAVYN_SDKROOT}${SLF}/IOKit.framework/PrivateHeaders

${FRAMEWORK}: kextmanager_mig.h powermanagement.h

.defs.h:
	${MIG} ${MIGFLAGS} -header ${.TARGET} ${.IMPSRC}

kextmanager_mig.h: ${.CURDIR}/kext.subproj/kextmanager_mig.defs
powermanagement.h: ${.CURDIR}/pwr_mgt.subproj/powermanagement.defs

iokitmig64.h iokitmig64.c: ${.CURDIR}/iokitmig.defs
	${MIG} ${MIGFLAGS} -header iokitmig64.h -user iokitmig64.c \
		${.CURDIR}/iokitmig.defs

# SUBDIR = kext.subproj

.include <rvn.kext.mk>
.include <bsd.subdir.mk>
