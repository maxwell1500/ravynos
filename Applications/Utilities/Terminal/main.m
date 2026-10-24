#import <AppKit/AppKit.h>
#import "TerminalAppDelegate.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        TerminalAppDelegate *delegate = [TerminalAppDelegate new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
