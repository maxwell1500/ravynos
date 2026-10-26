MK_WERROR = no
FRAMEWORK = IOKit
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.0.0
FMWK_CURRENT_VERSION = 100150.1
INFO_PLIST = Info.plist

# Frameworks/IOKit carries the IOFireWire/IOUSB/IONetwork plugin headers but no
# implementation.  The API third-party applications link against is the
# userland IOKitLib one, whose sources live under Kernel/IOKitUser.  Those
# cannot be built from here: they need the kernel's mach registry service and
# MIG stubs.  IOKitRuntime.c implements the same surface against an empty
# registry, so a caller gets the documented "nothing matched" results instead
# of a missing symbol at launch.
SRCS = IOKitRuntime.c

HEADERS += IOCFPlugIn.h
HEADERS += network/IONetworkLib.h network/IONetworkInterface.h \
	network/IONetworkData.h network/IONetworkMedium.h \
	network/IONetworkStats.h network/IOEthernetStats.h \
	network/IOEthernetInterface.h network/IOEthernetController.h \
	network/IONetworkController.h network/IONetworkStack.h
HEADERS += usb/IOUSBLib.h usb/USBSpec.h usb/AppleUSBDefinitions.h \
	usb/IOUSBHostFamilyDefinitions.h
HEADERS += firewire/IOFireWireLib.h firewire/IOFireWireLibIsoch.h \
	firewire/IOFireWireFamilyCommon.h firewire/IOFWIsoch.h

IOKITUSER = ${ROOT_SOURCE_DIR}/Kernel/IOKitUser
XNU_IOKIT_HDRS = ${ROOT_SOURCE_DIR}/Kernel/xnu/BUILD/dst/System/Library/Frameworks/IOKit.framework/Versions/A/Headers

# The userland headers spell their includes the Darwin way -- <IOKit/IOKitLib.h>,
# <IOKit/pwr_mgt/IOPMKeys.h> -- but live flat under Kernel/IOKitUser.  Build an
# include overlay in the object directory rather than symlinking into the
# source tree: same technique isysroot-cc uses for its mach and libkern shims,
# and it keeps the tree free of generated links.
IOKIT_INC = ${.OBJDIR}/inc

${IOKIT_INC}/.stamp:
	@mkdir -p "${IOKIT_INC}/IOKit/pwr_mgt"
	@ln -sfn "${IOKITUSER}/IOKitLib.h" "${IOKIT_INC}/IOKit/IOKitLib.h"
	@ln -sfn "${IOKITUSER}/IOKitLibPrivate.h" "${IOKIT_INC}/IOKit/IOKitLibPrivate.h"
	@ln -sfn "${IOKITUSER}/IOCFPlugIn.h" "${IOKIT_INC}/IOKit/IOCFPlugIn.h"
	@ln -sfn "${IOKITUSER}/pwr_mgt.subproj/IOPMLib.h" "${IOKIT_INC}/IOKit/pwr_mgt/IOPMLib.h"
	@ln -sfn "${IOKITUSER}/pwr_mgt.subproj/IOPMKeys.h" "${IOKIT_INC}/IOKit/pwr_mgt/IOPMKeys.h"
	@ln -sfn "${IOKITUSER}/pwr_mgt.subproj/IOPMLibDefs.h" "${IOKIT_INC}/IOKit/pwr_mgt/IOPMLibDefs.h"
	@ln -sfn "${IOKITUSER}/hid.subproj/IOHIDLib.h" "${IOKIT_INC}/IOKit/hid/IOHIDLib.h" 2>/dev/null || true
	@ln -sfn "${XNU_IOKIT_HDRS}/IOReturn.h" "${IOKIT_INC}/IOKit/IOReturn.h"
	@ln -sfn "${XNU_IOKIT_HDRS}/IOTypes.h" "${IOKIT_INC}/IOKit/IOTypes.h"
	@ln -sfn "${XNU_IOKIT_HDRS}/IOKitKeys.h" "${IOKIT_INC}/IOKit/IOKitKeys.h"
	@ln -sfn "${XNU_IOKIT_HDRS}/IOKitServer.h" "${IOKIT_INC}/IOKit/IOKitServer.h"
	@ln -sfn "${XNU_IOKIT_HDRS}/IOMessage.h" "${IOKIT_INC}/IOKit/IOMessage.h"
	@ln -sfn "${XNU_IOKIT_HDRS}/IOMapTypes.h" "${IOKIT_INC}/IOKit/IOMapTypes.h"
	@ln -sfn "${XNU_IOKIT_HDRS}/IODataQueueShared.h" "${IOKIT_INC}/IOKit/IODataQueueShared.h"
	@ln -sfn "${XNU_IOKIT_HDRS}/IOSerialStreamSync.h" "${IOKIT_INC}/IOKit/IOSerialStreamSync.h" 2>/dev/null || true
	@mkdir -p "${IOKIT_INC}/IOKit/hid"
	@touch "${IOKIT_INC}/.stamp"

CFLAGS += -I${IOKIT_INC} -I${.CURDIR} -I${IOKITUSER} \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
	-I${RAVYN_SDKROOT}/usr/include

LDFLAGS += -F${RAVYN_SDKROOT}/System/Library/Frameworks \
	-Wl,-framework,CoreFoundation

all: ${IOKIT_INC}/.stamp

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
