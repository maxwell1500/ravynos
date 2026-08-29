/*
 * Kernel shim: redirect libdispatch's os/internal/atomic.h to the kernel's
 * os/atomic_private.h, then provide the "2o" field-accessor macro wrappers
 * that firehose_buffer.c uses when compiled under KERNEL.
 *
 * The "2o" suffix means "struct-field pointer" — they expand &(p)->f and
 * delegate to the base os_atomic_* macros from the kernel's atomic_private.h.
 */
#ifndef __OS_INTERNAL_ATOMIC_H__
#define __OS_INTERNAL_ATOMIC_H__

#include <os/atomic_private.h>

/* Field-pointer (2o) wrappers used by firehose_buffer.c in KERNEL mode */
#define os_atomic_load2o(p, f, m)              os_atomic_load(&(p)->f, m)
#define os_atomic_store2o(p, f, v, m)          os_atomic_store(&(p)->f, (v), m)
#define os_atomic_xchg2o(p, f, v, m)           os_atomic_xchg(&(p)->f, (v), m)
#define os_atomic_cmpxchg2o(p, f, e, v, m)     os_atomic_cmpxchg(&(p)->f, (e), (v), m)
#define os_atomic_cmpxchgv2o(p, f, e, v, g, m) os_atomic_cmpxchgv(&(p)->f, (e), (v), (g), m)
/* os_atomic_cmpxchgvw: weak CAS — kernel has no weak variant, alias to strong */
#define os_atomic_cmpxchgvw(p, e, v, g, m)     os_atomic_cmpxchgv(p, e, v, g, m)
#define os_atomic_cmpxchgvw2o(p, f, e, v, g, m) os_atomic_cmpxchgv(&(p)->f, (e), (v), (g), m)
#define os_atomic_add2o(p, f, v, m)            os_atomic_add(&(p)->f, (v), m)
#define os_atomic_add_orig2o(p, f, v, m)       os_atomic_add_orig(&(p)->f, (v), m)
#define os_atomic_sub2o(p, f, v, m)            os_atomic_sub(&(p)->f, (v), m)
#define os_atomic_sub_orig2o(p, f, v, m)       os_atomic_sub_orig(&(p)->f, (v), m)
#define os_atomic_and2o(p, f, v, m)            os_atomic_and(&(p)->f, (v), m)
#define os_atomic_and_orig2o(p, f, v, m)       os_atomic_and_orig(&(p)->f, (v), m)
#define os_atomic_or2o(p, f, v, m)             os_atomic_or(&(p)->f, (v), m)
#define os_atomic_or_orig2o(p, f, v, m)        os_atomic_or_orig(&(p)->f, (v), m)
#define os_atomic_xor2o(p, f, v, m)            os_atomic_xor(&(p)->f, (v), m)
#define os_atomic_xor_orig2o(p, f, v, m)       os_atomic_xor_orig(&(p)->f, (v), m)
#define os_atomic_inc2o(p, f, m)               os_atomic_add2o(p, f, 1, m)
#define os_atomic_inc_orig2o(p, f, m)          os_atomic_add_orig2o(p, f, 1, m)
#define os_atomic_dec2o(p, f, m)               os_atomic_sub2o(p, f, 1, m)
#define os_atomic_dec_orig2o(p, f, m)          os_atomic_sub_orig2o(p, f, 1, m)
#define os_atomic_rmw_loop2o(p, f, ov, nv, m, ...) \
		os_atomic_rmw_loop(&(p)->f, ov, nv, m, __VA_ARGS__)
#define os_atomic_load_with_dependency_on2o(p, f, e) \
		os_atomic_load(&(p)->f, relaxed)

/* Thread fence */
#ifndef os_atomic_thread_fence
#define os_atomic_thread_fence(m)  atomic_thread_fence(memory_order_##m)
#endif

/* _os_atomic_basetypeof used by firehose_inline_internal.h */
#ifndef _os_atomic_basetypeof
#define _os_atomic_basetypeof(p) \
		__typeof__(atomic_load_explicit(_os_atomic_c11_atomic(p), memory_order_relaxed))
#endif

#endif /* __OS_INTERNAL_ATOMIC_H__ */
