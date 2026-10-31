/*
 * be16dec/be16enc/... for libbsm.
 *
 * libbsm's token encoder calls the FreeBSD byte-order helpers, which this
 * libc does not export (Darwin keeps them in the kernel headers only).  They
 * are four-line functions; implementing them here keeps libbsm free of a new
 * dependency for them.
 */
/*
 * stdint.h in the launchd build resolves through a shim that leaves bsm_u16
 * and friends undefined, so use plain integer types with the same width on
 * this ABI.  unsigned short is bsm_u16, unsigned int is bsm_u32, and
 * unsigned long long is bsm_u64 on x86_64 Darwin.
 */
/* force_compat.h defines be16dec()/be32enc()/... as macros for the launchd
 * build; this file is where the real functions live, so cancel them here. */
#undef be16dec
#undef be32dec
#undef be64dec
#undef be16enc
#undef be32enc
#undef be64enc

typedef unsigned char bsm_u8;
typedef unsigned short bsm_u16;
typedef unsigned int bsm_u32;
typedef unsigned long long bsm_u64;

bsm_u16 be16dec(const void *pp)
{
	const bsm_u8 *p = (const bsm_u8 *)pp;
	return (bsm_u16)((p[0] << 8) | p[1]);
}

bsm_u32 be32dec(const void *pp)
{
	const bsm_u8 *p = (const bsm_u8 *)pp;
	return ((bsm_u32)p[0] << 24) | ((bsm_u32)p[1] << 16) |
	       ((bsm_u32)p[2] << 8) | (bsm_u32)p[3];
}

bsm_u64 be64dec(const void *pp)
{
	const bsm_u8 *p = (const bsm_u8 *)pp;
	return ((bsm_u64)be32dec(p) << 32) | be32dec(p + 4);
}

void be16enc(void *pp, bsm_u16 u)
{
	bsm_u8 *p = (bsm_u8 *)pp;
	p[0] = (bsm_u8)(u >> 8);
	p[1] = (bsm_u8)u;
}

void be32enc(void *pp, bsm_u32 u)
{
	bsm_u8 *p = (bsm_u8 *)pp;
	p[0] = (bsm_u8)(u >> 24);
	p[1] = (bsm_u8)(u >> 16);
	p[2] = (bsm_u8)(u >> 8);
	p[3] = (bsm_u8)u;
}

void be64enc(void *pp, bsm_u64 u)
{
	bsm_u8 *p = (bsm_u8 *)pp;
	be32enc(p, (bsm_u32)(u >> 32));
	be32enc(p + 4, (bsm_u32)u);
}
