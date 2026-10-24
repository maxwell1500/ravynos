#import "FontPreviewView.h"

@implementation FontPreviewView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if(self) {
        _mode = 0;
        _sampleText = [@"The quick brown fox jumps over the lazy dog." copy];
        _validationResult = [@"Not validated" copy];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setFont:(NSDictionary *)font {
    _font = font;
    [self setNeedsDisplay:YES];
}

- (void)setMode:(NSInteger)mode {
    _mode = mode;
    [self setNeedsDisplay:YES];
}

- (void)setSampleText:(NSString *)sampleText {
    _sampleText = [sampleText copy];
    [self setNeedsDisplay:YES];
}

- (NSFont *)currentFontWithSize:(CGFloat)size {
    if(_font == nil) return [NSFont systemFontOfSize:size];
    NSString *ps = [_font objectForKey:@"PostScriptName"];
    NSFont *f = [NSFont fontWithName:ps size:size];
    if(f == nil) f = [NSFont systemFontOfSize:size];
    return f;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor whiteColor] setFill];
    NSRectFill(dirtyRect);

    if(_font == nil) {
        NSString *msg = @"Select a font";
        NSDictionary *attrs = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:14] forKey:NSFontAttributeName];
        [msg drawAtPoint:NSMakePoint(10, 10) withAttributes:attrs];
        return;
    }

    if(_mode == 0) {
        CGFloat sizes[] = {12, 18, 24, 36};
        CGFloat y = 10;
        NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789";
        for(int si = 0; si < 4; si++) {
            CGFloat sz = sizes[si];
            NSFont *f = [self currentFontWithSize:sz];
            NSDictionary *attrs = [NSDictionary dictionaryWithObject:f forKey:NSFontAttributeName];
            [alphabet drawAtPoint:NSMakePoint(10, y) withAttributes:attrs];
            y += sz + 8;
        }
        if(_sampleText != nil && [_sampleText length] > 0) {
            NSFont *f = [self currentFontWithSize:16];
            NSDictionary *attrs = [NSDictionary dictionaryWithObject:f forKey:NSFontAttributeName];
            [_sampleText drawAtPoint:NSMakePoint(10, y + 8) withAttributes:attrs];
        }
    } else if(_mode == 1) {
        /* Bordered glyph grid over printable ASCII plus Latin-1 supplement,
         * each cell labelled with its code point so a missing glyph is
         * visible as an empty cell instead of silently blank output. */
        CGFloat cell = 34;
        CGFloat x0 = 10, y0 = 10;
        int cols = (int)(([self bounds].size.width - 20) / cell);
        int row = 0, col = 0;
        NSFont *tiny = [NSFont systemFontOfSize:8];
        NSDictionary *labelAttrs = [NSDictionary dictionaryWithObject:tiny
            forKey:NSFontAttributeName];

        if(cols < 1) cols = 1;
        for(int cp = 0x20; cp <= 0xFF; cp++) {
            if(cp > 0x7E && cp < 0xA1) continue;
            NSString *ch = [NSString stringWithFormat:@"%C", (unichar)cp];
            NSFont *f = [self currentFontWithSize:18];
            NSDictionary *attrs = [NSDictionary dictionaryWithObject:f forKey:NSFontAttributeName];
            CGFloat x = x0 + col * cell;
            CGFloat y = y0 + row * cell;

            [[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] setStroke];
            NSFrameRect(NSMakeRect(x, y, cell, cell));
            [ch drawAtPoint:NSMakePoint(x + 8, y + 10) withAttributes:attrs];
            [[NSString stringWithFormat:@"%02X", cp]
                drawAtPoint:NSMakePoint(x + 2, y + 1) withAttributes:labelAttrs];

            col++;
            if(col >= cols) { col = 0; row++; }
        }
    } else {
        CGFloat y = 10;
        NSArray *lines = [NSArray arrayWithObjects:
            [NSString stringWithFormat:@"PostScript: %@", [_font objectForKey:@"PostScriptName"]],
            [NSString stringWithFormat:@"Family: %@", [_font objectForKey:@"Family"]],
            [NSString stringWithFormat:@"Style: %@", [_font objectForKey:@"Style"]],
            [NSString stringWithFormat:@"Version: %@", [_font objectForKey:@"Version"]],
            [NSString stringWithFormat:@"Glyph count: %@", [_font objectForKey:@"GlyphCount"]],
            [NSString stringWithFormat:@"File: %@", [_font objectForKey:@"FilePath"]],
            [NSString stringWithFormat:@"Validation: %@", _validationResult],
            nil];
        for(NSString *line in lines) {
            NSDictionary *attrs = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:12] forKey:NSFontAttributeName];
            [line drawAtPoint:NSMakePoint(10, y) withAttributes:attrs];
            y += 16;
        }
    }
}

- (void)validate {
    NSString *path = [_font objectForKey:@"FilePath"];
    NSArray *missing = nil;
    BOOL ok = [O2Font_ttf validateFontFileAtPath:path missingTables:&missing];
    if(ok) {
        _validationResult = @"Pass";
    } else {
        _validationResult = [NSString stringWithFormat:@"Missing: %@", [missing componentsJoinedByString:@", "]];
    }
    [self setNeedsDisplay:YES];
}

@end