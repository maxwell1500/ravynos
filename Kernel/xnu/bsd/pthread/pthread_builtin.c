/*
 * Built-in pthread function table.
 *
 * The pthread kext (Kernel/Extensions/pthread, com.apple.kec.pthread) used to
 * be loaded with kxld.  ravynOS does not bring up external kext loading, so
 * kern_support.c and kern_synch.c from that kext are compiled straight into
 * the kernel (see tools/bootlab/kernel_build.py) and this file publishes the
 * struct pthread_functions_s that bsd/pthread/pthread_shims.c hands to them.
 *
 * Before that port this file carried panic stubs for every bsdthread, psynch
 * and workqueue entry point, so the first pthread_create() in userspace died
 * with "pthread facility pthread_builtin_bsdthread_create not built into this
 * kernel".  The stubs are gone; the table below points at the real kext code.
 *
 * kern_init.c is deliberately NOT compiled: it defines pthread_kern (which
 * pthread_shims.c already owns) and the kxld-only pthread_start/pthread_stop
 * entry points.  This file is the registrar in its place.
 *
 * pthread_builtin_register() is called by pthread_shims.c during bsd_init and
 * simply installs the table, so the kernel core never sees a NULL
 * pthread_functions.
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

/*
 * The real pthread implementation, compiled from
 * Kernel/Extensions/pthread/{kern_support.c,kern_synch.c}.  These are the
 * symbols its own kern_init.c would have published in
 * pthread_internal_functions; declaring them here keeps that file - which
 * cannot be linked, see above - out of the build.
 */
extern void _pthread_init(void);
extern void _pth_proc_hashinit(proc_t p);
extern void _pth_proc_hashdelete(proc_t p);

extern int _bsdthread_create(struct proc *p, user_addr_t user_func,
    user_addr_t user_funcarg, user_addr_t user_stack, user_addr_t user_pthread,
    uint32_t flags, user_addr_t *retval);
extern int _bsdthread_register(struct proc *p, user_addr_t threadstart,
    user_addr_t wqthread, int pthsize, user_addr_t dummy_value,
    user_addr_t targetconc_ptr, uint64_t dispatchqueue_offset, int32_t *retval);
extern int _bsdthread_terminate(struct proc *p, user_addr_t stackaddr,
    size_t size, uint32_t kthport, uint32_t sem, int32_t *retval);
extern int _thread_selfid(struct proc *p, uint64_t *retval);

extern int _psynch_mutexwait(proc_t p, user_addr_t mutex, uint32_t mgen,
    uint32_t ugen, uint64_t tid, uint32_t flags, uint32_t *retval);
extern int _psynch_mutexdrop(proc_t p, user_addr_t mutex, uint32_t mgen,
    uint32_t ugen, uint64_t tid, uint32_t flags, uint32_t *retval);
extern int _psynch_cvbroad(proc_t p, user_addr_t cv, uint64_t cvlsgen,
    uint64_t cvudgen, uint32_t flags, user_addr_t mutex, uint64_t mugen,
    uint64_t tid, uint32_t *retval);
extern int _psynch_cvsignal(proc_t p, user_addr_t cv, uint64_t cvlsgen,
    uint32_t cvugen, int thread_port, user_addr_t mutex, uint64_t mugen,
    uint64_t tid, uint32_t flags, uint32_t *retval);
extern int _psynch_cvwait(proc_t p, user_addr_t cv, uint64_t cvlsgen,
    uint32_t cvugen, user_addr_t mutex, uint64_t mugen, uint32_t flags,
    int64_t sec, uint32_t nsec, uint32_t *retval);
extern int _psynch_cvclrprepost(proc_t p, user_addr_t cv, uint32_t cvgen,
    uint32_t cvugen, uint32_t cvsgen, uint32_t prepocnt, uint32_t preposeq,
    uint32_t flags, int *retval);
extern int _psynch_rw_longrdlock(proc_t p, user_addr_t rwlock, uint32_t lgenval,
    uint32_t ugenval, uint32_t rw_wc, int flags, uint32_t *retval);
extern int _psynch_rw_rdlock(proc_t p, user_addr_t rwlock, uint32_t lgenval,
    uint32_t ugenval, uint32_t rw_wc, int flags, uint32_t *retval);
extern int _psynch_rw_unlock(proc_t p, user_addr_t rwlock, uint32_t lgenval,
    uint32_t ugenval, uint32_t rw_wc, int flags, uint32_t *retval);
extern int _psynch_rw_wrlock(proc_t p, user_addr_t rwlock, uint32_t lgenval,
    uint32_t ugenval, uint32_t rw_wc, int flags, uint32_t *retval);
extern int _psynch_rw_yieldwrlock(proc_t p, user_addr_t rwlock, uint32_t lgenval,
    uint32_t ugenval, uint32_t rw_wc, int flags, uint32_t *retval);

extern void _pthread_find_owner(thread_t thread,
    struct stackshot_thread_waitinfo *waitinfo);
extern void *_pthread_get_thread_kwq(thread_t thread);

extern int workq_handle_stack_events(proc_t p, thread_t th, vm_map_t map,
    user_addr_t stackaddr, mach_port_name_t kport, user_addr_t events,
    int nevents, int upcall_flags);
extern int workq_create_threadstack(proc_t p, vm_map_t vmap,
    mach_vm_offset_t *out_addr);
