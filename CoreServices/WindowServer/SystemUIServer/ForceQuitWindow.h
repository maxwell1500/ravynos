/*
 * ForceQuitWindow - Force Quit Applications dialog for SystemUIServer
 *
 * Copyright (c) 2026 ravynOS Project
 */

#pragma once
#import <AppKit/AppKit.h>

@interface ForceQuitWindow : NSWindow {
    NSTableView *_tableView;
    NSButton *_forceQuitButton;
    NSMutableArray *_apps; // Array of NSDictionary: @{@"pid": @(pid), @"name": name}
}

- (ForceQuitWindow *)init;
- (void)refreshApps;
- (void)forceQuitSelected:(id)sender;
- (void)cancel:(id)sender;

@end
