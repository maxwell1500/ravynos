#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

/* Captures `rect` (in display coordinates) of the main display, writes a PNG to
 * ~/Desktop/Screen Shot <timestamp>.png, and places the PNG bytes on the general
 * pasteboard under both NSPasteboardTypePNG and NSPasteboardTypeTIFF.
 * Returns the written file path (or nil on failure). */
NSString *ScreenshotCaptureRect(CGRect rect);

/* Full-display capture convenience. */
NSString *ScreenshotCaptureFull(void);

/* The captured image without writing it, so callers can honour a destination
 * choice (Desktop / Clipboard / Preview).  Caller releases. */
CGImageRef ScreenshotCaptureFullImage(void);
CGImageRef ScreenshotCaptureTopWindow(void);

/* Capture the window under a screen point, using the same hit test dragging
 * uses.  NULL when the point is over no capturable window. */
CGImageRef ScreenshotCaptureWindowAtPoint(CGPoint point);

/* dest: 0 = Desktop + Clipboard, 1 = Clipboard only, 2 = Desktop + Preview. */
NSString *ScreenshotWriteImageWithDestination(CGImageRef image, int destination);

@interface ScreenshotOverlayView : NSView
@property (nonatomic, assign) CGImageRef frozenImage;
@property (nonatomic, assign) NSPoint selStart;
@property (nonatomic, assign) NSRect selectionRect;
@property (nonatomic, assign) BOOL selecting;
- (instancetype)initWithFrame:(NSRect)frame frozenImage:(CGImageRef)image
                  destination:(int)destination;

/* mode: 0 = drag a rectangle, 1 = click a window. */
- (instancetype)initWithFrame:(NSRect)frame frozenImage:(CGImageRef)image
                  destination:(int)destination mode:(int)mode;

@end