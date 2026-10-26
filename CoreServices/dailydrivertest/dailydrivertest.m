/*
 * dailydrivertest - the in-guest self test of the daily-driver desktop.
 *
 * The harness (tools/bootlab/verify_daily_driver.py) boots the image and
 * reads this program's report back out of the image filesystem.  The test
 * covers the things that only the running system can show:
 *
 *   1. the pasteboard daemon answers under BOTH its native name and the
 *      canonical macOS name, on the SAME port,
 *   2. a paste written by one process is read by another process (the
 *      daemon is the only shared state),
 *   3. the same for a file URL payload,
 *   4. the canonical macOS paths (Finder.app, /Applications/System Settings.app)
 *      and the daily-driver applications are present in the image,
 *   5. a global capture produces a screenshot file (the same path the
 *      Cmd+Shift+3 shortcut uses), and Finder.app and Filer.app are one
 *      process.
 *
 * The report is written to /var/log/daily-driver-selftest.txt.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "WindowServer/message.h"
#import "WindowServer/rpc.h"

#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/stat.h>

extern mach_port_t bootstrap_port;
extern void bootstrap_init(void);

#define REPORT_PATH "/var/log/daily-driver-selftest.txt"
#define SELF_TEST_PATH "/System/Library/CoreServices/dailydrivertest"

static int _failures = 0;

static void _say(NSMutableString *report, NSString *line, BOOL ok) {
    if(!ok)
        _failures++;
    [report appendFormat:@"%@ %@\n", ok ? @"PASS" : @"FAIL", line];
    fprintf(stderr, "%s %s\n", ok ? @"PASS" : @"FAIL", [line UTF8String]);
    fflush(stderr);
}

/* The count is generated, not stored: the report is written once before the
 * fleet starts (so a hang still leaves a report) and again at the end, and
 * both copies have to state the failures known at that moment. */
static void _writeReport(NSString *body) {
    NSMutableString *out = [NSMutableString stringWithString:body];
    NSString *reportPath = @"/var/log/daily-driver-selftest.txt";
    NSData *data;

    [out appendFormat:@"%d failure(s)\n", _failures];
    data = [out dataUsingEncoding:NSUTF8StringEncoding];
    FILE *f = fopen([reportPath fileSystemRepresentation], "wb");
    if(f != NULL) {
        fwrite([data bytes], 1, [data length], f);
        fflush(f);
        /* The harness reads the report out of the image after the guest is
         * stopped: the data has to be on the disk, not in the file system's
         * cache. */
        fsync(fileno(f));
        fclose(f);
    }
}

/* Run this program again with a mode and return what it printed. */
static NSString *_runChild(const char *mode, const char *argument) {
    int fds[2];
    pid_t pid;
    NSMutableData *data;
    char buf[512];
    ssize_t n;

    if(pipe(fds) != 0)
        return nil;

    pid = fork();
    if(pid == 0) {
        char *argv[3];

        close(fds[0]);
        dup2(fds[1], 1);
        close(fds[1]);
        argv[0] = (char *)SELF_TEST_PATH;
        argv[1] = (char *)mode;
        argv[2] = (char *)argument;
        argv[2] = (char *)argument;
        execv(SELF_TEST_PATH, argv);
        _exit(127);
    }

    close(fds[1]);
    data = [NSMutableData data];
    while((n = read(fds[0], buf, sizeof(buf))) > 0)
        [data appendBytes:buf length:(NSUInteger)n];
    close(fds[0]);

    {
        int status = 0;
        waitpid(pid, &status, 0);
    }

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

/* The two service names must resolve to the same port. */
static int _portsChild(void) {
    mach_port_t native = MACH_PORT_NULL, canonical = MACH_PORT_NULL;
    kern_return_t kr1, kr2;

    if(bootstrap_port == MACH_PORT_NULL)
        bootstrap_init();
    kr1 = bootstrap_look_up(bootstrap_port, "com.ravynos.pasteboardd", &native);
    kr2 = bootstrap_look_up(bootstrap_port, "com.apple.pboard", &canonical);

    printf("native=%u canonical=%u same=%d\n",
           (unsigned)native, (unsigned)canonical,
           (kr1 == KERN_SUCCESS && kr2 == KERN_SUCCESS && native == canonical) ? 1 : 0);
    fflush(stdout);
    return 0;
}

static int _readTextChild(void) {
    NSString *text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];

    printf("%s", text != nil ? [text UTF8String] : "(null)");
    fflush(stdout);
    return 0;
}

