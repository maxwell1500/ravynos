/*
 * Copyright (c) 2006-2007 Christopher J. W. Lloyd
 * Copyright (C) 2024 Zoe Knox <zoe@ravynsoft.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

#import <AppKit/NSThemeFrame.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSWindow-Private.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSToolbarView.h>
#import <AppKit/NSAttributedString.h>
#import <Onyx2D/O2Context.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSDictionary.h>
#import <AppKit/NSApplication.h>

/* defined in NSWindow.m */
void CGNativeBorderFrameWidthsForStyle(unsigned styleMask, CGFloat *top, CGFloat *left, CGFloat *bottom, CGFloat *right);

/* Appearance comes from /Library/Preferences/.GlobalPreferences.plist, the
 * same file the Appearance pane writes.  Cached per process and invalidated
 * when a CODE_PREFS_CHANGED broadcast arrives, so switching Light/Dark
 * repaints every open window without a relaunch. */
static int sDarkMode = -1;

static void NSThemeFrameInvalidateAppearance(void) {
    sDarkMode = -1;
}

static BOOL NSThemeFrameDarkMode(void) {
    if(sDarkMode < 0) {
        NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:
            @"/Library/Preferences/.GlobalPreferences.plist"];
        NSString *style=[prefs objectForKey:@"AppleInterfaceStyle"];

        sDarkMode = (style != nil && [style isEqualToString:@"Dark"]) ? 1 : 0;
    }
    return sDarkMode == 1;
}

static void buildWindowFramePath(O2Context *context, NSRect frame, float radius) {
    O2ContextBeginPath(context);
    O2ContextMoveToPoint(context, frame.origin.x + radius, NSMaxY(frame));
    O2ContextAddArc(context, frame.origin.x + frame.size.width - radius,
        frame.origin.y + frame.size.height - radius, radius, 1.5708, 0, YES);
    O2ContextAddLineToPoint(context, frame.origin.x + frame.size.width, frame.origin.y);
    O2ContextAddArc(context, frame.origin.x + frame.size.width - radius,
        frame.origin.y + radius, radius, 6.28319, 4.71239, YES);
    O2ContextAddLineToPoint(context, frame.origin.x, frame.origin.y);
    O2ContextAddArc(context, frame.origin.x + radius, frame.origin.y + radius,
        radius, 4.71239, 3.14159, YES);
    O2ContextAddLineToPoint(context, frame.origin.x, frame.origin.y + frame.size.height);
    O2ContextAddArc(context, frame.origin.x + radius,
        frame.origin.y + frame.size.height - radius, radius, 3.14159, 1.5708, YES);
    O2ContextAddLineToPoint(context, frame.origin.x, NSMaxY(frame));
    O2ContextClosePath(context);
}

@implementation NSThemeFrame

// all measurements in pixels
const float NSWindowTitleHeight = 32;
const float NSWindowEdgePad = 2;
const float NSWindowCornerRadius = 8;
const float NSWindowControlDiameter = 14;
const float NSWindowControlSpacing = 10;

static O2Image *wsClose, *wsCloseHover, *wsMini, *wsMiniHover;
static O2Image *wsZoom, *wsZoomUp, *wsZoomDown;

-initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    pointer = NSZeroPoint;

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(_appearanceChanged:)
        name:NSApplicationPreferencesChangedNotification object:nil];

    return self;
}

-(void)_appearanceChanged:(NSNotification *)note {
    NSThemeFrameInvalidateAppearance();
    [self setNeedsDisplay:YES];
}

-(BOOL)isOpaque {
   return YES;
}

-(void)_updateControlRects {
    CGRect button = NSMakeRect(NSWindowControlSpacing,
        _frame.size.height - NSWindowTitleHeight / 2 - NSWindowControlDiameter / 2,
        NSWindowControlDiameter, NSWindowControlDiameter);
    _closeButtonRect = button;
    button.origin.x += NSWindowControlSpacing + NSWindowControlDiameter;
    _miniButtonRect = button;
    button.origin.x += NSWindowControlSpacing + NSWindowControlDiameter;
    _zoomButtonRect = button;

    controls = NSMakeRect(_closeButtonRect.origin.x, _closeButtonRect.origin.y,
            3*NSWindowControlSpacing + 3*NSWindowControlDiameter, NSWindowControlDiameter);
}

