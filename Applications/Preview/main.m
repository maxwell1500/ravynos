#import <AppKit/AppKit.h>
#import "PreviewDocument.h"

@interface PreviewAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation PreviewAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {
    return YES;
}
- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
    for (NSString *f in filenames) {
        NSURL *url = [NSURL fileURLWithPath:f];
        [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES error:NULL];
    }
    [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        PreviewAppDelegate *delegate = [PreviewAppDelegate new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}