/* homechain.m -- name the producer of the nil URL that crashed
 * Downloads.app via LSOpenFromURLSpec ([LSNIL] itemURLs[0] of 1 is NULL,
 * wm suite full run, corpse pid 198/201).  Prints each link of
 * Downloads.app's chain so the compat log says which one went nil. */
#import <Foundation/Foundation.h>
/* NSPlatform exists only in ravynOS Foundation; declare the two methods we
 * call so the host (Apple SDK) fixture build compiles, and the guest binds
 * the class dynamically at load like every other ObjC symbol. */
@interface NSPlatform : NSObject
+ (instancetype)currentPlatform;
- (NSString *)homeDirectory;
@end

int main(void) {
    @autoreleasepool {
        NSString *home = [[NSPlatform currentPlatform] homeDirectory];
        printf("HOMECHAIN home=%s\n", home ? [home UTF8String] : "(nil)");

        NSString *dir =
            [home stringByAppendingPathComponent:@"Downloads"];
        printf("HOMECHAIN dir=%s\n", dir ? [dir UTF8String] : "(nil)");

        NSURL *url = [NSURL fileURLWithPath:dir];
        printf("HOMECHAIN url=%s\n", url ? [[url absoluteString] UTF8String]
                                         : "(nil)");

        NSArray *urls = [NSArray arrayWithObject:url];
        printf("HOMECHAIN count=%lu\n",
               (unsigned long)[urls count]);
        for (NSUInteger i = 0; i < [urls count]; i++)
            printf("HOMECHAIN urls[%lu]=%s\n", (unsigned long)i,
                   urls[i] ? "non-nil" : "NULL");
        return 0;
    }
}
