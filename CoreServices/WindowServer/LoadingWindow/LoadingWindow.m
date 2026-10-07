/*
 * Copyright (C) 2024 Zoe Knox <zoe@pixin.net>
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

#import "LoadingWindow.h"
#import <unistd.h>

NSTimer *timer;

@implementation LoadingWindow
- init {
    NSScreen *screen = [NSScreen mainScreen];
    self = [super initWithContentRect:[screen frame] styleMask:NSBorderlessWindowMask
        backing:NSBackingStoreBuffered defer:NO];
    [self setLevel:kCGMaximumWindowLevelKey];
    return self;
}
-(void)applicationWillFinishLaunching:(NSNotification *)note {
   write(2, "[LW] applicationWillFinishLaunching\n", 36);
   /* ravynOS: skip NSImageView/NSProgressIndicator -- the NSWindow
    * initialization chain triggers 45+ NSFileManager/fileSystemRepresentation
    * calls that crash with NULL pointer dereference on TCG.  Just make
    * the window key and enter the run loop. */
   [self becomeMainWindow];
   [self makeKeyAndOrderFront:nil];
   timer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:nil selector:NULL
                          userInfo:nil repeats:YES];
   [NSThread detachNewThreadSelector:@selector(watchForFile:) toTarget:self withObject:nil];
}

-(void)watchForFile:(id)object {
    write(2, "[LW] watchForFile thread running\n", 33);
    while(access("/var/run/windowserver", F_OK) != 0) {
        usleep(100000);
    }
    write(2, "[LW] /var/run/windowserver detected, terminating\n", 49);
    [spinner stopAnimation:nil];
    [NSApp terminate:self];
}

@end

extern void bootstrap_init(void);

int main(int argc, const char *argv[]) {
    write(2, "[LW] main entered\n", 18);
    bootstrap_init();
    write(2, "[LW] bootstrap_init done\n", 25);
    /* ravynOS: skip __NSInitializeProcess and NSApplication -- the init
     * path crashes with NULL pointer dereference on TCG.  The
     * WindowServer has already painted the desktop.  Exit with status 0
     * so the WindowServer transitions to LOGINWINDOW. */
    write(2, "[LW] exiting without ObjC init\n", 32);
    exit(0);
}


