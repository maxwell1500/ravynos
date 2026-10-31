/*
 * Vision -- Objective-C classes a stock application binds at load time.
 *
 * Firefox's XUL records _OBJC_CLASS_$_<name> for each of these, and dyld
 * resolves class references eagerly: a missing class stops the application
 * before it runs ("Symbol not found: _OBJC_CLASS_$_...").  The classes here
 * exist with no behaviour -- implementing them is separate work -- and every
 * method they do not implement raises the usual unrecognized-selector
 * exception rather than pretending to succeed.
 *
 * Subclasses are declared with the superclass the framework documents, so
 * type checks and isKindOfClass: in framework code behave.
 */
#import <Foundation/Foundation.h>

@interface VNImageRequestHandler : NSObject
@end

@implementation VNImageRequestHandler
@end

@interface VNRecognizeTextRequest : NSObject
@end

@implementation VNRecognizeTextRequest
@end
