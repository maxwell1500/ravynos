/*
 * CoreText attribute and option keys, plus the font-variation axis keys.
 *
 * XUL binds kCT* at load ("Symbol not found: _kCTFontAttributeName",
 * "Expected in: CoreText").  These are dictionary keys compared by pointer or
 * contents inside the application, so each is a real NSString with the
 * documented name; behaviour behind them is CoreText's own.
 */
#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font.h>
#import <CoreText/CTFont.h>
#import <Foundation/NSCFTypeID.h>
#import <objc/runtime.h>
#include "CFRuntime.h"
#import "KTFont.h"
#import <CoreGraphics/CoreGraphics.h>

static CFArrayRef ravyn_wrap_array(CFArrayRef array);
static CFArrayRef ravyn_wrap_nsarray(NSArray *array);

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
NSString * const kCTFontSizeAttribute = @"kCTFontSizeAttribute";
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

/*
 * The families this platform can resolve, from the same name table the
 * font lookup uses (O2FontKnownFontNames).  A face name is PostScript
 * style ("Helvetica-Bold"); the part before the dash is the family.
 */
CFArrayRef
CTFontManagerCopyAvailableFontFamilyNames(void)
{
    NSArray *names = O2FontKnownFontNames();
    NSMutableArray *families = [NSMutableArray array];
    NSUInteger i, count = [names count];
    CFArrayRef wrapped;

    for (i = 0; i < count; i++) {
        NSString *name = [names objectAtIndex:i];
        NSRange dash = [name rangeOfString:@"-"];
        NSString *family = (dash.location == NSNotFound)
            ? name : [name substringToIndex:dash.location];
        if (![families containsObject:family])
            [families addObject:family];
    }
    wrapped = ravyn_wrap_nsarray(families);
    return wrapped;
}


/*
 * CTFontDescriptor is a real CF object: callers retain, release, compare and
 * hash it.  It owns an immutable attribute dictionary; the name and size
 * attributes are the only ones this font engine acts on.
 */
static void
ravyn_dictionary_set_value(const void *key, const void *value, void *context)
{
    CFDictionarySetValue((CFMutableDictionaryRef)context, key, value);
}

typedef struct {
    CFRuntimeBase base;
    CFDictionaryRef attributes;
} RavynFontDescriptor;

static void
ravyn_fd_finalize(CFTypeRef cf)
{
    RavynFontDescriptor *descriptor = (RavynFontDescriptor *)cf;

    if (descriptor->attributes != NULL) {
        CFRelease(descriptor->attributes);
        descriptor->attributes = NULL;
    }
}

static Boolean
ravyn_fd_equal(CFTypeRef cf1, CFTypeRef cf2)
{
    return CFEqual(((RavynFontDescriptor *)cf1)->attributes,
        ((RavynFontDescriptor *)cf2)->attributes);
}

static CFHashCode
ravyn_fd_hash(CFTypeRef cf)
{
    return CFHash(((RavynFontDescriptor *)cf)->attributes);
}

static CFStringRef
ravyn_fd_copy_description(CFTypeRef cf)
{
    return CFStringCreateWithFormat(NULL, NULL,
        CFSTR("<CTFontDescriptor %p>"), cf);
}

CFTypeID
CTFontDescriptorGetTypeID(void)
{
    /*
     * _CFRuntimeRegisterClass stores the pointer it is given, so the class
     * description must outlive this call.  A stack local here left the type
     * table pointing at a dead frame; the next CFRelease ran a finaliser
     * address read from stack garbage and jumped into the stack.
     */
    static CFRuntimeClass cls;
    static CFTypeID typeID = _kCFRuntimeNotATypeID;

    if (typeID == _kCFRuntimeNotATypeID) {
        memset(&cls, 0, sizeof(cls));
        cls.version = 0;
        cls.className = "CTFontDescriptor";
        cls.finalize = ravyn_fd_finalize;
        cls.equal = ravyn_fd_equal;
        cls.hash = ravyn_fd_hash;
        cls.copyDebugDesc = ravyn_fd_copy_description;
        typeID = _CFRuntimeRegisterClass(&cls);
    }
    return typeID;
}

