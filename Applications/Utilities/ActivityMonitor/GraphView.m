#import "GraphView.h"

@implementation GraphView
@synthesize userHistory, systemHistory, memHistory, netHistory, mode, summary;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        userHistory = [NSMutableArray array];
        systemHistory = [NSMutableArray array];
        memHistory = [NSMutableArray array];
        netHistory = [NSMutableArray array];
        mode = 0;
    }
    return self;
}

- (void)addSampleUser:(double)u system:(double)s memoryPressure:(double)m {
    [self addSampleUser:u system:s memoryPressure:m netKBps:0];
}

- (void)addSampleUser:(double)u system:(double)s memoryPressure:(double)m netKBps:(double)net {
    [userHistory addObject:@(u)];
    [systemHistory addObject:@(s)];
    [memHistory addObject:@(m)];
    [netHistory addObject:@(net)];
    while ([userHistory count] > 60) [userHistory removeObjectAtIndex:0];
    while ([systemHistory count] > 60) [systemHistory removeObjectAtIndex:0];
    while ([memHistory count] > 60) [memHistory removeObjectAtIndex:0];
    while ([netHistory count] > 60) [netHistory removeObjectAtIndex:0];
    [self setNeedsDisplay:YES];
}

- (void)setMode:(int)newMode {
    mode = newMode;
    [self setNeedsDisplay:YES];
}

- (void)drawLineHistory:(NSArray *)history maximum:(double)maxValue colour:(NSColor *)colour {
    CGFloat w = [self bounds].size.width;
    CGFloat h = [self bounds].size.height;
    int count = (int)[history count];
    NSBezierPath *path;

    if (count < 2 || maxValue <= 0)
        return;
    path = [NSBezierPath bezierPath];
    for (int i = 0; i < count; i++) {
        double v = [[history objectAtIndex:i] doubleValue];
        CGFloat x = w * (CGFloat)i / 60.0;
        CGFloat y = h * (CGFloat)(v / maxValue);

        if (y > h) y = h;
        if (i == 0) [path moveToPoint:NSMakePoint(x, y)];
        else [path lineToPoint:NSMakePoint(x, y)];
    }
    [colour set];
    [path setLineWidth:2.0];
    [path stroke];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor blackColor] set];
    NSRectFill(dirtyRect);

    CGFloat w = [self bounds].size.width;
    CGFloat h = [self bounds].size.height;
    int n = (int)[userHistory count];
    NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:11],
                             NSForegroundColorAttributeName: [NSColor whiteColor] };

    if (summary != nil)
        [summary drawAtPoint:NSMakePoint(8, h - 18) withAttributes:attrs];

    if (mode == 1) {          /* Memory pressure */
        [self drawLineHistory:memHistory maximum:100.0 colour:[NSColor cyanColor]];
        return;
    }
    if (mode == 3) {          /* Network KB/s */
        double peak = 1.0;
        for (NSNumber *v in netHistory) if ([v doubleValue] > peak) peak = [v doubleValue];
        [self drawLineHistory:netHistory maximum:peak colour:[NSColor greenColor]];
        return;
    }
    if (mode == 2) {          /* Disk: summary only, no history series */
        return;
    }

    if (n < 2) return;

    // CPU stacked chart (left 70%)
    CGFloat chartW = w * 0.7;
    CGFloat xStep = chartW / 60.0;
    // grid
    [[NSColor darkGrayColor] set];
    for (int i = 0; i <= 4; i++) {
        CGFloat y = h * i / 4.0;
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(0, y)];
        [p lineToPoint:NSMakePoint(chartW, y)];
        [p stroke];
    }
    // system (bottom) + user (top)
    for (int i = 1; i < n; i++) {
        double u0 = [[userHistory objectAtIndex:i-1] doubleValue];
        double s0 = [[systemHistory objectAtIndex:i-1] doubleValue];
        double u1 = [[userHistory objectAtIndex:i] doubleValue];
        double s1 = [[systemHistory objectAtIndex:i] doubleValue];
        // system band
        [[NSColor orangeColor] set];
        NSBezierPath *ps = [NSBezierPath bezierPath];
        [ps moveToPoint:NSMakePoint((i-1)*xStep, 0)];
        [ps lineToPoint:NSMakePoint((i-1)*xStep, h * (s0/100.0))];
        [ps lineToPoint:NSMakePoint(i*xStep, h * (s1/100.0))];
        [ps lineToPoint:NSMakePoint(i*xStep, 0)];
        [ps closePath];
        [ps fill];
        // user band on top of system
        [[NSColor greenColor] set];
        NSBezierPath *pu = [NSBezierPath bezierPath];
        [pu moveToPoint:NSMakePoint((i-1)*xStep, h*(s0/100.0))];
        [pu lineToPoint:NSMakePoint((i-1)*xStep, h*((s0+u0)/100.0))];
        [pu lineToPoint:NSMakePoint(i*xStep, h*((s1+u1)/100.0))];
        [pu lineToPoint:NSMakePoint(i*xStep, h*(s1/100.0))];
        [pu closePath];
        [pu fill];
    }
    // labels
    NSDictionary *chartAttrs = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSFontAttributeName: [NSFont systemFontOfSize:10]};
    [@"CPU" drawAtPoint:NSMakePoint(4, h-14) withAttributes:chartAttrs];

    // Memory pressure meter (right 30%)
    CGFloat mx = chartW + 10;
    CGFloat mw = w - mx - 10;
    CGFloat my = 10;
    CGFloat mh = h - 20;
    [[NSColor darkGrayColor] set];
    NSRect frame = NSMakeRect(mx, my, mw, mh);
    NSFrameRect(frame);
    if ([memHistory count] > 0) {
        double m = [[memHistory lastObject] doubleValue];
        NSRect fill = NSMakeRect(mx+1, my+1, mw-2, (mh-2)*m);
        [[NSColor blueColor] set];
        NSRectFill(fill);
    }
    [@"Mem" drawAtPoint:NSMakePoint(mx, h-14) withAttributes:attrs];
}

@end