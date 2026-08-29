/*
 * Copyright (c) 2022 Apple Inc. All rights reserved.
 */

#ifndef _TRUSTCACHE_API_H_
#define _TRUSTCACHE_API_H_

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define kUUIDSize 16
#define kTCEntryHashSize 20
#define kLibTrustCacheHasQueryForREM 1

typedef enum {
	kTCCapabilityNone = 0,
} TCCapability_t;

typedef uint64_t TCCapabilities_t;
typedef enum {
	kTCTypeInvalid = 0,
	kTCTypeLTRS = 1,
	kTCTypeDTRS = 2,
	kTCTypeStatic = 3,
	kTCTypeEngineering = 4,
	kTCTypeLegacy = 5,
	kTCTypePersonalized = 6,
	kTCTypeBaseSystem = 7,
	kTCTypeCryptex1BootOS = 8,
	kTCTypeCryptex1BootApp = 9,
	kTCTypeTotal = 10
} TCType_t;

typedef enum {
	kTCQueryTypeAll = 0,
	kTCQueryTypeLoadable = 1,
	kTCQueryTypeStatic = 2,
	kTCQueryTypeTotal = 3
} TCQueryType_t;

typedef enum {
	kTCReturnSuccess = 0,
	kTCReturnNotFound = 1,
	kTCReturnDuplicate = 2,
	kTCReturnInvalid = 3,
	kTCReturnError = 4
} TCReturnCode_t;

typedef struct _TCReturn {
	uint8_t component;
	uint8_t error;
	uint16_t uniqueError;
} TCReturn_t;

typedef struct _TrustCache {
	uint8_t opaque[128];
} TrustCache_t;

typedef struct _TrustCacheRuntime {
	bool allowSecondStaticTC;
	bool allowEngineeringTC;
	uint8_t opaque[60];
} TrustCacheRuntime_t;

typedef struct _TrustCacheMutableRuntime {
	uint8_t opaque[64];
} TrustCacheMutableRuntime_t;

typedef struct _TrustCacheQueryToken {
	const TrustCache_t *trustCache;
	const void *trustCacheEntry;
	uint8_t opaque[32];
} TrustCacheQueryToken_t;
/*
 * Per-type trust cache configuration. The definition of the table itself
 * lives in the kernel (bsd/kern/kern_trustcache.c) because the ravynOS
 * build does not include Apple's closed trust cache runtime library.
 *
 * "entitlementValue" is the expected value of the caller's
 * "com.apple.private.pmap.load-trust-cache" entitlement; NULL means no
 * userland caller may load this type (it is loaded at boot).
 */
typedef struct _TCTypeConfigEntry {
	const char *entitlementValue;
} TCTypeConfigEntry;

extern const TCTypeConfigEntry TCTypeConfig[kTCTypeTotal];
/*
 * Forward declaration matching img4/firmware.h ("typedef struct _img4_runtime
 * img4_runtime_t;").
 */
typedef struct _img4_runtime img4_runtime_t;

/*
 * Initialize the trust cache runtime. The ravynOS kernel provides the
 * implementation in bsd/kern/kern_trustcache.c; Apple's closed runtime
 * does this inside the trust cache library.
 */
extern void trustCacheInitializeRuntime(
	TrustCacheRuntime_t *rt,
	TrustCacheMutableRuntime_t *mut_rt,
	bool allow_second_static_cache,
	bool allow_engineering_caches,
	bool allow_legacy_caches,
	const img4_runtime_t *img4_runtime);

#endif /* _TRUSTCACHE_API_H_ */