static CTFontDescriptorRef
ravyn_fd_create(CFDictionaryRef attributes)
{
    RavynFontDescriptor *descriptor;

    descriptor = (RavynFontDescriptor *)_CFRuntimeCreateInstance(NULL,
        CTFontDescriptorGetTypeID(),
        sizeof(RavynFontDescriptor) - sizeof(CFRuntimeBase), NULL);
    if (descriptor == NULL) {
        return NULL;
    }
    descriptor->attributes = (attributes != NULL)
        ? CFDictionaryCreateCopy(NULL, attributes)
        : CFDictionaryCreate(NULL, NULL, NULL, 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    return (CTFontDescriptorRef)descriptor;
}

CTFontDescriptorRef
CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes)
{
    CTFontDescriptorRef d = ravyn_fd_create(attributes);
    return d;
}

CTFontDescriptorRef
CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size)
{
    CFMutableDictionaryRef attributes;
    CFNumberRef number;
    CTFontDescriptorRef descriptor;

    attributes = CFDictionaryCreateMutable(NULL, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (name != NULL) {
        CFDictionarySetValue(attributes, kCTFontNameAttribute, name);
    }
    number = CFNumberCreate(NULL, kCFNumberDoubleType, &size);
    CFDictionarySetValue(attributes, kCTFontSizeAttribute, number);
    CFRelease(number);

    descriptor = ravyn_fd_create(attributes);
    CFRelease(attributes);
    return descriptor;
}

CTFontDescriptorRef
CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef descriptor,
    CFDictionaryRef attributes)
{
    CFMutableDictionaryRef merged;

    if (descriptor == NULL) {
        return ravyn_fd_create(attributes);
    }
    merged = CFDictionaryCreateMutableCopy(NULL, 0,
        ((RavynFontDescriptor *)descriptor)->attributes);
    if (attributes != NULL) {
        CFDictionaryApplyFunction(attributes, (CFDictionaryApplierFunction)
            ravyn_dictionary_set_value, merged);
    }
    descriptor = ravyn_fd_create(merged);
    CFRelease(merged);
    return descriptor;
}

CFDictionaryRef
CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor)
{
    if (descriptor == NULL) {
        return NULL;
    }
    return CFDictionaryCreateCopy(NULL,
        ((RavynFontDescriptor *)descriptor)->attributes);
}

CFTypeRef
CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor,
    CFStringRef attribute)
{
    CFTypeRef value;

    if (descriptor == NULL || attribute == NULL) {
        return NULL;
    }
    value = CFDictionaryGetValue(((RavynFontDescriptor *)descriptor)->attributes,
        attribute);
    return (value != NULL) ? CFRetain(value) : NULL;
}

CFArrayRef
CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef descriptor,
    CFSetRef mandatoryAttributes)
{
    CFMutableArrayRef result;
    CFStringRef requestedName = NULL;
    CFStringRef requestedFamily = NULL;
    NSArray *known;
    NSUInteger i, count;

    (void)mandatoryAttributes;
    result = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (descriptor == NULL) {
        return result;
    }
    requestedName = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor,
        kCTFontNameAttribute);
    requestedFamily = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor,
        kCTFontFamilyNameAttribute);

    known = O2FontKnownFontNames();
    count = [known count];
    for (i = 0; i < count; i++) {
        NSString *face = [known objectAtIndex:i];
        NSRange dash = [face rangeOfString:@"-"];
        NSString *family = (dash.location == NSNotFound)
            ? face : [face substringToIndex:dash.location];
        Boolean nameMatches = (requestedName == NULL)
            || [(NSString *)requestedName isEqualToString:face];
        Boolean familyMatches = (requestedFamily == NULL)
            || [(NSString *)requestedFamily caseInsensitiveCompare:family]
                == NSOrderedSame;

        if (nameMatches && familyMatches) {
            CFMutableDictionaryRef attributes;
            CFNumberRef number;
            double size = 12.0;
            CTFontDescriptorRef match;

            attributes = CFDictionaryCreateMutable(NULL, 3,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks);
            CFDictionarySetValue(attributes, kCTFontNameAttribute, face);
            CFDictionarySetValue(attributes, kCTFontFamilyNameAttribute,
                family);
            number = CFNumberCreate(NULL, kCFNumberDoubleType, &size);
            CFDictionarySetValue(attributes, kCTFontSizeAttribute, number);
            CFRelease(number);
            match = ravyn_fd_create(attributes);
            CFRelease(attributes);
            if (match != NULL) {
                CFArrayAppendValue(result, match);
                CFRelease(match);
            }
        }
    }
    if (requestedName != NULL) {
        CFRelease(requestedName);
    }
    if (requestedFamily != NULL) {
        CFRelease(requestedFamily);
    }
    return result;
}

