# ravynOS `open` command.
#
# The old Makefile compiled with a hand written ${CC} rule against a sysroot
# that does not exist on this host (/usr/obj/.../tmp) and used ld64's
# rejected -Wl,-R flag.  It now builds with the same environment as every
# other ravynOS component (the platform clang-17 through isysroot-cc) against
# the SDK's Foundation and LaunchServices frameworks.
PROG=	open
SRCS=	open.m
# There is no open(1) man page in this tree; bsd.prog.mk's "all" target would
# otherwise fail trying to install one.
MAN= 

MK_WERROR=	no
MK_PIE=		no
WARNS=		1

CFLAGS+=	-g -O2 --sysroot=${RAVYN_SDKROOT} -D__RAVYNOS__ -D__MACH__ -fobjc-runtime=gnustep-2.0 \
		-fobjc-nonfragile-abi -fPIC -pthread \
		-Wno-missing-method-return-type -Wno-macro-redefined \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${ROOT_SOURCE_DIR}/Frameworks \
		-I${ROOT_SOURCE_DIR}/Frameworks/CoreServices/LaunchServices \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks \
		-F${OBJTOP}/Frameworks/Foundation \
		-I${OBJTOP}/Frameworks/Foundation/Headers

LDFLAGS+=	-F${RAVYN_SDKROOT}/System/Library/Frameworks -framework Foundation \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks -framework LaunchServices \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-Wl,-rpath,/System/Library/Frameworks/LaunchServices.framework/Versions/A \
		-L${RAVYN_SDKROOT}/usr/lib -lobjc -lSystem

.include <bsd.prog.mk>
