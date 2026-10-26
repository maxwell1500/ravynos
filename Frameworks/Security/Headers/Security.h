/*
 * Security.framework public header for ravynOS.
 *
 * This is a deliberately small subset of the macOS Security API: the calls a
 * bundled application reaches for while starting up and while using TLS,
 * keychain-backed preferences and code-signing checks.  Everything declared
 * here is implemented by SecurityRuntime.c; nothing is declared that would
 * fail to link.
 *
 * The rest of Apple's Security surface (CSSM, CMS, SecKeychain search lists,
 * SASL, the Trust evaluation engine with a real root store) is not present.
 * Code that needs it fails to compile rather than failing silently at run
 * time, which is the point.
 */

#ifndef _RAVYNOS_SECURITY_H_
#define _RAVYNOS_SECURITY_H_

#include <CoreFoundation/CoreFoundation.h>
#include <mach/message.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t OSStatus;
typedef UInt32 SecCSFlags;

/* ------------------------------------------------------------------ */
/* Result codes                                                        */
/* ------------------------------------------------------------------ */

enum {
    errSecSuccess                 = 0,
    errSecUnimplemented           = -4,
    errSecParam                   = -50,
    errSecAllocate                = -108,
    errSecNotAvailable            = -25291,
    errSecDuplicateItem           = -25299,
    errSecItemNotFound            = -25300,
    errSecInteractionNotAllowed   = -25308,
    errSecDecode                  = -26275,
    errSecAuthFailed              = -25293,
    errSecNoSuchKeychain          = -25294,
    errSecNoDefaultKeychain       = -25307,
    errSecCSUnsigned              = -67062,
    errSecCSUnsigned2             = -67062,
    errAuthorizationSuccess       = 0,
    errAuthorizationDenied        = -60005,
    errAuthorizationToolExecuteFailure = -60031,
};

/* ------------------------------------------------------------------ */
/* Opaque object references                                            */
/* ------------------------------------------------------------------ */

typedef struct __SecTask *SecTaskRef;
typedef struct __SecCode *SecCodeRef;
typedef struct __SecCode const *SecStaticCodeRef;
typedef struct __SecRequirement *SecRequirementRef;
typedef struct __SecKeychain *SecKeychainRef;
typedef struct __SecTrust *SecTrustRef;
typedef struct __SecPolicy *SecPolicyRef;
typedef struct __SecCertificate *SecCertificateRef;
typedef struct __SecKey *SecKeyRef;
typedef struct __SecIdentity *SecIdentityRef;
typedef struct __SecAccessControl *SecAccessControlRef;
typedef struct __SecRandom *SecRandomRef;
typedef struct __SecKeychainItem *SecKeychainItemRef;
typedef struct __Authorization *AuthorizationRef;
typedef UInt32 SecKeychainStatus;

typedef const struct __SecRandom *SecRandomRefConst;

typedef enum {
    kSecTrustResultInvalid = 0,
    kSecTrustResultProceed = 1,
    kSecTrustResultConfirm = 2,
    kSecTrustResultDeny = 3,
    kSecTrustResultUnspecified = 4,
    kSecTrustResultRecoverableTrustFailure = 5,
    kSecTrustResultFatalTrustFailure = 6,
    kSecTrustResultOtherError = 7,
} SecTrustResultType;

/* ------------------------------------------------------------------ */
/* Dictionary keys and values                                          */
/* ------------------------------------------------------------------ */

/* ravynOS note: Apple's headers declare these as `const CFStringRef`.  This
 * CoreFoundation builds CFSTR() strings at run time (it does not use
 * -fconstant-cfstrings), so the pointers are populated once by a constructor
 * in SecurityRuntime.c and the storage has to stay writable.  The ABI is
 * identical; only the const qualification differs. */
extern CFStringRef kSecClass;
extern CFStringRef kSecClassGenericPassword;
extern CFStringRef kSecClassInternetPassword;
extern CFStringRef kSecClassCertificate;
extern CFStringRef kSecClassKey;
extern CFStringRef kSecClassIdentity;

