#import <AppKit/AppKit.h>

@interface TextDocument : NSDocument
@property (nonatomic, assign) NSStringEncoding encoding;
@property (nonatomic, assign) BOOL richTextMode;
@property (nonatomic, retain) NSTextStorage *textStorage;

- (void)setEncoding:(NSStringEncoding)encoding;
- (NSStringEncoding)encoding;
@end