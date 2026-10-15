/*
 * Copyright (C) 2024-2025 Zoe Knox <zoe@ravynsoft.com>
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

#import "SysPrefs.h"
#import <PreferencePanes/NSPreferencePane.h>


@interface PanePanelView : NSView {
    NSString *_title;
}
-(void)setTitle:(NSString *)inTitle;
-(NSString *)paneTitleValue;
-(void)drawRect:(NSRect)rect;
@end

@implementation PanePanelView

-(void)setTitle:(NSString *)inTitle { _title = [inTitle copy]; }

-(NSString *)paneTitleValue { return _title ? _title : @"Preferences"; }

-(void)drawRect:(NSRect)rect {
    NSGraphicsContext *context = [[self window] graphicsContext];
    if(context == nil)
        return;
    CGContextRef port = [context graphicsPort];
    NSSize size = [self frame].size;

    /* flat panel so the chosen pane reads as one surface under the icon grid */
    CGContextSetRGBFillColor(port, 0.93, 0.93, 0.95, 1.0);
    CGContextFillRect(port, NSMakeRect(0, 0, size.width, size.height));
    CGContextSetRGBStrokeColor(port, 0.62, 0.62, 0.66, 1.0);
    CGContextSetLineWidth(port, 1.0);
    CGContextAddRect(port, NSMakeRect(0.5, 0.5, size.width - 1, size.height - 1));
    CGContextStrokePath(port);

    /* title art via attributed string (Inter-Regular per repo text idiom) */
    NSFont *font = [NSFont fontWithName:@"Inter-Regular" size:18];
    if(font == nil)
        font = [NSFont systemFontOfSize:18];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjects:@[font, [NSColor blackColor]]
                                                        forKeys:@[NSFontAttributeName,
                                                                  NSForegroundColorAttributeName]];
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:[self paneTitleValue]
                                                             attributes:attributes];
    NSSize measured = [title size];
    float x = (size.width - measured.width)/2;
    if(x < 12)
        x = 12;
    [title drawInRect:NSMakeRect(x, size.height - 46, measured.width + 24, 30)];
}

@end

#define PANE_ICON_BOX 72

/* NSButton keeps its artwork in an NSCell and this tree never paints
 * cell-based views, so a button holding setImage:/setTitle: drew nothing at
 * all -- that was the invisible Preference pane grid.  This cell composites
 * the icon and the label itself, using the graphicsPort + drawInRect: idiom
 * which does work on this tree (Filer rows, Dock tiles, PanePanelView). */
@interface PaneButtonCell : NSButtonCell {
    NSImage *_iconImage;
}
-(void)setImage:(NSImage *)image;
-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
@end

@implementation PaneButtonCell

/* NSCell has no public -image on this tree, so the button's image (stored via
 * -setImage: on the button) is reached through the cell's NSAttributedCell
 * family; hold a direct reference set alongside -setImage: below. */
-(NSImage *)image { return _iconImage; }
-(void)setImage:(NSImage *)image { _iconImage = image; }

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    CGContextRef port = [[[controlView window] graphicsContext] graphicsPort];
    if(port == NULL)
        return;
    NSImage *img = [self image];
    float w = cellFrame.size.width;
    float iconBox = PANE_ICON_BOX;
    float x = cellFrame.origin.x + (w - iconBox)/2;
    if(img != nil)
        [img drawInRect:NSMakeRect(x, cellFrame.origin.y + 24, iconBox, iconBox)
               fromRect:NSZeroRect
              operation:NSCompositingOperationSourceOver
               fraction:1.0];

    NSString *title = [self title];
    if(title == nil)
        return;
    NSFont *titleFont = [self font];
    if(titleFont == nil)
        titleFont = [NSFont fontWithName:@"Inter-Regular" size:11];
    NSDictionary *attributes = (titleFont != nil)
        ? [NSDictionary dictionaryWithObjects:@[titleFont, [NSColor blackColor]]
            forKeys:@[NSFontAttributeName, NSForegroundColorAttributeName]]
        : [NSDictionary dictionaryWithObjects:@[[NSColor blackColor]]
            forKeys:@[NSForegroundColorAttributeName]];
    NSAttributedString *line = [[NSAttributedString alloc] initWithString:title
                                                              attributes:attributes];
    NSSize measured = [line size];
    float tx = cellFrame.origin.x + (w - measured.width)/2;
    if(tx < cellFrame.origin.x + 2)
        tx = cellFrame.origin.x + 2;
    [line drawInRect:NSMakeRect(tx, cellFrame.origin.y + 4, measured.width + 4, 20)];
}

@end
@implementation SystemPreferences

const float windowWidth = 668; // Apple uses a fixed width and grows vertically
const float size = 96; // icon & label container size
const float spacer = 8; // icon spacing


