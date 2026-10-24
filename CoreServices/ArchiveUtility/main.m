#import <AppKit/AppKit.h>
#import "ArchiveController.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ArchiveController *delegate = [ArchiveController new];
        if (argc >= 2 && strcmp(argv[1], "--compress") == 0) {
            delegate.compressMode = YES;
            NSMutableArray *ps = [NSMutableArray array];
            for (int i = 2; i < argc; i++) [ps addObject:[NSString stringWithUTF8String:argv[i]]];
            delegate.paths = ps;
        } else if (argc >= 2) {
            delegate.archivePath = [NSString stringWithUTF8String:argv[1]];
        }
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}