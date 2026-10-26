FRAMEWORK=Cocoa
# Apple's compatibility version; dyld refuses to load this framework for a
# binary that recorded a higher one, so it has to match at least.
FMWK_COMPAT_VERSION = 1.0.0
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

# The in-repo SDK is an install product, not a source tree, and it is what
# tools/bootlab/make_gui_manifest.py stages frameworks from.  Without this
# hook a copy only ever appeared there by hand, which is how an untracked and
# stale Cocoa.framework came to sit in the tree.  The empty-string guard keeps
# a manual build with no RAVYN_* variable set from installing into the host.
fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>

installresources: std_install_hook
