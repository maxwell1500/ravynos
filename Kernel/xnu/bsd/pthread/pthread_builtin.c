/*
 * Built-in pthread bring-up table.
 *
 * The pthread kext (Kernel/Extensions/pthread, com.apple.kec.pthread) is a
 * 2012-era code base that no longer compiles against this kernel: the
 * kernel↔kext interfaces have since moved on (several pthread_callbacks_s
 * slots it relies on are now __unused_was_* tombstones, workq/psynch entry
 * points changed shape, port_name_to_thread grew a parameter, and the
 * uthread-embedded struct ksyn_waitq_element changed size). Until that kext
 * is properly ported, kernels built without any kext collection would panic
 * in bsd_init's pthread_init() with "function table is NULL".
 *
 * This file provides the minimum in-kernel bring-up so such kernels boot:
 * a real pthread_init (lock groups, global pthread hash, mutex-policy
 * boot-arg/sysctl) plus real per-proc pthread-hash lifecycle, and explicit
 * panic stubs for every entry point that genuinely needs the kext
 * (bsdthread/psynch/workqueue). The stubs panic with a clear message naming
 * the missing facility instead of faulting on a NULL function pointer.
 *
 * What is deliberately NOT here: the kext's psynch wait-queue layer
 * (ksyn zones, psynch_thcall) and workqueue thread-stack management.
 * The core kernel owns turnstiles and the workqueue fast paths directly;
 * those kext layers have no in-kernel consumers during boot.
 */

#include <sys/param.h>
#include <sys/proc_internal.h>
#include <sys/pthread_shims.h>
#include <sys/systm.h>
#include <sys/malloc.h>
#include <sys/sysctl.h>

#include <kern/debug.h>
#include <kern/locks.h>
#include <kern/thread.h>

#include <pexpert/pexpert.h>

/* Lock group/attr state ported from the pthread kext's _pthread_init. */
static lck_grp_attr_t *pthread_builtin_grp_attr;
static lck_grp_t *pthread_builtin_grp;
static lck_attr_t *pthread_builtin_attr;
static lck_mtx_t *pthread_builtin_list_mlock;

/* Global pthread wait-queue hash (port of the kext's pth_global_hashinit). */
static void *pthread_builtin_glob_hashtbl;
static u_long pthread_builtin_glob_hashmask;
#define PTH_BUILTIN_HASHSIZE 100

/*
 * Mask for the per-proc tables. hashinit() derives the mask deterministically
 * from the element count alone, so every PTH_BUILTIN_HASHSIZE table shares
 * one mask; hashdestroy() needs it back to size the free.
 */
static u_long pthread_builtin_proc_hashmask;
static uint32_t pthread_builtin_mutex_default_policy;

SYSCTL_INT(_kern, OID_AUTO, pthread_mutex_default_policy, CTLFLAG_RW | CTLFLAG_LOCKED,
    &pthread_builtin_mutex_default_policy, 0, "");


static void
pthread_builtin_init(void)
{
	pthread_builtin_grp_attr = lck_grp_attr_alloc_init();
	pthread_builtin_grp = lck_grp_alloc_init("pthread", pthread_builtin_grp_attr);

	/*
	 * Allocate the lock attribute for pthread synchronizers.
	 */
	pthread_builtin_attr = lck_attr_alloc_init();
	pthread_builtin_list_mlock = lck_mtx_alloc_init(pthread_builtin_grp, pthread_builtin_attr);

	pthread_builtin_glob_hashtbl = hashinit(PTH_BUILTIN_HASHSIZE * 4, M_PROC,
	    &pthread_builtin_glob_hashmask);

	int policy_bootarg;
	if (PE_parse_boot_argn("pthread_mutex_default_policy", &policy_bootarg,
	    sizeof(policy_bootarg))) {
		pthread_builtin_mutex_default_policy = (uint32_t)policy_bootarg;
	}
	/*
	 * No sysctl_register_oid*() call here: SYSCTL_INT() above already
	 * arranges static registration via __STARTUP_ARG
	 * (sysctl_register_oid_early at STARTUP_RANK_SECOND). An explicit
	 * call would be a wrong-phase panic: too late for _early
	 * (startup_phase < STARTUP_SUB_SYSCTL no longer holds in bsd_init)
	 * and _oid refuses CTLFLAG_PERMANENT nodes.
	 */
}

static void
pthread_builtin_proc_hashinit(proc_t p)
{
	void *ptr = hashinit(PTH_BUILTIN_HASHSIZE, M_PCB,
	    &pthread_builtin_proc_hashmask);
	if (ptr == NULL) {
		panic("pthread_builtin_proc_hashinit: hash init returned 0\n");
	}

	p->p_pthhash = ptr;
}

