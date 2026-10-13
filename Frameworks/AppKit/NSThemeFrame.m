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

/* defined in NSWindow.m */
void CGNativeBorderFrameWidthsForStyle(unsigned styleMask, CGFloat *top, CGFloat *left, CGFloat *bottom, CGFloat *right);

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

    return self;
}

-(BOOL)isOpaque {
   return YES;
}

-(NSView *)hitTest:(NSPoint)point {
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
    NSRect bounds = [NSWindow contentRectForFrameRect:[self bounds]
        styleMask:[[self window] styleMask]];
    float cheatSheet = 0;

    switch(_borderType){
        case NSNoBorder:
            break;
            
        case NSWindowToolTipBorderType:
            [[NSColor blackColor] setStroke];
            NSFrameRect(bounds);
            bounds = NSInsetRect(bounds, 1, 1);
            cheatSheet = 1;
            break;
                
        case NSWindowSheetBorderType:
            NSDrawButton(bounds,bounds);
            bounds = NSInsetRect(bounds, 2, 2);
            cheatSheet = 2;
            break;
    }

    NSWindow *window = [self window];
    O2Context *_context = [[window graphicsContext] graphicsPort];
    CGFloat r, g, b, a;
    [[[self window] backgroundColor] getRed:&r green:&g blue:&b alpha:&a];
    O2ContextSetRGBStrokeColor(_context, r, g, b, a);
    O2ContextSetRGBFillColor(_context, r, g, b, a);
    O2ContextFillRect(_context, bounds);

    if([[self window] styleMask] == NSBorderlessWindowMask)
        return;
    
    if([[self window] isSheet])
        bounds.size.height += cheatSheet;

    O2ContextSetGrayStrokeColor(_context, 0.8, 1);
    O2ContextSetGrayFillColor(_context, 0.8, 1);

    // let's round these corners
    float radius = NSWindowCornerRadius;
    O2ContextBeginPath(_context);
    O2ContextMoveToPoint(_context, _frame.origin.x+radius, NSMaxY(_frame));
    O2ContextAddArc(_context, _frame.origin.x + _frame.size.width - radius,
        _frame.origin.y + _frame.size.height - radius, radius, 1.5708 /*radians*/,
        0 /*radians*/, YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x + _frame.size.width,
        _frame.origin.y);
    O2ContextAddArc(_context, _frame.origin.x + _frame.size.width - radius,
        _frame.origin.y + radius, radius, 6.28319 /*radians*/, 4.71239 /*radians*/,
        YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x, _frame.origin.y);
    O2ContextAddArc(_context, _frame.origin.x + radius, _frame.origin.y + radius,
        radius, 4.71239, 3.14159, YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x,
        _frame.origin.y + _frame.size.height);
    O2ContextAddArc(_context, _frame.origin.x + radius, _frame.origin.y +
        _frame.size.height - radius, radius, 3.14159, 1.5708, YES);
    O2ContextAddLineToPoint(_context, _frame.origin.x, NSMaxY(_frame));
    O2ContextClosePath(_context);
    O2ContextFillPath(_context);

    // window controls
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

    // Draw traffic light controls (vector circles)
    // Red (close)
    O2ContextSetRGBFillColor(_context, 0.99, 0.38, 0.35, 1.0);
    O2ContextFillEllipseInRect(_context, _closeButtonRect);
    // Yellow (mini)
    O2ContextSetRGBFillColor(_context, 0.99, 0.77, 0.19, 1.0);
    O2ContextFillEllipseInRect(_context, _miniButtonRect);
    // Green (zoom)
    O2ContextSetRGBFillColor(_context, 0.17, 0.78, 0.28, 1.0);
    O2ContextFillEllipseInRect(_context, _zoomButtonRect);

    /* Title bar text drawing bypassed to avoid NSStringDrawer autorelease pool crash */
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
