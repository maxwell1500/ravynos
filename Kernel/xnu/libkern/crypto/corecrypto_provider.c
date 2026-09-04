/*
 * Minimal in-kernel corecrypto provider (RNG subset).
 *
 * Upstream, the corecrypto kext registers the crypto_functions table via
 * register_crypto_functions() when it loads.  This kernel boots monolithic
 * without kexts, so nothing registers it, g_crypto_funcs stays NULL, and
 * kmem_crypto_init (STARTUP EARLY_BOOT/MIDDLE) faults dereferencing it.
 *
 * Provide the RNG entry points backed by ccdrbg_nisthmac, built exactly
 * like the early random DRBG in osfmk/prng/prng_random.c, and register
 * the table at EARLY_BOOT/FIRST so it is in place before kmem needs it.
 *
 * Only the RNG entry points are populated; digest/HMAC/cipher slots stay
 * NULL until a full provider lands.  Do not call those.
 */

#include <libkern/libkern.h>
#include <libkern/crypto/crypto_internal.h>
#include <libkern/crypto/register_crypto.h>
#include <libkern/crypto/rand.h>

#include <corecrypto/ccdrbg.h>
#include <corecrypto/ccrng.h>
#include <corecrypto/ccsha2.h>

#include <kern/locks.h>
#include <kern/simple_lock.h>
extern uint64_t early_random(void);
#include <kern/startup.h>
#include <machine/machine_routines.h>

/* Same construction (and state size) as erandom in prng_random.c. */
#define PROVIDER_DRBG_STATE_SIZE 264

static const struct ccdrbg_nisthmac_custom provider_drbg_custom = {
	.di         = &ccsha256_ltc_di,
	.strictFIPS = 0,
};

static struct {
	struct ccrng_state base;
	decl_simple_lock_data(, lock);
	struct ccdrbg_info info;
	uint8_t state[PROVIDER_DRBG_STATE_SIZE];
} provider_rng;

static size_t provider_ctx_size;

static int
provider_ccrng_generate(struct ccrng_state *rng, size_t outlen, void *out)
{
	int rc;

	(void)rng;
	if (outlen == 0) {
		return 0;
	}
	simple_lock(&provider_rng.lock, LCK_GRP_NULL);
	rc = ccdrbg_generate(&provider_rng.info,
	    (struct ccdrbg_state *)provider_rng.state,
	    outlen, out, 0, NULL);
	simple_unlock(&provider_rng.lock);
	return rc;
}

static struct ccrng_state *
provider_ccrng(int *error)
{
	if (error != NULL) {
		*error = 0;
	}
	return &provider_rng.base;
}

static void
provider_random_generate(crypto_random_ctx_t ctx, void *random,
    size_t random_size)
{
	if (random_size == 0) {
		return;
	}
	/* Per-CPU contexts need no locking. */
	(void)ccdrbg_generate(&provider_rng.info, (struct ccdrbg_state *)ctx,
	    random_size, random, 0, NULL);
}

static void
provider_random_uniform(crypto_random_ctx_t ctx, uint64_t bound,
    uint64_t *random)
{
	uint64_t limit, v;

	if (bound == 0) {
		*random = 0;
		return;
	}
	/* Rejection sampling for an unbiased value in [0, bound). */
	limit = (~0ULL / bound) * bound;
	do {
		provider_random_generate(ctx, &v, sizeof(v));
	} while (v >= limit);
	*random = v % bound;
}

static size_t
provider_random_kmem_ctx_size(void)
{
	return provider_ctx_size;
}

static void
provider_random_kmem_init(crypto_random_ctx_t ctx)
{
	uint64_t entropy[4];
	uint64_t nonce;
	static const char ps[] = "xnu kmem rng";
	int i;

	for (i = 0; i < 4; i++) {
		entropy[i] = early_random();
	}
	nonce = ml_get_timebase();
	(void)ccdrbg_init(&provider_rng.info, (struct ccdrbg_state *)ctx,
	    sizeof(entropy), entropy, sizeof(nonce), &nonce,
	    sizeof(ps) - 1, ps);
}

static struct crypto_functions provider_funcs = {
	.ccrng_fn                = provider_ccrng,
	.random_generate_fn      = provider_random_generate,
	.random_uniform_fn       = provider_random_uniform,
	.random_kmem_ctx_size_fn = provider_random_kmem_ctx_size,
	.random_kmem_init_fn     = provider_random_kmem_init,
};


static void
corecrypto_provider_init(void)
{
	uint64_t entropy[4];
	uint64_t nonce;
	static const char ps[] = "xnu crypto provider";
	int i;

	provider_rng.base.generate = provider_ccrng_generate;
	simple_lock_init(&provider_rng.lock, 0);

	ccdrbg_factory_nisthmac(&provider_rng.info, &provider_drbg_custom);
	provider_ctx_size = ccdrbg_context_size(&provider_rng.info);

	for (i = 0; i < 4; i++) {
		entropy[i] = early_random();
	}
	nonce = ml_get_timebase();
	(void)ccdrbg_init(&provider_rng.info,
	    (struct ccdrbg_state *)provider_rng.state,
	    sizeof(entropy), entropy, sizeof(nonce), &nonce,
	    sizeof(ps) - 1, ps);
	register_crypto_functions(&provider_funcs);
}
STARTUP(EARLY_BOOT, STARTUP_RANK_FIRST, corecrypto_provider_init);
