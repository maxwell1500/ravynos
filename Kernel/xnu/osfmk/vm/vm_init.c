/*
 * Copyright (c) 2000-2020 Apple Inc. All rights reserved.
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
 * Copyright (c) 1991,1990,1989,1988,1987 Carnegie Mellon University
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
 *	File:	vm/vm_init.c
 *	Author:	Avadis Tevanian, Jr., Michael Wayne Young
 *	Date:	1985
 *
 *	Initialize the Virtual Memory subsystem.
 */

#include <mach/machine/vm_types.h>
#include <mach/vm_map.h>
#include <kern/startup.h>
#include <kern/zalloc_internal.h>
#include <kern/kext_alloc.h>
#include <sys/kdebug.h>
#include <vm/vm_object_internal.h>
#include <vm/vm_map_internal.h>
#include <vm/vm_page_internal.h>
#include <vm/vm_kern.h>
#include <vm/memory_object.h>
#include <vm/vm_fault_xnu.h>
#include <vm/vm_init_xnu.h>

#include <pexpert/pexpert.h>

#include <vm/vm_protos.h>

const vm_offset_t vm_min_kernel_address = VM_MIN_KERNEL_AND_KEXT_ADDRESS;
const vm_offset_t vm_max_kernel_address = VM_MAX_KERNEL_ADDRESS;

TUNABLE(bool, iokit_iomd_setownership_enabled,
    "iokit_iomd_setownership_enabled", true);

static inline void
vm_mem_bootstrap_log(const char *message)
{
//	kprintf("vm_mem_bootstrap: %s\n", message);
	kernel_debug_string_early(message);
}

/*
 *	vm_mem_bootstrap initializes the virtual memory system.
 *	This is done only by the first cpu up.
 */
__startup_func
void
vm_mem_bootstrap(void)
{
	vm_offset_t start, end;

	/*
	 *	Initializes resident memory structures.
	 *	From here on, all physical memory is accounted for,
	 *	and we use only virtual addresses.
	 */
	extern void pal_serial_putc(char);
	const char *vmb1 = "  vm_mem_bootstrap: calling vm_page_bootstrap...\r\n";
	while (*vmb1) { pal_serial_putc(*vmb1++); }

	vm_page_bootstrap(&start, &end);

	const char *vmb2 = "  vm_mem_bootstrap: calling zone_bootstrap...\r\n";
	while (*vmb2) { pal_serial_putc(*vmb2++); }

	zone_bootstrap();

	const char *vmb3 = "  vm_mem_bootstrap: calling vm_object_bootstrap...\r\n";
	while (*vmb3) { pal_serial_putc(*vmb3++); }

	vm_object_bootstrap();

	const char *vmb4 = "  vm_mem_bootstrap: calling vm_retire_boot_pages...\r\n";
	while (*vmb4) { pal_serial_putc(*vmb4++); }

	vm_retire_boot_pages();

	const char *vmb5 = "  vm_mem_bootstrap: calling vm_map_init...\r\n";
	while (*vmb5) { pal_serial_putc(*vmb5++); }

	vm_map_init();

	const char *vmb6 = "  vm_mem_bootstrap: calling kmem_init...\r\n";
	while (*vmb6) { pal_serial_putc(*vmb6++); }

	kmem_init(start, end);

	const char *vmb7 = "  vm_mem_bootstrap: initializing STARTUP_SUB_KMEM...\r\n";
	while (*vmb7) { pal_serial_putc(*vmb7++); }

	kernel_startup_initialize_upto(STARTUP_SUB_KMEM);

	const char *vmb8 = "  vm_mem_bootstrap: calling vm_fault_init...\r\n";
	while (*vmb8) { pal_serial_putc(*vmb8++); }

	vm_fault_init();

	const char *vmb9 = "  vm_mem_bootstrap: initializing STARTUP_SUB_ZALLOC...\r\n";
	while (*vmb9) { pal_serial_putc(*vmb9++); }

	kernel_startup_initialize_upto(STARTUP_SUB_ZALLOC);

	const char *vmb10 = "  vm_mem_bootstrap: vm_init completed!\r\n";
	while (*vmb10) { pal_serial_putc(*vmb10++); }
}
