/*
 * AppCatalog.h - Software catalog and metadata management for ravynOS App Store
 */
#import <Foundation/Foundation.h>

@interface AppItem : NSObject

@property (nonatomic, copy) NSString *portName;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *homepage;
@property (nonatomic, copy) NSString *iconGlyph;
@property (nonatomic, assign) BOOL isGUIApp;
@property (nonatomic, assign) BOOL isInstalled;

@end

@interface AppCatalog : NSObject

+ (instancetype)sharedCatalog;

- (NSArray *)categories;
- (NSArray *)appsForCategory:(NSString *)category searchQuery:(NSString *)query;
- (void)refreshInstalledStatus;

@end