CTFontRef
CTFontCreateWithName(CFStringRef name, CGFloat size,
    const CGAffineTransform *matrix)
{
    CGFontRef cgFont;
    KTFont *font;

    (void)matrix;
    if (name == NULL) {
        return NULL;
    }
    cgFont = CGFontCreateWithFontName(name);
    if (cgFont == NULL) {
        return NULL;
    }
    font = [[KTFont alloc] initWithFont:cgFont size:size];
    CGFontRelease(cgFont);
    return (CTFontRef)font;
}

CTFontRef
CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size,
    const CGAffineTransform *matrix)
{
    CFStringRef name;
    CFNumberRef number;
    double descriptorSize;

    if (descriptor == NULL) {
        return NULL;
    }
    name = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor,
        kCTFontNameAttribute);
    if (name == NULL) {
        name = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor,
            kCTFontFamilyNameAttribute);
    }
    if (name == NULL) {
        return NULL;
    }
    if (size == 0.0) {
        number = (CFNumberRef)CTFontDescriptorCopyAttribute(descriptor,
            kCTFontSizeAttribute);
        if (number != NULL) {
            CFNumberGetValue(number, kCFNumberDoubleType, &descriptorSize);
            size = descriptorSize;
            CFRelease(number);
        }
    }
    if (size == 0.0) {
        size = 12.0;
    }
    {
        CTFontRef font = CTFontCreateWithName(name, size, matrix);

        CFRelease(name);
        return font;
    }
}

CTFontRef
CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size,
    const CGAffineTransform *matrix, CTFontDescriptorRef attributes)
{
    if (attributes != NULL) {
        return CTFontCreateWithFontDescriptor(attributes, size, matrix);
    }
    if (font == NULL) {
        return NULL;
    }
    if (size == 0.0) {
        size = CTFontGetSize(font);
    }
    {
        CFStringRef name = CTFontCopyPostScriptName(font);
        CTFontRef copy = (name != NULL)
            ? CTFontCreateWithName(name, size, matrix) : NULL;

        if (name != NULL) {
            CFRelease(name);
        }
        return copy;
    }
}

CTFontRef
CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size,
    const CGAffineTransform *matrix, CTFontSymbolicTraits symTraitValue,
    CTFontSymbolicTraits symTraitMask)
{
    static Boolean logged = false;

    (void)symTraitValue;
    (void)symTraitMask;
    if (!logged) {
        logged = true;
        fprintf(stderr,
            "[compat] CoreText: symbolic traits are not synthesised; "
            "returning the base face\n");
    }
    return CTFontCreateCopyWithAttributes(font, size, matrix, NULL);
}

