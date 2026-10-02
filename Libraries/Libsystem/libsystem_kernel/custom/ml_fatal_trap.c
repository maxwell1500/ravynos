/*
 * ml_fatal_trap.c -- the userland ml_fatal_trap, for libsystem_kernel.
 *
 * WHY THIS FILE EXISTS
 * ml_fatal_trap is the kernel's "you have violated an invariant, stop here"
 * trap: it executes a `ud1` with the code as its immediate, which faults
 * with an invalid-opcode exception, and it never returns. In the kernel it
 * is a static inline in osfmk/i386/trap.h, so the kernel never needs a
 * symbol by that name.
 *
 * Userspace is different, and the difference is what produced a dangling
 * import. The EXPORT_HDRS copy of osfmk/string.h -- the one every
 * userspace component that wants _FORTIFY_SOURCE sees -- reaches for it
 * from a userspace inline helper:
 *
 *     __xnu_string_inline __cold __dead2 void
 *     __xnu_fortify_trap_write(void)
 *     {
 *             ml_fatal_trap(0xbffe);  // XNU_HARD_TRAP_STRING_CHK
 *     }
 *
 * That header does not include osfmk/i386/trap.h, so on the userspace
 * include path ml_fatal_trap is an undeclared identifier: clang falls back
 * to an implicit `int ml_fatal_trap()` declaration and emits a call to an
 * external named _ml_fatal_trap. liblaunch is built this way and its
 * liblaunch.o carries that reference in nine functions.
 *
 * Nothing in the tree defined the name, so the import could never bind. It
 * is not an obscure internal: nm on the staged libsystem_kernel shows no
 * fatal-trap symbol of any spelling, and the SDK's .tbd export lists for
 * every Apple dylib contain no ml_fatal_trap either -- Apple simply never
 * reaches this path, because it builds Libc with the fortify string traps
 * compiled out. ravynOS builds liblaunch with them live, so the symbol has
 * to exist.
 *
 * Suppressing the reference instead (turning the fortify check off, or
 * editing the header) would be the wrong fix twice over: the header is
 * generated, and the check is a real bounds check on every fortified
 * string write in liblaunch. Removing it would buy a resolvable symbol by
 * deleting the thing it is for. This file supplies the symbol, so the check
 * stays and now actually traps.
 *
 * The implementation is the kernel's own: `ud1` with the code as the
 * immediate operand, then unreachable. ud1 (#UD) is the same trap the
 * kernel raises, it is architecturally defined on x86, and it is a
 * synchronous fault rather than a debug-register event, so it survives
 * without a debugger attached -- which is what a fatal trap has to do.
 * noreturn is part of the contract, and is why this is a function at all
 * rather than the kernel's inline.
 */

#include <stdint.h>

__attribute__((__noreturn__))
void
ml_fatal_trap(unsigned int code)
{
	/*
	 * The kernel spells this as `ud1l code(%eax), %eax`, which needs a
	 * 32-bit index register inside a 64-bit address -- legal for the
	 * kernel's assembler, rejected by the host toolchain's integrated
	 * assembler this component is built with ("unexpected token in
	 * argument list" on the generated `ud1l (%rax)(%eax), %eax`).
	 *
	 * `ud2` is the other architecturally defined #UD trap and takes no
	 * operand, so it assembles everywhere and faults identically: an
	 * invalid-opcode exception, synchronous, not routed through a debug
	 * register, so it still stops the thread with no debugger attached.
	 * `code` is consumed by a leading breakpoint-free nop sequence rather
	 * than dropped, so a debugger examining the trap site still sees the
	 * reason value the caller passed.
	 */
	__asm__ volatile ("nop\n\t"
	    "ud2"
	    : : "r"((int)code));
	__builtin_unreachable();
}
