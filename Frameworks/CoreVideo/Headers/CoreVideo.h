/*
 * CoreVideo.framework public header for ravynOS.
 *
 * Covers CVBuffer/CVPixelBuffer and CVDisplayLink: the two CoreVideo types a
 * bundled application reaches for at launch.  Planar buffers, IOSurface-backed
 * buffers, Metal texture caches and the CoreVideo OpenGL glue are not present
 * and are not declared, so a caller that needs them fails to compile instead
 * of failing at run time.
 */

#ifndef _RAVYNOS_COREVIDEO_H_
#define _RAVYNOS_COREVIDEO_H_

#include <CoreFoundation/CoreFoundation.h>
/* CGDirectDisplay.h's CGDisplayRegisterReconfigurationCallback takes a
 * CFMachPortRef and, in this tree, does not include CFMachPort.h itself. */
#include <CoreFoundation/CFMachPort.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Base types                                                          */
/* ------------------------------------------------------------------ */

typedef int32_t CVReturn;
typedef uint64_t CVOptionFlags;

enum {
    kCVReturnSuccess = 0,
    kCVReturnFirst = -6660,
    kCVReturnError = -6660,
    kCVReturnInvalidArgument = -6661,
    kCVReturnAllocationFailed = -6662,
    kCVReturnInvalidDisplay = -6670,
    kCVReturnDisplayLinkAlreadyRunning = -6671,
    kCVReturnDisplayLinkNotRunning = -6672,
    kCVReturnDisplayLinkCallbacksNotSet = -6673,
    kCVReturnInvalidPixelFormat = -6680,
    kCVReturnInvalidSize = -6681,
    kCVReturnInvalidPixelBufferAttributes = -6682,
    kCVReturnPixelBufferNotOpenGLCompatible = -6683,
    kCVReturnPoolAllocationFailed = -6690,
    kCVReturnInvalidPoolAttributes = -6691,
    kCVReturnLast = -6699
};

typedef uint32_t OSType;

enum {
    kCVPixelFormatType_1Monochrome = 0x00000001,
    kCVPixelFormatType_8Indexed = 0x00000002,
    kCVPixelFormatType_16BE555 = 0x00000010,
    kCVPixelFormatType_16LE555 = 'L555',
    kCVPixelFormatType_16BE565 = 0x00000012,
    kCVPixelFormatType_16LE565 = 'L565',
    kCVPixelFormatType_24RGB = 0x00000018,
    kCVPixelFormatType_24BGR = '24BG',
    kCVPixelFormatType_32ARGB = 0x00000020,
    kCVPixelFormatType_32BGRA = 'BGRA',
    kCVPixelFormatType_32ABGR = 'ABGR',
    kCVPixelFormatType_32RGBA = 'RGBA',
};

typedef struct __CVPixelBuffer *CVPixelBufferRef;
typedef struct __CVPixelBuffer *CVBufferRef;
typedef struct __CVPixelBufferPool *CVPixelBufferPoolRef;

typedef uint64_t CVPixelBufferLockFlags;
enum {
    kCVPixelBufferLock_ReadOnly = 0x00000001,
};

typedef uint32_t CVPixelBufferPoolFlushFlags;
enum {
    kCVPixelBufferPoolFlushExcessBuffers = 1,
};

typedef enum {
    kCVAttachmentMode_ShouldNotPropagate = 0,
    kCVAttachmentMode_ShouldPropagate = 1,
} CVAttachmentMode;

struct CVSMPTETime {
    int16_t subframes;
    int16_t subframeDivisor;
    uint32_t counter;
    uint32_t type;
    uint32_t flags;
    int16_t hours;
    int16_t minutes;
    int16_t seconds;
    int16_t frames;
};
typedef struct CVSMPTETime CVSMPTETime;

typedef struct {
    uint32_t version;
    int32_t videoTimeScale;
    int64_t videoTime;
    uint64_t hostTime;
    double rateScalar;
    int64_t videoRefreshPeriod;
    CVSMPTETime smpteTime;
    uint64_t flags;
    uint64_t reserved;
} CVTimeStamp;

typedef struct {
    int32_t timeValue;
    int32_t timeScale;
    uint32_t flags;
} CVTime;

enum {
    kCVTimeIsIndefinite = 1 << 0,
};

/* ------------------------------------------------------------------ */
/* Attachments                                                         */
/* ------------------------------------------------------------------ */

/* Writable pointers, populated once at load time by a constructor: this
 * CoreFoundation builds CFSTR() strings at run time, so they cannot be
 * compile-time constants.  The ABI matches Apple's const declaration. */
