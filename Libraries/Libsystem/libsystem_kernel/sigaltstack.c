/* sigaltstack(2) wrapper.  The kernel implements syscall 53 and libsyscall
 * carries __sigaltstack, but the public name was never aliased on x86_64,
 * so any binary that provides an alternate signal stack (Firefox's crash
 * handler among them) failed to bind. */
#include <signal.h>
#include <sys/signal.h>

extern int __sigaltstack(const stack_t *, stack_t *);

int
sigaltstack(const stack_t *restrict ss, stack_t *restrict oss)
{
	return __sigaltstack(ss, oss);
}
