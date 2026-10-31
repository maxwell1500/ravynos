/* SHA-512 context, internal to libsystem_c's crypt(3). */
#ifndef _LIBSYSTEM_C_SHA512_H_
#define _LIBSYSTEM_C_SHA512_H_

#include <stddef.h>
#include <stdint.h>

typedef struct {
	uint64_t count[2];
	uint64_t state[8];
	uint8_t buffer[128];
} SHA512_CTX;

void SHA512_Init(SHA512_CTX *);
void SHA512_Update(SHA512_CTX *, const void *, size_t);
void SHA512_Final(uint8_t digest[64], SHA512_CTX *);

#endif
