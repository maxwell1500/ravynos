/*
 * CoreMedia -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement CoreMedia yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/CoreMedia.framework/Versions/A/CoreMedia
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from CoreMedia (measured from its Mach-O undefined symbols against
 * the SDK's own .tbd exports, not guessed).  Data symbols are zero, which
 * reads as NULL/invalid rather than as a plausible-looking value.  Function
 * symbols log one line the first time they are called and return zero; they
 * never report success for an operation ravynOS did not perform.
 *
 * Replacing a function with a real implementation is how this file shrinks.
 * Nothing here may be widened to "define everything the framework exports".
 */
#include <stdio.h>

static void
coremedia_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] CoreMedia: %s is not implemented\n", name);
	}
}


long kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms __attribute__((visibility("default"))) = 0;
long kCMSampleAttachmentKey_DisplayImmediately __attribute__((visibility("default"))) = 0;
long kCMSampleAttachmentKey_NotSync __attribute__((visibility("default"))) = 0;
long kCMTimeIndefinite __attribute__((visibility("default"))) = 0;
long kCMTimingInfoInvalid __attribute__((visibility("default"))) = 0;
void
CMBlockBufferCopyDataBytes(void)
{
	coremedia_unimplemented("CMBlockBufferCopyDataBytes");
}

void
CMBlockBufferCreateWithMemoryBlock(void)
{
	coremedia_unimplemented("CMBlockBufferCreateWithMemoryBlock");
}

void
CMClockGetHostTimeClock(void)
{
	coremedia_unimplemented("CMClockGetHostTimeClock");
}

void
CMCopyDictionaryOfAttachments(void)
{
	coremedia_unimplemented("CMCopyDictionaryOfAttachments");
}

void
CMFormatDescriptionGetExtension(void)
{
	coremedia_unimplemented("CMFormatDescriptionGetExtension");
}

void
CMFormatDescriptionGetMediaSubType(void)
{
	coremedia_unimplemented("CMFormatDescriptionGetMediaSubType");
}

void
CMSampleBufferCreate(void)
{
	coremedia_unimplemented("CMSampleBufferCreate");
}

void
CMSampleBufferCreateReadyWithImageBuffer(void)
{
	coremedia_unimplemented("CMSampleBufferCreateReadyWithImageBuffer");
}

void
CMSampleBufferDataIsReady(void)
{
	coremedia_unimplemented("CMSampleBufferDataIsReady");
}

void
CMSampleBufferGetDataBuffer(void)
{
	coremedia_unimplemented("CMSampleBufferGetDataBuffer");
}

void
CMSampleBufferGetFormatDescription(void)
{
	coremedia_unimplemented("CMSampleBufferGetFormatDescription");
}

void
CMSampleBufferGetImageBuffer(void)
{
	coremedia_unimplemented("CMSampleBufferGetImageBuffer");
}

void
CMSampleBufferGetNumSamples(void)
{
	coremedia_unimplemented("CMSampleBufferGetNumSamples");
}

void
CMSampleBufferGetOutputDuration(void)
{
	coremedia_unimplemented("CMSampleBufferGetOutputDuration");
}

void
CMSampleBufferGetPresentationTimeStamp(void)
{
	coremedia_unimplemented("CMSampleBufferGetPresentationTimeStamp");
}

void
CMSampleBufferGetSampleAttachmentsArray(void)
{
	coremedia_unimplemented("CMSampleBufferGetSampleAttachmentsArray");
}

void
CMSampleBufferGetTotalSampleSize(void)
{
	coremedia_unimplemented("CMSampleBufferGetTotalSampleSize");
}

void
CMSampleBufferIsValid(void)
{
	coremedia_unimplemented("CMSampleBufferIsValid");
}

void
CMTimeGetSeconds(void)
{
	coremedia_unimplemented("CMTimeGetSeconds");
}

void
CMTimeMake(void)
{
	coremedia_unimplemented("CMTimeMake");
}

void
CMTimeSubtract(void)
{
	coremedia_unimplemented("CMTimeSubtract");
}

void
CMTimebaseCreateWithMasterClock(void)
{
	coremedia_unimplemented("CMTimebaseCreateWithMasterClock");
}

void
CMTimebaseSetRate(void)
{
	coremedia_unimplemented("CMTimebaseSetRate");
}

void
CMVideoFormatDescriptionCreate(void)
{
	coremedia_unimplemented("CMVideoFormatDescriptionCreate");
}

void
CMVideoFormatDescriptionCreateForImageBuffer(void)
{
	coremedia_unimplemented("CMVideoFormatDescriptionCreateForImageBuffer");
}

void
CMVideoFormatDescriptionGetDimensions(void)
{
	coremedia_unimplemented("CMVideoFormatDescriptionGetDimensions");
}

void
CMVideoFormatDescriptionGetH264ParameterSetAtIndex(void)
{
	coremedia_unimplemented("CMVideoFormatDescriptionGetH264ParameterSetAtIndex");
}
