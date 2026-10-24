#import <AppKit/AppKit.h>

@interface MarkdownHighlighter : NSObject
+ (NSAttributedString *)highlightedStringForMarkdown:(NSString *)markdown baseFont:(NSFont *)baseFont;
+ (NSAttributedString *)renderedPreviewForMarkdown:(NSString *)markdown baseFont:(NSFont *)baseFont;
@end