#import <Onyx2D/O2Font_ttf.h>
#import <Onyx2D/O2TTFDecoder.h>
#import <Onyx2D/O2Font_freetype.h>
#import <Onyx2D/O2DataProvider.h>
#import <Onyx2D/O2Defines_FreeType.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSData.h>
#include <string.h>

#ifdef FREETYPE_PRESENT
#import <ft2build.h>
#include FT_FREETYPE_H
#include FT_SFNT_NAMES_H
#endif

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
   { "NimbusMonoPS-Regular", "/System/Library/Fonts/TTF/NimbusMonoPS-Regular.ttf" },
   { "NimbusMonoPS-Bold",   "/System/Library/Fonts/TTF/NimbusMonoPS-Bold.ttf" },
   { "NimbusRoman-Regular", "/System/Library/Fonts/TTF/NimbusRoman-Regular.ttf" },
   { "NimbusRoman-Bold",    "/System/Library/Fonts/TTF/NimbusRoman-Bold.ttf" },

   /* Canonical macOS / PDF face names.  PDF content streams name Helvetica,
    * Times-Roman and Courier directly, and AppKit asks for the system faces by
    * these names; without the aliases those lookups return nil and the text
    * silently draws nothing. */
   { "Helvetica",           "/System/Library/Fonts/TTF/Inter-Regular.ttf" },
   { "Arial",               "/System/Library/Fonts/TTF/Inter-Regular.ttf" },
   { "ArialMT",             "/System/Library/Fonts/TTF/Inter-Regular.ttf" },
   { "LucidaGrande",        "/System/Library/Fonts/TTF/Inter-Regular.ttf" },
   { "System",              "/System/Library/Fonts/TTF/Inter-Regular.ttf" },
   { "Helvetica-Bold",      "/System/Library/Fonts/TTF/Inter-Bold.ttf" },
   { "Arial-BoldMT",        "/System/Library/Fonts/TTF/Inter-Bold.ttf" },
   { "LucidaGrande-Bold",   "/System/Library/Fonts/TTF/Inter-Bold.ttf" },
   { "Helvetica-Oblique",   "/System/Library/Fonts/TTF/Inter-Italic.ttf" },
   { "Helvetica-Italic",    "/System/Library/Fonts/TTF/Inter-Italic.ttf" },
   { "Arial-ItalicMT",      "/System/Library/Fonts/TTF/Inter-Italic.ttf" },
   { "Courier",             "/System/Library/Fonts/TTF/NimbusMonoPS-Regular.ttf" },
   { "CourierNewPSMT",      "/System/Library/Fonts/TTF/NimbusMonoPS-Regular.ttf" },
   { "Monaco",              "/System/Library/Fonts/TTF/NimbusMonoPS-Regular.ttf" },
   { "Menlo",               "/System/Library/Fonts/TTF/NimbusMonoPS-Regular.ttf" },
   { "Menlo-Regular",       "/System/Library/Fonts/TTF/NimbusMonoPS-Regular.ttf" },
   { "Courier-Bold",        "/System/Library/Fonts/TTF/NimbusMonoPS-Bold.ttf" },
   { "Menlo-Bold",          "/System/Library/Fonts/TTF/NimbusMonoPS-Bold.ttf" },
   { "Times",               "/System/Library/Fonts/TTF/NimbusRoman-Regular.ttf" },
   { "Times-Roman",         "/System/Library/Fonts/TTF/NimbusRoman-Regular.ttf" },
   { "TimesNewRomanPSMT",   "/System/Library/Fonts/TTF/NimbusRoman-Regular.ttf" },
   { "Times-Bold",          "/System/Library/Fonts/TTF/NimbusRoman-Bold.ttf" },
   { NULL, NULL },
};

/* Dynamic discovery state. */
static NSMutableDictionary *sFontPathByName = nil;
static NSMutableArray *sDiscoveredFonts = nil;
static NSMutableDictionary *sDirMtime = nil;

static void ensureCollections(void) {
   if(sFontPathByName == nil)
      sFontPathByName = [[NSMutableDictionary alloc] init];
   if(sDiscoveredFonts == nil)
      sDiscoveredFonts = [[NSMutableArray alloc] init];
   if(sDirMtime == nil)
      sDirMtime = [[NSMutableDictionary alloc] init];
}

#ifdef FREETYPE_PRESENT
static FT_Library sFreeTypeLibrary = NULL;
static FT_Library freeTypeLibrary(void) {
   if(sFreeTypeLibrary == NULL)
      FT_Init_FreeType(&sFreeTypeLibrary);
   return sFreeTypeLibrary;
}
#endif

