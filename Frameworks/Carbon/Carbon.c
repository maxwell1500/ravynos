/*
 * Carbon -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement Carbon yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/Carbon.framework/Versions/A/Carbon
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from Carbon (measured from its Mach-O undefined symbols against
 * the SDK's own .tbd exports, not guessed).  Data symbols are zero, which
 * reads as NULL/invalid rather than as a plausible-looking value.  Function
 * symbols log one line the first time they are called and return zero; they
 * never report success for an operation ravynOS did not perform.
 *
 * Replacing a function with a real implementation is how this file shrinks.
 * Nothing here may be widened to "define everything the framework exports".
 */
#include <stdio.h>

#include <CoreFoundation/CoreFoundation.h>

static void
carbon_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] Carbon: %s is not implemented\n", name);
	}
}


/*
 * Text Input Sources constants.  These are CFStringRef data symbols, not
 * zero: Gecko reads the symbol and passes the string to CFStringCompare,
 * and a NULL there faults in CFStringGetLength.  The values are the names
 * HIToolbox uses for the same constants.
 */
CFStringRef kTISNotifySelectedKeyboardInputSourceChanged __attribute__((visibility("default"))) = CFSTR("TISNotifySelectedKeyboardInputSourceChanged");
CFStringRef kTISPropertyBundleID __attribute__((visibility("default"))) = CFSTR("TISPropertyBundleID");
CFStringRef kTISPropertyInputSourceID __attribute__((visibility("default"))) = CFSTR("TISPropertyInputSourceID");
CFStringRef kTISPropertyInputSourceIsASCIICapable __attribute__((visibility("default"))) = CFSTR("TISPropertyInputSourceIsASCIICapable");
CFStringRef kTISPropertyInputSourceIsEnabled __attribute__((visibility("default"))) = CFSTR("TISPropertyInputSourceIsEnabled");
CFStringRef kTISPropertyInputSourceLanguages __attribute__((visibility("default"))) = CFSTR("TISPropertyInputSourceLanguages");
CFStringRef kTISPropertyInputSourceType __attribute__((visibility("default"))) = CFSTR("TISPropertyInputSourceType");
CFStringRef kTISPropertyLocalizedName __attribute__((visibility("default"))) = CFSTR("TISPropertyLocalizedName");
CFStringRef kTISPropertyUnicodeKeyLayoutData __attribute__((visibility("default"))) = CFSTR("TISPropertyUnicodeKeyLayoutData");
CFStringRef kTISTypeKeyboardInputMode __attribute__((visibility("default"))) = CFSTR("TISTypeKeyboardInputMode");
CFStringRef kTISTypeKeyboardLayout __attribute__((visibility("default"))) = CFSTR("TISTypeKeyboardLayout");
void
AcquireFirstMatchingEventInQueue(void)
{
	carbon_unimplemented("AcquireFirstMatchingEventInQueue");
}

void
DisableSecureEventInput(void)
{
	carbon_unimplemented("DisableSecureEventInput");
}

void
EnableSecureEventInput(void)
{
	carbon_unimplemented("EnableSecureEventInput");
}

void
GetCurrentEventKeyModifiers(void)
{
	carbon_unimplemented("GetCurrentEventKeyModifiers");
}

void
GetCurrentEventQueue(void)
{
	carbon_unimplemented("GetCurrentEventQueue");
}

void
GetThemeMetric(void)
{
	carbon_unimplemented("GetThemeMetric");
}

void
HIThemeDrawButton(void)
{
	carbon_unimplemented("HIThemeDrawButton");
}

void
HIThemeDrawGroupBox(void)
{
	carbon_unimplemented("HIThemeDrawGroupBox");
}

void
HIThemeDrawMenuSeparator(void)
{
	carbon_unimplemented("HIThemeDrawMenuSeparator");
}

void
HIThemeDrawSeparator(void)
{
	carbon_unimplemented("HIThemeDrawSeparator");
}

void
HIThemeDrawTabPane(void)
{
	carbon_unimplemented("HIThemeDrawTabPane");
}

void
HIThemeDrawTrack(void)
{
	carbon_unimplemented("HIThemeDrawTrack");
}

void
KBGetLayoutType(void)
{
	carbon_unimplemented("KBGetLayoutType");
}

void
LMGetKbdType(void)
{
	carbon_unimplemented("LMGetKbdType");
}

void
ReceiveNextEvent(void)
{
	carbon_unimplemented("ReceiveNextEvent");
}

void
TISCopyCurrentASCIICapableKeyboardInputSource(void)
{
	carbon_unimplemented("TISCopyCurrentASCIICapableKeyboardInputSource");
}

void
TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void)
{
	carbon_unimplemented("TISCopyCurrentASCIICapableKeyboardLayoutInputSource");
}

void
TISCopyCurrentKeyboardInputSource(void)
{
	carbon_unimplemented("TISCopyCurrentKeyboardInputSource");
}

void
TISCopyCurrentKeyboardLayoutInputSource(void)
{
	carbon_unimplemented("TISCopyCurrentKeyboardLayoutInputSource");
}

void
TISCopyInputMethodKeyboardLayoutOverride(void)
{
	carbon_unimplemented("TISCopyInputMethodKeyboardLayoutOverride");
}

void
TISCopyInputSourceForLanguage(void)
{
	carbon_unimplemented("TISCopyInputSourceForLanguage");
}

void
TISCreateASCIICapableInputSourceList(void)
{
	carbon_unimplemented("TISCreateASCIICapableInputSourceList");
}

void
TISCreateInputSourceList(void)
{
	carbon_unimplemented("TISCreateInputSourceList");
}

void
TISGetInputSourceProperty(void)
{
	carbon_unimplemented("TISGetInputSourceProperty");
}

void
TISSelectInputSource(void)
{
	carbon_unimplemented("TISSelectInputSource");
}

void
TSMGetActiveDocument(void)
{
	carbon_unimplemented("TSMGetActiveDocument");
}

void
TSMRemoveDocumentProperty(void)
{
	carbon_unimplemented("TSMRemoveDocumentProperty");
}

void
TSMSetDocumentProperty(void)
{
	carbon_unimplemented("TSMSetDocumentProperty");
}
