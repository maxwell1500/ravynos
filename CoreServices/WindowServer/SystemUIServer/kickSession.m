#import <AppKit/AppKit.h>
#include <servers/bootstrap.h>

/*
 * ravynOS kickSession
 *
 * Run by SystemUIServer (SystemUIServer.m:44-53) once WindowServer has reached
 * the DESKTOP state.  Its own comment states the intent: "kick off a per-user
 * launchd to invoke LaunchAgents and per-user LaunchDaemons / this starts Filer
 * and Dock to establish the desktop session."
 *
 * The mechanism is the private liblaunch session switch.  Asking launchd to
 * move this process to the Background session makes launchd create that session
 * (jobmgr_init_session -> "/bin/launchctl bootstrap -S Background"); launchctl's
 * Background branch then scans agent_paths[] (/System/Library/LaunchAgents,
 * /Library/LaunchAgents) and submits Dock and Filer.  Without this call the
 * Background session is never created and the agent scan never runs.
 *
 * _vprocmgr_switch_to_session() is exported by liblaunch.dylib
 * (Libraries/Libsystem/liblaunch/libvproc.c:459; declared in vproc_priv.h:169).
 * vproc_priv.h is not in the SDK, so the prototype and the two typedefs it needs
 * are declared here.  VPROCMGR_SESSION_BACKGROUND is the string "Background"
 * (vproc_priv.h:45).  liblaunch is linked by this target's -llaunch.
 */
typedef void *vproc_err_t;
typedef unsigned int vproc_flags_t;
extern vproc_err_t _vprocmgr_switch_to_session(const char *target_session,
                                               vproc_flags_t flags);

int main(int argc, const char **argv) {
    __NSInitializeProcess(argc, argv);

    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    /* Locate the WindowServer port first, so a missing WindowServer is reported
     * before we try to start the desktop session. */
    mach_port_t tmp = MACH_PORT_NULL;
    int rc = bootstrap_look_up(bootstrap_port, "com.ravynos.WindowServer", &tmp);
    if(rc != KERN_SUCCESS)
        NSLog(@"Failed to locate WindowServer port: rc=%d", rc);

    /* Move to the per-user Background session.  This is what makes launchd
     * create it and run the agent scan that starts Dock and Filer. */
    vproc_err_t verr = _vprocmgr_switch_to_session("Background", 0);
    if(verr != NULL)
        NSLog(@"Failed to switch to the Background session: %p", verr);
    else
        NSLog(@"kicked off the per-user session");

    [pool drain];
    return 0;
}
