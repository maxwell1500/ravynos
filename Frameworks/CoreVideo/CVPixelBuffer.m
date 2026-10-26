/*
 * CoreVideo pixel buffer and buffer-attachment API for ravynOS.
 *
 * CVPixelBuffer is the type third-party applications use for video frames and
 * for the buffers they hand to CoreImage/OpenGL/Metal.  Nothing here is
 * accelerated: the buffer is malloc'd rows, which is exactly what the software
 * renderer and every CPU-side consumer wants.
 *
 * Implemented as real CF objects so CFRetain/CFRelease, CFEqual and
 * CVPixelBufferGetTypeID all behave the way a caller expects.
 */

#include "Headers/CoreVideo.h"
#include "CFRuntime.h"
#include <stdlib.h>
#include <string.h>

struct __CVPixelBuffer {
    CFRuntimeBase base;
    void *baseAddress;
    size_t width;
    size_t height;
    size_t bytesPerRow;
    OSType pixelFormat;
    size_t dataSize;
    bool usesExternalStorage;
    void (*releaseCallback)(void *releaseRefCon, const void *baseAddress);
    void *releaseRefCon;
    CFMutableDictionaryRef attachments;
};

struct __CVPixelBufferPool {
    CFRuntimeBase base;
    CFDictionaryRef attributes;
    size_t width;
    size_t height;
    OSType pixelFormat;
};

/* ------------------------------------------------------------------ */
/* Attachments keys                                                    */
/* ------------------------------------------------------------------ */

CFStringRef kCVBufferMovieTimeKey = NULL;
CFStringRef kCVBufferTimeValueKey = NULL;
CFStringRef kCVBufferTimeScaleKey = NULL;
CFStringRef kCVBufferPropagatedAttachmentsKey = NULL;
CFStringRef kCVBufferNonPropagatedAttachmentsKey = NULL;
CFStringRef kCVImageBufferCGColorSpaceKey = NULL;
CFStringRef kCVImageBufferGammaLevelKey = NULL;
CFStringRef kCVImageBufferYCbCrMatrixKey = NULL;
CFStringRef kCVImageBufferColorPrimariesKey = NULL;
CFStringRef kCVImageBufferTransferFunctionKey = NULL;
CFStringRef kCVImageBufferCleanApertureKey = NULL;
CFStringRef kCVImageBufferPixelAspectRatioKey = NULL;
CFStringRef kCVPixelBufferPixelFormatTypeKey = NULL;
CFStringRef kCVPixelBufferWidthKey = NULL;
CFStringRef kCVPixelBufferHeightKey = NULL;
CFStringRef kCVPixelBufferBytesPerRowAlignmentKey = NULL;
CFStringRef kCVPixelBufferCGBitmapContextCompatibilityKey = NULL;
CFStringRef kCVPixelBufferCGImageCompatibilityKey = NULL;
CFStringRef kCVPixelBufferOpenGLCompatibilityKey = NULL;
CFStringRef kCVPixelBufferIOSurfacePropertiesKey = NULL;
CFStringRef kCVPixelBufferPoolMinimumBufferCountKey = NULL;
CFStringRef kCVPixelBufferPoolMaximumBufferAgeKey = NULL;

static void CVCreateAttachmentKeys(void) {
    struct { CFStringRef *slot; const char *text; } table[] = {
        { &kCVBufferMovieTimeKey, "CVBufferMovieTime" },
        { &kCVBufferTimeValueKey, "CVBufferTimeValue" },
        { &kCVBufferTimeScaleKey, "CVBufferTimeScale" },
        { &kCVBufferPropagatedAttachmentsKey, "CVBufferPropagatedAttachments" },
        { &kCVBufferNonPropagatedAttachmentsKey, "CVBufferNonPropagatedAttachments" },
        { &kCVImageBufferCGColorSpaceKey, "CVImageBufferCGColorSpace" },
        { &kCVImageBufferGammaLevelKey, "CVImageBufferGammaLevel" },
        { &kCVImageBufferYCbCrMatrixKey, "CVImageBufferYCbCrMatrix" },
        { &kCVImageBufferColorPrimariesKey, "CVImageBufferColorPrimaries" },
        { &kCVImageBufferTransferFunctionKey, "CVImageBufferTransferFunction" },
        { &kCVImageBufferCleanApertureKey, "CVImageBufferCleanAperture" },
        { &kCVImageBufferPixelAspectRatioKey, "CVImageBufferPixelAspectRatio" },
        { &kCVPixelBufferPixelFormatTypeKey, "PixelFormatType" },
        { &kCVPixelBufferWidthKey, "Width" },
        { &kCVPixelBufferHeightKey, "Height" },
        { &kCVPixelBufferBytesPerRowAlignmentKey, "BytesPerRowAlignment" },
        { &kCVPixelBufferCGBitmapContextCompatibilityKey, "CGBitmapContextCompatibility" },
        { &kCVPixelBufferCGImageCompatibilityKey, "CGImageCompatibility" },
        { &kCVPixelBufferOpenGLCompatibilityKey, "OpenGLCompatibility" },
        { &kCVPixelBufferIOSurfacePropertiesKey, "IOSurfaceProperties" },
        { &kCVPixelBufferPoolMinimumBufferCountKey, "MinimumBufferCount" },
        { &kCVPixelBufferPoolMaximumBufferAgeKey, "MaximumBufferAge" },
    };
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        if (*table[i].slot == NULL) {
            *table[i].slot = CFStringCreateWithCString(kCFAllocatorDefault, table[i].text,
                                                       kCFStringEncodingUTF8);
        }
    }
}

