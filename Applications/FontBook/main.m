#import <AppKit/AppKit.h>
#import "FontBookController.h"

@interface FontBookAppDelegate : NSObject <NSApplicationDelegate>
@property (retain) FontBookController *controller;
@end

@implementation FontBookAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _controller = [FontBookController new];
    [_controller showWindow];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        FontBookAppDelegate *delegate = [FontBookAppDelegate new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}