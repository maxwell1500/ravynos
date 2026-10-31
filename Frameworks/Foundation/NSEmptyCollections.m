/*
 * Fill CoreFoundation's empty-collection singletons.
 *
 * XUL references ___NSArray0__ and ___NSDictionary0__ (the objects behind
 * @[] and @{}), and these are bound to CoreFoundation on macOS.  CF exports
 * the storage; the classes are ours, so they are created here when Foundation
 * loads, before any application code can evaluate a literal.
 */
#import <Foundation/Foundation.h>

extern id __NSArray0__;
extern id __NSDictionary0__;

@interface NSArray (RavynEmptyCollections)
@end
@implementation NSArray (RavynEmptyCollections)
+ (void)load
{
	if (__NSArray0__ == nil) {
		__NSArray0__ = [[NSArray alloc] init];
	}
}
@end

@interface NSDictionary (RavynEmptyCollections)
@end
@implementation NSDictionary (RavynEmptyCollections)
+ (void)load
{
	if (__NSDictionary0__ == nil) {
		__NSDictionary0__ = [[NSDictionary alloc] init];
	}
}
@end
