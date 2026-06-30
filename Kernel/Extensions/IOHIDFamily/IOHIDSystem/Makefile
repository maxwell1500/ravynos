MK_WERROR = no
KEXT = IOHIDSystem
INFO_PLIST = Info-IOHIDSystem.plist
BUNDLE_IDENTIFIER = com.apple.iokit.IOHIDFamily
BUNDLE_VERSION = 1.5.2
KERNEL_PRIVATE = yes

.PATH: ${.CURDIR:H}
SRCS = \
	HIDDriverKit/IOHIDDevice.iig \
	HIDDriverKit/IOHIDEventService.iig \
	IOHIDFamily/IOHIDUserDevice.cpp \
	IOHIDFamily/AppleUserHIDDevice.cpp \
	IOHIDFamily/IOHIDEventServiceFastPathUserClient.cpp \
	IOHIDSystem/IOHIDKeyboardEventDevice.cpp \
	IOHIDFamily/IOHIDEventServiceUserClient.cpp \
	IOHIDFamily/IOHIDLibUserClient.cpp \
	HIDDriverKit/IOHIDDevice.cpp \
	IOHIDFamily/IOHIDEventQueue.cpp \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetButtonCaps.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetCaps.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetCollectionNodes.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetValueCaps.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDHasUsage.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDMaxUsageListLength.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDNextItem.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDOpenCloseDescriptor.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDParseDescriptor.c \
	HIDDriverKit/IOHIDElementContainer.cpp \
	IOHIDSystem/IOHIDDescriptorParser/HIDProcessCollection.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDProcessGlobalItem.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDProcessLocalItem.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDProcessMainItem.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDProcessReportItem.c \
	IOHIDFamily/AppleUserHIDEventService.cpp \
	IOHIDSystem/IOHIDDescriptorParser/HIDUsageInRange.c \
	IOHIDFamily/IOHIDDeviceElementContainer.cpp \
	IOHIDSystem/IOHIDDescriptorParser/PoolAlloc.c \
	IOHIDSystem/IOHIDevice.cpp \
	IOHIDSystem/IOHIDIO.cpp \
	HIDDriverKit/IOHIDElementPrivate.cpp \
	HIDDriverKit/IOHIDInterface.cpp \
	HIDDriverKit/IOHIDInterface.iig \
	HIDDriverKit/IOHIDEventService.cpp \
	IOHIDFamily/IOHIDActionQueue.cpp \
	IOHIDFamily/IOHIDProviderPropertyMerger.cpp \
	IOHIDFamily/IOHIDEventDriver.cpp \
	IOHIDFamily/AppleEmbeddedKeyboard.cpp \
	IOHIDFamily/IOHIDEventRepairDriver.cpp \
	IOHIDFamily/IOHIDFamilyPrivate.cpp \
	HIDDriverKit/IOHIDEvent.cpp \
	IOHIDSystem/IOHIDDescriptorParser/HIDCountDescriptorItems.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetReportLength.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDIsButtonOrValue.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDCheckReport.c \
	IOHIDFamily/IOHIDEventSource.cpp \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetButtonsOnPage.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetButtons.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetUsageValue.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetUsageValueArray.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetNextUsageValueInfo.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetNextButtonInfo.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDGetData.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDInitReport.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDPostProcessRIValue.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDPutData.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDScaleUsageValue.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDUsageListDifference.c \
	IOHIDSystem/IOHIDPointingEventDevice.cpp \
	IOHIDSystem/IOHIDDescriptorParser/HIDUsageAndPageFromIndex.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDSetUsageValueArray.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDSetUsageValue.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDSetScaledUsageValue.c \
	IOHIDSystem/IOHIDDescriptorParser/HIDSetButtons.c \
	IOHIDFamily/Cosmo_USB2ADB.c \
	IOHIDFamily/IOHIDConsumer.cpp \
	IOHIDFamily/IOHIDKeyboard.cpp \
	IOHIDFamily/IOHIDPointing.cpp \
	IOHIDSystem/IOHIDPrivate.cpp \
	IOHIDSystem/IOHIDPointingDevice.cpp \
	IOHIDSystem/IOHIDKeyboardDevice.cpp \
	IOHIDSystem/IOHIDSystem.cpp \
	IOHIDSystem/IOHIKeyboard.cpp \
	IOHIDSystem/IOHIKeyboardMapper.cpp \
	IOHIDSystem/IOHIPointing.cpp \
	IOHIDSystem/IOHITablet.cpp \
	IOHIDSystem/IOHITabletPointer.cpp \
	IOHIDSystem/IOHIDDeviceShim.cpp \
	IOHIDFamily/IOHIDEventServiceQueue.cpp \
	IOHIDSystem/IOHIDUserClient.cpp \
	IOHIDSystem/IOFixed64.cpp \
	IOHIDSystem/IOHIDWorkLoop.cpp \
	IOHIDSystem/IOFixedPoint64.cpp \
	IOHIDSystem/IOHIDSystemCursorHelper.cpp \
	IOHIDFamily/IOHIDResourceUserClient.cpp \
	IOHIDFamily/IOHIDResource.cpp

CFLAGS = -Wno-implicit-int-conversion -Wno-sign-conversion \
	-I${.CURDIR}/include \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/iokit \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
	-I${.CURDIR:H}/IOPCIFamily \
	-I${.CURDIR:H}/AppleAPIC \
	-I${.CURDIR:H}/RavynAHCIPort

LDFLAGS = -mmacos-version-min=${MACOS_VERSION_MIN} --sysroot=${RAVYN_SDKROOT} \
	-fuse-ld=${LD}

.include <rvn.kext.mk>