CTFontDescriptorRef
CTFontCopyFontDescriptor(CTFontRef font)
{
    CFStringRef name;
    CFMutableDictionaryRef attributes;
    CFNumberRef number;
    double size;
    CTFontDescriptorRef descriptor;

    if (font == NULL) {
        return NULL;
    }
    name = CTFontCopyPostScriptName(font);
    size = CTFontGetSize(font);
    attributes = CFDictionaryCreateMutable(NULL, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (name != NULL) {
        CFDictionarySetValue(attributes, kCTFontNameAttribute, name);
        CFRelease(name);
    }
    number = CFNumberCreate(NULL, kCFNumberDoubleType, &size);
    CFDictionarySetValue(attributes, kCTFontSizeAttribute, number);
    CFRelease(number);

    descriptor = ravyn_fd_create(attributes);
    CFRelease(attributes);
    return descriptor;
}

CFTypeRef
CTFontCopyAttribute(CTFontRef font, CFStringRef attribute)
{
    CTFontDescriptorRef descriptor;
    CFTypeRef value;

    descriptor = CTFontCopyFontDescriptor(font);
    if (descriptor == NULL) {
        return NULL;
    }
    value = CTFontDescriptorCopyAttribute(descriptor, attribute);
    CFRelease(descriptor);
    return value;
}


/*
 * CTFontCollection.  Gecko enumerates the installed fonts through this API;
 * with no implementation it reports "no fonts" and aborts before it can draw.
 * The collection is a thin CF object over an array of CTFontDescriptorRef.
 */
typedef struct {
    CFRuntimeBase base;
    CFArrayRef descriptors;
} RavynFontCollection;

static void
ravyn_fc_finalize(CFTypeRef cf)
{
    RavynFontCollection *collection = (RavynFontCollection *)cf;

    if (collection->descriptors != NULL) {
        CFRelease(collection->descriptors);
        collection->descriptors = NULL;
    }
}

static CFStringRef
ravyn_fc_copy_description(CFTypeRef cf)
{
    return CFStringCreateWithFormat(NULL, NULL,
        CFSTR("<CTFontCollection %p>"), cf);
}

CFTypeID
CTFontCollectionGetTypeID(void)
{
    static CFRuntimeClass cls;
    static CFTypeID typeID = _kCFRuntimeNotATypeID;

    if (typeID == _kCFRuntimeNotATypeID) {
        memset(&cls, 0, sizeof(cls));
        cls.version = 0;
        cls.className = "CTFontCollection";
        cls.finalize = ravyn_fc_finalize;
        cls.copyDebugDesc = ravyn_fc_copy_description;
        typeID = _CFRuntimeRegisterClass(&cls);
    }
    return typeID;
}

static CTFontCollectionRef
ravyn_fc_create(CFArrayRef descriptors)
{
    RavynFontCollection *collection;

    collection = (RavynFontCollection *)_CFRuntimeCreateInstance(NULL,
        CTFontCollectionGetTypeID(),
        sizeof(RavynFontCollection) - sizeof(CFRuntimeBase), NULL);
    if (collection == NULL) {
        return NULL;
    }
    collection->descriptors = (descriptors != NULL)
        ? CFArrayCreateCopy(NULL, descriptors)
        : CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    return (CTFontCollectionRef)collection;
}

static CFArrayRef
ravyn_descriptors_for_known_fonts(void)
{
    CFMutableArrayRef result;
    NSArray *names = O2FontKnownFontNames();
    NSUInteger i, count = [names count];

    result = CFArrayCreateMutable(NULL, (CFIndex)count,
        &kCFTypeArrayCallBacks);
    for (i = 0; i < count; i++) {
        NSString *name = [names objectAtIndex:i];
        NSRange dash = [name rangeOfString:@"-"];
        NSString *family = (dash.location == NSNotFound)
            ? name : [name substringToIndex:dash.location];
        CFMutableDictionaryRef attributes;
        CFNumberRef size;
        double pointSize = 12.0;
        CTFontDescriptorRef descriptor;

        attributes = CFDictionaryCreateMutable(NULL, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(attributes, kCTFontNameAttribute, name);
        CFDictionarySetValue(attributes, kCTFontFamilyNameAttribute, family);
        size = CFNumberCreate(NULL, kCFNumberDoubleType, &pointSize);
        CFDictionarySetValue(attributes, kCTFontSizeAttribute, size);
        CFRelease(size);

        descriptor = ravyn_fd_create(attributes);
        CFRelease(attributes);
        if (descriptor != NULL) {
            CFArrayAppendValue(result, descriptor);
            CFRelease(descriptor);
        }
    }
    return result;
}

CTFontCollectionRef
CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef options)
{
    CFArrayRef descriptors;
    CTFontCollectionRef collection;

    (void)options;
    descriptors = ravyn_descriptors_for_known_fonts();
    collection = ravyn_fc_create(descriptors);
    CFRelease(descriptors);
    return collection;
}

CTFontCollectionRef
CTFontCollectionCreateWithFontDescriptors(CFArrayRef descriptors,
    CFDictionaryRef options)
{
    (void)options;
    return ravyn_fc_create(descriptors);
}

CFArrayRef
CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef collection,
    CFSetRef mandatoryAttributes)
{
    (void)mandatoryAttributes;
    if (collection == NULL) {
        return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    }
    {
        CFArrayRef r = CFArrayCreateCopy(NULL,
            ((RavynFontCollection *)collection)->descriptors);
        CFArrayRef wrapped;
        wrapped = ravyn_wrap_array(r);
        CFRelease(r);
        return wrapped;
    }
}

