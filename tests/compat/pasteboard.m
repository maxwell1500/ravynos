/*
 * pasteboard.m -- cross-process pasteboard fixture for ravynOS.
 *
 * Built against Apple's macOS SDK like the other fixtures.  Two separate
 * invocations share state only through the pasteboard server, which is the
 * property that matters: a string written by one process must be readable by
 * another, through NSPasteboard, with no shared memory between them.
 *
 *   pasteboard write   -> clear and write the test string
 *   pasteboard read    -> read it back and compare
 */

#import <Cocoa/Cocoa.h>
#include <string.h>
#include <stdio.h>

static NSString *const kTestString = @"ravyn-compat-paste";

int
main(int argc, const char **argv)
{
    @autoreleasepool {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];

        if (argc > 1 && strcmp(argv[1], "write") == 0) {
            [pb clearContents];
            if (![pb setString:kTestString forType:NSPasteboardTypeString]) {
                fprintf(stderr, "pasteboard write failed\n");
                return 1;
            }
            return 0;
        }

        NSString *got = [pb stringForType:NSPasteboardTypeString];
        if (got == nil) {
            fprintf(stderr, "pasteboard read: nil string\n");
            return 1;
        }
        if (![got isEqualToString:kTestString]) {
            fprintf(stderr, "pasteboard read: got '%s'\n", [got UTF8String]);
            return 1;
        }
        return 0;
    }
}
