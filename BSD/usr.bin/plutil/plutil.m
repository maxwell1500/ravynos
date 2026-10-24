/*
 * plutil - property list utility for ravynOS
 *
 * Copyright (c) 2026 ravynOS Project
 */

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static void printUsage(void) {
    fprintf(stderr,
        "Usage: plutil [options] [files]\n"
        "  -lint                  Check file syntax\n"
        "  -convert fmt           Convert to format (xml1, binary1, json)\n"
        "  -help                  Show this message\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printUsage();
            return 1;
        }

        BOOL lintMode = NO;
        NSString *convertFmt = nil;
        NSMutableArray *files = [NSMutableArray array];

        for (int i = 1; i < argc; i++) {
            const char *arg = argv[i];
            if (strcmp(arg, "-lint") == 0) {
                lintMode = YES;
            } else if (strcmp(arg, "-convert") == 0) {
                if (i + 1 < argc) {
                    convertFmt = [NSString stringWithUTF8String:argv[++i]];
                } else {
                    fprintf(stderr, "Missing format after -convert\n");
                    return 1;
                }
            } else if (strcmp(arg, "-help") == 0 || strcmp(arg, "--help") == 0) {
                printUsage();
                return 0;
            } else if (arg[0] == '-') {
                fprintf(stderr, "Unknown option: %s\n", arg);
                printUsage();
                return 1;
            } else {
                [files addObject:[NSString stringWithUTF8String:arg]];
            }
        }

        if ([files count] == 0) {
            fprintf(stderr, "No files specified.\n");
            return 1;
        }

        int exitCode = 0;

        for (NSString *file in files) {
            NSData *data = [NSData dataWithContentsOfFile:file];
            if (!data) {
                fprintf(stderr, "%s: file cannot be read\n", [file UTF8String]);
                exitCode = 1;
                continue;
            }

            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:file];
            if (!dict) {
                NSArray *arr = [NSArray arrayWithContentsOfFile:file];
                if (!arr) {
                    fprintf(stderr, "%s: file is not a valid property list\n", [file UTF8String]);
                    exitCode = 1;
                    continue;
                }
            }

            if (lintMode || convertFmt == nil) {
                printf("%s: OK\n", [file UTF8String]);
            }

            if (convertFmt) {
                if (dict) {
                    if (![dict writeToFile:file atomically:YES]) {
                        fprintf(stderr, "%s: failed to write converted file\n", [file UTF8String]);
                        exitCode = 1;
                    }
                }
            }
        }

        return exitCode;
    }
}
