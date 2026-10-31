/*
 * malloczone -- does free() give each pointer back to the zone that owns it?
 *
 * Firefox dies early in mozjemalloc's _free() (libmozglue + 0x16168, fault 0)
 * when it is asked to free a pointer it did not allocate.  The suspects are
 * libSystem's free() and find_registered_zone(), which currently accept the
 * first zone whose size(zone, ptr) returns nonzero.  A zone that answers
 * nonzero for pointers it does not own therefore steals frees from the zone
 * that does, and its own free() walks metadata that was never written.
 *
 * This fixture makes that situation explicit: allocate from the default zone,
 * register a zone that claims every pointer, free the default zone's pointer,
 * and report which zone received the free.  Passing means the default zone
 * kept its own pointer.
 *
 * The fixture is deliberately a separate gate: if this regresses, the fix
 * belongs in libSystem's zone dispatch, not in any application.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <malloc/malloc.h>

static int evil_frees;
static int other_frees;

static size_t
evil_size(malloc_zone_t *zone, const void *ptr)
{
	(void)zone;
	(void)ptr;
	return 64;	/* claims every pointer, correct or not */
}

static void
evil_free(malloc_zone_t *zone, void *ptr)
{
	(void)zone;
	(void)ptr;
	evil_frees++;
}

static void *
evil_malloc(malloc_zone_t *zone, size_t size)
{
	(void)zone;
	(void)size;
	return NULL;
}

static void *
evil_calloc(malloc_zone_t *zone, size_t n, size_t size)
{
	(void)zone;
	(void)n;
	(void)size;
	return NULL;
}

static void *
evil_realloc(malloc_zone_t *zone, void *ptr, size_t size)
{
	(void)zone;
	(void)ptr;
	(void)size;
	return NULL;
}

static void
other_free(malloc_zone_t *zone, void *ptr)
{
	(void)zone;
	(void)ptr;
	other_frees++;
}

int
main(void)
{
	void *p1, *p2;
	malloc_zone_t *owner, *other, *evil;
	int rc;

	p1 = malloc(64);
	p2 = malloc(64);
	if (p1 == NULL || p2 == NULL) {
		printf("malloczone: malloc failed\n");
		printf("FIXTURE malloczone rc=1\n");
		return 1;
	}
	memset(p1, 0x5a, 64);
	memset(p2, 0x5a, 64);

	owner = malloc_zone_from_ptr(p1);
	printf("malloczone: ptr=%p owner=%s default=%s\n", p1,
	    owner != NULL ? owner->zone_name : "(nil)",
	    malloc_default_zone()->zone_name);

	/*
	 * A well-behaved second zone: it owns nothing, so free() must never
	 * hand it a default-zone pointer.  Registered first so that a broken
	 * dispatch picks it up even without the claim-all zone.
	 */
	other = calloc(1, sizeof(*other));
	other->version = 1;
	other->size = evil_size;
	other->malloc = evil_malloc;
	other->calloc = evil_calloc;
	other->realloc = evil_realloc;
	other->free = other_free;
	other->zone_name = "other-empty";
	malloc_zone_register(other);

	free(p1);

	/*
	 * Now the hostile zone.  It allocates nothing, yet claims everything;
	 * a correct free() still must not consult it for a pointer the default
	 * zone created.
	 */
	evil = calloc(1, sizeof(*evil));
	evil->version = 1;
	evil->size = evil_size;
	evil->malloc = evil_malloc;
	evil->calloc = evil_calloc;
	evil->realloc = evil_realloc;
	evil->free = evil_free;
	evil->zone_name = "evil-claim-all";
	malloc_zone_register(evil);

	free(p2);

	malloc_zone_unregister(evil);
	malloc_zone_unregister(other);
	free(evil);
	free(other);

	rc = (evil_frees == 0 && other_frees == 0) ? 0 : 1;
	printf("malloczone: frees_to_claim_all=%d frees_to_other=%d\n",
	    evil_frees, other_frees);
	printf("FIXTURE malloczone rc=%d\n", rc);
	return rc;
}
