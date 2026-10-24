#import "MarkdownHighlighter.h"

static NSFont *boldFont(NSFont *f, CGFloat size) {
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSFont *b = [fm convertFont:f toHaveTrait:NSBoldFontMask];
    if (b && size > 0) b = [NSFont fontWithName:[b fontName] size:size];
    return b ? b : f;
}
static NSFont *italicFont(NSFont *f) {
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSFont *it = [fm convertFont:f toHaveTrait:NSItalicFontMask];
    return it ? it : f;
}

@implementation MarkdownHighlighter

+ (NSAttributedString *)highlightedStringForMarkdown:(NSString *)markdown baseFont:(NSFont *)baseFont {
    if (!baseFont) baseFont = [NSFont systemFontOfSize:12];
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:markdown attributes:@{NSFontAttributeName: baseFont}];
    // Headings: whole line
    NSUInteger len = [markdown length];
    // line scan
    NSUInteger i = 0;
    while (i < len) {
        // find line end
        NSUInteger lineStart = i;
        NSUInteger j = i;
        while (j < len && [markdown characterAtIndex:j] != '\n') j++;
        // check heading
        NSUInteger k = lineStart;
        int level = 0;
        while (k < j && [markdown characterAtIndex:k] == '#' && level < 6) { level++; k++; }
        if (level > 0 && (k == j || [markdown characterAtIndex:k] == ' ')) {
            CGFloat size = [baseFont pointSize] + (7 - level);
            NSFont *hf = [NSFont boldSystemFontOfSize:size];
            [out addAttribute:NSFontAttributeName value:hf range:NSMakeRange(lineStart, j-lineStart)];
            [out addAttribute:NSForegroundColorAttributeName value:[NSColor colorWithCalibratedRed:0.2 green:0.2 blue:0.7 alpha:1] range:NSMakeRange(lineStart, j-lineStart)];
        }
        i = (j < len) ? j+1 : len;
    }
    // Inline code spans
    i = 0;
    while (i < len) {
        if ([markdown characterAtIndex:i] == '`') {
            NSUInteger j = [markdown rangeOfString:@"`" options:0 range:NSMakeRange(i+1, len-(i+1))].location;
            if (j != NSNotFound) {
                NSRange r = NSMakeRange(i, j-i+1);
                NSFont *mf = [NSFont fontWithName:@"Menlo" size:[baseFont pointSize]];
                if (!mf) mf = [NSFont userFixedPitchFontOfSize:[baseFont pointSize]];
                [out addAttribute:NSFontAttributeName value:mf range:r];
                [out addAttribute:NSBackgroundColorAttributeName value:[NSColor colorWithCalibratedWhite:0.9 alpha:1] range:r];
                i = j+1;
                continue;
            }
        }
        i++;
    }
    // Bold **...**
    /* No blocks: the block runtime is unreliable on this image. */
    [self applyBoldInlineTo:out text:markdown];
    // Italic *...* (single)
    // Simple: find single asterisks not part of double
    [self applySingleItalicTo:out text:markdown baseFont:baseFont];
    // Links [text](url)
    [self applyLinksTo:out text:markdown];
    return out;
}

+ (void)applyBoldInlineTo:(NSMutableAttributedString *)out text:(NSString *)text {
    NSString *marker = @"**";
    NSUInteger len = [text length];
    NSUInteger i = 0;
    while (i < len) {
        NSRange r = [text rangeOfString:marker options:0 range:NSMakeRange(i, len-i)];
        if (r.location == NSNotFound) break;
        NSUInteger start = r.location;
        NSUInteger searchFrom = start + [marker length];
        NSRange r2 = [text rangeOfString:marker options:0 range:NSMakeRange(searchFrom, len-searchFrom)];
        if (r2.location == NSNotFound) break;
        NSRange content = NSMakeRange(start, r2.location + [marker length] - start);
        // apply to inner range
        NSRange inner = NSMakeRange(start + [marker length], r2.location - (start + [marker length]));
        if (inner.length > 0) {
            NSFont *existing = [out attribute:NSFontAttributeName atIndex:inner.location effectiveRange:NULL];
            if (!existing) existing = [NSFont systemFontOfSize:12];
            NSFont *nf = boldFont(existing, [existing pointSize]);
            [out addAttribute:NSFontAttributeName value:nf range:inner];
        }
        i = r2.location + [marker length];
    }
}

+ (void)applySingleItalicTo:(NSMutableAttributedString *)out text:(NSString *)text baseFont:(NSFont *)baseFont {
    NSUInteger len = [text length];
    NSUInteger i = 0;
    while (i < len) {
        if ([text characterAtIndex:i] == '*' && (i+1 < len) && [text characterAtIndex:i+1] != '*') {
            // find closing single *
            NSUInteger j = i+1;
            while (j < len) {
                if ([text characterAtIndex:j] == '*' && (j+1 >= len || [text characterAtIndex:j+1] != '*') && (j==0 || [text characterAtIndex:j-1] != '*')) {
                    break;
                }
                j++;
            }
            if (j < len) {
                NSRange inner = NSMakeRange(i+1, j-i-1);
                if (inner.length > 0) {
                    NSFont *existing = [out attribute:NSFontAttributeName atIndex:inner.location effectiveRange:NULL];
                    if (!existing) existing = baseFont;
                    [out addAttribute:NSFontAttributeName value:italicFont(existing) range:inner];
                }
                i = j+1;
                continue;
            }
        }
        i++;
    }
}

