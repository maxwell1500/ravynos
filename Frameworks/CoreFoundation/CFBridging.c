/*
 * Toll-free bridging glue
 * Copyright (C) 2026 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "CFBridging.h"
#include "CFInternal.h"
#include <Foundation/NSCFTypeID.h>
extern Boolean __CFInitialized; /* defined in CFRuntime.c */
void _CFCompletePendingBridging(void);
extern int __CFPendingBridging;

#define DEBUG 0
#if DEBUG
#define TRACE(...) printf(__VA_ARGS__)
#else
#define TRACE(...) /**/
#endif

NSRange NSMakeRange(NSUInteger location, NSUInteger length) {
   NSRange range = { location, length };
   return range;
}

/*
 * IOKit create functions hand CF collections to clients that then send
 * Objective-C messages to them (Gecko calls objc_autorelease on the
 * dictionary from IORegistryEntryCreateCFProperties).  A C CFDictionary
 * has a CFRuntimeClass in its first word, which is not an ObjC class.
 * Build the bridged NSMutableDictionary instead.
 */
CF_EXPORT CFMutableDictionaryRef
_CFDictionaryCreateMutableObjC(CFAllocatorRef allocator, CFIndex capacity)
{
    Class cls;
    id (*msg0)(id, SEL);
    id (*msg1)(id, SEL, unsigned long);

    (void)allocator;
    cls = objc_lookUpClass("NSMutableDictionary");
    if (cls == Nil) {
        return CFDictionaryCreateMutable(allocator ? allocator : kCFAllocatorDefault,
            capacity, &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
    }
    msg0 = (id (*)(id, SEL))objc_msgSend;
    msg1 = (id (*)(id, SEL, unsigned long))objc_msgSend;
    return (CFMutableDictionaryRef)msg1(msg0((id)cls, sel_registerName("alloc")),
        sel_registerName("initWithCapacity:"), (unsigned long)capacity);
}

CF_EXPORT int _CFRuntimeRegisterObjCClass(CFTypeID typeID, uintptr_t cls)
{
    if (typeID >= __CFRuntimeClassTableSize)
        return -1;
    TRACE("Registering ObjC class 0x%lx for type ID %d\n", cls, typeID);
    __CFRuntimeObjCClassTable[typeID] = cls;
    return 0;
}

/* Registers the bridge class AND opts the typeID into the ObjC
 * superclass-chain walk of CF_IS_OBJC: for containers whose concrete
 * Foundation classes are subclasses (NSArray_concrete and friends),
 * the exact-isa match alone never fires.  Exact-only registration
 * (above) stays the default -- widening the walk to the string bridge
 * made every NSString subclass dispatch compare: into XUL and Firefox
 * faulted inside CFStringCompare. */
CF_EXPORT int _CFRuntimeRegisterObjCClassHierarchy(CFTypeID typeID, uintptr_t cls)
{
    int rc = _CFRuntimeRegisterObjCClass(typeID, cls);
    if (rc == 0 && typeID < __CFRuntimeClassTableSize)
        __CFRuntimeObjCClassWalkTable[typeID] = 1;
    return rc;
}

CF_EXPORT void CFSetupFoundationBridging(void)
{
    _CFRuntimeRegisterObjCClass(kNSCFTypeString, (uintptr_t)objc_lookUpClass("NSCFString"));
    /* The array bridge class: every Foundation array (concrete,
     * placeholder, mutable) is an NSArray, and CF_IS_OBJC walks
     * superclasses, so registering NSArray covers them all.  Without
     * this registration CFArrayGetValueAtIndex read CF-layout buckets
     * out of an ObjC array and returned garbage (measured: NULL in one
     * boot, a stale Object instance in another). */
    /* Registering needs CFArrayGetTypeID(), which registers a runtime
     * class -- but libmain's constructor in the Foundation image calls
     * this function, and the guest dyld runs image initializers in
     * load order, so in processes whose executable lists Foundation
     * before CoreFoundation (WindowServer) that registration would run
     * before __CFInitialize and corrupt the fixed class-table layout
     * (every WS instance died at boot until this was deferred).  When
     * CF is not initialized yet, defer to __CFInitialize's tail, where
     * the canonical table is in place and NSArray is installed. */
    if (__CFInitialized)
        _CFCompletePendingBridging();
    else
        __CFPendingBridging = 1;
}

int __CFPendingBridging = 0;

void _CFCompletePendingBridging(void)
{
    __CFPendingBridging = 0;
    _CFRuntimeRegisterObjCClassHierarchy(CFArrayGetTypeID(),
        (uintptr_t)objc_lookUpClass("NSArray"));
}
