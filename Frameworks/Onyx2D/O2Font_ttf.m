#import <Onyx2D/O2Font_ttf.h>
#import <Onyx2D/O2TTFDecoder.h>
#import <Onyx2D/O2Font_freetype.h>
#import <Onyx2D/O2DataProvider.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSData.h>
#include <string.h>

/* Fonts were unloadable before: both platform hooks were nil stubs, so
 * O2FontCreateWithFontName() returned nil for every name and all text drawing
 * silently produced nothing. The FreeType backend in O2Font_freetype.m is
 * complete; only the two entry points that reach it were missing. */

/* The shipped image has a fixed set of fonts, and enumerating
 * /System/Library/Fonts on this FAT32 image stalls under TCG (opendir alone never
 * returned). Map the names the frameworks ask for directly to their files. */
typedef struct {
   const char *name;
   const char *path;
} FontEntry;

static const FontEntry knownFonts[] = {
   { "Inter-Regular",       "/System/Library/Fonts/TTF/Inter-Regular.ttf" },
   { "Inter-Bold",          "/System/Library/Fonts/TTF/Inter-Bold.ttf" },
   { "Inter-Italic",        "/System/Library/Fonts/TTF/Inter-Italic.ttf" },
   { "Inter-BoldItalic",    "/System/Library/Fonts/TTF/Inter-BoldItalic.ttf" },
   { "NimbusSans-Regular",  "/System/Library/Fonts/TTF/NimbusSans-Regular.ttf" },
   { NULL, NULL },
};

static const char *pathForFontName(NSString *name) {
   for(int i = 0; knownFonts[i].name != NULL; i++)
      if([name isEqualToString:[NSString stringWithUTF8String:knownFonts[i].name]])
         return knownFonts[i].path;

   /* Accept a family name by falling through to the first matching style. */
   for(int i = 0; knownFonts[i].name != NULL; i++) {
      NSString *known = [NSString stringWithUTF8String:knownFonts[i].name];
      if([known hasPrefix:[NSString stringWithFormat:@"%@-", name]])
         return knownFonts[i].path;
   }
   return NULL;
}

NSArray *O2FontKnownFontNames(void) {
   NSMutableArray *result=[NSMutableArray array];

   for(int i = 0; knownFonts[i].name != NULL; i++)
      [result addObject:[NSString stringWithUTF8String:knownFonts[i].name]];

   return result;
}

@implementation O2Font_ttf

-initWithDataProvider:(O2DataProviderRef)provider {
   O2TTFDecoderRef decoder=O2TTFDecoderCreate(provider);

   _nameToGlyph=O2TTFDecoderGetPostScriptNameMapTable(decoder,&_numberOfGlyphs);
   _glyphLocations=O2TTFDecoderGetGlyphLocations(decoder,_numberOfGlyphs);
   return self;
}

-(O2Glyph)glyphWithGlyphName:(NSString *)name {
   return (O2Glyph)(int)NSMapGet(_nameToGlyph,name);
}

O2FontRef O2FontCreateWithFontName_platform(NSString *name) {
   if(name == nil)
    return NULL;

   const char *path = pathForFontName(name);
   if(path == NULL)
    return NULL;

   /* File-based face creation: the memory-provider path never returns on this
    * target even though the same file parses in ~0.1ms on the host. */
   return [[O2Font_freetype alloc] initWithFilename:path];
}

O2FontRef O2FontCreateWithDataProvider_platform(O2DataProviderRef provider) {
   if(provider == NULL)
    return NULL;

   return [[O2Font_freetype alloc] initWithDataProvider:provider];
}

@end
