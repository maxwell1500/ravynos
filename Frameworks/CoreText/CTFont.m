/* Copyright (c) 2008 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreText/CTFont.h>
#import <Foundation/NSObjCRuntime.h>
#import "KTFont.h"
#import <CoreGraphics/CGFont.h>

static KTFont * ravyn_ref_font = NULL;


Boolean
ravyn_is_ours(id self)
{
   /* Every CTFontRef in this tree is a KTFont, whichever constructor made
      it.  Comparing against the class rather than a lazily-created ref font
      keeps fonts from CTFontCreateUIFontForLanguage() usable even when no
      graphics-font CTFont was created first. */
   if (self == NULL)
      return NO;
   return [(id)self isKindOfClass:[KTFont class]];
}

static CGFontRef
ravyn_fb_cg_get(void)
{
   static CGFontRef cg = NULL;
   if (cg == NULL)
      cg = CGFontCreateWithFontName(CFSTR("Nimbus Roman"));
   return cg;
}

 CTFontRef CTFontCreateWithGraphicsFont(CGFontRef cgFont,CGFloat size,CGAffineTransform *xform,id attributes) {
    if (size <= 0.0)
       size = 12.0;
    KTFont * font = [[KTFont alloc] initWithFont:cgFont size:size];
    if (ravyn_ref_font == NULL && font != NULL)
       ravyn_ref_font = (KTFont *)[font retain];   /* static must stay alive */
    return font;
 }

CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType uiFontType,CGFloat size,NSString *language ) {
   /* The UI font has to be a real font: Gecko resolves -apple-system (the
    * Firefox chrome font) through this call, and returning NULL leaves its
    * chrome text with no face at all while page text keeps working.  Inter is
    * the family AppKit's own UI font path falls back to, so both toolkits
    * agree on metrics.  The emphasized variants get the bold face. */
   const char *face = "Inter-Regular";
   CGFontRef cgFont;
   KTFont *font;


   switch(uiFontType) {
    case kCTFontEmphasizedSystemFontType:
    case kCTFontSmallEmphasizedSystemFontType:
    case kCTFontMiniEmphasizedSystemFontType:
    case kCTFontEmphasizedSystemDetailFontType:
     face = "Inter-Bold";
     break;
    default:
     break;
   }
   if(size <= 0.0)
    size = 13.0;

   cgFont = CGFontCreateWithFontName((CFStringRef)[NSString stringWithUTF8String:face]);
   if(cgFont == NULL)
    return NULL;
   font = [[KTFont alloc] initWithFont:cgFont size:size];
   CGFontRelease(cgFont);
   return (CTFontRef)font;
}

CFStringRef CTFontCopyFullName(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return NULL;
   return [self copyName];
}

/* This tree carries one name per face -- the name the font was created
 * with, which is its PostScript name.  Family and display name requests
 * answer with it rather than inventing a different string. */
CFStringRef CTFontCopyFamilyName(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return NULL;
   return [self copyFamilyName];
}

CFStringRef CTFontCopyPostScriptName(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return NULL;
   return [self copyName];
}

CFStringRef CTFontCopyDisplayName(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return NULL;
   return [self copyName];
}

CGFloat CTFontGetSize(CTFontRef self) {
   if (!ravyn_is_ours(self))
      return 16.0;
   return [self pointSize];
}

size_t CTFontGetGlyphCount(CTFontRef self) {
      if (!ravyn_is_ours(self)) {
      CGFontRef cg = ravyn_fb_cg_get();
      return cg != NULL ? CGFontGetNumberOfGlyphs(cg) : 0;
   }
   return [self numberOfGlyphs];
}

BOOL CTFontGetGlyphsForCharacters(CTFontRef self,const unichar *characters,CGGlyph *glyphs,size_t count) {
   /* cairo mac backend passes CFCharBuffer = array of 1-char CFString
    * pointers; legacy callers pass unichar arrays.  Only sniff when we
    * can read a pointer slot without overreading (count >= 4, so count*2
    * >= sizeof(void*)) and the slots look like CFStrings on the heap.
    * count < 4 cannot be safely sniffed; treat as unichar. */
   unichar stackbuf[64];
   const unichar *ucs = characters;
   Boolean isCFCharBuffer = NO;
   if (characters != NULL && count >= 4 && count <= 64) {
      const void * const *slots = (const void * const *)(uintptr_t)characters;
      size_t safe = (count * sizeof(unichar)) / sizeof(void *);
      size_t i;
      uintptr_t p0 = (uintptr_t)slots[0];
      if (p0 >= 0x100000000ULL && p0 < 0x800000000000ULL && (p0 & 0x7) == 0) {
         isCFCharBuffer = YES;
         for (i = 1; i < safe && i < count; i++) {
            uintptr_t pi = (uintptr_t)slots[i];
            if (pi < 0x100000000ULL || pi >= 0x800000000000ULL || (pi & 0x7) != 0) {
               isCFCharBuffer = NO;
               break;
            }
         }
         if (isCFCharBuffer &&
             CFGetTypeID((CFTypeRef)slots[0]) != CFStringGetTypeID())
            isCFCharBuffer = NO;
      }
   }
   if (isCFCharBuffer) {
      const void * const *slots = (const void * const *)(uintptr_t)characters;
      size_t i;
      for (i = 0; i < count; i++)
         stackbuf[i] = CFStringGetCharacterAtIndex((CFStringRef)slots[i], 0);
      ucs = stackbuf;
   }
   if (glyphs != NULL && count > 0) {
      size_t zi;
      for (zi = 0; zi < count; zi++)
         glyphs[zi] = CGNullGlyph;
      [self getGlyphs:glyphs forCharacters:ucs length:count];
      {
         CGFontRef sfg = NULL;
         for (zi = 0; zi < count; zi++) {
            if (glyphs[zi] != CGNullGlyph)
               continue;
            if (sfg == NULL)
               sfg = ravyn_fb_cg_get();
            if (sfg != NULL)
               CGFontGetGlyphsForUnicodeString(sfg, (const uint16_t *)(ucs + zi),
                  glyphs + zi, 1);
         }
      }
   }
   // FIXME: change getGlyphs: to return a BOOL
   return YES;
}

