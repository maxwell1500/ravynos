/*
 * ravynOS Application Launcher & Status Bar
 *
 * Copyright (C) 2021-2024 Zoe Knox <zoe@pixin.net>
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

#import <AppKit/AppKit.h>
#import <AppKit/NSRaise.h>
#import <CoreGraphics/CGWindowLevel.h>
#import "Dock.h"
#import "DockItem.h"
#import "DockTileData.h"
#import "DesktopWindow.h"
#import "WindowServer/message.h"
#import "WindowServer/rpc.h"

@interface DockView: NSView
@end

@interface Divider: NSView
@end

extern Dock *dock; // our singleton object in main.m

/* WindowServer RPC entry point, provided by libWindowServer on ravynOS. */
kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);

@implementation Dock

/* The Dock's preferences are read from the same file System Preferences
 * writes.  NSUserDefaults would resolve the "Dock" domain to
 * $HOME/Library/Preferences/Dock.plist, which is not where the Preferences
 * app puts them, so read the shared location explicitly and fall back to the
 * per-domain path only when it is missing. */
-(NSDictionary *)readDockPlist {
    NSArray *paths = [NSArray arrayWithObjects:
        @"/Library/Preferences/Dock.plist",
        [@"~/Library/Preferences/Dock.plist" stringByExpandingTildeInPath],
        [@"~/Library/Preferences/com.ravynos.Dock.plist" stringByExpandingTildeInPath],
        nil];
    unsigned i;

    for(i = 0; i < [paths count]; i++) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:
            [paths objectAtIndex:i]];

        if(dict != nil)
            return dict;
    }
    return nil;
}

-(id)init {
    NSDictionary *plist;

    _PID = getpid();
    _prefs = [NSUserDefaults standardUserDefaults];
    _desktops = [NSMutableDictionary new];
    _currentSize = NSZeroSize;
    _window = nil;
    _hidden = NO;
    _hoverIndex = -1;

    plist = [self readDockPlist];

    _tileSize = [[plist objectForKey:INFOKEY_TILESIZE] intValue];
    if(_tileSize < TILESIZE_MIN)
        _tileSize = [_prefs integerForKey:INFOKEY_TILESIZE];
    if(_tileSize < TILESIZE_MIN)
        _tileSize = 64;

    int pos = [[plist objectForKey:INFOKEY_LOCATION] intValue];
    if(plist == nil)
        pos = [_prefs integerForKey:INFOKEY_LOCATION];
    _location = (Location)pos;

    _alpha = [[plist objectForKey:INFOKEY_OPACITY] floatValue];
    if(_alpha <= 0.0f)
        _alpha = [_prefs floatForKey:INFOKEY_OPACITY];
    if(_alpha <= 0.0f)
        _alpha = 0.85;

    _autohide = [[plist objectForKey:INFOKEY_AUTOHIDE] boolValue];
    _magnification = [[plist objectForKey:INFOKEY_MAGNIFICATION] boolValue];

    [self loadItems];

    int max = [self fitWindowToItems];
    NSRect frame = NSMakeRect(0,0,_currentSize.width,_currentSize.height);
    [self createWindowWithFrame:frame];
    [self placeItemsInWindow:max];
    return self;
}

