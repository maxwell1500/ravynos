/*
 * AppStoreAppDelegate.m - App delegate for ravynOS App Store
 */
#import "AppStoreAppDelegate.h"

@implementation AppStoreAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self _setupMenus];
    self.windowController = [[AppStoreWindowController alloc] init];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)_setupMenus {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    /* App Store menu */
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"App Store" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App Store"];
    [appMenu addItemWithTitle:@"About App Store" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Preferences…" action:nil keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide App Store" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [hideOthers setKeyEquivalentModifierMask:NSAlternateKeyMask | NSCommandKeyMask];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit App Store" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];

    /* Window menu */
    NSMenuItem *winMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [winMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [winMenuItem setSubmenu:winMenu];
    [mainMenu addItem:winMenuItem];

    [NSApp setMainMenu:mainMenu];
}

@end
