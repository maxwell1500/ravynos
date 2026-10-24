#import <AppKit/AppKit.h>
#import <Onyx2D/O2Font_ttf.h>

@interface FontPreviewView : NSView
@property (assign) NSInteger mode; // 0 sample, 1 repertoire, 2 info
@property (retain) NSDictionary *font;
@property (copy) NSString *sampleText;
@property (retain) NSString *validationResult;

- (void)validate;
@end