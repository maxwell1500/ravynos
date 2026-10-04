/*
 * ravynos-mach-compat.h -- force-included by tools/bootlab/isysroot-cc.
 *
 * The ravynOS SDK ships a mach/ tree that is one xnu generation older than the
 * Kernel/xnu tree this libc is built from. Two declarations that
 * Kernel/xnu/libsyscall uses unconditionally are simply absent from the SDK's
 * mach/message.h:
 *
 *   Kernel/xnu/libsyscall/mach/mach/mach.h:258
 *       extern mach_msg_size_t voucher_mach_msg_fill_aux(
 *               mach_msg_aux_header_t *aux_hdr, mach_msg_size_t sz);
 *   Kernel/xnu/libsyscall/wrappers/_libkernel_init.h:124
 *       mach_msg_size_t (*voucher_mach_msg_fill_aux)(mach_msg_aux_header_t*, ...);
 *   Kernel/xnu/libsyscall/mach/mach_msg.c:204-246
 *       uint8_t inline_aux_buf[LIBSYSCALL_MSGV_AUX_MAX_SIZE];
 *
 * Without them libBase produced zero objects and libsystem_platform died after
 * 154:
 *   Kernel/xnu/libsyscall/wrappers/_libkernel_init.h:124:47: error: unknown
 *       type name 'mach_msg_aux_header_t'; did you mean 'mach_msg_header_t'?
 *
 * Both definitions below are copied from the matching header in this same tree,
 * Kernel/xnu/osfmk/mach/message.h, so the layout is the one the kernel actually
 * uses rather than a guess:
 *
 *     #define LIBSYSCALL_MSGV_AUX_MAX_SIZE 128
 *     typedef struct {
 *         mach_msg_size_t   msgdh_size;
 *         uint32_t          msgdh_reserved;   // "For future" in the original
 *     } mach_msg_aux_header_t;
 *
 * Every use in libsyscall is opaque -- the type is only ever cast to and from a
 * uint8_t scratch buffer and handed to voucher_mach_msg_fill_aux(), which fills
 * it -- so nothing depends on the field names, only on the size being at least
 * the 128-byte buffer.
 *
 * This header is force-included ONLY when build-libraries.sh has verified that
 * the SDK's mach/message.h really lacks the type (RAVYN_COMPAT_MAC_AUX), so it
 * can never collide with a mach tree that does define it. Kernel/xnu is never
 * modified.
 */

#ifndef RAVYNOS_MACH_COMPAT_H
#define RAVYNOS_MACH_COMPAT_H

#ifndef LIBSYSCALL_MSGV_AUX_MAX_SIZE
#define LIBSYSCALL_MSGV_AUX_MAX_SIZE 128
#endif

/*
 * isysroot-cc gates the force-include on `-x assembler`, but a .S file needs no
 * -x to be assembled: clang preprocesses it and assembles the result, so the
 * shim still arrived at every .S input and the C declarations below were fed to
 * the assembler:
 *   sys/_types/_int8_t.h:30:16: error: unexpected token in argument list
 *   typedef signed char int8_t;
 * __ASSEMBLER__ is defined by clang exactly in those runs, so the shim steps
 * aside on its own. The size macro stays visible: it is a plain integer and
 * some .S inputs may consult it, while the C types below are only ever needed
 * by .c inputs (Kernel/xnu/libsyscall/wrappers/_libkernel_init.h).
 */
#ifndef __ASSEMBLER__

/*
 * message.h defines mach_msg_aux_header_t itself inside `#if PRIVATE` (605-631),
 * so a TU compiled with -DPRIVATE already has the type by the time message.h is
 * reached. The force-include gate only inspects the SDK copy at `#if PRIVATE`
 * depth 0, so it still hands this shim to those TUs; defer to message.h here or
 * the two typedefs collide:
 *   ravynos-mach-compat.h:72: error: typedef redefinition with different types
 *     ('struct mach_msg_aux_header' vs 'struct mach_msg_aux_header_t')
 * (message.h's is an anonymous struct, so there is no tag to test against.)
 */
#if !PRIVATE

#include <stdint.h>
#include <mach/mach_types.h>     /* mach_msg_size_t */

struct mach_msg_aux_header {
	mach_msg_size_t   msgdh_size;
	uint32_t          msgdh_reserved;
};

typedef struct mach_msg_aux_header mach_msg_aux_header_t;

#endif /* !PRIVATE */

#endif /* !__ASSEMBLER__ */


#endif /* RAVYNOS_MACH_COMPAT_H */
