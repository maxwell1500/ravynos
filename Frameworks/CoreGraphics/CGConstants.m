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
