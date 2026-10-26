MK_WERROR = no
FRAMEWORK = SystemConfiguration
FMWK_VERSION = A
FMWK_COMPAT_VERSION = 1.0.0
FMWK_CURRENT_VERSION = 1300.6.4
INFO_PLIST = Info.plist

# The tree carries Apple's full SystemConfiguration sources -- SCD (the configd
# client), the SCNetworkConfiguration editors, VPN/PPP/DHCP/CaptiveNetwork
# support -- and none of it builds or applies here: all of it is a client of a
# configd daemon this system does not ship.  What applications actually link
# against is the dynamic store, SCPreferences and SCNetworkReachability, so
# this framework implements those against a process-local store and a real
# routing-table probe, and does not pretend to provide the rest.
SRCS = SystemConfigurationRuntime.c
HEADERS = Headers/SystemConfiguration.h

CFLAGS += -I${.CURDIR}/Headers -I${ROOT_SOURCE_DIR}/Frameworks/CoreFoundation \
	-I${RAVYN_SDKROOT}/System/Library/Frameworks/CoreFoundation.framework/Headers \
	-I${RAVYN_SDKROOT}/usr/include

LDFLAGS += -F${RAVYN_SDKROOT}/System/Library/Frameworks \
	-Wl,-framework,CoreFoundation -lSystem

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT} ${SYSROOT_DIR} ${RAVYN_REPO_SDKROOT}
	@if [ -n "${dir}" ]; then \
		mkdir -p "${dir}/System/Library/Frameworks" && \
		cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework "${dir}/System/Library/Frameworks/"; \
	fi
.endfor

.include <rvn.framework.mk>
