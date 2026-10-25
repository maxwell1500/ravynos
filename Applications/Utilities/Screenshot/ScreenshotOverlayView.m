#import "ScreenshotOverlayView.h"
#import <CoreFoundation/CoreFoundation.h>
#import <LaunchServices/LaunchServices.h>
#import "WindowServer/rpc.h"
#include <sys/ipc.h>
#include <sys/shm.h>
#include <string.h>

NSString *ScreenshotWriteImageWithDestination(CGImageRef image, int destination) {
    if (image == NULL) return nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *desktop = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
    NSString *path = nil;

    if (destination != 1) {
        [fm createDirectoryAtPath:desktop withIntermediateDirectories:YES attributes:nil error:nil];

        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd 'at' HH.mm.ss"];
        /* Milliseconds keep two captures in the same second apart. */
        NSDate *now = [NSDate date];
        int ms = (int)(([now timeIntervalSince1970] - (double)(long)[now timeIntervalSince1970]) * 1000.0);
        NSString *name = [NSString stringWithFormat:@"Screen Shot %@.%03d.png",
            [df stringFromDate:now], ms];
        path = [desktop stringByAppendingPathComponent:name];

        CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
        if (dest) {
            CGImageDestinationAddImage(dest, image, NULL);
            if (!CGImageDestinationFinalize(dest))
                fprintf(stderr, "Screenshot: PNG encode failed for %s\n", [path UTF8String]);
            CFRelease(dest);
        }
    }

    /* In-memory PNG for the pasteboard (reuse file bytes if written, encode to NSMutableData otherwise). */
    NSData *pngData = nil;
    if (path != nil) {
        pngData = [NSData dataWithContentsOfFile:path];
    }
    if (pngData == nil) {
        NSMutableData *mdata = [NSMutableData data];
        CGImageDestinationRef d2 = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)mdata, CFSTR("public.png"), 1, NULL);
        if (d2) {
            CGImageDestinationAddImage(d2, image, NULL);
            CGImageDestinationFinalize(d2);
            CFRelease(d2);
        }
        pngData = mdata;
    }

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setData:pngData forType:NSPasteboardTypePNG];
    /* No TIFF encoder is available in ravynOS CoreGraphics; the PNG bytes are
     * placed in the TIFF slot as an acceptable fallback (see report). */
    [pb setData:pngData forType:NSPasteboardTypeTIFF];

    fprintf(stderr, "Screenshot: captured %lu bytes (dest %d, path %s)\n",
            (unsigned long)[pngData length], destination,
            path != nil ? [path UTF8String] : "(clipboard only)");
    fflush(stderr);

    if (destination == 2 && path != nil)
        LSOpenCFURLRef((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);

    return path;
}

NSString *ScreenshotCaptureRect(CGRect rect) {
    CGImageRef img = CGDisplayCreateImageForRect(CGMainDisplayID(), rect);
    NSString *path = ScreenshotWriteImageWithDestination(img, 0);
    if (img) CFRelease(img);
    return path;
}

NSString *ScreenshotCaptureFull(void) {
    return ScreenshotCaptureRect(CGDisplayBounds(CGMainDisplayID()));
}

CGImageRef ScreenshotCaptureFullImage(void) {
    return CGDisplayCreateImageForRect(CGMainDisplayID(),
                                       CGDisplayBounds(CGMainDisplayID()));
}

/* Ask the WindowServer for the topmost visible application window and wrap
 * the returned shared-memory pixels in a CGImage.  Returns NULL when the RPC
 * fails, so callers can fall back to a full capture. */
