/*
 * IOSurface.c - IOSurface implementation backed by memory for ravynOS
 *
 * Copyright (c) 2026 ravynOS Project
 */

#include "IOSurface.h"
#include <sys/mman.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

struct __IOSurface {
    uint32_t id;
    size_t width;
    size_t height;
    size_t bytesPerRow;
    size_t bytesPerElement;
    size_t allocSize;
    uint32_t pixelFormat;
    void *address;
    int useCount;
};

const CFStringRef kIOSurfaceAllocSize = CFSTR("IOSurfaceAllocSize");
const CFStringRef kIOSurfaceWidth = CFSTR("IOSurfaceWidth");
const CFStringRef kIOSurfaceHeight = CFSTR("IOSurfaceHeight");
const CFStringRef kIOSurfaceBytesPerRow = CFSTR("IOSurfaceBytesPerRow");
const CFStringRef kIOSurfaceBytesPerElement = CFSTR("IOSurfaceBytesPerElement");
const CFStringRef kIOSurfacePixelFormat = CFSTR("IOSurfacePixelFormat");
const CFStringRef kIOSurfacePlaneBytesPerRow = CFSTR("IOSurfacePlaneBytesPerRow");
const CFStringRef kIOSurfacePlaneWidth = CFSTR("IOSurfacePlaneWidth");
const CFStringRef kIOSurfacePlaneHeight = CFSTR("IOSurfacePlaneHeight");
const CFStringRef kIOSurfacePlaneOffset = CFSTR("IOSurfacePlaneOffset");
const CFStringRef kIOSurfacePlaneSize = CFSTR("IOSurfacePlaneSize");
const CFStringRef kIOSurfacePlaneInfo = CFSTR("IOSurfacePlaneInfo");
const CFStringRef kIOSurfacePlaneBytesPerElement = CFSTR("IOSurfacePlaneBytesPerElement");
const CFStringRef kCVPixelBufferIOSurfacePropertiesKey = CFSTR("IOSurfaceProperties");

static uint32_t gNextID = 1000;

IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties) {
    IOSurfaceRef surf = (IOSurfaceRef)calloc(1, sizeof(struct __IOSurface));
    if (!surf)
        return NULL;

    surf->id = __sync_fetch_and_add(&gNextID, 1);
    surf->width = 1920;
    surf->height = 1080;
    surf->bytesPerElement = 4;
    surf->bytesPerRow = surf->width * surf->bytesPerElement;
    surf->allocSize = surf->bytesPerRow * surf->height;

    if (properties) {
        if (CFDictionaryContainsKey(properties, kIOSurfaceWidth)) {
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(properties, kIOSurfaceWidth);
            if (num) CFNumberGetValue(num, kCFNumberLongType, &surf->width);
        }
        if (CFDictionaryContainsKey(properties, kIOSurfaceHeight)) {
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(properties, kIOSurfaceHeight);
            if (num) CFNumberGetValue(num, kCFNumberLongType, &surf->height);
        }
        if (CFDictionaryContainsKey(properties, kIOSurfaceBytesPerRow)) {
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(properties, kIOSurfaceBytesPerRow);
            if (num) CFNumberGetValue(num, kCFNumberLongType, &surf->bytesPerRow);
        }
        if (CFDictionaryContainsKey(properties, kIOSurfaceBytesPerElement)) {
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(properties, kIOSurfaceBytesPerElement);
            if (num) CFNumberGetValue(num, kCFNumberLongType, &surf->bytesPerElement);
        }
        if (CFDictionaryContainsKey(properties, kIOSurfaceAllocSize)) {
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(properties, kIOSurfaceAllocSize);
            if (num) CFNumberGetValue(num, kCFNumberLongType, &surf->allocSize);
        }
        if (CFDictionaryContainsKey(properties, kIOSurfacePixelFormat)) {
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(properties, kIOSurfacePixelFormat);
            if (num) CFNumberGetValue(num, kCFNumberIntType, &surf->pixelFormat);
        }
    }

    if (surf->allocSize == 0)
        surf->allocSize = surf->bytesPerRow * surf->height;
    if (surf->allocSize == 0)
        surf->allocSize = 4096;

    surf->address = mmap(NULL, surf->allocSize, PROT_READ | PROT_WRITE, MAP_ANON | MAP_SHARED, -1, 0);
    if (surf->address == MAP_FAILED || surf->address == NULL)
        surf->address = malloc(surf->allocSize);

    return surf;
}

