/* SPDX-License-Identifier: BSD-2-Clause */
/* Minimal libmd-compatible MD5 for the BSD programs that use it (sort's
 * random-key hash, and tools that only need a digest).  This is the RFC 1321
 * algorithm; the ABI matches <md5.h> so FreeBSD sources compile unchanged. */
#include <sys/types.h>

#include <stdint.h>
#include <string.h>

#include <md5.h>

#define F(x, y, z) (((x) & (y)) | (~(x) & (z)))
#define G(x, y, z) (((x) & (z)) | ((y) & ~(z)))
#define H(x, y, z) ((x) ^ (y) ^ (z))
#define I(x, y, z) ((y) ^ ((x) | ~(z)))
#define ROTL(x, n) (((x) << (n)) | ((x) >> (32 - (n))))

static const uint32_t K[64] = {
	0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
	0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
	0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
	0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
	0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
	0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
	0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
	0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
	0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
	0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
	0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
	0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
	0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
	0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
	0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
	0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
};

static const unsigned S[64] = {
	7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
	5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
	4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
	6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
};

static void
md5_block(MD5_CTX *ctx, const unsigned char *p)
{
	uint32_t a = ctx->state[0], b = ctx->state[1];
	uint32_t c = ctx->state[2], d = ctx->state[3];
	uint32_t m[16];
	int i;

	for (i = 0; i < 16; i++)
		m[i] = (uint32_t)p[i * 4] | (uint32_t)p[i * 4 + 1] << 8 |
		    (uint32_t)p[i * 4 + 2] << 16 | (uint32_t)p[i * 4 + 3] << 24;
	for (i = 0; i < 64; i++) {
		uint32_t f, g, tmp;

		if (i < 16) {
			f = F(b, c, d);
			g = (uint32_t)i;
		} else if (i < 32) {
			f = G(b, c, d);
			g = (uint32_t)(5 * i + 1) & 15;
		} else if (i < 48) {
			f = H(b, c, d);
			g = (uint32_t)(3 * i + 5) & 15;
		} else {
			f = I(b, c, d);
			g = (uint32_t)(7 * i) & 15;
		}
		tmp = d;
		d = c;
		c = b;
		b = b + ROTL(a + f + K[i] + m[g], S[i]);
		a = tmp;
	}
	ctx->state[0] += a;
	ctx->state[1] += b;
	ctx->state[2] += c;
	ctx->state[3] += d;
}

void
MD5Init(MD5_CTX *ctx)
{
	ctx->state[0] = 0x67452301;
	ctx->state[1] = 0xefcdab89;
	ctx->state[2] = 0x98badcfe;
	ctx->state[3] = 0x10325476;
	ctx->count[0] = ctx->count[1] = 0;
}

void
MD5Update(MD5_CTX *ctx, const void *data, size_t len)
{
	const unsigned char *p = data;
	size_t have = (size_t)(ctx->count[0] >> 3) & 63;
	uint32_t old = ctx->count[0];

	if ((ctx->count[0] += (uint32_t)(len << 3)) < old)
		ctx->count[1]++;
	ctx->count[1] += (uint32_t)(len >> 29);
	if (have != 0) {
		size_t need = 64 - have;

		if (len < need) {
			memcpy(ctx->buffer + have, p, len);
			return;
		}
		memcpy(ctx->buffer + have, p, need);
		md5_block(ctx, ctx->buffer);
		p += need;
		len -= need;
	}
	while (len >= 64) {
		md5_block(ctx, p);
		p += 64;
		len -= 64;
	}
	if (len != 0)
		memcpy(ctx->buffer, p, len);
}

void
MD5Final(unsigned char digest[MD5_DIGEST_LENGTH], MD5_CTX *ctx)
{
	unsigned char pad[72];
	uint32_t bits0 = ctx->count[0], bits1 = ctx->count[1];
	size_t have = (size_t)(ctx->count[0] >> 3) & 63;
	size_t padlen = have < 56 ? 56 - have : 120 - have;
	int i;

	memset(pad, 0, sizeof(pad));
	pad[0] = 0x80;
	for (i = 0; i < 8; i++)
		pad[padlen + i] = (unsigned char)((i < 4 ? bits0 : bits1) >>
		    (8 * (i & 3)));
	MD5Update(ctx, pad, padlen + 8);
	for (i = 0; i < 4; i++) {
		digest[i * 4] = (unsigned char)ctx->state[i];
		digest[i * 4 + 1] = (unsigned char)(ctx->state[i] >> 8);
		digest[i * 4 + 2] = (unsigned char)(ctx->state[i] >> 16);
		digest[i * 4 + 3] = (unsigned char)(ctx->state[i] >> 24);
	}
}

char *
MD5End(MD5_CTX *ctx, char *buf)
{
	static const char hex[] = "0123456789abcdef";
	unsigned char digest[MD5_DIGEST_LENGTH];
	int i;

	MD5Final(digest, ctx);
	for (i = 0; i < MD5_DIGEST_LENGTH; i++) {
		buf[i * 2] = hex[digest[i] >> 4];
		buf[i * 2 + 1] = hex[digest[i] & 15];
	}
	buf[MD5_DIGEST_LENGTH * 2] = '\0';
	return buf;
}