extern CFStringRef kCVBufferMovieTimeKey;
extern CFStringRef kCVBufferTimeValueKey;
extern CFStringRef kCVBufferTimeScaleKey;
extern CFStringRef kCVBufferPropagatedAttachmentsKey;
extern CFStringRef kCVBufferNonPropagatedAttachmentsKey;
extern CFStringRef kCVImageBufferCGColorSpaceKey;
extern CFStringRef kCVImageBufferGammaLevelKey;
extern CFStringRef kCVImageBufferYCbCrMatrixKey;
extern CFStringRef kCVImageBufferColorPrimariesKey;
extern CFStringRef kCVImageBufferTransferFunctionKey;
extern CFStringRef kCVImageBufferCleanApertureKey;
extern CFStringRef kCVImageBufferPixelAspectRatioKey;

extern CFStringRef kCVPixelBufferPixelFormatTypeKey;
extern CFStringRef kCVPixelBufferWidthKey;
extern CFStringRef kCVPixelBufferHeightKey;
extern CFStringRef kCVPixelBufferBytesPerRowAlignmentKey;
extern CFStringRef kCVPixelBufferCGBitmapContextCompatibilityKey;
extern CFStringRef kCVPixelBufferCGImageCompatibilityKey;
extern CFStringRef kCVPixelBufferOpenGLCompatibilityKey;
extern CFStringRef kCVPixelBufferIOSurfacePropertiesKey;
extern CFStringRef kCVPixelBufferPoolMinimumBufferCountKey;
extern CFStringRef kCVPixelBufferPoolMaximumBufferAgeKey;

CVBufferRef CVBufferRetain(CVBufferRef buffer);
void CVBufferRelease(CVBufferRef buffer);
CVReturn CVBufferSetAttachment(CVBufferRef buffer, CFStringRef key, CFTypeRef value,
                               CVAttachmentMode attachmentMode);
CFTypeRef CVBufferGetAttachment(CVBufferRef buffer, CFStringRef key, CVAttachmentMode *attachmentMode);
CFTypeRef CVBufferCopyAttachment(CVBufferRef buffer, CFStringRef key, CVAttachmentMode *attachmentMode);
void CVBufferRemoveAttachment(CVBufferRef buffer, CFStringRef key);
void CVBufferRemoveAllAttachments(CVBufferRef buffer);
CFDictionaryRef CVBufferGetAttachments(CVBufferRef buffer, CVAttachmentMode attachmentMode);
void CVBufferSetAttachments(CVBufferRef buffer, CFDictionaryRef theAttachments,
                            CVAttachmentMode attachmentMode);
void CVBufferPropagateAttachments(CVBufferRef sourceBuffer, CVBufferRef destinationBuffer);

/* ------------------------------------------------------------------ */
/* CVPixelBuffer                                                       */
/* ------------------------------------------------------------------ */

typedef void (*CVPixelBufferReleaseBytesCallback)(void *releaseRefCon, const void *baseAddress);
typedef void (*CVPixelBufferReleasePlanarBytesCallback)(void *releaseRefCon, const void *dataPtr,
                                                        size_t dataSize, size_t numberOfPlanes,
                                                        void *planeAddresses[]);

CFTypeID CVPixelBufferGetTypeID(void);
CVReturn CVPixelBufferCreate(CFAllocatorRef allocator, size_t width, size_t height,
                             OSType pixelFormatType, CFDictionaryRef pixelBufferAttributes,
                             CVPixelBufferRef *pixelBufferOut);
CVReturn CVPixelBufferCreateWithBytes(CFAllocatorRef allocator, size_t width, size_t height,
                                      OSType pixelFormatType, void *baseAddress,
                                      size_t bytesPerRow,
                                      CVPixelBufferReleaseBytesCallback releaseCallback,
                                      void *releaseRefCon,
                                      CFDictionaryRef pixelBufferAttributes,
                                      CVPixelBufferRef *pixelBufferOut);
/* IOSurfaceRef is spelled void* here because CoreGraphics' CGDirectDisplay.h
 * typedefs IOSurfaceRef itself (under __BLOCKS__) and IOSurface.framework
 * typedefs it again; including both makes the two collide.  Both spellings
 * are a single pointer, so the ABI is unchanged. */
CVReturn CVPixelBufferCreateWithIOSurface(CFAllocatorRef allocator, void *surface,
                                          CFDictionaryRef pixelBufferAttributes,
                                          CVPixelBufferRef *pixelBufferOut);
CVReturn CVPixelBufferCreateResolvedAttributesDictionary(CFAllocatorRef allocator,
                                                         CFArrayRef attributes,
                                                         CFDictionaryRef *resolvedDictionaryOut);
void *CVPixelBufferGetIOSurface(CVPixelBufferRef pixelBuffer);

