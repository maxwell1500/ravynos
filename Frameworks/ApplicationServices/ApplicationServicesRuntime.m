/*
 * ApplicationServices.framework runtime for ravynOS.
 *
 * ApplicationServices is the umbrella for CoreGraphics, CoreText, CoreImage,
 * ATS, ColorSync, PrintCore and the Carbon-era process/accessibility calls.
 * CoreGraphics and CoreText are their own frameworks here and are re-exported;
 * this file implements the process and accessibility entry points that
 * third-party applications call while bringing themselves to the front and
 * before using accessibility APIs.
 *
 * Everything answers honestly: a process query describes this process
 * truthfully, and accessibility reports "not trusted" / "not implemented"
 * rather than granting access this system cannot enforce.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/* Carbon process manager (Processes.h)                                */
/* ------------------------------------------------------------------ */

/* ProcessSerialNumber is a MacTypes.h type (two UInt32 fields); reusing it
 * keeps the struct layout identical to what a caller was compiled against. */
static ProcessSerialNumber g_self_psn = { 0, 1 };

OSStatus GetCurrentProcess(ProcessSerialNumber *psn) {
    if (psn == NULL) return -50;   /* paramErr */
    *psn = g_self_psn;
    return 0;
}

OSStatus SameProcess(const ProcessSerialNumber *psn1, const ProcessSerialNumber *psn2, Boolean *result) {
    if (psn1 == NULL || psn2 == NULL || result == NULL) return -50;
    *result = (memcmp(psn1, psn2, sizeof(ProcessSerialNumber)) == 0) ? true : false;
    return 0;
}

typedef struct {
    ProcessSerialNumber processInfo;
    UInt32 processSignature;
    UInt32 processType;
    UInt32 processMode;
    UInt32 processLocation;
    char processName[32];
} ProcessInfoRec;

OSStatus GetProcessInformation(const ProcessSerialNumber *psn, ProcessInfoRec *info) {
    if (info == NULL) return -50;
    /* Only this process can be described: there is no process database. */
    if (psn != NULL && memcmp(psn, &g_self_psn, sizeof(ProcessSerialNumber)) != 0) {
        return -600;   /* procNotFound */
    }
    memset(info, 0, sizeof(*info));
    info->processInfo = g_self_psn;
    info->processType = 0x464F5247;   /* 'FORG' */
    info->processSignature = 0;
    const char *name = getprogname();
    if (name) {
        strncpy(info->processName, name, sizeof(info->processName) - 1);
    }
    return 0;
}

enum {
    kProcessTransformToForegroundApplication = 1,
    kProcessTransformToBackgroundApplication = 2,
    kProcessTransformToUIElementApplication = 4,
};

OSStatus TransformProcessType(const ProcessSerialNumber *psn, UInt32 transformState) {
    (void)psn;
    (void)transformState;
    /* WindowServer decides what is frontmost from the window a process owns;
     * there is no separate transform to perform and nothing to lie about. */
    return 0;
}

OSStatus SetFrontProcess(const ProcessSerialNumber *psn) {
    (void)psn;
    return 0;
}

OSStatus SetFrontProcessWithOptions(const ProcessSerialNumber *psn, OptionBits inOptions) {
    (void)psn;
    (void)inOptions;
    return 0;
}

OSStatus ProcessSerialNumberToProcessID(const ProcessSerialNumber *psn, void *options, pid_t *pid) {
    if (psn == NULL || pid == NULL) return -50;
    *pid = getpid();
    return 0;
}

/* ------------------------------------------------------------------ */
/* Accessibility                                                       */
/* ------------------------------------------------------------------ */

typedef struct __AXUIElement *AXUIElementRef;
typedef struct __AXObserver *AXObserverRef;
typedef int AXError;
typedef int AXValueType;
typedef struct __AXValue *AXValueRef;
enum {
    kAXErrorSuccess = 0,
    kAXErrorFailure = -25200,
    kAXErrorIllegalArgument = -25201,
    kAXErrorInvalidUIElement = -25202,
    kAXErrorInvalidUIElementObserver = -25203,
    kAXErrorCannotComplete = -25204,
    kAXErrorAttributeUnsupported = -25205,
    kAXErrorActionUnsupported = -25206,
    kAXErrorNotificationUnsupported = -25207,
    kAXErrorNotImplemented = -25208,
    kAXErrorAPIDisabled = -25211,
};

