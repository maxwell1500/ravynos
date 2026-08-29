#ifndef _MACH_MACHINE_TYPES_H_
#define _MACH_MACHINE_TYPES_H_

#include <stdint.h>
#include <sys/_types.h>

/* u_int/u_long compatibility */
typedef unsigned int    u_int;
typedef int             int_t;
typedef unsigned uint_t;

typedef uint8_t   u_int8_t;
typedef uint16_t  u_int16_t;
typedef uint32_t  u_int32_t;
typedef uint64_t  u_int64_t;

typedef long            intptr_t;
typedef unsigned long   uintptr_t;

/* User address space types (x86_64: 64-bit) */
typedef uint64_t        user_addr_t;
#define CAST_USER_ADDR_T(x)   ((user_addr_t)(x))
typedef uint64_t        user_size_t;
typedef int             user_idx_t;
typedef uint32_t        user32_addr_t;
typedef uint32_t        user32_size_t;
typedef int64_t         user32_off_t;
typedef uint64_t        user64_addr_t;
typedef uint64_t        user64_size_t;
typedef int64_t         user64_ssize_t;
typedef int64_t         user64_long_t;
typedef uint64_t        user64_ulong_t;
typedef int64_t         user64_time_t;
typedef int64_t         user64_off_t;
typedef int64_t         user_long_t;
typedef int64_t         user_time_t;
#define INT64_MIN   (-9223372036854775808LL)
#define user64_time_t  int64_t
#define user64_long_t  int64_t
#define USER_ADDR_NULL  ((user_addr_t)0)
typedef int32_t         user32_long_t;
typedef uint32_t        user32_ulong_t;
#define syscall_arg_t u_int64_t
typedef int32_t         user32_time_t;
/* Word size for x86_64 */
#define __WORDSIZE 64
#endif /* _MACH_MACHINE_TYPES_H_ */
