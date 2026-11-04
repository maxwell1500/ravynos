/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreGraphics/CGFont.h>
#import <CoreGraphics/CGDataProvider.h>
#import <Onyx2D/O2Font.h>
#import <CoreFoundation/CoreFoundation.h>

CGFontRef CGFontCreateWithFontName(CFStringRef name) {
   return O2FontCreateWithFontName((NSString *)name);
}

CGFontRef CGFontRetain(CGFontRef self) {
   return O2FontRetain(self);
}

void      CGFontRelease(CGFontRef self) {
   O2FontRelease(self);
}

CFStringRef CGFontCopyFullName(CGFontRef self) {
   return (CFStringRef)O2FontCopyFullName(self);
}

int       CGFontGetUnitsPerEm(CGFontRef self) {
   return O2FontGetUnitsPerEm(self);
}

int       CGFontGetAscent(CGFontRef self) {
   return O2FontGetAscent(self);
}

int       CGFontGetDescent(CGFontRef self) {
   return O2FontGetDescent(self);
}

int       CGFontGetLeading(CGFontRef self) {
   return O2FontGetLeading(self);
}

int       CGFontGetCapHeight(CGFontRef self) {
   return O2FontGetCapHeight(self);
}

int       CGFontGetXHeight(CGFontRef self) {
   return O2FontGetXHeight(self);
}

CGFloat   CGFontGetItalicAngle(CGFontRef self) {
   return O2FontGetItalicAngle(self);
}

CGFloat   CGFontGetStemV(CGFontRef self) {
   return O2FontGetStemV(self);
}

CGRect    CGFontGetFontBBox(CGFontRef self) {
   return O2FontGetFontBBox(self);
}

size_t    CGFontGetNumberOfGlyphs(CGFontRef self) {
   return O2FontGetNumberOfGlyphs(self);
}

bool      CGFontGetGlyphAdvances(CGFontRef self,const CGGlyph *glyphs,size_t count,int *advances) {
   return O2FontGetGlyphAdvances(self,glyphs,count,advances);
}

CGGlyph   CGFontGetGlyphWithGlyphName(CGFontRef self,CFStringRef name) {
   return O2FontGetGlyphWithGlyphName(self,name);
}

CFStringRef CGFontCopyGlyphNameForGlyph(CGFontRef self,CGGlyph glyph) {
   return (CFStringRef)O2FontCopyGlyphNameForGlyph(self,glyph);
}

CFDataRef CGFontCopyTableForTag(CGFontRef self,uint32_t tag) {
   return (CFDataRef)O2FontCopyTableForTag(self,tag);
}

CFStringRef CGFontCopyPostScriptName(CGFontRef self) {
   return CGFontCopyFullName(self);
}

CGFontRef CGFontCreateWithDataProvider(CGDataProviderRef provider) {
   return O2FontCreateWithDataProvider((O2DataProviderRef)provider);
}

CFArrayRef CGFontCopyTableTags(CGFontRef self) {
   static const uint32_t kKnownTags[] = {
      0x636d6170, /* 'cmap' */
      0x68656164, /* 'head' */
      0x68686561, /* 'hhea' */
      0x686d7478, /* 'hmtx' */
      0x6d617870, /* 'maxp' */
      0x6e616d65, /* 'name' */
      0x4f532f32, /* 'OS/2' */
      0x706f7374, /* 'post' */
      0x676c7966, /* 'glyf' */
      0x6c6f6361, /* 'loca' */
      0x43464620, /* 'CFF ' */
      0x47444546, /* 'GDEF' */
      0x47504f53, /* 'GPOS' */
      0x47535542, /* 'GSUB' */
      0x6b65726e, /* 'kern' */
   };
   const void *present[sizeof(kKnownTags) / sizeof(kKnownTags[0])];
   CFIndex count = 0;
   if (self != NULL) {
      for (size_t i = 0; i < sizeof(kKnownTags) / sizeof(kKnownTags[0]); i++) {
         CFDataRef d = CGFontCopyTableForTag(self, kKnownTags[i]);
         if (d != NULL) {
            CFRelease(d);
            present[count++] = (const void *)(uintptr_t)kKnownTags[i];
         }
      }
   }
   return CFArrayCreate(NULL, present, count, NULL);
}

CFArrayRef CGFontCopyVariationAxes(CGFontRef self) {
   (void)self;
   return NULL;
}

CFDictionaryRef CGFontCopyVariations(CGFontRef self) {
   (void)self;
   return NULL;
}

CGFontRef CGFontCreateCopyWithVariations(CGFontRef self, CFDictionaryRef variations) {
   (void)variations;
   return CGFontRetain(self);
}

bool CGFontGetGlyphBBoxes(CGFontRef self, const CGGlyph *glyphs, size_t count, CGRect *bboxes) {
   if (self == NULL || glyphs == NULL || bboxes == NULL)
      return false;
   CGRect fbox = CGFontGetFontBBox(self);
   int ascent = CGFontGetAscent(self);
   int descent = CGFontGetDescent(self);
   for (size_t i = 0; i < count; i++) {
      int adv = 0;
      CGFontGetGlyphAdvances(self, &glyphs[i], 1, &adv);
      bboxes[i] = CGRectMake(0, descent, adv > 0 ? adv : fbox.size.width, ascent - descent);
   }
   return true;
}

CFTypeID CGFontGetTypeID(void) {
   return 0;
}
