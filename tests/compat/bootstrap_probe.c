/*
 * bootstrap_probe -- is the launchd bootstrap port usable after dropping
 * privileges?
 *
 * Firefox runs as uid 501 (runas) and stops right after AppKit prints its
 * bundle id, before "WindowServer service located"; the next call in that
 * function is bootstrap_look_up().  This probe does exactly those two calls
 * and prints each step, so a hang can be attributed to the bootstrap
 * protocol instead of the browser.
 */
#include <mach/mach.h>
#include <stdio.h>
#include <unistd.h>

extern mach_port_t bootstrap_port;
extern void bootstrap_init(void);
extern kern_return_t bootstrap_look_up(mach_port_t, const char *,
    mach_port_t *);

int
main(void)
{
	mach_port_t port = MACH_PORT_NULL;
	kern_return_t kr;

	bootstrap_init();
	printf("bootstrap: uid=%u port=%u\n", (unsigned)getuid(),
	    (unsigned)bootstrap_port);
	fflush(stdout);

	kr = bootstrap_look_up(bootstrap_port, "com.ravynos.WindowServer", &port);
	printf("bootstrap: look_up kr=0x%x port=%u\n", (unsigned)kr,
	    (unsigned)port);
	return (kr == 0 ? 0 : 1);
}
