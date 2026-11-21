/*
 * clickprobe.m -- in-guest oracle for "does the click reach the view".
 *
 * The WindowServer trace ([WS] ev ...) proves which *window* a click was
 * routed to.  It cannot prove which *view* inside that window received it,
 * because view dispatch happens in the framework.  This probe prints both
 * sides, so a click that lands on the wrong control is distinguishable from
 * one that never reaches the app at all.
 *
 * Prints, on /dev/console:
 *   CLICKPROBE ready window=<frame> button=<frame>
 *   CLICKPROBE down loc=<x>,<y> hit=<Class> button=<frame>
 *   CLICKPROBE up   loc=<x>,<y> hit=<Class> button=<frame>
 *   CLICKPROBE done downs=<n> ups=<n>
 *
 * Runs for a bounded time so it can never hang the fixture runner.
 */
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>
#import <stdarg.h>

static FILE *gOut;
static int gDowns, gUps;

static void
emit(const char *fmt, ...)
{
    va_list ap;
    if (gOut == NULL)
        return;
    va_start(ap, fmt);
    vfprintf(gOut, fmt, ap);
    fflush(gOut);
    va_end(ap);
}

@interface LoggingButton : NSButton
@end

@implementation LoggingButton

- (void)mouseDown:(NSEvent *)event
{
    NSPoint p = [event locationInWindow];
    NSView *hit = [[self superview] hitTest:p];
    ++gDowns;
    emit("CLICKPROBE down loc=%d,%d hit=%s button=%d,%d %dx%d\n",
         (int)p.x, (int)p.y, hit ? class_getName([hit class]) : "(nil)",
         (int)[self frame].origin.x, (int)[self frame].origin.y,
         (int)[self frame].size.width, (int)[self frame].size.height);
    [super mouseDown:event];
}

- (void)mouseUp:(NSEvent *)event
{
    NSPoint p = [event locationInWindow];
    NSView *hit = [[self superview] hitTest:p];
    ++gUps;
    emit("CLICKPROBE up   loc=%d,%d hit=%s button=%d,%d %dx%d\n",
         (int)p.x, (int)p.y, hit ? class_getName([hit class]) : "(nil)",
         (int)[self frame].origin.x, (int)[self frame].origin.y,
         (int)[self frame].size.width, (int)[self frame].size.height);
    [super mouseUp:event];
}

@end

@interface ClickProbeDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow *_window;
    NSTimer  *_timer;
}
@end

@implementation ClickProbeDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    (void)note;

    NSRect wf = NSMakeRect(300, 300, 320, 140);
    _window = [[NSWindow alloc] initWithContentRect:wf
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
        backing:NSBackingStoreBuffered
        defer:NO];
    if (_window == nil) {
        emit("CLICKPROBE fail window-nil\n");
        [NSApp terminate:nil];
        return;
    }
    [_window setTitle:@"ClickProbe"];

    NSView *content = [_window contentView];
    NSRect bf = NSMakeRect(40, 40, 160, 40);
    LoggingButton *b = [[LoggingButton alloc] initWithFrame:bf];
    [b setTitle:@"Press"];
    [b setBezelStyle:NSBezelStyleRounded];
    [content addSubview:b];
    [b release];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    emit("CLICKPROBE ready window=%d,%d %dx%d button=%d,%d %dx%d\n",
         (int)wf.origin.x, (int)wf.origin.y,
         (int)wf.size.width, (int)wf.size.height,
         (int)bf.origin.x, (int)bf.origin.y,
         (int)bf.size.width, (int)bf.size.height);

    NSString *secs = [[[NSProcessInfo processInfo] environment]
        objectForKey:@"CLICKPROBE_SECONDS"];
    NSTimeInterval life = secs ? [secs doubleValue] : 30.0;
    if (life <= 0) life = 30.0;
    _timer = [NSTimer scheduledTimerWithTimeInterval:life
                                              target:self
                                            selector:@selector(finish:)
                                            userInfo:nil
                                             repeats:NO];
}

- (void)finish:(NSTimer *)t
{
    (void)t;
    emit("CLICKPROBE done downs=%d ups=%d\n", gDowns, gUps);
    [NSApp terminate:nil];
}

@end

int
main(int argc, char **argv)
{
    (void)argc; (void)argv;

    /* /dev/console keeps the lines visible in the guest serial log, which is
     * where both the WM harness and a human reading the log expect them. */
    gOut = fopen("/dev/console", "w");
    if (gOut == NULL)
        gOut = stderr;

    @autoreleasepool {
        [NSApplication sharedApplication];
        ClickProbeDelegate *d = [[ClickProbeDelegate alloc] init];
        [NSApp setDelegate:d];
        [NSApp run];
        [d release];
    }
    return 0;
}