__attribute__((constructor)) static void CVCoreVideoInit(void) {
    CVCreateAttachmentKeys();
}

/* ------------------------------------------------------------------ */
/* CVPixelBuffer                                                       */
/* ------------------------------------------------------------------ */

static void CVPixelBufferFinalize(CFTypeRef cf) {
    struct __CVPixelBuffer *buffer = (struct __CVPixelBuffer *)cf;
    if (buffer->baseAddress) {
        if (buffer->usesExternalStorage) {
            if (buffer->releaseCallback) {
                buffer->releaseCallback(buffer->releaseRefCon, buffer->baseAddress);
            }
        } else {
            free(buffer->baseAddress);
        }
    }
    if (buffer->attachments) CFRelease(buffer->attachments);
}

static CFStringRef CVPixelBufferCopyDesc(CFTypeRef cf) {
    struct __CVPixelBuffer *buffer = (struct __CVPixelBuffer *)cf;
    char text[160];
    snprintf(text, sizeof(text), "CVPixelBuffer %zux%zu '%.4s'",
             buffer->width, buffer->height, (const char *)&buffer->pixelFormat);
    return CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
}

static CFRuntimeClass CVPixelBufferClass = {
    .version = 0,
    .className = "CVPixelBuffer",
    .finalize = CVPixelBufferFinalize,
    .copyDebugDesc = CVPixelBufferCopyDesc,
};

static CFTypeID CVPixelBufferTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        typeID = _CFRuntimeRegisterClass(&CVPixelBufferClass);
    }
    return typeID;
}

CFTypeID CVPixelBufferGetTypeID(void) {
    return CVPixelBufferTypeID();
}

