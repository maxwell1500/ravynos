/*
 * Symbols a stock application expects from CoreFoundation itself.
 *
 * dyld reported this one by name, with the owning library spelled out:
 *
 *   Symbol not found: _NSDefaultRunLoopMode
 *   Expected in: /System/Library/Frameworks/CoreFoundation.framework/...
 *
 * On macOS the NS* run loop mode strings are reachable through
 * CoreFoundation, so XUL's binding names CF, not Foundation.  The value is
 * the documented string for the constant; making it a real CFString keeps
 * run-loop calls and dictionary lookups working.
 */
#include "CFInternal.h"

CFStringRef NSDefaultRunLoopMode = NULL;
CFStringRef NSRunLoopCommonModes = NULL;

/*
 * Empty-collection singletons.  Clang's @[] and @{} literals reference these
 * data symbols, and on macOS CoreFoundation exports them.  They cannot be
 * created here: the classes live in Foundation, so Foundation fills them in
 * its +load (Frameworks/Foundation/NSEmptyCollections.m).  A NULL here until
 * then is honest -- the only caller is the compiler's literal machinery,
 * which runs after Foundation is loaded.
 */
void *__NSArray0__ = NULL;
void *__NSDictionary0__ = NULL;

CFStringRef NSSystemTimeZoneDidChangeNotification = NULL;

/*
 * CFURL resource property keys.  These are declared `const CFStringRef` in
 * the headers, so they must be compile-time constants; the build uses
 * -fconstant-cfstrings, and __CFInitialize fills the constant-string class
 * reference these literals point at.
 */
const CFStringRef kCFURLQuarantinePropertiesKey = CFSTR("NSURLQuarantinePropertiesKey");

/* NSLocale keys, exported through CoreFoundation on macOS. */
CFStringRef NSLocaleIdentifier = NULL;
CFStringRef NSLocaleLanguageCode = NULL;
CFStringRef NSLocaleCountryCode = NULL;
CFStringRef NSLocaleScriptCode = NULL;
CFStringRef NSLocaleVariantCode = NULL;
CFStringRef NSLocaleExemplarCharacterSet = NULL;
CFStringRef NSLocaleCalendar = NULL;
CFStringRef NSLocaleCollationIdentifier = NULL;
CFStringRef NSLocaleUsesMetricSystem = NULL;
CFStringRef NSLocaleMeasurementSystem = NULL;
CFStringRef NSLocaleDecimalSeparator = NULL;
CFStringRef NSLocaleGroupingSeparator = NULL;
CFStringRef NSLocaleCurrencySymbol = NULL;
CFStringRef NSLocaleCurrencyCode = NULL;
CFStringRef NSLocaleCollatorIdentifier = NULL;
CFStringRef NSLocaleQuotationBeginDelimiterKey = NULL;
CFStringRef NSLocaleQuotationEndDelimiterKey = NULL;
CFStringRef NSLocaleAlternateQuotationBeginDelimiterKey = NULL;
CFStringRef NSLocaleAlternateQuotationEndDelimiterKey = NULL;

/* NSException names, exported through CoreFoundation on macOS. */
CFStringRef NSGenericException = NULL;
CFStringRef NSRangeException = NULL;
CFStringRef NSInvalidArgumentException = NULL;
CFStringRef NSInternalInconsistencyException = NULL;
CFStringRef NSMallocException = NULL;
CFStringRef NSObjectInaccessibleException = NULL;
CFStringRef NSObjectNotAvailableException = NULL;
CFStringRef NSDestinationInvalidException = NULL;
CFStringRef NSPortTimeoutException = NULL;
CFStringRef NSInvalidSendPortException = NULL;
CFStringRef NSInvalidReceivePortException = NULL;
CFStringRef NSPortSendException = NULL;
CFStringRef NSPortReceiveException = NULL;
CFStringRef NSOldStyleException = NULL;

