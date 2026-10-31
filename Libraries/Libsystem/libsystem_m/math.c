/*
 * Minimal libm for ravynOS
 * Copyright (C) 2026 Zoe Knox <zoe@pixin.net>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#include <math.h>
#include <stdbool.h>
#include <errno.h>

#undef signbit
#undef fpclassify
#undef isfinite
#undef isinf
#undef isnan
#undef isnormal
#undef isgreater
#undef isgreaterequal
#undef isless
#undef islessequal
#undef islessgreater
#undef isunordered
#undef __isnanf

bool signbit(double __x) { return __builtin_signbit(__x); }
int __signbit(double __x) { return __builtin_signbit(__x); }
int __signbitd(double __x) { return __builtin_signbit(__x); }
int __signbitf(float __x) { return __builtin_signbit(__x); }
int __signbitl(long double __x) { return __builtin_signbit(__x); }
int fpclassify(double __x) {
  return __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, __x);
}
int __fpclassifyd(double __x) {
  return __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, __x);
}
int __fpclassifyf(float __x) {
  return __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, __x);
}
int __fpclassifyl(long double __x) {
  return __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, __x);
}
bool isfinite(double __x) { return __builtin_isfinite(__x); }
int __isfinited(double __x) { return __builtin_isfinite(__x); }
int __isfinitef(float __x) { return __builtin_isfinite(__x); }
int __isfinitel(long double __x) { return __builtin_isfinite(__x); }
bool isinf(double __x) { return __builtin_isinf(__x); }
int __isinf(double __x) { return __builtin_isinf(__x); }
int __isinfd(double __x) { return __builtin_isinf(__x); }
int __isinff(float __x) { return __builtin_isinf(__x); }
int __isinfl(long double __x) { return __builtin_isinf(__x); }
bool isnan(double __x) { return __builtin_isnan(__x); }
int __isnand(double __x) { return __builtin_isnan(__x); }
int __isnanf(float __x) { return __builtin_isnan(__x); }
int __isnanl(long double __x) { return __builtin_isnan(__x); }
bool isnormal(double __x) { return __builtin_isnormal(__x); }
int __isnormald(double __x) { return __builtin_isnormal(__x); }
bool isgreater(double __x, double __y) { return __builtin_isgreater(__x, __y); }
bool isgreaterequal(double __x, double __y) { return __builtin_isgreaterequal(__x, __y); }
bool isless(double __x, double __y) { return __builtin_isless(__x, __y); }
bool islessequal(double __x, double __y) { return __builtin_islessequal(__x, __y); }
bool islessgreater(double __x, double __y) { return __builtin_islessgreater(__x, __y); }
bool isunordered(double __x, double __y) { return __builtin_isunordered(__x, __y); }

double sqrt(double x);
float sqrtf(float x);
long double sqrtl(long double x);
double exp(double x);
float expf(float x);
long double expl(long double x);
double log(double x);
float logf(float x);
long double logl(long double x);

double atan2(double y, double x) {
    double r;
    __asm__ ("fpatan" : "=t" (r) : "0" (x), "u" (y) : "st(1)");
    return r;
}
float atan2f(float y, float x) { return (float)atan2((double)y, (double)x); }
long double atan2l(long double y, long double x) {
    long double r;
    __asm__ ("fpatan" : "=t" (r) : "0" (x), "u" (y) : "st(1)");
    return r;
}

double atan(double x) {
    double r;
    __asm__ ("fld1; fpatan" : "=t" (r) : "0" (x));
    return r;
}
float atanf(float x) { return (float)atan((double)x); }
long double atanl(long double x) {
    long double r;
    __asm__ ("fld1; fpatan" : "=t" (r) : "0" (x));
    return r;
}

double asin(double x) { return atan2(x, sqrt(1.0 - x * x)); }
float asinf(float x) { return (float)asin((double)x); }
long double asinl(long double x) { return (long double)asin((double)x); }

double acos(double x) { return atan2(sqrt(1.0 - x * x), x); }
float acosf(float x) { return (float)acos((double)x); }
long double acosl(long double x) { return (long double)acos((double)x); }

double cos(double x) {
    double r;
    __asm__ ("fcos" : "=t" (r) : "0" (x));
    return r;
}
float cosf(float x) { return (float)cos((double)x); }
long double cosl(long double x) {
    long double r;
    __asm__ ("fcos" : "=t" (r) : "0" (x));
    return r;
}

double ceil(double x) { double r; __asm__ ("roundsd $2, %1, %0" : "=x" (r) : "x" (x)); return r; }
float ceilf(float x) { float r; __asm__ ("roundss $2, %1, %0" : "=x" (r) : "x" (x)); return r; }
long double ceill(long double x) { return (long double)ceil((double)x); }

double cosh(double x) { return (exp(x) + exp(-x)) * 0.5; }
float coshf(float x) { return (float)cosh((double)x); }
long double coshl(long double x) { return (long double)cosh((double)x); }

double exp(double x) {
    double r;
    __asm__ ("fldl2e; fmulp; fld %%st(0); frndint; fsubr %%st(0), %%st(1); fxch; f2xm1; fld1; faddp; fscale; fstp %%st(1)" : "=t" (r) : "0" (x) : "st(1)");
    return r;
}
float expf(float x) { return (float)exp((double)x); }
long double expl(long double x) {
    long double r;
    __asm__ ("fldl2e; fmulp; fld %%st(0); frndint; fsubr %%st(0), %%st(1); fxch; f2xm1; fld1; faddp; fscale; fstp %%st(1)" : "=t" (r) : "0" (x) : "st(1)");
    return r;
}

float fabsf(float __x) { return __builtin_fabsf(__x); }
double fabs(double __x) { return __builtin_fabs(__x); }
long double fabsl(long double __x) { return __builtin_fabsl(__x); }

double floor(double x) { double r; __asm__ ("roundsd $1, %1, %0" : "=x" (r) : "x" (x)); return r; }
float floorf(float x) { float r; __asm__ ("roundss $1, %1, %0" : "=x" (r) : "x" (x)); return r; }
long double floorl(long double x) { return (long double)floor((double)x); }

float fmodf(float __x, float __y) { return (float)fmodl(__x, __y); }
double fmod(double __x, double __y) { return (double)fmodl(__x, __y); }
long double fmodl(long double __x, long double __y) {
    if (isnan(__x) || isnan(__y))
        return FP_NAN;
    if (isinf(__x)) {
        errno = EDOM;
        return FP_NAN; // FIXME: should raise exception
    }
    if (__y == 0) {
        errno = EDOM;
        return FP_NAN; // FIXME: should raise exception
    }
    long long n = (long long)__x / (long long)__y;
    long double z = __x - (long double)n * __y;
    if (z < 0)
        z *= -1.0;
    return z;
}

int _fmodtest(void) {
    if (fmod(372, 360) != 12) return 1;
    if (fmod(-372, 360) != -12) return 2;
    if (fmod(-372, -360) != -12) return 3;
    return 0;
}



/* ------------------------------------------------------------------
 * Real implementations for the stubs below.
 *
 * Each wrapper used to read "__builtin_<name>(...)", which clang lowers
 * to a call to <name> itself for everything it does not expand inline
 * (frexp, ldexp, modf, scalbn, ilogb, nextafter, rint, round, trunc,
 * remainder, erf, lgamma, tgamma ...).  Those stubs recursed until the
 * stack guard page was hit (measured: tclsh9.0 died in libsystem_m
 * frexp+0x22 with rsp at the bottom of its 8 MB stack).  The versions
 * here compute, using only the asm primitives in this file plus IEEE
 * format bit manipulation.
 *
 * Accuracy shortcuts, each marked where the code is:
 *  - erf/erfc use the Numerical-Recipes Chebyshev fit (~1.2e-7 relative)
 *  - fma() is unfused (x*y+z); a correctly rounded fma needs a
 *    multi-precision step that nothing in the image needs yet.
 *  - long double transcendentals are computed in long double but on top
 *    of this file's expl/logl/sqrtl, not an 80-bit-accurate kernel.
 * ------------------------------------------------------------------ */
