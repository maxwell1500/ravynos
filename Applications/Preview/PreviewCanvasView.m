#import "PreviewCanvasView.h"
 #ifndef MIN
 #define MIN(a,b) ((a)<(b)?(a):(b))
 #endif

@implementation PreviewCanvasView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _zoom = 1.0;
        _rotation = 0;
        _flipH = NO;
        _flipV = NO;
        _selectionRect = NSZeroRect;
        _panOffset = NSZeroPoint;
    }
    return self;
}

- (BOOL)isFlipped { return NO; }

- (BOOL)acceptsFirstResponder { return YES; }

- (void)setImage:(CGImageRef)image {
    _image = image;
    [self setNeedsDisplay:YES];
}

- (void)setPdf:(PDFRenderer *)pdf {
    _pdf = pdf;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor whiteColor] setFill];
    NSRectFill(dirtyRect);

    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, _panOffset.x, _panOffset.y);
    CGContextScaleCTM(ctx, _zoom, _zoom);

    if (_image) {
        size_t w = CGImageGetWidth(_image);
        size_t h = CGImageGetHeight(_image);
        CGContextTranslateCTM(ctx, (CGFloat)w/2.0, (CGFloat)h/2.0);
        CGContextRotateCTM(ctx, _rotation * 90.0 * M_PI / 180.0);
        if (_flipH) CGContextScaleCTM(ctx, -1, 1);
        if (_flipV) CGContextScaleCTM(ctx, 1, -1);
        CGContextTranslateCTM(ctx, -(CGFloat)w/2.0, -(CGFloat)h/2.0);
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), _image);
    } else if (_pdf) {
        CGSize sz = [_pdf pageSizeAtIndex:_pageIndex];
        CGContextTranslateCTM(ctx, sz.width/2.0, sz.height/2.0);
        CGContextRotateCTM(ctx, _rotation * 90.0 * M_PI / 180.0);
        if (_flipH) CGContextScaleCTM(ctx, -1, 1);
        if (_flipV) CGContextScaleCTM(ctx, 1, -1);
        CGContextTranslateCTM(ctx, -sz.width/2.0, -sz.height/2.0);
        [_pdf drawPageAtIndex:_pageIndex inContext:ctx rect:CGRectMake(0,0,sz.width,sz.height)];
    }
    CGContextRestoreGState(ctx);

    if (_pdf != nil && [_highlightQuery length] > 0) {
        /* Search result banner over the page. */
        [[NSColor colorWithCalibratedRed:1.0 green:0.92 blue:0.2 alpha:0.45] setFill];
        NSRectFill(NSMakeRect(0, [self bounds].size.height - 26,
                              [self bounds].size.width, 22));
        [[NSColor colorWithCalibratedRed:0.45 green:0.35 blue:0.0 alpha:1.0] setStroke];
        NSFrameRect(NSMakeRect(0, [self bounds].size.height - 26,
                               [self bounds].size.width, 22));
        NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:12],
                                 NSForegroundColorAttributeName: [NSColor blackColor] };
        [[NSString stringWithFormat:@"Found \u201c%@\u201d on page %lu",
            _highlightQuery, (unsigned long)_pageIndex + 1]
            drawAtPoint:NSMakePoint(8, [self bounds].size.height - 22)
          withAttributes:attrs];
    }

    if (!NSEqualRects(_selectionRect, NSZeroRect)) {
        [[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:1.0 alpha:0.15] setFill];
        NSRectFill(_selectionRect);
        [[NSColor blueColor] setStroke];
        NSFrameRect(_selectionRect);
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if (_cropMode) {
        _selecting = YES;
        _selStart = p;
        _selectionRect = NSMakeRect(p.x, p.y, 0, 0);
    } else {
        _selStart = p;
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if (_cropMode && _selecting) {
        CGFloat x = MIN(_selStart.x, p.x);
        CGFloat y = MIN(_selStart.y, p.y);
        CGFloat w = fabs(p.x - _selStart.x);
        CGFloat h = fabs(p.y - _selStart.y);
        _selectionRect = NSMakeRect(x, y, w, h);
        [self setNeedsDisplay:YES];
    } else {
        _panOffset.x += p.x - _selStart.x;
        _panOffset.y += p.y - _selStart.y;
        _selStart = p;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _selecting = NO;

    /* Text selection without a glyph hit test: take the lines of the page
     * text whose vertical band overlaps the dragged rectangle. */
    if (_pdf != nil && !NSIsEmptyRect(_selectionRect)) {
        NSString *text = [_pdf textForPageAtIndex:_pageIndex];
        NSArray *lines = [text componentsSeparatedByString:@"\n"];
        CGFloat bandTop = NSMaxY(_selectionRect);
        CGFloat bandBottom = NSMinY(_selectionRect);
        NSMutableString *picked = [NSMutableString string];
        NSUInteger i;

        for (i = 0; i < [lines count]; i++) {
            CGFloat y = 1.0 - ((CGFloat)i + 0.5) / (CGFloat)[lines count];
            CGFloat scaled = y * [self bounds].size.height;
            if (scaled >= bandBottom && scaled <= bandTop)
                [picked appendFormat:@"%@\n", [lines objectAtIndex:i]];
        }
        [self setSelectedText:picked];
    }
}

- (void)zoomIn { _zoom *= 1.25; if (_zoom > 8) _zoom = 8; [self setNeedsDisplay:YES]; }
- (void)zoomOut { _zoom /= 1.25; if (_zoom < 0.1) _zoom = 0.1; [self setNeedsDisplay:YES]; }
- (void)actualSize { _zoom = 1.0; [self setNeedsDisplay:YES]; }
- (void)zoomToFit {
    NSRect b = [self bounds];
    CGSize sz = _image ? CGSizeMake(CGImageGetWidth(_image), CGImageGetHeight(_image)) : (_pdf ? [_pdf pageSizeAtIndex:_pageIndex] : CGSizeMake(100,100));
    CGFloat sx = b.size.width / sz.width;
    CGFloat sy = b.size.height / sz.height;
    _zoom = MIN(sx, sy);
    if (_zoom < 0.1) _zoom = 0.1;
    [self setNeedsDisplay:YES];
}
- (void)rotateLeft { _rotation = (_rotation + 3) % 4; [self setNeedsDisplay:YES]; }
- (void)rotateRight { _rotation = (_rotation + 1) % 4; [self setNeedsDisplay:YES]; }
- (void)flipHorizontal { _flipH = !_flipH; [self setNeedsDisplay:YES]; }
- (void)flipVertical { _flipV = !_flipV; [self setNeedsDisplay:YES]; }

@end