#ifndef _STDLIB_H_
#define _STDLIB_H_
#include <stddef.h>
#include <stdint.h>
#include <Availability.h>
/* Minimal kernel stub for <stdlib.h> - kernel should not use user-space stdlib */
#ifndef NULL
#define NULL ((void*)0)
#endif
__BEGIN_DECLS
void *malloc(size_t);
void *calloc(size_t, size_t);
void free(void *);
void abort(void);
unsigned long strtoul(const char *__restrict, char **__restrict, int);
__END_DECLS
#endif
