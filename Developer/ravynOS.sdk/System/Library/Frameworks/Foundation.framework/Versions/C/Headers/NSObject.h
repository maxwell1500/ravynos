/*
 * Foundation/NSObject.h
 * Copyright (c) 2026 Zoe Knox. All rights reserved.
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

#ifndef _FOUNDATION_NSOBJECT_H_
#define _FOUNDATION_NSOBJECT_H_

#include <stdarg.h>
#include <stdint.h>
#include <limits.h>
#include <sys/types.h>

/*
 * NSComparisonResult is an NSInteger, not an int: it is returned *by value*
 * by -compare: and friends, and a stock application compiled against Apple's
 * headers reads the full 64-bit register.  Declaring it as a plain enum made
 * every such call return 32 bits, so "ascending" (-1) arrived as 0x00000000FFFF
 * FFFF and comparisons against NSOrderedAscending were never true.
 */
#include <Foundation/NSObjCRuntime.h>

typedef NSInteger NSComparisonResult;

enum {
    NSOrderedAscending = -1,
    NSOrderedSame = 0,
    NSOrderedDescending = 1
};

#define NSNotFound NSIntegerMax

#include <objc/NSObject.h>

@interface NSObject (Foundation)
+(NSInteger)version;
+(void)setVersion:(NSInteger)version;
+(void)initialize;
@end

@protocol NSCopying
- copyWithZone:(struct _NSZone *) __unused zone;
@end

@protocol NSMutableCopying
- mutableCopyWithZone:(struct _NSZone *) __unused zone;
@end

@class NSCoder;
@protocol NSCoding
- initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
@end

#ifdef __cplusplus
extern "C" {
#endif
void NSLog(NSString *format,...);
void NSLogv(NSString *format,va_list arguments);
#ifdef __cplusplus
}
#endif

#define NS_RETURNS_INNER_POINTER __attribute__((objc_returns_inner_pointer))
#endif
