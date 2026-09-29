/* -*- mode: C++; c-basic-offset: 4; tab-width: 4 -*-
 *
 * Copyright (c) 2004-2008 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

#define __STDC_LIMIT_MACROS
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <mach/mach.h>
#include <System/sys/event.h>

#include "dyld2.h"
#include "dyldSyscallInterface.h"
#include "MachOAnalyzer.h"
#include "Tracing.h"

// from libc.a
extern "C" void mach_init();
extern "C" void _dyld_setup_minimal_tsd();
// from libc.a -- used only by the INSTRUMENTATION print in start() below
extern "C" void _simple_dprintf(int fd, const char* fmt, ...);
extern "C" void __guard_setup(const char* apple[]);


// from dyld_debugger.cpp
extern void syncProcessInfo();

const dyld::SyscallHelpers* gSyscallHelpers = NULL;


//
//  Code to bootstrap dyld into a runnable state
//
//

namespace dyldbootstrap {


// currently dyld has no initializers, but if some come back, set this to non-zero
#define DYLD_INITIALIZER_SUPPORT  0


#if DYLD_INITIALIZER_SUPPORT

typedef void (*Initializer)(int argc, const char* argv[], const char* envp[], const char* apple[]);

extern const Initializer  inits_start  __asm("section$start$__DATA$__mod_init_func");
extern const Initializer  inits_end    __asm("section$end$__DATA$__mod_init_func");

//
// For a regular executable, the crt code calls dyld to run the executables initializers.
// For a static executable, crt directly runs the initializers.
// dyld (should be static) but is a dynamic executable and needs this hack to run its own initializers.
// We pass argc, argv, etc in case libc.a uses those arguments
//
static void runDyldInitializers(int argc, const char* argv[], const char* envp[], const char* apple[])
{
	for (const Initializer* p = &inits_start; p < &inits_end; ++p) {
		(*p)(argc, argv, envp, apple);
	}
}
#endif // DYLD_INITIALIZER_SUPPORT


//
// On disk, all pointers in dyld's DATA segment are chained together.
// They need to be fixed up to be real pointers to run.
//
static void rebaseDyld(const dyld3::MachOLoaded* dyldMH)
{
    // walk all fixups chains and rebase dyld
    const dyld3::MachOAnalyzer* ma = (dyld3::MachOAnalyzer*)dyldMH;
    assert(ma->hasChainedFixups());
    uintptr_t slide = (long)ma; // all fixup chain based images have a base address of zero, so slide == load address
    __block Diagnostics diag;
	// Install a tiny TSD block before any fallible syscalls hit libsyscall's
	// cerror path, which expects GS-relative errno storage to exist.
	//
	// This MUST precede the fixup walk below, and it used to follow it. The
	// fixup walk calls __simple_salloc -> _vm_allocate -> _mach_vm_allocate ->
	// __kernelrpc_mach_vm_allocate -> __mig_get_reply_port, which reads
	// _os_tsd_get_direct(__TSD_MIG_REPLY) -- a %gs-relative load. With no %gs
	// base yet that faults, and it faulted: the first boot of our own
	// MH_DYLINKER died at exactly that instruction (RIP +0xbe02d, four bytes
	// into __mig_get_reply_port), with this backtrace:
	//
	//   __dyld_start -> dyldbootstrap::start -> rebaseDyld ->
	//   rebaseDyld_block_invoke -> MachOLoaded::fixupAllChainedFixups ->
	//   walkChain -> forEachFixupInAllChains -> MachOAnalyzer::withChainStarts
	//   -> __simple_salloc -> _vm_allocate -> _mach_vm_allocate ->
	//   __kernelrpc_mach_vm_allocate -> __mig_get_reply_port  <-- fault
	//
	// The comment above already stated the requirement; only the placement was
	// wrong. Note __thread_set_tsd_base is itself a syscall on x86_64
	// (SYSCALL_CONSTRUCT_MDEP(3)), so it is one of the earliest things that
	// can establish a TSD base at all -- it cannot be moved much earlier than
	// this, and it does not need to be.
	_dyld_setup_minimal_tsd();

	// ---- INSTRUMENTATION -----------------------------------------------------
	// Why this is here and not a diag.error(): Diagnostics::error formats into
	// _buffer and only fprintf()s under `#if BUILDING_CACHE_BUILDER`
	// (Diagnostics.cpp:86-103).  In the dyld TOOL build that #if is false, so
	// EVERY diag.error() in this loader records a message and prints NOTHING.
	// That is why a missing message on the serial log is not evidence that the
	// code did not run -- and it is the same defect class as the empty export
	// trie and rc=0 by default: a check that cannot be seen failing.
	//
	// _simple_dprintf is used instead because it is the one path proven to reach
	// the console this early -- line 199 prints DYLD-LOAD-BASE with it.
	__block const dyld_chained_starts_in_image* startsSeen = nullptr;
	__block uint32_t unboundBinds = 0;
	__block uint32_t totalBinds = 0;

	ma->withChainStarts(diag, 0, ^(const dyld_chained_starts_in_image* starts) {
		startsSeen = starts;
		_simple_dprintf(2, "CHAINPROBE: block FIRED, starts=%p seg_count=%u "
		                   "off0=%#x off1=%#x off2=%#x off3=%#x\n",
		                (void*)starts, starts->seg_count,
		                starts->seg_info_offset[0], starts->seg_info_offset[1],
		                starts->seg_info_offset[2], starts->seg_info_offset[3]);
		ma->fixupAllChainedFixups(diag, starts, slide, dyld3::Array<const void*>(), nullptr);

		// The guard, folded into the same walk so it sees the same starts the
		// fixup pass saw.  A fixup pass that binds nothing must not report
		// success.  bindTargets above is EMPTY, so every bind is unresolvable by
		// construction, and a slot left alone is one a __stub will jmpq through
		// into a non-canonical address.
		ma->forEachFixupInAllChains(diag, starts, false, ^(dyld3::MachOLoaded::ChainedFixupPointerOnDisk* fixupLoc, const dyld_chained_starts_in_segment* segInfo, bool& stop) {
			if ( segInfo->pointer_format == DYLD_CHAINED_PTR_64
			  || segInfo->pointer_format == DYLD_CHAINED_PTR_64_OFFSET ) {
				if ( fixupLoc->generic64.bind.bind ) {
					++totalBinds;
					if ( fixupLoc->raw64 & (1ULL << 63) )
						++unboundBinds;
				}
			}
		});
	});

	if ( startsSeen == nullptr ) {
		// leInfo.chainedFixups was null, so withChainStarts never invoked the
		// block: no rebases, no binds, no diagnostics, and noError.  Say so.
		_simple_dprintf(2, "CHAINPROBE: BLOCK NEVER FIRED - leInfo.chainedFixups is "
		                   "null, so this loader applied NO chained fixups at all\n");
	} else {
		_simple_dprintf(2, "CHAINPROBE: %u of %u bind slots still unbound after the "
		                   "fixup pass\n", unboundBinds, totalBinds);
	}
	diag.assertNoError();

	// now that rebasing done, initialize mach/syscall layer
    mach_init();

    // <rdar://47805386> mark __DATA_CONST segment in dyld as read-only (once fixups are done)
    ma->forEachSegment(^(const dyld3::MachOFile::SegmentInfo& info, bool& stop) {
        if ( info.readOnlyData ) {
            ::mprotect(((uint8_t*)(dyldMH))+info.vmAddr, (size_t)info.vmSize, VM_PROT_READ);
        }
    });
}



//
//  This is code to bootstrap dyld.  This work in normally done for a program by dyld and crt.
//  In dyld we have to do this manually.
//
uintptr_t start(const dyld3::MachOLoaded* appsMachHeader, int argc, const char* argv[],
				const dyld3::MachOLoaded* dyldsMachHeader, uintptr_t* startGlue)
{

    // Emit kdebug tracepoint to indicate dyld bootstrap has started <rdar://46878536>
    dyld3::kdebug_trace_dyld_marker(DBG_DYLD_TIMING_BOOTSTRAP_START, 0, 0, 0, 0);

	// ---- INSTRUMENTATION, NOT A FEATURE. REMOVE ONCE THE LOADER CRASH IS FIXED.
	// dyldsMachHeader IS this image's load address. The loader is re-slid on
	// every boot (0x1092..., 0x116b8..., 0x1145d..., 0x10e58... over four boots),
	// so a backtrace from one run cannot be symbolized against another, and one
	// whose frames all sit in a 5 KB cycle has no outer frame to anchor on.
	// Printing the base turns an unanchored crash into an anchored one.
	//
	// PLACEMENT IS LOAD-BEARING and this got it wrong twice: this print must
	// PRECEDE rebaseDyld() below, because the crash is INSIDE rebaseDyld, so a
	// print after it can never fire. That is the same defect class as the %gs
	// fix in this same function -- a correct mechanism in the wrong place --
	// committed the same session. Recorded, not quietly corrected.
	// fd 2, not fd 1: dyld's own _ZN4dyld3logEPKcz is _simple_dprintf(2,...)
	// at glue.c:248.
	_simple_dprintf(2, "DYLD-LOAD-BASE: 0x%lx\n", (unsigned long)dyldsMachHeader);
	// if kernel had to slide dyld, we need to fix up load sensitive locations
	// we have to do this before using any global variables
    rebaseDyld(dyldsMachHeader);


	// kernel sets up env pointer to be just past end of agv array
	const char** envp = &argv[argc+1];
	
	// kernel sets up apple pointer to be just past end of envp array
	const char** apple = envp;
	while(*apple != NULL) { ++apple; }
	++apple;

        open("/dev/console", O_RDONLY); // stdin
        open("/dev/console", O_WRONLY); // stdout
        open("/dev/console", O_WRONLY); // stderr

	// set up random value for stack canary
	__guard_setup(apple);

#if DYLD_INITIALIZER_SUPPORT
	// run all C++ initializers inside dyld
	runDyldInitializers(argc, argv, envp, apple);
#endif

	// now that we are done bootstrapping dyld, call dyld's main
	uintptr_t appsSlide = appsMachHeader->getSlide();
	return dyld::_main((macho_header*)appsMachHeader, appsSlide, argc, argv, envp, apple, startGlue);
}


#if TARGET_OS_SIMULATOR

extern "C" uintptr_t start_sim(int argc, const char* argv[], const char* envp[], const char* apple[],
							const dyld3::MachOLoaded* mainExecutableMH, const dyld3::MachOLoaded* dyldMH, uintptr_t dyldSlide,
							const dyld::SyscallHelpers*, uintptr_t* startGlue);
					

uintptr_t start_sim(int argc, const char* argv[], const char* envp[], const char* apple[],
					const dyld3::MachOLoaded* mainExecutableMH, const dyld3::MachOLoaded* dyldSimMH, uintptr_t dyldSlide,
					const dyld::SyscallHelpers* sc, uintptr_t* startGlue)
{
    // save table of syscall pointers
    gSyscallHelpers = sc;

	// dyld_sim uses chained rebases, so it always need to be fixed up
    rebaseDyld(dyldSimMH);

	// set up random value for stack canary
	__guard_setup(apple);

	// setup gProcessInfo to point to host dyld's struct
	dyld::gProcessInfo = (struct dyld_all_image_infos*)(sc->getProcessInfo());
	syncProcessInfo();

	// now that we are done bootstrapping dyld, call dyld's main
    uintptr_t appsSlide = mainExecutableMH->getSlide();
	return dyld::_main((macho_header*)mainExecutableMH, appsSlide, argc, argv, envp, apple, startGlue);
}
#endif


} // end of namespace




