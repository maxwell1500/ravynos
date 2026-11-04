/*
 * Core Graphics colour constants.
 *
 * XUL binds kCGColor* at load ("Symbol not found: _kCGColorBlack",
 * "Expected in: CoreGraphics").  They are created once through this
 * framework's own colour constructors, so they behave exactly like any other
 * CGColor created here.
 */
#include "CGColor.h"
#include <CoreFoundation/CFString.h>

CGColorRef kCGColorBlack = NULL;
CGColorRef kCGColorWhite = NULL;
CGColorRef kCGColorClear = NULL;

__attribute__((constructor)) static void
CGColorConstantsInit(void)
{
	if (kCGColorBlack == NULL) {
		kCGColorBlack = CGColorCreateGenericGray(0.0f, 1.0f);
	}
	if (kCGColorWhite == NULL) {
		kCGColorWhite = CGColorCreateGenericGray(1.0f, 1.0f);
	}
	if (kCGColorClear == NULL) {
		kCGColorClear = CGColorCreateGenericRGB(0.0f, 0.0f, 0.0f, 0.0f);
	}
}

/*
 * Named colour spaces.  This framework creates them from its device colour
 * spaces; the names are the documented values so a caller comparing by name
 * (CGColorSpaceCopyName) sees the expected string even though the colour
 * model is the device one.
 */
CGColorSpaceRef kCGColorSpaceSRGB = NULL;
CGColorSpaceRef kCGColorSpaceDisplayP3 = NULL;
CGColorSpaceRef kCGColorSpaceGenericRGB = NULL;
CGColorSpaceRef kCGColorSpaceGenericGray = NULL;
CGColorSpaceRef kCGColorSpaceGenericCMYK = NULL;
CGColorSpaceRef kCGColorSpaceAdobeRGB1998 = NULL;
CGColorSpaceRef kCGColorSpaceGenericRGBLinear = NULL;
CGColorSpaceRef kCGColorSpaceExtendedSRGB = NULL;

__attribute__((constructor)) static void
CGColorSpaceConstantsInit(void)
{
	if (kCGColorSpaceSRGB == NULL) kCGColorSpaceSRGB = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceDisplayP3 == NULL) kCGColorSpaceDisplayP3 = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceGenericRGB == NULL) kCGColorSpaceGenericRGB = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceGenericGray == NULL) kCGColorSpaceGenericGray = CGColorSpaceCreateDeviceGray();
	if (kCGColorSpaceGenericCMYK == NULL) kCGColorSpaceGenericCMYK = CGColorSpaceCreateDeviceCMYK();
	if (kCGColorSpaceAdobeRGB1998 == NULL) kCGColorSpaceAdobeRGB1998 = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceGenericRGBLinear == NULL) kCGColorSpaceGenericRGBLinear = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceExtendedSRGB == NULL) kCGColorSpaceExtendedSRGB = CGColorSpaceCreateDeviceRGB();
}

/* Remaining named spaces bound at load. */
CGColorSpaceRef kCGColorSpaceITUR_2020 = NULL;
CGColorSpaceRef kCGColorSpaceITUR_709 = NULL;
CGColorSpaceRef kCGColorSpaceITUR_2020_sRGBGamma = NULL;
CGColorSpaceRef kCGColorSpaceITUR_2100_PQ = NULL;
CGColorSpaceRef kCGColorSpaceITUR_2100_HLG = NULL;
CGColorSpaceRef kCGColorSpaceDCIP3 = NULL;
CGColorSpaceRef kCGColorSpaceDisplayP3_HLG = NULL;
CGColorSpaceRef kCGColorSpaceDisplayP3_PQ = NULL;
CGColorSpaceRef kCGColorSpaceExtendedLinearDisplayP3 = NULL;
CGColorSpaceRef kCGColorSpaceExtendedLinearSRGB = NULL;
CGColorSpaceRef kCGColorSpaceLinearDisplayP3 = NULL;
CGColorSpaceRef kCGColorSpaceLinearSRGB = NULL;