CFArrayRef
CTFontManagerCopyAvailablePostScriptNames(void)
{
    return ravyn_wrap_nsarray(O2FontKnownFontNames());
}


/*
 * CFArray is toll-free bridged to NSArray on macOS.  Gecko fast-enumerates
 * arrays returned by CoreText (font family names, matching descriptors), and
 * a C CFArray does not respond to countByEnumeratingWithState:.  This wrapper
 * is an ObjC object registered as the ObjC class for kNSCFTypeArray: CFArray
 * API calls dispatch to -count/-objectAtIndex: (CFArray.c already has that
 * dispatch), and fast enumeration walks the inner C array.
 */
extern int _CFRuntimeRegisterObjCClass(CFTypeID typeID, uintptr_t cls);

@interface RavynCFArray : NSObject <NSFastEnumeration> {
    id _storage;
    BOOL _isCFArray;
}
- (id)initWithCFArray:(CFArrayRef)array;
- (id)initWithNSArray:(NSArray *)array;
@end

@implementation RavynCFArray

- (id)initWithCFArray:(CFArrayRef)array {
    self = [super init];
    if (self != nil) {
        _storage = (id)CFRetain(array);
        _isCFArray = YES;
    }
    return self;
}

- (id)initWithNSArray:(NSArray *)array {
    self = [super init];
    if (self != nil) {
        _storage = [array retain];
        _isCFArray = NO;
    }
    return self;
}

- (void)dealloc {
    if (_isCFArray) {
        if (_storage != NULL) {
            CFRelease((CFArrayRef)_storage);
        }
    } else {
        [(NSArray *)_storage release];
    }
    _storage = nil;
    [super dealloc];
}

- (NSUInteger)count {
    if (_isCFArray) {
        return (NSUInteger)CFArrayGetCount((CFArrayRef)_storage);
    }
    return [(NSArray *)_storage count];
}

- (id)objectAtIndex:(NSUInteger)index {
    if (_isCFArray) {
        return (id)CFArrayGetValueAtIndex((CFArrayRef)_storage, (CFIndex)index);
    }
    return [(NSArray *)_storage objectAtIndex:index];
}


- (void)getObjects:(id *)objects range:(NSRange)range {
    NSUInteger i;

    if (!_isCFArray) {
        [(NSArray *)_storage getObjects:objects range:range];
        return;
    }
    for (i = 0; i < range.length; i++) {
        objects[i] = (id)CFArrayGetValueAtIndex((CFArrayRef)_storage,
            (CFIndex)(range.location + i));
    }
}

- (unsigned)_cfTypeID {
    return kNSCFTypeArray;
}
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
    objects:(id *)stackbuf count:(NSUInteger)len {
    NSUInteger i, count;

    if (!_isCFArray) {
        return [(NSArray *)_storage countByEnumeratingWithState:state
            objects:stackbuf count:len];
    }
    if (state->state != 0) {
        free((void *)state->extra[0]);
        state->extra[0] = 0;
        return 0;
    }
    count = (NSUInteger)CFArrayGetCount((CFArrayRef)_storage);
    state->itemsPtr = (id *)malloc(count * sizeof(id));
    for (i = 0; i < count; i++) {
        state->itemsPtr[i] = (id)CFArrayGetValueAtIndex((CFArrayRef)_storage,
            (CFIndex)i);
    }
    state->extra[0] = (unsigned long)state->itemsPtr;
    state->mutationsPtr = &state->extra[1];
    state->state = 1;
    return count;
}

@end

static void
ravyn_ensure_array_bridge(void)
{
    static int registered = 0;

    if (!registered) {
        registered = 1;
        /* RavynCFArray is a compiled class; no runtime class creation. */
        _CFRuntimeRegisterObjCClass(kNSCFTypeArray,
            (uintptr_t)[RavynCFArray class]);
    }
}

static CFArrayRef
ravyn_wrap_array(CFArrayRef array)
{
    RavynCFArray *wrapper;

    if (array == NULL) {
        return NULL;
    }
    ravyn_ensure_array_bridge();
    wrapper = [[RavynCFArray alloc] initWithCFArray:array];
    return (CFArrayRef)wrapper;
}