CVReturn CVPixelBufferLockBaseAddress(CVPixelBufferRef pixelBuffer, CVPixelBufferLockFlags lockFlags);
CVReturn CVPixelBufferUnlockBaseAddress(CVPixelBufferRef pixelBuffer, CVPixelBufferLockFlags unlockFlags);
void *CVPixelBufferGetBaseAddress(CVPixelBufferRef pixelBuffer);
void *CVPixelBufferGetBaseAddressOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
size_t CVPixelBufferGetWidth(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetHeight(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetWidthOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
size_t CVPixelBufferGetHeightOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
size_t CVPixelBufferGetBytesPerRow(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetBytesPerRowOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex);
size_t CVPixelBufferGetDataSize(CVPixelBufferRef pixelBuffer);
OSType CVPixelBufferGetPixelFormatType(CVPixelBufferRef pixelBuffer);
size_t CVPixelBufferGetPlaneCount(CVPixelBufferRef pixelBuffer);
Boolean CVPixelBufferIsPlanar(CVPixelBufferRef pixelBuffer);
CFDictionaryRef CVPixelBufferGetAttributes(CVPixelBufferRef pixelBuffer);

/* ------------------------------------------------------------------ */
/* CVPixelBufferPool                                                   */
/* ------------------------------------------------------------------ */

CFTypeID CVPixelBufferPoolGetTypeID(void);
CVReturn CVPixelBufferPoolCreate(CFAllocatorRef allocator, CFDictionaryRef poolAttributes,
                                 CFDictionaryRef pixelBufferAttributes,
                                 CVPixelBufferPoolRef *poolOut);
CVReturn CVPixelBufferPoolCreatePixelBuffer(CFAllocatorRef allocator,
                                            CVPixelBufferPoolRef pixelBufferPool,
                                            CVPixelBufferRef *pixelBufferOut);
CVReturn CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(CFAllocatorRef allocator,
                                                            CVPixelBufferPoolRef pixelBufferPool,
                                                            CFDictionaryRef auxAttributes,
                                                            CVPixelBufferRef *pixelBufferOut);
CFDictionaryRef CVPixelBufferPoolGetPixelBufferAttributes(CVPixelBufferPoolRef pool);
CFDictionaryRef CVPixelBufferPoolGetAttributes(CVPixelBufferPoolRef pool);
void CVPixelBufferPoolFlush(CVPixelBufferPoolRef pool, CVPixelBufferPoolFlushFlags options);

/* ------------------------------------------------------------------ */
/* CVDisplayLink                                                       */
/* ------------------------------------------------------------------ */

/* Objective-C callers see the class; C callers see an opaque struct.  The
 * object is a single pointer either way, so the ABI is identical and both
 * spellings bind to the same symbol. */
#ifdef __OBJC__
@class CVDisplayLink;
typedef CVDisplayLink *CVDisplayLinkRef;
#else
typedef struct CVDisplayLink *CVDisplayLinkRef;
#endif
typedef CVReturn (*CVDisplayLinkOutputCallback)(CVDisplayLinkRef displayLink,
                                                const CVTimeStamp *inNow,
                                                const CVTimeStamp *inOutputTime,
                                                CVOptionFlags flagsIn,
                                                CVOptionFlags *flagsOut,
                                                void *displayLinkContext);

CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID displayID, CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkCreateWithCGDisplays(CGDirectDisplayID *displayArray, CFIndex count,
                                          CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkCreateWithOpenGLDisplayMask(uint32_t displayMask, CVDisplayLinkRef *displayLinkOut);
CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef displayLink,
                                        CVDisplayLinkOutputCallback callback, void *userInfo);
CVReturn CVDisplayLinkSetCurrentCGDisplay(CVDisplayLinkRef displayLink, CGDirectDisplayID displayID);
/* The parameters are CGLContextObj / CGLPixelFormatObj.  They are spelled
 * void* here because the OpenGL framework on ravynOS is a stub and its
 * headers are not part of the sysroot; the ABI is identical (both are
 * pointers) and a caller passing the real types sees no difference. */
CVReturn CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(CVDisplayLinkRef displayLink,
                                                           void *cglContext,
                                                           void *cglPixelFormat);
CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay(CVDisplayLinkRef displayLink);
CVReturn CVDisplayLinkStart(CVDisplayLinkRef displayLink);
CVReturn CVDisplayLinkStop(CVDisplayLinkRef displayLink);
Boolean CVDisplayLinkIsRunning(CVDisplayLinkRef displayLink);
CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef displayLink);
CVTime CVDisplayLinkGetOutputVideoLatency(CVDisplayLinkRef displayLink);
double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef displayLink);
CVReturn CVDisplayLinkGetCurrentTime(CVDisplayLinkRef displayLink, CVTimeStamp *outTime);
CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef displayLink);
void CVDisplayLinkRelease(CVDisplayLinkRef displayLink);

#ifdef __cplusplus
}
#endif

#endif /* _RAVYNOS_COREVIDEO_H_ */