CVReturn CVPixelBufferCreate(CFAllocatorRef allocator, size_t width, size_t height,
                             OSType pixelFormatType, CFDictionaryRef pixelBufferAttributes,
                             CVPixelBufferRef *pixelBufferOut) {
    (void)pixelBufferAttributes;
    if (pixelBufferOut == NULL) return kCVReturnInvalidArgument;
    *pixelBufferOut = NULL;
    if (width == 0 || height == 0) return kCVReturnInvalidSize;

    struct __CVPixelBuffer *buffer = (struct __CVPixelBuffer *)_CFRuntimeCreateInstance(
        allocator ? allocator : kCFAllocatorDefault, CVPixelBufferTypeID(),
        sizeof(struct __CVPixelBuffer) - sizeof(CFRuntimeBase), NULL);
    if (buffer == NULL) return kCVReturnAllocationFailed;

    size_t bytesPerPixel = 4;
    switch (pixelFormatType) {
        case kCVPixelFormatType_32BGRA:
        case kCVPixelFormatType_32ARGB:
        case kCVPixelFormatType_32ABGR:
        case kCVPixelFormatType_32RGBA:
            bytesPerPixel = 4;
            break;
        case kCVPixelFormatType_24RGB:
        case kCVPixelFormatType_24BGR:
            bytesPerPixel = 3;
            break;
        case kCVPixelFormatType_16BE555:
        case kCVPixelFormatType_16LE555:
        case kCVPixelFormatType_16BE565:
        case kCVPixelFormatType_16LE565:
            bytesPerPixel = 2;
            break;
        case kCVPixelFormatType_8Indexed:
            bytesPerPixel = 1;
            break;
        default:
            bytesPerPixel = 4;
            break;
    }
    size_t rowBytes = width * bytesPerPixel;
    /* 16-byte row alignment: what CoreGraphics, CoreImage and the software
     * raster paths in this tree assume when they wrap a buffer. */
    rowBytes = (rowBytes + 15) & ~(size_t)15;

    void *storage = calloc(1, rowBytes * height);
    if (storage == NULL) {
        CFRelease((CFTypeRef)buffer);
        return kCVReturnAllocationFailed;
    }
    buffer->baseAddress = storage;
    buffer->width = width;
    buffer->height = height;
    buffer->bytesPerRow = rowBytes;
    buffer->pixelFormat = pixelFormatType;
    buffer->dataSize = rowBytes * height;
    buffer->usesExternalStorage = false;
    buffer->releaseCallback = NULL;
    buffer->releaseRefCon = NULL;
    buffer->attachments = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                   &kCFTypeDictionaryKeyCallBacks,
                                                   &kCFTypeDictionaryValueCallBacks);
    *pixelBufferOut = (CVPixelBufferRef)buffer;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferCreateWithBytes(CFAllocatorRef allocator, size_t width, size_t height,
                                      OSType pixelFormatType, void *baseAddress,
                                      size_t bytesPerRow, CVPixelBufferReleaseBytesCallback releaseCallback,
                                      void *releaseRefCon, CFDictionaryRef pixelBufferAttributes,
                                      CVPixelBufferRef *pixelBufferOut) {
    (void)pixelBufferAttributes;
    if (pixelBufferOut == NULL || baseAddress == NULL) return kCVReturnInvalidArgument;
    *pixelBufferOut = NULL;
    if (width == 0 || height == 0) return kCVReturnInvalidSize;

    struct __CVPixelBuffer *buffer = (struct __CVPixelBuffer *)_CFRuntimeCreateInstance(
        allocator ? allocator : kCFAllocatorDefault, CVPixelBufferTypeID(),
        sizeof(struct __CVPixelBuffer) - sizeof(CFRuntimeBase), NULL);
    if (buffer == NULL) return kCVReturnAllocationFailed;

    buffer->baseAddress = baseAddress;
    buffer->width = width;
    buffer->height = height;
    buffer->bytesPerRow = bytesPerRow;
    buffer->pixelFormat = pixelFormatType;
    buffer->dataSize = bytesPerRow * height;
    buffer->usesExternalStorage = true;
    buffer->releaseCallback = releaseCallback;
    buffer->releaseRefCon = releaseRefCon;
    buffer->attachments = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                   &kCFTypeDictionaryKeyCallBacks,
                                                   &kCFTypeDictionaryValueCallBacks);
    *pixelBufferOut = (CVPixelBufferRef)buffer;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferCreateWithPlanarBytes(CFAllocatorRef allocator, size_t width, size_t height,
                                            OSType pixelFormatType, void *dataPtr, size_t dataSize,
                                            size_t numberOfPlanes, void **planeBaseAddress,
                                            size_t *planeWidth, size_t *planeHeight,
                                            size_t *planeBytesPerRow,
                                            CVPixelBufferReleasePlanarBytesCallback releaseCallback,
                                            void *releaseRefCon, CFDictionaryRef pixelBufferAttributes,
                                            CVPixelBufferRef *pixelBufferOut) {
    /* Planar formats need a plane-aware buffer type; the single-plane path
     * covers every format the software renderer produces. */
    (void)allocator; (void)width; (void)height; (void)pixelFormatType;
    (void)dataPtr; (void)dataSize; (void)numberOfPlanes; (void)planeBaseAddress;
    (void)planeWidth; (void)planeHeight; (void)planeBytesPerRow;
    (void)releaseCallback; (void)releaseRefCon; (void)pixelBufferAttributes;
    if (pixelBufferOut) *pixelBufferOut = NULL;
    return kCVReturnInvalidArgument;
}

CVReturn CVPixelBufferCreateWithIOSurface(CFAllocatorRef allocator, void *surface,
                                          CFDictionaryRef pixelBufferAttributes,
                                          CVPixelBufferRef *pixelBufferOut) {
    (void)allocator;
    (void)surface;
    (void)pixelBufferAttributes;
    if (pixelBufferOut) *pixelBufferOut = NULL;
    return kCVReturnInvalidArgument;
}