extern CFStringRef kSecAttrAccount;
extern CFStringRef kSecAttrService;
extern CFStringRef kSecAttrLabel;
extern CFStringRef kSecAttrDescription;
extern CFStringRef kSecAttrComment;
extern CFStringRef kSecAttrCreator;
extern CFStringRef kSecAttrType;
extern CFStringRef kSecAttrAccessible;
extern CFStringRef kSecAttrAccessibleWhenUnlocked;
extern CFStringRef kSecAttrAccessibleAfterFirstUnlock;
extern CFStringRef kSecAttrAccessGroup;
extern CFStringRef kSecAttrCreationDate;
extern CFStringRef kSecAttrModificationDate;
extern CFStringRef kSecAttrGeneric;
extern CFStringRef kSecAttrProtocol;
extern CFStringRef kSecAttrServer;
extern CFStringRef kSecAttrPort;
extern CFStringRef kSecAttrPath;
extern CFStringRef kSecAttrSecurityDomain;
extern CFStringRef kSecAttrAuthenticationType;

extern CFStringRef kSecValueData;
extern CFStringRef kSecValueRef;
extern CFStringRef kSecValuePersistentRef;
extern CFStringRef kSecReturnData;
extern CFStringRef kSecReturnAttributes;
extern CFStringRef kSecReturnRef;
extern CFStringRef kSecReturnPersistentRef;
extern CFStringRef kSecMatchLimit;
extern CFStringRef kSecMatchLimitOne;
extern CFStringRef kSecMatchLimitAll;
extern CFStringRef kSecMatchCaseInsensitive;
extern CFStringRef kSecMatchTrustedOnly;
extern CFStringRef kSecUseDataProtectionKeychain;

extern CFStringRef kSecRandomDefault;

extern CFStringRef kSecPolicyAppleSSL;
extern CFStringRef kSecPolicyAppleX509Basic;
extern CFStringRef kSecPolicyAppleSMIME;
extern CFStringRef kSecPolicyAppleIPSec;
extern CFStringRef kSecPolicyAppleTimeStamping;
extern CFStringRef kSecPolicyAppleRevocation;
extern CFStringRef kSecPolicyAppleCodeSigning;

extern CFStringRef kSecTrustSettingsResult;
extern CFStringRef kSecTrustSettingsPolicy;
extern CFStringRef kSecTrustSettingsApplication;

extern CFStringRef kSecCertificateSubject;
extern CFStringRef kSecOIDCommonName;
extern CFStringRef kSecOIDOrganizationName;
extern CFStringRef kSecOIDOrganizationalUnitName;
extern CFStringRef kSecOIDCountryName;

/* ------------------------------------------------------------------ */
/* SecTask                                                             */
/* ------------------------------------------------------------------ */

CFTypeID SecTaskGetTypeID(void);
SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
SecTaskRef SecTaskCreateWithAuditToken(CFAllocatorRef allocator, audit_token_t token);
SecTaskRef SecTaskCreateWithPID(CFAllocatorRef allocator, pid_t pid);
CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);
CFDictionaryRef SecTaskCopyValuesForEntitlements(SecTaskRef task, CFArrayRef entitlements, CFErrorRef *error);
CFStringRef SecTaskCopySigningIdentifier(SecTaskRef task, CFErrorRef *error);
uint32_t SecTaskGetCodeSignStatus(SecTaskRef task);
OSStatus SecTaskCopyTeamIdentifier(SecTaskRef task, CFErrorRef *error, CFStringRef *teamIdentifier);

/* ------------------------------------------------------------------ */
/* SecCode / SecRequirement                                            */
/* ------------------------------------------------------------------ */

OSStatus SecCodeCopySelf(SecCSFlags flags, SecCodeRef *self);
OSStatus SecCodeCopyGuestWithAttributes(SecCodeRef host, CFDictionaryRef attributes,
                                        SecCSFlags flags, SecCodeRef *guest);