__attribute__((constructor)) static void
CGColorSpaceConstantsInit2(void)
{
	if (kCGColorSpaceITUR_2020 == NULL) kCGColorSpaceITUR_2020 = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceITUR_709 == NULL) kCGColorSpaceITUR_709 = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceITUR_2020_sRGBGamma == NULL) kCGColorSpaceITUR_2020_sRGBGamma = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceITUR_2100_PQ == NULL) kCGColorSpaceITUR_2100_PQ = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceITUR_2100_HLG == NULL) kCGColorSpaceITUR_2100_HLG = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceDCIP3 == NULL) kCGColorSpaceDCIP3 = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceDisplayP3_HLG == NULL) kCGColorSpaceDisplayP3_HLG = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceDisplayP3_PQ == NULL) kCGColorSpaceDisplayP3_PQ = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceExtendedLinearDisplayP3 == NULL) kCGColorSpaceExtendedLinearDisplayP3 = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceExtendedLinearSRGB == NULL) kCGColorSpaceExtendedLinearSRGB = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceLinearDisplayP3 == NULL) kCGColorSpaceLinearDisplayP3 = CGColorSpaceCreateDeviceRGB();
	if (kCGColorSpaceLinearSRGB == NULL) kCGColorSpaceLinearSRGB = CGColorSpaceCreateDeviceRGB();
}

/* Font variation axis keys, bound at load by XUL. */
CFStringRef kCGFontVariationAxisName = NULL;
CFStringRef kCGFontVariationAxisMinValue = NULL;
CFStringRef kCGFontVariationAxisMaxValue = NULL;
CFStringRef kCGFontVariationAxisDefaultValue = NULL;

__attribute__((constructor)) static void
CGFontVariationKeysInit(void)
{
	struct { CFStringRef *slot; const char *value; } keys[] = {
		{ &kCGFontVariationAxisName, "Name" },
		{ &kCGFontVariationAxisMinValue, "MinValue" },
		{ &kCGFontVariationAxisMaxValue, "MaxValue" },
		{ &kCGFontVariationAxisDefaultValue, "DefaultValue" },
	};
	for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
		if (*keys[i].slot == NULL) {
			*keys[i].slot = CFStringCreateWithCString(kCFAllocatorDefault,
			    keys[i].value, kCFStringEncodingUTF8);
		}
	}
}

/* PDF context keys, bound at load by XUL. */
CFStringRef kCGPDFContextCreator = NULL;
CFStringRef kCGPDFContextAuthor = NULL;
CFStringRef kCGPDFContextSubject = NULL;
CFStringRef kCGPDFContextKeywords = NULL;
CFStringRef kCGPDFContextMediaBox = NULL;
CFStringRef kCGPDFContextCropBox = NULL;
CFStringRef kCGPDFContextBleedBox = NULL;
CFStringRef kCGPDFContextTrimBox = NULL;
CFStringRef kCGPDFContextArtBox = NULL;
CFStringRef kCGPDFContextEncryptionKey = NULL;
CFStringRef kCGPDFContextOwnerPassword = NULL;
CFStringRef kCGPDFContextUserPassword = NULL;
CFStringRef kCGPDFContextAllowsPrinting = NULL;
CFStringRef kCGPDFContextAllowsCopying = NULL;
CFStringRef kCGPDFContextAllowsDocumentChanges = NULL;
CFStringRef kCGPDFContextAllowsCommenting = NULL;
CFStringRef kCGPDFContextAllowsFormFieldEntry = NULL;
CFStringRef kCGPDFContextOutputIntents = NULL;
CFStringRef kCGPDFContextDestination = NULL;
CFStringRef kCGPDFContextURL = NULL;

__attribute__((constructor)) static void
CGPDFContextKeysInit(void)
{
	struct { CFStringRef *slot; const char *value; } keys[] = {
		{ &kCGPDFContextCreator, "Creator" },
		{ &kCGPDFContextAuthor, "Author" },
		{ &kCGPDFContextSubject, "Subject" },
		{ &kCGPDFContextKeywords, "Keywords" },
		{ &kCGPDFContextMediaBox, "MediaBox" },
		{ &kCGPDFContextCropBox, "CropBox" },
		{ &kCGPDFContextBleedBox, "BleedBox" },
		{ &kCGPDFContextTrimBox, "TrimBox" },
		{ &kCGPDFContextArtBox, "ArtBox" },
		{ &kCGPDFContextEncryptionKey, "EncryptionKey" },
		{ &kCGPDFContextOwnerPassword, "OwnerPassword" },
		{ &kCGPDFContextUserPassword, "UserPassword" },
		{ &kCGPDFContextAllowsPrinting, "AllowsPrinting" },
		{ &kCGPDFContextAllowsCopying, "AllowsCopying" },
		{ &kCGPDFContextAllowsDocumentChanges, "AllowsDocumentChanges" },
		{ &kCGPDFContextAllowsCommenting, "AllowsCommenting" },
		{ &kCGPDFContextAllowsFormFieldEntry, "AllowsFormFieldEntry" },
		{ &kCGPDFContextOutputIntents, "OutputIntents" },
		{ &kCGPDFContextDestination, "Destination" },
		{ &kCGPDFContextURL, "URL" },
	};
	for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
		if (*keys[i].slot == NULL) {
			*keys[i].slot = CFStringCreateWithCString(kCFAllocatorDefault,
			    keys[i].value, kCFStringEncodingUTF8);
		}
	}
}