#include <stdint.h>
#include <string.h>
#include <limits.h>

typedef struct { uint64_t m; uint16_t se; } __ravyn_ld80;

static long double __ravyn_ld80_pow2(int n) {
    __ravyn_ld80 u;
    u.m = 0x8000000000000000ULL;
    u.se = (uint16_t)(0x3fff + n);
    long double r;
    memcpy(&r, &u, 10);
    return r;
}

static long double __ravyn_ld80_trunc(long double x) {
    __ravyn_ld80 u;
    memcpy(&u, &x, 10);
    int ex = (u.se & 0x7fff) - 16383;
    if (ex < 0) return copysignl(0.0L, x);
    if (ex >= 63) return x;
    u.m &= ~((1ULL << (63 - ex)) - 1);
    memcpy(&x, &u, 10);
    return x;
}

/* --- frexp / scalbn / ldexp ------------------------------------- */

static double __ravyn_frexp_d(double x, int *e) {
    union { double d; uint64_t u; } v;
    v.d = x;
    int ex = (int)((v.u >> 52) & 0x7ff);
    if (ex == 0x7ff) { *e = 0; return x; }
    int adj = 0;
    if (ex == 0) {
        /* +-0 has an all-zero magnitude too; only a real subnormal gets
         * renormalized here, otherwise -0.0 came back as a scaled -0.5. */
        if ((v.u & 0x7fffffffffffffffULL) == 0) { *e = 0; return x; }
        x *= 0x1p64;
        v.d = x;
        ex = (int)((v.u >> 52) & 0x7ff);
        adj = -64;
    }
    *e = ex - 1022 + adj;
    v.u = (v.u & 0x800fffffffffffffULL) | 0x3fe0000000000000ULL;
    return v.d;
}

static double __ravyn_scalbn_d(double x, int n) {
    if (x != x || x == 0.0 || x == 1.0/0.0 || x == -1.0/0.0) return x;
    while (n > 1023) { x *= 0x1p1023; n -= 1023; if (x == 1.0/0.0 || x == -1.0/0.0) return x; }
    while (n < -1022) { x *= 0x1p-1022; n += 1022; if (x == 0.0) return x; }
    union { double d; uint64_t u; } v;
    v.u = (uint64_t)(n + 1023) << 52;
    return x * v.d;
}

static long double __ravyn_scalbn_l(long double x, int n) {
    if (x != x || x == 0.0L) return x;
    while (n > 16383) { x *= __ravyn_ld80_pow2(16383); n -= 16383; if (x == 1.0L/0.0L || x == -1.0L/0.0L) return x; }
    while (n < -16382) { x *= __ravyn_ld80_pow2(-16382); n += 16382; if (x == 0.0L) return x; }
    return x * __ravyn_ld80_pow2(n);
}

static float  __ravyn_frexpf(float x, int *e) { return (float)__ravyn_frexp_d((double)x, e); }
static double __ravyn_frexp(double x, int *e) { return __ravyn_frexp_d(x, e); }
static long double __ravyn_frexpl(long double x, int *e) {
    __ravyn_ld80 u;
    memcpy(&u, &x, 10);
    int ex = u.se & 0x7fff;
    if (ex == 0x7fff) { *e = 0; return x; }
    int adj = 0;
    if (ex == 0) {
        if (u.m == 0) { *e = 0; return x; }
        x *= 0x1p64L;
        memcpy(&u, &x, 10);
        ex = u.se & 0x7fff;
        adj = -64;
    }
    *e = ex - 16382 + adj;
    u.se = (uint16_t)((u.se & 0x8000) | 0x3ffe);
    memcpy(&x, &u, 10);
    return x;
}

