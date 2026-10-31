MK_WERROR = no
SUBDIR =
KEXT = IntelE1000
KERNEL_PRIVATE = yes
INFO_PLIST = Info.plist
BUNDLE_IDENTIFIER = com.ravynos.driver.IntelE1000
BUNDLE_VERSION = 1.0.0

SRCS = IntelE1000.cpp

CFLAGS = -Wno-implicit-int-conversion -Wno-sign-conversion \
	-I${ROOT_SOURCE_DIR}/Kernel/Extensions \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/iokit \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
	-I${ROOT_SOURCE_DIR}/Kernel/Extensions/IOPCIFamily \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk

.include <rvn.kext.mk>
