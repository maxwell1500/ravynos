#import <Onyx2D/O2Font_freetype.h>
#import <CoreGraphics/CGPath.h>
#ifdef FREETYPE_PRESENT
#import <Onyx2D/O2Encoding.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_TRUETYPE_TABLES_H


@implementation O2Font_freetype

FT_Library freeTypeLibrary;
+(void)initialize {
  if(self==[O2Font_freetype class]){
   int error = FT_Init_FreeType(&freeTypeLibrary);
   if ( error ) {
     NSLog(@"error initializing FreeType %d",error);
   }
  }
}


- (id)initWithFilename:(const char *)path {
   /* File-based face creation. The memory-based path (FT_New_Memory_Face with
    * an O2DataProvider's bytes) never returns on this target even though the
    * identical call parses the same file in ~0.1ms on the host, so files are
    * opened directly instead. */
   if(![super init])
    return nil;

   _platformType=O2FontPlatformTypeFreeType;

   int error=FT_New_Face(freeTypeLibrary,path,0,&_face);

   if(error!=0){
    NSLog(@"FT_New_Face returned %d",error);
    [self dealloc];
    return nil;
   }

   FT_Select_Charmap(_face, FT_ENCODING_UNICODE);

   if(!(_face->face_flags&FT_FACE_FLAG_SCALABLE))
    NSLog(@"FreeType font face is not scalable");

   if (_name == nil) {
    const char *ps = FT_Get_Postscript_Name(_face);
    if (ps != NULL)
     _name = [[NSString alloc] initWithUTF8String:ps];
    else if (_face->family_name != NULL)
     _name = [[NSString alloc] initWithUTF8String:_face->family_name];
   }
   _unitsPerEm=(float)_face->units_per_EM;
   _ascent=_face->ascender;
   _descent=_face->descender;
   _leading=0;
   _capHeight=_face->height;
   _xHeight=_face->height;
   _italicAngle=0;
   _stemV=0;
   _bbox.origin.x=_face->bbox.xMin;
   _bbox.origin.y=_face->bbox.yMin;
   _bbox.size.width=_face->bbox.xMax-_face->bbox.xMin;
   _bbox.size.height=_face->bbox.yMax-_face->bbox.yMin;
   _numberOfGlyphs=_face->num_glyphs;
   _advances=NULL;

   return self;
}

-initWithDataProvider:(O2DataProviderRef)provider {
   if([super initWithDataProvider:provider]==nil)
    return nil;

   _platformType=O2FontPlatformTypeFreeType;

   /* FT_New_Memory_Face() keeps the caller's buffer for the face's lifetime,
    * so the provider must outlive any release by the caller. */
   _dataProvider=O2DataProviderRetain(provider);

   const void *bytes=[provider bytes];
   size_t      length=[provider length];
   
   int error=FT_New_Memory_Face(freeTypeLibrary,bytes,length,0,&_face);
   
   if(error!=0){
    NSLog(@"FT_New_Memory_Face=%d",error);
    [self dealloc];
    return nil;
   }
   
   int i,numberOfCharMaps=_face->num_charmaps;
   bool hasUnicode=FALSE;
   bool hasMacRoman=FALSE;
   
   for(i=0;i<numberOfCharMaps;i++){
    
    if(_face->charmaps[i]->encoding==FT_ENCODING_UNICODE)
     hasUnicode=TRUE;
    if(_face->charmaps[i]->encoding==FT_ENCODING_APPLE_ROMAN)
     hasMacRoman=TRUE;
   }
   
   if(hasUnicode){
    _ftEncoding=FT_ENCODING_UNICODE;
   }
   else if(hasMacRoman){
    _ftEncoding=FT_ENCODING_APPLE_ROMAN;
   }
   else {
    NSLog(@"encoding=%c %c %c %c",_face->charmaps[i]->encoding>>24,_face->charmaps[i]->encoding>>16,_face->charmaps[i]->encoding>>8,_face->charmaps[i]->encoding);
    _ftEncoding=_face->charmaps[0]->encoding;
   }
   
   if(FT_Select_Charmap(_face,_ftEncoding)!=0)
    NSLog(@"FT_Select_Charmap(%d) failed",_ftEncoding);
   
   if(!(_face->face_flags&FT_FACE_FLAG_SCALABLE))
    NSLog(@"FreeType font face is not scalable");
    
   if (_name == nil) {
    const char *ps = FT_Get_Postscript_Name(_face);
    if (ps != NULL)
     _name = [[NSString alloc] initWithUTF8String:ps];
    else if (_face->family_name != NULL)
     _name = [[NSString alloc] initWithUTF8String:_face->family_name];
   }
   _unitsPerEm=(float)_face->units_per_EM;
   _ascent=_face->ascender;
   _descent=_face->descender;
   _leading=0;
   _capHeight=_face->height;
   _xHeight=_face->height;
   _italicAngle=0;
   _stemV=0;
   _bbox.origin.x=_face->bbox.xMin;
   _bbox.origin.y=_face->bbox.yMin;
   _bbox.size.width=_face->bbox.xMax-_face->bbox.xMin;
   _bbox.size.height=_face->bbox.yMax-_face->bbox.yMin;
   _numberOfGlyphs=_face->num_glyphs;
   _advances=NULL;
   return self;
}

