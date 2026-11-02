/*
 * CoreText attribute and option keys, plus the font-variation axis keys.
 *
 * XUL binds kCT* at load ("Symbol not found: _kCTFontAttributeName",
 * "Expected in: CoreText").  These are dictionary keys compared by pointer or
 * contents inside the application, so each is a real NSString with the
 * documented name; behaviour behind them is CoreText's own.
 */
#import <Foundation/Foundation.h>

NSString * const kCTFontAttributeName = @"kCTFontAttributeName";
NSString * const kCTFontCollectionRemoveDuplicatesOption = @"kCTFontCollectionRemoveDuplicatesOption";
NSString * const kCTFontDisplayNameAttribute = @"kCTFontDisplayNameAttribute";
NSString * const kCTFontFamilyNameAttribute = @"kCTFontFamilyNameAttribute";
NSString * const kCTFontFamilyNameKey = @"kCTFontFamilyNameKey";
NSString * const kCTFontFeatureSelectorIdentifierKey = @"kCTFontFeatureSelectorIdentifierKey";
NSString * const kCTFontFeatureSettingsAttribute = @"kCTFontFeatureSettingsAttribute";
NSString * const kCTFontFeatureTypeIdentifierKey = @"kCTFontFeatureTypeIdentifierKey";
NSString * const kCTFontFormatAttribute = @"kCTFontFormatAttribute";
NSString * const kCTFontFullNameKey = @"kCTFontFullNameKey";
NSString * const kCTFontManagerRegisteredFontsChangedNotification = @"kCTFontManagerRegisteredFontsChangedNotification";
NSString * const kCTFontNameAttribute = @"kCTFontNameAttribute";
NSString * const kCTFontPostScriptNameKey = @"kCTFontPostScriptNameKey";
NSString * const kCTFontSlantTrait = @"kCTFontSlantTrait";
NSString * const kCTFontStyleNameAttribute = @"kCTFontStyleNameAttribute";
NSString * const kCTFontStyleNameKey = @"kCTFontStyleNameKey";
NSString * const kCTFontSubFamilyNameKey = @"kCTFontSubFamilyNameKey";
NSString * const kCTFontSymbolicTrait = @"kCTFontSymbolicTrait";
NSString * const kCTFontTraitsAttribute = @"kCTFontTraitsAttribute";
NSString * const kCTFontURLAttribute = @"kCTFontURLAttribute";
NSString * const kCTFontUniqueNameKey = @"kCTFontUniqueNameKey";
NSString * const kCTFontVariationAttribute = @"kCTFontVariationAttribute";
NSString * const kCTFontVariationAxisDefaultValueKey = @"kCTFontVariationAxisDefaultValueKey";
NSString * const kCTFontVariationAxisIdentifierKey = @"kCTFontVariationAxisIdentifierKey";
NSString * const kCTFontVariationAxisMaximumValueKey = @"kCTFontVariationAxisMaximumValueKey";
NSString * const kCTFontVariationAxisMinimumValueKey = @"kCTFontVariationAxisMinimumValueKey";
NSString * const kCTFontWeightTrait = @"kCTFontWeightTrait";
NSString * const kCTFontWidthTrait = @"kCTFontWidthTrait";
NSString * const kCTWritingDirectionAttributeName = @"kCTWritingDirectionAttributeName";

/*
 * Font manager entry points.  XUL binds _CTFontManagerRegisterFontsForURLs at
 * load ("dyld: Symbol not found: _CTFontManagerRegisterFontsForURLs"), and
 * without the symbol the process aborts before it can draw anything.
 *
 * Registration itself is not implemented: the honest answer is "no", with the
 * error dictionaries left empty the way CoreText leaves them when nothing was
 * registered.  Callers keep running (Firefox merely loses the supplementary
 * fonts it wanted to add), and the log names the gap exactly once.
 */
typedef CFIndex CTFontManagerScope;

static void
_ravyn_font_manager_gap(const char *symbol)
{
	static Boolean logged = false;
	if (!logged) {
		logged = true;
		fprintf(stderr, "[compat] CoreText: %s is not implemented\n", symbol);
	}
}

bool
CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope,
    CFErrorRef *error)
{
	(void)fontURL;
	(void)scope;
	_ravyn_font_manager_gap("CTFontManagerRegisterFontsForURL");
	if (error)
		*error = NULL;
	return false;
}

bool
CTFontManagerRegisterFontsForURLs(CFArrayRef fontURLs, CTFontManagerScope scope,
    CFArrayRef *errors)
{
	(void)fontURLs;
	(void)scope;
	_ravyn_font_manager_gap("CTFontManagerRegisterFontsForURLs");
	if (errors)
		*errors = NULL;
	return false;
}

bool
CTFontManagerUnregisterFontsForURLs(CFArrayRef fontURLs, CTFontManagerScope scope,
    CFArrayRef *errors)
{
	(void)fontURLs;
	(void)scope;
	_ravyn_font_manager_gap("CTFontManagerUnregisterFontsForURLs");
	if (errors)
		*errors = NULL;
	return false;
}
