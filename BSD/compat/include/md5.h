/* SPDX-License-Identifier: BSD-2-Clause */
/* <md5.h> as FreeBSD's libmd exposes it.  The implementation is
 * libutil/md5.c; the SDK has no libmd, and sort(1) (plus any future md5
 * consumer) needs the documented ABI. */
#ifndef _RAVYN_MD5_H_
#define _RAVYN_MD5_H_

#include <sys/types.h>
#include <stdint.h>

#define MD5_DIGEST_LENGTH 16
#define MD5_DIGEST_STRING_LENGTH (MD5_DIGEST_LENGTH * 2 + 1)

typedef struct MD5Context {
	uint32_t state[4];
	uint32_t count[2];
	unsigned char buffer[64];
} MD5_CTX;

#ifdef __cplusplus
extern "C" {
#endif
void MD5Init(MD5_CTX *);
void MD5Update(MD5_CTX *, const void *, size_t);
void MD5Final(unsigned char[MD5_DIGEST_LENGTH], MD5_CTX *);
char *MD5End(MD5_CTX *, char *);
#ifdef __cplusplus
}
#endif

#endif