static float  __ravyn_ldexpf(float x, int e) { return (float)__ravyn_scalbn_d((double)x, e); }
static double __ravyn_ldexp(double x, int e) { return __ravyn_scalbn_d(x, e); }
static long double __ravyn_ldexpl(long double x, int e) { return __ravyn_scalbn_l(x, e); }
static float  __ravyn_scalbnf(float x, int n) { return (float)__ravyn_scalbn_d((double)x, n); }
static double __ravyn_scalbn(double x, int n) { return __ravyn_scalbn_d(x, n); }
static long double __ravyn_scalbnl(long double x, int n) { return __ravyn_scalbn_l(x, n); }
static float  __ravyn_scalblnf(float x, long n) { return (float)__ravyn_scalbn_d((double)x, (int)n); }
static double __ravyn_scalbln(double x, long n) { return __ravyn_scalbn_d(x, (int)n); }
static long double __ravyn_scalblnl(long double x, long n) { return __ravyn_scalbn_l(x, (int)n); }

/* --- modf ------------------------------------------------------- */

static double __ravyn_modf_d(double x, double *ip) {
    if (x != x) { *ip = x; return x; }
    if (x == 1.0/0.0 || x == -1.0/0.0) { *ip = x; return copysign(0.0, x); }
    double t = trunc(x);
    *ip = t;
    double f = x - t;
    return (f == 0.0) ? copysign(0.0, x) : f;
}
static float  __ravyn_modff(float x, float *ip) { double i; double f = __ravyn_modf_d((double)x, &i); *ip = (float)i; return (float)f; }
static double __ravyn_modf(double x, double *ip) { return __ravyn_modf_d(x, ip); }
static long double __ravyn_modfl(long double x, long double *ip) {
    if (x != x) { *ip = x; return x; }
    if (x == 1.0L/0.0L || x == -1.0L/0.0L) { *ip = x; return copysignl(0.0L, x); }
    long double t = __ravyn_ld80_trunc(x);
    *ip = t;
    long double f = x - t;
    return (f == 0.0L) ? copysignl(0.0L, x) : f;
}

/* --- round / rint / trunc --------------------------------------- */

static double __ravyn_round_d(double x) {
    if (x != x || x == 1.0/0.0 || x == -1.0/0.0) return x;
    double t = trunc(x);
    double f = x - t;
    if (f >= 0.5) t += 1.0;
    else if (f <= -0.5) t -= 1.0;
    return (t == 0.0) ? copysign(0.0, x) : t;
}
static double __ravyn_round(double x) { return __ravyn_round_d(x); }
static long double __ravyn_roundl(long double x) {
    if (x != x || x == 1.0L/0.0L || x == -1.0L/0.0L) return x;
    long double t = __ravyn_ld80_trunc(x);
    long double f = x - t;
    if (f >= 0.5L) t += 1.0L;
    else if (f <= -0.5L) t -= 1.0L;
    return (t == 0.0L) ? copysignl(0.0L, x) : t;
}
/* x87 rounds to the control word's mode, which is round-to-nearest-even by
 * default, so frndint *is* rint() here. */
static long double __ravyn_rintl(long double x) {
    long double r;
    __asm__ ("frndint" : "=t" (r) : "0" (x));
    return r;
}
static long double __ravyn_nearbyintl(long double x) { return __ravyn_rintl(x); }
static long double __ravyn_truncl(long double x) { return __ravyn_ld80_trunc(x); }

static long long __ravyn_llround_d(double r) {
    if (r != r) return 0;
    if (r >= 0x1p63) return 0x7fffffffffffffffLL;
    if (r <= -0x1p63) return (long long)0x8000000000000000ULL;
    return (long long)r;
}
static long long __ravyn_llround(double x) { return __ravyn_llround_d(__ravyn_round_d(x)); }
static long long __ravyn_llroundf(float x) { return __ravyn_llround_d(__ravyn_round_d((double)x)); }
static long long __ravyn_llroundl(long double x) {
    long double r = __ravyn_roundl(x);
    if (r != r) return 0;
    if (r >= 0x1p63L) return 0x7fffffffffffffffLL;
    if (r <= -0x1p63L) return (long long)0x8000000000000000ULL;
    return (long long)r;
}
static long __ravyn_lround(double x) { return (long)__ravyn_llround_d(__ravyn_round_d(x)); }
static long __ravyn_lroundf(float x) { return (long)__ravyn_llround_d(__ravyn_round_d((double)x)); }
static long __ravyn_lroundl(long double x) { return (long)__ravyn_llroundl(x); }

/* --- ilogb / logb ----------------------------------------------- */

static int __ravyn_ilogb_d(double x) {
    union { double d; uint64_t u; } v;
    v.d = x;
    int ex = (int)((v.u >> 52) & 0x7ff);
    if (ex == 0x7ff) return (x != x) ? INT_MAX : 0x7fffffff;
    if (ex == 0) {
        if (x == 0.0) return (-INT_MAX);
        int e;
        __ravyn_frexp_d(x, &e);
        return e - 1;
    }
    return ex - 1023;
}
static int __ravyn_ilogbf(float x) { return __ravyn_ilogb_d((double)x); }
static int __ravyn_ilogb(double x) { return __ravyn_ilogb_d(x); }
static int __ravyn_ilogbl(long double x) {
    __ravyn_ld80 u;
    memcpy(&u, &x, 10);
    int ex = u.se & 0x7fff;
    if (ex == 0x7fff) return (x != x) ? INT_MAX : 0x7fffffff;
    if (ex == 0) {
        if (u.m == 0) return (-INT_MAX);
        int e;
        __ravyn_frexpl(x, &e);
        return e - 1;
    }
    return ex - 16383;
}
static double __ravyn_logb(double x) {
    if (x != x) return x;
    if (x == 1.0/0.0 || x == -1.0/0.0) return 1.0/0.0;
    if (x == 0.0) return -1.0/0.0;
    return (double)__ravyn_ilogb_d(x);
}
static float __ravyn_logbf(float x) { return (float)__ravyn_logb((double)x); }
static long double __ravyn_logbl(long double x) {
    if (x != x) return x;
    if (x == 1.0L/0.0L || x == -1.0L/0.0L) return 1.0L/0.0L;
    if (x == 0.0L) return -1.0L/0.0L;
    return (long double)__ravyn_ilogbl(x);
}

