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

CFURLRef LSCopyDefaultApplicationURLForContentType(CFStringRef inContentType, uint32_t inRoleMask, CFErrorRef *outError)
{
    if (outError)
        *outError = NULL;
    return NULL;
}