-(void)applicationWillFinishLaunching:(NSNotification *)note {
    NSScreen *screen = [NSScreen mainScreen];
    DesktopWindow *desktop = nil;

    /* A desktop window can fail to come up (no screen yet); the Dock still
     * has to run, and -[NSMutableDictionary setObject:nil ...] aborted it. */
    if(screen != nil)
        desktop = [[DesktopWindow alloc] initForScreen:screen];
    if(desktop != nil) {
        [_desktops setObject:desktop forKey:@"NSMainScreen"]; // FIXME: use NSScreen deviceDescription dict for display ID
        [desktop setDelegate:self];
        [desktop orderBack:self];
    }

    [_window makeKeyAndOrderFront:nil];
    [_window display];

    [self savePrefs];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidQuit:)
        name:@"NSApplicationDidQuit" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidLaunch:)
        name:@"NSApplicationDidLaunch" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
         selector:@selector(windowDidChangeState:) name:@"WSWindowDidChangeState" object:nil];
    /* The System Settings app changed the Dock's preferences. */
    [[NSNotificationCenter defaultCenter] addObserver:self
         selector:@selector(preferencesChanged:) name:NSApplicationPreferencesChangedNotification object:nil];

    /* Autohide and magnification need the pointer position even when the
     * Dock is off screen, so poll it rather than relying on tracking areas
     * (a hidden window receives no mouse-moved events). */
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.08 target:self
        selector:@selector(pollMouse:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_pollTimer forMode:NSRunLoopCommonModes];

    /* WindowServer may have seen apps launch while this delegate was still
     * being set up (Filer registers before we get here), so ask it to replay
     * the launch announcements now that the observers above are in place.
     * Without this the Filer tile never learns the app is running and
     * clicking it forks a second instance. */
    struct wsRPCBase data = { kWSApplicationList, 0 };
    _windowServerRPC(&data, sizeof(data), NULL, NULL);
}

-(void)windowDidChangeState:(NSNotification *)note {
    NSMutableDictionary *dict = (NSMutableDictionary *)[note userInfo];
    NSString *bundleID = [dict objectForKey:@"BundleID"];
    pid_t pid = [[dict objectForKey:@"ProcessID"] intValue];
    int windowID = [[dict objectForKey:@"WindowID"] intValue];
    int state = [[dict objectForKey:@"State"] intValue];

    // First, find the matching app owning this window
    DockItem *app = nil;
    for(int i = 0; i < [_items count]; ++i) {
        DockItem *candidate = [_items objectAtIndex:i];
        if([candidate type] == DIT_WINDOW)
            continue;
        if([[candidate bundleIdentifier] isEqualToString:bundleID]) {
            app = candidate;
            break;
        }
    }

    if(!app) {
        NSLog(@"processWindowUpdate for unknown app %@", bundleID);
        return;
    }

    switch(state) {
        case MINIMIZED: {
            DockItem *win = [DockItem dockItemWithMinimizedWindow:windowID
                                                           forApp:app];
            [_items insertObject:win atIndex:[_items count] - 1];
            [app addWindow:windowID];
            [self relocate];
            break;
        }
        default: {
            for(int i = 0; i < [_items count]; ++i) {
                DockItem *win = [_items objectAtIndex:i];
                if([win type] != DIT_WINDOW)
                    continue;
                if([win dockWindowID] == windowID) {
                    [app removeWindow:windowID];
                    [_items removeObject:win];
                    [self relocate];
                }
            }
        }
    }
}

-(void)appDidLaunch:(NSNotification *)note {
    NSMutableDictionary *dict = (NSMutableDictionary *)[note userInfo];
    NSString *bundleID = [dict objectForKey:@"BundleID"];
    pid_t pid = [[dict objectForKey:@"ProcessID"] intValue];
    NSString *path = [dict objectForKey:@"Path"];

    // just to be safe
    if([bundleID isEqualToString:@"com.ravynos.Dock"] ||
        [bundleID isEqualToString:@"com.ravynos.WindowServer"] ||
        [bundleID isEqualToString:@"com.ravynos.SystemUIServer"] ||
        [bundleID isEqualToString:@"com.ravynOS.LoginWindow"])
            return;

    DockItem *item = [self dockItemForPath:path];
    if(item == nil) {
        item = [DockItem dockItemWithPath:path];
        if([item type] == DIT_INVALID) {
            NSDebugLog(@"Invalid bundle type for %@", path);
            return;
        }

        [item setRunning:YES];
        [_items insertObject:item atIndex:[_items count] - 1]; // before Trash
        [self relocate];
    } else if([item isPersistent])
        [item setRunning:YES];
    else
        NSDebugLog(@"Attempted to add launched bundle %@ with path %@, already added",
                bundleID, path);
}

