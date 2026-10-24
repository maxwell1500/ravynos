#import "PreviewDocument.h"
#import <CoreGraphics/CGImageSource.h>
#import <CoreGraphics/CGImageDestination.h>

@implementation PreviewDocument

- (id)init {
    self = [super init];
    if (self) {
        _thumbnails = [[NSMutableArray alloc] init];
        _cropMode = NO;
    }
    return self;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error {
    const unsigned char *b = [data bytes];
    BOOL isPDF = (data.length > 4 && b[0]=='%' && b[1]=='P' && b[2]=='D' && b[3]=='F');
    NSString *ext = [[[self fileURL] path] pathExtension];
    if (isPDF || [ext caseInsensitiveCompare:@"pdf"] == NSOrderedSame) {
        _pdfRenderer = [[PDFRenderer alloc] initWithData:data];
    } else {
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (src) {
            _image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
            CFRelease(src);
        }
    }
    return YES;
}

- (void)makeWindowControllers {
    [self buildMenu];
    NSRect frame = NSMakeRect(100, 100, 1000, 700);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [_window setTitle:[self displayName]];
    [self buildUI];
    NSWindowController *wc = [[NSWindowController alloc] initWithWindow:_window];
    [wc setDocument:self];
    [self addWindowController:wc];
    [_window makeKeyAndOrderFront:nil];
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *appItem = [mainMenu addItemWithTitle:@"Preview" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Preview"];
    [appMenu addItemWithTitle:@"Quit Preview" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];

    NSMenuItem *fileItem = [mainMenu addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Export As…" action:@selector(exportAs:) keyEquivalent:@"S"];
    NSMenuItem *exportItem = [[fileMenu itemArray] lastObject];
    [exportItem setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [fileItem setSubmenu:fileMenu];

    NSMenuItem *editItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copySelection:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Find…" action:@selector(find:) keyEquivalent:@"f"];
    [editMenu addItemWithTitle:@"Find Next" action:@selector(findNext:) keyEquivalent:@"g"];
    [editItem setSubmenu:editMenu];

    NSMenuItem *viewItem = [mainMenu addItemWithTitle:@"View" action:NULL keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [viewMenu addItemWithTitle:@"Actual Size" action:@selector(actualSize:) keyEquivalent:@"0"];
    [viewMenu addItemWithTitle:@"Zoom to Fit" action:@selector(zoomToFit:) keyEquivalent:@"9"];
    [viewMenu addItemWithTitle:@"Rotate Left" action:@selector(rotateLeft:) keyEquivalent:@"l"];
    [viewMenu addItemWithTitle:@"Rotate Right" action:@selector(rotateRight:) keyEquivalent:@"r"];
    [viewMenu addItemWithTitle:@"Flip Horizontal" action:@selector(flipHorizontal:) keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Flip Vertical" action:@selector(flipVertical:) keyEquivalent:@""];
    [viewMenu addItemWithTitle:@"Crop" action:@selector(crop:) keyEquivalent:@"k"];
    [viewItem setSubmenu:viewMenu];

    [[NSApplication sharedApplication] setMainMenu:mainMenu];
}

- (void)buildUI {
    NSView *content = [_window contentView];
    NSRect cb = [content bounds];

    // Sidebar
    NSScrollView *sideScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 140, cb.size.height)];
    _sidebarTable = [[NSTableView alloc] initWithFrame:[sideScroll bounds]];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"page"];
    [col setWidth:140];
    [_sidebarTable addTableColumn:col];
    [_sidebarTable setDataSource:self];
    [_sidebarTable setDelegate:self];
    [sideScroll setDocumentView:_sidebarTable];
    [sideScroll setHasVerticalScroller:YES];
    [content addSubview:sideScroll];

    // Toolbar: zoom, rotate, crop, search
    NSRect barFrame = NSMakeRect(140, cb.size.height - 36, cb.size.width - 140, 36);
    NSView *bar = [[NSView alloc] initWithFrame:barFrame];
    NSArray *titles = @[@"-", @"+", @"↺", @"↻", @"Crop"];
    NSArray *actions = @[@"zoomOut:", @"zoomIn:", @"rotateLeft:", @"rotateRight:", @"crop:"];
    CGFloat bx = 8;
    NSUInteger bi;

    for (bi = 0; bi < [titles count]; bi++) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(bx, 5, 34, 24)];
        [button setTitle:[titles objectAtIndex:bi]];
        [button setTarget:self];
        [button setAction:NSSelectorFromString([actions objectAtIndex:bi])];
        [bar addSubview:button];
        bx += 38;
    }

    _searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(bx + 16, 6, 180, 24)];
    [[_searchField cell] setPlaceholderString:@"Search"];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(findNext:)];
    [bar addSubview:_searchField];
    {
        NSButton *find = [[NSButton alloc] initWithFrame:NSMakeRect(bx + 202, 5, 60, 24)];
        [find setTitle:@"Find"];
        [find setTarget:self];
        [find setAction:@selector(findNext:)];
        [bar addSubview:find];
    }
    [content addSubview:bar];

    // Canvas scroll
    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(140, 0, cb.size.width-140, cb.size.height - 36)];
    _canvasView = [[PreviewCanvasView alloc] initWithFrame:NSMakeRect(0,0,cb.size.width-140, cb.size.height)];
    [_canvasView setImage:_image];
    [_canvasView setPdf:_pdfRenderer];
    [_scrollView setDocumentView:_canvasView];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:YES];
    [content addSubview:_scrollView];

    // thumbnails
    [self buildThumbnails];
    [_sidebarTable reloadData];
}