void *CVPixelBufferGetIOSurface(CVPixelBufferRef pixelBuffer) {
    (void)pixelBuffer;
    return NULL;
}

CVReturn CVPixelBufferCreateResolvedAttributesDictionary(CFAllocatorRef allocator,
                                                         CFArrayRef attributes,
                                                         CFDictionaryRef *resolvedDictionaryOut) {
    if (resolvedDictionaryOut == NULL) return kCVReturnInvalidArgument;
    if (attributes != NULL && CFArrayGetCount(attributes) > 0) {
        CFDictionaryRef first = (CFDictionaryRef)CFArrayGetValueAtIndex(attributes, 0);
        if (first && CFGetTypeID(first) == CFDictionaryGetTypeID()) {
            *resolvedDictionaryOut = CFDictionaryCreateCopy(allocator ? allocator : kCFAllocatorDefault, first);
            return kCVReturnSuccess;
        }
    }
    *resolvedDictionaryOut = CFDictionaryCreate(allocator ? allocator : kCFAllocatorDefault,
                                                NULL, NULL, 0,
                                                &kCFTypeDictionaryKeyCallBacks,
                                                &kCFTypeDictionaryValueCallBacks);
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferLockBaseAddress(CVPixelBufferRef pixelBuffer, CVPixelBufferLockFlags lockFlags) {
    (void)lockFlags;
    return pixelBuffer ? kCVReturnSuccess : kCVReturnInvalidArgument;
}

CVReturn CVPixelBufferUnlockBaseAddress(CVPixelBufferRef pixelBuffer, CVPixelBufferLockFlags unlockFlags) {
    (void)unlockFlags;
    return pixelBuffer ? kCVReturnSuccess : kCVReturnInvalidArgument;
}

void *CVPixelBufferGetBaseAddress(CVPixelBufferRef pixelBuffer) {
    return pixelBuffer ? pixelBuffer->baseAddress : NULL;
}

void *CVPixelBufferGetBaseAddressOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex) {
    if (pixelBuffer == NULL || planeIndex != 0) return NULL;
    return pixelBuffer->baseAddress;
}

size_t CVPixelBufferGetWidth(CVPixelBufferRef pixelBuffer) {
    return pixelBuffer ? pixelBuffer->width : 0;
}

size_t CVPixelBufferGetHeight(CVPixelBufferRef pixelBuffer) {
    return pixelBuffer ? pixelBuffer->height : 0;
}

size_t CVPixelBufferGetWidthOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex) {
    return (planeIndex == 0) ? CVPixelBufferGetWidth(pixelBuffer) : 0;
}

size_t CVPixelBufferGetHeightOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex) {
    return (planeIndex == 0) ? CVPixelBufferGetHeight(pixelBuffer) : 0;
}

size_t CVPixelBufferGetBytesPerRow(CVPixelBufferRef pixelBuffer) {
    return pixelBuffer ? pixelBuffer->bytesPerRow : 0;
}

size_t CVPixelBufferGetBytesPerRowOfPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex) {
    return (planeIndex == 0) ? CVPixelBufferGetBytesPerRow(pixelBuffer) : 0;
}

size_t CVPixelBufferGetDataSize(CVPixelBufferRef pixelBuffer) {
    return pixelBuffer ? pixelBuffer->dataSize : 0;
}

OSType CVPixelBufferGetPixelFormatType(CVPixelBufferRef pixelBuffer) {
    return pixelBuffer ? pixelBuffer->pixelFormat : 0;
}

size_t CVPixelBufferGetPlaneCount(CVPixelBufferRef pixelBuffer) {
    return pixelBuffer ? 1 : 0;
}

Boolean CVPixelBufferIsPlanar(CVPixelBufferRef pixelBuffer) {
    (void)pixelBuffer;
    return false;
}

CFDictionaryRef CVPixelBufferGetAttributes(CVPixelBufferRef pixelBuffer) {
    if (pixelBuffer == NULL) return NULL;
    return pixelBuffer->attachments;
}

/* ------------------------------------------------------------------ */
/* Attachments                                                         */
/* ------------------------------------------------------------------ */

