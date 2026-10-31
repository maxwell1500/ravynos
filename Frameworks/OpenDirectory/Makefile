MK_WERROR = no
FRAMEWORK = OpenDirectory
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.0.0
FMWK_CURRENT_VERSION = 606.0.0
INFO_PLIST = Framework/Info.plist

.PATH: ${.CURDIR}/Framework ${.CURDIR}/Core

SRCS = ODSession.m \
       ODNode.m \
       ODRecord.m \
       ODQuery.m \
       ODContext.m \
       constants.c

HEADERS = Framework/OpenDirectory.h \
          Framework/ODSession.h \
          Framework/ODNode.h \
_OD_INCLUDES = -I${.CURDIR}/include \
               -I${.CURDIR}/Framework \
               -I${.CURDIR}/Core \
               -I${.CURDIR}/DirectoryService \
               -I${RAVYN_SDKROOT}/System/Library/Frameworks/Foundation.framework/Headers \
               -I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
               -I${RAVYN_SDKROOT}/usr/include

CFLAGS += ${_OD_INCLUDES}
STATIC_CFLAGS += ${_OD_INCLUDES}
SHARED_CFLAGS += ${_OD_INCLUDES}
FMWK_FLAG += ${_OD_INCLUDES}
OBJCFLAGS += ${_OD_INCLUDES}
LDFLAGS += -F${RAVYN_SDKROOT}/System/Library/Frameworks \
           -Wl,-framework,Foundation -Wl,-framework,CoreFoundation -lSystem

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