typedef CFTypeRef AXUIElementRefStorage;

Boolean AXIsProcessTrusted(void) {
    /* No accessibility TCC database exists.  Reporting "not trusted" is the
     * conservative answer: a caller then avoids driving other applications'
     * UI, which is precisely what this system cannot police. */
    return false;
}

Boolean AXIsProcessTrustedWithOptions(CFDictionaryRef options) {
    (void)options;
    return false;
}

AXUIElementRef AXUIElementCreateApplication(pid_t pid) {
    (void)pid;
    return NULL;
}

AXUIElementRef AXUIElementCreateSystemWide(void) {
    return NULL;
}

AXError AXUIElementCopyAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef *value) {
    (void)element;
    (void)attribute;
    if (value) *value = NULL;
    return kAXErrorAPIDisabled;
}

AXError AXUIElementCopyAttributeNames(AXUIElementRef element, CFArrayRef *names) {
    (void)element;
    if (names) *names = NULL;
    return kAXErrorAPIDisabled;
}

AXError AXUIElementSetAttributeValue(AXUIElementRef element, CFStringRef attribute, CFTypeRef value) {
    (void)element;
    (void)attribute;
    (void)value;
    return kAXErrorAPIDisabled;
}

AXError AXUIElementPerformAction(AXUIElementRef element, CFStringRef action) {
    (void)element;
    (void)action;
    return kAXErrorAPIDisabled;
}

AXError AXObserverCreate(pid_t application, void *callback, AXObserverRef *observer) {
    (void)application;
    (void)callback;
    if (observer) *observer = NULL;
    return kAXErrorAPIDisabled;
}

AXError AXObserverAddNotification(AXObserverRef observer, AXUIElementRef element,
                                  CFStringRef notification, void *refcon) {
    (void)observer;
    (void)element;
    (void)notification;
    (void)refcon;
    return kAXErrorAPIDisabled;
}

CFRunLoopSourceRef AXObserverGetRunLoopSource(AXObserverRef observer) {
    (void)observer;
    return NULL;
}

AXValueRef AXValueCreate(AXValueType theType, const void *valuePtr) {
    (void)theType;
    (void)valuePtr;
    return NULL;
}

Boolean AXValueGetValue(AXValueRef value, AXValueType theType, void *valuePtr) {
    (void)value;
    (void)theType;
    (void)valuePtr;
    return false;
}

Boolean AXAPIEnabled(void) {
    return false;
}

/* ------------------------------------------------------------------ */
/* PrintCore                                                           */
/* ------------------------------------------------------------------ */

typedef struct __PMPrintSession *PMPrintSession;
typedef struct __PMPrintSettings *PMPrintSettings;
typedef struct __PMPageFormat *PMPageFormat;

OSStatus PMCreateSession(PMPrintSession *printSession) {
    (void)printSession;
    /* No print system exists; a NULL session is the documented failure and
     * callers fall back to "no printers". */
    return -50;
}

OSStatus PMCreatePageFormat(PMPageFormat *pageFormat) {
    (void)pageFormat;
    return -50;
}

OSStatus PMCreatePrintSettings(PMPrintSettings *printSettings) {
    (void)printSettings;
    return -50;
}

OSStatus PMRelease(void *object) {
    (void)object;
    return 0;
}

/* ------------------------------------------------------------------ */
/* HIShape                                                             */
/* ------------------------------------------------------------------ */

typedef struct __HIShape *HIShapeRef;

HIShapeRef HIShapeCreateWithRect(const CGRect *inRect) {
    (void)inRect;
    return NULL;
}

HIShapeRef HIShapeCreateEmpty(void) {
    return NULL;
}

Boolean HIShapeIsEmpty(HIShapeRef inShape) {
    (void)inShape;
    return true;
}

/* ------------------------------------------------------------------ */
/* Accessibility text markers (HIServices)                             */
/* ------------------------------------------------------------------ */

