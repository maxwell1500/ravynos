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
#include <errno.h>

bool signbit(double __x) { return __builtin_signbit(__x); }
int fpclassify(double __x) {
  return __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, __x);
}
bool isfinite(double __x) { return __builtin_isfinite(__x); }
bool isinf(double __x) { return __builtin_isinf(__x); }
bool isnan(double __x) { return __builtin_isnan(__x); }
bool isnormal(double __x) { return __builtin_isnormal(__x); }
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


float frexpf(float __x, int* __e) { return __builtin_frexpf(__x, __e); }
double frexp(double __x, int* __e) { return __builtin_frexp(__x, __e); }
long double frexpl(long double __x, int* __e) { return __builtin_frexpl(__x, __e); }

float ldexpf(float __x, int __e) { return __builtin_ldexpf(__x, __e); }
double ldexp(double __x, int __e) { return __builtin_ldexp(__x, __e); }
long double ldexpl(long double __x, int __e) { return __builtin_ldexpl(__x, __e); }

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

float modff(float __x, float* __y) { return __builtin_modff(__x, __y); }
double modf(double __x, double* __y)  { return __builtin_modf(__x, __y); }
long double modfl(long double __x, long double* __y) { return __builtin_modfl(__x, __y); }

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
float acoshf(float __x) { return __builtin_acoshf(__x); }
double acosh(double __x) { return __builtin_acosh(__x); }
long double acoshl(long double __x) { return __builtin_acoshl(__x); }

float asinhf(float __x) { return __builtin_asinhf(__x); }
double asinh(double __x) { return __builtin_asinh(__x); }
long double asinhl(long double __x) { return __builtin_asinhl(__x); }

float atanhf(float __x) { return __builtin_atanhf(__x); }
double atanh(double __x) { return __builtin_atanh(__x); }
long double atanhl(long double __x) { return __builtin_atanhl(__x); }

float cbrtf(float __x) { return __builtin_cbrtf(__x); }
double cbrt(double __x) { return __builtin_cbrt(__x); }
long double cbrtl(long double __x) { return __builtin_cbrtl(__x); }

double copysignf(float __x, float __y) { return __builtin_copysignf(__x, __y); }
double copysign(double __x, double __y) { return __builtin_copysign(__x, __y); }
long double copysignl(long double __x, long double __y) { return __builtin_copysignl(__x, __y); }

float erff(float __x) { return __builtin_erff(__x); }
double erf(double __x) { return __builtin_erf(__x); }
long double erfl(long double __x) { return __builtin_erfl(__x); }

float erfcf(float __x) { return __builtin_erfcf(__x); }
double erfc(double __x) { return __builtin_erfc(__x); }
long double erfcl(long double __x) { return __builtin_erfcl(__x); }

float exp2f(float __x) { return __builtin_exp2f(__x); }
double exp2(double __x) { return __builtin_exp2(__x); }
long double exp2l(long double __x) { return __builtin_exp2l(__x); }

float expm1f(float __x) { return __builtin_expm1f(__x); }
double expm1(double __x) { return __builtin_expm1(__x); }
long double expm1l(long double __x) { return __builtin_expm1l(__x); }

float fdimf(float __x, float __y) { return __builtin_fdimf(__x, __y); }
double fdim(double __x, double __y) { return __builtin_fdim(__x, __y); }
long double fdiml(long double __x, long double __y) { return __builtin_fdiml(__x, __y); }

float fmaf(float __x, float __y, float __z) { return __builtin_fmaf(__x, __y, __z); }
double fma(double __x, double __y, double __z) { return __builtin_fma(__x, __y, __z); }
long double fmal(long double __x, long double __y, long double __z) { return __builtin_fmal(__x, __y, __z); }

float fmaxf(float __x, float __y) { return __builtin_fmaxf(__x, __y); }
double fmax(double __x, double __y) { return __builtin_fmax(__x, __y); }
long double fmaxl(long double __x, long double __y) { return __builtin_fmaxl(__x, __y); }

float fminf(float __x, float __y) { return __builtin_fminf(__x, __y); }
double fmin(double __x, double __y) { return __builtin_fmin(__x, __y); }
long double fminl(long double __x, long double __y) { return __builtin_fminl(__x, __y); }

float hypotf(float __x, float __y) { return __builtin_hypotf(__x, __y); }
double hypot(double __x, double __y) { return __builtin_hypot(__x, __y); }
long double hypotl(long double __x, long double __y) { return __builtin_hypotl(__x, __y); }

int ilogbf(float __x) { return __builtin_ilogbf(__x); }
double ilogb(double __x) { return __builtin_ilogb(__x); }
int ilogbl(long double __x) { return __builtin_ilogbl(__x); }