OSStatus SecCodeCopyPath(SecStaticCodeRef code, SecCSFlags flags, CFURLRef *path);
OSStatus SecCodeCopyStaticCode(SecCodeRef code, SecCSFlags flags, SecStaticCodeRef *staticCode);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *info);
OSStatus SecCodeCheckValidity(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement);
OSStatus SecCodeCheckValidityWithErrors(SecCodeRef code, SecCSFlags flags,
                                        SecRequirementRef requirement, CFErrorRef *errors);

OSStatus SecStaticCodeCreateWithPath(CFURLRef path, SecCSFlags flags, SecStaticCodeRef *staticCode);
OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags,
                                                 CFDictionaryRef attributes,
                                                 SecStaticCodeRef *staticCode);
OSStatus SecStaticCodeCheckValidity(SecStaticCodeRef staticCode, SecCSFlags flags,
                                    SecRequirementRef requirement);
OSStatus SecStaticCodeCheckValidityWithErrors(SecStaticCodeRef staticCode, SecCSFlags flags,
                                              SecRequirementRef requirement, CFErrorRef *errors);

OSStatus SecRequirementCreateWithString(CFStringRef text, SecCSFlags flags,
                                        SecRequirementRef *requirement);
OSStatus SecRequirementCreateWithStringAndErrors(CFStringRef text, SecCSFlags flags,
                                                 CFErrorRef *errors,
                                                 SecRequirementRef *requirement);
OSStatus SecRequirementCreateWithData(CFDataRef data, SecCSFlags flags,
                                      SecRequirementRef *requirement);
OSStatus SecRequirementCopyString(SecRequirementRef requirement, SecCSFlags flags, CFStringRef *text);
OSStatus SecRequirementCopyData(SecRequirementRef requirement, SecCSFlags flags, CFDataRef *data);

/* ------------------------------------------------------------------ */
/* Randomness                                                          */
/* ------------------------------------------------------------------ */

int SecRandomCopyBytes(SecRandomRef rnd, size_t count, void *bytes);

/* ------------------------------------------------------------------ */
/* Keychain / SecItem                                                  */
/* ------------------------------------------------------------------ */

OSStatus SecKeychainCopyDefault(SecKeychainRef *keychain);
OSStatus SecKeychainGetStatus(SecKeychainRef keychain, SecKeychainStatus *status);
OSStatus SecKeychainOpen(const char *pathName, SecKeychainRef *keychain);
OSStatus SecKeychainLock(SecKeychainRef keychain);
OSStatus SecKeychainUnlock(SecKeychainRef keychain, UInt32 passwordLength,
                           const void *password, Boolean usePassword);

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
OSStatus SecItemDelete(CFDictionaryRef query);

/* ------------------------------------------------------------------ */
/* Trust / policy / certificate / key                                  */
/* ------------------------------------------------------------------ */

CFTypeID SecTrustGetTypeID(void);
SecPolicyRef SecPolicyCreateSSL(Boolean server, CFStringRef hostname);
SecPolicyRef SecPolicyCreateBasicX509(void);
SecPolicyRef SecPolicyCreateRevocation(CFOptionFlags revocationFlags);
SecPolicyRef SecPolicyCreateWithProperties(CFTypeRef policyIdentifier, CFDictionaryRef properties);
OSStatus SecPolicySetProperties(SecPolicyRef policy, CFDictionaryRef properties);
OSStatus SecPolicyCopyProperties(SecPolicyRef policy, CFDictionaryRef *properties);

OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates, CFTypeRef policies, SecTrustRef *trust);
OSStatus SecTrustSetPolicies(SecTrustRef trust, CFTypeRef policies);
OSStatus SecTrustSetAnchorCertificates(SecTrustRef trust, CFArrayRef anchorCertificates);
OSStatus SecTrustSetAnchorCertificatesOnly(SecTrustRef trust, Boolean anchorCertificatesOnly);
OSStatus SecTrustSetVerifyDate(SecTrustRef trust, CFDateRef verifyDate);
OSStatus SecTrustSetNetworkFetchAllowed(SecTrustRef trust, Boolean allowFetch);
OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result);
OSStatus SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error);
OSStatus SecTrustGetTrustResult(SecTrustRef trust, SecTrustResultType *result);
CFIndex SecTrustGetCertificateCount(SecTrustRef trust);
SecCertificateRef SecTrustGetCertificateAtIndex(SecTrustRef trust, CFIndex ix);
OSStatus SecTrustCopyPublicKey(SecTrustRef trust, SecKeyRef *key);
OSStatus SecTrustCopyExceptions(SecTrustRef trust, CFDataRef *exceptions);
OSStatus SecTrustSetExceptions(SecTrustRef trust, CFDataRef exceptions);
OSStatus SecTrustCopyPolicies(SecTrustRef trust, CFArrayRef *policies);

OSStatus SecCertificateCopyCommonName(SecCertificateRef certificate, CFStringRef *commonName);
CFDataRef SecCertificateCopyData(SecCertificateRef certificate);
SecCertificateRef SecCertificateCreateWithData(CFAllocatorRef allocator, CFDataRef data);
CFStringRef SecCertificateCopySubjectSummary(SecCertificateRef certificate);
OSStatus SecCertificateCopyEmailAddresses(SecCertificateRef certificate, CFArrayRef *addresses);

OSStatus SecKeyVerifySignature(SecKeyRef key, CFStringRef algorithm, CFDataRef signedData,
                               CFDataRef signature, CFErrorRef *error);
SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef parameters, CFErrorRef *error);
CFDataRef SecKeyCreateSignature(SecKeyRef key, CFStringRef algorithm, CFDataRef dataToSign,
                                CFErrorRef *error);
CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error);
CFDictionaryRef SecKeyCopyAttributes(SecKeyRef key);
size_t SecKeyGetBlockSize(SecKeyRef key);

/* ------------------------------------------------------------------ */
/* Authorization Services                                              */
/* ------------------------------------------------------------------ */

typedef struct AuthorizationItem {
    const char *name;
    size_t valueLength;
    void *value;
    UInt32 flags;
} AuthorizationItem;

typedef struct AuthorizationItemSet {
    UInt32 count;
    AuthorizationItem *items;
} AuthorizationItemSet;

typedef AuthorizationItemSet AuthorizationRights;
typedef AuthorizationItemSet AuthorizationEnvironment;
typedef AuthorizationItemSet AuthorizationInfo;

typedef UInt32 AuthorizationFlags;
enum {
    kAuthorizationFlagDefaults = 0,
    kAuthorizationFlagInteractionAllowed = (1 << 0),
    kAuthorizationFlagExtendRights = (1 << 1),
    kAuthorizationFlagPartialRights = (1 << 2),
    kAuthorizationFlagDestroyRights = (1 << 3),
    kAuthorizationFlagPreAuthorize = (1 << 4),
};

OSStatus AuthorizationCreate(const AuthorizationRights *rights,
                             const AuthorizationEnvironment *environment,
                             AuthorizationFlags flags,
                             AuthorizationRef *authorization);
OSStatus AuthorizationFree(AuthorizationRef authorization, AuthorizationFlags flags);
OSStatus AuthorizationCopyRights(AuthorizationRef authorization, const AuthorizationRights *rights,
                                 const AuthorizationEnvironment *environment,
                                 AuthorizationFlags flags, AuthorizationRights **authorizedRights);
OSStatus AuthorizationCopyInfo(AuthorizationRef authorization, const char *tag, AuthorizationInfo **info);
OSStatus AuthorizationFreeItemSet(AuthorizationItemSet *set);

#ifdef __cplusplus
}
#endif

#endif /* _RAVYNOS_SECURITY_H_ */
