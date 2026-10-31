/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2011 The FreeBSD Project. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/* Based on:
 * SHA512-based Unix crypt implementation. Released into the Public Domain by
 * Ulrich Drepper <drepper@redhat.com>. */

#include <sys/cdefs.h>
#include <sys/endian.h>
#include <sys/param.h>

#include <errno.h>
#include <limits.h>
#include "sha512.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

int crypt_sha512(const char *pw, const char *salt, char *buf);

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

static const char itoa64[] =
    "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

static void
b64_from_24bit(uint8_t B2, uint8_t B1, uint8_t B0, int n, char **cp)
{
	uint32_t w;
	int i;

	w = ((uint32_t)B2 << 16) | ((uint32_t)B1 << 8) | B0;
	for (i = 0; i < n; i++) {
		**cp = itoa64[w & 0x3f];
		(*cp)++;
		w >>= 6;
	}
}

/* Define our magic string to mark salt for SHA512 "encryption" replacement. */
static const char sha512_salt_prefix[] = "$6$";

/* Prefix for optional rounds specification. */
static const char sha512_rounds_prefix[] = "rounds=";

/* Maximum salt string length. */
#define SALT_LEN_MAX 16
/* Default number of rounds if not explicitly specified. */
#define ROUNDS_DEFAULT 5000
/* Minimum number of rounds. */
#define ROUNDS_MIN 1000
/* Maximum number of rounds. */
#define ROUNDS_MAX 999999999

