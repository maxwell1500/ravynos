/*
 * CoreAudio -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement CoreAudio yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/CoreAudio.framework/Versions/A/CoreAudio
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from CoreAudio (measured from its Mach-O undefined symbols against
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
coreaudio_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] CoreAudio: %s is not implemented\n", name);
	}
}


void
AudioConvertHostTimeToNanos(void)
{
	coreaudio_unimplemented("AudioConvertHostTimeToNanos");
}

void
AudioGetCurrentHostTime(void)
{
	coreaudio_unimplemented("AudioGetCurrentHostTime");
}

void
AudioObjectAddPropertyListener(void)
{
	coreaudio_unimplemented("AudioObjectAddPropertyListener");
}

void
AudioObjectGetPropertyData(void)
{
	coreaudio_unimplemented("AudioObjectGetPropertyData");
}

void
AudioObjectGetPropertyDataSize(void)
{
	coreaudio_unimplemented("AudioObjectGetPropertyDataSize");
}

void
AudioObjectHasProperty(void)
{
	coreaudio_unimplemented("AudioObjectHasProperty");
}

void
AudioObjectRemovePropertyListener(void)
{
	coreaudio_unimplemented("AudioObjectRemovePropertyListener");
}

void
AudioObjectSetPropertyData(void)
{
	coreaudio_unimplemented("AudioObjectSetPropertyData");
}
