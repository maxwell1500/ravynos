/* CoreServices compatibility entry points used by prebuilt applications.
 *
 * The Carbon memory-manager pair is real (it is just a double indirection);
 * the catalog and keyboard-layout calls have no backing store here and answer
 * "not found" / "not implemented" while still existing as symbols, which is
 * what dyld's two-level bind needs.  CoreServices is where a stock binary
 * records these, even though they originated in CarbonCore.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>

typedef char **Handle;
typedef int16_t OSErr;

OSErr PtrToHand(const void *srcPtr, Handle *dstHndl, Size size)
{
	char **handle;
	void *data;

	if (dstHndl == NULL || (srcPtr == NULL && size != 0))
		return -50;	/* paramErr */
	data = malloc(size ? size : 1);
	handle = malloc(sizeof(*handle));
	if (data == NULL || handle == NULL) {
		free(data);
		free(handle);
		return -108;	/* memFullErr */
	}
	if (size != 0)
		memcpy(data, srcPtr, size);
	*handle = data;
	*dstHndl = handle;
	return 0;
}

void DisposeHandle(Handle h)
{
	if (h == NULL)
		return;
	free(*h);
	free(h);
}

Size GetAliasSizeFromPtr(const void *alias)
{
	(void)alias;
	return 0;
}

OSErr FSGetCatalogInfo(const void *ref, uint32_t bitmap, void *catalogInfo,
    void *volume, void *parentRef, void *spec)
{
	(void)ref; (void)bitmap; (void)catalogInfo; (void)volume;
	(void)parentRef; (void)spec;
	return -43;		/* fnfErr: no catalog */
}

OSStatus UCKeyTranslate(const void *keyLayout, uint16_t keyCode,
    uint16_t keyAction, uint32_t modifierKeyState, uint32_t keyboardType,
    OptionBits options, uint32_t *deadKeyState, UniCharCount maxStringLength,
    UniCharCount *actualStringLength, UniChar *unicodeString)
{
	(void)keyLayout; (void)keyCode; (void)keyAction; (void)modifierKeyState;
	(void)keyboardType; (void)options; (void)deadKeyState;
	(void)maxStringLength; (void)unicodeString;
	if (actualStringLength != NULL)
		*actualStringLength = 0;
	return -50;		/* paramErr: no UCKeyboardLayout in this system */
}

CFStringRef UTTypeCopyDescription(CFStringRef identifier)
{
	(void)identifier;
	return NULL;		/* no localized type database */
}

void *MDItemCreate(CFAllocatorRef allocator, CFStringRef path)
{
	(void)allocator; (void)path;
	return NULL;		/* Spotlight metadata is not indexed */
}