-(void)dealloc {
   FT_Done_Face(_face);
   [_macRomanEncoding release];
   [_macExpertEncoding release];
   [_winAnsiEncoding release];
   if(_dataProvider!=NULL)
    O2DataProviderRelease(_dataProvider);
   [super dealloc];
}

- (FT_Face)face {
   return _face;
}

FT_Face O2FontFreeTypeFace(O2Font_freetype *self) {
   return self->_face;
}

#ifdef FREETYPE_PRESENT
CGPathRef
O2Font_freetypeCreatePath(FT_Face face, int upem, double size, CGGlyph glyph, const CGAffineTransform *xform)
{
   if (face == NULL || upem <= 0)
      return NULL;
   if (size <= 0)
      size = (double)upem;
   if (FT_Set_Char_Size(face, 0, (FT_F26Dot6)(size * 64.0), 72, 72) != 0)
      return NULL;
   if (FT_Load_Glyph(face, (FT_UInt)glyph, FT_LOAD_DEFAULT) != 0)
      return NULL;
   {
      FT_Outline *outline = &face->glyph->outline;
      const CGFloat scale = 1.0 / 64.0;
      CGMutablePathRef path;
      int c;

      if (outline->n_points == 0 || outline->n_contours <= 0)
         return NULL;
      path = CGPathCreateMutable();
      for (c = 0; c < outline->n_contours; c++) {
         int first = (c == 0) ? 0 : outline->contours[c - 1] + 1;
         int end = outline->contours[c];
         int n, i, startIdx;

         if (end < first || end >= outline->n_points)
            continue;
         n = end - first + 1;
         if (n <= 0)
            continue;

         startIdx = first;
         while (startIdx <= end && (outline->tags[startIdx] & FT_CURVE_TAG_ON) == 0)
            startIdx++;
         if (startIdx > end) {
            /* All off-curve: start at midpoint of last and first. */
            CGFloat startX = (outline->points[end].x + outline->points[first].x) * 0.5 * scale;
            CGFloat startY = (outline->points[end].y + outline->points[first].y) * 0.5 * scale;
            CGFloat curX = startX, curY = startY;
            CGPathMoveToPoint(path, xform, startX, startY);
            for (i = 0; i < n; i++) {
               int idx = first + i;
               int next = first + ((i + 1) % n);
               CGFloat cx = outline->points[idx].x * scale;
               CGFloat cy = outline->points[idx].y * scale;
               CGFloat nx = outline->points[next].x * scale;
               CGFloat ny = outline->points[next].y * scale;
               CGFloat mx = (cx + nx) * 0.5;
               CGFloat my = (cy + ny) * 0.5;
               CGPathAddCurveToPoint(path, xform,
                  curX + (2.0 / 3.0) * (cx - curX), curY + (2.0 / 3.0) * (cy - curY),
                  mx + (2.0 / 3.0) * (cx - mx), my + (2.0 / 3.0) * (cy - my),
                  mx, my);
               curX = mx; curY = my;
            }
            CGPathCloseSubpath(path);
            continue;
         }

         {
            int firstOn = startIdx;
            CGFloat sx = outline->points[firstOn].x * scale;
            CGFloat sy = outline->points[firstOn].y * scale;
            BOOL haveCtrl = NO;
            CGFloat ctrlX = 0, ctrlY = 0;
            CGFloat curX = sx, curY = sy;

            CGPathMoveToPoint(path, xform, sx, sy);
            for (i = 1; i <= n; i++) {
               int idx = first + ((firstOn - first + i) % n);
               BOOL on = (outline->tags[idx] & FT_CURVE_TAG_ON) != 0;
               CGFloat px = outline->points[idx].x * scale;
               CGFloat py = outline->points[idx].y * scale;
               if (on) {
                  if (haveCtrl) {
                     CGPathAddCurveToPoint(path, xform,
                        curX + (2.0 / 3.0) * (ctrlX - curX), curY + (2.0 / 3.0) * (ctrlY - curY),
                        px + (2.0 / 3.0) * (ctrlX - px), py + (2.0 / 3.0) * (ctrlY - py),
                        px, py);
                     haveCtrl = NO;
                  } else {
                     CGPathAddLineToPoint(path, xform, px, py);
                  }
                  curX = px; curY = py;
               } else if (haveCtrl) {
                  CGFloat midX = (ctrlX + px) * 0.5;
                  CGFloat midY = (ctrlY + py) * 0.5;
                  CGPathAddCurveToPoint(path, xform,
                     curX + (2.0 / 3.0) * (ctrlX - curX), curY + (2.0 / 3.0) * (ctrlY - curY),
                     midX + (2.0 / 3.0) * (ctrlX - midX), midY + (2.0 / 3.0) * (ctrlY - midY),
                     midX, midY);
                  curX = midX; curY = midY;
                  ctrlX = px; ctrlY = py;
               } else {
                  ctrlX = px; ctrlY = py;
                  haveCtrl = YES;
               }
            }
            if (haveCtrl) {
               CGPathAddCurveToPoint(path, xform,
                  curX + (2.0 / 3.0) * (ctrlX - curX), curY + (2.0 / 3.0) * (ctrlY - curY),
                  sx + (2.0 / 3.0) * (ctrlX - sx), sy + (2.0 / 3.0) * (ctrlY - sy),
                  sx, sy);
            }
            CGPathCloseSubpath(path);
         }
      }
      return (CGPathRef)path;
   }
}
#endif
-(void)fetchAdvances {
   O2Glyph glyph;

   FT_Set_Char_Size(_face,0,_unitsPerEm*64,72,72);

   _advances=NSZoneMalloc(NULL,sizeof(int)*_numberOfGlyphs);

   for(glyph=0;glyph<_numberOfGlyphs;glyph++){
    FT_Load_Glyph(_face, glyph, FT_LOAD_DEFAULT);
    
    _advances[glyph]=_face->glyph->advance.x/(float)(2<<5);
   }
}