CGGlyph CTFontGetGlyphForCharacter(CTFontRef self, unichar character) {
   if (!ravyn_is_ours(self)) {
      CGFontRef cg = ravyn_fb_cg_get();
      CGGlyph glyph = CGNullGlyph;
      if (cg != NULL && CGFontGetGlyphsForUnicodeString(cg,&character,&glyph,1))
         ;
      return glyph;
   }
   CGGlyph glyph = CGNullGlyph;
   [self getGlyphs:&glyph forCharacters:&character length:1];
   return glyph;
}

CGRect CTFontGetBoundingBox(CTFontRef self) {
   if (!ravyn_is_ours(self))
      return CGRectMake(0,0,1000,1000);
   return [self boundingRect];
}

void CTFontGetAdvancesForGlyphs(CTFontRef self,int orientation,const CGGlyph *glyphs,CGSize *advances,size_t count) {
   (void)orientation;
   if (advances == NULL)
      return;
   if (ravyn_is_ours(self)) {
      [self getAdvancements:advances forGlyphs:glyphs count:count];
      return;
   }
   {
      CGFontRef cg = ravyn_fb_cg_get();
      if (cg != NULL) {
         int upem = CGFontGetUnitsPerEm(cg);
         if (upem <= 0)
            upem = 1000;
         int *advBuf = (int *)malloc(sizeof(int) * (count + 1));
         if (advBuf != NULL) {
            CGFontGetGlyphAdvances(cg,glyphs,count,advBuf);
            for (size_t i = 0; i < count; i++) {
               advances[i].width = ((CGFloat)advBuf[i] / (CGFloat)upem) * (CGFloat)16.0;
               advances[i].height = 0.0;
            }
            free(advBuf);
            return;
         }
      }
      for (size_t i = 0; i < count; i++) {
         advances[i].width = 0.0;
         advances[i].height = 0.0;
      }
   }
}

CGFloat CTFontGetUnderlinePosition(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return 0.0;
   return [self underlinePosition];
}

CGFloat CTFontGetUnderlineThickness(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return 0.0;
   return [self underlineThickness];
}

CGFloat CTFontGetAscent(CTFontRef self) {
   if (!ravyn_is_ours(self)) {
      CGFontRef cg = ravyn_fb_cg_get();
      if (cg != NULL) {
         int upem = CGFontGetUnitsPerEm(cg);
         if (upem > 0)
            return ((CGFloat)CGFontGetAscent(cg) / (CGFloat)upem) * (CGFloat)16.0;
      }
      return 16.0;
   }
   return [self ascender];
}

CGFloat CTFontGetDescent(CTFontRef self) {
   if (!ravyn_is_ours(self)) {
      CGFontRef cg = ravyn_fb_cg_get();
      if (cg != NULL) {
         int upem = CGFontGetUnitsPerEm(cg);
         if (upem > 0)
            return ((CGFloat)CGFontGetDescent(cg) / (CGFloat)upem) * (CGFloat)16.0;
      }
      return -4.0;
   }
   return [self descender];
}

CGFloat CTFontGetLeading(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return 0.0;
   return [self leading];
}

CGFloat CTFontGetSlantAngle(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return 0.0;
   return [self italicAngle];
}

CGFloat CTFontGetXHeight(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return 0.0;
   return [self xHeight];
}

CGFloat CTFontGetCapHeight(CTFontRef self) {
	if (!ravyn_is_ours(self))
	    return 0.0;
   return [self capHeight];
}

CGPathRef CTFontCreatePathForGlyph(CTFontRef self,CGGlyph glyph,CGAffineTransform *xform) {
   CGPathRef rr = NULL;
   if (!ravyn_is_ours(self)) {
      extern CGPathRef ravyn_glyph_path(id fontref,int upem,double size,CGGlyph glyph);
      CGFontRef cg = ravyn_fb_cg_get();
      if (cg != NULL)
         rr = ravyn_glyph_path((id)cg, CGFontGetUnitsPerEm(cg), 16.0, glyph);
   } else
      rr = (CGPathRef)[self createPathForGlyph:glyph transform:xform];
   return rr;
}