/* Window dictionary keys, bound at load by XUL. */
CFStringRef kCGWindowBounds = NULL;
CFStringRef kCGWindowNumber = NULL;
CFStringRef kCGWindowOwnerName = NULL;
CFStringRef kCGWindowName = NULL;
CFStringRef kCGWindowLayer = NULL;
CFStringRef kCGWindowOwnerPID = NULL;
CFStringRef kCGWindowIsOnscreen = NULL;
CFStringRef kCGWindowMemoryUsage = NULL;
CFStringRef kCGWindowSharingState = NULL;
CFStringRef kCGWindowAlpha = NULL;
CFStringRef kCGWindowStoreType = NULL;
CFStringRef kCGWindowWorkspace = NULL;

__attribute__((constructor)) static void
CGWindowKeysInit(void)
{
	struct { CFStringRef *slot; const char *value; } keys[] = {
		{ &kCGWindowBounds, "Bounds" },
		{ &kCGWindowNumber, "Number" },
		{ &kCGWindowOwnerName, "OwnerName" },
		{ &kCGWindowName, "Name" },
		{ &kCGWindowLayer, "Layer" },
		{ &kCGWindowOwnerPID, "OwnerPID" },
		{ &kCGWindowIsOnscreen, "IsOnscreen" },
		{ &kCGWindowMemoryUsage, "MemoryUsage" },
		{ &kCGWindowSharingState, "SharingState" },
		{ &kCGWindowAlpha, "Alpha" },
		{ &kCGWindowStoreType, "StoreType" },
		{ &kCGWindowWorkspace, "Workspace" },
	};
	for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
		if (*keys[i].slot == NULL) {
			*keys[i].slot = CFStringCreateWithCString(kCFAllocatorDefault,
			    keys[i].value, kCFStringEncodingUTF8);
		}
	}
}

#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2MutablePath.h>

typedef void (*CGBitmapContextReleaseDataCallback)(void *releaseInfo, void *data);

CGContextRef CGBitmapContextCreateWithData(void *data, size_t width, size_t height,
    size_t bitsPerComponent, size_t bytesPerRow, CGColorSpaceRef space,
    CGBitmapInfo bitmapInfo, CGBitmapContextReleaseDataCallback releaseCallback,
    void *releaseInfo) {
	(void)releaseCallback;
	(void)releaseInfo;
	return CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, space, bitmapInfo);
}

CGColorRef CGColorGetConstantColor(CFStringRef colorName) {
	static CGColorRef sBlack = NULL;
	static CGColorRef sWhite = NULL;
	static CGColorRef sClear = NULL;
	if (sBlack == NULL) {
		CGFloat black[4] = {0, 0, 0, 1};
		CGFloat white[4] = {1, 1, 1, 1};
		CGFloat clear[4] = {0, 0, 0, 0};
		CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
		sBlack = CGColorCreate(rgb, black);
		sWhite = CGColorCreate(rgb, white);
		sClear = CGColorCreate(rgb, clear);
		CGColorSpaceRelease(rgb);
	}
	if (colorName != NULL) {
		if (CFEqual(colorName, CFSTR("kCGColorWhite")) || CFEqual(colorName, CFSTR("WHITE")))
			return sWhite;
		if (CFEqual(colorName, CFSTR("kCGColorClear")) || CFEqual(colorName, CFSTR("CLEAR")))
			return sClear;
	}
	return sBlack;
}

CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef name) {
	if (name != NULL && CFStringFind(name, CFSTR("Gray"), 0).location != kCFNotFound)
		return CGColorSpaceCreateDeviceGray();
	return CGColorSpaceCreateDeviceRGB();
}

CFDataRef CGColorSpaceCopyICCProfile(CGColorSpaceRef space) {
	(void)space;
	return NULL;
}

void CGContextBeginTransparencyLayerWithRect(CGContextRef context, CGRect rect, CFDictionaryRef auxInfo) {
	(void)rect;
	CGContextBeginTransparencyLayer(context, auxInfo);
}

void CGContextDrawLinearGradient(CGContextRef context, void *gradient,
    CGPoint startPoint, CGPoint endPoint, uint32_t options) {
	(void)context;
	(void)gradient;
	(void)startPoint;
	(void)endPoint;
	(void)options;
}

