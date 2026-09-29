/*
 * Copyright (c) 2000-2018 Apple Inc. All rights reserved.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. The rights granted to you under the License
 * may not be used to create, or enable the creation or redistribution of,
 * unlawful or unlicensed copies of an Apple operating system, or to
 * circumvent, violate, or enable the circumvention or violation of, any
 * terms of an Apple operating system software license agreement.
 *
 * Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_OSREFERENCE_LICENSE_HEADER_END@
 */
/*
 * @OSF_COPYRIGHT@
 */
/*
 * Mach Operating System
 * Copyright (c) 1991,1990,1989,1988 Carnegie Mellon University
 * All Rights Reserved.
 *
 * Permission to use, copy, modify and distribute this software and its
 * documentation is hereby granted, provided that both the copyright
 * notice and this permission notice appear in all copies of the
 * software, derivative works or modified versions, and any portions
 * thereof, and that both notices appear in supporting documentation.
 *
 * CARNEGIE MELLON ALLOWS FREE USE OF THIS SOFTWARE IN ITS "AS IS"
 * CONDITION.  CARNEGIE MELLON DISCLAIMS ANY LIABILITY OF ANY KIND FOR
 * ANY DAMAGES WHATSOEVER RESULTING FROM THE USE OF THIS SOFTWARE.
 *
 * Carnegie Mellon requests users of this software to return to
 *
 *  Software Distribution Coordinator  or  Software.Distribution@CS.CMU.EDU
 *  School of Computer Science
 *  Carnegie Mellon University
 *  Pittsburgh PA 15213-3890
 *
 * any improvements or extensions that they make and grant Carnegie Mellon
 * the rights to redistribute these changes.
 */
/*
 */
/*
 * NOTICE: This file was modified by SPARTA, Inc. in 2005 to introduce
 * support for mandatory and extensible security protections.  This notice
 * is included in support of clause 2.2 (b) of the Apple Public License,
 * Version 2.0.
 */
/*
 *	File:	mach/mach_types.h
 *	Author:	Avadis Tevanian, Jr., Michael Wayne Young
 *	Date:	1986
 *
 *	Mach external interface definitions.
 *
 */

#ifndef _MACH_MACH_TYPES_H_
#define _MACH_MACH_TYPES_H_

#include <stdint.h>

#include <sys/cdefs.h>

#include <mach/host_info.h>
#include <mach/host_notify.h>
#include <mach/host_special_ports.h>
#include <mach/machine.h>
#include <mach/machine/vm_types.h>
#include <mach/memory_object_types.h>
#include <mach/message.h>
#include <mach/exception_types.h>
#include <mach/port.h>
#include <mach/mach_voucher_types.h>
#include <mach/processor_info.h>
#include <mach/task_info.h>
#include <mach/task_inspect.h>
#include <mach/task_policy.h>
#include <mach/task_special_ports.h>
#include <mach/thread_info.h>
#include <mach/thread_policy.h>
#include <mach/thread_special_ports.h>
#include <mach/thread_status.h>
#include <mach/time_value.h>
#include <mach/clock_types.h>
#include <mach/vm_attributes.h>
#include <mach/vm_inherit.h>
#include <mach/vm_purgable.h>
#include <mach/vm_behavior.h>
#include <mach/vm_prot.h>
#include <mach/vm_statistics.h>
#include <mach/vm_sync.h>
#include <mach/vm_types.h>
#include <mach/vm_region.h>
#include <mach/kmod.h>
#include <mach/dyld_kernel.h>


/*
 * If we are not in the kernel, then these will all be represented by
 * ports at user-space.
 */
typedef mach_port_t             task_t;
typedef mach_port_t             task_name_t;
typedef mach_port_t             task_inspect_t;
typedef mach_port_t             task_suspension_token_t;
typedef mach_port_t             thread_t;
typedef mach_port_t             thread_act_t;
typedef mach_port_t             thread_inspect_t;
typedef mach_port_t             ipc_space_t;
typedef mach_port_t             ipc_space_inspect_t;
typedef mach_port_t             coalition_t;
typedef mach_port_t             host_t;
typedef mach_port_t             host_priv_t;
typedef mach_port_t             host_security_t;
typedef mach_port_t             processor_t;
typedef mach_port_t             processor_set_t;
typedef mach_port_t             processor_set_control_t;
typedef mach_port_t             semaphore_t;
typedef mach_port_t             lock_set_t;
typedef mach_port_t             ledger_t;
typedef mach_port_t             alarm_t;
typedef mach_port_t             clock_serv_t;
typedef mach_port_t             clock_ctrl_t;
typedef mach_port_t             arcade_register_t;
typedef mach_port_t             suid_cred_t;


