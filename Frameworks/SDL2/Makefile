MK_WERROR = no
FRAMEWORK = SDL2
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.0.0
FMWK_CURRENT_VERSION = 3201.10.0
INSTALL_NAME = /usr/lib/libSDL2-2.0.0.dylib

.PATH: ${.CURDIR}/src

SRCS = \
	SDL_ravynos_core.m \
	SDL_ravynos_video.m \
	SDL_ravynos_surface.c \
	SDL_ravynos_render.c \
	SDL_ravynos_events.m \
	SDL_ravynos_timer_thread_audio.c \
	SDL_ravynos_devices_stubs.c

HEADERS != cd ${.CURDIR} && echo Headers/*.h
RESOURCES_FILES = Info.plist

CFLAGS += -fobjc-exceptions -fblocks -Wno-deprecated-declarations \
	-D__RAVYNOS__=1 -D_REENTRANT \
	-I${.CURDIR}/Headers \
	-I${.CURDIR}/src \
	-I${ROOT_SOURCE_DIR}/Frameworks \
	-I${ROOT_SOURCE_DIR}/Frameworks/Foundation/Headers \
	-I${OBJTOP}/Frameworks/AppKit/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/Foundation.framework/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreGraphics.framework/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/Onyx2D.framework/Headers \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/AppKit.framework/Headers \
	-I${RAVYN_SDKROOT}/usr/include \
	-F${RAVYN_SDKROOT}/System/Library/Frameworks

LDFLAGS += \
	-F${RAVYN_SDKROOT}/System/Library/Frameworks \
	-Wl,-framework,AppKit \
	-Wl,-framework,Foundation \
	-Wl,-framework,CoreGraphics \
	-Wl,-framework,Onyx2D \
	-Wl,-framework,CoreFoundation \
	-L${RAVYN_SDKROOT}/usr/lib \
	-lobjc -lpthread -lm

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" "${dir}/usr/lib" "${dir}/usr/include/SDL2" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/" && \
		cp -fp ${.OBJDIR}/${FRAMEWORK}.framework/Versions/${FMWK_VERSION}/${FRAMEWORK} "${dir}/usr/lib/libSDL2-2.0.0.dylib" && \
		ln -sfn libSDL2-2.0.0.dylib "${dir}/usr/lib/libSDL2.dylib" && \
		cp -fp ${.CURDIR}/Headers/*.h "${dir}/usr/include/SDL2/"; \
	fi
.endfor

.include <rvn.framework.mk>