void CGContextDrawRadialGradient(CGContextRef context, void *gradient,
    CGPoint startCenter, CGFloat startRadius, CGPoint endCenter, CGFloat endRadius,
    uint32_t options) {
	(void)context;
	(void)gradient;
	(void)startCenter;
	(void)startRadius;
	(void)endCenter;
	(void)endRadius;
	(void)options;
}

void CGContextSetAllowsFontSmoothing(CGContextRef context, bool allows) {
	(void)context;
	(void)allows;
}

void CGContextSetAllowsFontSubpixelPositioning(CGContextRef context, bool allows) {
	(void)context;
	(void)allows;
}

void CGContextSetAllowsFontSubpixelQuantization(CGContextRef context, bool allows) {
	(void)context;
	(void)allows;
}

void CGContextSetShouldSubpixelPositionFonts(CGContextRef context, bool should) {
	(void)context;
	(void)should;
}

void CGContextSetShouldSubpixelQuantizeFonts(CGContextRef context, bool should) {
	(void)context;
	(void)should;
}

void CGContextSetFontSmoothingStyle(CGContextRef context, int style) {
	(void)context;
	(void)style;
}

void CGContextSetBaseCTM(CGContextRef context, CGAffineTransform m) {
	(void)context;
	(void)m;
}

void CGContextShowGlyphsAtPositions(CGContextRef context, const CGGlyph *glyphs,
    const CGPoint *positions, size_t count) {
	if (context == NULL || glyphs == NULL || positions == NULL)
		return;
	for (size_t i = 0; i < count; i++) {
		CGContextShowGlyphsAtPoint(context, positions[i].x, positions[i].y, &glyphs[i], 1);
	}
}

CGPathRef CGPathCreateWithRect(CGRect rect, const CGAffineTransform *transform) {
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathAddRect(path, transform, rect);
	return path;
}

CFStringRef CGDisplayModeCopyPixelEncoding(CGDisplayModeRef mode) {
	(void)mode;
	return CFSTR("--------RRRRRRRRGGGGGGGGBBBBBBBB");
}

void CGPDFContextAddDestinationAtPoint(CGContextRef context, CFStringRef name, CGPoint point) {
	(void)context;
	(void)name;
	(void)point;
}

void CGPDFContextSetDestinationForRect(CGContextRef context, CFStringRef name, CGRect rect) {
	(void)context;
	(void)name;
	(void)rect;
}

void CGPDFContextSetURLForRect(CGContextRef context, CFURLRef url, CGRect rect) {
	(void)context;
	(void)url;
	(void)rect;
}

CFTypeID CGColorGetTypeID(void) { return 0; }
CFTypeID CGColorSpaceGetTypeID(void) { return 0; }
CFTypeID CGContextGetTypeID(void) { return 0; }
CFTypeID CGDataProviderGetTypeID(void) { return 0; }
CFTypeID CGImageGetTypeID(void) { return 0; }
CFTypeID CGPathGetTypeID(void) { return 0; }

CFArrayRef CGWindowListCopyWindowInfo(uint32_t option, uint32_t relativeToWindow) {
	(void)option;
	(void)relativeToWindow;
	return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
}

CFArrayRef CGWindowListCreate(uint32_t option, uint32_t relativeToWindow) {
	(void)option;
	(void)relativeToWindow;
	return CFArrayCreate(NULL, NULL, 0, NULL);
}

CFArrayRef CGWindowListCreateDescriptionFromArray(CFArrayRef windowArray) {
	(void)windowArray;
	return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
}

CGImageRef CGWindowListCreateImage(CGRect screenBounds, uint32_t listOption,
    uint32_t windowID, uint32_t imageOption) {
	(void)screenBounds;
	(void)listOption;
	(void)windowID;
	(void)imageOption;
	return NULL;
}

CGImageRef CGWindowListCreateImageFromArray(CGRect screenBounds,
    CFArrayRef windowArray, uint32_t imageOption) {
	(void)screenBounds;
	(void)windowArray;
	(void)imageOption;
	return NULL;
}

uint32_t _CGSDefaultConnection(void) { return 0; }
void CGSRegionRelease(void *region) { (void)region; }
int CGSSetDenyWindowServerConnections(bool deny) { (void)deny; return 0; }
int CGSSetWindowTransform(uint32_t cid, uint32_t wid, CGAffineTransform t) {
	(void)cid; (void)wid; (void)t; return 0;
}
int CGSShutdownServerConnections(void) { return 0; }
