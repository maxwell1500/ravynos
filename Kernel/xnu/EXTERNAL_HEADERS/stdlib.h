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
void free(void *);
unsigned long strtoul(const char *__restrict, char **__restrict, unsigned);
__END_DECLS
#endif
