#import <AppKit/AppKit.h>
#import "PreviewCanvasView.h"
#import "PDFRenderer.h"

@interface PreviewDocument : NSDocument
@property (nonatomic, retain) NSWindow *window;
@property (nonatomic, retain) NSScrollView *scrollView;
@property (nonatomic, retain) PreviewCanvasView *canvasView;
@property (nonatomic, retain) NSTableView *sidebarTable;
@property (nonatomic, retain) NSTextField *searchField;
@property (nonatomic, retain) NSPopUpButton *formatPopup;
@property (nonatomic, assign) CGImageRef image;
@property (nonatomic, retain) PDFRenderer *pdfRenderer;
@property (nonatomic, retain) NSMutableArray *thumbnails;
@property (nonatomic, assign) BOOL cropMode;

- (void)buildUI;
- (void)buildMenu;

- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)actualSize:(id)sender;
- (void)zoomToFit:(id)sender;
- (void)rotateLeft:(id)sender;
- (void)rotateRight:(id)sender;
- (void)flipHorizontal:(id)sender;
- (void)flipVertical:(id)sender;
- (void)crop:(id)sender;
- (void)exportAs:(id)sender;
- (void)find:(id)sender;
- (void)findNext:(id)sender;
- (void)copySelection:(id)sender;
@end