- (void)buildThumbnails {
    [_thumbnails removeAllObjects];
    if (_pdfRenderer) {
        for (size_t i = 0; i < _pdfRenderer.pageCount; i++) {
            NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(120, 120)];
            [img lockFocus];
            CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
            [[NSColor whiteColor] setFill];
            NSRectFill(NSMakeRect(0,0,120,120));
            [_pdfRenderer drawPageAtIndex:i inContext:ctx rect:NSMakeRect(10,10,100,100)];
            [img unlockFocus];
            [_thumbnails addObject:img];
        }
    } else if (_image) {
        NSImage *img = [[NSImage alloc] initWithCGImage:_image size:NSMakeSize(CGImageGetWidth(_image), CGImageGetHeight(_image))];
        [_thumbnails addObject:img];
    }
}

// Table data source
 - (int)numberOfRowsInTableView:(NSTableView *)tableView {
    if (_pdfRenderer) return _pdfRenderer.pageCount;
    return _image ? 1 : 0;
}

 - (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row {
    if (_pdfRenderer) return [NSString stringWithFormat:@"Page %ld", (long)row + 1];
    return @"Image";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [_sidebarTable selectedRow];
    if (row < 0) return;
    if (_pdfRenderer) {
        [_canvasView setPageIndex:row];
        [_canvasView setNeedsDisplay:YES];
    }
}

// Actions
- (void)zoomIn:(id)sender { [_canvasView zoomIn]; }
- (void)zoomOut:(id)sender { [_canvasView zoomOut]; }
- (void)actualSize:(id)sender { [_canvasView actualSize]; }
- (void)zoomToFit:(id)sender { [_canvasView zoomToFit]; }
/* Transform the pixels, not the view's CTM: Crop and Export As read _image,
 * so a view-only rotation looked right on screen and was silently discarded
 * on save. */
- (CGImageRef)createTransformedImage:(CGImageRef)src
                       rotateDegrees:(int)degrees
                               flipH:(BOOL)flipH
                               flipV:(BOOL)flipV {
    if (src == NULL)
        return NULL;

    size_t w = CGImageGetWidth(src);
    size_t h = CGImageGetHeight(src);
    BOOL quarterTurn = ((degrees % 180) != 0);
    size_t outW = quarterTurn ? h : w;
    size_t outH = quarterTurn ? w : h;
    CGColorSpaceRef space = CGImageGetColorSpace(src);
    CGContextRef ctx;
    CGImageRef result;

    if (space == NULL)
        space = CGColorSpaceCreateDeviceRGB();
    else
        CGColorSpaceRetain(space);
    ctx = CGBitmapContextCreate(NULL, outW, outH, 8, 0, space,
        kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (ctx == NULL)
        return NULL;

    CGContextTranslateCTM(ctx, outW / 2.0, outH / 2.0);
    CGContextRotateCTM(ctx, degrees * M_PI / 180.0);
    if (flipH) CGContextScaleCTM(ctx, -1, 1);
    if (flipV) CGContextScaleCTM(ctx, 1, -1);
    CGContextTranslateCTM(ctx, -w / 2.0, -h / 2.0);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), src);

    result = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return result;
}

- (void)applyTransformDegrees:(int)degrees flipH:(BOOL)flipH flipV:(BOOL)flipV {
    if (_image == NULL)
        return;

    CGImageRef transformed = [self createTransformedImage:_image
                                            rotateDegrees:degrees
                                                    flipH:flipH
                                                    flipV:flipV];
    if (transformed == NULL)
        return;

    CGImageRelease(_image);
    _image = transformed;
    [_canvasView setImage:_image];
    [_canvasView setRotation:0];
    [_canvasView setFlipH:NO];
    [_canvasView setFlipV:NO];
    [_canvasView setNeedsDisplay:YES];
}

