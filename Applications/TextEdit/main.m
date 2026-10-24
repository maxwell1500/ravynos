#import <AppKit/AppKit.h>
#import "TextDocument.h"
#import "TextWindowController.h"

@interface TextAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation TextAppDelegate

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {
    return YES;
}

- (void)openPath:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES error:NULL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    NSUInteger i = 1;
    while (i < [args count]) {
        NSString *a = [args objectAtIndex:i];
        if ([a isEqualToString:@"-NSOpen"]) {
            i++;
            if (i < [args count]) [self openPath:[args objectAtIndex:i]];
        } else if (![a hasPrefix:@"-"]) {
            [self openPath:a];
        }
        i++;
    }
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
    for (NSString *f in filenames) [self openPath:f];
    [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        TextAppDelegate *delegate = [TextAppDelegate new];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}