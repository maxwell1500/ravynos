/*
 * be16dec/be16enc/... for libbsm.
 *
 * libbsm's token encoder calls the FreeBSD byte-order helpers, which this
 * libc does not export (Darwin keeps them in the kernel headers only).  They
 * are four-line functions; implementing them here keeps libbsm free of a new
 * dependency for them.
 */
#include <stdint.h>

uint16_t be16dec(const void *pp)
{
	const uint8_t *p = (const uint8_t *)pp;
	return (uint16_t)((p[0] << 8) | p[1]);
}

uint32_t be32dec(const void *pp)
{
	const uint8_t *p = (const uint8_t *)pp;
	return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
	       ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

uint64_t be64dec(const void *pp)
{
	const uint8_t *p = (const uint8_t *)pp;
	return ((uint64_t)be32dec(p) << 32) | be32dec(p + 4);
}

void be16enc(void *pp, uint16_t u)
{
	uint8_t *p = (uint8_t *)pp;
	p[0] = (uint8_t)(u >> 8);
	p[1] = (uint8_t)u;
}

void be32enc(void *pp, uint32_t u)
{
	uint8_t *p = (uint8_t *)pp;
	p[0] = (uint8_t)(u >> 24);
	p[1] = (uint8_t)(u >> 16);
	p[2] = (uint8_t)(u >> 8);
	p[3] = (uint8_t)u;
}

void be64enc(void *pp, uint64_t u)
{
	uint8_t *p = (uint8_t *)pp;
	be32enc(p, (uint32_t)(u >> 32));
	be32enc(p + 4, (uint32_t)u);
}
