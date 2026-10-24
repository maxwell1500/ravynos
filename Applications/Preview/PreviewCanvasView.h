#import <AppKit/AppKit.h>
#import "PDFRenderer.h"

@interface PreviewCanvasView : NSView
@property (nonatomic, assign) CGImageRef image;
@property (nonatomic, retain) PDFRenderer *pdf;
@property (nonatomic, assign) NSUInteger pageIndex;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) NSPoint panOffset;
@property (nonatomic, assign) NSInteger rotation; // 0..3
@property (nonatomic, assign) BOOL flipH;
@property (nonatomic, assign) BOOL flipV;
@property (nonatomic, assign) NSRect selectionRect;
@property (nonatomic, assign) BOOL selecting;
@property (nonatomic, assign) NSPoint selStart;
@property (nonatomic, assign) BOOL cropMode;
@property (nonatomic, copy) NSString *selectedText;
@property (nonatomic, copy) NSString *highlightQuery;

- (void)zoomIn;
- (void)zoomOut;
- (void)actualSize;
- (void)zoomToFit;
- (void)rotateLeft;
- (void)rotateRight;
- (void)flipHorizontal;
- (void)flipVertical;
@end