static NSString *pathStringForFontName(NSString *name) {
   if(name == nil)
      return nil;

   for(int i = 0; knownFonts[i].name != NULL; i++)
      if([name isEqualToString:[NSString stringWithUTF8String:knownFonts[i].name]])
         return [NSString stringWithUTF8String:knownFonts[i].path];

   /* Accept a family name by falling through to the first matching style. */
   for(int i = 0; knownFonts[i].name != NULL; i++) {
      NSString *known = [NSString stringWithUTF8String:knownFonts[i].name];
      if([known hasPrefix:[NSString stringWithFormat:@"%@-", name]])
         return [NSString stringWithUTF8String:knownFonts[i].path];
   }

   ensureCollections();
   NSString *dyn = [sFontPathByName objectForKey:name];
   if(dyn != nil)
      return dyn;

   [O2Font_ttf loadAllFontsInDirectories];

   return [sFontPathByName objectForKey:name];
}

NSArray *O2FontKnownFontNames(void) {
   NSMutableArray *result=[NSMutableArray array];

   for(int i = 0; knownFonts[i].name != NULL; i++)
      [result addObject:[NSString stringWithUTF8String:knownFonts[i].name]];

   ensureCollections();
   [O2Font_ttf loadAllFontsInDirectories];
   [result addObjectsFromArray:[sFontPathByName allKeys]];

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

+ (void)loadAllFontsInDirectories {
   ensureCollections();

#ifdef FREETYPE_PRESENT
   NSArray *dirs = [NSArray arrayWithObjects:
      @"/System/Library/Fonts",
      @"/System/Library/Fonts/TTF",
      @"/Library/Fonts",
      [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Fonts"],
      nil];

   for(NSString *dir in dirs) {
      NSFileManager *fm = [NSFileManager defaultManager];
      BOOL isDir = NO;
      if(![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir)
         continue;

      NSDictionary *attrs = [fm attributesOfItemAtPath:dir error:nil];
      NSDate *mtime = [attrs fileModificationDate];
      NSNumber *prev = [sDirMtime objectForKey:dir];
      BOOL changed = NO;
      if(prev == nil) {
         changed = YES;
      } else if(mtime != nil && [mtime timeIntervalSince1970] != [prev doubleValue]) {
         changed = YES;
      }
      if(mtime != nil)
         [sDirMtime setObject:[NSNumber numberWithDouble:[mtime timeIntervalSince1970]] forKey:dir];

      if(!changed)
         continue;

      NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
      for(NSString *item in items) {
         NSString *full = [dir stringByAppendingPathComponent:item];
         BOOL subIsDir = NO;
         [fm fileExistsAtPath:full isDirectory:&subIsDir];
         if(subIsDir)
            continue;
         NSString *ext = [[item pathExtension] lowercaseString];
         if(![ext isEqualToString:@"ttf"] && ![ext isEqualToString:@"otf"])
            continue;
         /* Inter.ttc alone is ~10 MB and enumerating a collection face by face
          * stalls the guest for seconds under TCG; the individual Inter-*.ttf
          * files in TTF/ already cover every face NSFontManager asks for. */
         [O2Font_ttf registerFontFileAtPath:full];
      }
   }
#endif
}

+ (BOOL)registerFontFileAtPath:(NSString *)path {
#ifdef FREETYPE_PRESENT
   if(path == nil)
      return NO;
   ensureCollections();

   FT_Library lib = freeTypeLibrary();
   if(lib == NULL)
      return NO;

   FT_Face face;
   if(FT_New_Face(lib, [path UTF8String], 0, &face) != 0)
      return NO;

   const char *psNameC = FT_Get_Postscript_Name(face);
   NSString *postscript = nil;
   if(psNameC != NULL)
      postscript = [NSString stringWithUTF8String:psNameC];
   if(postscript == nil || [postscript length] == 0) {
      NSString *fam = (face->family_name != NULL) ? [NSString stringWithUTF8String:face->family_name] : @"Unknown";
      NSString *sty = (face->style_name != NULL) ? [NSString stringWithUTF8String:face->style_name] : @"Regular";
      fam = [fam stringByReplacingOccurrencesOfString:@" " withString:@""];
      sty = [sty stringByReplacingOccurrencesOfString:@" " withString:@""];
      if([sty length] == 0)
         sty = @"Regular";
      postscript = [NSString stringWithFormat:@"%@-%@", fam, sty];
   }

   if([sFontPathByName objectForKey:postscript] != nil) {
      FT_Done_Face(face);
      return YES;
   }

   NSString *family = (face->family_name != NULL) ? [NSString stringWithUTF8String:face->family_name] : postscript;
   NSString *style = (face->style_name != NULL) ? [NSString stringWithUTF8String:face->style_name] : @"Regular";
   if([style length] == 0)
      style = @"Regular";

   /* Version string from SFNT 'name' table (name ID 5). */
   NSString *version = @"Unknown";
   FT_UInt nameCount = FT_Get_Sfnt_Name_Count(face);
   for(FT_UInt i = 0; i < nameCount; i++) {
      FT_SfntName sfntName;
      if(FT_Get_Sfnt_Name(face, i, &sfntName) == 0 && sfntName.name_id == 5) {
         NSString *s = [[NSString alloc] initWithBytes:sfntName.string
                                                  length:sfntName.string_len
                                                encoding:NSUTF8StringEncoding];
         if(s == nil)
            s = [[NSString alloc] initWithBytes:sfntName.string
                                         length:sfntName.string_len
                                       encoding:NSASCIIStringEncoding];
         if(s != nil) {
            version = s;
            break;
         }
      }
   }

   int glyphCount = (int)face->num_glyphs;

   [sFontPathByName setObject:path forKey:postscript];

   NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
      family, @"Family",
      style, @"Style",
      postscript, @"PostScriptName",
      [NSNumber numberWithInt:glyphCount], @"GlyphCount",
      version, @"Version",
      path, @"FilePath",
      nil];
   [sDiscoveredFonts addObject:entry];

   FT_Done_Face(face);
   return YES;
#else
   return NO;
#endif
}

+ (BOOL)validateFontFileAtPath:(NSString *)path missingTables:(NSArray **)outMissing {
#ifdef FREETYPE_PRESENT
   if(path == nil) {
      if(outMissing) *outMissing = [NSArray arrayWithObject:@"No path"];
      return NO;
   }
   FT_Library lib = freeTypeLibrary();
   if(lib == NULL) {
      if(outMissing) *outMissing = [NSArray arrayWithObject:@"FreeType init failed"];
      return NO;
   }
   FT_Face face;
   if(FT_New_Face(lib, [path UTF8String], 0, &face) != 0) {
      if(outMissing) *outMissing = [NSArray arrayWithObject:@"Cannot open font file"];
      return NO;
   }

   NSMutableArray *missing = [NSMutableArray array];
   FT_ULong len = 0;

#define CHECK_TABLE(tagStr, tag) \
   len = 0; \
   if(FT_Load_Sfnt_Table(face, (tag), 0, NULL, &len) != 0 || len == 0) \
      [missing addObject:@(tagStr)];

   CHECK_TABLE("head", FT_MAKE_TAG('h','e','a','d'));
   CHECK_TABLE("hhea", FT_MAKE_TAG('h','h','e','a'));
   CHECK_TABLE("maxp", FT_MAKE_TAG('m','a','x','p'));
   CHECK_TABLE("cmap", FT_MAKE_TAG('c','m','a','p'));
   CHECK_TABLE("name", FT_MAKE_TAG('n','a','m','e'));
   CHECK_TABLE("post", FT_MAKE_TAG('p','o','s','t'));

   FT_ULong glyfLen = 0, cffLen = 0;
   BOOL glyfOk = (FT_Load_Sfnt_Table(face, FT_MAKE_TAG('g','l','y','f'), 0, NULL, &glyfLen) == 0 && glyfLen > 0);
   BOOL cffOk = (FT_Load_Sfnt_Table(face, FT_MAKE_TAG('C','F','F',' '), 0, NULL, &cffLen) == 0 && cffLen > 0);
   if(!glyfOk && !cffOk)
      [missing addObject:@"glyf/CFF "];

#undef CHECK_TABLE

   FT_Done_Face(face);

   if(outMissing)
      *outMissing = missing;
   return [missing count] == 0;
#else
   if(outMissing) *outMissing = [NSArray arrayWithObject:@"FreeType unavailable"];
   return NO;
#endif
}

+ (NSArray *)discoveredFonts {
   [O2Font_ttf loadAllFontsInDirectories];
   ensureCollections();
   return [NSArray arrayWithArray:sDiscoveredFonts];
}

O2FontRef O2FontCreateWithFontName_platform(NSString *name) {
   if(name == nil)
    return NULL;

   NSString *path = pathStringForFontName(name);
   if(path == nil)
    return NULL;

   /* File-based face creation: the memory-provider path never returns on this
    * target even though the same file parses in ~0.1ms on the host. */
   return [[O2Font_freetype alloc] initWithFilename:[path UTF8String]];
}

O2FontRef O2FontCreateWithDataProvider_platform(O2DataProviderRef provider) {
   if(provider == NULL)
    return NULL;

   return [[O2Font_freetype alloc] initWithDataProvider:provider];
}

@end