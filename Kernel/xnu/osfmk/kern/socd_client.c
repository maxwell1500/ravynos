/*
 * Copyright (c) 2021, 2024 Apple Inc. All rights reserved.
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

#include <kern/clock.h>
#include <kern/cpu_data.h>
#include <kern/debug.h>
#include <kern/socd_client.h>
#include <kern/startup.h>
#include <os/overflow.h>
#include <os/atomic_private.h>
#include <libkern/section_keywords.h>

#define SOCD_CLIENT_HDR_VERSION 0x1

/* Configuration values mutable only at init time */
typedef struct {
	uint64_t boot_time_ns;
	vm_offset_t trace_buff_offset;
	uint32_t trace_buff_len;
} socd_client_cfg_t;

static SECURITY_READ_ONLY_LATE(socd_client_cfg_t) socd_client_cfg = {0};
static SECURITY_READ_ONLY_LATE(bool) socd_client_trace_available = false;

/* Run-time state */
static struct {
	_Atomic uint32_t trace_idx;
} socd_client_state = {0};

static void
socd_client_init(void)
{
	extern void pal_serial_putc(char);
	const char *sc1 = "    socd_client_init: checking...\r\n";
	while (*sc1) { pal_serial_putc(*sc1++); }

	vm_size_t buff_size = PE_init_socd_client();
	if (!buff_size) {
		const char *sc2 = "    socd_client_init: not supported on this platform, skipping!\r\n";
		while (*sc2) { pal_serial_putc(*sc2++); }
		return;
	}
}
STARTUP(PMAP_STEAL, 0, socd_client_init);

static void
socd_client_set_primary_kernelcache_uuid(void)
{
	long available = os_atomic_load(&socd_client_trace_available, relaxed);
	if (kernelcache_uuid_valid && available) {
		PE_write_socd_client_buffer(offsetof(socd_client_hdr_t, primary_kernelcache_uuid), &kernelcache_uuid, sizeof(kernelcache_uuid));
	}
}
STARTUP(EARLY_BOOT, 0, socd_client_set_primary_kernelcache_uuid);

void
socd_client_reinit(void)
{
	socd_client_init();
	socd_client_set_primary_kernelcache_uuid();
}

void
socd_client_trace(
	uint32_t                 debugid,
	socd_client_trace_arg_t  arg1,
	socd_client_trace_arg_t  arg2,
	socd_client_trace_arg_t  arg3,
	socd_client_trace_arg_t  arg4)
{
	socd_client_trace_entry_t entry;
	uint32_t trace_idx, buff_idx, len;
	uint64_t time_ns;
	long available;
	vm_offset_t offset;

	available = os_atomic_load(&socd_client_trace_available, dependency);
	if (__probable(available)) {
		len = os_atomic_load_with_dependency_on(&socd_client_cfg.trace_buff_len, available);
		offset = os_atomic_load_with_dependency_on(&socd_client_cfg.trace_buff_offset, available);
		/* trace_idx is allowed to overflow */
		trace_idx = os_atomic_inc_orig(&socd_client_state.trace_idx, relaxed);
		buff_idx = trace_idx % len;

		absolutetime_to_nanoseconds(mach_continuous_time(), &time_ns);
		entry.timestamp = time_ns;
		entry.debugid = debugid;
		entry.arg1 = arg1;
		entry.arg2 = arg2;
		entry.arg3 = arg3;
		entry.arg4 = arg4;
		PE_write_socd_client_buffer(offset + (buff_idx * sizeof(entry)), &entry, sizeof(entry));
	}

	/* Duplicate tracepoint to kdebug */
	if (!debug_is_current_cpu_in_panic_state()) {
		KDBG(debugid, arg1, arg2, arg3, arg4);
	}
}