int
crypt_sha512(const char *key, const char *salt, char *buffer)
{
	u_long srounds;
	uint8_t alt_result[64], temp_result[64];
	SHA512_CTX ctx, alt_ctx;
	size_t salt_len, key_len, cnt, rounds;
	char *cp, *p_bytes, *s_bytes, *endp;
	const char *num;
	bool rounds_custom;

	/* Default number of rounds. */
	rounds = ROUNDS_DEFAULT;
	rounds_custom = false;

	/* Find beginning of salt string. The prefix should normally always
	 * be present. Just in case it is not. */
	if (strncmp(sha512_salt_prefix, salt, sizeof(sha512_salt_prefix) - 1) == 0)
		/* Skip salt prefix. */
		salt += sizeof(sha512_salt_prefix) - 1;

	if (strncmp(salt, sha512_rounds_prefix, sizeof(sha512_rounds_prefix) - 1)
	    == 0) {
		num = salt + sizeof(sha512_rounds_prefix) - 1;
		srounds = strtoul(num, &endp, 10);

		if (*endp == '$') {
			salt = endp + 1;
			rounds = MAX(ROUNDS_MIN, MIN(srounds, ROUNDS_MAX));
			rounds_custom = true;
		}
	}

	salt_len = MIN(strcspn(salt, "$"), SALT_LEN_MAX);
	key_len = strlen(key);

	/* Prepare for the real work. */
	SHA512_Init(&ctx);

	/* Add the key string. */
	SHA512_Update(&ctx, key, key_len);

	/* The last part is the salt string. This must be at most 8
	 * characters and it ends at the first `$' character (for
	 * compatibility with existing implementations). */
	SHA512_Update(&ctx, salt, salt_len);

	/* Compute alternate SHA512 sum with input KEY, SALT, and KEY. The
	 * final result will be added to the first context. */
	SHA512_Init(&alt_ctx);

	/* Add key. */
	SHA512_Update(&alt_ctx, key, key_len);

	/* Add salt. */
	SHA512_Update(&alt_ctx, salt, salt_len);

	/* Add key again. */
	SHA512_Update(&alt_ctx, key, key_len);

	/* Now get result of this (64 bytes) and add it to the other context. */
	SHA512_Final(alt_result, &alt_ctx);

	/* Add for any character in the key one byte of the alternate sum. */
	for (cnt = key_len; cnt > 64; cnt -= 64)
		SHA512_Update(&ctx, alt_result, 64);
	SHA512_Update(&ctx, alt_result, cnt);

	/* Take the binary representation of the length of the key and for
	 * every 1 add the alternate sum, for every 0 the key. */
	for (cnt = key_len; cnt > 0; cnt >>= 1)
		if ((cnt & 1) != 0)
			SHA512_Update(&ctx, alt_result, 64);
		else
			SHA512_Update(&ctx, key, key_len);

	/* Create intermediate result. */
	SHA512_Final(alt_result, &ctx);

	/* Start computation of P byte sequence. */
	SHA512_Init(&alt_ctx);

	/* For every character in the password add the entire password. */
	for (cnt = 0; cnt < key_len; ++cnt)
		SHA512_Update(&alt_ctx, key, key_len);

	/* Finish the digest. */
	SHA512_Final(temp_result, &alt_ctx);

	/* Create byte sequence P. */
	cp = p_bytes = alloca(key_len);
	for (cnt = key_len; cnt >= 64; cnt -= 64) {
		memcpy(cp, temp_result, 64);
		cp += 64;
	}
	memcpy(cp, temp_result, cnt);

	/* Start computation of S byte sequence. */
	SHA512_Init(&alt_ctx);

	/* For every character in the password add the entire password. */
	for (cnt = 0; cnt < 16 + alt_result[0]; ++cnt)
		SHA512_Update(&alt_ctx, salt, salt_len);

	/* Finish the digest. */
	SHA512_Final(temp_result, &alt_ctx);

	/* Create byte sequence S. */
	cp = s_bytes = alloca(salt_len);
	for (cnt = salt_len; cnt >= 64; cnt -= 64) {
		memcpy(cp, temp_result, 64);
		cp += 64;
	}
	memcpy(cp, temp_result, cnt);

	/* Repeatedly run the collected hash value through SHA512 to burn CPU
	 * cycles. */
	for (cnt = 0; cnt < rounds; ++cnt) {
		/* New context. */
		SHA512_Init(&ctx);

		/* Add key or last result. */
		if ((cnt & 1) != 0)
			SHA512_Update(&ctx, p_bytes, key_len);
		else
			SHA512_Update(&ctx, alt_result, 64);

		/* Add salt for numbers not divisible by 3. */
		if (cnt % 3 != 0)
			SHA512_Update(&ctx, s_bytes, salt_len);

		/* Add key for numbers not divisible by 7. */
		if (cnt % 7 != 0)
			SHA512_Update(&ctx, p_bytes, key_len);

		/* Add key or last result. */
		if ((cnt & 1) != 0)
			SHA512_Update(&ctx, alt_result, 64);
		else
			SHA512_Update(&ctx, p_bytes, key_len);

		/* Create intermediate result. */
		SHA512_Final(alt_result, &ctx);
	}

	/* Now we can construct the result string. It consists of three
	 * parts. */
	cp = stpcpy(buffer, sha512_salt_prefix);

	if (rounds_custom)
		cp += sprintf(cp, "%s%zu$", sha512_rounds_prefix, rounds);

	cp = stpncpy(cp, salt, salt_len);

	*cp++ = '$';

	b64_from_24bit(alt_result[0], alt_result[21], alt_result[42], 4, &cp);
	b64_from_24bit(alt_result[22], alt_result[43], alt_result[1], 4, &cp);
	b64_from_24bit(alt_result[44], alt_result[2], alt_result[23], 4, &cp);
	b64_from_24bit(alt_result[3], alt_result[24], alt_result[45], 4, &cp);
	b64_from_24bit(alt_result[25], alt_result[46], alt_result[4], 4, &cp);
	b64_from_24bit(alt_result[47], alt_result[5], alt_result[26], 4, &cp);
	b64_from_24bit(alt_result[6], alt_result[27], alt_result[48], 4, &cp);
	b64_from_24bit(alt_result[28], alt_result[49], alt_result[7], 4, &cp);
	b64_from_24bit(alt_result[50], alt_result[8], alt_result[29], 4, &cp);
	b64_from_24bit(alt_result[9], alt_result[30], alt_result[51], 4, &cp);
	b64_from_24bit(alt_result[31], alt_result[52], alt_result[10], 4, &cp);
	b64_from_24bit(alt_result[53], alt_result[11], alt_result[32], 4, &cp);
	b64_from_24bit(alt_result[12], alt_result[33], alt_result[54], 4, &cp);
	b64_from_24bit(alt_result[34], alt_result[55], alt_result[13], 4, &cp);
	b64_from_24bit(alt_result[56], alt_result[14], alt_result[35], 4, &cp);
	b64_from_24bit(alt_result[15], alt_result[36], alt_result[57], 4, &cp);
	b64_from_24bit(alt_result[37], alt_result[58], alt_result[16], 4, &cp);
	b64_from_24bit(alt_result[59], alt_result[17], alt_result[38], 4, &cp);
	b64_from_24bit(alt_result[18], alt_result[39], alt_result[60], 4, &cp);
	b64_from_24bit(alt_result[40], alt_result[61], alt_result[19], 4, &cp);
	b64_from_24bit(alt_result[62], alt_result[20], alt_result[41], 4, &cp);
	b64_from_24bit(0, 0, alt_result[63], 2, &cp);

	*cp = '\0';	/* Terminate the string. */

	/* Clear the buffer for the intermediate result so that people
	 * attaching to processes or reading core dumps cannot get any
	 * information. We do it in this way to clear correct_words[] inside
	 * the SHA512 implementation as well. */
	SHA512_Init(&ctx);
	SHA512_Final(alt_result, &ctx);
	memset(temp_result, 0, sizeof(temp_result));
	memset(p_bytes, 0, key_len);
	memset(s_bytes, 0, salt_len);

	return (0);
}