-(NSView *)hitTest:(NSPoint)point {
    [self _updateControlRects];
    static BOOL inRect = NO;

    pointer = point;
    if(NSPointInRect(pointer, controls)) {
        if(!inRect) {
            [self setNeedsDisplay:YES]; // highlight controls if mouse has gone into them
            inRect = YES;
        }
    } else if(inRect) { // we left the control zone
            [self setNeedsDisplay:YES];
            inRect = NO;
    }

    return [super hitTest:point];
}

-(NSWindowBorderType)windowBorderType {
   return _borderType;
}

-(void)setWindowBorderType:(NSWindowBorderType)borderType {
   _borderType = borderType;
   [self setNeedsDisplay:YES];
}

-(void)drawRect:(NSRect)rect {
    NSWindow *window = [self window];
    O2Context *_context = [[window graphicsContext] graphicsPort];

    if([[self window] styleMask] == NSBorderlessWindowMask) {
        CGFloat r, g, b, a;
        [[[self window] backgroundColor] getRed:&r green:&g blue:&b alpha:&a];
        O2ContextSetRGBFillColor(_context, r, g, b, a);
        O2ContextFillRect(_context, [self bounds]);
        return;
    }

    // 1. Draw outer rounded window frame & titlebar background
    BOOL active = [[self window] isKeyWindow] || [[self window] isMainWindow];
    BOOL dark = NSThemeFrameDarkMode();
    float radius = NSWindowCornerRadius;
    O2ContextSetGrayFillColor(_context,
        dark ? (active ? 0.18f : 0.24f) : (active ? 0.86f : 0.925f), 1.0);
    buildWindowFramePath(_context, _frame, radius);
    O2ContextFillPath(_context);
    O2ContextSetGrayStrokeColor(_context,
        dark ? (active ? 0.10f : 0.16f) : (active ? 0.63f : 0.78f), 1.0);
    O2ContextSetLineWidth(_context, 1.0);
    buildWindowFramePath(_context, _frame, radius);
    O2ContextStrokePath(_context);

    // 2. Fill content bounds with window background color
    NSRect bounds = [NSWindow contentRectForFrameRect:[self bounds]
        styleMask:[[self window] styleMask]];
    CGFloat r, g, b, a;
    [[[self window] backgroundColor] getRed:&r green:&g blue:&b alpha:&a];
    O2ContextSetRGBFillColor(_context, r, g, b, a);
    O2ContextFillRect(_context, bounds);

    // 3. Stroke 1px horizontal separator line between titlebar and content
    O2ContextSetGrayStrokeColor(_context, dark ? 0.30f : 0.70, 1.0);
    O2ContextSetLineWidth(_context, 1.0);
    O2ContextBeginPath(_context);
    O2ContextMoveToPoint(_context, 0, NSMaxY(bounds));
    O2ContextAddLineToPoint(_context, _frame.size.width, NSMaxY(bounds));
    O2ContextStrokePath(_context);

    // 4. Traffic light window controls
    [self _updateControlRects];

    // Red (close: #FF5F56)
    O2ContextSetRGBFillColor(_context, active ? 1.0f : 0.85f, active ? 0.373f : 0.85f, active ? 0.337f : 0.85f, 1.0);
    O2ContextFillEllipseInRect(_context, _closeButtonRect);
    O2ContextSetRGBStrokeColor(_context, active ? 0.89f : 0.75f, active ? 0.20f : 0.75f, active ? 0.18f : 0.75f, 1.0);
    O2ContextStrokeEllipseInRect(_context, _closeButtonRect);

    // Yellow (mini: #FFBD2E)
    O2ContextSetRGBFillColor(_context, active ? 1.0f : 0.85f, active ? 0.741f : 0.85f, active ? 0.180f : 0.85f, 1.0);
    O2ContextFillEllipseInRect(_context, _miniButtonRect);
    O2ContextSetRGBStrokeColor(_context, active ? 0.88f : 0.75f, active ? 0.60f : 0.75f, active ? 0.10f : 0.75f, 1.0);
    O2ContextStrokeEllipseInRect(_context, _miniButtonRect);

    // Green (zoom: #27C93F)
    O2ContextSetRGBFillColor(_context, active ? 0.153f : 0.85f, active ? 0.788f : 0.85f, active ? 0.247f : 0.85f, 1.0);
    O2ContextFillEllipseInRect(_context, _zoomButtonRect);
    O2ContextSetRGBStrokeColor(_context, active ? 0.12f : 0.75f, active ? 0.65f : 0.75f, active ? 0.20f : 0.75f, 1.0);
    O2ContextStrokeEllipseInRect(_context, _zoomButtonRect);

    // 4b. Unsaved-changes dot inside the close button
    if([[self window] isDocumentEdited]) {
        O2ContextSetRGBFillColor(_context, 0.25f, 0.05f, 0.05f, 1.0f);
        O2ContextFillEllipseInRect(_context,
            NSInsetRect(_closeButtonRect, 4.5f, 4.5f));
    }

    // 5. Window title text
    NSString *title = [[self window] title];
    if([title length] > 0) {
        NSFont *font = [NSFont boldSystemFontOfSize:13] ?: [NSFont systemFontOfSize:13];
        if(font != nil) {
            NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                [NSColor colorWithCalibratedWhite:
                    (dark ? (active ? 0.94f : 0.65f) : (active ? 0.067f : 0.467f))
                    alpha:1.0], NSForegroundColorAttributeName,
                nil];
            NSSize titleSize = [title sizeWithAttributes:attrs];
            float tx = (_frame.size.width - titleSize.width) / 2.0;
            float minX = NSMaxX(_zoomButtonRect) + 12.0;
            if(tx < minX) tx = minX;
            float ty = _frame.size.height - NSWindowTitleHeight / 2.0 - titleSize.height / 2.0 + 1.0;
            [title drawAtPoint:NSMakePoint(tx, ty) withAttributes:attrs];
        }
    }
}

