#import <AppKit/AppKit.h>
#import "ConsoleController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ConsoleController *delegate = [ConsoleController new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}