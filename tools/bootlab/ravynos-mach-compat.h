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

#include <stdint.h>
#include <mach/mach_types.h>     /* mach_msg_size_t */

#ifndef LIBSYSCALL_MSGV_AUX_MAX_SIZE
#define LIBSYSCALL_MSGV_AUX_MAX_SIZE 128
#endif

struct mach_msg_aux_header {
	mach_msg_size_t   msgdh_size;
	uint32_t          msgdh_reserved;
};

typedef struct mach_msg_aux_header mach_msg_aux_header_t;


#endif /* RAVYNOS_MACH_COMPAT_H */
