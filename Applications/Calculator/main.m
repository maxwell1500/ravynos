#import <AppKit/AppKit.h>
#import "CalcController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        CalcController *delegate = [CalcController new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}