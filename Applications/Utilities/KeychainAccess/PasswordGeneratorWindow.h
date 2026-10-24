#import <AppKit/AppKit.h>

@interface PasswordGeneratorWindow : NSObject
- (void)show;
- (NSString *)generatedPassword;
@end