/*
 * These aren't really unique types.  They are just called
 * out as unique types at one point in history.  So we list
 * them here for compatibility.
 */
typedef processor_set_t         processor_set_name_t;

/*
 * These types are just hard-coded as ports
 */
typedef mach_port_t             clock_reply_t;
typedef mach_port_t             bootstrap_t;
typedef mach_port_t             mem_entry_name_port_t;
typedef mach_port_t             exception_handler_t;
typedef exception_handler_t     *exception_handler_array_t;
typedef mach_port_t             vm_task_entry_t;
typedef mach_port_t             io_master_t;
/* SOURCED from Kernel/xnu/osfmk/mach/mach_types.h:227, verbatim. ADDITIVE:
 * io_master_t above is left exactly as it was.
 *
 * xnu-11215 renamed io_master_t to io_main_t along with the Mach trap
 * host_get_io_master -> host_get_io_main. It is a rename, not a new type:
 * both are `typedef mach_port_t`, and this is the generation our own kernel
 * is built from (see tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 22).
 * libsyscall/mach/host.c:113-124 needs the newer spelling:
 *     /* compatibility symbol for IOKit_sim *\/
 *     host_get_io_master(host_t host, io_main_t *io_main)
 *         { return host_get_io_main(host, io_main); }
 */
typedef mach_port_t             io_main_t;

/* SOURCED from Kernel/xnu/osfmk/mach/mach_types.h:186, verbatim. ADDITIVE:
 * nothing above is replaced or removed. Same class as the io_main_t addition
 * above -- a typedef of an existing type, not a layout.
 *
 * thread_act_internal.h (mig-generated, userspace) uses thread_read_t, and the
 * SDK's Catalina mach_types.h has no such typedef. The userspace spelling at
 * :186 is the one sourced here; the KERNEL spelling at :123 is a different
 * declaration of the same name and does not apply to a userspace build.
 * See tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 33.
 */
typedef mach_port_t             thread_read_t;

/* SOURCED from Kernel/xnu/osfmk/mach/mach_types.h, verbatim, ADDITIVE. The
 * whole mach_port_t family in that header was checked member by member; these
 * two were the only ones the SDK lacked:
 *
 *   :181  typedef mach_port_t             task_read_t;      <- SDK: absent
 *   :188  typedef mach_port_t             ipc_space_read_t; <- SDK: absent
 *
 * The other eight (task_inspect_t, task_suspension_token_t, thread_inspect_t,
 * thread_read_t, ipc_space_t, ipc_space_inspect_t, coalition_t, io_main_t) are
 * all already present and were left alone. That check is the point: this is a
 * family, and sourcing it member by member by iterating on compiler errors is
 * what made the earlier rounds report "15 symbols" when the real answer needed
 * a per-header enumeration.
 *
 * Both are typedefs of mach_port_t. No struct, no layout, nothing that can
 * mis-size. See tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 33.
 */
typedef mach_port_t             task_read_t;
typedef mach_port_t             ipc_space_read_t;


/* SOURCED from Kernel/xnu/osfmk/mach/mach_types.h:231, verbatim. ADDITIVE.
 *
 * thread_act_internal.h (mig-generated, userspace) needs
 * exception_handler_info_t; no SDK mach_types.h declares it.
 *
 * Only this one typedef is missing. The type it names is NOT: the SDK's own
 * mach_debug/ipc_info.h:116-119 already declares the identical struct
 *
 *     typedef struct ipc_info_port {
 *             natural_t iip_port_object;
 *             natural_t iip_receiver_object;
 *     } ipc_info_port_t;
 *
 * and line 121 already declares exception_handler_info_array_t. An earlier
 * attempt of mine re-copied all three and died with
 * "redefinition of 'ipc_info_port'" -- the SDK had them the whole time. Copying
 * a struct that already exists verbatim is a redefinition, not a fix. Only the
 * alias was ever missing.
 *
 * MIG encodes both types as POINTER descriptors (thread_act_internal.h:473 and
 * :1358), so userspace passes an exception_handler_info_t* and the kernel
 * fills it; the body is never marshalled here.
 * See tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 33.
 */
