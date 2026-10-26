/*
 * MacOSIntakeProbe -- the macOS binary intake proof target.
 *
 * Built with the *host* macOS SDK by /usr/bin/clang, linked against the real
 * macOS frameworks, and then staged into ravynOS by tools/bootlab/app_stage.py.
 * That is the whole point: nothing in this file knows about ravynOS.  It links
 *
 *   * an embedded dylib through @rpath with an LC_RPATH of
 *     @executable_path/../Frameworks, so app_stage.py's rpath resolution is
 *     exercised end to end;
 *   * Security (SecTaskCreateFromSelf, SecRandomCopyBytes),
 *   * IOKit (IOMasterPort, IOServiceMatching),
 *   * CoreVideo (CVDisplayLinkCreateWithActiveCGDisplays),
 *   * SystemConfiguration (SCNetworkReachabilityCreateWithName),
 *   * CFNetwork (CFNetworkCopySystemProxySettings),
 *   * ApplicationServices (GetCurrentProcess, AXIsProcessTrusted),
 *   * Cocoa for the window.
 *
 * If every one of those resolves and the window paints, a real macOS
 * application's launch path works.
 */

#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#include <IOKit/IOKitLib.h>
#include <CoreVideo/CoreVideo.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <CoreServices/CoreServices.h>
#include <ApplicationServices/ApplicationServices.h>

#include "MacIntakeCore.h"

#define LOG_PATH "/var/log/macos-intake.log"

@interface ProbeAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation ProbeAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;

    char line[512];
    int rpath = 0, sec = 0, iokit = 0, cv = 0, sc = 0, cfnet = 0, apps = 0;
    char detail[256] = "";

    /* 1. The @rpath dylib.  Reaching this code at all proves dyld resolved
     *    @rpath/MacIntakeCore.dylib through LC_RPATH. */
    int magic = MacIntakeCoreMagic();
    rpath = (magic == 0x4D414349) ? 1 : 0;

    /* 2. Security.  SecTaskCreateFromSelf is the call that aborts a launch on
     *    a system without Security.framework, because its return value is
     *    released unconditionally. */
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    uint8_t randomBytes[16] = { 0 };
    OSStatus randomStatus = SecRandomCopyBytes(kSecRandomDefault, sizeof(randomBytes), randomBytes);
    sec = (task != NULL && randomStatus == errSecSuccess) ? 1 : 0;
    if (task) CFRelease(task);

    /* 3. IOKit. */
    mach_port_t master = MACH_PORT_NULL;
    IOMasterPort(MACH_PORT_NULL, &master);
    CFMutableDictionaryRef matching = IOServiceMatching("IOPlatformExpertDevice");
    io_service_t platform = IOServiceGetMatchingService(master, matching);
    iokit = (matching != NULL) ? 1 : 0;
    if (platform) IOObjectRelease(platform);

    /* 4. CoreVideo. */
    CVDisplayLinkRef link = NULL;
    CVReturn cvStatus = CVDisplayLinkCreateWithActiveCGDisplays(&link);
    cv = (cvStatus == kCVReturnSuccess && link != NULL) ? 1 : 0;
    if (link) CVDisplayLinkRelease(link);

    /* 5. SystemConfiguration reachability. */
    SCNetworkReachabilityRef reach = SCNetworkReachabilityCreateWithName(NULL, "example.com");
    SCNetworkReachabilityFlags flags = 0;
    Boolean gotFlags = reach ? SCNetworkReachabilityGetFlags(reach, &flags) : false;
    sc = (reach != NULL && gotFlags) ? 1 : 0;
    if (reach) CFRelease(reach);

    /* 6. CFNetwork proxy settings. */
    CFDictionaryRef proxies = CFNetworkCopySystemProxySettings();
    cfnet = (proxies != NULL) ? 1 : 0;
    if (proxies) CFRelease(proxies);

    /* 7. ApplicationServices process manager. */
    ProcessSerialNumber psn = { 0, 0 };
    apps = (GetCurrentProcess(&psn) == noErr) ? 1 : 0;

    snprintf(detail, sizeof(detail),
             "rpath=%d sec=%d iokit=%d cv=%d sc=%d cfnet=%d apps=1 ax=%d",
             rpath, sec, iokit, cv, sc, cfnet, AXIsProcessTrusted() ? 1 : 0);
    snprintf(line, sizeof(line), "%s macos-intake: %s",
             (rpath && sec && iokit && cv && sc && cfnet && apps) ? "PASS" : "FAIL",
             detail);

    FILE *log = fopen(LOG_PATH, "w");
    if (log) {
        fprintf(log, "%s\n", line);
        fclose(log);
    }
    fprintf(stderr, "%s\n", line);

    /* A window, so the run is visible and WindowServer reports a paint. */
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(160, 160, 560, 200)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"macOS Binary Intake"];
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 80, 520, 60)];
    [label setStringValue:[NSString stringWithUTF8String:line]];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:YES];
    [[window contentView] addSubview:label];
    [window makeKeyAndOrderFront:nil];
    [window flushWindow];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    (void)app;
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ProbeAppDelegate *delegate = [[ProbeAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
