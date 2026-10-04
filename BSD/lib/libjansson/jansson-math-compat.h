/*
 * jansson-math-compat.h -- build shim for libjansson.
 *
 * The ravynOS build SDK's <math.h> ("Minimal math.h for ravynOS") declares
 * isnan() and isinf() as ordinary functions but does not provide the C99
 * type-generic macros of the same name.  jansson's src/value.c guards its own
 * fallback definitions with `#ifndef isnan` / `#ifndef isinf`, so without the
 * macros it emits a static definition that clashes with the SDK declaration:
 *
 *   contrib/jansson/src/value.c:33:24: error: static declaration of 'isnan'
 *       follows non-static declaration
 *
 * C99 requires isnan/isinf to be macros, and Apple's <math.h> defines them
 * (which is why upstream jansson builds unmodified on macOS).  This header is
 * force-included so the macros exist after <math.h> has been parsed, without
 * editing jansson's sources or the SDK.  The definitions expand to clang's
 * builtins, which is what the SDK functions themselves return.
 */
#ifndef JANSSON_MATH_COMPAT_H
#define JANSSON_MATH_COMPAT_H

#include <math.h>

#ifndef isnan
#define isnan(x) __builtin_isnan(x)
#endif
#ifndef isinf
#define isinf(x) __builtin_isinf(x)
#endif

#endif /* JANSSON_MATH_COMPAT_H */