-(void)appDidQuit:(NSNotification *)note {
    NSMutableDictionary *dict = (NSMutableDictionary *)[note userInfo];
    NSString *path = [dict objectForKey:@"Path"];
    DockItem *item = [self dockItemForPath:path];

    if(item == nil) {
        NSLog(@"App %@ exited but not found in our list", path);
        return;
    }

    [item setRunning:NO];
    if(![item isPersistent]) {
        [_items removeObjectIdenticalTo:item];
    }

    int count = [_items count];
    for(int i = 0; i < count; ) {
        DockItem *d = [_items objectAtIndex:i];
        if([d type] == DIT_WINDOW && [d app] == item) {
            [_items removeObject:d];
            --count;
        } else
            ++i;
    }
    [self relocate];
}

-(DockItem *)dockItemForPath:(NSString *)path {
    for(int i = 0; i < [_items count]; ++i) {
        DockItem *item = [_items objectAtIndex:i];
        if([item hasPath:path])
            return item;
    }
    return nil;
}

-(NSRect)positionWindowWithFrame:(NSRect)frame {
    NSScreen *mainScreen = [NSScreen mainScreen];
    switch(_location) {
        case LOCATION_LEFT:
            frame.origin.x = 0;
            frame.origin.y = [mainScreen frame].size.height / 2 - frame.size.height / 2;
            break;
        case LOCATION_RIGHT:
            frame.origin.x = [mainScreen frame].size.width - frame.size.width;
            frame.origin.y = [mainScreen frame].size.height / 2 - frame.size.height / 2;
            break;
        default:
            frame.origin.x = [mainScreen frame].size.width / 2 - frame.size.width / 2;
            frame.origin.y = 0;
    }

    /* Autohide: leave a 4 px strip at the screen edge so the pointer can find
     * the Dock again. */
    if(_autohide && _hidden) {
        NSSize screen = [mainScreen frame].size;
        switch(_location) {
            case LOCATION_LEFT:
                frame.origin.x = -frame.size.width + 4;
                break;
            case LOCATION_RIGHT:
                frame.origin.x = screen.width - 4;
                break;
            default:
                frame.origin.y = -frame.size.height + 4;
                break;
        }
    }
    return frame;
}

