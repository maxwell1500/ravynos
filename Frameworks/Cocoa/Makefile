FRAMEWORK=Cocoa
MK_WERROR=no
.include "../framework.common.mk"

SRCS=Cocoa.m
INCS=Cocoa.h

RESOURCES=Info.plist
CFLAGS+= ${FMWK_CFLAGS} -Wno-incompatible-sysroot -Wno-nullability-completeness -Wno-missing-method-return-type -I${ROOT_SOURCE_DIR}/Frameworks -I../Foundation/Headers \
	-I${.CURDIR}/../AppKit/Headers -F../OpenGL \
	-I${SRCTOP}/CoreServices -framework OpenGL
LDFLAGS+= -F${OBJTOP}/Frameworks/AppKit -framework AppKit \
	-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
	-F${OBJTOP}/Frameworks/CoreFoundation -framework CoreFoundation \
        -lobjc \
        -Wl,-rpath,/System/Library/Frameworks/AppKit.framework/Versions/A \
        -Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/A \
        -Wl,-rpath,/System/Library/Frameworks/CoreFoundation.framework/Versions/A

.include <rvn.framework.mk>

installresources: std_install_hook
