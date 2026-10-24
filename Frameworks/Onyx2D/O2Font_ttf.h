#import <Onyx2D/O2Font.h>

@class NSMapTable;

@interface O2Font_ttf : O2Font {
    NSMapTable *_nameToGlyph;
    int *_glyphLocations;
}

- initWithDataProvider:(O2DataProviderRef)provider;

/* Dynamic font discovery: scan the standard font directories and register
 * every TrueType/OpenType/TrueType-Collection face found there so that
 * O2FontCreateWithFontName() (and therefore +[NSFont fontWithName:size:])
 * can resolve them.  Safe to call repeatedly; directories are only
 * re-scanned when their modification time changes. */
+ (void)loadAllFontsInDirectories;
+ (BOOL)registerFontFileAtPath:(NSString *)path;

/* Returns YES and an empty/nil missing list when the font file opens cleanly
 * and contains the SFNT tables required by the Font Book validator. */
+ (BOOL)validateFontFileAtPath:(NSString *)path missingTables:(NSArray **)outMissing;

/* Inventory of every discovered face: dictionaries with keys
 * "Family", "Style", "PostScriptName", "GlyphCount", "Version", "FilePath". */
+ (NSArray *)discoveredFonts;

@end