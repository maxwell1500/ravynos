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

@interface NSUserActivity : NSObject {
    NSString *_activityType;
    NSString *_title;
    NSDictionary *_userInfo;
    NSURL *_webpageURL;
    BOOL _eligibleForHandoff;
    BOOL _eligibleForSearch;
    BOOL _eligibleForPublicIndexing;
    id _delegate;
}
@property(readonly, copy) NSString *activityType;
@property(copy) NSString *title;
@property(copy) NSDictionary *userInfo;
@property(copy) NSURL *webpageURL;
@property(getter=isEligibleForHandoff) BOOL eligibleForHandoff;
@property(getter=isEligibleForSearch) BOOL eligibleForSearch;
@property(getter=isEligibleForPublicIndexing) BOOL eligibleForPublicIndexing;
@property(assign) id delegate;
- (instancetype)initWithActivityType:(NSString *)activityType;
- (void)becomeCurrent;
- (void)resignCurrent;
- (void)invalidate;
@end

@implementation NSUserActivity
- (instancetype)initWithActivityType:(NSString *)activityType {
    if((self = [super init])) {
        _activityType = [activityType copy];
        _eligibleForHandoff = YES;
    }
    return self;
}
- (void)dealloc {
    [_activityType release];
    [_title release];
    [_userInfo release];
    [_webpageURL release];
    [super dealloc];
}
- (NSString *)activityType { return _activityType; }
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)title {
    if(_title != title) {
        [_title release];
        _title = [title copy];
    }
}
- (NSDictionary *)userInfo { return _userInfo; }
- (void)setUserInfo:(NSDictionary *)info {
    if(_userInfo != info) {
        [_userInfo release];
        _userInfo = [info copy];
    }
}
- (NSURL *)webpageURL { return _webpageURL; }
- (void)setWebpageURL:(NSURL *)url {
    if(_webpageURL != url) {
        [_webpageURL release];
        _webpageURL = [url copy];
    }
}
- (BOOL)isEligibleForHandoff { return _eligibleForHandoff; }
- (void)setEligibleForHandoff:(BOOL)flag { _eligibleForHandoff = flag; }
- (BOOL)isEligibleForSearch { return _eligibleForSearch; }
- (void)setEligibleForSearch:(BOOL)flag { _eligibleForSearch = flag; }
- (BOOL)isEligibleForPublicIndexing { return _eligibleForPublicIndexing; }
- (void)setEligibleForPublicIndexing:(BOOL)flag { _eligibleForPublicIndexing = flag; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (void)becomeCurrent {}
- (void)resignCurrent {}
- (void)invalidate {}
@end

@interface NSMutableOrderedSet : NSObject
@end

@implementation NSMutableOrderedSet
@end