CGImageRef ScreenshotCaptureWindow(uint32_t windowNumber) {
    extern kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);
    struct wsRPCSimple args;
    struct wsRPCSimple reply;
    int len = sizeof(reply);
    CGImageRef result = NULL;

    memset(&args, 0, sizeof(args));
    memset(&reply, 0, sizeof(reply));
    args.base.code = kWSWindowCreateImage;
    args.base.len = 0;
    args.val1 = windowNumber; /* 0 = the topmost window owned by another app */

    if(_windowServerRPC(&args, sizeof(args), &reply, &len) != KERN_SUCCESS)
        return NULL;
    if(reply.val1 == 0 || reply.val2 == 0 || reply.val3 == 0)
        return NULL;

    {
        int shmid = (int)reply.val1;
        size_t width = reply.val2;
        size_t height = reply.val3;
        size_t bpr = reply.val4 != 0 ? reply.val4 : width * 4;
        void *pixels = shmat(shmid, NULL, 0);

        if(pixels != NULL && pixels != (void *)-1) {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(pixels, width, height, 8, bpr,
                space, kCGImageAlphaPremultipliedFirst);
            CGColorSpaceRelease(space);
            if(ctx != NULL) {
                result = CGBitmapContextCreateImage(ctx);
                CGContextRelease(ctx);
            }
            shmdt(pixels);
        }
        shmctl(shmid, IPC_RMID, NULL);
    }
    return result;
}

CGImageRef ScreenshotCaptureTopWindow(void) {
    return ScreenshotCaptureWindow(0);
}

/* Which window a click lands on is the WindowServer's answer, not ours: the
 * same hit test dragging uses (kWSDragHitTest) returns the topmost visible
 * window under a screen point.  This is what makes "Capture Selected Window"
 * select the window the user clicked instead of whatever happens to be
 * frontmost at the moment the timer fires. */
CGImageRef ScreenshotCaptureWindowAtPoint(CGPoint point) {
    extern kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);
    struct wsRPCDragHitTest args;
    struct wsRPCDragHitTest reply;
    int len = sizeof(reply);

    memset(&args, 0, sizeof(args));
    memset(&reply, 0, sizeof(reply));
    args.base.code = kWSDragHitTest;
    args.base.len = 0;
    args.x = point.x;
    args.y = point.y;

    if(_windowServerRPC(&args, sizeof(args), &reply, &len) != KERN_SUCCESS)
        return NULL;
    if(reply.found == 0 || reply.windowID == 0)
        return NULL;
    return ScreenshotCaptureWindow(reply.windowID);
}

@implementation ScreenshotOverlayView {
    NSPoint _mouseLocation;
    int _destination;
    int _mode;
}

- (instancetype)initWithFrame:(NSRect)frame frozenImage:(CGImageRef)image {
    return [self initWithFrame:frame frozenImage:image destination:0 mode:0];
}

- (instancetype)initWithFrame:(NSRect)frame frozenImage:(CGImageRef)image
                  destination:(int)destination {
    return [self initWithFrame:frame frozenImage:image destination:destination mode:0];
}

- (instancetype)initWithFrame:(NSRect)frame frozenImage:(CGImageRef)image
                  destination:(int)destination mode:(int)mode {
    self = [super initWithFrame:frame];
    if (self) {
        if (image) CFRetain(image);
        _frozenImage = image;
        _selecting = NO;
        _selectionRect = NSZeroRect;
        _mouseLocation = NSZeroPoint;
        /* A portion used to be written with the hardcoded Desktop default:
         * the HUD offered Save to Clipboard and Preview and this path ignored
         * both. */
        _destination = destination;
        _mode = mode;
    }
    return self;
}

