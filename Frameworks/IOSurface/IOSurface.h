/*
 * IOSurface.h - IOSurface framework for ravynOS
 *
 * Copyright (c) 2026 ravynOS Project
 */

#ifndef _IOSURFACE_H_
#define _IOSURFACE_H_

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct __IOSurface* IOSurfaceRef;
typedef uint32_t IOSurfaceID;

extern const CFStringRef kIOSurfaceAllocSize;
extern const CFStringRef kIOSurfaceWidth;
extern const CFStringRef kIOSurfaceHeight;
extern const CFStringRef kIOSurfaceBytesPerRow;
extern const CFStringRef kIOSurfaceBytesPerElement;
extern const CFStringRef kIOSurfacePixelFormat;
extern const CFStringRef kIOSurfacePlaneBytesPerRow;
extern const CFStringRef kIOSurfacePlaneWidth;
extern const CFStringRef kIOSurfacePlaneHeight;
extern const CFStringRef kIOSurfacePlaneOffset;
extern const CFStringRef kIOSurfacePlaneSize;
extern const CFStringRef kIOSurfacePlaneInfo;
extern const CFStringRef kIOSurfacePlaneBytesPerElement;
extern const CFStringRef kCVPixelBufferIOSurfacePropertiesKey;

IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
IOSurfaceID IOSurfaceGetID(IOSurfaceRef buffer);
size_t IOSurfaceGetWidth(IOSurfaceRef buffer);
size_t IOSurfaceGetHeight(IOSurfaceRef buffer);
size_t IOSurfaceGetBytesPerRow(IOSurfaceRef buffer);
size_t IOSurfaceGetBytesPerElement(IOSurfaceRef buffer);
size_t IOSurfaceGetAllocSize(IOSurfaceRef buffer);
uint32_t IOSurfaceGetPixelFormat(IOSurfaceRef buffer);
void *IOSurfaceGetBaseAddress(IOSurfaceRef buffer);
void *IOSurfaceGetBaseAddressOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetWidthOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetHeightOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetBytesPerRowOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetBytesPerElementOfPlane(IOSurfaceRef buffer, size_t planeIndex);
size_t IOSurfaceGetPlaneCount(IOSurfaceRef buffer);

kern_return_t IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);

void IOSurfaceIncrementUseCount(IOSurfaceRef buffer);
void IOSurfaceDecrementUseCount(IOSurfaceRef buffer);
Boolean IOSurfaceIsInUse(IOSurfaceRef buffer);
size_t IOSurfaceAlignProperty(CFStringRef property, size_t value);
mach_port_t IOSurfaceCreateMachPort(IOSurfaceRef buffer);
IOSurfaceRef IOSurfaceLookupFromMachPort(mach_port_t port);
void IOSurfaceSetValue(IOSurfaceRef buffer, CFStringRef key, CFTypeRef value);
void IOSurfaceSetPurgeable(IOSurfaceRef buffer, uint32_t newState, uint32_t *oldState);

void *CVPixelBufferCreateWithIOSurface(CFAllocatorRef allocator, IOSurfaceRef surface, CFDictionaryRef pixelBufferAttributes, void **pixelBufferOut);
IOSurfaceRef CVPixelBufferGetIOSurface(void *pixelBuffer);

#ifdef __cplusplus
}
#endif

#endif /* _IOSURFACE_H_ */