- (void)rotateLeft:(id)sender { [self applyTransformDegrees:-90 flipH:NO flipV:NO]; }
- (void)rotateRight:(id)sender { [self applyTransformDegrees:90 flipH:NO flipV:NO]; }
- (void)flipHorizontal:(id)sender { [self applyTransformDegrees:0 flipH:YES flipV:NO]; }
- (void)flipVertical:(id)sender { [self applyTransformDegrees:0 flipH:NO flipV:YES]; }

- (void)crop:(id)sender {
    _cropMode = !_cropMode;
    [_canvasView setCropMode:_cropMode];
    if (!_cropMode && !NSEqualRects([_canvasView selectionRect], NSZeroRect)) {
        // perform crop on image
        if (_image) {
            NSRect r = [_canvasView selectionRect];
            r.origin.x -= _canvasView.panOffset.x;
            r.origin.y -= _canvasView.panOffset.y;
            r.origin.x /= _canvasView.zoom;
            r.origin.y /= _canvasView.zoom;
            r.size.width /= _canvasView.zoom;
            r.size.height /= _canvasView.zoom;
            CGRect rect = CGRectMake(r.origin.x, r.origin.y, r.size.width, r.size.height);
            CGImageRef cropped = CGImageCreateWithImageInRect(_image, rect);
            if (cropped) {
                CGImageRelease(_image);
                _image = cropped;
                [_canvasView setImage:_image];
            }
            [_canvasView setSelectionRect:NSZeroRect];
            [_canvasView setNeedsDisplay:YES];
        }
    }
}

- (void)exportAs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,120,24) pullsDown:NO];
    [popup addItemsWithTitles:@[@"PNG",@"JPEG",@"TIFF"]];
    [panel setAccessoryView:popup];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        NSURL *url = [panel URL];
        NSString *fmt = [popup titleOfSelectedItem];
        CFStringRef type = CFSTR("public.png");
        if ([fmt isEqualToString:@"JPEG"]) type = CFSTR("public.jpeg");
        else if ([fmt isEqualToString:@"TIFF"]) type = CFSTR("public.tiff");
        CGImageRef img = _image;
        CGImageRef rendered = NULL;

        if (img == NULL && _pdfRenderer != nil) {
            /* Export the current PDF page: rasterize it at page size. */
            CGSize sz = [_pdfRenderer pageSizeAtIndex:[_canvasView pageIndex]];
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)sz.width,
                (size_t)sz.height, 8, 0, space, kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(space);
            if (ctx != NULL) {
                [[NSColor whiteColor] setFill];
                CGContextFillRect(ctx, CGRectMake(0, 0, sz.width, sz.height));
                [_pdfRenderer drawPageAtIndex:[_canvasView pageIndex]
                                    inContext:ctx
                                         rect:CGRectMake(0, 0, sz.width, sz.height)];
                rendered = CGBitmapContextCreateImage(ctx);
                CGContextRelease(ctx);
                img = rendered;
            }
        }
        if (img) {
            CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, type, 1, NULL);
            if (dest) {
                CGImageDestinationAddImage(dest, img, NULL);
                CGImageDestinationFinalize(dest);
                CFRelease(dest);
            }
        }
        if (rendered != NULL)
            CGImageRelease(rendered);
    }
}

- (void)find:(id)sender {
    // store search query from search field if present; use a simple prompt via field
    [self findNext:sender];
}

- (void)findNext:(id)sender {
    if (!_pdfRenderer) return;
    if (_pdfRenderer.pageCount == 0) return; /* nothing to search, and the modulo below would divide by zero */
    NSString *query = [_searchField stringValue];
    if ([query length] == 0) return;
    NSUInteger start = [_canvasView pageIndex] + 1;
    for (NSUInteger i = 0; i < _pdfRenderer.pageCount; i++) {
        NSUInteger idx = (start + i) % _pdfRenderer.pageCount;
        NSString *t = [_pdfRenderer textForPageAtIndex:idx];
        if ([t rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [_canvasView setPageIndex:idx];
            [_canvasView setHighlightQuery:query];
            [_canvasView setNeedsDisplay:YES];
            [_sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
            return;
        }
    }
}

- (void)copySelection:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *t = nil;

    if (_pdfRenderer) {
        t = [_canvasView selectedText];
        if ([t length] == 0)
            t = [_pdfRenderer textForPageAtIndex:[_canvasView pageIndex]];
    }
    [pb clearContents];
    if (t != nil)
        [pb setString:t forType:NSPasteboardTypeString];
}

- (void)openDocument:(id)sender {
    [[NSDocumentController sharedDocumentController] openDocument:sender];
}

- (void)performClose:(id)sender {
    [_window performClose:sender];
}

@end