-(void)applicationWillFinishLaunching:(NSNotification *)note {
    doubleClickInterval = [[NSDisplay currentDisplay] doubleClickInterval];
    lastClickTime = 0;
    lastClickObject = nil;
    clickCount = 0;

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *displayName = [[mainBundle infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSRect rect = NSMakeRect(100, 100, windowWidth, 200);
    window = [[NSWindow alloc] initWithContentRect:rect
                                         styleMask:NSTitledWindowMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setTitle:displayName];

    panes = [NSMutableArray new];
    font = [NSFont systemFontOfSize:15];

    [self loadPanes];
    [window makeKeyAndOrderFront:self];
}

-(void)loadPanes {
    NSArray *dirs = @[@"/System/Library/PreferencePanes", @"/Library/PreferencePanes"];
    NSFileManager *fm = [NSFileManager defaultManager];

    [panes removeAllObjects]; 

    float x = 0, y = 0;
    for(int d = 0; d < [dirs count]; ++d) {
        NSString *dirPath = [dirs objectAtIndex:d];
        NSArray *files = [fm contentsOfDirectoryAtPath:dirPath error:NULL];

        for(int i = 0; i < [files count]; ++i) {
            NSString *path = [dirPath stringByAppendingPathComponent:[files objectAtIndex:i]];
            if([path hasSuffix:@".prefPane"]) {
                NSBundle *b = [NSBundle bundleWithPath:path];
                if(b) {
                    [panes addObject:b];
                    NSView *item = [self loadPaneIcon:b]; 
                    [(NSButton *)item setTag:[panes indexOfObject:b]];
                    [item setFrameOrigin:NSMakePoint(x, y)];
                    x += size;
                    x += spacer;
                    if(x > (windowWidth - size - spacer)) {
                        x = 0;
                        y += size;
                        y += spacer;
                    }
                    [[window contentView] addSubview:item];
                } else
                    NSLog(@"error loading prefPane %@", path);
            }
        }
    }
}


-(NSView *)loadPaneIcon:(NSBundle *)b {
        NSString *label = [b objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if(!label)
            label = [b objectForInfoDictionaryKey:@"CFBundleName"];

        NSString *rsc = [b resourcePath];
        NSString *exe = [b executablePath];

        NSString *iconFile = [b objectForInfoDictionaryKey:@"CFBundleIconFile"];
        if(!iconFile)
            iconFile = [b objectForInfoDictionaryKey:@"NSIcon"];
        NSString *iconPath = [NSString stringWithFormat:@"%@/%@",rsc,iconFile];

        NSRect rect = NSMakeRect(0, 0, size, size);
        NSButton *container = [[NSButton alloc] initWithFrame:rect];
        [container setBezeled:NO];
        [container setBordered:NO];
        [container setImagePosition:NSImageAbove];
        [container setAction:@selector(iconClicked:)];
        /* See PaneButtonCell above: this tree paints no cell-based view, so the
         * button's own cell is swapped for one that composites itself. */
        PaneButtonCell *cell = [[PaneButtonCell alloc] initTextCell:@""];
        [container setCell:cell];

        NSImage *img = [[NSImage alloc] initWithContentsOfFile:iconPath];
        [container setImage:img];
        [cell setImage:img];
        [img setScalesWhenResized:YES];
        [[container image] setSize:NSMakeSize(size - 24, size - 24)];

        [container setFont:font];
        [container setTitle:label];

        return container;
}

// This is a little hacky but it works :)
-(void)iconClicked:(NSButton *)button {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    NSTimeInterval now = ts.tv_sec + ts.tv_nsec / 1000000000;

    if(button != lastClickObject) {
        clickCount = 1;
        lastClickTime = now;
        lastClickObject = button;
        return;
    }

    if((now - lastClickTime) < doubleClickInterval)
        clickCount++;
    else
        clickCount = 1;
    lastClickTime = now;
    lastClickObject = button;

    if(clickCount >= 2) {
        [self openPane:[button tag]];
        clickCount = 0;
    }
}

-(void)openPane:(int)tag {
    if(tag < 0 || tag >= [panes count])
        return;
    NSBundle *bundle = [panes objectAtIndex:tag];
    NSPreferencePane *pane = [[NSPreferencePane alloc] initWithBundle:bundle];
    [pane setWindow:window];
    NSString *label = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if(!label)
        label = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if(!label)
        label = @"Preferences";
    NSView *main = [pane loadMainView];
    if(main == nil)
        main = [self panePanelForLabel:label];
    if(main != nil){
        NSRect content = [[window contentView] frame];
        NSSize panelSize = [main frame].size;
        float x = (content.size.width - panelSize.width)/2;
        if(x < 0)
            x = 0;
        [main setFrameOrigin:NSMakePoint(x, content.size.height - panelSize.height - 48)];
        [[window contentView] addSubview:main];
        [[window contentView] setNeedsDisplay:YES];
    }
}

-(NSView *)panePanelForLabel:(NSString *)label {
    PanePanelView *panel = [PanePanelView alloc];
    [panel setTitle:label];
    [panel initWithFrame:NSMakeRect(0, 0, 360, 120)];
    return panel;
}

@end
