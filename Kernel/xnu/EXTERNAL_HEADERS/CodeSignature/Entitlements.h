/*
 * Copyright (c) 2026 ravynOS Project. All rights reserved.
 *
 * Vendor of the Apple SDK header <CodeSignature/Entitlements.h> for the
 * kernel build, which compiles with -nostdlibinc and therefore cannot see
 * the SDK usr/include tree. Only the constants consumed by XNU are defined
 * here (bsd/kern/kern_exec.c and bsd/net/necp_client.c).
 *
 * These are the entitlement keys historically used to mark WebKit's
 * out-of-process browser services and the host browser application. The
 * kernel compares them as opaque strings (hardened-runtime web browser
 * detection in kern_exec.c, web network entitlement checks in
 * necp_client.c), so they are defined as string literals rather than
 * CFStringRef externs (the kernel does not link CoreFoundation).
 */

#ifndef _CODESIGNING_ENTITLEMENTS_H_
#define _CODESIGNING_ENTITLEMENTS_H_

#define kCSWebBrowserHostEntitlement        "com.apple.WebKit.web-host"
#define kCSWebBrowserGPUEntitlement         "com.apple.WebKit.web-gpu"
#define kCSWebBrowserNetworkEntitlement     "com.apple.WebKit.web-network"
#define kCSWebBrowserWebContentEntitlement  "com.apple.WebKit.web-content"

#endif /* _CODESIGNING_ENTITLEMENTS_H_ */