- (void)dealloc {
    if (_frozenImage) CFRelease(_frozenImage);
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *ta in [self trackingAreas]) [self removeTrackingArea:ta];
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:[self bounds]
                                                          options:(NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect)
                                                            owner:self userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseMoved:(NSEvent *)event {
    _mouseLocation = [event locationInWindow];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    _selStart = [event locationInWindow];
    _selecting = YES;
    _selectionRect = NSMakeRect(_selStart.x, _selStart.y, 0, 0);
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint p = [event locationInWindow];
    CGFloat x = (_selStart.x < p.x) ? _selStart.x : p.x;
    CGFloat y = (_selStart.y < p.y) ? _selStart.y : p.y;
    CGFloat w = fabs(p.x - _selStart.x);
    CGFloat h = fabs(p.y - _selStart.y);
    _selectionRect = NSMakeRect(x, y, w, h);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (_mode == 1) {
        /* Click a window.  Hide the overlay first: it covers the whole screen
         * at screen-saver level, so an unhidden overlay is what the hit test
         * would find.  The order-out RPC is answered by the WindowServer, so
         * by the time it returns the overlay is out of the hit test. */
        NSPoint click = [event locationInWindow];
        CGImageRef shot = NULL;

        [[self window] orderOut:nil];
        shot = ScreenshotCaptureWindowAtPoint(click);
        if (shot != NULL) {
            ScreenshotWriteImageWithDestination(shot, _destination);
            CGImageRelease(shot);
        } else {
            fprintf(stderr, "Screenshot: no window at %.0f,%.0f\n",
                    click.x, click.y);
            fflush(stderr);
        }
        [NSApp terminate:nil];
        return;
    }
    if (_selectionRect.size.width < 4 || _selectionRect.size.height < 4) {
    } else {
        CGImageRef full = _frozenImage;
        if (full) {
            size_t iw = CGImageGetWidth(full);
            size_t ih = CGImageGetHeight(full);
            CGFloat sx = (CGFloat)iw / self.bounds.size.width;
            CGFloat sy = (CGFloat)ih / self.bounds.size.height;
            /* Flip Y: view origin bottom-left, image origin top-left. */
            CGRect crop = CGRectMake(_selectionRect.origin.x * sx,
                                    (self.bounds.size.height - _selectionRect.origin.y - _selectionRect.size.height) * sy,
                                    _selectionRect.size.width * sx,
                                    _selectionRect.size.height * sy);
            CGImageRef cropped = CGImageCreateWithImageInRect(full, crop);
            if (cropped) {
                ScreenshotWriteImageWithDestination(cropped, _destination);
                CFRelease(cropped);
            }
        }
    }
    [[self window] orderOut:nil];
    [NSApp terminate:nil];
}

- (void)keyDown:(NSEvent *)event {
    if ([event keyCode] == 53) { /* Escape */
        [[self window] orderOut:nil];
        [NSApp terminate:nil];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    if (_frozenImage) {
        CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
        CGContextDrawImage(ctx, NSRectToCGRect(self.bounds), _frozenImage);
    } else {
        [[NSColor blackColor] setFill];
        NSRectFill(self.bounds);
    }

    if (_mode == 1) {
        NSDictionary *hint = @{NSFontAttributeName: [NSFont systemFontOfSize:15],
                               NSForegroundColorAttributeName: [NSColor whiteColor]};
        [@"Click a window to capture it   \u00b7   Esc to cancel"
            drawAtPoint:NSMakePoint(24, self.bounds.size.height - 34)
          withAttributes:hint];
        return;
    }

    /* Crosshair */
    if (!_selecting || NSEqualRects(_selectionRect, NSZeroRect)) {
        [[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:0.6] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(_mouseLocation.x, 0)
                                 toPoint:NSMakePoint(_mouseLocation.x, self.bounds.size.height)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(0, _mouseLocation.y)
                                 toPoint:NSMakePoint(self.bounds.size.width, _mouseLocation.y)];
    }

    if (_selecting && (_selectionRect.size.width > 0 || _selectionRect.size.height > 0)) {
        [[NSColor whiteColor] setStroke];
        [NSBezierPath strokeRect:_selectionRect];

        NSString *label = [NSString stringWithFormat:@"%.0f, %.0f   %.0f x %.0f",
                           _selectionRect.origin.x, _selectionRect.origin.y,
                           _selectionRect.size.width, _selectionRect.size.height];
        NSFont *font = [NSFont systemFontOfSize:12];
        NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor whiteColor]};
        NSRect pill = NSMakeRect(_selectionRect.origin.x, _selectionRect.origin.y + _selectionRect.size.height + 4, 160, 18);
        [label drawInRect:pill withAttributes:attrs];
    }
}

@end