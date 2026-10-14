/*
 * Copyright (C) 2022-2024 Zoe Knox <zoe@pixin.net>
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

#include <pthread.h>
#import <AppKit/AppKit.h>
#import "desktop.h"

extern pthread_mutex_t mtx;

@implementation MenuBarWindow
- initWithFrame:(NSRect)frame {
    frame.origin.x = 0;
    frame.origin.y = frame.size.height - menuBarHeight;
    frame.size.height = menuBarHeight;
    self = [self initWithContentRect:frame styleMask:NSBorderlessWindowMask
        backing:NSBackingStoreBuffered defer:NO];
    [self setMovableByWindowBackground:NO];
    [self setLevel:kCGMainMenuWindowLevelKey];

    float mainWidth = frame.size.width * 0.65;
    float extraWidth = frame.size.width - mainWidth;    clockView = [[ClockView alloc] initWithFrame:frame];    NSSize clockSize = [clockView size];    menuView = [[MenuView alloc] initWithFrame:
	NSMakeRect(0, 0, mainWidth, menuBarHeight)];    extrasView = [[ExtrasView alloc]
	initWithFrame:NSMakeRect(frame.size.width - extraWidth, 0,
		extraWidth - clockSize.width, menuBarHeight)];

    menuDict = [NSMutableDictionary new];    [_contentView addSubview:menuView];
    [_contentView addSubview:extrasView];
    [_contentView addSubview:clockView];
    [_contentView setAutoresizingMask:0];

    [self setAllowsToolTipsWhenApplicationIsInactive:YES];

    fprintf(stderr,"[SUI] mbw-up frame=%d,%d %dx%d level=%d num=%d\n",
        (int)[self frame].origin.x, (int)[self frame].origin.y,
        (int)[self frame].size.width, (int)[self frame].size.height,
        (int)[self level], (int)[self windowNumber]);
    return self;
}

/* TEMP: does an event reach this window at all, and where does AppKit think
 * the click was?  Integer formats only: this libc's printf does not implement
 * %f/%g and prints <UNSUPPORTED-CONVERSION> instead. */
-(void)sendEvent:(NSEvent *)event {
        (int)[event type], (int)[event locationInWindow].x,
        (int)[event locationInWindow].y, (int)[self windowNumber]);
    [super sendEvent:event];
}

- (NSMenu *)menuForApp:(NSString *)bundleID {
    return [menuDict objectForKey:bundleID];
}

- (void)setMenu:(NSMenu *)menu forApp:(NSString *)bundleID {
    [menuDict setObject:menu forKey:bundleID];

    /* We don't get menus until after the app registers its mach ports with WS,
     * so it can be the active app with empty menus. Then it should send us the
     * menu dict, and we can display it
     */
    if([activeApp isEqualToString:bundleID]) {
        [menuView setMenu:menu];
        [menuView setNeedsDisplay:YES];
    }
}

- (void)removeMenuForApp:(NSString *)bundleID {
    if([bundleID isEqualToString:activeApp]) {
        [menuView setMenu:nil];
        [menuView setNeedsDisplay:YES];
        activeApp = nil;
    }
    [menuDict removeObjectForKey:bundleID];
}

- (void)activateApp:(NSString *)bundleID {
    activeApp = bundleID;
    NSMenu *menu = [self menuForApp:bundleID];
    [menuView setMenu:menu];
    [menuView setNeedsDisplay:YES];
}

- (void)addRecentItem:(NSURL *)itemURL {
    [menuView addRecentItem:itemURL];
}

- (void)addStatusItem:(NSStatusItem *)item pid:(unsigned int)pid {
    [extrasView addStatusItem:item pid:pid];
}

- (void)removeStatusItemsForPID:(unsigned int)pid {
    [extrasView removeStatusItemsForPID:pid];
}


// intercept these - we don't want this app to become activated or deactivated
-(void)platformWindowActivated:(CGWindow *)window displayIfNeeded:(BOOL)displayIfNeeded {
    // do nothing
}

-(void)platformWindowDeactivated:(CGWindow *)window checkForAppDeactivation:(BOOL)checkForAppDeactivation {
    // do nothing
}

-(NSEvent *)nextEventMatchingMask:(unsigned int)mask {
    return [self nextEventMatchingMask:mask untilDate:[NSDate distantFuture]
                                inMode:NSEventTrackingRunLoopMode dequeue:YES];
}

// Don't let NSWindow constrain us to the visibleFrame, because it excludes the menu bar!
-(NSRect)constrainFrameRect:(NSRect)rect toScreen:(NSScreen *)screen {
    return rect;
}
@end

