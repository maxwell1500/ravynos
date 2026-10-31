/*
 * cocoa.m -- AppKit conformance fixture for ravynOS.
 *
 * Built against Apple's macOS SDK with Apple's clang.  It exercises the
 * smallest complete Cocoa application: NSApplication, a window with a text
 * field, a real main menu, a run loop, and a timer-driven quit.  If this
 * runs, a stock AppKit application can start, draw, take keyboard focus and
 * exit cleanly on ravynOS.
 */

#import <Cocoa/Cocoa.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>

static int failures;

static void
check(const char *name, int ok, const char *detail)
{
    fprintf(stderr, "%s %s%s%s\n", ok ? "PASS" : "FAIL", name,
        ok ? "" : ": ", ok ? "" : (detail ? detail : "failed"));
    if (!ok) {
        failures++;
    }
}

@interface ProbeDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow    *_window;
    NSTextField *_field;
}
- (void)quitAfterDelay:(NSTimer *)timer;
@end

@implementation ProbeDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    (void)note;

    /* Launched through LaunchServices, this fixture's stdout goes nowhere
     * useful, so it leaves proof of arrival on disk.  The launch fixture
     * removes the file first and waits for it to reappear. */
    [[NSFileManager defaultManager] createFileAtPath:@"/tmp/ravyn-compat-launched"
                                            contents:[NSData data]
                                          attributes:nil];

    NSRect frame = NSMakeRect(200, 200, 360, 120);

    _window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
        backing:NSBackingStoreBuffered
        defer:NO];
    if (_window == nil) {
        check("window", 0, "initWithContentRect returned nil");
        [NSApp terminate:nil];
        return;
    }
    [_window setTitle:@"CocoaProbe"];

    _field = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 320, 24)];
    [_field setStringValue:@"ravynOS compat"];
    [[_window contentView] addSubview:_field];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    check("window", 1, NULL);
    check("textfield", [_field stringValue] != nil, NULL);

    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    [NSApp setMainMenu:mainMenu];

    NSMenu *appMenu = [[NSMenu alloc] init];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit"
        action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenu addItem:quit];
    [appItem setSubmenu:appMenu];
    check("mainmenu", [[NSApp mainMenu] numberOfItems] > 0, NULL);

    [NSTimer scheduledTimerWithTimeInterval:2.0
        target:self
        selector:@selector(quitAfterDelay:)
        userInfo:nil
        repeats:NO];
}

- (void)quitAfterDelay:(NSTimer *)timer
{
    (void)timer;
    check("runloop", 1, NULL);
    printf("FIXTURE cocoa rc=%d\n", failures);
    fflush(stdout);
    [NSApp terminate:nil];
}

@end

int
main(int argc, const char **argv)
{
    (void)argc;
    (void)argv;

    /* Written before Foundation or AppKit is touched, with plain POSIX, so a
     * launch that reaches main is distinguishable from a launch that dies in
     * dyld: /tmp/ravyn-compat-entered-main.  The later marker, written in
     * applicationDidFinishLaunching, proves the full AppKit launch. */
    {
        int fd = open("/tmp/ravyn-compat-entered-main", O_CREAT | O_WRONLY | O_TRUNC, 0644);
        if (fd >= 0) {
            char buf[64];
            int n = snprintf(buf, sizeof(buf), "pid=%d\n", (int)getpid());
            if (n > 0) {
                ssize_t ignored = write(fd, buf, (size_t)n);
                (void)ignored;
            }
            close(fd);
        }
    }

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ProbeDelegate *delegate = [[ProbeDelegate alloc] init];

        [app setDelegate:delegate];
        check("nsapplication", app != nil, NULL);
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }

    printf("FIXTURE cocoa rc=%d\n", failures);
    fflush(stdout);
    return failures == 0 ? 0 : 1;
}
