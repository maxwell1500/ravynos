#import <Onyx2D/O2Font.h>
#import "O2Defines_FreeType.h"

#ifdef FREETYPE_PRESENT

#include <ft2build.h>
#include FT_FREETYPE_H

@interface O2Font_freetype : O2Font {
    FT_Face _face;
    FT_Encoding _ftEncoding;
    O2Encoding *_macRomanEncoding;
    O2Encoding *_macExpertEncoding;
    O2Encoding *_winAnsiEncoding;
    O2DataProviderRef _dataProvider;   /* FT_New_Memory_Face keeps the buffer */
}

- initWithDataProvider:(O2DataProviderRef)provider;
- (id)initWithFilename:(const char *)path;

/* AppKit's FreeType text paths (KTFont_FT.m, O2Context_builtin_FT.m) send
 * -face to the font object they are handed.  Only O2Font_FT -- a class this
 * build never instantiates -- implemented it, so the selector went
 * unrecognised on O2Font_freetype and SystemUIServer aborted with
 * "-[O2Font_freetype face]: unrecognized selector sent to instance". */
- (FT_Face)face;

FT_Face O2FontFreeTypeFace(O2Font_freetype *self);

@end

#endif
