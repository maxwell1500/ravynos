/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Original - Christopher Lloyd <cjwl@objc.net>
#import <Foundation/NSLock.h>
#import <Foundation/NSPlatform.h>
#import <Foundation/NSRaise.h>
#import "../platform_posix/NSLock_posix.h"

@implementation NSLock

/* ravynOS: the abstract NSLock is instantiated through the CONCRETE platform
 * class directly, not through [[NSPlatform currentPlatform] lockClass].
 *
 * Asking the platform instance here closes a construction cycle that makes
 * Foundation unusable before main():
 *
 *   NSPlatformCurrentThread  ->  [NSThread alloc] + -[NSThread init]
 *     ->  [NSLock new]  ->  +[NSLock alloc]
 *       ->  [[NSPlatform currentPlatform] lockClass]
 *         ->  NSThreadSharedInstance  ->  NSPlatformCurrentThread  ->  ...
 *
 * lockClass is a constant ([NSPlatform_posix -lockClass] just returns
 * [NSLock_posix class]), so consulting the platform *instance* buys nothing and
 * costs a re-entrant call into the very machinery that is still starting up.
 * Measured on this tree: with the platform lookup in place WindowServer crashed
 * at +[NSLock alloc]'s objc_msgSend of `lockClass` (fault isa+0x18, g42-g48);
 * reordering the publish instead exposed unbounded recursion in the same cycle
 * (g49, fault on an unmapped stack page).
 *
 * NSLock_posix is the only concrete NSLock subclass on this platform and lives
 * in the same framework, so naming it directly is both correct and honest about
 * what +alloc does.  -[NSPlatform_posix lockClass] is left in place for callers
 * that already hold a platform instance. */
+allocWithZone:(NSZone *)zone {
  if(self==[NSLock class])
   return NSAllocateObject([NSLock_posix class],0,zone);
  else
   return NSAllocateObject(self,0,zone);

}

/* +[NSObject new] is [[self alloc] init], and +[NSObject alloc] calls
 * NSAllocateObject(self,...) directly -- it never routes through
 * +allocWithZone:.  So "[NSLock new]" built a real, abstract NSLock and
 * -init hit the NSInvalidAbstractInvocation() stub below, exactly as
 * [[NSString alloc] init...] did before d8660ddce5.  The redirect belongs
 * in +alloc as well; NSString/NSString.m carries the same fix.  */
+(id)alloc {
   if(self==[NSLock class])
   return NSAllocateObject([NSLock_posix class],0,NULL);

   return NSAllocateObject(self,0,NULL);
}

-init {
   NSInvalidAbstractInvocation();
   return self;
}

-(void)dealloc
{
    [_name release];
    [super dealloc];
}

-(NSString *)name
{
    return _name;
}

-(void)setName:(NSString *)value
{
    if(value!=_name)
    {
        [_name release];
        _name=[value retain];
    }
}

-(void)lock {
   NSInvalidAbstractInvocation();
}

-(void)unlock {
   NSInvalidAbstractInvocation();
}

-(BOOL)tryLock {
   NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)lockBeforeDate:(NSDate *)value {
   NSInvalidAbstractInvocation();
   return NO;
}

@end
