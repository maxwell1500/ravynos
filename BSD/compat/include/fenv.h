/* ravynOS <fenv.h>: the SDK does not ship one.  Layout and constants match
 * the macOS x86_64 ABI so prebuilt applications can pass fenv_t across. */
#ifndef _RAVYN_COMPAT_FENV_H_
#define _RAVYN_COMPAT_FENV_H_

#if defined(__x86_64__) || defined(__i386__)
typedef struct {
	unsigned short __control;
	unsigned short __status;
	unsigned int __mxcsr;
	char __reserved[8];
} fenv_t;
typedef unsigned short fexcept_t;

#define FE_INEXACT          0x0020
#define FE_UNDERFLOW        0x0010
#define FE_OVERFLOW         0x0008
#define FE_DIVBYZERO        0x0004
#define FE_INVALID          0x0001
#define FE_DENORMALOPERAND  0x0002
#define FE_ALL_EXCEPT       0x003f
#define FE_TONEAREST        0x0000
#define FE_DOWNWARD         0x0400
#define FE_UPWARD           0x0800
#define FE_TOWARDZERO       0x0c00
#endif

#ifdef __cplusplus
extern "C" {
#endif
int fegetenv(fenv_t *);
int fesetenv(const fenv_t *);
float __exp10f(float);
#ifdef __cplusplus
}
#endif

#endif