-(NSWindow *)createWindowWithFrame:(NSRect)frame {
    _window = [[NSWindow alloc] initWithContentRect:[self positionWindowWithFrame:frame]
                                          styleMask:NSBorderlessWindowMask
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    // transparent background because we'll draw over it
    [_window setBackgroundColor:[NSColor colorWithDeviceRed:1 green:1 blue:1 alpha:0]];
    [_window setContentView:[[DockView alloc] initWithFrame:
        NSMakeRect(0, 0, frame.size.width, frame.size.height)]];
    [_window setLevel:kCGDockWindowLevelKey];
    [_window setDelegate:self];

    return _window;
}

-(NSArray *)tileDataForAppItems {
    NSMutableArray *a = [NSMutableArray new];
    for(int i = 0; i < [_items count]; ++i) {
        DockItem *di = [_items objectAtIndex:i];
        if(![di isPersistent] || [[di bundleIdentifier] hasPrefix:@"com.ravynos.Dock"])
            continue;
        [a addObject:[di tileData]];
    }
    return [NSArray arrayWithArray:a];
}

-(NSArray *)tileDataForOtherItems {
    return [NSArray new];
}

-(void)savePrefs {
    [_prefs setInteger:_tileSize forKey:INFOKEY_TILESIZE];
    [_prefs setInteger:_location forKey:INFOKEY_LOCATION];
    [_prefs setFloat:_alpha forKey:INFOKEY_OPACITY];

    NSMutableDictionary *_wallpaper = [NSMutableDictionary new];
    NSArray *values = [_desktops allValues];
    for(unsigned i = 0; i < [values count]; ++i) {
        DesktopWindow *dw = [values objectAtIndex:i];
        NSString *path = [dw wallpaperPath];

        /* A window that has not resolved its wallpaper yet has no path; an
         * empty dictionary entry is what raised "insert nil object" here. */
        if(path != nil)
            [_wallpaper setObject:path forKey:@"NSMainScreen"]; // FIXME: CGDisplayID
    }
    [_prefs setObject:_wallpaper forKey:INFOKEY_WALLPAPER];
    [_prefs setObject:[self tileDataForAppItems] forKey:INFOKEY_PERSISTENT_APPS];
    //[_prefs setObject:[self tileDataForOtherItems] forKey:INFOKEY_PERSISTENT_OTHERS];

    [_prefs synchronize];

    /* Mirror the settings the Preferences app owns into the shared file, so
     * both apps read and write one place.  The Dock's own tile list still
     * lives in its NSUserDefaults domain. */
    {
        NSMutableDictionary *shared = [NSMutableDictionary dictionaryWithDictionary:
            ([NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/Dock.plist"] ?: @{})];

        [shared setObject:[NSNumber numberWithInt:_tileSize] forKey:INFOKEY_TILESIZE];
        [shared setObject:[NSNumber numberWithInt:(int)_location] forKey:INFOKEY_LOCATION];
        [shared setObject:[NSNumber numberWithFloat:_alpha] forKey:INFOKEY_OPACITY];
        [shared setObject:[NSNumber numberWithBool:_autohide] forKey:INFOKEY_AUTOHIDE];
        [shared setObject:[NSNumber numberWithBool:_magnification] forKey:INFOKEY_MAGNIFICATION];

        if(![[NSFileManager defaultManager] fileExistsAtPath:@"/Library/Preferences"])
            [[NSFileManager defaultManager] createDirectoryAtPath:@"/Library/Preferences"
                withIntermediateDirectories:YES attributes:nil error:nil];
        [shared writeToFile:@"/Library/Preferences/Dock.plist" atomically:YES];
    }
}

// size the window to our number of items. if it exceeds the screen size, shrink the tiles
// until it fits or we reach the minimum tile size. truncate items if we can't display them.
-(DockItem *)itemAtDisplayIndex:(int)idx ofTotal:(int)displayCount {
    if(displayCount < [_items count] && idx == displayCount - 1)
        return [_items objectAtIndex:[_items count] - 1];
    return [_items objectAtIndex:idx];
}

-(int)calculateLengthForItems:(int)count {
    if(count <= 0)
        return 2 * END_CAP;
    int len = 2 * END_CAP;
    for(int i = 0; i < count; ++i) {
        if(i > 0) {
            DockItem *curr = [self itemAtDisplayIndex:i ofTotal:count];
            DockItem *prev = [self itemAtDisplayIndex:i-1 ofTotal:count];
            if([curr isSpecial] && ![prev isSpecial])
                len += DIVIDER_SPACE;
            else
                len += CELL_SPACER;
        }
        len += _tileSize;
    }
    return len;
}

-(int)fitWindowToItems {
    NSSize scrSize = [[NSScreen mainScreen] visibleFrame].size;

    int maxLength = (_location == LOCATION_BOTTOM) ? scrSize.width : scrSize.height;
    int numItems = [_items count];
    int needLength;

    do {
        needLength = [self calculateLengthForItems:numItems];
        if(needLength > maxLength)
            _tileSize -= 8;
    } while(needLength > maxLength && _tileSize > TILESIZE_MIN);

    int maxItems = numItems;
    while(needLength > maxLength && maxItems > 0) {
        --maxItems;
        needLength = [self calculateLengthForItems:maxItems];
    }

    if(_location == LOCATION_BOTTOM) {
        _currentSize.height = _tileSize + 16;
        _currentSize.width = needLength;
    } else {
        _currentSize.height = needLength;
        _currentSize.width = _tileSize + 16;
    }

    return maxItems;
}

-(void)placeItemsInWindow:(int)maxItems {
    if(maxItems < [_items count])
        NSLog(@"Warning: truncating some items to fit the screen");

    NSArray *existing = [[[_window contentView] subviews] copy];
    for(NSView *v in existing) {
        [v removeFromSuperview];
    }

    NSPoint itemPos;
    if(_location == LOCATION_BOTTOM)
        itemPos = NSMakePoint(END_CAP, 0);
    else
        itemPos = NSMakePoint(0, END_CAP);

    NSSize size = NSMakeSize(_tileSize, _tileSize);
    int count = (maxItems < [_items count]) ? maxItems : (int)[_items count];

    for(int i = 0; i < count; ++i) {
        DockItem *item = [self itemAtDisplayIndex:i ofTotal:count];

        if(i > 0) {
            DockItem *prev = [self itemAtDisplayIndex:i-1 ofTotal:count];
            if([item isSpecial] && ![prev isSpecial]) {
                NSRect rect;
                if(_location == LOCATION_BOTTOM) {
                    rect = NSMakeRect(itemPos.x + (DIVIDER_SPACE - 2) / 2, 8, 2, _tileSize);
                    itemPos.x += DIVIDER_SPACE;
                } else {
                    rect = NSMakeRect(8, itemPos.y + (DIVIDER_SPACE - 2) / 2, _tileSize, 2);
                    itemPos.y += DIVIDER_SPACE;
                }
                Divider *divider = [[Divider alloc] initWithFrame:rect];
                [[_window contentView] addSubview:divider];
            } else {
                if(_location == LOCATION_BOTTOM)
                    itemPos.x += CELL_SPACER;
                else
                    itemPos.y += CELL_SPACER;
            }
        }

        NSSize thisSize = size;
        if(_magnification && _hoverIndex >= 0) {
            int distance = i - _hoverIndex;
            if(distance < 0) distance = -distance;
            if(distance == 0)
                thisSize = NSMakeSize(_tileSize * 1.35, _tileSize * 1.35);
            else if(distance == 1)
                thisSize = NSMakeSize(_tileSize * 1.15, _tileSize * 1.15);
        }
        /* Keep magnified tiles inside the dock window: the grown tile is
         * centred on its normal slot. */
        [item setFrameOrigin:NSMakePoint(itemPos.x - (thisSize.width - _tileSize) / 2,
                                         itemPos.y - (thisSize.height - _tileSize) / 2)];
        [item setTileSize:thisSize];
        [[_window contentView] addSubview:item];
        [item _installTileClickProxy];

        if(_location == LOCATION_BOTTOM)
            itemPos.x += _tileSize;
        else
            itemPos.y += _tileSize;
    }

    [[_window contentView] setNeedsDisplay:YES];
}

-(void)loadItems {
    if(_items == nil)
        _items = [NSMutableArray arrayWithCapacity:10];

    NSMutableArray *pa = [NSMutableArray arrayWithCapacity:10];
    [pa addObjectsFromArray:[_prefs objectForKey:INFOKEY_PERSISTENT_APPS]];

    if(!pa || [pa count] == 0) {
        /* The default tiles: the file manager, the terminal and the daily
         * driver applications that are actually installed. */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *defaults[] = {
            @"/System/Library/CoreServices/Filer.app",
            @"/Applications/Utilities/Terminal.app",
            @"/Applications/TextEdit.app",
            @"/Applications/Calculator.app",
            @"/Applications/Preview.app",
            @"/Applications/Font Book.app",
            @"/Applications/Utilities/Screenshot.app",
            @"/Applications/Utilities/Activity Monitor.app",
            @"/Applications/Utilities/Disk Utility.app",
            @"/Applications/Utilities/Console.app",
            @"/Applications/Utilities/Keychain Access.app",
            @"/System/Library/CoreServices/Archive Utility.app",
            @"/System/Library/CoreServices/System Preferences.app",
        };
        for(int i = 0; i < (int)(sizeof(defaults) / sizeof(defaults[0])); i++) {
            if([fm fileExistsAtPath:defaults[i]])
                [pa addObject:dockTileData(defaults[i])];
        }
    }

    for(int i = 0; i < [pa count]; ++i) {
        NSDictionary *dict = [pa objectAtIndex:i];
        DockItem *di = [DockItem dockItemWithPath:CFURLString(dict)];
        [di setPersistent:YES];
        [_items addObject:di];
    }

    // FIXME: load persistent-other items

    NSString *specials[] = {@"Downloads",@"Trash"};
    for(int x = 0; x < 2; ++x) {
        NSString *bundle = [[NSBundle mainBundle] pathForResource:specials[x] ofType:@"app"];
        DockItem *di = [DockItem dockItemWithPath:bundle];
        [di setPersistent:YES];
        [_items addObject:di];
    }
}

-(void)pollMouse:(NSTimer *)timer {
    NSPoint p = [NSEvent mouseLocation];
    NSScreen *screen = [NSScreen mainScreen];
    NSSize screenSize = [screen frame].size;
    BOOL shouldShow = !_hidden;

    if(_autohide) {
        switch(_location) {
            case LOCATION_LEFT:
                shouldShow = _hidden ? (p.x <= 6) : (p.x <= _currentSize.width + 8);
                break;
            case LOCATION_RIGHT:
                shouldShow = _hidden ? (p.x >= screenSize.width - 6)
                                     : (p.x >= screenSize.width - _currentSize.width - 8);
                break;
            default:
                shouldShow = _hidden ? (p.y <= 6) : (p.y <= _currentSize.height + 8);
                break;
        }
        if(shouldShow == _hidden) {
            _hidden = !shouldShow;
            NSRect frame = [self positionWindowWithFrame:[_window frame]];
            [_window setFrame:frame display:YES];
        }
    }

    if(_magnification) {
        int hover = -1;

        if(!_hidden && NSPointInRect(p, [_window frame])) {
            NSArray *subviews = [[_window contentView] subviews];
            NSRect frame = [_window frame];
            NSPoint local = NSMakePoint(p.x - frame.origin.x, p.y - frame.origin.y);
            int itemIndex = 0;
            unsigned i;

            for(i = 0; i < [subviews count]; i++) {
                NSView *v = [subviews objectAtIndex:i];

                if(![v isKindOfClass:[DockItem class]])
                    continue;
                if(NSPointInRect(local, [v frame])) {
                    hover = itemIndex;
                    break;
                }
                itemIndex++;
            }
        }
        if(hover != _hoverIndex) {
            _hoverIndex = hover;
            [self relocate];
        }
    }
}

// FIXME: call this when _location changes
-(void)relocate {
    int maxItems = [self fitWindowToItems];
    NSRect frame = NSMakeRect(0, 0, _currentSize.width, _currentSize.height);
    if(_window == nil) {
        [self createWindowWithFrame:frame];
    } else {
        NSArray *subviews = [[[_window contentView] subviews] copy];
        for(NSView *view in subviews)
            [view removeFromSuperview];
        NSRect positioned = [self positionWindowWithFrame:frame];
        [_window setFrame:positioned display:NO];
        [[_window contentView] setFrame:NSMakeRect(0, 0, _currentSize.width, _currentSize.height)];
    }
    [self placeItemsInWindow:maxItems];
    [_window makeKeyAndOrderFront:nil];
    [_window display];
}

/* The system preferences changed: pick up the new icon size, position and
 * opacity and lay the Dock out again. */
-(void)preferencesChanged:(NSNotification *)note {
    NSDictionary *plist = [self readDockPlist];
    int pos;

    _tileSize = [[plist objectForKey:INFOKEY_TILESIZE] intValue];
    if(_tileSize < TILESIZE_MIN)
        _tileSize = [_prefs integerForKey:INFOKEY_TILESIZE];
    if(_tileSize < TILESIZE_MIN)
        _tileSize = 64;
    pos = [[plist objectForKey:INFOKEY_LOCATION] intValue];
    if(plist == nil)
        pos = [_prefs integerForKey:INFOKEY_LOCATION];
    _location = (Location)pos;
    _alpha = [[plist objectForKey:INFOKEY_OPACITY] floatValue];
    if(_alpha <= 0.0f)
        _alpha = 0.85;
    _autohide = [[plist objectForKey:INFOKEY_AUTOHIDE] boolValue];
    _magnification = [[plist objectForKey:INFOKEY_MAGNIFICATION] boolValue];

    [self relocate];
}

-(float)alpha {
    return _alpha;
}

@end

@implementation DockView
-(void)drawRect:(NSRect)rect {
    CGContextRef context = [[[self window] graphicsContext] graphicsPort];

    CGContextSetGrayStrokeColor(context, 0.666, [dock alpha]);
    CGContextSetGrayFillColor(context, 0.666, [dock alpha]);

    // round the corners
    float radius = RADIUS;
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, _frame.origin.x+radius, NSMaxY(_frame));
    CGContextAddArc(context, _frame.origin.x + _frame.size.width - radius,
        _frame.origin.y + _frame.size.height - radius, radius, 1.5708 /*radians*/,
        0 /*radians*/, YES);
    CGContextAddLineToPoint(context, _frame.origin.x + _frame.size.width,
        _frame.origin.y);
    CGContextAddArc(context, _frame.origin.x + _frame.size.width - radius,
        _frame.origin.y + radius, radius, 6.28319 /*radians*/, 4.71239 /*radians*/,
        YES);
    CGContextAddLineToPoint(context, _frame.origin.x, _frame.origin.y);
    CGContextAddArc(context, _frame.origin.x + radius, _frame.origin.y + radius,
        radius, 4.71239, 3.14159, YES);
    CGContextAddLineToPoint(context, _frame.origin.x,
        _frame.origin.y + _frame.size.height);
    CGContextAddArc(context, _frame.origin.x + radius, _frame.origin.y +
        _frame.size.height - radius, radius, 3.14159, 1.5708, YES);
    CGContextAddLineToPoint(context, _frame.origin.x, NSMaxY(_frame));
    CGContextClosePath(context);
    CGContextFillPath(context);

    // The tiles are subviews, but this view marks itself dirty at the end of
    // every draw and repaints the whole tray opaquely.  A tile only repaints
    // when it is itself dirty, so its artwork gets erased and never comes
    // back.  Composite the tile icons here, in the same pass as the tray.
    for(NSView *view in [self subviews]) {
        if([view isKindOfClass:[DockItem class]]) {
            [(DockItem *)view drawIconInContext:context];
        } else if([view isKindOfClass:[Divider class]]) {
            NSRect df = [view frame];
            CGContextSetRGBStrokeColor(context, 0.45, 0.45, 0.45, 0.85);
            CGContextSetLineWidth(context, 1.5);
            CGContextBeginPath(context);
            if(df.size.width > df.size.height) {
                CGContextMoveToPoint(context, df.origin.x + 4, df.origin.y + df.size.height/2);
                CGContextAddLineToPoint(context, df.origin.x + df.size.width - 4, df.origin.y + df.size.height/2);
            } else {
                CGContextMoveToPoint(context, df.origin.x + df.size.width/2, df.origin.y + 8);
                CGContextAddLineToPoint(context, df.origin.x + df.size.width/2, df.origin.y + df.size.height - 8);
            }
            CGContextStrokePath(context);
        }
    }

}
@end

@implementation Divider
-(void)drawRect:(NSRect)rect {
    // Divider is stroked directly by DockView's drawRect: in the tray pass.
}
@end
