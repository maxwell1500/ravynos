#import <AppKit/AppKit.h>
#import "KeychainController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        KeychainController *delegate = [KeychainController new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}