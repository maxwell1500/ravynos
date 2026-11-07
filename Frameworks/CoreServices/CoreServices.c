/* Placeholder for future implementation.
 * CoreServices is not yet implemented in ravynOS. This stub exists so
 * the framework can be linked; it should eventually contain the
 * CoreServices API surface (FSRef, FSSpec, LaunchServices, etc.). */
#include "CoreServices.h"

/* placeholder until we write more of this */
int __stub(void)
{
    return 0;
}

/*
 * LaunchServices scheme-handler entry points, also exported from CoreServices.
 *
 * XUL binds these with CoreServices as the two-level-namespace library, and
 * dyld did not follow CoreServices' LC_REEXPORT_DYLIB for the newer entries
 * even though the same call resolved when LaunchServices was bound directly.
 * Export real answers from the umbrella itself: this build has no scheme
 * handler registry, so the honest result is "no handlers" / "no default".
 */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

CFArrayRef LSCopyAllHandlersForURLScheme(CFStringRef inURLScheme)
{
    static int logged = 0;
    if (!logged) {
        logged = 1;
        fprintf(stderr, "[compat] CoreServices: LSCopyAllHandlersForURLScheme has no handler registry; returning empty\n");
    }
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
}

CFStringRef LSCopyDefaultHandlerForURLScheme(CFStringRef inURLScheme)
{
    return NULL;
}

CFURLRef LSCopyDefaultApplicationURLForURL(CFURLRef inURL, uint32_t inRoleMask, CFErrorRef *outError)
{
    static int logged = 0;
    if (!logged) {
        logged = 1;
        fprintf(stderr, "[compat] CoreServices: LSCopyDefaultApplicationURLForURL has no handler registry; returning NULL\n");
    }
    if (outError)
        *outError = NULL;
    return NULL;
}

CFURLRef LSCopyApplicationForMIMEType(CFStringRef inMIMEType, uint32_t inRoleMask, CFErrorRef *outError)
{
    static int logged = 0;
    if (!logged) {
        logged = 1;
        fprintf(stderr, "[compat] CoreServices: LSCopyApplicationForMIMEType has no handler registry; returning NULL\n");
    }
    if (outError)
        *outError = NULL;
    return NULL;
}
CFURLRef LSCopyDefaultApplicationURLForContentType(CFStringRef inContentType, uint32_t inRoleMask, CFErrorRef *outError)
{
    if (outError)
        *outError = NULL;
    return NULL;
}

/* Pre-10.15 LaunchServices application lookups used by Gecko / XUL.
 * In ravynOS, default handlers are not in a system database, so report the
 * honest result: kLSApplicationNotFoundErr (-10814). */
OSStatus LSGetApplicationForInfo(OSType inType, OSType inCreator, CFStringRef inExtension, uint32_t inRoleMask, void *outAppRef, CFURLRef *outAppURL)
{
    if (outAppURL)
        *outAppURL = NULL;
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSGetApplicationForItem(void *inItemRef, uint32_t inRoleMask, void *outAppRef, CFURLRef *outAppURL)
{
    if (outAppURL)
        *outAppURL = NULL;
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSCopyItemAttribute(CFURLRef inItemURL, uint32_t whichInfo, CFStringRef inAttributeName, CFTypeRef *outValue)
{
    if (outValue)
        *outValue = NULL;
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSCopyItemInfoForURL(CFURLRef inURL, uint32_t inWhichInfo, void *outItemInfo)
{
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSOpenCFURLRef(CFURLRef inURL, CFURLRef *outLaunchedURL)
{
    if (outLaunchedURL)
        *outLaunchedURL = NULL;
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSOpenFSRef(const void *inRef, void *outLaunchedRef)
{
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSOpenFromRefSpec(const void *inLaunchSpec, void *outLaunchedRef)
{
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSOpenFromURLSpec(const void *inLaunchSpec, CFURLRef *outLaunchedURL)
{
    if (outLaunchedURL)
        *outLaunchedURL = NULL;
    return -10814; /* kLSApplicationNotFoundErr */
}

OSStatus LSSetDefaultHandlerForURLScheme(CFStringRef inURLScheme, CFStringRef inHandlerBundleID)
{
    return 0; /* noErr */
}

OSStatus LSSetDefaultRoleHandlerForContentType(CFStringRef inContentType, uint32_t inRole, CFStringRef inHandlerBundleID)
{
    return 0; /* noErr */
}