IOSurfaceID IOSurfaceGetID(IOSurfaceRef buffer) { return buffer ? buffer->id : 0; }
size_t IOSurfaceGetWidth(IOSurfaceRef buffer) { return buffer ? buffer->width : 0; }
size_t IOSurfaceGetHeight(IOSurfaceRef buffer) { return buffer ? buffer->height : 0; }
size_t IOSurfaceGetBytesPerRow(IOSurfaceRef buffer) { return buffer ? buffer->bytesPerRow : 0; }
size_t IOSurfaceGetBytesPerElement(IOSurfaceRef buffer) { return buffer ? buffer->bytesPerElement : 4; }
size_t IOSurfaceGetAllocSize(IOSurfaceRef buffer) { return buffer ? buffer->allocSize : 0; }
uint32_t IOSurfaceGetPixelFormat(IOSurfaceRef buffer) { return buffer ? buffer->pixelFormat : 0; }
void *IOSurfaceGetBaseAddress(IOSurfaceRef buffer) { return buffer ? buffer->address : NULL; }
void *IOSurfaceGetBaseAddressOfPlane(IOSurfaceRef buffer, size_t planeIndex) { return IOSurfaceGetBaseAddress(buffer); }
size_t IOSurfaceGetWidthOfPlane(IOSurfaceRef buffer, size_t planeIndex) { return IOSurfaceGetWidth(buffer); }
size_t IOSurfaceGetHeightOfPlane(IOSurfaceRef buffer, size_t planeIndex) { return IOSurfaceGetHeight(buffer); }
size_t IOSurfaceGetBytesPerRowOfPlane(IOSurfaceRef buffer, size_t planeIndex) { return IOSurfaceGetBytesPerRow(buffer); }
size_t IOSurfaceGetBytesPerElementOfPlane(IOSurfaceRef buffer, size_t planeIndex) { return IOSurfaceGetBytesPerElement(buffer); }
size_t IOSurfaceGetPlaneCount(IOSurfaceRef buffer) { return 1; }

kern_return_t IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed) {
    if (seed) *seed = 1;
    return 0;
}

kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed) {
    if (seed) *seed = 1;
    return 0;
}

void IOSurfaceIncrementUseCount(IOSurfaceRef buffer) { if (buffer) buffer->useCount++; }
void IOSurfaceDecrementUseCount(IOSurfaceRef buffer) { if (buffer && buffer->useCount > 0) buffer->useCount--; }
Boolean IOSurfaceIsInUse(IOSurfaceRef buffer) { return (buffer && buffer->useCount > 0); }
size_t IOSurfaceAlignProperty(CFStringRef property, size_t value) { return value; }
mach_port_t IOSurfaceCreateMachPort(IOSurfaceRef buffer) { return 0; }
IOSurfaceRef IOSurfaceLookupFromMachPort(mach_port_t port) { return NULL; }
void IOSurfaceSetValue(IOSurfaceRef buffer, CFStringRef key, CFTypeRef value) {}
void IOSurfaceSetPurgeable(IOSurfaceRef buffer, uint32_t newState, uint32_t *oldState) {
    if (oldState) *oldState = 0;
}

void *CVPixelBufferCreateWithIOSurface(CFAllocatorRef allocator, IOSurfaceRef surface, CFDictionaryRef pixelBufferAttributes, void **pixelBufferOut) {
    if (pixelBufferOut) *pixelBufferOut = surface;
    return NULL;
}

IOSurfaceRef CVPixelBufferGetIOSurface(void *pixelBuffer) {
    return (IOSurfaceRef)pixelBuffer;
}
