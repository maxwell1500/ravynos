/*
 * VideoToolbox -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement VideoToolbox yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/VideoToolbox.framework/Versions/A/VideoToolbox
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from VideoToolbox (measured from its Mach-O undefined symbols against
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
videotoolbox_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] VideoToolbox: %s is not implemented\n", name);
	}
}


long kVTCompressionPropertyKey_AllowFrameReordering __attribute__((visibility("default"))) = 0;
long kVTCompressionPropertyKey_AverageBitRate __attribute__((visibility("default"))) = 0;
long kVTCompressionPropertyKey_MaxKeyFrameInterval __attribute__((visibility("default"))) = 0;
long kVTCompressionPropertyKey_ProfileLevel __attribute__((visibility("default"))) = 0;
long kVTCompressionPropertyKey_RealTime __attribute__((visibility("default"))) = 0;
long kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder __attribute__((visibility("default"))) = 0;
long kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder __attribute__((visibility("default"))) = 0;
long kVTEncodeFrameOptionKey_ForceKeyFrame __attribute__((visibility("default"))) = 0;
long kVTProfileLevel_H264_Baseline_AutoLevel __attribute__((visibility("default"))) = 0;
long kVTProfileLevel_H264_Main_AutoLevel __attribute__((visibility("default"))) = 0;
long kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder __attribute__((visibility("default"))) = 0;
long kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder __attribute__((visibility("default"))) = 0;
void
VTCompressionSessionCompleteFrames(void)
{
	videotoolbox_unimplemented("VTCompressionSessionCompleteFrames");
}

void
VTCompressionSessionCreate(void)
{
	videotoolbox_unimplemented("VTCompressionSessionCreate");
}

void
VTCompressionSessionEncodeFrame(void)
{
	videotoolbox_unimplemented("VTCompressionSessionEncodeFrame");
}

void
VTCompressionSessionInvalidate(void)
{
	videotoolbox_unimplemented("VTCompressionSessionInvalidate");
}

void
VTDecompressionSessionCreate(void)
{
	videotoolbox_unimplemented("VTDecompressionSessionCreate");
}

void
VTDecompressionSessionDecodeFrame(void)
{
	videotoolbox_unimplemented("VTDecompressionSessionDecodeFrame");
}

void
VTDecompressionSessionInvalidate(void)
{
	videotoolbox_unimplemented("VTDecompressionSessionInvalidate");
}

void
VTDecompressionSessionWaitForAsynchronousFrames(void)
{
	videotoolbox_unimplemented("VTDecompressionSessionWaitForAsynchronousFrames");
}

void
VTSessionCopyProperty(void)
{
	videotoolbox_unimplemented("VTSessionCopyProperty");
}

void
VTSessionSetProperty(void)
{
	videotoolbox_unimplemented("VTSessionSetProperty");
}