float lgammaf(float __x) { return __builtin_lgammaf(__x); }
double lgamma(double __x) { return __builtin_lgamma(__x); }
long double lgammal(long double __x) { return __builtin_lgammal(__x); }

long long llrintf(float __x) { return __builtin_llrintf(__x); }
long long llrint(double __x) { return __builtin_llrint(__x); }
long long llrintl(long double __x) { return __builtin_llrintl(__x); }

long long llroundf(float __x) { return __builtin_llroundf(__x); }
long long llround(double __x) { return __builtin_llround(__x); }
long long llroundl(long double __x) { return __builtin_llroundl(__x); }

float log1pf(float __x) { return __builtin_log1pf(__x); }
double log1p(double __x) { return __builtin_log1p(__x); }
long double log1pl(long double __x) { return __builtin_log1pl(__x); }

float log2f(float __x) { return __builtin_log2f(__x); }
double log2(double __x) { return __builtin_log2(__x); }
long double log2l(long double __x) { return __builtin_log2l(__x); }

float logbf(float __x) { return __builtin_logbf(__x); }
double logb(double __x) { return __builtin_logb(__x); }
long double logbl(long double __x) { return __builtin_logbl(__x); }

long lrintf(float __x) { return __builtin_lrintf(__x); }
long lrint(double __x) { return __builtin_lrint(__x); }
long lrintl(long double __x) { return __builtin_lrintl(__x); }

long lroundf(float __x) { return __builtin_lroundf(__x); }
long lround(double __x) { return __builtin_lround(__x); }
long lroundl(long double __x) { return __builtin_lroundl(__x); }

float nanf(const char * __s) { return __builtin_nan(__s); }
double nan(const char * __s) { return __builtin_nan(__s); }
long double nanl(const char * __s) { return __builtin_nan(__s); }

float nearbyintf(float __x) { return __builtin_nearbyintf(__x); }
double nearbyint(double __x) { return __builtin_nearbyint(__x); }
long double nearbyintl(long double __x) { return __builtin_nearbyintl(__x); }

float nextafterf(float __x, float __y) { return __builtin_nextafterf(__x, __y); }
double nextafter(double __x, double __y) { return __builtin_nextafter(__x, __y); }
long double nextafterl(long double __x, long double __y)  { return __builtin_nextafterl(__x, __y); }

float nexttowardf(float __x, long double __y) { return __builtin_nexttowardf(__x, __y); }
double nexttoward(double __x, long double __y) { return __builtin_nexttoward(__x, __y); }
long double nexttowardl(long double __x, long double __y) { return __builtin_nexttowardl(__x, __y); }

float remainderf(float __x, float __y) { return __builtin_remainderf(__x, __y); }
double remainder(double __x, double __y) { return __builtin_remainder(__x, __y); }
long double remainderl(long double __x, long double __y) { return __builtin_remainderl(__x, __y); }

float remquof(float __x, float __y, int* __z) { return __builtin_remquof(__x, __y, __z); }
double remquo(double __x, double __y, int* __z) { return __builtin_remquo(__x, __y, __z); }
long double remquol(long double __x, long double __y, int* __z) { return __builtin_remquol(__x, __y, __z); }

float rintf(float __x) { return __builtin_rintf(__x); }
double rint(double __x) { return __builtin_rint(__x); }
long double rintl(long double __x) { return __builtin_rintl(__x); }

float roundf(float __x) { return __builtin_round(__x); }
double round(double __x) { return __builtin_round(__x); }
long double roundl(long double __x) { return __builtin_roundl(__x); }

float scalblnf(float __x, long __y) { return __builtin_scalblnf(__x, __y); }
double scalbln(double __x, long __y) { return __builtin_scalbln(__x, __y); }
long double scalblnl(long double __x, long __y) { return __builtin_scalblnl(__x, __y); }

float scalbnf(float __x, int __y) { return __builtin_scalbnf(__x, __y); }
double scalbn(double __x, int __y) { return __builtin_scalbn(__x, __y); }
long double scalbnl(long double __x, int __y) { return __builtin_scalbnl(__x, __y); }

float tgammaf(float __x) { return __builtin_tgammaf(__x); }
double tgamma(double __x) { return __builtin_tgamma(__x); }
long double tgammal(long double __x)  { return __builtin_tgammal(__x); }

float truncf(float __x) { return __builtin_truncf(__x); }
double trunc(double __x) { return __builtin_trunc(__x); }
long double truncl(long double __x) { return __builtin_truncl(__x); }

double __exp10(double x) { return 0.0; } // FIXME: implement this

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
