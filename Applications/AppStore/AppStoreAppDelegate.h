/*
 * AppStoreAppDelegate.h - App delegate for ravynOS App Store
 */
#import <AppKit/AppKit.h>
#import "AppStoreWindowController.h"

@interface AppStoreAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) AppStoreWindowController *windowController;

@end
