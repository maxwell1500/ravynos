/*
 * AudioUnit -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement AudioUnit yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/AudioUnit.framework/Versions/A/AudioUnit
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from AudioUnit (measured from its Mach-O undefined symbols against
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
audiounit_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] AudioUnit: %s is not implemented\n", name);
	}
}


void
AudioComponentFindNext(void)
{
	audiounit_unimplemented("AudioComponentFindNext");
}

void
AudioComponentInstanceDispose(void)
{
	audiounit_unimplemented("AudioComponentInstanceDispose");
}

void
AudioComponentInstanceNew(void)
{
	audiounit_unimplemented("AudioComponentInstanceNew");
}

void
AudioOutputUnitStart(void)
{
	audiounit_unimplemented("AudioOutputUnitStart");
}

void
AudioOutputUnitStop(void)
{
	audiounit_unimplemented("AudioOutputUnitStop");
}

void
AudioUnitAddPropertyListener(void)
{
	audiounit_unimplemented("AudioUnitAddPropertyListener");
}

void
AudioUnitGetParameter(void)
{
	audiounit_unimplemented("AudioUnitGetParameter");
}

void
AudioUnitGetProperty(void)
{
	audiounit_unimplemented("AudioUnitGetProperty");
}

void
AudioUnitGetPropertyInfo(void)
{
	audiounit_unimplemented("AudioUnitGetPropertyInfo");
}

void
AudioUnitInitialize(void)
{
	audiounit_unimplemented("AudioUnitInitialize");
}

void
AudioUnitRemovePropertyListenerWithUserData(void)
{
	audiounit_unimplemented("AudioUnitRemovePropertyListenerWithUserData");
}

void
AudioUnitRender(void)
{
	audiounit_unimplemented("AudioUnitRender");
}

void
AudioUnitSetParameter(void)
{
	audiounit_unimplemented("AudioUnitSetParameter");
}

void
AudioUnitSetProperty(void)
{
	audiounit_unimplemented("AudioUnitSetProperty");
}

void
AudioUnitUninitialize(void)
{
	audiounit_unimplemented("AudioUnitUninitialize");
}