extern int workq_destroy_threadstack(proc_t p, vm_map_t vmap,
    mach_vm_offset_t stackaddr);
extern void workq_setup_thread(proc_t p, thread_t th, vm_map_t map,
    user_addr_t stackaddr, mach_port_name_t kport, int th_qos, int setup_flags,
    int upcall_flags);
extern void workq_markfree_threadstack(proc_t p, thread_t th, vm_map_t map,
    user_addr_t stackaddr);

/*
 * bsdthread_register2 is the syscall 366 entry point the shim
 * (bsd/pthread/pthread_shims.c) calls whenever the table reports version
 * >= 1, which is every boot now that this table is the one installed.  The
 * slot only exists because the 2012 kext predates it; the work behind it is
 * exactly the work _bsdthread_register() in kern_support.c does, so this
 * forwards there instead of reimplementing it.
 *
 * The previous stub stored four proc fields and returned.  It never called
 * proc_setregister(), so P_LREGISTER stayed clear for every process, and
 * _bsdthread_create() (Kernel/Extensions/pthread/kern_support.c:272) rejects
 * an unregistered process with EINVAL -- which is why the first
 * pthread_create() in launchd died.  It also copied the registration-data
 * pointer straight into p_stack_addr_hint and the kernel's garbage seventh
 * syscall argument into p_pth_tsd_offset; _bsdthread_register() copyin()s the
 * struct, clamps tsd_offset against pthsize, computes the real stack hint,
 * and copies the reply back out.
 *
 * ARGUMENTS.  ravynOS's libsystem_pthread calls bsdthread_register with the
 * six-argument form
 *
 *	(threadstart, wqthread, pthsize, pthread_init_data,
 *	 pthread_init_data_size, dispatchqueue_offset)
 *
 * while syscalls.master declares the seven-field argument struct
 * (threadstart, wqthread, flags, stack_addr_hint, targetconc_ptr,
 * dispatchqueue_offset, tsd_offset).  Userspace fills fields 3-6 with the
 * values above, positionally, and never writes the seventh -- unix_syscall64
 * copyin()s that one from the syscall's return address, so it is not an
 * argument at all.  The shim forwards the fields in order, which is why this
 * signature takes them in the order above and drops the last.
 */
static int
pthread_builtin_bsdthread_register2(struct proc *p,
    user_addr_t threadstart, user_addr_t wqthread,
    uint32_t pthsize, user_addr_t pthread_init_data,
    user_addr_t pthread_init_data_size, uint32_t dispatchqueue_offset,
    __unused uint32_t tsd_offset, int32_t *retval)
{
	return _bsdthread_register(p, threadstart, wqthread, (int)pthsize,
	    pthread_init_data, pthread_init_data_size, dispatchqueue_offset,
	    retval);
}

const struct pthread_functions_s pthread_builtin_functions = {
	.version = PTHREAD_FUNCTIONS_TABLE_VERSION,
	/*
	 * _pthread_init also brings up what the psynch layer needs to exist at
	 * all: the "pthread" lock group, the global pthread hash, the psynch
	 * thread_call and the ksyn zones.  The proc-hash lifecycle must come
	 * from the same object, since _pth_proc_hashinit's hashinit() mask is
	 * what _pth_proc_hashdelete's hashdestroy() has to be given back.
	 */
	.pthread_init = _pthread_init,
	.pth_proc_hashinit = _pth_proc_hashinit,
	.pth_proc_hashdelete = _pth_proc_hashdelete,
	.bsdthread_create = _bsdthread_create,
	.bsdthread_register = _bsdthread_register,
	.bsdthread_register2 = pthread_builtin_bsdthread_register2,
	.bsdthread_terminate = _bsdthread_terminate,
	.thread_selfid = _thread_selfid,
	.psynch_mutexwait = _psynch_mutexwait,
	.psynch_mutexdrop = _psynch_mutexdrop,
	.psynch_cvbroad = _psynch_cvbroad,
	.psynch_cvsignal = _psynch_cvsignal,
	.psynch_cvwait = _psynch_cvwait,
	.psynch_cvclrprepost = _psynch_cvclrprepost,
	.psynch_rw_longrdlock = _psynch_rw_longrdlock,
	.psynch_rw_rdlock = _psynch_rw_rdlock,
	.psynch_rw_unlock = _psynch_rw_unlock,
	.psynch_rw_wrlock = _psynch_rw_wrlock,
	.psynch_rw_yieldwrlock = _psynch_rw_yieldwrlock,
	.pthread_find_owner = _pthread_find_owner,
	.pthread_get_thread_kwq = _pthread_get_thread_kwq,
	.workq_handle_stack_events = workq_handle_stack_events,
	.workq_create_threadstack = workq_create_threadstack,
	.workq_destroy_threadstack = workq_destroy_threadstack,
	.workq_setup_thread = workq_setup_thread,
	.workq_markfree_threadstack = workq_markfree_threadstack,
};

/*
 * Stand-in for pthread_kext_register: publish the built-in table.  Called by
 * pthread_shims.c from bsd_init before any pthread syscall can arrive.
 */
void
pthread_builtin_register(void)
{
	if (pthread_functions != NULL) {
		panic("pthread_builtin_register: pthread table already registered");
	}

	pthread_functions = &pthread_builtin_functions;
}
