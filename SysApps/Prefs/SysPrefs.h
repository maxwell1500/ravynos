/*
 * Copyright (C) 2024-2026 ravynOS Project
 */

#pragma once
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGDirectDisplay.h>

 @interface SystemPreferences : NSApplication <NSApplicationDelegate> {
    NSWindow *window;
    NSTableView *sidebarView;
    NSView *detailContainer;
    NSArray *categories;
    NSView *currentPaneView;

    // Displays
    CGDirectDisplayID displayID;
    NSMutableArray *displayModeTitles;
    NSMutableArray *displayModeRefs;
    int selectedDisplayMode;
    NSPopUpButton *dispRefreshPopup;
    NSPopUpButton *dispScalePopup;
    NSPopUpButton *dispRotationPopup;
    NSTextField *dispCurrentLabel;

    // Network
    NSPopUpButton *netIfacePopup;
    NSTextField *netStatusField;
    NSPopUpButton *netConfigPopup;
    NSTextField *netIPField;
    NSTextField *netMaskField;
    NSTextField *netRouterField;
    NSTextField *netDNSField;
    NSMutableArray *netIfaceNames;

    // Users
    NSTableView *usersTable;
    NSMutableArray *usersList;
    NSButton *autoLoginToggle;
    NSPopUpButton *autoLoginPopup;
    NSTableView *loginItemsTable;
    NSMutableArray *loginItemsList;

    // Appearance
    NSButton *appearanceLightBtn;
    NSButton *appearanceDarkBtn;
    NSSlider *dockSizeSlider;
    NSButton *dockMagnifyCheck;
    NSButton *dockAutoHideCheck;
    NSButton *dockPosBottom;
    NSButton *dockPosLeft;
    NSButton *dockPosRight;

    // Keyboard
    NSSlider *keyRepeatSlider;
    NSSlider *keyDelaySlider;
    NSPopUpButton *capsLockPopup;
    NSButton *swapCmdOptCheck;
    NSSlider *trackingSlider;
    NSButton *naturalScrollCheck;

    // Sound
    NSTableView *soundOutTable;
    NSMutableArray *soundOutDevices;
    NSSlider *soundVolSlider;
    NSButton *soundMuteCheck;
    NSPopUpButton *alertSoundPopup;
    NSTableView *soundInTable;
    NSMutableArray *soundInDevices;
    NSSlider *soundInputVolSlider;
    NSTextField *soundLevelField;
    NSTextField *soundNoDeviceLabel;
}

- (void)selectCategoryAtIndex:(int)index;
- (NSView *)createDisplaysPane;
- (NSView *)createNetworkPane;
- (NSView *)createUsersPane;
- (NSView *)createAppearancePane;
- (NSView *)createKeyboardPane;
- (NSView *)createSoundPane;

- (void)broadcastPrefsChanged;
- (void)writePlist:(NSDictionary *)dict toPath:(NSString *)path;

@end