/*-
 * SHA-512 (FIPS 180-4), self-contained.
 *
 * Derived from sudo's sha2.c (ISC licence, Todd C. Miller), itself derived
 * from the public domain SHA-2 implementation by Wei Dai.  Only the SHA-512
 * path is kept; libcrypt's $6$ scheme needs exactly that.
 */
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "sha512.h"

#define BE8TO64(x, y) do {				\
	(x) = (((uint64_t)((y)[0] & 255) << 56) |	\
	       ((uint64_t)((y)[1] & 255) << 48) |	\
	       ((uint64_t)((y)[2] & 255) << 40) |	\
	       ((uint64_t)((y)[3] & 255) << 32) |	\
	       ((uint64_t)((y)[4] & 255) << 24) |	\
	       ((uint64_t)((y)[5] & 255) << 16) |	\
	       ((uint64_t)((y)[6] & 255) << 8)  |	\
	       ((uint64_t)((y)[7] & 255)));		\
} while (0)

#define BE64TO8(x, y) do {			\
	(x)[0] = (uint8_t)(((y) >> 56) & 255);	\
	(x)[1] = (uint8_t)(((y) >> 48) & 255);	\
	(x)[2] = (uint8_t)(((y) >> 40) & 255);	\
	(x)[3] = (uint8_t)(((y) >> 32) & 255);	\
	(x)[4] = (uint8_t)(((y) >> 24) & 255);	\
	(x)[5] = (uint8_t)(((y) >> 16) & 255);	\
	(x)[6] = (uint8_t)(((y) >> 8) & 255);	\
	(x)[7] = (uint8_t)((y) & 255);		\
} while (0)

#define rotrFixed(x,y) (y ? ((x>>y) | (x<<(sizeof(x)*8-y))) : x)

#define blk0(i) (W[i])
#define blk2(i) (W[i&15]+=s1(W[(i-2)&15])+W[(i-7)&15]+s0(W[(i-15)&15]))

#define Ch(x,y,z) (z^(x&(y^z)))
#define Maj(x,y,z) (y^((x^y)&(y^z)))

#define a(i) T[(0-i)&7]
#define b(i) T[(1-i)&7]
#define c(i) T[(2-i)&7]
#define d(i) T[(3-i)&7]
#define e(i) T[(4-i)&7]
#define f(i) T[(5-i)&7]
#define g(i) T[(6-i)&7]
#define h(i) T[(7-i)&7]

static const uint64_t SHA512_K[80] = {
	0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL,
	0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
	0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL,
	0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
	0xd807aa98a3030242ULL, 0x12835b0145706fbeULL,
	0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
	0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL,
	0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
	0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL,
	0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
	0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL,
	0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
	0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL,
	0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
	0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
	0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
	0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL,
	0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
	0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL,
	0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
	0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL,
	0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
	0xd192e819d6ef5218ULL, 0xd69906245565a910ULL,
	0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
	0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL,
	0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
	0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL,
	0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
	0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL,
	0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
	0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL,
	0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
	0xca273eceea26619cULL, 0xd186b8c721c0c207ULL,
	0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
	0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL,
	0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
	0x28db77f523047d84ULL, 0x32caab7b40c72493ULL,
	0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
	0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL,
	0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

/* Round macros for SHA512 */
#define R(i) do {							     \
	h(i)+=S1(e(i))+Ch(e(i),f(i),g(i))+SHA512_K[i+j]+(j?blk2(i):blk0(i)); \
	d(i)+=h(i);							     \
	h(i)+=S0(a(i))+Maj(a(i),b(i),c(i));				     \
} while (0)

#define S0(x) (rotrFixed(x,28)^rotrFixed(x,34)^rotrFixed(x,39))
#define S1(x) (rotrFixed(x,14)^rotrFixed(x,18)^rotrFixed(x,41))
#define s0(x) (rotrFixed(x,1)^rotrFixed(x,8)^(x>>7))
#define s1(x) (rotrFixed(x,19)^rotrFixed(x,61)^(x>>6))

void
SHA512_Init(SHA512_CTX *ctx)
{
	memset(ctx, 0, sizeof(*ctx));
	ctx->state[0] = 0x6a09e667f3bcc908ULL;
	ctx->state[1] = 0xbb67ae8584caa73bULL;
	ctx->state[2] = 0x3c6ef372fe94f82bULL;
	ctx->state[3] = 0xa54ff53a5f1d36f1ULL;
	ctx->state[4] = 0x510e527fade682d1ULL;
	ctx->state[5] = 0x9b05688c2b3e6c1fULL;
	ctx->state[6] = 0x1f83d9abfb41bd6bULL;
	ctx->state[7] = 0x5be0cd19137e2179ULL;
}

static void
SHA512_Transform(uint64_t state[8], const uint8_t data[128])
{
	uint64_t W[16];
	uint64_t T[8];
	unsigned int j;

	memcpy(T, state, sizeof(T));
	for (j = 0; j < 16; j++) {
		BE8TO64(W[j], data);
		data += 8;
	}
	for (j = 0; j < 80; j += 16) {
		R( 0); R( 1); R( 2); R( 3);
		R( 4); R( 5); R( 6); R( 7);
		R( 8); R( 9); R(10); R(11);
		R(12); R(13); R(14); R(15);
	}
	state[0] += a(0);
	state[1] += b(0);
	state[2] += c(0);
	state[3] += d(0);
	state[4] += e(0);
	state[5] += f(0);
	state[6] += g(0);
	state[7] += h(0);
	memset(T, 0, sizeof(T));
	memset(W, 0, sizeof(W));
}

void
SHA512_Update(SHA512_CTX *ctx, const void *_data, size_t len)
{
	const uint8_t *data = _data;
	size_t i = 0, j;

	j = (size_t)((ctx->count[0] >> 3) & 127);
	ctx->count[0] += ((uint64_t)len << 3);
	if (ctx->count[0] < ((uint64_t)len << 3))
		ctx->count[1]++;
	if ((j + len) > 127) {
		memcpy(&ctx->buffer[j], data, (i = 128 - j));
		SHA512_Transform(ctx->state, ctx->buffer);
		for ( ; i + 127 < len; i += 128)
			SHA512_Transform(ctx->state, &data[i]);
		j = 0;
	}
	memcpy(&ctx->buffer[j], &data[i], len - i);
}

void
SHA512_Final(uint8_t digest[64], SHA512_CTX *ctx)
{
	uint8_t finalcount[16];
	unsigned int i;

	BE64TO8(finalcount, ctx->count[1]);
	BE64TO8(finalcount + 8, ctx->count[0]);

	SHA512_Update(ctx, "\200", 1);
	while ((ctx->count[0] & 1023) != 896)
		SHA512_Update(ctx, "\0", 1);
	SHA512_Update(ctx, finalcount, sizeof(finalcount));

	for (i = 0; i < 8; i++)
		BE64TO8(digest + (i * 8), ctx->state[i]);
	memset(ctx, 0, sizeof(*ctx));
}