CVReturn CVBufferSetAttachment(CVBufferRef buffer, CFStringRef key, CFTypeRef value,
                               CVAttachmentMode attachmentMode) {
    (void)attachmentMode;
    if (buffer == NULL || key == NULL) return kCVReturnInvalidArgument;
    if (buffer->attachments == NULL) {
        buffer->attachments = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                       &kCFTypeDictionaryKeyCallBacks,
                                                       &kCFTypeDictionaryValueCallBacks);
    }
    if (value) {
        CFDictionarySetValue(buffer->attachments, key, value);
    } else {
        CFDictionaryRemoveValue(buffer->attachments, key);
    }
    return kCVReturnSuccess;
}

CFTypeRef CVBufferCopyAttachment(CVBufferRef buffer, CFStringRef key, CVAttachmentMode *attachmentMode) {
    if (attachmentMode) *attachmentMode = kCVAttachmentMode_ShouldPropagate;
    if (buffer == NULL || key == NULL || buffer->attachments == NULL) return NULL;
    CFTypeRef value = CFDictionaryGetValue(buffer->attachments, key);
    if (value) CFRetain(value);
    return value;
}

CFTypeRef CVBufferGetAttachment(CVBufferRef buffer, CFStringRef key, CVAttachmentMode *attachmentMode) {
    if (attachmentMode) *attachmentMode = kCVAttachmentMode_ShouldPropagate;
    if (buffer == NULL || key == NULL || buffer->attachments == NULL) return NULL;
    return CFDictionaryGetValue(buffer->attachments, key);
}

void CVBufferRemoveAttachment(CVBufferRef buffer, CFStringRef key) {
    if (buffer == NULL || key == NULL || buffer->attachments == NULL) return;
    CFDictionaryRemoveValue(buffer->attachments, key);
}

void CVBufferRemoveAllAttachments(CVBufferRef buffer) {
    if (buffer == NULL || buffer->attachments == NULL) return;
    CFDictionaryRemoveAllValues(buffer->attachments);
}

CFDictionaryRef CVBufferGetAttachments(CVBufferRef buffer, CVAttachmentMode attachmentMode) {
    (void)attachmentMode;
    if (buffer == NULL || buffer->attachments == NULL) return NULL;
    return buffer->attachments;
}

void CVBufferPropagateAttachments(CVBufferRef sourceBuffer, CVBufferRef destinationBuffer) {
    if (sourceBuffer == NULL || destinationBuffer == NULL) return;
    if (sourceBuffer->attachments == NULL) return;
    if (destinationBuffer->attachments == NULL) {
        destinationBuffer->attachments = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                                  &kCFTypeDictionaryKeyCallBacks,
                                                                  &kCFTypeDictionaryValueCallBacks);
    }
    CFDictionaryApplyFunction(sourceBuffer->attachments, NULL, NULL);
    CFIndex count = CFDictionaryGetCount(sourceBuffer->attachments);
    const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
    const void **values = (const void **)calloc((size_t)count, sizeof(void *));
    if (keys && values) {
        CFDictionaryGetKeysAndValues(sourceBuffer->attachments, keys, values);
        for (CFIndex i = 0; i < count; i++) {
            CFDictionarySetValue(destinationBuffer->attachments, keys[i], values[i]);
        }
    }
    free(keys);
    free(values);
}

CVBufferRef CVBufferRetain(CVBufferRef buffer) {
    if (buffer) CFRetain(buffer);
    return buffer;
}

void CVBufferRelease(CVBufferRef buffer) {
    if (buffer) CFRelease(buffer);
}

void CVBufferSetAttachments(CVBufferRef buffer, CFDictionaryRef theAttachments, CVAttachmentMode attachmentMode) {
    (void)attachmentMode;
    if (buffer == NULL || theAttachments == NULL) return;
    if (buffer->attachments == NULL) {
        buffer->attachments = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                       &kCFTypeDictionaryKeyCallBacks,
                                                       &kCFTypeDictionaryValueCallBacks);
    }
    CFIndex count = CFDictionaryGetCount(theAttachments);
    const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
    const void **values = (const void **)calloc((size_t)count, sizeof(void *));
    if (keys && values) {
        CFDictionaryGetKeysAndValues(theAttachments, keys, values);
        for (CFIndex i = 0; i < count; i++) {
            CFDictionarySetValue(buffer->attachments, keys[i], values[i]);
        }
    }
    free(keys);
    free(values);
}

/* ------------------------------------------------------------------ */
/* CVPixelBufferPool                                                   */
/* ------------------------------------------------------------------ */

static void CVPixelBufferPoolFinalize(CFTypeRef cf) {
    struct __CVPixelBufferPool *pool = (struct __CVPixelBufferPool *)cf;
    if (pool->attributes) CFRelease(pool->attributes);
}

