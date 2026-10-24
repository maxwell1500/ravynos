#import <AppKit/AppKit.h>
#import "DiskUtilityController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        DiskUtilityController *delegate = [DiskUtilityController new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}