static void
pthread_builtin_proc_hashdelete(proc_t p)
{
	void *hashptr = p->p_pthhash;

	p->p_pthhash = NULL;
	if (hashptr == NULL) {
		return;
	}

	hashdestroy(hashptr, M_PCB, pthread_builtin_proc_hashmask);
}

/*
 * Diagnostic hook used by stackshot. The kext answers from live psynch
 * wait queues; with no kext there is never anything to report. Report
 * "no owner" exactly as the kext does for non-owner wait types.
 */
static void
pthread_builtin_find_owner(__unused thread_t thread,
    struct stackshot_thread_waitinfo *waitinfo)
{
	waitinfo->owner = 0;
	waitinfo->context = 0;
}

static void *
pthread_builtin_get_thread_kwq(__unused thread_t thread)
{
	return NULL;
}

/* Everything below needs the real pthread kext; fail loudly if reached. */
#define PTHREAD_BUILTIN_STUB_PANIC() \
	panic("pthread facility %s not built into this kernel", __func__)

static int
pthread_builtin_bsdthread_create(__unused struct proc *p,
    __unused user_addr_t user_func, __unused user_addr_t user_funcarg,
    __unused user_addr_t user_stack, __unused user_addr_t user_pthread,
    __unused uint32_t flags, __unused user_addr_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_bsdthread_register(struct proc *p,
    user_addr_t threadstart, user_addr_t wqthread,
    int pthsize, __unused user_addr_t dummy_value,
    __unused user_addr_t targetconc_ptr,
    uint64_t dispatchqueue_offset, int32_t *retval)
{
	p->p_threadstart = threadstart;
	p->p_wqthread = wqthread;
	p->p_pthsize = pthsize;
	p->p_dispatchqueue_offset = dispatchqueue_offset;
	if (retval) {
		*retval = 0;
	}
	return 0;
}

static int
pthread_builtin_bsdthread_register2(struct proc *p,
    user_addr_t threadstart, user_addr_t wqthread,
    __unused uint32_t flags, user_addr_t stack_addr_hint,
    __unused user_addr_t targetconc_ptr,
    uint32_t dispatchqueue_offset, uint32_t tsd_offset,
    int32_t *retval)
{
	p->p_threadstart = threadstart;
	p->p_wqthread = wqthread;
	p->p_stack_addr_hint = stack_addr_hint;
	p->p_dispatchqueue_offset = dispatchqueue_offset;
	p->p_pth_tsd_offset = tsd_offset;
	if (retval) {
		*retval = 0;
	}
	return 0;
}

static int
pthread_builtin_bsdthread_terminate(__unused struct proc *p,
    __unused user_addr_t stackaddr, __unused size_t size,
    __unused uint32_t kthport, __unused uint32_t sem,
    __unused int32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_thread_selfid(__unused struct proc *p,
    uint64_t *retval)
{
	thread_t thread = current_thread();
	if (retval) {
		*retval = thread_tid(thread);
	}
	return 0;
}

static int
pthread_builtin_psynch_mutexwait(__unused proc_t p,
    __unused user_addr_t mutex, __unused uint32_t mgen,
    __unused uint32_t ugen, __unused uint64_t tid, __unused uint32_t flags,
    __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_mutexdrop(__unused proc_t p,
    __unused user_addr_t mutex, __unused uint32_t mgen,
    __unused uint32_t ugen, __unused uint64_t tid, __unused uint32_t flags,
    __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_cvbroad(__unused proc_t p, __unused user_addr_t cv,
    __unused uint64_t cvlsgen, __unused uint64_t cvudgen,
    __unused uint32_t flags, __unused user_addr_t mutex,
    __unused uint64_t mugen, __unused uint64_t tid,
    __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_cvsignal(__unused proc_t p, __unused user_addr_t cv,
    __unused uint64_t cvlsgen, __unused uint32_t cvugen,
    __unused int thread_port, __unused user_addr_t mutex,
    __unused uint64_t mugen, __unused uint64_t tid, __unused uint32_t flags,
    __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_cvwait(__unused proc_t p, __unused user_addr_t cv,
    __unused uint64_t cvlsgen, __unused uint32_t cvugen,
    __unused user_addr_t mutex, __unused uint64_t mugen,
    __unused uint32_t flags, __unused int64_t sec, __unused uint32_t nsec,
    __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_cvclrprepost(__unused proc_t p,
    __unused user_addr_t cv, __unused uint32_t cvgen,
    __unused uint32_t cvugen, __unused uint32_t cvsgen,
    __unused uint32_t prepocnt, __unused uint32_t preposeq,
    __unused uint32_t flags, __unused int *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_rw_longrdlock(__unused proc_t p,
    __unused user_addr_t rwlock, __unused uint32_t lgenval,
    __unused uint32_t ugenval, __unused uint32_t rw_wc,
    __unused int flags, __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_rw_rdlock(__unused proc_t p,
    __unused user_addr_t rwlock, __unused uint32_t lgenval,
    __unused uint32_t ugenval, __unused uint32_t rw_wc,
    __unused int flags, __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_rw_unlock(__unused proc_t p,
    __unused user_addr_t rwlock, __unused uint32_t lgenval,
    __unused uint32_t ugenval, __unused uint32_t rw_wc,
    __unused int flags, __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_rw_wrlock(__unused proc_t p,
    __unused user_addr_t rwlock, __unused uint32_t lgenval,
    __unused uint32_t ugenval, __unused uint32_t rw_wc,
    __unused int flags, __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_psynch_rw_yieldwrlock(__unused proc_t p,
    __unused user_addr_t rwlock, __unused uint32_t lgenval,
    __unused uint32_t ugenval, __unused uint32_t rw_wc,
    __unused int flags, __unused uint32_t *retval)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_workq_handle_stack_events(__unused proc_t p,
    __unused thread_t th, __unused vm_map_t map,
    __unused user_addr_t stackaddr, __unused mach_port_name_t kport,
    __unused user_addr_t events, __unused int nevents,
    __unused int upcall_flags)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_workq_create_threadstack(__unused proc_t p,
    __unused vm_map_t vmap, __unused mach_vm_offset_t *out_addr)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static int
pthread_builtin_workq_destroy_threadstack(__unused proc_t p,
    __unused vm_map_t vmap, __unused mach_vm_offset_t stackaddr)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static void
pthread_builtin_workq_setup_thread(__unused proc_t p, __unused thread_t th,
    __unused vm_map_t map, __unused user_addr_t stackaddr,
    __unused mach_port_name_t kport, __unused int th_qos,
    __unused int setup_flags, __unused int upcall_flags)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

static void
pthread_builtin_workq_markfree_threadstack(__unused proc_t p,
    __unused thread_t th, __unused vm_map_t map,
    __unused user_addr_t stackaddr)
{
	PTHREAD_BUILTIN_STUB_PANIC();
}

const struct pthread_functions_s pthread_builtin_functions = {
	.version = PTHREAD_FUNCTIONS_TABLE_VERSION,
	.pthread_init = pthread_builtin_init,
	.pth_proc_hashinit = pthread_builtin_proc_hashinit,
	.pth_proc_hashdelete = pthread_builtin_proc_hashdelete,
	.bsdthread_create = pthread_builtin_bsdthread_create,
	.bsdthread_register = pthread_builtin_bsdthread_register,
	.bsdthread_register2 = pthread_builtin_bsdthread_register2,
	.bsdthread_terminate = pthread_builtin_bsdthread_terminate,
	.thread_selfid = pthread_builtin_thread_selfid,
	.psynch_mutexwait = pthread_builtin_psynch_mutexwait,
	.psynch_mutexdrop = pthread_builtin_psynch_mutexdrop,
	.psynch_cvbroad = pthread_builtin_psynch_cvbroad,
	.psynch_cvsignal = pthread_builtin_psynch_cvsignal,
	.psynch_cvwait = pthread_builtin_psynch_cvwait,
	.psynch_cvclrprepost = pthread_builtin_psynch_cvclrprepost,
	.psynch_rw_longrdlock = pthread_builtin_psynch_rw_longrdlock,
	.psynch_rw_rdlock = pthread_builtin_psynch_rw_rdlock,
	.psynch_rw_unlock = pthread_builtin_psynch_rw_unlock,
	.psynch_rw_wrlock = pthread_builtin_psynch_rw_wrlock,
	.psynch_rw_yieldwrlock = pthread_builtin_psynch_rw_yieldwrlock,
	.pthread_find_owner = pthread_builtin_find_owner,
	.pthread_get_thread_kwq = pthread_builtin_get_thread_kwq,
	.workq_handle_stack_events = pthread_builtin_workq_handle_stack_events,
	.workq_create_threadstack = pthread_builtin_workq_create_threadstack,
	.workq_destroy_threadstack = pthread_builtin_workq_destroy_threadstack,
	.workq_setup_thread = pthread_builtin_workq_setup_thread,
	.workq_markfree_threadstack = pthread_builtin_workq_markfree_threadstack,
};

/*
 * Stand-in for pthread_kext_register: publish the built-in table.
 * If the real kext ever registers later, its pthread_kext_register
 * refuses (it panics on re-initialisation), so the two cannot silently
 * stack; the kext build must drop this file first.
 */
void
pthread_builtin_register(void)
{
	if (pthread_functions != NULL) {
		panic("pthread_builtin_register: pthread table already registered");
	}

	pthread_functions = &pthread_builtin_functions;
}
