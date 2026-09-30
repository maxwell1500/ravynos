/* Call a Windows-x64-ABI function from a SysV host.
 *
 * The EFI application is compiled with -target x86_64-unknown-windows, so
 * its entry point takes (ImageHandle, SystemTable) in RCX/RDX and expects
 * 32 bytes of shadow space.  This shim performs the register shuffle and
 * allocates the shadow space so hostsim.py can drive the real image.
 */
#include <stdint.h>

/* NOTE: %0 is the output operand; inputs are %1..%3. */

uint64_t win_call(uint64_t a, uint64_t b, uint64_t fn)
{
	uint64_t ret;

	__asm__ volatile(
		"pushq	%%rbp\n\t"
		"movq	%%rsp, %%rbp\n\t"
		"andq	$-16, %%rsp\n\t"
		"subq	$32, %%rsp\n\t"        /* Windows x64 shadow space */
		"movq	%1, %%rcx\n\t"
		"movq	%2, %%rdx\n\t"
		"movq	%3, %%r11\n\t"
		"call	*%%r11\n\t"
		"movq	%%rbp, %%rsp\n\t"
		"popq	%%rbp\n\t"
		: "=a"(ret)
		: "r"(a), "r"(b), "r"(fn)
		: "rbp", "rcx", "rdx", "r11", "memory");
	return ret;
}
