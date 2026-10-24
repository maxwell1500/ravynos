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

#import <AppKit/AppKit.h>
#import <CoreGraphics/CGWindowLevel.h>
#import "Dock.h"
#import "DesktopWindow.h"

@interface DesktopView : NSImageView
@end

@implementation DesktopView
// Block any clicks on the wallpaper so it doesn't flicker on redraw
// This should just activate Finder eventually
-(void)mouseDown:(NSEvent *)event {
    NSLog(@"clickity click");
}

-(void)drawRect:(NSRect)dirtyRect {
    NSImage *image = [self image];
    NSRect bounds = [self bounds];

    if (image == nil || bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        [[NSColor blackColor] setFill];
        NSRectFill(dirtyRect);
        return;
    }

    NSSize imageSize = [image size];
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        [[NSColor blackColor] setFill];
        NSRectFill(dirtyRect);
        return;
    }

    float scaleX = bounds.size.width / imageSize.width;
    float scaleY = bounds.size.height / imageSize.height;
    float scale = (scaleX > scaleY) ? scaleX : scaleY;

    NSSize scaledSize = NSMakeSize(imageSize.width * scale, imageSize.height * scale);
    NSRect destination = NSMakeRect(bounds.origin.x + (bounds.size.width - scaledSize.width) / 2.0,
                                    bounds.origin.y + (bounds.size.height - scaledSize.height) / 2.0,
                                    scaledSize.width, scaledSize.height);

    [image drawInRect:destination fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
}
@end

@implementation DesktopWindow
- initForScreen:(NSScreen *)screen {
    _screen = screen;
    NSRect frame = [screen frame];

    self = [super initWithContentRect:frame
                            styleMask:NSBorderlessWindowMask
                              backing:NSBackingStoreBuffered
                                defer:NO
                               screen:screen];
    if(!self) return nil;
    [self setLevel:kCGDesktopWindowLevelKey];
    [self setMovableByWindowBackground:NO];

    frame.origin = NSZeroPoint;
    view = [[DesktopView alloc] initWithFrame:frame];
    [view setAutoresizingMask:0];
    [view setImageScaling:NSImageScaleAxesIndependently];
    [view setImageAlignment:NSImageAlignCenter];
    [_contentView addSubview:view];
    [self updateBackground];

    return self;
}

-(BOOL)acceptsFirstResponder {
    return NO;
}

-(BOOL)refusesFirstResponder {
    return YES;
}

-(BOOL)canBecomeKeyWindow {
    return NO;
}

-(BOOL)canBecomeMainWindow {
    return NO;
}

- (void)updateBackground {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSDictionary *dict = [prefs objectForKey:INFOKEY_WALLPAPER];
    _wallpaperPath = [dict objectForKey:@"NSMainScreen"]; // FIXME: use CGDisplayID from NSScreen deviceDescription
    if(!_wallpaperPath)
        _wallpaperPath = @"/System/Library/Desktop Pictures/ravynos_dunes.png";

    NSImage *image = [[NSImage alloc] initWithContentsOfFile:_wallpaperPath];
    NSLog(@"[DesktopWindow] wallpaper %@ image %@ size %dx%d",
          _wallpaperPath, image ? @"loaded" : @"nil",
          (int)[image size].width, (int)[image size].height);
    [image setScalesWhenResized:YES];
    [view setImage:image];
    [view setNeedsDisplay:YES];
}

- (NSString *)wallpaperPath {
    return _wallpaperPath;
}

- (NSScreen *)screen {
    return _screen;
}

- (NSDictionary *)properties {
    return nil; // FIXME
}

// Don't let NSWindow constrain us to the visibleFrame, because it excludes the menu bar!
-(NSRect)constrainFrameRect:(NSRect)rect toScreen:(NSScreen *)screen {
    return rect;
}

@end