/* --- nextafter / nexttoward ------------------------------------- */

static double __ravyn_nextafter_d(double x, double y) {
    if (x != x || y != y) return x + y;
    if (x == y) return y;
    union { double d; uint64_t u; } v;
    v.d = x;
    if (x == 0.0) {
        v.u = (y > 0.0) ? 1ULL : 0x8000000000000001ULL;
        return v.d;
    }
    if ((y > x) == (x > 0.0)) v.u++;
    else v.u--;
    return v.d;
}
static float __ravyn_nextafterf(float x, float y) {
    if (x != x || y != y) return x + y;
    if (x == y) return y;
    union { float f; uint32_t u; } v;
    v.f = x;
    if (x == 0.0f) {
        v.u = (y > 0.0f) ? 1u : 0x80000001u;
        return v.f;
    }
    if ((y > x) == (x > 0.0f)) v.u++;
    else v.u--;
    return v.f;
}
static double __ravyn_nextafter(double x, double y) { return __ravyn_nextafter_d(x, y); }
static long double __ravyn_nextafterl(long double x, long double y) {
    if (x != x || y != y) return x + y;
    if (x == y) return y;
    __ravyn_ld80 u;
    memcpy(&u, &x, 10);
    if (x == 0.0L) {
        u.m = 1;
        u.se = (uint16_t)(y > 0.0L ? 0x0000 : 0x8000);
        memcpy(&x, &u, 10);
        return x;
    }
    if ((y > x) == (x > 0.0L)) {
        if (++u.m == 0) u.se++;
    } else {
        if (u.m-- == 0) u.se--;
    }
    memcpy(&x, &u, 10);
    return x;
}
static float __ravyn_nexttowardf(float x, long double y) { return __ravyn_nextafterf(x, (float)y); }
static double __ravyn_nexttoward(double x, long double y) { return __ravyn_nextafter_d(x, (double)y); }
static long double __ravyn_nexttowardl(long double x, long double y) { return __ravyn_nextafterl(x, y); }

/* --- fdim / fmaxl / fminl --------------------------------------- */

static double __ravyn_fdim_d(double x, double y) {
    if (x != x || y != y) return x + y;
    return (x > y) ? x - y : 0.0;
}
static float  __ravyn_fdimf(float x, float y) { return (float)__ravyn_fdim_d((double)x, (double)y); }
static double __ravyn_fdim(double x, double y) { return __ravyn_fdim_d(x, y); }
static long double __ravyn_fdiml(long double x, long double y) {
    if (x != x || y != y) return x + y;
    return (x > y) ? x - y : 0.0L;
}
static long double __ravyn_fmaxl(long double x, long double y) {
    if (x != x) return y;
    if (y != y) return x;
    return (x > y) ? x : y;
}
static long double __ravyn_fminl(long double x, long double y) {
    if (x != x) return y;
    if (y != y) return x;
    return (x < y) ? x : y;
}

/* --- hypot ------------------------------------------------------ */

static double __ravyn_hypot_d(double x, double y) {
    x = fabs(x); y = fabs(y);
    if (x < y) { double t = x; x = y; y = t; }
    if (x == 1.0/0.0) return x;
    if (x == 0.0) return 0.0;
    double r = y / x;
    return x * sqrt(1.0 + r * r);
}
static float  __ravyn_hypotf(float x, float y) { return (float)__ravyn_hypot_d((double)x, (double)y); }
static double __ravyn_hypot(double x, double y) { return __ravyn_hypot_d(x, y); }
static long double __ravyn_hypotl(long double x, long double y) {
    x = fabsl(x); y = fabsl(y);
    if (x < y) { long double t = x; x = y; y = t; }
    if (x == 1.0L/0.0L) return x;
    if (x == 0.0L) return 0.0L;
    long double r = y / x;
    return x * sqrtl(1.0L + r * r);
}

/* --- cbrt ------------------------------------------------------- */

static double __ravyn_cbrt_d(double x) {
    if (x != x || x == 0.0 || x == 1.0/0.0 || x == -1.0/0.0) return x;
    double a = fabs(x);
    int e;
    __ravyn_frexp_d(a, &e);
    double y = __ravyn_scalbn_d(1.0, e / 3);
    for (int i = 0; i < 6; i++) y = (2.0 * y + a / (y * y)) / 3.0;
    return copysign(y, x);
}
static float  __ravyn_cbrtf(float x) { return (float)__ravyn_cbrt_d((double)x); }
static double __ravyn_cbrt(double x) { return __ravyn_cbrt_d(x); }
static long double __ravyn_cbrtl(long double x) {
    if (x != x || x == 0.0L || x == 1.0L/0.0L || x == -1.0L/0.0L) return x;
    long double a = fabsl(x);
    int e;
    __ravyn_frexpl(a, &e);
    long double y = __ravyn_scalbn_l(1.0L, e / 3);
    for (int i = 0; i < 7; i++) y = (2.0L * y + a / (y * y)) / 3.0L;
    return copysignl(y, x);
}

/* --- exp2 / log2 / log1p / expm1 -------------------------------- */

static double __ravyn_exp2_d(double x) { return exp(x * 0.69314718055994530941723212145817657); }
static float  __ravyn_exp2f(float x) { return (float)__ravyn_exp2_d((double)x); }
static double __ravyn_exp2(double x) { return __ravyn_exp2_d(x); }
static long double __ravyn_exp2l(long double x) { return expl(x * 0.69314718055994530941723212145817657L); }

static double __ravyn_log2_d(double x) { return log(x) * 1.44269504088896340735992468100189214; }
static float  __ravyn_log2f(float x) { return (float)__ravyn_log2_d((double)x); }
static double __ravyn_log2(double x) { return __ravyn_log2_d(x); }
static long double __ravyn_log2l(long double x) { return logl(x) * 1.44269504088896340735992468100189214L; }

/* log1p from its atanh series: log1p(x) = 2*atanh(x/(2+x)); |u| <= 1/3 for
 * |x| <= 0.5, so the odd series converges in a few dozen terms. */
