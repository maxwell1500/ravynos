// openurl.m -- ask NSWorkspace to open an http URL; LaunchServices must route
// it to Firefox (registered for http/https). Prints OPENURL-OK on success.
#import <Cocoa/Cocoa.h>
#import <stdio.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *u = argc > 1 ? argv[1] : "http://10.0.2.2:8123/http-index.html";
        NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:u]];
        if (!url) { printf("OPENURL-FAIL bad url\n"); return 1; }
        CFStringRef h = LSCopyDefaultHandlerForURLScheme(CFSTR("http"));
        printf("HANDLER-http: %s\n", h ? [[(NSString *)h description] UTF8String] : "(null)");
        if (h) CFRelease(h);
        CFArrayRef all = LSCopyAllHandlersForURLScheme(CFSTR("http"));
        printf("ALLHANDLERS: %d\n", all ? (int)CFArrayGetCount(all) : -1);
        if (all) CFRelease(all);
        CFURLRef au = LSCopyDefaultApplicationURLForURL((CFURLRef)url, 0, NULL);
        printf("APPURL: %s\n", au ? [[(NSURL *)au absoluteString] UTF8String] : "(null)");
        if (au) CFRelease(au);
        BOOL ok = [[NSWorkspace sharedWorkspace] openURL:url];
        printf("OPENURL-%s %s\n", ok ? "OK" : "FAIL", u);
        return ok ? 0 : 1;
    }
}
