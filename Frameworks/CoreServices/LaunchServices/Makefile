MK_WERROR = no
FRAMEWORK = LaunchServices
FMWK_VERSION = A

SRCS = LaunchServices.mm LSAppRecord.mm UTTypes.mm LSIPC.mm
HEADERS = LaunchServices.h UTCoreTypes.h UTTypes.h
# rvn.framework.mk stages RESOURCES_FILES, not RESOURCES, so the old
# `RESOURCES= ...` line was inert. LaunchServices.mm reads InitDB.sql out of
# the bundle's Resources (pathForResource:@"InitDB" ofType:@"sql") to create
# the database, so the schema files must actually land in the bundle.
RESOURCES_FILES = Info.plist InitDB.sql DBSchema_3_4.sql

# LSAppRecord.mm imports <LaunchServices/LSAppRecord.h>. That framework-style
# include resolves through the SDK once the framework is installed, but not
# while it is being built, so put the parent directory on the include path:
# <LaunchServices/X.h> then reaches the sources in ${.CURDIR}.
#
# -I${ROOT_SOURCE_DIR}/Frameworks is what makes <CFNetwork/CFNetwork.h> resolve.
# Foundation.h:61 imports <CoreServices/CoreServices.h>, whose whole body is
# `#import <CFNetwork/CFNetwork.h>`. CFNetwork.framework is not built here (it
# needs Security.framework and SystemConfiguration.framework, neither of which
# exists or has a framework Makefile), but the header source is real and this
# is exactly how AppKit and WindowServer already resolve it -- their build logs
# show CFNetwork.h coming from ${ROOT_SOURCE_DIR}/Frameworks/CFNetwork/.
CFLAGS = -fobjc-arc -I${.CURDIR:H} -I${.CURDIR} -I${ROOT_SOURCE_DIR}/Frameworks
LDFLAGS = -lsqlite3 -llaunch

# Without this the framework was built into the object directory and never
# installed anywhere -- the empty override suppressed rvn.framework.mk's
# default and nothing replaced it. Install it into both SDK trees the way
# CoreFoundation/CoreGraphics do.
fmwk-install-hook:
	# ravynOS: see Frameworks/Foundation/Makefile's fmwk-install-hook -- RAVYN_REPO_SDKROOT
	# is the in-repo SDK the manifest stages from and prefers.
.for dir in ${RAVYN_SDKROOT}/System/Library/Frameworks/ ${SYSROOT_DIR}/System/Library/Frameworks/ ${RAVYN_REPO_SDKROOT}/System/Library/Frameworks/
	mkdir -p ${dir}
	cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework ${dir}
.endfor

.include <rvn.framework.mk>

