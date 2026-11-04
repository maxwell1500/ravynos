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

#include <CoreFoundation/CFURL.h>
#include <CoreFoundation/CFRunLoop.h>
#include <objc/runtime.h>
#include <objc/message.h>

Boolean
CFURLCopyResourcePropertyForKey(CFURLRef url, CFStringRef key,
    void *propertyValueTypeRefPtr, CFErrorRef *error)
{
	(void)url;
	(void)key;
	if (propertyValueTypeRefPtr != NULL)
		*(CFTypeRef *)propertyValueTypeRefPtr = NULL;
	if (error != NULL)
		*error = NULL;
	return true;
}

Boolean
CFURLSetResourcePropertyForKey(CFURLRef url, CFStringRef key,
    CFTypeRef propertyValue, CFErrorRef *error)
{
	(void)url;
	(void)key;
	(void)propertyValue;
	if (error != NULL)
		*error = NULL;
	return true;
}

CFTypeRef
CFAttributedStringCreate(CFAllocatorRef alloc, CFStringRef str, CFDictionaryRef attributes)
{
	(void)alloc;
	Class cls = objc_lookUpClass("NSAttributedString");
	if (cls == Nil)
		return NULL;
	id (*msg0)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
	id (*msg2)(id, SEL, CFStringRef, CFDictionaryRef) =
	    (id (*)(id, SEL, CFStringRef, CFDictionaryRef))objc_msgSend;
	id obj = msg0((id)cls, sel_registerName("alloc"));
	return (CFTypeRef)msg2(obj, sel_registerName("initWithString:attributes:"),
	    str ? str : CFSTR(""), attributes);
}

CFTypeRef
CFAttributedStringCreateMutable(CFAllocatorRef alloc, CFIndex maxLength)
{
	(void)alloc;
	(void)maxLength;
	Class cls = objc_lookUpClass("NSMutableAttributedString");
	if (cls == Nil)
		return NULL;
	id (*msg0)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
	id obj = msg0((id)cls, sel_registerName("alloc"));
	return (CFTypeRef)msg0(obj, sel_registerName("init"));
}

typedef struct __CFFileDescriptor *CFFileDescriptorRef;
typedef int CFFileDescriptorNativeDescriptor;
typedef struct {
	CFIndex version;
	void *info;
	void *(*retain)(void *info);
	void (*release)(void *info);
	CFStringRef (*copyDescription)(void *info);
} CFFileDescriptorContext;
typedef void (*CFFileDescriptorCallBack)(CFFileDescriptorRef f, CFOptionFlags callBackTypes, void *info);

CFFileDescriptorRef
CFFileDescriptorCreate(CFAllocatorRef allocator, CFFileDescriptorNativeDescriptor fd,
    Boolean closeOnInvalidate, CFFileDescriptorCallBack callout,
    const CFFileDescriptorContext *context)
{
	(void)allocator;
	(void)fd;
	(void)closeOnInvalidate;
	(void)callout;
	(void)context;
	return NULL;
}

CFRunLoopSourceRef
CFFileDescriptorCreateRunLoopSource(CFAllocatorRef allocator, CFFileDescriptorRef f, CFIndex order)
{
	(void)allocator;
	(void)f;
	(void)order;
	return NULL;
}

void
CFFileDescriptorEnableCallBacks(CFFileDescriptorRef f, CFOptionFlags callBackTypes)
{
	(void)f;
	(void)callBackTypes;
}

void
CFFileDescriptorDisableCallBacks(CFFileDescriptorRef f, CFOptionFlags callBackTypes)
{
	(void)f;
	(void)callBackTypes;
}

void
CFFileDescriptorGetContext(CFFileDescriptorRef f, CFFileDescriptorContext *context)
{
	(void)f;
	if (context != NULL)
		memset(context, 0, sizeof(*context));
}

CFFileDescriptorNativeDescriptor
CFFileDescriptorGetNativeDescriptor(CFFileDescriptorRef f)
{
	(void)f;
	return -1;
}

void
CFFileDescriptorInvalidate(CFFileDescriptorRef f)
{
	(void)f;
}

Boolean
CFFileDescriptorIsValid(CFFileDescriptorRef f)
{
	(void)f;
	return false;
}

typedef struct __CFStringTokenizer *CFStringTokenizerRef;

CFStringTokenizerRef
CFStringTokenizerCreate(CFAllocatorRef alloc, CFStringRef string, CFRange range,
    CFOptionFlags options, CFLocaleRef locale)
{
	(void)alloc;
	(void)string;
	(void)range;
	(void)options;
	(void)locale;
	return NULL;
}

CFOptionFlags
CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer)
{
	(void)tokenizer;
	return 0;
}

CFRange
CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer)
{
	(void)tokenizer;
	return CFRangeMake(kCFNotFound, 0);
}
