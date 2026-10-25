FRAMEWORK=PreferencePanes
.include "../framework.common.mk"

WARNS= 0
SRCS= NSPreferencePane.m
INCS= NSPreferencePane.h
RESOURCES= Info.plist 
CFLAGS+= ${FMWK_CFLAGS:N-D__WSRPC} -fobjc-arc -I${OBJTOP}/Frameworks/Foundation/Headers \
	 -I${SRCTOP}/Frameworks/AppKit/Headers/
LDFLAGS+= -L${OBJTOP}/tmp/usr/lib 

# The in-repo SDK is an install product, not a source tree, and it is what
# tools/bootlab/make_gui_manifest.py stages frameworks from.  Without this
# hook a copy only ever appeared there by hand, which is how an untracked and
# stale PreferencePanes.framework came to sit in the tree.  The empty-string
# guard keeps a manual build with no RAVYN_* variable set from installing
# into the host.
fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>

installresources: std_install_hook
