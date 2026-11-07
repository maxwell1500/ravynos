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

@implementation NSAppleEventDescriptor
+ (NSAppleEventDescriptor *)nullDescriptor {
	static NSAppleEventDescriptor *nullDesc = nil;
	if (nullDesc == nil) {
		nullDesc = [[self alloc] init];
		nullDesc->_descType = 0x6E756C6C;
	}
	return nullDesc;
}

+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)descType data:(NSData *)data {
	NSAppleEventDescriptor *d = [[[self alloc] init] autorelease];
	d->_descType = descType;
	d->_data = [data copy];
	return d;
}

+ (NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)eventClass
                                            eventID:(AEEventID)eventID
                                   targetDescriptor:(NSAppleEventDescriptor *)targetDescriptor
                                           returnID:(AEReturnID)returnID
                                      transactionID:(AETransactionID)transactionID
{
	(void)targetDescriptor;
	NSAppleEventDescriptor *d = [[[self alloc] init] autorelease];
	d->_descType = 0x61657674;
	d->_eventClass = eventClass;
	d->_eventID = eventID;
	d->_returnID = returnID;
	d->_transactionID = transactionID;
	return d;
}

- (DescType)descriptorType { return _descType; }
- (NSData *)data { return _data ? _data : [NSData data]; }
- (AEEventClass)eventClass { return _eventClass; }
- (AEEventID)eventID { return _eventID; }
- (AEReturnID)returnID { return _returnID; }
- (AETransactionID)transactionID { return _transactionID; }
- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword { (void)keyword; return nil; }
- (void)setParamDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword { (void)descriptor; (void)keyword; }
- (void)removeParamDescriptorForKeyword:(AEKeyword)keyword { (void)keyword; }
- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword { (void)keyword; return nil; }
- (void)setAttributeDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword { (void)descriptor; (void)keyword; }
- (unsigned int)numberOfItems { return 0; }
- (NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)index { (void)index; return nil; }
- (NSString *)stringValue { return @""; }
- (int32_t)int32Value { return 0; }
- (unsigned int)enumCodeValue { return 0; }
- (unsigned int)typeCodeValue { return 0; }

- (void)dealloc {
	[_data release];
	[super dealloc];
}
@end

@interface _NSAppleEventHandlerEntry : NSObject {
@public
	id handler;
	SEL selector;
	BOOL dispatched;
}
@end

@implementation _NSAppleEventHandlerEntry
@end

@implementation NSAppleEventManager
+ (NSAppleEventManager *)sharedAppleEventManager
{
	static NSAppleEventManager *shared;
	if (shared == nil)
		shared = [[self alloc] init];
	return (shared);
}

- (id)init {
	self = [super init];
	if (self) {
		_handlers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)setEventHandler:(id)handler andSelector:(SEL)handleSelector
    forEventClass:(AEEventClass)eventClass andEventID:(AEEventID)eventID
{
	char cls[5] = { (char)(eventClass >> 24), (char)(eventClass >> 16),
	                (char)(eventClass >> 8), (char)eventClass, 0 };
	char idstr[5] = { (char)(eventID >> 24), (char)(eventID >> 16),
	                  (char)(eventID >> 8), (char)eventID, 0 };
	NSLog(@"[NSAppleEventManager] register handler %p sel=%s for class='%s' id='%s'",
	      handler, sel_getName(handleSelector), cls, idstr);

	_NSAppleEventHandlerEntry *entry = [[_NSAppleEventHandlerEntry alloc] init];
	entry->handler = handler;
	entry->selector = handleSelector;
	entry->dispatched = NO;
	NSNumber *key = [NSNumber numberWithUnsignedLongLong:(((uint64_t)eventClass) << 32) | (uint64_t)eventID];
	[_handlers setObject:entry forKey:key];
	[entry release];

	if (eventClass == kCoreEventClass && eventID == kAEOpenApplication) {
		[self performSelector:@selector(_dispatchPendingOApp:)
		           withObject:key
		           afterDelay:0.0];
	}
}

- (void)_dispatchPendingOApp:(NSNumber *)key {
	_NSAppleEventHandlerEntry *entry = [_handlers objectForKey:key];
	if (entry != nil && !entry->dispatched) {
		[self dispatchAppleEventForClass:kCoreEventClass id:kAEOpenApplication];
	}
}

- (void)removeEventHandlerForEventClass:(AEEventClass)eventClass
    andEventID:(AEEventID)eventID
{
	NSNumber *key = [NSNumber numberWithUnsignedLongLong:(((uint64_t)eventClass) << 32) | (uint64_t)eventID];
	[_handlers removeObjectForKey:key];
}

- (void)dispatchAppleEventForClass:(AEEventClass)eventClass id:(AEEventID)eventID {
	NSNumber *key = [NSNumber numberWithUnsignedLongLong:(((uint64_t)eventClass) << 32) | (uint64_t)eventID];
	_NSAppleEventHandlerEntry *entry = [_handlers objectForKey:key];
	if (entry != nil && entry->handler != nil && entry->selector != NULL) {
		if (entry->dispatched) {
			NSLog(@"[NSAppleEventManager] event 0x%08x:0x%08x already dispatched to %p",
			      eventClass, eventID, entry->handler);
			return;
		}
		entry->dispatched = YES;
		char cls[5] = { (char)(eventClass >> 24), (char)(eventClass >> 16),
		                (char)(eventClass >> 8), (char)eventClass, 0 };
		char idstr[5] = { (char)(eventID >> 24), (char)(eventID >> 16),
		                  (char)(eventID >> 8), (char)eventID, 0 };
		NSLog(@"[NSAppleEventManager] dispatching '%s':'%s' to %p sel=%s",
		      cls, idstr, entry->handler, sel_getName(entry->selector));
		NSAppleEventDescriptor *evt = [NSAppleEventDescriptor appleEventWithEventClass:eventClass
		                                                                       eventID:eventID
		                                                              targetDescriptor:nil
		                                                                      returnID:0
		                                                                 transactionID:0];
		NSAppleEventDescriptor *reply = [NSAppleEventDescriptor nullDescriptor];
		[entry->handler performSelector:entry->selector withObject:evt withObject:reply];
	}
}

- (NSAppleEventDescriptor *)currentAppleEvent { return [NSAppleEventDescriptor nullDescriptor]; }
- (NSAppleEventDescriptor *)currentReplyAppleEvent { return [NSAppleEventDescriptor nullDescriptor]; }
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