static CFArrayRef
ravyn_wrap_nsarray(NSArray *array)
{
    RavynCFArray *wrapper;

    if (array == nil) {
        return NULL;
    }
    ravyn_ensure_array_bridge();
    wrapper = [[RavynCFArray alloc] initWithNSArray:array];
    return (CFArrayRef)wrapper;
}

/*
 * Table, metric, trait and line/run surface used by Gecko's CoreText /
 * HarfBuzz font backend.
 */
extern CFArrayRef CGFontCopyTableTags(CGFontRef font);
extern bool CGFontGetGlyphBBoxes(CGFontRef font, const CGGlyph *glyphs, size_t count, CGRect *bboxes);
extern void CGContextShowGlyphsAtPositions(CGContextRef context, const CGGlyph *glyphs, const CGPoint *positions, size_t count);

CFDataRef
CTFontCopyTable(CTFontRef font, uint32_t table, uint32_t options)
{
    (void)options;
    if (font == NULL)
        return NULL;
    return CGFontCopyTableForTag([(KTFont *)font graphicsFont], table);
}

CFArrayRef
CTFontCopyAvailableTables(CTFontRef font, uint32_t options)
{
    (void)options;
    if (font == NULL)
        return NULL;
    return CGFontCopyTableTags([(KTFont *)font graphicsFont]);
}

CGFontRef
CTFontCopyGraphicsFont(CTFontRef font, CTFontDescriptorRef *attributes)
{
    if (attributes != NULL)
        *attributes = NULL;
    if (font == NULL)
        return NULL;
    return CGFontRetain([(KTFont *)font graphicsFont]);
}

unsigned int
CTFontGetUnitsPerEm(CTFontRef font)
{
    if (font == NULL)
        return 1000;
    return (unsigned int)[(KTFont *)font unitsPerEm];
}

uint32_t
CTFontGetSymbolicTraits(CTFontRef font)
{
    uint32_t traits = 0;
    if (font == NULL)
        return 0;
    NSString *name = (NSString *)[(KTFont *)font copyName];
    if (name != nil) {
        if ([name rangeOfString:@"Bold" options:NSCaseInsensitiveSearch].location != NSNotFound)
            traits |= (1U << 1);
        if ([name rangeOfString:@"Italic" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"Oblique" options:NSCaseInsensitiveSearch].location != NSNotFound)
            traits |= (1U << 0);
        [name release];
    }
    return traits;
}

