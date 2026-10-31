/*
 * Foundation -- Objective-C classes a stock application binds at load time.
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

@interface NSAppleEventDescriptor : NSObject
@end

@implementation NSAppleEventDescriptor
@end

@interface NSAppleEventManager : NSObject
+ (NSAppleEventManager *)sharedAppleEventManager;
- (void)setEventHandler:(id)handler andSelector:(SEL)handleSelector
    forEventClass:(unsigned int)eventClass andEventID:(unsigned int)eventID;
- (void)removeEventHandlerForEventClass:(unsigned int)eventClass
    andEventID:(unsigned int)eventID;
- (NSAppleEventDescriptor *)currentAppleEvent;
- (NSAppleEventDescriptor *)currentReplyAppleEvent;
@end

@implementation NSAppleEventManager
+ (NSAppleEventManager *)sharedAppleEventManager
{
	static NSAppleEventManager *shared;
	static BOOL noted;

	if (shared == nil)
		shared = [[self alloc] init];
	if (!noted) {
		noted = YES;
		NSLog(@"[compat] Foundation: NSAppleEventManager exists; handler "
		    "registration is recorded but Apple Events are not dispatched");
	}
	return (shared);
}

- (void)setEventHandler:(id)handler andSelector:(SEL)handleSelector
    forEventClass:(unsigned int)eventClass andEventID:(unsigned int)eventID
{
	/* Recorded nowhere: WindowServer does not deliver Apple Events in this
	 * tree yet.  The registration itself must not fail, or applications
	 * abort before their first window (Firefox did). */
	(void)handler;
	(void)handleSelector;
	(void)eventClass;
	(void)eventID;
}

- (void)removeEventHandlerForEventClass:(unsigned int)eventClass
    andEventID:(unsigned int)eventID
{
	(void)eventClass;
	(void)eventID;
}

- (NSAppleEventDescriptor *)currentAppleEvent { return (nil); }
- (NSAppleEventDescriptor *)currentReplyAppleEvent { return (nil); }
@end

@interface NSProgress : NSObject
@end

@implementation NSProgress
@end

@interface NSURLFileTypeMappings : NSObject
@end

@implementation NSURLFileTypeMappings
@end

@interface NSURLSession : NSObject
@end

@implementation NSURLSession
@end

@interface NSUserActivity : NSObject
@end

@implementation NSUserActivity
@end

@interface NSMutableOrderedSet : NSObject
@end

@implementation NSMutableOrderedSet
@end
