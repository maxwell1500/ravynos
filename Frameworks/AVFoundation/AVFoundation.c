/*
 * AVFoundation -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement AVFoundation yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/AVFoundation.framework/Versions/A/AVFoundation
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from AVFoundation (measured from its Mach-O undefined symbols against
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
avfoundation_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] AVFoundation: %s is not implemented\n", name);
	}
}


long AVCaptureDeviceWasConnectedNotification __attribute__((visibility("default"))) = 0;
long AVCaptureDeviceWasDisconnectedNotification __attribute__((visibility("default"))) = 0;
long AVCaptureSessionDidStartRunningNotification __attribute__((visibility("default"))) = 0;
long AVCaptureSessionDidStopRunningNotification __attribute__((visibility("default"))) = 0;
long AVCaptureSessionErrorKey __attribute__((visibility("default"))) = 0;
long AVCaptureSessionPreset1280x720 __attribute__((visibility("default"))) = 0;
long AVCaptureSessionPreset352x288 __attribute__((visibility("default"))) = 0;
long AVCaptureSessionPreset640x480 __attribute__((visibility("default"))) = 0;
long AVCaptureSessionPresetLow __attribute__((visibility("default"))) = 0;
long AVCaptureSessionRuntimeErrorNotification __attribute__((visibility("default"))) = 0;
long AVMediaTypeAudio __attribute__((visibility("default"))) = 0;
long AVMediaTypeVideo __attribute__((visibility("default"))) = 0;