-(void)resizeSubviewsWithOldSize:(NSSize)oldSize {
   NSToolbarView *toolbarView=nil;
   NSView *contentView=nil;
   
// tile the subviews, when/if we add titlebars and such do it here
   for(NSView *view in _subviews){
    if([view isKindOfClass:[NSToolbarView class]])
     toolbarView=(NSToolbarView *)view;
    else
     contentView=view;
   }
   
   NSRect toolbarFrame=(toolbarView!=nil)?[toolbarView frame]:NSZeroRect;
   NSRect contentFrame=[[[self window] class] contentRectForFrameRect:[self bounds] styleMask:[[self window] styleMask]];
   toolbarFrame.origin.y=NSMaxY(contentFrame)-toolbarFrame.size.height;
   toolbarFrame.origin.x=contentFrame.origin.x;
   toolbarFrame.size.width=contentFrame.size.width;
   
   [toolbarView setFrame:toolbarFrame];
   [toolbarView layoutViews];
   
   contentFrame.size.height-=toolbarFrame.size.height;
   [contentView setFrame:contentFrame];
}

-(void)mouseDown:(NSEvent *)event {
    CGFloat top, left, right, bottom;
    CGNativeBorderFrameWidthsForStyle([[self window] styleMask], &top, &left, &bottom, &right);
    [self _updateControlRects];
    NSPoint pos = [event locationInWindow];

    if(NSPointInRect(pos, _closeButtonRect))
        [[self window] performClose:self];
    else if(NSPointInRect(pos, _miniButtonRect))
        [[self window] performMiniaturize:self];
    else if(NSPointInRect(pos, _zoomButtonRect))
        [[self window] performZoom:self];
    else if(pos.y > (NSMaxY(_frame) - top)) // in titlebar?
        [[self window] requestMove:event];
    else if([[self window] isMovableByWindowBackground])
        [[self window] requestMove:event];
}

@end
