#import "CapacityBarView.h"

@implementation CapacityBarView
@synthesize totalBytes, usedBytes;

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect b = [self bounds];
    [[NSColor lightGrayColor] setFill];
    NSRectFill(b);
    if (totalBytes > 0) {
        double frac = (double)usedBytes / (double)totalBytes;
        if (frac < 0) frac = 0;
        if (frac > 1) frac = 1;
        NSRect usedRect = NSMakeRect(b.origin.x, b.origin.y, b.size.width * frac, b.size.height);
        [[NSColor blueColor] setFill];
        NSRectFill(usedRect);
    }
    [[NSColor darkGrayColor] setStroke];
    NSBezierPath *p = [NSBezierPath bezierPathWithRect:b];
    [p stroke];
}

- (BOOL)isOpaque { return YES; }
@end