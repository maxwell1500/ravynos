#ifndef _STDLINT_H_
#define _STDLINT_H_

#include <stddef.h>
#include <sys/cdefs.h>

/* Exact-width integer types - use compiler builtins */
typedef signed char       int8_t;
typedef short             int16_t;
typedef int               int32_t;
typedef long long         int64_t;

typedef unsigned char     uint8_t;
typedef unsigned short    uint16_t;
typedef unsigned int      uint32_t;
typedef unsigned long long uint64_t;

/* Least-width integer types */
typedef int8_t    int_least8_t;
typedef int16_t   int_least16_t;
typedef int32_t   int_least32_t;
typedef int64_t   int_least64_t;

typedef uint8_t   uint_least8_t;
typedef uint16_t  uint_least16_t;
typedef uint32_t  uint_least32_t;
typedef uint64_t  uint_least64_t;

/* Smallest-width integer types */
typedef int8_t    int_fast8_t;
typedef int32_t   int_fast16_t;
typedef int32_t   int_fast32_t;
typedef int64_t   int_fast64_t;

typedef uint8_t   uint_fast8_t;
typedef uint32_t  uint_fast16_t;
typedef uint32_t  uint_fast32_t;
typedef uint64_t  uint_fast64_t;

/* Integer types capable of holding object pointers */
typedef long            intptr_t;
typedef unsigned long   uintptr_t;

/* Greatest-width integer types */
typedef int64_t         intmax_t;
typedef uint64_t        uintmax_t;

/* Minimal kernel stub for <stdint.h> - kernel should not use user-space stdlib */
#ifndef NULL
#define NULL ((void*)0)
#endif


/* Word size for x86_64 */
#define __WORDSIZE 64

/* Maximum/minimum values */
#define UINT8_MAX   0xff
#define UINT16_MAX  0xffff
#define UINT32_MAX  0xffffffffU
#define UINT64_MAX  0xffffffffffffffffULL
#define INT8_MAX    0x7f
#define INT16_MAX   0x7fff
#define INT32_MAX   0x7fffffff
#define INT64_MAX   0x7fffffffffffffffLL
#define INT8_MIN    (-128)
#define INT16_MIN   (-32768)
#define INT32_MIN   (-2147483648)
#define INT64_MIN   (-9223372036854775808LL)
#define UINT8_MIN   0x00
#define UINT16_MIN  0x0000
#define UINT32_MIN  0x00000000U
#define UINT64_MIN  0x0000000000000000ULL
#define INTPTR_MIN  (-9223372036854775808LL)
#define INTPTR_MAX  0x7fffffffffffffffLL
#define UINTPTR_MAX 0xffffffffffffffffULL
#define INTMAX_MAX  0x7fffffffffffffffLL
#define INTMAX_MIN  (-9223372036854775808LL)
#define UINTMAX_MAX 0xffffffffffffffffULL
#define UINTMAX_MIN 0x0000000000000000ULL
#define UINT8_C(x)  (x)
#define UINT16_C(x) (x)
#define UINT32_C(x) (x)
#define UINT64_C(x) (x##ULL)
#define INT8_C(x)   (x)
#define INT16_C(x)  (x)
#define INT32_C(x)  (x)
#define INT64_C(x)  (x##LL)
#define SIZE_MAX  0xffffffffffffffffULL

#endif
