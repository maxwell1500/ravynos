/*
 * ============================================================================
 * PROVISIONAL - ravynOS-INTERNAL LAYOUT. NOT Apple's ABI. DO NOT TREAT AS
 * A RECOVERED STRUCTURE.
 * ============================================================================
 *
 * `struct os_log_pack_s` is defined in NO public source available to this
 * project. It is absent from every header in the host macOS SDK (the only
 * places the names appear are .tbd files, which list exported symbol NAMES
 * and never carry layouts), absent from the ravynOS SDK, absent from
 * Kernel/xnu/libkern/os/log.h, and absent from the vendored LLVM tree.
 * `log_mem.h` does not exist in the host SDK at all.
 *
 * The struct below is therefore a LOCAL SUBSTITUTION, invented for this tree
 * so that libsystem_c can compile. It is NOT a reconstruction of Apple's
 * structure and makes NO claim of binary compatibility with one. The field
 * order and sizes are this file's choice.
 *
 * Why that is currently safe: in this tree nothing ever reads a pack header
 * back.
 *   - libsystem_trace/log.c:267 `os_log_pack_send` is a FIXME no-op whose body
 *     is a comment, "Send completed pack to ring buffer for logging".
 *   - libsystem_c/os/assumes.c:262-269 resolves `os_log_pack_send_and_compose`
 *     and `_os_log_default` with dlsym(RTLD_DEFAULT) and returns false if
 *     either is absent. Neither symbol exists here, so on ravynOS that path
 *     always bails out.
 *
 * THE ONE PLACE THIS LEAKS: assumes.c:274 passes the raw pack to
 *     abort_with_payload(OS_REASON_LIBSYSTEM, ..., pack, pack_size, composed, 0)
 * which archives it for crash analysis. If a consumer of that archived buffer
 * ever expects Apple's layout, this will be misread. That is why the marking
 * is PROVISIONAL: it is correct only while the crash-reporter consumer is
 * also ravynOS-internal.
 *
 * This file is NOT a fix for the ABI question. It is a local substitution
 * that unblocks components. See
 * Libraries/Libsystem/NOTES_os_log_pack_and_log_mem.md.
 *
 * To do this properly, fetch the public SDK header os/log.h / os/log_mem.h
 * from a real macOS SDK. That is a header-import task, categorically
 * different from the binary mining that was correctly refused.
 * ============================================================================
 */

#ifndef __RAVYNOS_OS_LOG_PACK_PRIVATE_H
#define __RAVYNOS_OS_LOG_PACK_PRIVATE_H

/*
 * Pull in the real os/log API first (os_log_t, OS_LOG_TYPE_*, the os_log()
 * macro family, os_log_encode, ...). This is a chain, not a replacement:
 * everything defined below is the provisional part.
 */
#include_next <os/log.h>

#include <stdint.h>
#include <stddef.h>
#include <time.h>

/*
 * PROVISIONAL ravynOS-internal layout. The five fields are exactly those
 * referenced in-tree:
 *   libsystem_trace/log.c:252  s->olp_continuous_time = mach_continuous_time();
 *   libsystem_trace/log.c:253  clock_gettime(CLOCK_REALTIME, &s->olp_wall_time);
 *   libsystem_trace/log.c:257  s->olp_mh = info.dli_fbase;
 *   libsystem_trace/log.c:259  s->olp_pc = dso;
 *   libsystem_trace/log.c:260  s->olp_format = (const char *)payload;
 *   libsystem_c/os/assumes.c:259  const char *message = pack->olp_format;
 *
 * Payload (the format string and the encoded arguments) starts immediately
 * after this header, which is what log.c:249 assumes:
 *     uint8_t *payload = (uint8_t *)pack + sizeof(struct os_log_pack_s);
 */
struct os_log_pack_s {
	uint64_t	olp_continuous_time;	/* mach_continuous_time() */
	struct timespec	olp_wall_time;		/* CLOCK_REALTIME */
	const void	*olp_mh;		/* mach_header of the dso */
	const void	*olp_pc;		/* calling pc */
	const char	*olp_format;		/* payload follows the header */
};

/*
 * Apple declares the tag AND both typedefs; this file originally declared
 * only the pointer one.  That is invisible until someone uses the bare
 * struct as a TYPE rather than through the pointer typedef --
 * libsystem_c/os/assumes.h:77 does exactly that:
 *
 *     uint8_t buf[size] __attribute__((aligned(alignof(os_log_pack_s))));
 *
 * "struct os_log_pack_s" is a tag, not an identifier, so with only
 * os_log_pack_t present that line fails with
 *     assumes.h:130:3: error: use of undeclared identifier 'os_log_pack_s'
 * which is how libsystem_darwin was blocked.  Declare the struct typedef
 * too, matching Apple.
 */
typedef struct os_log_pack_s os_log_pack_s;

typedef struct os_log_pack_s *os_log_pack_t;

#ifdef __cplusplus
extern "C" {
#endif

size_t		os_log_pack_size(const char *format, void *args, uint32_t flags);
uint8_t	*os_log_pack_fill(void *pack, size_t pack_size, int saved_errno,
		    const void *dso, const char *format);

#ifdef __cplusplus
}
#endif

#endif /* __RAVYNOS_OS_LOG_PACK_PRIVATE_H */
