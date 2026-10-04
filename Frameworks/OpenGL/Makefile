FRAMEWORK=OpenGL
MK_WERROR = no

.include "../framework.common.mk"

MK_INSTALLLIB= no
SRCS=	OpenGL.c
HEADERS= \
	include/CGLCurrent.h \
	include/CGLTypes.h \
	include/gl.h \
	include/glext.h \
	include/glplatform.h \
	include/OpenGL.h \
        include/egl.h \
        include/eglext.h \
        include/eglextchromium.h \
        include/eglexternalplatform.h \
        include/eglexternalplatformversion.h \
        include/eglmesaext.h \
        include/eglplatform.h \
        include/khrplatform.h
RESOURCES=      Info.plist

CFLAGS+= ${FMWK_CFLAGS} -I${SRCTOP}/Frameworks -I${.CURDIR}/include
CFLAGS+= -I${SRCTOP}/Frameworks/Foundation/Headers
LDFLAGS+=


.include <rvn.framework.mk>

installresources: std_install_hook
