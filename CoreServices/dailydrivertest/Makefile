PROG=	dailydrivertest
SRCS=	dailydrivertest.m
# There is no man page for the self test; bsd.prog.mk's "all" target would
# otherwise fail trying to install one.
MAN= 

MK_WERROR=	no
MK_PIE=		no
WARNS=		1

CFLAGS+=	-g -O2 -fobjc-arc -D__MACH__ -D__RAVYNOS__ -fPIC -pthread \
		-Wno-missing-method-return-type -Wno-macro-redefined \
		-I${.CURDIR} \
		-I${ROOT_SOURCE_DIR}/Frameworks \
		-I${ROOT_SOURCE_DIR}/Frameworks/CoreServices/LaunchServices \
		-I${ROOT_SOURCE_DIR}/CoreServices \
		-I${OBJTOP}/Frameworks/Foundation/Headers \
		-I${OBJTOP}/Frameworks/AppKit/Headers \
		-I${RAVYN_SDKROOT}/usr/include \
		-I${RAVYN_SDKROOT}/usr/local/include/kernel \
		-F${OBJTOP}/Frameworks/AppKit -F${OBJTOP}/Frameworks/Foundation \
		-F${OBJTOP}/Frameworks/CoreGraphics \
		-F${RAVYN_SDKROOT}/System/Library/Frameworks

LDFLAGS+=	-F${RAVYN_SDKROOT}/System/Library/Frameworks -framework LaunchServices \
		-F${OBJTOP}/Frameworks/AppKit -framework AppKit \
		-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
		-Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
		-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/C \
		-L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/lib/system -lobjc -lSystem

.include <bsd.prog.mk>
