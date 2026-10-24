#import <AppKit/AppKit.h>
#import "ActivityMonitorController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ActivityMonitorController *delegate = [ActivityMonitorController new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}