+ (void)applyLinksTo:(NSMutableAttributedString *)out text:(NSString *)text {
    NSUInteger len = [text length];
    NSUInteger i = 0;
    while (i < len) {
        if ([text characterAtIndex:i] == '[') {
            NSUInteger closeBracket = [text rangeOfString:@"]" options:0 range:NSMakeRange(i+1, len-(i+1))].location;
            if (closeBracket != NSNotFound && closeBracket+1 < len && [text characterAtIndex:closeBracket+1] == '(') {
                NSUInteger closeParen = [text rangeOfString:@")" options:0 range:NSMakeRange(closeBracket+2, len-(closeBracket+2))].location;
                if (closeParen != NSNotFound) {
                    NSRange inner = NSMakeRange(i+1, closeBracket-i-1);
                    if (inner.length > 0) {
                        [out addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:NSUnderlineStyleSingle] range:inner];
                        [out addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:inner];
                    }
                    i = closeParen+1;
                    continue;
                }
            }
        }
        i++;
    }
}

+ (NSAttributedString *)renderedPreviewForMarkdown:(NSString *)markdown baseFont:(NSFont *)baseFont {
    if (!baseFont) baseFont = [NSFont systemFontOfSize:12];
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        // heading?
        NSUInteger k = 0; int level = 0;
        while (k < [line length] && [line characterAtIndex:k] == '#' && level < 6) { level++; k++; }
        if (level > 0 && (k == [line length] || [line characterAtIndex:k] == ' ')) {
            NSString *text = (k < [line length]) ? [line substringFromIndex:k+1] : @"";
            CGFloat size = [baseFont pointSize] + (7 - level);
            NSFont *hf = [NSFont boldSystemFontOfSize:size];
            NSAttributedString *a = [[NSAttributedString alloc] initWithString:[text stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName: hf, NSForegroundColorAttributeName: [NSColor blackColor]}];
            [out appendAttributedString:a];
            continue;
        }
        // inline parse
        NSMutableString *buf = [NSMutableString string];
        // We'll build chunks
        NSUInteger i = 0, L = [line length];
        while (i < L) {
            // bold
            if (i+1 < L && [line characterAtIndex:i]=='*' && [line characterAtIndex:i+1]=='*') {
                NSUInteger j = [line rangeOfString:@"**" options:0 range:NSMakeRange(i+2, L-(i+2))].location;
                if (j != NSNotFound) {
                    NSString *inner = [line substringWithRange:NSMakeRange(i+2, j-i-2)];
                    NSFont *bf = boldFont(baseFont, [baseFont pointSize]);
                    NSAttributedString *a = [[NSAttributedString alloc] initWithString:inner attributes:@{NSFontAttributeName: bf}];
                    [out appendAttributedString:a];
                    i = j+2;
                    continue;
                }
            }
            if ([line characterAtIndex:i] == '`') {
                NSUInteger j = [line rangeOfString:@"`" options:0 range:NSMakeRange(i+1, L-(i+1))].location;
                if (j != NSNotFound) {
                    NSString *inner = [line substringWithRange:NSMakeRange(i+1, j-i-1)];
                    NSFont *mf = [NSFont fontWithName:@"Menlo" size:[baseFont pointSize]];
                    if (!mf) mf = [NSFont userFixedPitchFontOfSize:[baseFont pointSize]];
                    NSAttributedString *a = [[NSAttributedString alloc] initWithString:inner attributes:@{NSFontAttributeName: mf, NSBackgroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.9 alpha:1]}];
                    [out appendAttributedString:a];
                    i = j+1;
                    continue;
                }
            }
            if ([line characterAtIndex:i] == '[') {
                NSUInteger cb = [line rangeOfString:@"]" options:0 range:NSMakeRange(i+1, L-(i+1))].location;
                if (cb != NSNotFound && cb+1 < L && [line characterAtIndex:cb+1]=='(') {
                    NSUInteger cp = [line rangeOfString:@")" options:0 range:NSMakeRange(cb+2, L-(cb+2))].location;
                    if (cp != NSNotFound) {
                        NSString *inner = [line substringWithRange:NSMakeRange(i+1, cb-i-1)];
                        NSAttributedString *a = [[NSAttributedString alloc] initWithString:inner attributes:@{NSFontAttributeName: baseFont, NSUnderlineStyleAttributeName: [NSNumber numberWithInt:NSUnderlineStyleSingle], NSForegroundColorAttributeName: [NSColor blueColor]}];
                        [out appendAttributedString:a];
                        i = cp+1;
                        continue;
                    }
                }
            }
            if ([line characterAtIndex:i] == '*' && (i+1>=L || [line characterAtIndex:i+1] != '*')) {
                // italic until next single *
                NSUInteger j = i+1;
                while (j < L && !([line characterAtIndex:j]=='*' && (j+1>=L || [line characterAtIndex:j+1]!='*'))) j++;
                if (j < L) {
                    NSString *inner = [line substringWithRange:NSMakeRange(i+1, j-i-1)];
                    NSAttributedString *a = [[NSAttributedString alloc] initWithString:inner attributes:@{NSFontAttributeName: italicFont(baseFont)}];
                    [out appendAttributedString:a];
                    i = j+1;
                    continue;
                }
            }
            // default char
            [buf appendFormat:@"%C", [line characterAtIndex:i]];
            i++;
        }
        if ([buf length] > 0) {
            NSAttributedString *a = [[NSAttributedString alloc] initWithString:buf attributes:@{NSFontAttributeName: baseFont}];
            [out appendAttributedString:a];
        }
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: baseFont}]];
    }
    return out;
}

@end