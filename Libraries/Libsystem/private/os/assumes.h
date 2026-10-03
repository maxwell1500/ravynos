/*
 * ravynOS shim for <os/assumes.h>.
 *
 * WHY THIS EXISTS
 *
 * The SDK's usr/local/include/os/assumes.h uses `os_log_pack_s` (lines 130,
 * 134, 157, 185) but never includes <os/log.h> -- only os/log_private.h at
 * line 70, which does not declare the type. So `os_log_pack_s` is undeclared
 * at first use and 381 of the 441 libFreeBSD sources fail on it. They are all
 * one error, not 381.
 *
 * The type is declared in NO public Apple source available to this tree; see
 * Libraries/Libsystem/NOTES_os_log_pack_and_log_mem.md. It is supplied by the
 * sibling shim private/os/log.h.
 *
 * READ private/os/log.h FIRST. That file carries a PROVISIONAL banner: the
 * layout is ravynOS-internal, is NOT Apple's, and is not a recovered ABI. This
 * shim and that header are a pair -- do not simplify one without the other.
 *
 * This is a shim, not a replacement: it establishes the type and then chains to
 * the real header, so every declaration in the SDK's os/assumes.h still applies.
 *
 * Deliberately NOT done instead: adding -I to the libsystem_c root, which
 * would shadow eight SDK header namespaces (sys, net, string, stdio, stdlib,
 * os, util, locale) and trade one clear error for a diffuse one.
 */

#ifndef __RAVYNOS_OS_ASSUMES_H_SHIM
#define __RAVYNOS_OS_ASSUMES_H_SHIM

/* Establishes os_log_pack_s / os_log_pack_t before anything below uses them.
 *
 * WHY ANGLED, NOT QUOTED -- this is load-bearing, do not "simplify" it.
 *
 * `#include_next` only advances when the current file was itself found BY
 * POSITION in the -I list. A quoted `#include "log.h"` resolves relative to
 * this file's own directory, so the shim's os/log.h is entered with NO position
 * in the search list. Its own `#include_next <os/log.h>` then has nothing to
 * advance from: clang considers ZERO candidates and fails immediately, even
 * though several -I entries remain and Kernel/xnu/libkern (position 15) does
 * contain os/log.h. `clang -H` shows the signature exactly: `.` for
 * os/assumes.h, then `..` for os/log.h, then instant termination.
 *
 * The angled form re-enters os/log.h BY POSITION -- the generated overlay
 * directory is on the -I list, so the overlay's copy of the provisional header
 * is found there and its #include_next correctly advances past that position to
 * the real header. It terminates, and it finds the right thing.
 *
 * INVARIANT THIS DEPENDS ON (enforced, not assumed -- see
 * Libraries/check_include_order.sh): the generated overlay directory MUST
 * appear on the -I list BEFORE any other os/log.h provider -- that is, before
 * the SDK's usr/include, before Kernel/xnu/libkern, and before
 * System.framework/.../PrivateHeaders. If the wrapper cannot guarantee that
 * ordering, the angled form is unsafe and this breaks again.
 *
 * This header and os/log.h are a PAIR. Do not simplify one without the other.
 */
#include <os/log.h>
/*
 * The SDK's os/assumes.h:77 writes `alignof(os_log_pack_s)` using the BARE
 * TAG NAME. In C11/C17 a bare struct tag is not a type name, so `alignof`
 * has nothing to ask about -- the diagnostic points at the callers
 * (os_assert_sprintf etc., lines 130/134/157/185) rather than at the real
 * use site, which is what made this look like a missing-struct problem.
 * Defining the struct is not sufficient; this alias is what makes it legal.
 * C23's implicit-typename rule does not help either: -std=c23 still errors
 * on this compiler.
 *
 * This adds a NAME only. No field, size or alignment claim is introduced, so
 * the PROVISIONAL banner in log.h is unaffected. It is placed here rather
 * than in log.h to keep it scoped to the one header that needs it.
 */
typedef struct os_log_pack_s os_log_pack_s;

#include_next <os/assumes.h>

#endif /* __RAVYNOS_OS_ASSUMES_H_SHIM */