-(NSData *)copyTableForTag:(uint32_t)tag {
   FT_ULong length = 0;
   if (_face == NULL)
    return nil;
   if (FT_Load_Sfnt_Table(_face, (FT_ULong)tag, 0, NULL, &length) != 0 || length == 0)
    return nil;
   void *bytes = malloc(length);
   if (bytes == NULL)
    return nil;
   if (FT_Load_Sfnt_Table(_face, (FT_ULong)tag, 0, (FT_Byte *)bytes, &length) != 0) {
    free(bytes);
    return nil;
   }
   CFDataRef data = CFDataCreate(NULL, (const UInt8 *)bytes, (CFIndex)length);
   free(bytes);
   return (NSData *)data;
}
-(O2Glyph)glyphWithGlyphName:(NSString *)name {
   return FT_Get_Name_Index(_face,(char *)[name cString]);
}

-(void)getGlyphsForCodePoints:(uint16_t *)codes :(O2Glyph *)glyphs :(int)length {
   int i;
   
   for(i=0;i<length;i++)
    glyphs[i]=FT_Get_Char_Index(_face,codes[i]);
}

-(O2Encoding *)unicode_createEncodingForTextEncoding:(O2TextEncoding)encoding {
   unichar unicode[256];
   O2Glyph glyphs[256];
   
   switch(encoding){
    case kO2EncodingFontSpecific:
    case kO2EncodingMacRoman:
     if(_macRomanEncoding==nil){
      O2EncodingGetMacRomanUnicode(unicode);
      [self getGlyphsForCodePoints:unicode:glyphs:256];
      _macRomanEncoding=[[O2Encoding alloc] initWithGlyphs:glyphs unicode:unicode];
     }
     return [_macRomanEncoding retain];
     
    case kO2EncodingMacExpert:
     if(_macExpertEncoding==nil){
      O2EncodingGetMacExpertUnicode(unicode);
      [self getGlyphsForCodePoints:unicode:glyphs:256];
      _macExpertEncoding=[[O2Encoding alloc] initWithGlyphs:glyphs unicode:unicode];
     }
     return [_macExpertEncoding retain];

    case kO2EncodingWinAnsi:
     if(_winAnsiEncoding==nil){
      O2EncodingGetWinAnsiUnicode(unicode);
      [self getGlyphsForCodePoints:unicode:glyphs:256];
      _winAnsiEncoding=[[O2Encoding alloc] initWithGlyphs:glyphs unicode:unicode];
     }
     return [_winAnsiEncoding retain];
    
    default:
     return nil;
   }
   return nil;
}

-(O2Encoding *)MacRoman_createEncodingForTextEncoding:(O2TextEncoding)encoding {
   uint16_t codes[256];
   O2Glyph glyphs[256];
   unichar unicode[256];

   if(_macRomanEncoding==nil){
    int i;
   
    if(encoding!=kO2EncodingMacRoman && encoding!=kO2EncodingFontSpecific){
     NSLog(@"font encoding is MacRoman, requesting encoding %d failed",encoding);
    }
   
    for(i=0;i<256;i++)
     codes[i]=i;
    
    [self getGlyphsForCodePoints:codes:glyphs:256];
    
    O2EncodingGetMacExpertUnicode(unicode);

    _macRomanEncoding=[[O2Encoding alloc] initWithGlyphs:glyphs unicode:unicode];
   }
   
   return [_macRomanEncoding retain];
}

-(O2Encoding *)createEncodingForTextEncoding:(O2TextEncoding)encoding {
   if(_ftEncoding==FT_ENCODING_APPLE_ROMAN)
    return [self MacRoman_createEncodingForTextEncoding:encoding];
    
   return [self unicode_createEncodingForTextEncoding:encoding];
}

@end
#endif