typedef struct __AXTextMarker *AXTextMarkerRef;
typedef struct __AXTextMarkerRange *AXTextMarkerRangeRef;

AXTextMarkerRef AXTextMarkerCreate(CFAllocatorRef allocator,
    const UInt8 *bytes, CFIndex length) {
    (void)allocator; (void)bytes; (void)length;
    return NULL;    /* no accessibility server to own a marker */
}

CFIndex AXTextMarkerGetLength(AXTextMarkerRef marker) {
    (void)marker;
    return 0;
}

const UInt8 *AXTextMarkerGetBytePtr(AXTextMarkerRef marker) {
    (void)marker;
    return NULL;
}

CFTypeID AXTextMarkerRangeGetTypeID(void) {
    return 0;
}

AXTextMarkerRangeRef AXTextMarkerRangeCreate(CFAllocatorRef allocator,
    AXTextMarkerRef startMarker, AXTextMarkerRef endMarker) {
    (void)allocator; (void)startMarker; (void)endMarker;
    return NULL;
}

AXTextMarkerRef AXTextMarkerRangeCopyStartMarker(AXTextMarkerRangeRef range) {
    (void)range;
    return NULL;
}

AXTextMarkerRef AXTextMarkerRangeCopyEndMarker(AXTextMarkerRangeRef range) {
    (void)range;
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Printing sessions beyond creation                                   */
/* ------------------------------------------------------------------ */

OSStatus PMRetain(void *object) {
    (void)object;
    return 0;
}

OSStatus PMSessionError(void *session) {
    (void)session;
    return -50;
}

OSStatus PMSessionBeginCGDocumentNoDialog(void *session, void *settings,
    void *pageFormat) {
    (void)session; (void)settings; (void)pageFormat;
    return -50;     /* no session was ever created */
}

OSStatus PMSessionEndDocumentNoDialog(void *session) {
    (void)session;
    return -50;
}

OSStatus PMSessionBeginPageNoDialog(void *session, void *pageFormat,
    const void *pageFrame) {
    (void)session; (void)pageFormat; (void)pageFrame;
    return -50;
}

OSStatus PMSessionEndPageNoDialog(void *session) {
    (void)session;
    return -50;
}

OSStatus PMSessionGetCGGraphicsContext(void *session, CGContextRef *context) {
    (void)session;
    if (context != NULL)
        *context = NULL;
    return -50;
}

OSStatus PMSessionGetDestinationType(void *session, void *settings,
    int *destinationType) {
    (void)session; (void)settings;
    if (destinationType != NULL)
        *destinationType = 0;
    return -50;
}

OSStatus PMSetFirstPage(void *settings, UInt32 first, Boolean lock) {
    (void)settings; (void)first; (void)lock;
    return -50;
}

OSStatus PMSetLastPage(void *settings, UInt32 last, Boolean lock) {
    (void)settings; (void)last; (void)lock;
    return -50;
}

OSStatus PMPrintSettingsSetJobName(void *settings, CFStringRef name) {
    (void)settings; (void)name;
    return -50;
}

OSStatus PMGetAdjustedPaperRect(void *pageFormat, CGRect *paperRect) {
    (void)pageFormat;
    if (paperRect != NULL)
        *paperRect = CGRectZero;
    return -50;
}

/* ------------------------------------------------------------------ */
/* Pasteboard and Universal Access                                     */
/* ------------------------------------------------------------------ */

typedef struct __Pasteboard *PasteboardRef;
typedef uint32_t PasteboardSyncFlags;

OSStatus PasteboardCreate(CFStringRef name, PasteboardRef *pasteboard) {
    (void)name;
    if (pasteboard != NULL)
        *pasteboard = NULL;
    return -50;     /* no pasteboard server */
}

PasteboardSyncFlags PasteboardSynchronize(PasteboardRef pasteboard) {
    (void)pasteboard;
    return 0;
}

OSStatus PasteboardCopyPasteLocation(PasteboardRef pasteboard,
    CFURLRef *location) {
    (void)pasteboard;
    if (location != NULL)
        *location = NULL;
    return -50;
}

Boolean UAZoomEnabled(void) {
    return false;   /* zoom is a WindowServer feature that does not exist */
}
