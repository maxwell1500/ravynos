/*
 * fontchain.m -- the cairo_mac font backend (Firefox basic-cairo) resolves
 * glyphs through the CoreText C API only: CTFontCreateWithName ->
 * CTFontGetGlyphsForCharacters -> CTFontCreatePathForGlyph, then fills the
 * path through CGContext.  It NEVER calls CTFontDrawGlyphs, and the 2026-11
 * navpage fixture proved outlines never arrive (solid bars).  This fixture
 * walks the exact same chain so a pass is a statement about the guest
 * frameworks, not about our headers.
 *
 * Built with Apple's clang and SDK, like the other fixtures.
 */

#import <CoreText/CTFont.h>
#import <CoreGraphics/CoreGraphics.h>

#include <stdio.h>
#include <string.h>

static int g_failures;

static void
fail(const char *what)
{
    fprintf(stderr, "fontchain: FAIL %s\n", what);
    g_failures++;
}

int
main(void)
{
    CTFontRef font = CTFontCreateWithName("Inter-Regular", 24.0, NULL);
    if (font == NULL) {
        fail("CTFontCreateWithName(Inter-Regular) NULL");
        fprintf(stderr, "fontchain: summary %d failures\n", g_failures);
        return 1;
    }

    CFCharBuffer buf = { { 'A', 'B' }, 2 };
    CGGlyph glyphs[2] = { 0, 0 };
    CTFontGetGlyphsForCharacters(font, (const CFCharBufferRef *)&buf,
        glyphs, 2, NULL);
    if (glyphs[0] == 0)
        fail("GetGlyphsForCharacters('A') -> 0");

    CGPathRef path = CTFontCreatePathForGlyph(font, glyphs[0], NULL);
    if (path == NULL)
        fail("CreatePathForGlyph(glyph A) NULL");
    else {
        CGRect bb = CGPathGetBoundingBox(path);
        fprintf(stderr, "fontchain: A path bbox w=%.1f h=%.1f\n",
            bb.size.width, bb.size.height);
        if (bb.size.width < 1.0 || bb.size.height < 1.0)
            fail("A path bbox empty");
    }

    fprintf(stderr, "fontchain: summary %d failures\n", g_failures);
    return g_failures ? 1 : 0;
}
