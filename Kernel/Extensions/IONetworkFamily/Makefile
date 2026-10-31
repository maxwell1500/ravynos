MK_WERROR = no
SUBDIR =
KEXT = IONetworkFamily
KERNEL_PRIVATE = yes
INFO_PLIST = Info.plist
BUNDLE_IDENTIFIER = com.ravynos.iokit.IONetworkFamily
BUNDLE_VERSION = 1.0.0

SRCS = IONetworkFamily.cpp

CFLAGS = -Wno-implicit-int-conversion -Wno-sign-conversion \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/iokit \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/osfmk \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk

.include <rvn.kext.mk>