/* ipc_info_port_t is declared by the SDK's own mach_debug/ipc_info.h:116-119,
 * which this file does not include. Reference the real definition rather than
 * copy it -- a verbatim copy of a struct that already exists is a
 * redefinition, not a fix. The include is self-contained: ipc_info.h needs
 * only natural_t and mach_port_name_t, both of which are already in scope
 * here.
 */
#include <mach_debug/ipc_info.h>
typedef ipc_info_port_t         exception_handler_info_t;


typedef mach_port_t             UNDServerRef;

/*
 * Mig doesn't translate the components of an array.
 * For example, Mig won't use the thread_t translations
 * to translate a thread_array_t argument.  So, these definitions
 * are not completely accurate at the moment for other kernel
 * components.
 */
typedef task_t                  *task_array_t;
typedef thread_t                *thread_array_t;
typedef processor_set_t         *processor_set_array_t;
typedef processor_set_t         *processor_set_name_array_t;
typedef processor_t             *processor_array_t;
typedef thread_act_t            *thread_act_array_t;
typedef ledger_t                *ledger_array_t;

/*
 * However the real mach_types got declared, we also have to declare
 * types with "port" in the name for compatability with the way OSF
 * had declared the user interfaces at one point.  Someday these should
 * go away.
 */
typedef task_t                  task_port_t;
typedef task_array_t            task_port_array_t;
typedef thread_t                thread_port_t;
typedef thread_array_t          thread_port_array_t;
typedef ipc_space_t             ipc_space_port_t;
typedef host_t                  host_name_t;
typedef host_t                  host_name_port_t;
typedef processor_set_t         processor_set_port_t;
typedef processor_set_t         processor_set_name_port_t;
typedef processor_set_array_t   processor_set_name_port_array_t;
typedef processor_set_t         processor_set_control_port_t;
typedef processor_t             processor_port_t;
typedef processor_array_t       processor_port_array_t;
typedef thread_act_t            thread_act_port_t;
typedef thread_act_array_t      thread_act_port_array_t;
typedef semaphore_t             semaphore_port_t;
typedef lock_set_t              lock_set_port_t;
typedef ledger_t                ledger_port_t;
typedef ledger_array_t          ledger_port_array_t;
typedef alarm_t                 alarm_port_t;
typedef clock_serv_t            clock_serv_port_t;
typedef clock_ctrl_t            clock_ctrl_port_t;
typedef exception_handler_t     exception_port_t;
typedef exception_handler_array_t exception_port_arrary_t;
typedef char vfs_path_t[4096];
typedef char nspace_path_t[1024]; /* 1024 == PATH_MAX */
typedef char suid_cred_path_t[1024];
typedef uint32_t suid_cred_uid_t;

#define TASK_NULL               ((task_t) 0)
#define TASK_NAME_NULL          ((task_name_t) 0)
#define TASK_INSPECT_NULL               ((task_inspect_t) 0)
#define THREAD_NULL             ((thread_t) 0)
#define THREAD_INSPECT_NULL     ((thread_inspect_t) 0)
#define TID_NULL                ((uint64_t) 0)
#define THR_ACT_NULL            ((thread_act_t) 0)
#define IPC_SPACE_NULL          ((ipc_space_t) 0)
#define IPC_SPACE_INSPECT_NULL  ((ipc_space_inspect_t) 0)
#define COALITION_NULL          ((coalition_t) 0)
#define HOST_NULL               ((host_t) 0)
#define HOST_PRIV_NULL          ((host_priv_t) 0)
#define HOST_SECURITY_NULL      ((host_security_t) 0)
#define PROCESSOR_SET_NULL      ((processor_set_t) 0)
#define PROCESSOR_NULL          ((processor_t) 0)
#define SEMAPHORE_NULL          ((semaphore_t) 0)
#define LOCK_SET_NULL           ((lock_set_t) 0)
#define LEDGER_NULL             ((ledger_t) 0)
#define ALARM_NULL              ((alarm_t) 0)
#define CLOCK_NULL              ((clock_t) 0)
#define UND_SERVER_NULL         ((UNDServerRef) 0)
#define ARCADE_REG_NULL         ((arcade_register_t) 0)
#define SUID_CRED_NULL         ((suid_cred_t) 0)

/* DEPRECATED */
typedef natural_t       ledger_item_t;
#define LEDGER_ITEM_INFINITY    ((ledger_item_t) (~0))

