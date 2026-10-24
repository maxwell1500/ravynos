/*
 * defaults - command line interface to user defaults system
 *
 * Copyright (c) 2026 ravynOS Project
 */

#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

static void printUsage(void) {
    fprintf(stderr,
        "Usage:\n"
        "  defaults read [<domain> [<key>]]\n"
        "  defaults write <domain> <key> [-string|-int|-bool|-float] <value>\n"
        "  defaults delete <domain> [<key>]\n"
        "  defaults [-g|-globalDomain] ...\n");
}

static NSString *resolveDomainPath(NSString *domain) {
    if ([domain isEqualToString:@"-g"] ||
        [domain isEqualToString:@"-globalDomain"] ||
        [domain isEqualToString:@"NSGlobalDomain"]) {
        NSString *home = NSHomeDirectory();
        return [home stringByAppendingPathComponent:@"Library/Preferences/.GlobalPreferences.plist"];
    }

    if ([domain hasPrefix:@"/"] || [domain hasPrefix:@"."]) {
        if (![domain hasSuffix:@".plist"])
            return [domain stringByAppendingString:@".plist"];
        return domain;
    }

    NSString *home = NSHomeDirectory();
    NSString *prefDir = [home stringByAppendingPathComponent:@"Library/Preferences"];
    return [prefDir stringByAppendingPathComponent:[domain stringByAppendingPathExtension:@"plist"]];
}

static NSMutableDictionary *loadDict(NSString *path) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (dict)
        return dict;
    return [NSMutableDictionary dictionary];
}

static BOOL saveDict(NSDictionary *dict, NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    return [dict writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printUsage();
            return 1;
        }

        const char *cmd = argv[1];

        if (strcmp(cmd, "read") == 0) {
            if (argc == 2) {
                // Read all defaults
                NSString *prefDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"];
                NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:prefDir error:NULL];
                for (NSString *file in files) {
                    if ([file hasSuffix:@".plist"]) {
                        NSString *p = [prefDir stringByAppendingPathComponent:file];
                        NSDictionary *d = loadDict(p);
                        printf("=== %s ===\n", [file UTF8String]);
                        printf("%s\n", [[d description] UTF8String]);
                    }
                }
                return 0;
            }

            NSString *domain = [NSString stringWithUTF8String:argv[2]];
            NSString *path = resolveDomainPath(domain);
            NSDictionary *dict = loadDict(path);

            if (argc == 3) {
                if ([dict count] == 0) {
                    fprintf(stderr, "Domain %s does not exist\n", [domain UTF8String]);
                    return 1;
                }
                printf("%s\n", [[dict description] UTF8String]);
                return 0;
            }

            NSString *key = [NSString stringWithUTF8String:argv[3]];
            id val = [dict objectForKey:key];
            if (!val) {
                fprintf(stderr, "The domain/default pair of (%s, %s) does not exist\n",
                        [domain UTF8String], [key UTF8String]);
                return 1;
            }

            if ([val isKindOfClass:[NSString class]]) {
                printf("%s\n", [(NSString *)val UTF8String]);
            } else if ([val isKindOfClass:[NSNumber class]]) {
                printf("%s\n", [[(NSNumber *)val stringValue] UTF8String]);
            } else {
                printf("%s\n", [[val description] UTF8String]);
            }
            return 0;
        }

        if (strcmp(cmd, "write") == 0) {
            if (argc < 5) {
                printUsage();
                return 1;
            }

            NSString *domain = [NSString stringWithUTF8String:argv[2]];
            NSString *key = [NSString stringWithUTF8String:argv[3]];
            id value = nil;

            if (argc == 5) {
                // Default type: string
                value = [NSString stringWithUTF8String:argv[4]];
            } else if (argc >= 6) {
                const char *typeFlag = argv[4];
                const char *valStr = argv[5];

                if (strcmp(typeFlag, "-string") == 0) {
                    value = [NSString stringWithUTF8String:valStr];
                } else if (strcmp(typeFlag, "-int") == 0 || strcmp(typeFlag, "-integer") == 0) {
                    value = [NSNumber numberWithInteger:strtol(valStr, NULL, 10)];
                } else if (strcmp(typeFlag, "-float") == 0) {
                    value = [NSNumber numberWithDouble:strtod(valStr, NULL)];
                } else if (strcmp(typeFlag, "-bool") == 0 || strcmp(typeFlag, "-boolean") == 0) {
                    BOOL b = (strcasecmp(valStr, "YES") == 0 ||
                              strcasecmp(valStr, "TRUE") == 0 ||
                              strcmp(valStr, "1") == 0);
                    value = [NSNumber numberWithBool:b];
                } else {
                    fprintf(stderr, "Unknown value type '%s'\n", typeFlag);
                    return 1;
                }
            }

            NSString *path = resolveDomainPath(domain);
            NSMutableDictionary *dict = loadDict(path);
            [dict setObject:value forKey:key];

            if (!saveDict(dict, path)) {
                fprintf(stderr, "Could not write domain %s\n", [domain UTF8String]);
                return 1;
            }
            return 0;
        }

        if (strcmp(cmd, "delete") == 0) {
            if (argc < 3) {
                printUsage();
                return 1;
            }

            NSString *domain = [NSString stringWithUTF8String:argv[2]];
            NSString *path = resolveDomainPath(domain);

            if (argc == 3) {
                // Delete entire domain plist
                [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
                return 0;
            }

            NSString *key = [NSString stringWithUTF8String:argv[3]];
            NSMutableDictionary *dict = loadDict(path);
            if (![dict objectForKey:key]) {
                return 0;
            }
            [dict removeObjectForKey:key];
            saveDict(dict, path);
            return 0;
        }

        printUsage();
        return 1;
    }
}
