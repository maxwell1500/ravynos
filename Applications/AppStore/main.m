/*
 * main.m - Entry point for ravynOS App Store
 */
#import <AppKit/AppKit.h>
#import "AppStoreAppDelegate.h"

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        AppStoreAppDelegate *delegate = [[AppStoreAppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
