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
    static Class arrayClass = Nil;

    if (arrayClass == Nil) {
        arrayClass = objc_allocateClassPair([NSObject class], "RavynCFArray", 0);
        class_addMethod(arrayClass, @selector(count),
            class_getMethodImplementation(arrayClass, @selector(count)),
            "Q@:");
        class_addMethod(arrayClass, @selector(objectAtIndex:),
            class_getMethodImplementation(arrayClass, @selector(objectAtIndex:)),
            "@@:Q");
        class_addMethod(arrayClass,
            @selector(countByEnumeratingWithState:objects:count:),
            class_getMethodImplementation(arrayClass,
                @selector(countByEnumeratingWithState:objects:count:)),
            "Q@:^@Q");
        objc_registerClassPair(arrayClass);
        _CFRuntimeRegisterObjCClass(kNSCFTypeArray, (uintptr_t)arrayClass);
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