CFDictionaryRef
CTFontCopyTraits(CTFontRef font)
{
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(NULL, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int32_t sym = (int32_t)CTFontGetSymbolicTraits(font);
    double weight = (sym & (1 << 1)) ? 0.4 : 0.0;
    double width = 0.0;
    double slant = (sym & (1 << 0)) ? 0.1 : 0.0;
    CFNumberRef nSym = CFNumberCreate(NULL, kCFNumberSInt32Type, &sym);
    CFNumberRef nWeight = CFNumberCreate(NULL, kCFNumberDoubleType, &weight);
    CFNumberRef nWidth = CFNumberCreate(NULL, kCFNumberDoubleType, &width);
    CFNumberRef nSlant = CFNumberCreate(NULL, kCFNumberDoubleType, &slant);
    CFDictionarySetValue(dict, kCTFontSymbolicTrait, nSym);
    CFDictionarySetValue(dict, kCTFontWeightTrait, nWeight);
    CFDictionarySetValue(dict, kCTFontWidthTrait, nWidth);
    CFDictionarySetValue(dict, kCTFontSlantTrait, nSlant);
    CFRelease(nSym);
    CFRelease(nWeight);
    CFRelease(nWidth);
    CFRelease(nSlant);
    return dict;
}

CFStringRef
CTFontCopyName(CTFontRef font, CFStringRef nameKey)
{
    (void)nameKey;
    if (font == NULL)
        return NULL;
    CFStringRef name = [(KTFont *)font copyName];
    if (name == NULL)
        return CFSTR("Inter-Regular");
    return name;
}

CFStringRef
CTFontCopyLocalizedName(CTFontRef font, CFStringRef nameKey, CFStringRef *actualLanguage)
{
    if (actualLanguage != NULL)
        *actualLanguage = CFSTR("en");
    return CTFontCopyName(font, nameKey);
}

CFCharacterSetRef
CTFontCopyCharacterSet(CTFontRef font)
{
    (void)font;
    CFCharacterSetRef cs = CFCharacterSetGetPredefined(kCFCharacterSetAlphaNumeric);
    return cs ? (CFCharacterSetRef)CFRetain(cs) : NULL;
}

CFArrayRef
CTFontCopyFeatures(CTFontRef font)
{
    (void)font;
    return NULL;
}

CFArrayRef
CTFontCopyVariationAxes(CTFontRef font)
{
    (void)font;
    return NULL;
}

CFDictionaryRef
CTFontCopyVariation(CTFontRef font)
{
    (void)font;
    return NULL;
}

CTFontRef
CTFontCreateForString(CTFontRef currentFont, CFStringRef string, CFRange range)
{
    (void)string;
    (void)range;
    if (currentFont != NULL)
        return (CTFontRef)[(id)currentFont retain];
    return CTFontCreateWithName(CFSTR("Inter-Regular"), 12.0, NULL);
}

CGGlyph
CTFontGetGlyphWithName(CTFontRef font, CFStringRef glyphName)
{
    if (font == NULL || glyphName == NULL)
        return 0;
    return CGFontGetGlyphWithGlyphName([(KTFont *)font graphicsFont], glyphName);
}

CGRect
CTFontGetBoundingRectsForGlyphs(CTFontRef font, int orientation,
    const CGGlyph glyphs[], CGRect boundingRects[], CFIndex count)
{
    (void)orientation;
    if (font == NULL || glyphs == NULL || count <= 0)
        return CGRectZero;
    CGFontRef cgFont = [(KTFont *)font graphicsFont];
    CGFloat upem = [(KTFont *)font unitsPerEm];
    CGFloat size = [(KTFont *)font pointSize];
    CGFloat scale = (upem > 0 ? (size / upem) : 0.001);
    CGRect unionRect = CGRectZero;
    for (CFIndex i = 0; i < count; i++) {
        CGRect gbox = CGRectZero;
        if (cgFont != NULL)
            CGFontGetGlyphBBoxes(cgFont, &glyphs[i], 1, &gbox);
        CGRect r = CGRectMake(gbox.origin.x * scale, gbox.origin.y * scale,
            gbox.size.width * scale, gbox.size.height * scale);
        if (boundingRects != NULL)
            boundingRects[i] = r;
        unionRect = (i == 0) ? r : CGRectUnion(unionRect, r);
    }
    return unionRect;
}

void
CTFontGetVerticalTranslationsForGlyphs(CTFontRef font,
    const CGGlyph glyphs[], CGSize translations[], CFIndex count)
{
    (void)font;
    (void)glyphs;
    if (translations != NULL && count > 0)
        memset(translations, 0, (size_t)count * sizeof(CGSize));
}

void
CTFontDrawGlyphs(CTFontRef font, const CGGlyph glyphs[],
    const CGPoint positions[], size_t count, CGContextRef context)
{
    if (font == NULL || glyphs == NULL || positions == NULL || context == NULL || count == 0)
        return;
    CGContextSetFont(context, [(KTFont *)font graphicsFont]);
    CGContextSetFontSize(context, [(KTFont *)font pointSize]);
    CGContextShowGlyphsAtPositions(context, glyphs, positions, count);
}

CTFontDescriptorRef
CTFontManagerCreateFontDescriptorFromData(CFDataRef data)
{
    (void)data;
    return CTFontDescriptorCreateWithNameAndSize(CFSTR("Inter-Regular"), 12.0);
}

CFArrayRef
CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fileURL)
{
    (void)fileURL;
    return NULL;
}

void
CTFontManagerSetAutoActivationSetting(CFStringRef bundleIdentifier, uint32_t setting)
{
    (void)bundleIdentifier;
    (void)setting;
}

/* CTLine / CTRun / CTFrame / CTFramesetter minimal surface */
typedef const struct __CTLine *CTLineRef;
typedef const struct __CTRun *CTRunRef;
typedef const struct __CTFrame *CTFrameRef;
typedef const struct __CTFramesetter *CTFramesetterRef;

CTLineRef
CTLineCreateWithAttributedString(CFTypeRef attrString)
{
    (void)attrString;
    return NULL;
}

