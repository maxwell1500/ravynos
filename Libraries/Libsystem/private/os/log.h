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

#include <stdarg.h>		/* va_list, for _os_log_encode below */
#include <stdint.h>
#include <stddef.h>
#include <time.h>

/*
 * Pulled in for lck_spin_t, which xnu's libkern/os/log_mem.h:36 needs as a
 * struct member and which is declared nowhere in this tree (no lck.h exists
 * here at all). log_mem.h is reached from <os/log_encode_types.h>, which
 * log.c includes at log.c:50 -- after this header -- so providing the type
 * here is what keeps that include chain compiling. See os/lck.h for why that
 * is currently safe.
 */
#include <os/lck.h>

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

/*
 * ======================= PROVISIONAL, ravynOS-INTERNAL =======================
 *
 * The buffer types below are declared by NO header available to this project.
 * They are not in the host macOS SDK (which ships only os/log.h -- os/
 * log_private.h, os/log_encode_types.h, os/log_encode.h and os/log_mem.h are
 * all absent there), and they are not in xnu's copies either: xnu's
 * libkern/os/log_encode_types.h defines struct os_log_context_s with the
 * KERNEL field names (ctx_logmem, ctx_buffer, ctx_hdr, ...) and has no
 * os_log_buffer_s at all.
 *
 * libsystem_trace/log.c uses the USER-space spelling, and these are the exact
 * members it assigns, at log.c:183-187 and 193:
 *
 *     ctx->log         = OS_LOG_DEFAULT;
 *     ctx->buffer      = (os_log_buffer_t)buffer;
 *     ctx->content_sz  = buffer_size - sizeof(struct os_log_buffer_s);
 *     ctx->comp        = compspace;
 *     ctx->comp_sz     = sizeof(compspace);
 *     ... ctx->content_off ...
 *
 * so the layout below is derived from that file's own use of it, exactly as
 * struct os_log_pack_s above was. It is NOT Apple's layout and makes NO claim
 * of binary compatibility with one.
 *
 * Why that is currently safe, same reasoning as os_log_pack_s above:
 *   - _os_log_encode below is ravynOS-INTERNAL and defined in log.c itself.
 *     It is the only writer and the only reader of these bytes.
 *   - The buffer is handed to abort_with_payload() purely as an opaque
 *     crash-reason blob. Nothing in this tree decodes it.
 *   So the serialized form is a closed loop inside libsystem_trace. That is
 * what would stop being true if a logd/ log archive reader were ever added --
 * then this header must be replaced by the real os/log_private.h.
 * ============================================================================
 */

struct os_log_buffer_s {
	/* Header of a serialized os_log_encode() buffer. Contents are written and
 * read only by _os_log_encode; see the note above before relying on it. */
	uint8_t		ob_buffer[32];
};

typedef struct os_log_buffer_s *os_log_buffer_t;

struct os_log_buffer_context_s {
	void			*log;		/* os_log_t, passed through */
	os_log_buffer_t	buffer;
	size_t		content_sz;
	char		*comp;		/* composition scratch buffer */
	size_t		comp_sz;
	size_t		content_off;
};

typedef struct os_log_buffer_context_s *os_log_buffer_context_t;

#ifdef __cplusplus
extern "C" {
#endif

size_t		os_log_pack_size(const char *format, void *args, uint32_t flags);
uint8_t	*os_log_pack_fill(void *pack, size_t pack_size, int saved_errno,
		    const void *dso, const char *format);

/*
 * One encoded argument in an os_log pack. Declared by no header available to
 * this project -- not the host SDK (which ships only os/log.h), not xnu. Its
 * shape is taken from the single field libsystem_trace reads,
 * log.c:283 `psize += ah->payload_size`, walking one entry per non-'%%'
 * conversion in the format string.
 *
 * Both the writer and the reader of these entries are in this tree: the
 * caller in libsystem_c/os/assumes.h builds the array and passes it as `args'
 * to os_log_pack_size(), and log.c reads it back. They therefore only have to
 * agree with each other, which is why this can be defined rather than
 * recovered. As with os_log_pack_s above, this is ravynOS-INTERNAL and claims
 * no compatibility with Apple's.
 */
typedef struct _os_log_arg_header {
	uint32_t	payload_size;
} _os_log_arg_header;

/*
 * The encoder. Declared here rather than in os/log_encode.h because that
 * header is xnu's KERNEL encoder (it pulls log_mem.h and lck_spin_t) and does
 * not declare this. The definition is ravynOS-INTERNAL and lives in
 * libsystem_trace/log.c; see the PROVISIONAL note above.
 */
bool	_os_log_encode(const char *format, va_list args, int saved_errno,
		    os_log_buffer_context_t ctx);

#ifdef __cplusplus
}
#endif

#endif /* __RAVYNOS_OS_LOG_PACK_PRIVATE_H */