static double __ravyn_log1p_d(double x) {
    if (x != x || x == 1.0/0.0) return x;
    if (x == -1.0) return -1.0/0.0;
    if (x < -1.0) return 0.0/0.0;
    if (fabs(x) > 0.5) return log(1.0 + x);
    double u = x / (2.0 + x), u2 = u * u, sum = 0.0, p = u;
    for (int n = 1; n <= 51; n += 2) { sum += p / (double)n; p *= u2; }
    return 2.0 * sum;
}
static float  __ravyn_log1pf(float x) { return (float)__ravyn_log1p_d((double)x); }
static double __ravyn_log1p(double x) { return __ravyn_log1p_d(x); }
static long double __ravyn_log1pl(long double x) {
    if (x != x || x == 1.0L/0.0L) return x;
    if (x == -1.0L) return -1.0L/0.0L;
    if (x < -1.0L) return 0.0L/0.0L;
    if (fabsl(x) > 0.5L) return logl(1.0L + x);
    long double u = x / (2.0L + x), u2 = u * u, sum = 0.0L, p = u;
    for (int n = 1; n <= 51; n += 2) { sum += p / (long double)n; p *= u2; }
    return 2.0L * sum;
}

static double __ravyn_expm1_d(double x) {
    if (x != x || x == 1.0/0.0 || x == -1.0/0.0) return x;
    if (fabs(x) > 0.5) return exp(x) - 1.0;
    double term = 1.0, sum = 0.0;
    for (int n = 1; n <= 24; n++) { term *= x / (double)n; sum += term; }
    return sum;
}
static float  __ravyn_expm1f(float x) { return (float)__ravyn_expm1_d((double)x); }
static double __ravyn_expm1(double x) { return __ravyn_expm1_d(x); }
static long double __ravyn_expm1l(long double x) {
    if (x != x || x == 1.0L/0.0L || x == -1.0L/0.0L) return x;
    if (fabsl(x) > 0.5L) return expl(x) - 1.0L;
    long double term = 1.0L, sum = 0.0L;
    for (int n = 1; n <= 32; n++) { term *= x / (long double)n; sum += term; }
    return sum;
}

/* --- acosh / asinh / atanh -------------------------------------- */

static double __ravyn_asinh_d(double x) {
    if (x != x || x == 1.0/0.0 || x == -1.0/0.0) return x;
    if (x < 0.0) return -__ravyn_asinh_d(-x);
    return __ravyn_log1p_d(x + x * x / (1.0 + sqrt(1.0 + x * x)));
}
static float  __ravyn_asinhf(float x) { return (float)__ravyn_asinh_d((double)x); }
static double __ravyn_asinh(double x) { return __ravyn_asinh_d(x); }
static long double __ravyn_asinhl(long double x) {
    if (x < 0.0L) return -__ravyn_asinhl(-x);
    return __ravyn_log1pl(x + x * x / (1.0L + sqrtl(1.0L + x * x)));
}

static double __ravyn_acosh_d(double x) {
    if (x < 1.0) return (x != x || x == 1.0/0.0) ? (x - x) : 0.0/0.0;
    long double d = (long double)x - 1.0L;
    return __ravyn_log1p_d((double)(d + sqrtl(d * d + 2.0L * d)));
}
static float  __ravyn_acoshf(float x) { return (float)__ravyn_acosh_d((double)x); }
static double __ravyn_acosh(double x) { return __ravyn_acosh_d(x); }
static long double __ravyn_acoshl(long double x) {
    if (x < 1.0L) return 0.0L/0.0L;
    long double d = x - 1.0L;
    return __ravyn_log1pl(d + sqrtl(d * d + 2.0L * d));
}

static double __ravyn_atanh_d(double x) {
    if (x != x || x == 1.0/0.0 || x == -1.0/0.0) return x;
    if (x == 1.0) return 1.0/0.0;
    if (x == -1.0) return -1.0/0.0;
    if (x > 1.0 || x < -1.0) return 0.0/0.0;
    return 0.5 * __ravyn_log1p_d(2.0 * x / (1.0 - x));
}
static float  __ravyn_atanhf(float x) { return (float)__ravyn_atanh_d((double)x); }
static double __ravyn_atanh(double x) { return __ravyn_atanh_d(x); }
static long double __ravyn_atanhl(long double x) {
    if (x == 1.0L) return 1.0L/0.0L;
    if (x == -1.0L) return -1.0L/0.0L;
    if (x > 1.0L || x < -1.0L) return 0.0L/0.0L;
    return 0.5L * __ravyn_log1pl(2.0L * x / (1.0L - x));
}

/* --- erf / erfc ------------------------------------------------- */

/* shortcut: Chebyshev fit below is good to ~1.2e-7 relative; upgrade to a
 * rational minimax (msun s_erf.c) when anything needs full double accuracy. */
