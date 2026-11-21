#import <Foundation/Foundation.h>
int main(void) {
    @autoreleasepool {
        NSURL *u = [NSURL URLWithString:@"http://10.0.2.2:8123/marker.txt"];
        NSData *d = [[NSData dataWithContentsOfURL:u] retain];
        if (d == nil) { printf("DOWNLOAD-FAIL: (nil data)\n"); return 1; }
        NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
        [d release];
        if (s != nil && [s hasPrefix:@"RAVYN-TCP-OK"]) { printf("DOWNLOAD-OK\n"); return 0; }
        printf("DOWNLOAD-FAIL: %s\n", s != nil ? [s UTF8String] : "(nil)");
        return 1;
    }
}
