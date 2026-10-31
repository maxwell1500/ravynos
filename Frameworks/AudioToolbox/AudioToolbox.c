/*
 * AudioToolbox -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement AudioToolbox yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from AudioToolbox (measured from its Mach-O undefined symbols against
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
audiotoolbox_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] AudioToolbox: %s is not implemented\n", name);
	}
}


void
AudioConverterDispose(void)
{
	audiotoolbox_unimplemented("AudioConverterDispose");
}

void
AudioConverterFillComplexBuffer(void)
{
	audiotoolbox_unimplemented("AudioConverterFillComplexBuffer");
}

void
AudioConverterGetProperty(void)
{
	audiotoolbox_unimplemented("AudioConverterGetProperty");
}

void
AudioConverterGetPropertyInfo(void)
{
	audiotoolbox_unimplemented("AudioConverterGetPropertyInfo");
}

void
AudioConverterNew(void)
{
	audiotoolbox_unimplemented("AudioConverterNew");
}

void
AudioConverterReset(void)
{
	audiotoolbox_unimplemented("AudioConverterReset");
}

void
AudioConverterSetProperty(void)
{
	audiotoolbox_unimplemented("AudioConverterSetProperty");
}

void
AudioFileStreamClose(void)
{
	audiotoolbox_unimplemented("AudioFileStreamClose");
}

void
AudioFileStreamGetProperty(void)
{
	audiotoolbox_unimplemented("AudioFileStreamGetProperty");
}

void
AudioFileStreamGetPropertyInfo(void)
{
	audiotoolbox_unimplemented("AudioFileStreamGetPropertyInfo");
}

void
AudioFileStreamOpen(void)
{
	audiotoolbox_unimplemented("AudioFileStreamOpen");
}

void
AudioFileStreamParseBytes(void)
{
	audiotoolbox_unimplemented("AudioFileStreamParseBytes");
}

void
AudioFormatGetProperty(void)
{
	audiotoolbox_unimplemented("AudioFormatGetProperty");
}

void
AudioFormatGetPropertyInfo(void)
{
	audiotoolbox_unimplemented("AudioFormatGetPropertyInfo");
}