__attribute__((constructor)) static void
__CFCompatRunLoopModesInit(void)
{
	if (NSDefaultRunLoopMode == NULL) {
		NSDefaultRunLoopMode = __CFStringMakeConstantString("NSDefaultRunLoopMode");
	}
	if (NSRunLoopCommonModes == NULL) {
		NSRunLoopCommonModes = __CFStringMakeConstantString("NSRunLoopCommonModes");
	}
	if (NSSystemTimeZoneDidChangeNotification == NULL) {
		NSSystemTimeZoneDidChangeNotification = __CFStringMakeConstantString("NSSystemTimeZoneDidChangeNotification");
	}
	if (NSLocaleIdentifier == NULL) {
		NSLocaleIdentifier = __CFStringMakeConstantString("NSLocaleIdentifier");
	}
	if (NSLocaleLanguageCode == NULL) {
		NSLocaleLanguageCode = __CFStringMakeConstantString("NSLocaleLanguageCode");
	}
	if (NSLocaleCountryCode == NULL) {
		NSLocaleCountryCode = __CFStringMakeConstantString("NSLocaleCountryCode");
	}
	if (NSLocaleScriptCode == NULL) {
		NSLocaleScriptCode = __CFStringMakeConstantString("NSLocaleScriptCode");
	}
	if (NSLocaleVariantCode == NULL) {
		NSLocaleVariantCode = __CFStringMakeConstantString("NSLocaleVariantCode");
	}
	if (NSLocaleExemplarCharacterSet == NULL) {
		NSLocaleExemplarCharacterSet = __CFStringMakeConstantString("NSLocaleExemplarCharacterSet");
	}
	if (NSLocaleCalendar == NULL) {
		NSLocaleCalendar = __CFStringMakeConstantString("NSLocaleCalendar");
	}
	if (NSLocaleCollationIdentifier == NULL) {
		NSLocaleCollationIdentifier = __CFStringMakeConstantString("NSLocaleCollationIdentifier");
	}
	if (NSLocaleUsesMetricSystem == NULL) {
		NSLocaleUsesMetricSystem = __CFStringMakeConstantString("NSLocaleUsesMetricSystem");
	}
	if (NSLocaleMeasurementSystem == NULL) {
		NSLocaleMeasurementSystem = __CFStringMakeConstantString("NSLocaleMeasurementSystem");
	}
	if (NSLocaleDecimalSeparator == NULL) {
		NSLocaleDecimalSeparator = __CFStringMakeConstantString("NSLocaleDecimalSeparator");
	}
	if (NSLocaleGroupingSeparator == NULL) {
		NSLocaleGroupingSeparator = __CFStringMakeConstantString("NSLocaleGroupingSeparator");
	}
	if (NSLocaleCurrencySymbol == NULL) {
		NSLocaleCurrencySymbol = __CFStringMakeConstantString("NSLocaleCurrencySymbol");
	}
	if (NSLocaleCurrencyCode == NULL) {
		NSLocaleCurrencyCode = __CFStringMakeConstantString("NSLocaleCurrencyCode");
	}
	if (NSLocaleCollatorIdentifier == NULL) {
		NSLocaleCollatorIdentifier = __CFStringMakeConstantString("NSLocaleCollatorIdentifier");
	}
	if (NSLocaleQuotationBeginDelimiterKey == NULL) {
		NSLocaleQuotationBeginDelimiterKey = __CFStringMakeConstantString("NSLocaleQuotationBeginDelimiterKey");
	}
	if (NSLocaleQuotationEndDelimiterKey == NULL) {
		NSLocaleQuotationEndDelimiterKey = __CFStringMakeConstantString("NSLocaleQuotationEndDelimiterKey");
	}
	if (NSLocaleAlternateQuotationBeginDelimiterKey == NULL) {
		NSLocaleAlternateQuotationBeginDelimiterKey = __CFStringMakeConstantString("NSLocaleAlternateQuotationBeginDelimiterKey");
	}
	if (NSLocaleAlternateQuotationEndDelimiterKey == NULL) {
		NSLocaleAlternateQuotationEndDelimiterKey = __CFStringMakeConstantString("NSLocaleAlternateQuotationEndDelimiterKey");
	}
	if (NSGenericException == NULL) {
		NSGenericException = __CFStringMakeConstantString("NSGenericException");
	}
	if (NSRangeException == NULL) {
		NSRangeException = __CFStringMakeConstantString("NSRangeException");
	}
	if (NSInvalidArgumentException == NULL) {
		NSInvalidArgumentException = __CFStringMakeConstantString("NSInvalidArgumentException");
	}
	if (NSInternalInconsistencyException == NULL) {
		NSInternalInconsistencyException = __CFStringMakeConstantString("NSInternalInconsistencyException");
	}
	if (NSMallocException == NULL) {
		NSMallocException = __CFStringMakeConstantString("NSMallocException");
	}
	if (NSObjectInaccessibleException == NULL) {
		NSObjectInaccessibleException = __CFStringMakeConstantString("NSObjectInaccessibleException");
	}
	if (NSObjectNotAvailableException == NULL) {
		NSObjectNotAvailableException = __CFStringMakeConstantString("NSObjectNotAvailableException");
	}
	if (NSDestinationInvalidException == NULL) {
		NSDestinationInvalidException = __CFStringMakeConstantString("NSDestinationInvalidException");
	}
	if (NSPortTimeoutException == NULL) {
		NSPortTimeoutException = __CFStringMakeConstantString("NSPortTimeoutException");
	}
	if (NSInvalidSendPortException == NULL) {
		NSInvalidSendPortException = __CFStringMakeConstantString("NSInvalidSendPortException");
	}
	if (NSInvalidReceivePortException == NULL) {
		NSInvalidReceivePortException = __CFStringMakeConstantString("NSInvalidReceivePortException");
	}
	if (NSPortSendException == NULL) {
		NSPortSendException = __CFStringMakeConstantString("NSPortSendException");
	}
	if (NSPortReceiveException == NULL) {
		NSPortReceiveException = __CFStringMakeConstantString("NSPortReceiveException");
	}
	if (NSOldStyleException == NULL) {
		NSOldStyleException = __CFStringMakeConstantString("NSOldStyleException");
	}
}
