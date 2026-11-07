#import <Foundation/NSObject.h>

@class NSData, NSString, NSMutableDictionary;

typedef uint32_t AEEventClass;
typedef uint32_t AEEventID;
typedef uint32_t DescType;
typedef uint32_t AEKeyword;
typedef int16_t AEReturnID;
typedef int32_t AETransactionID;

enum {
    kCoreEventClass = 0x61657674, /* 'aevt' */
    kAEOpenApplication = 0x6F617070, /* 'oapp' */
    kAEReopenApplication = 0x72617070, /* 'rapp' */
    kAEOpenDocuments = 0x6F646F63, /* 'odoc' */
    kAEQuitApplication = 0x71756974 /* 'quit' */
};

@interface NSAppleEventDescriptor : NSObject {
    DescType _descType;
    NSData *_data;
    AEEventClass _eventClass;
    AEEventID _eventID;
    AEReturnID _returnID;
    AETransactionID _transactionID;
}
+ (NSAppleEventDescriptor *)nullDescriptor;
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)descType data:(NSData *)data;
+ (NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)eventClass
                                            eventID:(AEEventID)eventID
                                   targetDescriptor:(NSAppleEventDescriptor *)targetDescriptor
                                           returnID:(AEReturnID)returnID
                                      transactionID:(AETransactionID)transactionID;
- (DescType)descriptorType;
- (NSData *)data;
- (AEEventClass)eventClass;
- (AEEventID)eventID;
- (AEReturnID)returnID;
- (AETransactionID)transactionID;
- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword;
- (void)setParamDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (void)removeParamDescriptorForKeyword:(AEKeyword)keyword;
- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword;
- (void)setAttributeDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (unsigned int)numberOfItems;
- (NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)index;
- (NSString *)stringValue;
- (int32_t)int32Value;
- (unsigned int)enumCodeValue;
- (unsigned int)typeCodeValue;
@end

@interface NSAppleEventManager : NSObject {
    NSMutableDictionary *_handlers;
}
+ (NSAppleEventManager *)sharedAppleEventManager;
- (void)setEventHandler:(id)handler andSelector:(SEL)handleSelector
    forEventClass:(AEEventClass)eventClass andEventID:(AEEventID)eventID;
- (void)removeEventHandlerForEventClass:(AEEventClass)eventClass
    andEventID:(AEEventID)eventID;
- (NSAppleEventDescriptor *)currentAppleEvent;
- (NSAppleEventDescriptor *)currentReplyAppleEvent;
- (void)dispatchAppleEventForClass:(AEEventClass)eventClass id:(AEEventID)eventID;
@end
