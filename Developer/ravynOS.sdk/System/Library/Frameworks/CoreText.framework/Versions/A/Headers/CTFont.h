/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files(the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <CoreText/CoreTextExport.h>
#import <CoreGraphics/CGAffineTransform.h>
#import <CoreGraphics/CGFont.h>
#import <CoreGraphics/CGPath.h>
#import <CoreFoundation/CoreFoundation.h>

@class KTFont;

typedef KTFont *CTFontRef;
typedef struct __CTFontDescriptor *CTFontDescriptorRef;
typedef struct __CTFontCollection *CTFontCollectionRef;
#ifndef RAVYN_CTFONTSYMBOLICTRAITS_DEFINED
#define RAVYN_CTFONTSYMBOLICTRAITS_DEFINED
typedef uint32_t CTFontSymbolicTraits;
#endif

typedef enum {
    kCTFontSystemFontType = 2,
    kCTFontEmphasizedSystemFontType = 3,
    kCTFontSmallSystemFontType = 4,
    kCTFontSmallEmphasizedSystemFontType = 5,
    kCTFontMiniSystemFontType = 6,
    kCTFontMiniEmphasizedSystemFontType = 7,
    kCTFontViewsFontType = 8,
    kCTFontApplicationFontType = 9,
    kCTFontLabelFontType = 10,
    kCTFontMenuTitleFontType = 11,
    kCTFontMenuItemFontType = 12,
    kCTFontMenuItemMarkFontType = 13,
    kCTFontMenuItemCmdKeyFontType = 14,
    kCTFontWindowTitleFontType = 15,
    kCTFontPushButtonFontType = 16,
    kCTFontUtilityWindowTitleFontType = 17,
    kCTFontAlertHeaderFontType = 18,
    kCTFontSystemDetailFontType = 19,
    kCTFontEmphasizedSystemDetailFontType = 20,
    kCTFontToolbarFontType = 21,
    kCTFontSmallToolbarFontType = 22,
    kCTFontMessageFontType = 23,
    kCTFontPaletteFontType = 24,
    kCTFontToolTipFontType = 25,
    kCTFontControlContentFontType = 26
} CTFontUIFontType;

CORETEXT_EXPORT CTFontRef CTFontCreateWithGraphicsFont(CGFontRef cgFont, CGFloat size, CGAffineTransform *xform, id attributes);
CORETEXT_EXPORT CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType uiFontType, CGFloat size, NSString *language);
CORETEXT_EXPORT CFStringRef CTFontCopyFullName(CTFontRef self);
CORETEXT_EXPORT CFStringRef CTFontCopyFamilyName(CTFontRef self);
CORETEXT_EXPORT CFStringRef CTFontCopyPostScriptName(CTFontRef self);
CORETEXT_EXPORT CFStringRef CTFontCopyDisplayName(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetSize(CTFontRef self);
CORETEXT_EXPORT size_t CTFontGetGlyphCount(CTFontRef self);
CORETEXT_EXPORT BOOL CTFontGetGlyphsForCharacters(CTFontRef self, const unichar *characters, CGGlyph *glyphs, size_t count);
CORETEXT_EXPORT CGGlyph CTFontGetGlyphForCharacter(CTFontRef self, unichar character);
CORETEXT_EXPORT CGRect CTFontGetBoundingBox(CTFontRef self);
CORETEXT_EXPORT void CTFontGetAdvancesForGlyphs(CTFontRef self, int orientation, const CGGlyph *glyphs, CGSize *advances, size_t count);
CORETEXT_EXPORT CGFloat CTFontGetUnderlinePosition(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetUnderlineThickness(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetAscent(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetDescent(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetLeading(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetSlantAngle(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetXHeight(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetCapHeight(CTFontRef self);
CORETEXT_EXPORT CGPathRef CTFontCreatePathForGlyph(CTFontRef self, CGGlyph glyph, CGAffineTransform *xform);


/* Font descriptor attributes.  These are real CFString keys: callers
 * compare them by pointer or contents. */
extern NSString * const kCTFontNameAttribute;
extern NSString * const kCTFontSizeAttribute;
extern NSString * const kCTFontFamilyNameAttribute;

CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes);
CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size);
CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef descriptor, CFDictionaryRef attributes);
CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor);
CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute);
CFArrayRef CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef descriptor, CFSetRef mandatoryAttributes);
CFTypeID CTFontDescriptorGetTypeID(void);

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const CGAffineTransform *matrix);
CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size, const CGAffineTransform *matrix);
CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size, const CGAffineTransform *matrix, CTFontDescriptorRef attributes);
CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size, const CGAffineTransform *matrix, CTFontSymbolicTraits symTraitValue, CTFontSymbolicTraits symTraitMask);
CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef font);
CFTypeRef CTFontCopyAttribute(CTFontRef font, CFStringRef attribute);


CTFontCollectionRef CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef options);
CTFontCollectionRef CTFontCollectionCreateWithFontDescriptors(CFArrayRef descriptors, CFDictionaryRef options);
CFArrayRef CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef collection, CFSetRef mandatoryAttributes);
CFTypeID CTFontCollectionGetTypeID(void);
CFArrayRef CTFontManagerCopyAvailablePostScriptNames(void);
