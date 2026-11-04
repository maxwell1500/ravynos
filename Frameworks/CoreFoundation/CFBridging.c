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

CF_EXPORT void CFSetupFoundationBridging(void)
{
    _CFRuntimeRegisterObjCClass(kNSCFTypeString, (uintptr_t)objc_lookUpClass("NSCFString"));
}
