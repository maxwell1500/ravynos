#import <AppKit/AppKit.h>
#import "ScreenshotOverlayView.h"

/* Borderless windows are not key by default, so Escape never reached the
 * overlay and the HUD buttons could not take keyboard focus. */
@interface ScreenshotKeyWindow : NSWindow
@end

@implementation ScreenshotKeyWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface ScreenshotAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, strong) NSWindow *overlayWindow;
@property (nonatomic, strong) NSWindow *hudWindow;
@property (nonatomic, strong) NSPopUpButton *timerPopup;
@property (nonatomic, strong) NSPopUpButton *destPopup;
- (instancetype)initWithMode:(NSString *)mode;
- (void)startRectMode;
- (void)doFullCapture;
@end
@implementation ScreenshotAppDelegate

- (instancetype)initWithMode:(NSString *)mode {
    self = [super init];
    if (self) _mode = [mode copy];
    return self;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if ([_mode isEqualToString:@"full"]) {
        ScreenshotCaptureFull();
        [NSApp terminate:nil];
        return;
    }
    if ([_mode isEqualToString:@"rect"]) {
        [self startRectMode];
        return;
    }
    /* default: hud */
    [self showHUD];
}

- (void)startRectMode {
    CGDirectDisplayID display = CGMainDisplayID();
    CGRect bounds = CGDisplayBounds(display);
    CGImageRef img = CGDisplayCreateImageForRect(display, bounds);

    NSScreen *screen = [NSScreen mainScreen];
    NSWindow *win = [[ScreenshotKeyWindow alloc] initWithContentRect:(NSRect)bounds
                                                          styleMask:NSBorderlessWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO
                                                             screen:screen];
    [win setLevel:NSScreenSaverWindowLevel];
    [win setOpaque:YES];
    [win setBackgroundColor:[NSColor blackColor]];
    [win setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary];

    ScreenshotOverlayView *view = [[ScreenshotOverlayView alloc] initWithFrame:(NSRect)bounds frozenImage:img];
    [win setContentView:view];
    [win makeKeyAndOrderFront:nil];
    [[NSCursor crosshairCursor] push];
    self.overlayWindow = win;
    if (img) CFRelease(img);
}

- (void)showHUD {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect sf = [screen frame];
    CGFloat w = 460, h = 64;
    NSRect frame = NSMakeRect((sf.size.width - w) / 2.0, 48, w, h);

    NSWindow *win = [[ScreenshotKeyWindow alloc] initWithContentRect:frame
                                                          styleMask:NSBorderlessWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO
                                                             screen:screen];
    [win setLevel:NSFloatingWindowLevel];
    [win setOpaque:NO];
    [win setBackgroundColor:[NSColor clearColor]];
    [win setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary];

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    [win setContentView:content];

    CGFloat bw = 130, bh = 28, gap = 8, y = (h - bh) / 2.0;
    NSButton *b1 = [[NSButton alloc] initWithFrame:NSMakeRect(gap, y, bw, bh)];
    [b1 setTitle:@"Capture Entire Screen"];
    [b1 setBezelStyle:NSRoundedBezelStyle];
    [b1 setTarget:self];
    [b1 setAction:@selector(captureFullDelayed:)];
    [content addSubview:b1];

    NSButton *b2 = [[NSButton alloc] initWithFrame:NSMakeRect(gap + (bw + gap), y, bw, bh)];
    [b2 setTitle:@"Capture Selected Window"];
    [b2 setBezelStyle:NSRoundedBezelStyle];
    [b2 setTarget:self];
    [b2 setAction:@selector(captureWindowDelayed:)];
    [content addSubview:b2];

    NSButton *b3 = [[NSButton alloc] initWithFrame:NSMakeRect(gap + 2 * (bw + gap), y, bw, bh)];
    [b3 setTitle:@"Capture Selected Portion"];
    [b3 setBezelStyle:NSRoundedBezelStyle];
    [b3 setTarget:self];
    [b3 setAction:@selector(capturePortion:)];
    [content addSubview:b3];

    NSPopUpButton *timer = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(w - 150, y + 16, 140, 20) pullsDown:NO];
    [timer addItemsWithTitles:@[@"Timer: None", @"Timer: 5s", @"Timer: 10s"]];
    [content addSubview:timer];
    self.timerPopup = timer;

    NSPopUpButton *dest = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(w - 150, y - 4, 140, 20) pullsDown:NO];
    [dest addItemsWithTitles:@[@"Save to: Desktop", @"Save to: Clipboard", @"Save to: Preview"]];
    [content addSubview:dest];
    self.destPopup = dest;

    [win makeKeyAndOrderFront:nil];
    self.hudWindow = win;
}

- (int)timerDelay {
    NSInteger idx = [self.timerPopup indexOfSelectedItem];
    if (idx == 1) return 5;
    if (idx == 2) return 10;
    return 0;
}

- (void)captureFullDelayed:(id)sender {
    int delay = [self timerDelay];
    if (delay <= 0) {
        [self doFullCapture];
    } else {
        [self.hudWindow orderOut:nil];
        [self performSelector:@selector(doFullCapture) withObject:nil afterDelay:delay];
    }
}

- (int)destinationIndex {
    NSInteger idx = [self.destPopup indexOfSelectedItem];
    return (idx == 1) ? 1 : (idx == 2 ? 2 : 0);
}

- (void)doFullCapture {
    [self.hudWindow orderOut:nil];
    ScreenshotWriteImageWithDestination(ScreenshotCaptureFullImage(), [self destinationIndex]);
    [NSApp terminate:nil];
}

- (void)captureWindowDelayed:(id)sender {
    int delay = [self timerDelay];

    [self.hudWindow orderOut:nil];
    if (delay <= 0)
        [self doWindowCapture];
    else
        [self performSelector:@selector(doWindowCapture) withObject:nil afterDelay:delay];
}

/* Capture the topmost application window through the WindowServer RPC; fall
 * back to a full-display capture when no window is available. */
- (void)doWindowCapture {
    CGImageRef image = ScreenshotCaptureTopWindow();

    if (image == NULL)
        image = ScreenshotCaptureFullImage();
    if (image != NULL) {
        ScreenshotWriteImageWithDestination(image, [self destinationIndex]);
        CGImageRelease(image);
    }
    [NSApp terminate:nil];
}

- (void)capturePortion:(id)sender {
    [self.hudWindow orderOut:nil];
    [self startRectMode];
}

- (void)dealloc {
    if (self.overlayWindow != nil)
        [NSCursor pop];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = @"hud";
        for (int i = 1; i < argc; i++) {
            NSString *a = [NSString stringWithUTF8String:argv[i]];
            if ([a isEqualToString:@"--mode"] && i + 1 < argc) {
                mode = [NSString stringWithUTF8String:argv[++i]];
            } else if ([a hasPrefix:@"--mode="]) {
                mode = [a substringFromIndex:7];
            }
        }
        NSApplication *app = [NSApplication sharedApplication];
        ScreenshotAppDelegate *delegate = [[ScreenshotAppDelegate alloc] initWithMode:mode];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