static CFStringRef CVPixelBufferPoolCopyDesc(CFTypeRef cf) {
    (void)cf;
    return CFStringCreateWithCString(kCFAllocatorDefault, "CVPixelBufferPool", kCFStringEncodingUTF8);
}

static CFRuntimeClass CVPixelBufferPoolClass = {
    .version = 0,
    .className = "CVPixelBufferPool",
    .finalize = CVPixelBufferPoolFinalize,
    .copyDebugDesc = CVPixelBufferPoolCopyDesc,
};

static CFTypeID CVPixelBufferPoolTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        typeID = _CFRuntimeRegisterClass(&CVPixelBufferPoolClass);
    }
    return typeID;
}

CFTypeID CVPixelBufferPoolGetTypeID(void) {
    return CVPixelBufferPoolTypeID();
}

CVReturn CVPixelBufferPoolCreate(CFAllocatorRef allocator, CFDictionaryRef poolAttributes,
                                 CFDictionaryRef pixelBufferAttributes,
                                 CVPixelBufferPoolRef *poolOut) {
    if (poolOut == NULL || pixelBufferAttributes == NULL) return kCVReturnInvalidArgument;
    *poolOut = NULL;

    size_t width = 0, height = 0;
    OSType format = kCVPixelFormatType_32BGRA;
    CFNumberRef number = (CFNumberRef)CFDictionaryGetValue(pixelBufferAttributes, kCVPixelBufferWidthKey);
    if (number) CFNumberGetValue(number, kCFNumberSInt64Type, &width);
    number = (CFNumberRef)CFDictionaryGetValue(pixelBufferAttributes, kCVPixelBufferHeightKey);
    if (number) CFNumberGetValue(number, kCFNumberSInt64Type, &height);
    number = (CFNumberRef)CFDictionaryGetValue(pixelBufferAttributes, kCVPixelBufferPixelFormatTypeKey);
    if (number) {
        uint32_t value = 0;
        if (CFNumberGetValue(number, kCFNumberSInt32Type, &value)) {
            format = (OSType)value;
        }
    }
    if (width == 0 || height == 0) return kCVReturnInvalidSize;

    struct __CVPixelBufferPool *pool = (struct __CVPixelBufferPool *)_CFRuntimeCreateInstance(
        allocator ? allocator : kCFAllocatorDefault, CVPixelBufferPoolTypeID(),
        sizeof(struct __CVPixelBufferPool) - sizeof(CFRuntimeBase), NULL);
    if (pool == NULL) return kCVReturnPoolAllocationFailed;
    pool->attributes = CFDictionaryCreateCopy(kCFAllocatorDefault, pixelBufferAttributes);
    (void)poolAttributes;
    pool->width = width;
    pool->height = height;
    pool->pixelFormat = format;
    *poolOut = (CVPixelBufferPoolRef)pool;
    return kCVReturnSuccess;
}

CVReturn CVPixelBufferPoolCreatePixelBuffer(CFAllocatorRef allocator, CVPixelBufferPoolRef pixelBufferPool,
                                            CVPixelBufferRef *pixelBufferOut) {
    if (pixelBufferPool == NULL || pixelBufferOut == NULL) return kCVReturnInvalidArgument;
    return CVPixelBufferCreate(allocator, pixelBufferPool->width, pixelBufferPool->height,
                               pixelBufferPool->pixelFormat, pixelBufferPool->attributes,
                               pixelBufferOut);
}

CVReturn CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(CFAllocatorRef allocator,
                                                            CVPixelBufferPoolRef pixelBufferPool,
                                                            CFDictionaryRef auxAttributes,
                                                            CVPixelBufferRef *pixelBufferOut) {
    (void)auxAttributes;
    return CVPixelBufferPoolCreatePixelBuffer(allocator, pixelBufferPool, pixelBufferOut);
}

CFDictionaryRef CVPixelBufferPoolGetPixelBufferAttributes(CVPixelBufferPoolRef pool) {
    return pool ? pool->attributes : NULL;
}

CFDictionaryRef CVPixelBufferPoolGetAttributes(CVPixelBufferPoolRef pool) {
    return pool ? pool->attributes : NULL;
}

void CVPixelBufferPoolFlush(CVPixelBufferPoolRef pool, CVPixelBufferPoolFlushFlags options) {
    (void)pool;
    (void)options;
}
