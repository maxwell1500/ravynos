/* Copyright (c) 2006-2008 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:



THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "KTFont.h"
#import <Onyx2D/O2Exceptions.h>
#import <Foundation/NSArray.h>
#import <Onyx2D/O2Font_freetype.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
#include <stdio.h>

@implementation KTFont

-initWithFont:(CGFontRef)font size:(CGFloat)size {
   _font=CGFontRetain(font);
   _unitsPerEm=CGFontGetUnitsPerEm(_font);
   _size=size;
   return self;
}

-initWithUIFontType:(CTFontUIFontType)uiFontType size:(CGFloat)size language:(NSString *)language {
   O2InvalidAbstractInvocation();
   return nil;
}

-(void)dealloc {
   CGFontRelease(_font);
   [super dealloc];
}

-(CFStringRef)copyName {
   return CGFontCopyFullName(_font);
}
-(CFStringRef)copyFamilyName {
   return CGFontCopyFamilyName(_font);
}
-(CGFontRef)graphicsFont {
   return _font;
}

-(CGFloat)unitsPerEm {
   return _unitsPerEm > 0 ? _unitsPerEm : 1000.0;
}

-(CGFloat)pointSize {
	return _size;
}

-(CGFloat)fontSize {
	return _size;
}

-(CGRect)boundingRect {
   CGRect bbox = CGFontGetFontBBox(_font);
   CGFloat scale = (_unitsPerEm > 0 ? (_size / _unitsPerEm) : 0.001);
   return CGRectMake(bbox.origin.x * scale, bbox.origin.y * scale,
       bbox.size.width * scale, bbox.size.height * scale);
}

-(CGFloat)ascender {
   CGFloat ascent=CGFontGetAscent(_font);
   
   return (ascent/_unitsPerEm)*_size;
}

// CT descenter is the opposite of the CG one on Cocoa
-(CGFloat)descender {
   CGFloat descent=CGFontGetDescent(_font);
   return -(descent/_unitsPerEm)*_size;
}

-(CGFloat)leading {
   CGFloat leading=CGFontGetLeading(_font);
   
   return (leading/_unitsPerEm)*_size;
}

-(CGFloat)underlineThickness {
   return (_size > 0 ? _size : 12.0) / 14.0;
}

-(CGFloat)underlinePosition {
   return -((_size > 0 ? _size : 12.0) / 10.0);
}

-(CGFloat)italicAngle {
   return CGFontGetItalicAngle(_font);
}

-(CGFloat)xHeight {
   CGFloat xHeight=CGFontGetXHeight(_font);

   return (xHeight/_unitsPerEm)*_size;
}

-(CGFloat)capHeight {
   CGFloat capHeight=CGFontGetCapHeight(_font);
   
   return (capHeight/_unitsPerEm)*_size;
}

-(unsigned)numberOfGlyphs {
   return CGFontGetNumberOfGlyphs(_font);
}

-(CGPoint)positionOfGlyph:(CGGlyph)current precededByGlyph:(CGGlyph)previous isNominal:(BOOL *)isNominalp {
   int advancement;
   
   if(previous==0)
    return CGPointMake(0,0);

   *isNominalp=YES;
   CGFontGetGlyphAdvances(_font,&previous,1,&advancement);

   return CGPointMake(((CGFloat)advancement/_unitsPerEm)*_size,0);
}

-(void)getGlyphs:(CGGlyph *)glyphs forCharacters:(const unichar *)characters length:(unsigned)length {
   BOOL rp = (_font != NULL) && [(id)_font respondsToSelector:@selector(getGlyphsForCodePoints:::)];
   if (rp) {
    [(id)_font getGlyphsForCodePoints:(uint16_t *)characters :glyphs :(int)length];
    return;
   }
   for (unsigned i = 0; i < length; i++) {
    if (_twoLevel == NULL) {
     glyphs[i] = 0;
    } else {
     uint16_t code = characters[i];
     uint8_t group = code >> 8;
     uint8_t index = code & 0xFF;
     glyphs[i] = (_twoLevel[group] == NULL) ? 0 : _twoLevel[group][index];
    }
   }
}

-(void)getAdvancements:(CGSize *)advancements forGlyphs:(const CGGlyph *)glyphs count:(unsigned)count {
   int advances[count];
   
   CGFontGetGlyphAdvances(_font,glyphs,count,advances);
   for(int i=0;i<count;i++){
    advancements[i].width=((CGFloat)advances[i]/(CGFloat)_unitsPerEm)*_size;
    advancements[i].height=0;
   }
}

CGPathRef
ravyn_glyph_path(id fontref, int upem, double size, CGGlyph glyph)
{
#ifdef FREETYPE_PRESENT
   FT_Face face = O2FontFreeTypeFace((O2Font_freetype *)fontref);
   if (face == NULL || upem <= 0)
      return NULL;
   /* Deterministic point space: set the size before every load.  A face
    * someone else sized returns 26.6 fixed-point pixels, a fresh face
    * returns font units — derive nothing from the previous state. */
   if (size <= 0)
      size = (double)upem;
   if (FT_Set_Char_Size(face, 0, (FT_F26Dot6)(size * 64.0), 72, 72) != 0)
      return NULL;
   if (FT_Load_Glyph(face, (FT_UInt)glyph, FT_LOAD_DEFAULT) != 0)
      return NULL;
   FT_Outline *outline = &face->glyph->outline;
   (void)face; (void)size; (void)upem;
   if (outline->n_points == 0 || outline->n_contours <= 0)
      return NULL;
   /* Points are 26.6 fixed-point pixels, y-up, baseline at origin —
    * the space CTFontCreatePathForGlyph returns on macOS. */
   const CGFloat scale = 1.0 / 64.0;
   CGMutablePathRef path = CGPathCreateMutable();
   for (int c = 0; c < outline->n_contours; c++) {
      int end = outline->contours[c];
      int first = (c == 0) ? 0 : outline->contours[c - 1] + 1;
      if (end < first)
         continue;
      int start = first;
      BOOL moved = NO;
      CGFloat curx = outline->points[first].x * scale;
      CGFloat cury = outline->points[first].y * scale;
      while ((outline->tags[start] & FT_CURVE_TAG_ON) == 0 && start + 1 <= end) {
         if (outline->tags[start + 1] & FT_CURVE_TAG_ON) {
            CGPathMoveToPoint(path, NULL,
               outline->points[start].x * scale, outline->points[start].y * scale);
            start++;
            moved = YES;
            curx = outline->points[start].x * scale;
            cury = outline->points[start].y * scale;
            break;
         }
         CGPathMoveToPoint(path, NULL,
            (outline->points[start].x + outline->points[start + 1].x) * 0.5 * scale,
            (outline->points[start].y + outline->points[start + 1].y) * 0.5 * scale);
         start += 2;
         moved = YES;
         curx = outline->points[start - 1].x * scale;
         cury = outline->points[start - 1].y * scale;
         break;
      }
      if (!moved) {
         CGPathMoveToPoint(path, NULL, curx, cury);
      }
      for (int p = first + 1; p <= end; p++) {
         CGFloat ex, ey;
         if (outline->tags[p] & FT_CURVE_TAG_ON) {
            CGPathAddLineToPoint(path, NULL,
               outline->points[p].x * scale, outline->points[p].y * scale);
            curx = outline->points[p].x * scale;
            cury = outline->points[p].y * scale;
            continue;
         }
         /* Quadratic with control points[p]: elevate to cubic. */
         CGFloat ctrlx = outline->points[p].x * scale;
         CGFloat ctrly = outline->points[p].y * scale;
         if (p + 1 <= end && (outline->tags[p + 1] & FT_CURVE_TAG_ON)) {
            ex = outline->points[p + 1].x * scale;
            ey = outline->points[p + 1].y * scale;
            p++;
         } else {
            int wrap = (p + 1 > end) ? first : p + 1;
            ex = (outline->points[p].x + outline->points[wrap].x) * 0.5 * scale;
            ey = (outline->points[p].y + outline->points[wrap].y) * 0.5 * scale;
         }
         CGPathAddCurveToPoint(path, NULL,
            curx + (2.0 / 3.0) * (ctrlx - curx), cury + (2.0 / 3.0) * (ctrly - cury),
            ex + (2.0 / 3.0) * (ctrlx - ex), ey + (2.0 / 3.0) * (ctrly - ey),
            ex, ey);
         curx = ex;
         cury = ey;
      }
   }
   return (CGPathRef)path;
#else
   return NULL;
#endif
}

-(CGPathRef)createPathForGlyph:(CGGlyph)glyph transform:(CGAffineTransform *)xform {
   return ravyn_glyph_path(_font, (int)_unitsPerEm, (double)_size, glyph);
}

@end
