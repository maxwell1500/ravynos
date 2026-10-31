/*
 * ImageIO -- compatibility surface for stock macOS binaries.
 *
 * ravynOS does not implement ImageIO yet.  This library exists because a
 * stock application (Firefox 115 ESR is the conformance oracle) links it by
 * name, and dyld refuses to load the application at all when one of its
 * LC_LOAD_DYLIB entries is missing:
 *
 *   dlopen(.../XUL, 265): Library not loaded:
 *     /System/Library/Frameworks/ImageIO.framework/Versions/A/ImageIO
 *     Reason: image not found
 *
 * The symbols below are exactly the ones the staged application bundle
 * imports from ImageIO (measured from its Mach-O undefined symbols against
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
imageio_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] ImageIO: %s is not implemented\n", name);
	}
}


long kCGImageSourceShouldAllowFloat __attribute__((visibility("default"))) = 0;
void
kCGImageSourceTypeIdentifierHint(void)
{
	imageio_unimplemented("kCGImageSourceTypeIdentifierHint");
}