typedef int64_t                 ledger_amount_t;
#define LEDGER_LIMIT_INFINITY   ((ledger_amount_t)((1ULL << 63) - 1))

typedef mach_vm_offset_t        *emulation_vector_t;
typedef char                    *user_subsystem_t;

typedef char                    *labelstr_t;
/*
 *	Backwards compatibility, for those programs written
 *	before mach/{std,mach}_types.{defs,h} were set up.
 */
#include <mach/std_types.h>


/* SOURCED verbatim from Kernel/xnu/osfmk/mach/mach_types.h, ADDITIVE. These
 * are the remaining mach_port_t typedefs of that header with no SDK
 * counterpart, enumerated member by member rather than found one error at a
 * time:
 *   :178 task_policy_set_t      :204 ipc_eventlink_t
 *   :179 task_policy_get_t      :206 task_id_token_t
 *                              :207 kcdata_object_t
 *                              :229 mach_eventlink_t
 * (the :205 `eventlink_port_pair_t[2]` line is an array declarator, not a
 * typedef, and is not needed by libsyscall)
 * See tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 33.
 */
typedef mach_port_t             task_policy_set_t;
typedef mach_port_t             task_policy_get_t;
typedef mach_port_t             ipc_eventlink_t;
typedef mach_port_t             task_id_token_t;
typedef mach_port_t             kcdata_object_t;
typedef mach_port_t             mach_eventlink_t;


/* SOURCED from Kernel/xnu/osfmk/mach/mach_types.h:205, verbatim. ADDITIVE.
 *
 * typedef mach_port_t eventlink_port_pair_t[2];
 *
 * I previously recorded this line as "an array declarator, not a typedef, and
 * not needed by libsyscall" and left it out. That was WRONG, and it is worth
 * recording because the error is the same one sec. 17 warns about: my census
 * matched typedefs with a regex that could not see an array typedef, so it
 * reported a clean family that was not clean. The consumer is the
 * mig-generated mach_eventlink.h:84 and mach_eventlinkUser.c:185:
 *
 *   error: unknown type name 'eventlink_port_pair_t'
 *
 * A method that cannot see a form of the declaration cannot certify that the
 * form is absent. Grep the bare NAME, never the declaration shape.
 */
typedef mach_port_t             eventlink_port_pair_t[2];


/* SOURCED from Kernel/xnu/osfmk/mach/mach_types.h:362, verbatim. ADDITIVE.
 *
 *   typedef unsigned int mach_task_flavor_t;
 *
 * Needed by the mig-generated processor_set.h:216/:364 and
 * processor_setUser.c:1765/:1777. isysroot-cc's overlay_for already records
 * this exact error at its line 204, as the reason it strips mach/ from the
 * libsystem_kernel mig_hdr overlay -- so it is a known, named gap rather than
 * a new one. The stripping hides the generated processor_set.h; the raw
 * -I.../mig_hdr/include/mach on CFLAGS is not stripped, so the type is needed
 * either way.
 */
typedef unsigned int            mach_task_flavor_t;

/* SOURCED from Apple's own mach/task_info.h, verbatim. ADDITIVE.
 *
 *   typedef uint32_t task_corpse_forking_behavior_t;
 *
 * Two independent copies agree byte for byte: the host Command Line Tools SDK
 * at .../MacOSX.sdk/usr/include/mach/task_info.h:551, and this SDK's own
 * System/Library/Frameworks/Kernel.framework/Versions/A/Headers/mach/
 * task_info.h:531. It agrees with the .defs that drives the code, which is
 * mach_types.defs:349 `type task_corpse_forking_behavior_t = uint32_t;`.
 *
 * It is NOT in Kernel/xnu/osfmk/mach/mach_types.h, so this one cannot be
 * sourced from the in-tree generation -- there is nothing there to copy. It is
 * a real Apple header line in both SDKs, which is the same standard the
 * asm_help.h restoration met (LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 8).
 *
 * Needed by the mig-generated task.h:905/:1757 and taskUser.c:10056/:10066,
 * both the public and the internal pass:
 *
 *   error: unknown type name 'task_corpse_forking_behavior_t'
 *
 * The .defs had the type and no .h did, so the generated code used a
 * declaration that existed in the interface description and in neither
 * header. Same family as the three entries above.
 */
typedef uint32_t                 task_corpse_forking_behavior_t;

#endif  /* _MACH_MACH_TYPES_H_ */
