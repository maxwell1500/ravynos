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
