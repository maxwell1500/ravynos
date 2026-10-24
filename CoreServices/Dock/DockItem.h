/*
 * ravynOS Application Launcher & Status Bar
 *
 * Copyright (C) 2021-2022 Zoe Knox <zoe@pixin.net>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#pragma once

#import <AppKit/AppKit.h>

enum DockItemType : unsigned int {
    DIT_INVALID,
    DIT_APP_BUNDLE,     // item is NSBundle
    DIT_APP_APPDIR,     // item is AppDir
    DIT_APP_FOREIGN,    // item is unknown app found by window event
    DIT_WINDOW,         // item is minimized window
    DIT_FOLDER,         // item is a folder shortcut
    DIT_MAX = DIT_FOLDER
};

enum DockItemFlags : unsigned int {
    DIF_NORMAL = 0x0,
    DIF_LOCKED = 0x1,       // can't modify or remove
    DIF_PERSISTENT = 0x2,   // app is persistent in dock
    DIF_ATTENTION = 0x4     // app wants attention
};

typedef enum DockItemType DockItemType;
typedef enum DockItemFlags DockItemFlags;

@interface DockItem : NSView {
    DockItemType _type;
    DockItem *_app;         // owning app if this is a window, else nil
    unsigned int _flags;
    NSString *_path;        // path of the item represented
    NSString *_execPath;    // actual executable for _path
    NSString *_bundleID;    // CFBundleIdentifier
    NSMutableArray *_windows; // Window IDs
    NSString *_label;       // displayed on hover
    NSString *_badgeText;
    NSImageView *_badge;    // small app icon badge for window items
    NSImageView *_icon;
    CGImageRef _iconImage;  // icon composited by drawRect: (the control layer never paints)
    NSImageView *_origIcon; // original icon we found, to revert custom icons
    NSImageView *_runMarker;
    BOOL _isRunning;
    BOOL _special;
}

+(DockItem *)dockItemWithPath:(NSString *)path;
+(DockItem *)dockItemWithMinimizedWindow:(unsigned int)window forApp:(DockItem *)item;
+(int)iconSize;

-(DockItem *)initWithPath:(NSString *)path;
-(DockItem *)initWithMinimizedWindow:(unsigned int)window forApp:(DockItem *)item;
-(void)setTileSize:(NSSize)size;
-(void)drawIconInContext:(CGContextRef)context;

-(NSString *)path;
-(NSString *)execPath;
-(NSString *)bundleIdentifier;
-(NSString *)label;
-(DockItemType)type;
-(DockItemFlags)flags;
-(BOOL)isNormal;
-(BOOL)isLocked;
-(BOOL)isRunning;
-(BOOL)isPersistent;
-(BOOL)isSpecial;
-(BOOL)needsAttention;
-(unsigned int)dockWindowID; // NOT -window: that shadows NSView's window and
                             // returns a 32-bit value where callers (AppKit)
                             // expect an NSWindow pointer.
-(DockItem *)app;
-(NSArray *)windows;
-(NSImage *)icon;
-(BOOL)hasPath:(NSString *)path;

-(void)setFlags:(DockItemFlags)flags;
-(void)setNormal; // clears all flags
-(void)setLocked:(BOOL)value;
-(void)setRunning:(BOOL)value;
-(void)addWindow:(unsigned int)window;
-(void)removeWindow:(unsigned int)window;
-(void)setPersistent:(BOOL)value;
-(void)setNeedsAttention:(BOOL)value;

-(void)activateWindow:(id)sender;
-(void)openApp:(id)sender;
-(NSDictionary *)tileData;
-(void)_installTileClickProxy;
@end

// A tile's icon/badge/run-marker are live subviews, so AppKit's hitTest
// (NSWindow.m:2223 [_backgroundView hitTest:] -> deepest view) hands the click to
// one of them instead of the DockItem. An invisible cover installed frontmost is
// what receives the click and forwards it to openApp:.
@interface NSTileClickProxy : NSView { id _tileOwner; }
-(void)setTileOwner:(id)owner;
-(void)mouseDown:(NSEvent *)event;
@end