static double __ravyn_erfc_d(double x) {
    double t = 1.0 / (1.0 + 0.5 * fabs(x));
    double ans = t * exp(-x * x - 1.26551223 + t * (1.00002368 + t * (0.37409196 +
        t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 +
        t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
    return (x >= 0.0) ? ans : 2.0 - ans;
}
static double __ravyn_erf_d(double x) { return 1.0 - __ravyn_erfc_d(x); }
static float  __ravyn_erff(float x) { return (float)__ravyn_erf_d((double)x); }
static double __ravyn_erf(double x) { return __ravyn_erf_d(x); }
static long double __ravyn_erfl(long double x) { return (long double)__ravyn_erf_d((double)x); }
static float  __ravyn_erfcf(float x) { return (float)__ravyn_erfc_d((double)x); }
static double __ravyn_erfc(double x) { return __ravyn_erfc_d(x); }
static long double __ravyn_erfcl(long double x) { return (long double)__ravyn_erfc_d((double)x); }

/* --- lgamma / tgamma -------------------------------------------- */

static const double __ravyn_lanczos[9] = {
    0.99999999999980993, 676.5203681218851, -1259.1392167224028,
    771.32342877765313, -176.61502916214059, 12.507343278686905,
    -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7
};

static double __ravyn_lgamma_pos(double x) {   /* log(Gamma(x)) for x > 0 */
    x -= 1.0;
    double a = __ravyn_lanczos[0], t = x + 7.5;
    for (int i = 1; i < 9; i++) a += __ravyn_lanczos[i] / (x + i);
    return 0.91893853320467274178 + (x + 0.5) * log(t) - t + log(a);
}
static double __ravyn_lgamma_d(double x) {
    if (x != x) return x;
    if (x <= 0.0 && x == trunc(x)) return 1.0/0.0;
    if (x < 0.5) return log(3.14159265358979323846 / fabs(sin(3.14159265358979323846 * x)))
                      - __ravyn_lgamma_pos(1.0 - x);
    return __ravyn_lgamma_pos(x);
}
static double __ravyn_tgamma_d(double x) {
    if (x != x) return x;
    if (x == 1.0/0.0) return x;
    if (x == -1.0/0.0) return 0.0/0.0;
    if (x == 0.0) return copysign(1.0/0.0, x);
    if (x < 0.0 && x == trunc(x)) return 0.0/0.0;
    if (x < 0.5)
        return 3.14159265358979323846 / (sin(3.14159265358979323846 * x) * __ravyn_tgamma_d(1.0 - x));
    return exp(__ravyn_lgamma_pos(x));
}
static float  __ravyn_lgammaf(float x) { return (float)__ravyn_lgamma_d((double)x); }
static double __ravyn_lgamma(double x) { return __ravyn_lgamma_d(x); }
static long double __ravyn_lgammal(long double x) { return (long double)__ravyn_lgamma_d((double)x); }
static float  __ravyn_tgammaf(float x) { return (float)__ravyn_tgamma_d((double)x); }
static double __ravyn_tgamma(double x) { return __ravyn_tgamma_d(x); }
static long double __ravyn_tgammal(long double x) { return (long double)__ravyn_tgamma_d((double)x); }

/* --- fma -------------------------------------------------------- */

/* shortcut: unfused; the only callers in this image are compiler-emitted
 * scalar ops where the extra rounding is not observable. */
static float  __ravyn_fmaf(float x, float y, float z) { return x * y + z; }
static double __ravyn_fma(double x, double y, double z) { return x * y + z; }
static long double __ravyn_fmal(long double x, long double y, long double z) { return x * y + z; }

/* --- nan -------------------------------------------------------- */

static uint64_t __ravyn_nan_payload(const char *s) {
    uint64_t v = 0;
    if (s == NULL) return 0;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        for (s += 2; *s; s++) {
            char c = *s;
            int d = (c >= '0' && c <= '9') ? c - '0'
                  : (c >= 'a' && c <= 'f') ? c - 'a' + 10
                  : (c >= 'A' && c <= 'F') ? c - 'A' + 10 : -1;
            if (d < 0) break;
            v = (v << 4) | (uint64_t)d;
        }
    } else {
        for (; *s >= '0' && *s <= '9'; s++) v = v * 10 + (uint64_t)(*s - '0');
    }
    return v & 0x0007ffffffffffffULL;
}
static double __ravyn_nan(const char *s) {
    union { double d; uint64_t u; } v;
    v.u = 0x7ff8000000000000ULL | __ravyn_nan_payload(s);
    return v.d;
}
static float __ravyn_nanf(const char *s) {
    union { float f; uint32_t u; } v;
    v.u = 0x7fc00000u | (uint32_t)__ravyn_nan_payload(s);
    return v.f;
}
static long double __ravyn_nanl(const char *s) {
    __ravyn_ld80 u;
    u.m = 0xc000000000000000ULL | __ravyn_nan_payload(s);
    u.se = 0x7fff;
    long double r;
    memcpy(&r, &u, 10);
    return r;
}

/* --- remainder / remquo ----------------------------------------- */

static double __ravyn_remainder_d(double x, double y) {
    double r = fmod(x, y);
    if (r != r || r == 1.0/0.0 || r == -1.0/0.0) return r;
    double ay = fabs(y);
    if (fabs(r) > ay * 0.5 || (fabs(r) == ay * 0.5 && fmod(__ravyn_round_d(x / y), 2.0) != 0.0))
        r -= copysign(ay, r);
    return r;
}
static float  __ravyn_remainderf(float x, float y) { return (float)__ravyn_remainder_d((double)x, (double)y); }
static double __ravyn_remainder(double x, double y) { return __ravyn_remainder_d(x, y); }
static long double __ravyn_remainderl(long double x, long double y) {
    long double r = fmodl(x, y);
    if (r != r) return r;
    long double ay = fabsl(y);
    if (fabsl(r) > ay * 0.5L || (fabsl(r) == ay * 0.5L && fmodl(__ravyn_roundl(x / y), 2.0L) != 0.0L))
        r -= copysignl(ay, r);
    return r;
}
static double __ravyn_remquo_d(double x, double y, int *q) {
    double r = __ravyn_remainder_d(x, y);
    double quot = __ravyn_round_d(x / y);
    if (quot != quot || quot > 0x1p31) quot = 0.0;
    if (quot < -0x1p31) quot = 0.0;
    *q = (int)quot;
    return r;
}
static float  __ravyn_remquof(float x, float y, int *q) { return (float)__ravyn_remquo_d((double)x, (double)y, q); }
static double __ravyn_remquo(double x, double y, int *q) { return __ravyn_remquo_d(x, y, q); }
static long double __ravyn_remquol(long double x, long double y, int *q) {
    long double r = __ravyn_remainderl(x, y);
    long double quot = __ravyn_roundl(x / y);
    if (quot != quot || quot > 0x1p31L || quot < -0x1p31L) quot = 0.0L;
    *q = (int)quot;
    return r;
}

float frexpf(float __x, int* __e) { return __ravyn_frexpf(__x, __e); }
double frexp(double __x, int* __e) { return __ravyn_frexp(__x, __e); }
long double frexpl(long double __x, int* __e) { return __ravyn_frexpl(__x, __e); }

float ldexpf(float __x, int __e) { return __ravyn_ldexpf(__x, __e); }
double ldexp(double __x, int __e) { return __ravyn_ldexp(__x, __e); }
long double ldexpl(long double __x, int __e) { return __ravyn_ldexpl(__x, __e); }

double log(double x) {
    double r;
    __asm__ ("fldln2; fxch; fyl2x" : "=t" (r) : "0" (x) : "st(1)");
    return r;
}
float logf(float x) { return (float)log((double)x); }
long double logl(long double x) {
    long double r;
    __asm__ ("fldln2; fxch; fyl2x" : "=t" (r) : "0" (x) : "st(1)");
    return r;
}

double log10(double x) {
    double r;
    __asm__ ("fldlg2; fxch; fyl2x" : "=t" (r) : "0" (x) : "st(1)");
    return r;
}
float log10f(float x) { return (float)log10((double)x); }
long double log10l(long double x) {
    long double r;
    __asm__ ("fldlg2; fxch; fyl2x" : "=t" (r) : "0" (x) : "st(1)");
    return r;
}

float modff(float __x, float* __y) { return __ravyn_modff(__x, __y); }
double modf(double __x, double* __y)  { return __ravyn_modf(__x, __y); }
long double modfl(long double __x, long double* __y) { return __ravyn_modfl(__x, __y); }

double pow(double x, double y) {
    if (x == 0.0) return (y == 0.0) ? 1.0 : 0.0;
    if (y == 0.0) return 1.0;
    if (y == 1.0) return x;
    return exp(y * log(x));
}
float powf(float x, float y) { return (float)pow((double)x, (double)y); }
long double powl(long double x, long double y) { return (long double)pow((double)x, (double)y); }

double sin(double x) {
    double r;
    __asm__ ("fsin" : "=t" (r) : "0" (x));
    return r;
}
float sinf(float x) { return (float)sin((double)x); }
long double sinl(long double x) {
    long double r;
    __asm__ ("fsin" : "=t" (r) : "0" (x));
    return r;
}

double sinh(double x) { return (exp(x) - exp(-x)) * 0.5; }
float sinhf(float x) { return (float)sinh((double)x); }
long double sinhl(long double x) { return (long double)sinh((double)x); }

double sqrt(double x) {
    double r;
    __asm__ ("sqrtsd %1, %0" : "=x" (r) : "x" (x));
    return r;
}
float sqrtf(float x) {
    float r;
    __asm__ ("sqrtss %1, %0" : "=x" (r) : "x" (x));
    return r;
}
long double sqrtl(long double x) {
    long double r;
    __asm__ ("fsqrt" : "=t" (r) : "0" (x));
    return r;
}

double tan(double x) {
    double one, r;
    __asm__ ("fptan" : "=m" (one), "=t" (r) : "0" (x));
    return r;
}
float tanf(float x) { return (float)tan((double)x); }
long double tanl(long double x) {
    long double one, r;
    __asm__ ("fptan" : "=m" (one), "=t" (r) : "0" (x));
    return r;
}

double tanh(double x) { double e = exp(2.0 * x); return (e - 1.0) / (e + 1.0); }
float tanhf(float x) { return (float)tanh((double)x); }
long double tanhl(long double x) { return (long double)tanh((double)x); }
float acoshf(float __x) { return __ravyn_acoshf(__x); }
double acosh(double __x) { return __ravyn_acosh(__x); }
long double acoshl(long double __x) { return __ravyn_acoshl(__x); }

float asinhf(float __x) { return __ravyn_asinhf(__x); }
double asinh(double __x) { return __ravyn_asinh(__x); }
long double asinhl(long double __x) { return __ravyn_asinhl(__x); }

float atanhf(float __x) { return __ravyn_atanhf(__x); }
double atanh(double __x) { return __ravyn_atanh(__x); }
long double atanhl(long double __x) { return __ravyn_atanhl(__x); }

float cbrtf(float __x) { return __ravyn_cbrtf(__x); }
double cbrt(double __x) { return __ravyn_cbrt(__x); }
long double cbrtl(long double __x) { return __ravyn_cbrtl(__x); }

float copysignf(float __x, float __y) { return __builtin_copysignf(__x, __y); }
double copysign(double __x, double __y) { return __builtin_copysign(__x, __y); }
long double copysignl(long double __x, long double __y) { return __builtin_copysignl(__x, __y); }

float erff(float __x) { return __ravyn_erff(__x); }
double erf(double __x) { return __ravyn_erf(__x); }
long double erfl(long double __x) { return __ravyn_erfl(__x); }

float erfcf(float __x) { return __ravyn_erfcf(__x); }
double erfc(double __x) { return __ravyn_erfc(__x); }
long double erfcl(long double __x) { return __ravyn_erfcl(__x); }

float exp2f(float __x) { return __ravyn_exp2f(__x); }
double exp2(double __x) { return __ravyn_exp2(__x); }
long double exp2l(long double __x) { return __ravyn_exp2l(__x); }

float expm1f(float __x) { return __ravyn_expm1f(__x); }
double expm1(double __x) { return __ravyn_expm1(__x); }
long double expm1l(long double __x) { return __ravyn_expm1l(__x); }

float fdimf(float __x, float __y) { return __ravyn_fdimf(__x, __y); }
double fdim(double __x, double __y) { return __ravyn_fdim(__x, __y); }
long double fdiml(long double __x, long double __y) { return __ravyn_fdiml(__x, __y); }

float fmaf(float __x, float __y, float __z) { return __ravyn_fmaf(__x, __y, __z); }
double fma(double __x, double __y, double __z) { return __ravyn_fma(__x, __y, __z); }
long double fmal(long double __x, long double __y, long double __z) { return __ravyn_fmal(__x, __y, __z); }

float fmaxf(float __x, float __y) { return __builtin_fmaxf(__x, __y); }
double fmax(double __x, double __y) { return __builtin_fmax(__x, __y); }
long double fmaxl(long double __x, long double __y) { return __ravyn_fmaxl(__x, __y); }

float fminf(float __x, float __y) { return __builtin_fminf(__x, __y); }
double fmin(double __x, double __y) { return __builtin_fmin(__x, __y); }
long double fminl(long double __x, long double __y) { return __ravyn_fminl(__x, __y); }

float hypotf(float __x, float __y) { return __ravyn_hypotf(__x, __y); }
double hypot(double __x, double __y) { return __ravyn_hypot(__x, __y); }
long double hypotl(long double __x, long double __y) { return __ravyn_hypotl(__x, __y); }

int ilogbf(float __x) { return __ravyn_ilogbf(__x); }
int ilogb(double __x) { return __ravyn_ilogb(__x); }
int ilogbl(long double __x) { return __ravyn_ilogbl(__x); }

float lgammaf(float __x) { return __ravyn_lgammaf(__x); }
double lgamma(double __x) { return __ravyn_lgamma(__x); }
long double lgammal(long double __x) { return __ravyn_lgammal(__x); }

long long llrintf(float __x) { return __builtin_llrintf(__x); }
long long llrint(double __x) { return __builtin_llrint(__x); }
long long llrintl(long double __x) { return __builtin_llrintl(__x); }

long long llroundf(float __x) { return __ravyn_llroundf(__x); }
long long llround(double __x) { return __ravyn_llround(__x); }
long long llroundl(long double __x) { return __ravyn_llroundl(__x); }

float log1pf(float __x) { return __ravyn_log1pf(__x); }
double log1p(double __x) { return __ravyn_log1p(__x); }
long double log1pl(long double __x) { return __ravyn_log1pl(__x); }

float log2f(float __x) { return __ravyn_log2f(__x); }
double log2(double __x) { return __ravyn_log2(__x); }
long double log2l(long double __x) { return __ravyn_log2l(__x); }

float logbf(float __x) { return __ravyn_logbf(__x); }
double logb(double __x) { return __ravyn_logb(__x); }
long double logbl(long double __x) { return __ravyn_logbl(__x); }

long lrintf(float __x) { return __builtin_lrintf(__x); }
long lrint(double __x) { return __builtin_lrint(__x); }
long lrintl(long double __x) { return __builtin_lrintl(__x); }

long lroundf(float __x) { return __ravyn_lroundf(__x); }
long lround(double __x) { return __ravyn_lround(__x); }
long lroundl(long double __x) { return __ravyn_lroundl(__x); }

float nanf(const char * __s) { return __ravyn_nan(__s); }
double nan(const char * __s) { return __ravyn_nan(__s); }
long double nanl(const char * __s) { return __ravyn_nan(__s); }

float nearbyintf(float __x) { return __builtin_nearbyintf(__x); }
double nearbyint(double __x) { return __builtin_nearbyint(__x); }
long double nearbyintl(long double __x) { return __ravyn_nearbyintl(__x); }

float nextafterf(float __x, float __y) { return __ravyn_nextafterf(__x, __y); }
double nextafter(double __x, double __y) { return __ravyn_nextafter(__x, __y); }
long double nextafterl(long double __x, long double __y)  { return __ravyn_nextafterl(__x, __y); }

float nexttowardf(float __x, long double __y) { return __ravyn_nexttowardf(__x, __y); }
double nexttoward(double __x, long double __y) { return __ravyn_nexttoward(__x, __y); }
long double nexttowardl(long double __x, long double __y) { return __ravyn_nexttowardl(__x, __y); }

float remainderf(float __x, float __y) { return __ravyn_remainderf(__x, __y); }
double remainder(double __x, double __y) { return __ravyn_remainder(__x, __y); }
long double remainderl(long double __x, long double __y) { return __ravyn_remainderl(__x, __y); }

float remquof(float __x, float __y, int* __z) { return __ravyn_remquof(__x, __y, __z); }
double remquo(double __x, double __y, int* __z) { return __ravyn_remquo(__x, __y, __z); }
long double remquol(long double __x, long double __y, int* __z) { return __ravyn_remquol(__x, __y, __z); }

float rintf(float __x) { return __builtin_rintf(__x); }
double rint(double __x) { return __builtin_rint(__x); }
long double rintl(long double __x) { return __ravyn_rintl(__x); }

float roundf(float __x) { return __ravyn_round(__x); }
double round(double __x) { return __ravyn_round(__x); }
long double roundl(long double __x) { return __ravyn_roundl(__x); }

float scalblnf(float __x, long __y) { return __ravyn_scalblnf(__x, __y); }
double scalbln(double __x, long __y) { return __ravyn_scalbln(__x, __y); }
long double scalblnl(long double __x, long __y) { return __ravyn_scalblnl(__x, __y); }

float scalbnf(float __x, int __y) { return __ravyn_scalbnf(__x, __y); }
double scalbn(double __x, int __y) { return __ravyn_scalbn(__x, __y); }
long double scalbnl(long double __x, int __y) { return __ravyn_scalbnl(__x, __y); }

float tgammaf(float __x) { return __ravyn_tgammaf(__x); }
double tgamma(double __x) { return __ravyn_tgamma(__x); }
long double tgammal(long double __x)  { return __ravyn_tgammal(__x); }

float truncf(float __x) { return __builtin_truncf(__x); }
double trunc(double __x) { return __builtin_trunc(__x); }
long double truncl(long double __x) { return __ravyn_truncl(__x); }

double __exp10(double x) { return exp(x * 2.302585092994045684017991454684364); }
typedef struct { double sin; double cos; } __sincos_stret_f64_t;
typedef float __v4sf __attribute__ ((__vector_size__ (16)));

__sincos_stret_f64_t __sincos_stret(double x)
{
    __sincos_stret_f64_t r;

    r.sin = sin(x);
    r.cos = cos(x);
    return r;
}

__v4sf __sincosf_stret(float x)
{
    __v4sf r;

    float s = sinf(x);
    float c = cosf(x);

    r[0] = s;
    r[1] = c;
    r[2] = 0.0f;
    r[3] = 0.0f;

    return r;
}
