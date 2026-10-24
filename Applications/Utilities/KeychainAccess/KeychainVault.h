#import <Foundation/Foundation.h>

@interface KeychainItem : NSObject
@property (copy) NSString *uuid;
@property (copy) NSString *itemClass; // @"password", @"note", @"certificate"
@property (copy) NSString *service;
@property (copy) NSString *account;
@property (copy) NSString *label;
@property (strong) NSData *secretData;
@property (copy) NSString *notes;
@property (strong) NSDate *created;
@property (strong) NSDate *modified;
- (NSString *)displayTitle;
@end

@interface KeychainVault : NSObject
+ (instancetype)vaultWithPath:(NSString *)path;
@property (readonly, copy) NSString *path;
@property (readonly, getter=isLocked) BOOL locked;
@property (readonly) BOOL exists;
- (BOOL)unlockWithPassword:(NSString *)password error:(NSError **)error;
- (void)lock;
- (BOOL)verifyPassword:(NSString *)password;
- (BOOL)changePassword:(NSString *)oldPassword to:(NSString *)newPassword error:(NSError **)error;
- (NSArray *)allItems;
- (NSArray *)itemsMatchingClass:(NSString *)cls;
- (BOOL)addItem:(KeychainItem *)item error:(NSError **)error;
- (BOOL)updateItem:(KeychainItem *)item error:(NSError **)error;
- (BOOL)deleteItem:(KeychainItem *)item error:(NSError **)error;
@end