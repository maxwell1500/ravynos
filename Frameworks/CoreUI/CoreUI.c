/*
 * CoreUI -- compatibility surface for stock macOS binaries.
 *
 * Firefox's XUL loads CoreUI by name, so the private framework has to exist
 * for dyld to load the application at all.  The only symbol the staged bundle
 * imports from it is CUIDraw, which draws window chrome; ravynOS draws its own
 * chrome through Onyx2D/WindowServer.  The trampoline logs once and returns
 * zero; it never claims a draw happened.
 */
#include <stdio.h>

static void
coreui_unimplemented(const char *name)
{
	static int logged;

	if (!logged) {
		logged = 1;
		fprintf(stderr, "[compat] CoreUI: %s is not implemented\n", name);
	}
}

void
CUIDraw(void)
{
	coreui_unimplemented("CUIDraw");
}