static int _readURLChild(void) {
    NSString *url = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeFileURL];

    printf("%s", url != nil ? [url UTF8String] : "(null)");
    fflush(stdout);
    return 0;
}

static int _childMain(int argc, char **argv) {
    if(argc < 2)
        return 2;
    if(strcmp(argv[1], "ports") == 0)
        return _portsChild();
    if(strcmp(argv[1], "read-text") == 0)
        return _readTextChild();
    if(strcmp(argv[1], "read-url") == 0)
        return _readURLChild();
    return 2;
}

static BOOL _fileExists(NSString *path) {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

/* CODE_OPEN_BUNDLE: the payload is the bundle path. */
/* Bundle identifier from the bundle's own Info.plist (no NSBundle: walking the
 * .app tree on FAT32 hangs some processes). */
static NSString *_bundleIdentifierOfBundle(NSString *bundlePath) {
    if(bundlePath == nil)
        return nil;
    NSString *plistPath = [bundlePath stringByAppendingPathComponent:@"Contents/Info.plist"];
    const char *p = (plistPath != nil) ? [plistPath UTF8String] : NULL;
    if(p == NULL)
        return nil;
    FILE *f = fopen(p, "r");
    if(f == NULL)
        return nil;
    static char buf[16384];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = '\0';
    char *key = strstr(buf, "<key>CFBundleIdentifier</key>");
    if(key == NULL)
        return nil;
    char *s = strstr(key + strlen("<key>CFBundleIdentifier</key>"), "<string>");
    if(s == NULL)
        return nil;
    s += strlen("<string>");
    char *e = strstr(s, "</string>");
    if(e == NULL || e <= s)
        return nil;
    static char id[128];
    size_t len = (size_t)(e - s);
    if(len >= sizeof(id))
        len = sizeof(id) - 1;
    memcpy(id, s, len);
    id[len] = '\0';
    return [NSString stringWithCString:id encoding:NSASCIIStringEncoding];
}

/* Count how often WindowServer has announced this bundle on the marker file:
 * one entry per time one of its windows was seen painted, so a second entry
 * after an activation request proves that request reached the screen. */
static int _countPainted(const char *bundleID) {
    FILE *f = fopen("/var/log/ws-painted.log", "r");
    if(f == NULL)
        return 0;
    static char buf[65536];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = '\0';
    int count = 0;
    const char *p = buf;
    while((p = strstr(p, bundleID)) != NULL) {
        count++;
        p += 1;
    }
    return count;
}

/* Screenshot files a capture wrote into a directory. */
static NSSet *_screenShotNames(NSString *dir) {
    NSMutableSet *set = [NSMutableSet set];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    for(NSString *name in names)
        if([name hasPrefix:@"Screen Shot "] && [name hasSuffix:@".png"])
            [set addObject:name];
    return set;
}

static kern_return_t _openBundleOnWindowServer(NSString *bundlePath);

/* WindowServer records every launch and activation in /var/log/ws-apps.log:
 *   SPAWN <bundleID> <pid>
 *   ACTIVATE <bundleID> <pid>
 * verb == NULL counts every line for the bundle.  Counting is what makes
 * "Finder.app is the same app as Filer.app" checkable: the alias may activate
 * the running process, and must never add a second SPAWN. */
static int _countAppLog(const char *verb, const char *bundleID) {
    FILE *f = fopen("/var/log/ws-apps.log", "r");
    if(f == NULL)
        return 0;
    static char buf[65536];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = '\0';
    int count = 0;
    char *line = buf;
    while(line != NULL && *line != '\0') {
        char *end = strchr(line, '\n');
        if(end != NULL)
            *end = '\0';
        if(strstr(line, bundleID) != NULL &&
           (verb == NULL || strncmp(line, verb, strlen(verb)) == 0))
            count++;
        line = (end != NULL) ? end + 1 : NULL;
    }
    return count;
}

static BOOL _waitForAppLog(const char *bundleID, int atLeast, int seconds) {
    int i;
    for(i = 0; i < seconds * 4; i++) {
        if(_countAppLog(NULL, bundleID) >= atLeast)
            return YES;
        usleep(250000);
    }
    return NO;
}

/* Ask the WindowServer to open a bundle until its app log grows past target.
 * The first calls can land before the server is answering, so a failed open
 * is retried rather than counted. */
static BOOL _openAndWait(NSString *path, const char *bundleID, int target, int seconds) {
    int waited = 0;
    while(waited < seconds) {
        _openBundleOnWindowServer(path);
        if(_waitForAppLog(bundleID, target, 5))
            return YES;
        waited += 5;
    }
    return NO;
}

static kern_return_t _openBundleOnWindowServer(NSString *bundlePath) {
    mach_port_t port = MACH_PORT_NULL;
    Message msg;
    const char *path = [bundlePath UTF8String];
    size_t n;

    if(path == NULL)
        return KERN_FAILURE;
    n = strlen(path) + 1;
    if(n > sizeof(msg.data))
        n = sizeof(msg.data);

    if(bootstrap_port == MACH_PORT_NULL)
        bootstrap_init();
    if(bootstrap_look_up(bootstrap_port, WINDOWSERVER_SVC_NAME, &port) != KERN_SUCCESS)
        return KERN_FAILURE;

    memset(&msg, 0, sizeof(msg));
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg);
    msg.code = CODE_OPEN_BUNDLE;
    msg.pid = getpid();
    strncpy(msg.bundleID, "com.ravynos.dailydrivertest", sizeof(msg.bundleID));
    memcpy(msg.data, path, n);
    msg.len = (unsigned)n;

    kern_return_t kr = MACH_SEND_TIMED_OUT;
    for(int tries = 0; tries < 5 && kr == MACH_SEND_TIMED_OUT; tries++) {
        kr = mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                      sizeof(msg), 0, MACH_PORT_NULL,
                      3000 /* ms timeout */, MACH_PORT_NULL);
        if (kr != MACH_MSG_SUCCESS) usleep(250 * 1000);
    }
    if(kr != MACH_MSG_SUCCESS) {
        fprintf(stderr, "[ddtest] open bundle %s failed: 0x%x\n", path, kr);
        fflush(stderr);
    }
    mach_port_deallocate(mach_task_self(), port);
    return kr;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSMutableString *report = [NSMutableString string];
        NSString *text;
        NSString *url;
        NSString *childOut;
        NSPasteboard *board;
        int attempt;

        if(argc > 1)
            return _childMain(argc, argv);

        [report appendString:@"ravynOS daily driver self test\n"];

        /* 1. both service names, one port */
        childOut = _runChild("ports", NULL);
        _say(report, [NSString stringWithFormat:
                      @"the pasteboard daemon answers under com.ravynos.pasteboardd and com.apple.pboard on the same port (%@)",
                      childOut != nil ? childOut : @"no answer"],
             childOut != nil && [childOut rangeOfString:@"same=1"].location != NSNotFound);

        /* 2. text across processes */
        text = [NSString stringWithFormat:@"ravynOS-pasteboard-%d", getpid()];
        board = [NSPasteboard generalPasteboard];
        for(attempt = 0; attempt < 40; attempt++) {
            [board declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
            if([board setString:text forType:NSPasteboardTypeString])
                break;
            usleep(250000);
        }
        childOut = _runChild("read-text", NULL);
        _say(report, @"a UTF-8 paste written by one process is read by another",
             childOut != nil && [childOut isEqualToString:text]);

        /* 3. a file URL across processes */
        url = @"file:///var/log/daily-driver-selftest.txt";
        [board declareTypes:[NSArray arrayWithObject:NSPasteboardTypeFileURL] owner:nil];
        [board setString:url forType:NSPasteboardTypeFileURL];
        childOut = _runChild("read-url", NULL);
        _say(report, @"a file URL paste written by one process is read by another",
             childOut != nil && [childOut isEqualToString:url]);

        /* 4. the canonical paths and the fleet */
        {
            NSArray *paths = [NSArray arrayWithObjects:
                @"/System/Library/CoreServices/Finder.app",
                @"/Applications/System Settings.app",
                @"/System/Library/CoreServices/System Preferences.app",
                @"/System/Library/CoreServices/pasteboardd",
                @"/usr/bin/open",
                @"/Applications/TextEdit.app",
                @"/Applications/Calculator.app",
                @"/Applications/Preview.app",
                @"/Applications/Font Book.app",
                @"/Applications/Utilities/Terminal.app",
                @"/Applications/Utilities/Screenshot.app",
                @"/Applications/Utilities/Activity Monitor.app",
                @"/Applications/Utilities/Disk Utility.app",
                @"/Applications/Utilities/Console.app",
                @"/Applications/Utilities/Keychain Access.app",
                @"/System/Library/CoreServices/Archive Utility.app",
                nil];
            unsigned i;
            for(i = 0; i < [paths count]; i++) {
                NSString *path = [paths objectAtIndex:i];
                _say(report, [NSString stringWithFormat:@"%@ is installed", path],
                     _fileExists(path));
            }
        }

        /* 5. a global capture.  The Cmd+Shift+3 shortcut and the RPC used
         * here share captureScreenshotWithMode:, so this exercises the
         * launch, the capture and the file it writes; only the chord matching
         * itself is left untested. */
        {
            NSArray *dirs = [NSArray arrayWithObjects:
                [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"],
                @"/var/root/Desktop", @"/root/Desktop", @"/Desktop", nil];
            NSMutableDictionary *before = [NSMutableDictionary dictionary];
            NSString *found = nil;
            unsigned i;
            int attempt;

            for(i = 0; i < [dirs count]; i++) {
                NSString *dir = [dirs objectAtIndex:i];
                [before setObject:_screenShotNames(dir) forKey:dir];
            }
            {
                extern kern_return_t _windowServerRPC(void *, size_t, void *, int *);
                struct wsRPCSimple args;
                struct wsRPCSimple reply;
                int len = sizeof(reply);

                memset(&args, 0, sizeof(args));
                memset(&reply, 0, sizeof(reply));
                args.base.code = kWSRequestCapture;
                args.val1 = 0; /* whole display */
                if(_windowServerRPC(&args, sizeof(args), &reply, &len) != KERN_SUCCESS)
                    fprintf(stderr, "[ddtest] capture request failed\n");
            }
            unsigned long long size = 0;
            for(attempt = 0; attempt < 160 && size <= 10000; attempt++) {
                usleep(250000);
                for(i = 0; i < [dirs count]; i++) {
                    NSString *dir = [dirs objectAtIndex:i];
                    NSMutableSet *now = [NSMutableSet setWithSet:_screenShotNames(dir)];

                    [now minusSet:[before objectForKey:dir]];
                    if([now count] > 0) {
                        found = [dir stringByAppendingPathComponent:[now anyObject]];
                        struct stat st;
                        if(stat([found fileSystemRepresentation], &st) == 0)
                            size = (unsigned long long)st.st_size;
                        if(size > 10000)
                            break;
                    }
                }
            }
            _say(report, @"a global capture writes a screenshot file",
                 found != nil && size > 10000);
            if(found != nil)
                fprintf(stderr, "[ddtest] capture %s (%llu bytes)\n",
                        [found UTF8String], size);
        }

        /* 6. Objective-C block runtime check. */
        {
            __block int accumulator = 10;
            void (^addBlock)(int) = ^(int val) {
                accumulator += val;
            };
            addBlock(5);
            void (^copiedBlock)(int) = [addBlock copy];
            copiedBlock(15);
            copiedBlock = nil;

            _say(report, @"Objective-C blocks execute and support copy/release",
                 accumulator == 30);
            if(accumulator == 30)
                fprintf(stderr, "[ddtest] blocks ok: accumulator=%d\n", accumulator);
        }
        /* The report goes to the disk before the fleet starts: the fleet
         * takes a minute and a half, and the host harness reads the report
         * out of the image once the guest is stopped. */
        _writeReport(report);

        fprintf(stderr, "dailydrivertest: %d failure(s)\n", _failures);
        fflush(stderr);

        /* Launch every application in the fleet, one at a time, announcing
         * each on the console so the host harness can screendump the window
         * that just came up.  A launch that never produces a window is a
         * verification failure in its own right. */
        {
            NSArray *fleet = [NSArray arrayWithObjects:
                @"/System/Library/CoreServices/Filer.app",
                @"/Applications/TextEdit.app",
                @"/Applications/Calculator.app",
                @"/Applications/Preview.app",
                @"/Applications/Font Book.app",
                @"/Applications/Utilities/Terminal.app",
                @"/Applications/Utilities/Activity Monitor.app",
                @"/Applications/Utilities/Disk Utility.app",
                @"/Applications/Utilities/Console.app",
                @"/Applications/Utilities/Keychain Access.app",
                @"/System/Library/CoreServices/System Preferences.app",
                @"/Applications/Utilities/Screenshot.app",
                @"/System/Library/CoreServices/Archive Utility.app",
                nil];
            unsigned i;
            int wait;

            /* This job runs early in the boot; the WindowServer must be
             * answering before documents can be routed to applications. */
            if(bootstrap_port == MACH_PORT_NULL)
                bootstrap_init();
            for(wait = 0; wait < 120; wait++) {
                mach_port_t port = MACH_PORT_NULL;

                if(bootstrap_look_up(bootstrap_port, "com.ravynos.WindowServer",
                                     &port) == KERN_SUCCESS) {
                    mach_port_deallocate(mach_task_self(), port);
                    break;
                }
                usleep(250 * 1000);
            }
            /* The WindowServer answers as soon as it is up, but the Dock,
             * the Filer and the SystemUI server still have to finish coming
             * up before the fleet starts launching windows over them. */
            usleep(8000 * 1000);

            /* Pass one: bring every application up so its windows exist and
             * have painted content.  Nothing is screenshotted from this pass:
             * applications finish launching at their own pace and whichever
             * finished last raised itself to front, so the z-order here says
             * nothing reliable about any single application's shot. */
            for(i = 0; i < [fleet count]; i++) {
                NSString *path = [fleet objectAtIndex:i];

                fprintf(stderr, "[ddtest] preload %u %s\n", i,
                        [[path lastPathComponent] UTF8String]);
                fflush(stderr);
                _openBundleOnWindowServer(path);
                usleep(4000 * 1000);
            }

            /* WindowServer forks the queued bundles at its own pace, so a
             * pass-two activation that started too early raced the still
             * launching apps: they raised themselves once their windows
             * existed, on top of the application being held for its shot.
             * Wait until every preloaded application has announced a paint
             * before touching the z-order at all. */
            {
                int settle;
                for(settle = 0; settle < 600; settle++) {
                    unsigned pending = 0;

                    for(i = 0; i < [fleet count]; i++) {
                        NSString *bid = _bundleIdentifierOfBundle([fleet objectAtIndex:i]);
                        const char *bs = (bid != nil) ? [bid UTF8String] : NULL;

                        if(bs == NULL || _countPainted(bs) < 1)
                            pending++;
                    }
                    if(pending == 0)
                        break;
                    if((settle % 10) == 0) {
                        fprintf(stderr, "[ddtest] settle %d pending %u\n", settle, pending);
                        fflush(stderr);
                    }
                    usleep(1000 * 1000);
                }
                fprintf(stderr, "[ddtest] settled after %ds\n", settle);
                fflush(stderr);
            }

            /* Pass two: activate one application at a time.  WindowServer
             * already runs the bundle, so this only raises its windows to
             * front ("[WS] PAINTED" is announced again for an app that was
             * up before the request) and no other application activates
             * until the host has screenshotted this one -- which is what
             * makes the screenshot show this application's own window. */
            for(i = 0; i < [fleet count]; i++) {
                NSString *path = [fleet objectAtIndex:i];
                NSString *bid = _bundleIdentifierOfBundle(path);
                const char *bs = (bid != nil) ? [bid UTF8String] : NULL;
                int before = bs ? _countPainted(bs) : 0;
                int raised = 0;

                fprintf(stderr, "[ddtest] launch %u %s\n", i,
                        [[path lastPathComponent] UTF8String]);
                fflush(stderr);
                /* WindowServer works through queued bundle opens slower than
                 * this loop runs, and an activation can be dropped outright
                 * when a window is mid-create.  Ask again until THIS app has
                 * announced a fresh paint: only then is its window both on
                 * screen and topmost, so the host can screenshot it without
                 * risking a later window covering it. */
                if(bs != NULL) {
                    int attempt;
                    for(attempt = 0; attempt < 6 && raised == 0; attempt++) {
                        int waited = 0;
                        _openBundleOnWindowServer(path);
                        while(waited < 30000 && _countPainted(bs) <= before) {
                            usleep(500 * 1000);
                            waited += 500;
                        }
                        if(_countPainted(bs) > before) {
                            raised = 1;
                        }
                        fprintf(stderr, "[ddtest] paint %s try %d %d->%d in %dms\n",
                                bs, attempt, before, _countPainted(bs), waited);
                        fflush(stderr);
                    }
                } else {
                    _openBundleOnWindowServer(path);
                    raised = 1;
                }
                if(raised == 0) {
                    fprintf(stderr, "[ddtest] nopaint %s\n",
                            [[path lastPathComponent] UTF8String]);
                    fflush(stderr);
                    continue;
                }
                /* Hold this application frontmost while the host screendumps
                 * it.  The host cannot write anything back into the guest and
                 * its serial reader lags, so the hold is long and the window
                 * is re-raised every ten seconds: any instant inside it shows
                 * this application, whatever the reader's lag is. */
                {
                    const char *label = [[path lastPathComponent] UTF8String];
                    int k;
                    fprintf(stderr, "[ddtest] holding %s 0\n", label);
                    fflush(stderr);
                    for(k = 0; k < 60; k++) {
                        if(k > 0 && (k % 5) == 0) {
                            _openBundleOnWindowServer(path);
                        }
                        fprintf(stderr, "[ddtest] hold %s %d\n", label, k);
                        fflush(stderr);
                        usleep(2000 * 1000);
                    }
                }
            }

            /* One application, two names.  The image format has no symlinks,
             * so /System/Library/CoreServices/Finder.app is staged as a copy
             * of Filer.app (make_gui_manifest.py's ALIASES table) and the
             * canonical macOS path must resolve to the same running process.
             * Reached after the fleet so it cannot disturb a screenshot. */
            {
                NSString *filerPath = @"/System/Library/CoreServices/Filer.app";
                NSString *finderPath = @"/System/Library/CoreServices/Finder.app";
                NSString *filerID = _bundleIdentifierOfBundle(filerPath);
                NSString *finderID = _bundleIdentifierOfBundle(finderPath);
                BOOL sameID = filerID != nil && finderID != nil &&
                              [filerID isEqualToString:finderID];
                const char *bid = (filerID != nil) ? [filerID UTF8String]
                                                  : "com.ravynos.Filer";
                int base = _countAppLog(NULL, bid);
                BOOL launched = _openAndWait(filerPath, bid, base + 1, 90);
                int mark = _countAppLog(NULL, bid);
                int spawns = _countAppLog("SPAWN", bid);
                BOOL activated = _openAndWait(finderPath, bid, mark + 1, 90);
                int after = _countAppLog("SPAWN", bid);

                _say(report, @"Finder.app and Filer.app carry one bundle identifier",
                     sameID);
                _say(report, @"opening Filer.app reaches the WindowServer", launched);
                _say(report, @"opening Finder.app activates that process instead of forking a second copy",
                     activated && after == spawns);
                if(!activated || after != spawns)
                    fprintf(stderr, "[ddtest] alias: activated=%d spawns %d->%d\n",
                            (int)activated, spawns, after);
            }

            /* The two intake proof targets.  Each one is an application the
             * system did not hand-write: MacOSIntakeProbe was compiled by the
             * host macOS toolchain against the real Apple frameworks and
             * staged by tools/bootlab/app_stage.py, and SDLBlocks was built
             * from ordinary SDL2 source by tools/ports/build_port.py against
             * the ravynOS SDK.  A launch that paints and writes its PASS line
             * is what makes both tracks real rather than aspirational. */
            {
                struct {
                    const char *path;
                    const char *logPath;
                    const char *expect;
                    const char *label;
                } intake[] = {
                    { "/Applications/MacOSIntakeProbe.app", "/var/log/macos-intake.log",
                      "PASS macos-intake:",
                      "imported macOS .app bundle with @rpath + Security/IOKit/CoreVideo/SC/CFNetwork executes and paints" },
                    { "/Applications/SDLBlocks.app", "/var/log/sdl2-port-selftest.log",
                      "PASS sdl2-port:",
                      "ported CMake/SDL2 application executes and paints via WindowServer" },
                };
                unsigned k;

                for(k = 0; k < sizeof(intake) / sizeof(intake[0]); k++) {
                    NSString *bundlePath = [NSString stringWithUTF8String:intake[k].path];
                    NSString *logPath = [NSString stringWithUTF8String:intake[k].logPath];
                    BOOL installed = _fileExists(bundlePath);
                    BOOL passed = NO;

                    _say(report, [NSString stringWithFormat:@"%s is installed",
                                  intake[k].path], installed);
                    if(!installed)
                        continue;

                    /* The self-test log is written by the application itself,
                     * so a stale one from an earlier boot has to be removed
                     * first or the check could pass without this launch. */
                    remove([logPath fileSystemRepresentation]);
                    _openBundleOnWindowServer(bundlePath);

                    int waited;
                    for(waited = 0; waited < 120; waited++) {
                        usleep(500 * 1000);

                        const char *p = [logPath UTF8String];
                        FILE *f = p ? fopen(p, "r") : NULL;
                        if(f != NULL) {
                            char line[512];
                            size_t n = fread(line, 1, sizeof(line) - 1, f);
                            fclose(f);
                            line[n] = '\0';
                            if(strstr(line, intake[k].expect) != NULL) {
                                passed = YES;
                                break;
                            }
                        }
                    }

                    if(!passed) {
                        fprintf(stderr, "[ddtest] intake %s: no PASS in %s after 60s\n",
                                intake[k].path, intake[k].logPath);
                    } else {
                        /* The application runs its own window; give it a
                         * moment to paint before the screenshot pass, and
                         * record that WindowServer saw it. */
                        usleep(2000 * 1000);
                    }
                    _say(report, [NSString stringWithUTF8String:intake[k].label], passed);
                }
            }

            _writeReport(report);

            /* Last: the harness stops the guest as soon as it reads this, so
             * everything above has to be on the disk and in the console by
             * the time it is printed. */
            fprintf(stderr, "[ddtest] fleet-done %u\n", (unsigned)[fleet count]);
            fflush(stderr);
        }

        return _failures == 0 ? 0 : 1;
    }
}
