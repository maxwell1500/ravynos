#import "ArchiveController.h"

@interface ArchiveController ()
@property (nonatomic, strong) NSTextField *statusLabel;
- (void)updateProgressWithEntry:(NSString *)entryName bytes:(long long)bytesDone total:(long long)totalBytes;
@end

/* Progress is delivered through a plain C callback: Objective-C blocks are not
 * usable on this image (the _NSConcrete*Block class tables are zero-filled). */
static void ArchiveControllerProgress(void *ctx, NSString *entryName, long long bytesDone, long long totalBytes) {
    ArchiveController *controller = (__bridge ArchiveController *)ctx;
    [controller updateProgressWithEntry:entryName bytes:bytesDone total:totalBytes];
}

@implementation ArchiveController

- (void)createWindow {
    NSRect frame = NSMakeRect(400, 300, 360, 160);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:NSTitledWindowMask
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    [self.window setTitle:@"Archive Utility"];
    NSView *content = [self.window contentView];

    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 125, 340, 20)];
    [self.statusLabel setEditable:NO];
    [self.statusLabel setBordered:NO];
    [self.statusLabel setDrawsBackground:NO];
    [self.statusLabel setStringValue:@"Preparing..."];
    [content addSubview:self.statusLabel];

    self.entryField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 95, 340, 20)];
    [self.entryField setEditable:NO];
    [self.entryField setBordered:NO];
    [self.entryField setDrawsBackground:NO];
    [self.entryField setStringValue:@""];
    [content addSubview:self.entryField];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(10, 55, 340, 20)];
    [self.progress setMinValue:0];
    [self.progress setMaxValue:100];
    [self.progress setDoubleValue:0];
    [self.progress setIndeterminate:NO];
    [content addSubview:self.progress];
}

- (void)updateProgressWithEntry:(NSString *)entryName bytes:(long long)bytesDone total:(long long)totalBytes {
    [self.entryField setStringValue:entryName ?: @""];
    double frac = totalBytes > 0 ? (double)bytesDone / (double)totalBytes * 100.0 : 0;
    [self.progress setDoubleValue:frac];
    [self.entryField displayIfNeeded];
    [self.progress displayIfNeeded];
    [self.window displayIfNeeded];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self createWindow];
    [self.window makeKeyAndOrderFront:nil];
    [self.window display];
    [[NSApplication sharedApplication] updateWindows];

    /* Standalone launch (no archive, no paths): stay open with a ready state
     * so the window is visible for screenshots and manual use. */
    if (!self.compressMode && (self.archivePath == nil || [self.archivePath length] == 0)) {
        [self.statusLabel setStringValue:@"Ready — Drop or open an archive (.zip, .tar, .tar.gz) to extract"];
        [self.window display];
        return;
    }

    NSString *err = nil;
    BOOL ok = NO;
    if (self.compressMode) {
        ok = [ArchiveEngine compressPaths:self.paths
                               destination:nil
                                  progress:ArchiveControllerProgress
                                   context:(__bridge void *)self
                                     error:&err];
    } else {
        ok = [ArchiveEngine extractArchiveAtPath:self.archivePath
                                       progress:ArchiveControllerProgress
                                        context:(__bridge void *)self
                                          error:&err];
    }

    if (!ok) {
        fprintf(stderr, "Archive Utility: %s\n", [err UTF8String]);
        fflush(stderr);
        [self.statusLabel setStringValue:err ?: @"Archive failed"];
    } else {
        [self.statusLabel setStringValue:@"Done"];
    }
    [self.statusLabel displayIfNeeded];
    [self.window displayIfNeeded];

    [self.window close];
    [[NSApplication sharedApplication] terminate:nil];
}

@end
