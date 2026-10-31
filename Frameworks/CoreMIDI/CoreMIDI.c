/*
 * CoreMIDI -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement CoreMIDI yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/CoreMIDI.framework/Versions/A/CoreMIDI
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from CoreMIDI (measured from its Mach-O undefined symbols against
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
coremidi_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] CoreMIDI: %s is not implemented\n", name);
	}
}


long kMIDIPropertyAdvanceScheduleTimeMuSec __attribute__((visibility("default"))) = 0;
long kMIDIPropertyCanRoute __attribute__((visibility("default"))) = 0;
long kMIDIPropertyConnectionUniqueID __attribute__((visibility("default"))) = 0;
long kMIDIPropertyDeviceID __attribute__((visibility("default"))) = 0;
long kMIDIPropertyDisplayName __attribute__((visibility("default"))) = 0;
long kMIDIPropertyDriverDeviceEditorApp __attribute__((visibility("default"))) = 0;
long kMIDIPropertyDriverOwner __attribute__((visibility("default"))) = 0;
long kMIDIPropertyDriverVersion __attribute__((visibility("default"))) = 0;
long kMIDIPropertyIsBroadcast __attribute__((visibility("default"))) = 0;
long kMIDIPropertyIsDrumMachine __attribute__((visibility("default"))) = 0;
long kMIDIPropertyIsEffectUnit __attribute__((visibility("default"))) = 0;
long kMIDIPropertyIsEmbeddedEntity __attribute__((visibility("default"))) = 0;
long kMIDIPropertyIsMixer __attribute__((visibility("default"))) = 0;
long kMIDIPropertyIsSampler __attribute__((visibility("default"))) = 0;
long kMIDIPropertyManufacturer __attribute__((visibility("default"))) = 0;
long kMIDIPropertyMaxReceiveChannels __attribute__((visibility("default"))) = 0;
long kMIDIPropertyMaxSysExSpeed __attribute__((visibility("default"))) = 0;
long kMIDIPropertyMaxTransmitChannels __attribute__((visibility("default"))) = 0;
long kMIDIPropertyModel __attribute__((visibility("default"))) = 0;
long kMIDIPropertyName __attribute__((visibility("default"))) = 0;
long kMIDIPropertyOffline __attribute__((visibility("default"))) = 0;
long kMIDIPropertyPanDisruptsStereo __attribute__((visibility("default"))) = 0;
long kMIDIPropertyPrivate __attribute__((visibility("default"))) = 0;
long kMIDIPropertyReceiveChannels __attribute__((visibility("default"))) = 0;
long kMIDIPropertyReceivesBankSelectLSB __attribute__((visibility("default"))) = 0;
long kMIDIPropertyReceivesBankSelectMSB __attribute__((visibility("default"))) = 0;
long kMIDIPropertyReceivesClock __attribute__((visibility("default"))) = 0;
long kMIDIPropertyReceivesMTC __attribute__((visibility("default"))) = 0;
long kMIDIPropertyReceivesNotes __attribute__((visibility("default"))) = 0;
long kMIDIPropertyReceivesProgramChanges __attribute__((visibility("default"))) = 0;
long kMIDIPropertySingleRealtimeEntity __attribute__((visibility("default"))) = 0;
long kMIDIPropertySupportsGeneralMIDI __attribute__((visibility("default"))) = 0;
long kMIDIPropertySupportsMMC __attribute__((visibility("default"))) = 0;
long kMIDIPropertySupportsShowControl __attribute__((visibility("default"))) = 0;
long kMIDIPropertyTransmitChannels __attribute__((visibility("default"))) = 0;
long kMIDIPropertyTransmitsBankSelectLSB __attribute__((visibility("default"))) = 0;
long kMIDIPropertyTransmitsBankSelectMSB __attribute__((visibility("default"))) = 0;
long kMIDIPropertyTransmitsClock __attribute__((visibility("default"))) = 0;
long kMIDIPropertyTransmitsMTC __attribute__((visibility("default"))) = 0;
long kMIDIPropertyTransmitsNotes __attribute__((visibility("default"))) = 0;
long kMIDIPropertyTransmitsProgramChanges __attribute__((visibility("default"))) = 0;
long kMIDIPropertyUniqueID __attribute__((visibility("default"))) = 0;
void
MIDIClientCreate(void)
{
	coremidi_unimplemented("MIDIClientCreate");
}

void
MIDIClientDispose(void)
{
	coremidi_unimplemented("MIDIClientDispose");
}

void
MIDIEndpointDispose(void)
{
	coremidi_unimplemented("MIDIEndpointDispose");
}

void
MIDIFlushOutput(void)
{
	coremidi_unimplemented("MIDIFlushOutput");
}

void
MIDIGetDestination(void)
{
	coremidi_unimplemented("MIDIGetDestination");
}

void
MIDIGetNumberOfDestinations(void)
{
	coremidi_unimplemented("MIDIGetNumberOfDestinations");
}

void
MIDIGetNumberOfSources(void)
{
	coremidi_unimplemented("MIDIGetNumberOfSources");
}

void
MIDIGetSource(void)
{
	coremidi_unimplemented("MIDIGetSource");
}

void
MIDIInputPortCreate(void)
{
	coremidi_unimplemented("MIDIInputPortCreate");
}

void
MIDIObjectGetIntegerProperty(void)
{
	coremidi_unimplemented("MIDIObjectGetIntegerProperty");
}

void
MIDIObjectGetStringProperty(void)
{
	coremidi_unimplemented("MIDIObjectGetStringProperty");
}

void
MIDIObjectSetIntegerProperty(void)
{
	coremidi_unimplemented("MIDIObjectSetIntegerProperty");
}

void
MIDIObjectSetStringProperty(void)
{
	coremidi_unimplemented("MIDIObjectSetStringProperty");
}

void
MIDIOutputPortCreate(void)
{
	coremidi_unimplemented("MIDIOutputPortCreate");
}

void
MIDIPortConnectSource(void)
{
	coremidi_unimplemented("MIDIPortConnectSource");
}

void
MIDIPortDisconnectSource(void)
{
	coremidi_unimplemented("MIDIPortDisconnectSource");
}

void
MIDIPortDispose(void)
{
	coremidi_unimplemented("MIDIPortDispose");
}

void
MIDIReceived(void)
{
	coremidi_unimplemented("MIDIReceived");
}

void
MIDIRestart(void)
{
	coremidi_unimplemented("MIDIRestart");
}

void
MIDISend(void)
{
	coremidi_unimplemented("MIDISend");
}

void
MIDISourceCreate(void)
{
	coremidi_unimplemented("MIDISourceCreate");
}