void
CTLineDraw(CTLineRef line, CGContextRef context)
{
    (void)line;
    (void)context;
}

CFArrayRef
CTLineGetGlyphRuns(CTLineRef line)
{
    (void)line;
    return ravyn_wrap_nsarray([NSArray array]);
}

CGRect
CTLineGetImageBounds(CTLineRef line, CGContextRef context)
{
    (void)line;
    (void)context;
    return CGRectZero;
}

CGFloat
CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex, CGFloat *secondaryOffset)
{
    (void)line;
    (void)charIndex;
    if (secondaryOffset != NULL)
        *secondaryOffset = 0.0;
    return 0.0;
}

CFIndex
CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position)
{
    (void)line;
    (void)position;
    return 0;
}

CFRange
CTLineGetStringRange(CTLineRef line)
{
    (void)line;
    return CFRangeMake(0, 0);
}

double
CTLineGetTypographicBounds(CTLineRef line, CGFloat *ascent, CGFloat *descent, CGFloat *leading)
{
    (void)line;
    if (ascent) *ascent = 10.0;
    if (descent) *descent = 2.0;
    if (leading) *leading = 0.0;
    return 0.0;
}

CFDictionaryRef
CTRunGetAttributes(CTRunRef run)
{
    (void)run;
    return NULL;
}

CFIndex
CTRunGetGlyphCount(CTRunRef run)
{
    (void)run;
    return 0;
}

void
CTRunGetGlyphs(CTRunRef run, CFRange range, CGGlyph buffer[])
{
    (void)run;
    if (buffer != NULL && range.length > 0)
        memset(buffer, 0, (size_t)range.length * sizeof(CGGlyph));
}

const CGGlyph *
CTRunGetGlyphsPtr(CTRunRef run)
{
    (void)run;
    return NULL;
}

void
CTRunGetPositions(CTRunRef run, CFRange range, CGPoint buffer[])
{
    (void)run;
    if (buffer != NULL && range.length > 0)
        memset(buffer, 0, (size_t)range.length * sizeof(CGPoint));
}

const CGPoint *
CTRunGetPositionsPtr(CTRunRef run)
{
    (void)run;
    return NULL;
}

void
CTRunGetStringIndices(CTRunRef run, CFRange range, CFIndex buffer[])
{
    (void)run;
    if (buffer != NULL && range.length > 0)
        memset(buffer, 0, (size_t)range.length * sizeof(CFIndex));
}

const CFIndex *
CTRunGetStringIndicesPtr(CTRunRef run)
{
    (void)run;
    return NULL;
}

CFRange
CTRunGetStringRange(CTRunRef run)
{
    (void)run;
    return CFRangeMake(0, 0);
}

double
CTRunGetTypographicBounds(CTRunRef run, CFRange range, CGFloat *ascent, CGFloat *descent, CGFloat *leading)
{
    (void)run;
    (void)range;
    if (ascent) *ascent = 10.0;
    if (descent) *descent = 2.0;
    if (leading) *leading = 0.0;
    return 0.0;
}

CTFramesetterRef
CTFramesetterCreateWithAttributedString(CFTypeRef string)
{
    (void)string;
    return NULL;
}

CTFrameRef
CTFramesetterCreateFrame(CTFramesetterRef framesetter, CFRange stringRange, CGPathRef path, CFDictionaryRef frameAttributes)
{
    (void)framesetter;
    (void)stringRange;
    (void)path;
    (void)frameAttributes;
    return NULL;
}

CGSize
CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterRef framesetter, CFRange stringRange, CFDictionaryRef frameAttributes, CGSize constraints, CFRange *fitRange)
{
    (void)framesetter;
    (void)frameAttributes;
    (void)constraints;
    if (fitRange != NULL)
        *fitRange = stringRange;
    return CGSizeZero;
}

void
CTFrameDraw(CTFrameRef frame, CGContextRef context)
{
    (void)frame;
    (void)context;
}

CFArrayRef
CTFrameGetLines(CTFrameRef frame)
{
    (void)frame;
    return ravyn_wrap_nsarray([NSArray array]);
}

CGPathRef
CTFrameGetPath(CTFrameRef frame)
{
    (void)frame;
    return NULL;
}
