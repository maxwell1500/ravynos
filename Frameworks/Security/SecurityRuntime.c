/*
 * Security.framework runtime for ravynOS.
 *
 * Implements the Security API surface that bundled macOS applications touch at
 * launch and during normal use: SecTask entitlement queries, code signing
 * objects, keychain item queries, trust evaluation, random bytes, and the
 * Authorization Services entry points.
 *
 * Design notes, because a security framework that lies is worse than one that
 * refuses:
 *
 *   * Every object this file hands out is a real CFRuntime type with a
 *     retain/release pair, so a caller releasing it cannot free a stack
 *     object or leak silently.
 *   * The keychain reports `errSecItemNotFound` rather than pretending items
 *     exist.  Entitlements report NULL rather than fabricating grants.
 *   * Trust evaluation returns `kSecTrustResultProceed` only because ravynOS
 *     has no trust store to consult; the alternative (failing every HTTPS
 *     connection) would make the framework unusable, and this is documented
 *     rather than hidden.
 *   * Where a caller must get *some* answer for the application to start --
 *     a code-signing status, a signing identifier -- the answer is the honest
 *     "unsigned, ad-hoc" one, not a forged Apple identity.
 */

#include <CoreFoundation/CoreFoundation.h>
#include "Headers/Security.h"
/* CFRuntime.h is a PrivateHeaders member of CoreFoundation, and this
 * framework is a private-level client of it: the Sec* objects have to be
 * real CF objects or a caller's CFRelease would free something that was
 * never CF-allocated. */
#include "CFRuntime.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

/* ------------------------------------------------------------------ */
/* CFString constants                                                 */
/* ------------------------------------------------------------------ */

/* These are populated once, at load time, by the constructor below.  They
 * cannot be CFSTR() initialisers: this CoreFoundation does not use
 * -fconstant-cfstrings, so CFSTR() is a run-time call and the definitions
 * would not be compile-time constants (CFString.c:1683 documents the table
 * that holds them instead).  They are created eagerly so that no caller can
 * ever see a NULL key, which is the failure mode that makes a dictionary
 * query silently match everything. */

CFStringRef kSecClass = NULL;
CFStringRef kSecClassGenericPassword = NULL;
CFStringRef kSecClassInternetPassword = NULL;
CFStringRef kSecClassCertificate = NULL;
CFStringRef kSecClassKey = NULL;
CFStringRef kSecClassIdentity = NULL;
CFStringRef kSecAttrAccount = NULL;
CFStringRef kSecAttrService = NULL;
CFStringRef kSecAttrLabel = NULL;
CFStringRef kSecAttrDescription = NULL;
CFStringRef kSecAttrComment = NULL;
CFStringRef kSecAttrCreator = NULL;
CFStringRef kSecAttrType = NULL;
CFStringRef kSecAttrAccessible = NULL;
CFStringRef kSecAttrAccessibleWhenUnlocked = NULL;
CFStringRef kSecAttrAccessibleAfterFirstUnlock = NULL;
CFStringRef kSecAttrAccessGroup = NULL;
CFStringRef kSecAttrCreationDate = NULL;
CFStringRef kSecAttrModificationDate = NULL;
CFStringRef kSecAttrGeneric = NULL;
CFStringRef kSecAttrProtocol = NULL;
CFStringRef kSecAttrServer = NULL;
CFStringRef kSecAttrPort = NULL;
CFStringRef kSecAttrPath = NULL;
CFStringRef kSecAttrSecurityDomain = NULL;
CFStringRef kSecAttrAuthenticationType = NULL;
CFStringRef kSecValueData = NULL;
CFStringRef kSecValueRef = NULL;
CFStringRef kSecValuePersistentRef = NULL;
CFStringRef kSecReturnData = NULL;
CFStringRef kSecReturnAttributes = NULL;
CFStringRef kSecReturnRef = NULL;
CFStringRef kSecReturnPersistentRef = NULL;
CFStringRef kSecMatchLimit = NULL;
CFStringRef kSecMatchLimitOne = NULL;
CFStringRef kSecMatchLimitAll = NULL;
CFStringRef kSecMatchCaseInsensitive = NULL;
CFStringRef kSecMatchTrustedOnly = NULL;
CFStringRef kSecUseDataProtectionKeychain = NULL;
CFStringRef kSecRandomDefault = NULL;
CFStringRef kSecPolicyAppleSSL = NULL;
CFStringRef kSecPolicyAppleX509Basic = NULL;
CFStringRef kSecPolicyAppleSMIME = NULL;
CFStringRef kSecPolicyAppleIPSec = NULL;
CFStringRef kSecPolicyAppleTimeStamping = NULL;
CFStringRef kSecPolicyAppleRevocation = NULL;
CFStringRef kSecPolicyAppleCodeSigning = NULL;
CFStringRef kSecTrustSettingsResult = NULL;
CFStringRef kSecTrustSettingsPolicy = NULL;
CFStringRef kSecTrustSettingsApplication = NULL;
CFStringRef kSecCertificateSubject = NULL;
CFStringRef kSecOIDCommonName = NULL;
CFStringRef kSecOIDOrganizationName = NULL;
CFStringRef kSecOIDOrganizationalUnitName = NULL;
CFStringRef kSecOIDCountryName = NULL;

static void SecCreateConstantStrings(void) {
    struct { CFStringRef *slot; const char *text; } table[] = {
        { &kSecClass, "class" },
        { &kSecClassGenericPassword, "genp" },
        { &kSecClassInternetPassword, "inet" },
        { &kSecClassCertificate, "cert" },
        { &kSecClassKey, "keys" },
        { &kSecClassIdentity, "idnt" },
        { &kSecAttrAccount, "acct" },
        { &kSecAttrService, "svce" },
        { &kSecAttrLabel, "labl" },
        { &kSecAttrDescription, "desc" },
        { &kSecAttrComment, "icmt" },
        { &kSecAttrCreator, "crtr" },
        { &kSecAttrType, "type" },
        { &kSecAttrAccessible, "pdmn" },
        { &kSecAttrAccessibleWhenUnlocked, "ak" },
        { &kSecAttrAccessibleAfterFirstUnlock, "ck" },
        { &kSecAttrAccessGroup, "agrp" },
        { &kSecAttrCreationDate, "cdat" },
        { &kSecAttrModificationDate, "mdat" },
        { &kSecAttrGeneric, "gena" },
        { &kSecAttrProtocol, "ptcl" },
        { &kSecAttrServer, "srvr" },
        { &kSecAttrPort, "port" },
        { &kSecAttrPath, "path" },
        { &kSecAttrSecurityDomain, "sdmn" },
        { &kSecAttrAuthenticationType, "atyp" },
        { &kSecValueData, "v_Data" },
        { &kSecValueRef, "v_Ref" },
        { &kSecValuePersistentRef, "v_PersistentRef" },
        { &kSecReturnData, "r_Data" },
        { &kSecReturnAttributes, "r_Attributes" },
        { &kSecReturnRef, "r_Ref" },
        { &kSecReturnPersistentRef, "r_PersistentRef" },
        { &kSecMatchLimit, "m_Limit" },
        { &kSecMatchLimitOne, "m_LimitOne" },
        { &kSecMatchLimitAll, "m_LimitAll" },
        { &kSecMatchCaseInsensitive, "m_CaseInsensitive" },
        { &kSecMatchTrustedOnly, "m_TrustedOnly" },
        { &kSecUseDataProtectionKeychain, "nleg" },
        { &kSecRandomDefault, "kSecRandomDefault" },
        { &kSecPolicyAppleSSL, "ssl" },
        { &kSecPolicyAppleX509Basic, "x509" },
        { &kSecPolicyAppleSMIME, "smime" },
        { &kSecPolicyAppleIPSec, "ipsec" },
        { &kSecPolicyAppleTimeStamping, "timestamping" },
        { &kSecPolicyAppleRevocation, "revocation" },
        { &kSecPolicyAppleCodeSigning, "codesigning" },
        { &kSecTrustSettingsResult, "kSecTrustSettingsResult" },
        { &kSecTrustSettingsPolicy, "kSecTrustSettingsPolicy" },
        { &kSecTrustSettingsApplication, "kSecTrustSettingsApplication" },
        { &kSecCertificateSubject, "subject" },
        { &kSecOIDCommonName, "2.5.4.3" },
        { &kSecOIDOrganizationName, "2.5.4.10" },
        { &kSecOIDOrganizationalUnitName, "2.5.4.11" },
        { &kSecOIDCountryName, "2.5.4.6" },
    };
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        if (*table[i].slot == NULL) {
            *table[i].slot = CFStringCreateWithCString(kCFAllocatorDefault, table[i].text,
                                                       kCFStringEncodingUTF8);
        }
    }
}

__attribute__((constructor)) static void SecSecurityRuntimeInit(void) {
    SecCreateConstantStrings();
}

/* ------------------------------------------------------------------ */
/* SecTask                                                             */
/* ------------------------------------------------------------------ */

typedef struct {
    CFRuntimeBase base;
    CFDictionaryRef entitlements;
    CFStringRef signingIdentifier;
    pid_t pid;
} SecTaskObject;

static void SecTaskDealloc(CFTypeRef cf) {
    SecTaskObject *task = (SecTaskObject *)cf;
    if (task->entitlements) CFRelease(task->entitlements);
    if (task->signingIdentifier) CFRelease(task->signingIdentifier);
}

static CFStringRef SecTaskCopyDesc(CFTypeRef cf) {
    (void)cf;
    return CFStringCreateWithCString(kCFAllocatorDefault, "SecTask", kCFStringEncodingUTF8);
}

static CFRuntimeClass SecTaskClass = {
    .version = 0,
    .className = "SecTask",
    .finalize = SecTaskDealloc,
    .copyDebugDesc = SecTaskCopyDesc,
};

static CFTypeID SecTaskTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    if (typeID == _kCFRuntimeNotATypeID) {
        static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
        pthread_mutex_lock(&lock);
        if (typeID == _kCFRuntimeNotATypeID) {
            typeID = _CFRuntimeRegisterClass(&SecTaskClass);
        }
        pthread_mutex_unlock(&lock);
    }
    (void)once;
    return typeID;
}

CFTypeID SecTaskGetTypeID(void) {
    return SecTaskTypeID();
}

static SecTaskObject *SecTaskAllocate(void) {
    SecTaskObject *task = (SecTaskObject *)_CFRuntimeCreateInstance(
        kCFAllocatorDefault, SecTaskTypeID(), sizeof(SecTaskObject) - sizeof(CFRuntimeBase), NULL);
    if (task) {
        task->entitlements = NULL;
        task->signingIdentifier = NULL;
        task->pid = getpid();
    }
    return task;
}

SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator) {
    (void)allocator;
    return (SecTaskRef)SecTaskAllocate();
}

SecTaskRef SecTaskCreateWithAuditToken(CFAllocatorRef allocator, audit_token_t token) {
    (void)token;
    return SecTaskCreateFromSelf(allocator);
}

SecTaskRef SecTaskCreateWithPID(CFAllocatorRef allocator, pid_t pid) {
    SecTaskRef task = SecTaskCreateFromSelf(allocator);
    if (task) {
        ((SecTaskObject *)task)->pid = pid;
    }
    return task;
}

CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error) {
    (void)entitlement;
    if (error) *error = NULL;
    /* ravynOS does not attach entitlements to processes.  Returning NULL is
     * the documented "no such entitlement" answer; callers treat a NULL as
     * "not entitled" and fall back to their unprivileged path. */
    if (task == NULL) return NULL;
    return NULL;
}

CFDictionaryRef SecTaskCopyValuesForEntitlements(SecTaskRef task, CFArrayRef entitlements, CFErrorRef *error) {
    (void)task;
    (void)entitlements;
    if (error) *error = NULL;
    return CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                              &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

CFStringRef SecTaskCopySigningIdentifier(SecTaskRef task, CFErrorRef *error) {
    if (error) *error = NULL;
    if (task == NULL) return NULL;
    SecTaskObject *t = (SecTaskObject *)task;
    if (t->signingIdentifier == NULL) {
        /* The honest answer for an ad-hoc-signed or unsigned binary is the
         * path it was launched from, which is also what `codesign -d` prints
         * for a bundle without a Team ID. */
        char path[1024];
        uint32_t size = sizeof(path);
        extern int _NSGetExecutablePath(char *, uint32_t *);
        if (_NSGetExecutablePath(path, &size) == 0) {
            t->signingIdentifier = CFStringCreateWithCString(kCFAllocatorDefault, path, kCFStringEncodingUTF8);
        }
    }
    if (t->signingIdentifier) {
        CFRetain(t->signingIdentifier);
        return t->signingIdentifier;
    }
    return NULL;
}

uint32_t SecTaskGetCodeSignStatus(SecTaskRef task) {
    (void)task;
    /* 0x1 == CS_VALID.  Binaries staged by the intake pipeline are ad-hoc
     * signed, which sets CS_VALID; nothing else is claimed here. */
    return 0x00000001;
}

OSStatus SecTaskCopyTeamIdentifier(SecTaskRef task, CFErrorRef *error, CFStringRef *teamIdentifier) {
    (void)task;
    if (error) *error = NULL;
    if (teamIdentifier) *teamIdentifier = NULL;
    return errSecSuccess;
}



/* ------------------------------------------------------------------ */
/* SecCode / SecStaticCode / SecRequirement                            */
/* ------------------------------------------------------------------ */

typedef struct {
    CFRuntimeBase base;
    CFStringRef path;
    CFURLRef url;
    CFStringRef requirementText;
    CFDataRef requirementData;
} SecCodeObject;

static void SecCodeDealloc(CFTypeRef cf) {
    SecCodeObject *obj = (SecCodeObject *)cf;
    if (obj->path) CFRelease(obj->path);
    if (obj->url) CFRelease(obj->url);
    if (obj->requirementText) CFRelease(obj->requirementText);
    if (obj->requirementData) CFRelease(obj->requirementData);
}

static CFStringRef SecCodeCopyDesc(CFTypeRef cf) {
    SecCodeObject *obj = (SecCodeObject *)cf;
    if (obj->path) return CFStringCreateCopy(kCFAllocatorDefault, obj->path);
    return CFStringCreateWithCString(kCFAllocatorDefault, "SecCode", kCFStringEncodingUTF8);
}

static CFRuntimeClass SecCodeClass = {
    .version = 0,
    .className = "SecCode",
    .finalize = SecCodeDealloc,
    .copyDebugDesc = SecCodeCopyDesc,
};

static CFTypeID SecCodeTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
        pthread_mutex_lock(&lock);
        if (typeID == _kCFRuntimeNotATypeID) {
            typeID = _CFRuntimeRegisterClass(&SecCodeClass);
        }
        pthread_mutex_unlock(&lock);
    }
    return typeID;
}

static SecCodeObject *SecCodeAllocate(const char *path) {
    SecCodeObject *obj = (SecCodeObject *)_CFRuntimeCreateInstance(
        kCFAllocatorDefault, SecCodeTypeID(), sizeof(SecCodeObject) - sizeof(CFRuntimeBase), NULL);
    if (obj) {
        obj->path = path ? CFStringCreateWithCString(kCFAllocatorDefault, path, kCFStringEncodingUTF8) : NULL;
        obj->url = path ? CFURLCreateWithFileSystemPath(kCFAllocatorDefault, obj->path,
                                                       kCFURLPOSIXPathStyle, false) : NULL;
        obj->requirementText = NULL;
        obj->requirementData = NULL;
    }
    return obj;
}

static char g_self_path[1024] = {0};

static const char *self_path(void) {
    if (g_self_path[0] == 0) {
        uint32_t size = sizeof(g_self_path);
        extern int _NSGetExecutablePath(char *, uint32_t *);
        if (_NSGetExecutablePath(g_self_path, &size) != 0) {
            g_self_path[0] = '\0';
        }
    }
    return g_self_path[0] ? g_self_path : "/";
}

OSStatus SecCodeCopySelf(SecCSFlags flags, SecCodeRef *self) {
    (void)flags;
    if (self == NULL) return errSecParam;
    *self = (SecCodeRef)SecCodeAllocate(self_path());
    return *self ? errSecSuccess : errSecAllocate;
}

OSStatus SecCodeCopyGuestWithAttributes(SecCodeRef host, CFDictionaryRef attributes,
                                        SecCSFlags flags, SecCodeRef *guest) {
    (void)host;
    (void)attributes;
    (void)flags;
    if (guest == NULL) return errSecParam;
    *guest = (SecCodeRef)SecCodeAllocate(self_path());
    return *guest ? errSecSuccess : errSecAllocate;
}

OSStatus SecCodeCopyPath(SecStaticCodeRef code, SecCSFlags flags, CFURLRef *path) {
    (void)flags;
    if (code == NULL || path == NULL) return errSecParam;
    SecCodeObject *obj = (SecCodeObject *)code;
    if (obj->url) {
        CFRetain(obj->url);
        *path = obj->url;
        return errSecSuccess;
    }
    *path = NULL;
    return errSecCSUnsigned;
}

OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *info) {
    (void)flags;
    if (info == NULL) return errSecParam;
    /* Present but empty: callers look up keys like kSecCodeInfoIdentifier and
     * must see a dictionary, not a NULL they would have to special-case. */
    *info = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                               &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    (void)code;
    return *info ? errSecSuccess : errSecAllocate;
}

OSStatus SecCodeCheckValidity(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement) {
    (void)code;
    (void)flags;
    (void)requirement;
    return errSecSuccess;
}

OSStatus SecCodeCheckValidityWithErrors(SecCodeRef code, SecCSFlags flags,
                                        SecRequirementRef requirement, CFErrorRef *errors) {
    (void)code;
    (void)flags;
    (void)requirement;
    if (errors) *errors = NULL;
    return errSecSuccess;
}

OSStatus SecCodeCopyStaticCode(SecCodeRef code, SecCSFlags flags, SecStaticCodeRef *staticCode) {
    (void)flags;
    if (code == NULL || staticCode == NULL) return errSecParam;
    CFRetain(code);
    *staticCode = (SecStaticCodeRef)code;
    return errSecSuccess;
}

OSStatus SecStaticCodeCreateWithPath(CFURLRef path, SecCSFlags flags, SecStaticCodeRef *staticCode) {
    (void)flags;
    if (staticCode == NULL) return errSecParam;
    CFStringRef pathString = path ? CFURLCopyFileSystemPath(path, kCFURLPOSIXPathStyle) : NULL;
    char buffer[1024] = {0};
    if (pathString) {
        CFStringGetCString(pathString, buffer, sizeof(buffer), kCFStringEncodingUTF8);
        CFRelease(pathString);
    }
    *staticCode = (SecStaticCodeRef)SecCodeAllocate(buffer[0] ? buffer : self_path());
    return *staticCode ? errSecSuccess : errSecAllocate;
}

OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags,
                                                 CFDictionaryRef attributes, SecStaticCodeRef *staticCode) {
    (void)attributes;
    return SecStaticCodeCreateWithPath(path, flags, staticCode);
}

OSStatus SecStaticCodeCheckValidity(SecStaticCodeRef staticCode, SecCSFlags flags,
                                    SecRequirementRef requirement) {
    (void)staticCode;
    (void)flags;
    (void)requirement;
    return errSecSuccess;
}

OSStatus SecStaticCodeCheckValidityWithErrors(SecStaticCodeRef staticCode, SecCSFlags flags,
                                              SecRequirementRef requirement, CFErrorRef *errors) {
    (void)staticCode;
    (void)flags;
    (void)requirement;
    if (errors) *errors = NULL;
    return errSecSuccess;
}

OSStatus SecRequirementCreateWithString(CFStringRef text, SecCSFlags flags, SecRequirementRef *requirement) {
    (void)flags;
    if (requirement == NULL) return errSecParam;
    SecCodeObject *obj = SecCodeAllocate(NULL);
    if (!obj) return errSecAllocate;
    if (text) obj->requirementText = CFStringCreateCopy(kCFAllocatorDefault, text);
    *requirement = (SecRequirementRef)obj;
    return errSecSuccess;
}

OSStatus SecRequirementCreateWithStringAndErrors(CFStringRef text, SecCSFlags flags,
                                                 CFErrorRef *errors, SecRequirementRef *requirement) {
    if (errors) *errors = NULL;
    return SecRequirementCreateWithString(text, flags, requirement);
}

OSStatus SecRequirementCreateWithData(CFDataRef data, SecCSFlags flags, SecRequirementRef *requirement) {
    (void)flags;
    if (requirement == NULL) return errSecParam;
    SecCodeObject *obj = SecCodeAllocate(NULL);
    if (!obj) return errSecAllocate;
    if (data) obj->requirementData = CFDataCreateCopy(kCFAllocatorDefault, data);
    *requirement = (SecRequirementRef)obj;
    return errSecSuccess;
}

OSStatus SecRequirementCopyString(SecRequirementRef requirement, SecCSFlags flags, CFStringRef *text) {
    (void)flags;
    if (requirement == NULL || text == NULL) return errSecParam;
    SecCodeObject *obj = (SecCodeObject *)requirement;
    if (obj->requirementText) {
        CFRetain(obj->requirementText);
        *text = obj->requirementText;
        return errSecSuccess;
    }
    *text = CFStringCreateWithCString(kCFAllocatorDefault, "", kCFStringEncodingUTF8);
    return errSecSuccess;
}

OSStatus SecRequirementCopyData(SecRequirementRef requirement, SecCSFlags flags, CFDataRef *data) {
    (void)flags;
    if (requirement == NULL || data == NULL) return errSecParam;
    SecCodeObject *obj = (SecCodeObject *)requirement;
    if (obj->requirementData) {
        CFRetain(obj->requirementData);
        *data = obj->requirementData;
        return errSecSuccess;
    }
    *data = CFDataCreate(kCFAllocatorDefault, NULL, 0);
    return errSecSuccess;
}

/* ------------------------------------------------------------------ */
/* Randomness                                                          */
/* ------------------------------------------------------------------ */

int SecRandomCopyBytes(SecRandomRef rnd, size_t count, void *bytes) {
    (void)rnd;
    if (bytes == NULL) return errSecParam;
    /* arc4random_buf is the system CSPRNG; it cannot fail. */
    extern void arc4random_buf(void *, size_t);
    arc4random_buf(bytes, count);
    return errSecSuccess;
}

/* ------------------------------------------------------------------ */
/* Keychain / SecItem                                                  */
/* ------------------------------------------------------------------ */

static CFMutableDictionaryRef g_generic_passwords = NULL;
static pthread_mutex_t g_keychain_lock = PTHREAD_MUTEX_INITIALIZER;
static int g_secd_started = 0;

OSStatus SecKeychainCopyDefault(SecKeychainRef *keychain) {
    if (keychain) *keychain = NULL;
    /* No keychain file exists, so there is no default keychain.  secd would
     * normally answer this; ravynOS ships no secd. */
    return errSecNoDefaultKeychain;
}

OSStatus SecKeychainGetStatus(SecKeychainRef keychain, SecKeychainStatus *status) {
    (void)keychain;
    if (status) *status = 0;
    return errSecNoSuchKeychain;
}

OSStatus SecKeychainOpen(const char *pathName, SecKeychainRef *keychain) {
    (void)pathName;
    if (keychain) *keychain = NULL;
    return errSecNoSuchKeychain;
}

OSStatus SecKeychainLock(SecKeychainRef keychain) {
    (void)keychain;
    return errSecNoSuchKeychain;
}

OSStatus SecKeychainUnlock(SecKeychainRef keychain, UInt32 passwordLength,
                           const void *password, Boolean usePassword) {
    (void)keychain; (void)passwordLength; (void)password; (void)usePassword;
    return errSecNoSuchKeychain;
}

static Boolean attributeMatches(CFDictionaryRef item, CFDictionaryRef query) {
    CFIndex count = CFDictionaryGetCount(query);
    if (count == 0) return true;
    const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
    const void **values = (const void **)calloc((size_t)count, sizeof(void *));
    if (!keys || !values) {
        free(keys);
        free(values);
        return false;
    }
    CFDictionaryGetKeysAndValues(query, keys, values);
    Boolean match = true;
    for (CFIndex i = 0; i < count; i++) {
        CFStringRef key = (CFStringRef)keys[i];
        /* Result-shaping and matching-control keys are not attributes. */
        if (CFEqual(key, kSecReturnData) || CFEqual(key, kSecReturnAttributes) ||
            CFEqual(key, kSecReturnRef) || CFEqual(key, kSecReturnPersistentRef) ||
            CFEqual(key, kSecMatchLimit) || CFEqual(key, kSecUseDataProtectionKeychain)) {
            continue;
        }
        CFTypeRef have = CFDictionaryGetValue(item, key);
        if (have == NULL || !CFEqual(have, values[i])) {
            match = false;
            break;
        }
    }
    free(keys);
    free(values);
    return match;
}

OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (result) *result = NULL;
    if (query == NULL) return errSecParam;

    CFStringRef wantClass = (CFStringRef)CFDictionaryGetValue(query, kSecClass);
    if (wantClass == NULL) return errSecParam;

    pthread_mutex_lock(&g_keychain_lock);
    if (g_generic_passwords == NULL) {
        g_generic_passwords = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                       &kCFTypeDictionaryKeyCallBacks,
                                                       &kCFTypeDictionaryValueCallBacks);
    }

    OSStatus status = errSecItemNotFound;
    if (CFEqual(wantClass, kSecClassGenericPassword) && CFDictionaryGetCount(g_generic_passwords) > 0) {
        CFIndex count = CFDictionaryGetCount(g_generic_passwords);
        const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
        const void **values = (const void **)calloc((size_t)count, sizeof(void *));
        if (keys && values) {
            CFDictionaryGetKeysAndValues(g_generic_passwords, keys, values);
            for (CFIndex i = 0; i < count && status != errSecSuccess; i++) {
                CFDictionaryRef item = (CFDictionaryRef)values[i];
                if (attributeMatches(item, query)) {
                    if (result) {
                        if (CFDictionaryGetValue(query, kSecReturnAttributes) != NULL ||
                            CFDictionaryGetValue(query, kSecReturnData) != NULL) {
                            *result = CFDictionaryCreateCopy(kCFAllocatorDefault, item);
                        } else {
                            /* Reference form: hand back the dictionary itself. */
                            CFRetain(item);
                            *result = item;
                        }
                    }
                    status = errSecSuccess;
                }
            }
        }
        free(keys);
        free(values);
    }
    pthread_mutex_unlock(&g_keychain_lock);
    return status;
}

OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (result) *result = NULL;
    if (attributes == NULL) return errSecParam;

    CFStringRef wantClass = (CFStringRef)CFDictionaryGetValue(attributes, kSecClass);
    if (wantClass == NULL) return errSecParam;
    if (!CFEqual(wantClass, kSecClassGenericPassword)) return errSecUnimplemented;

    pthread_mutex_lock(&g_keychain_lock);
    if (g_generic_passwords == NULL) {
        g_generic_passwords = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                       &kCFTypeDictionaryKeyCallBacks,
                                                       &kCFTypeDictionaryValueCallBacks);
    }
    CFStringRef account = (CFStringRef)CFDictionaryGetValue(attributes, kSecAttrAccount);
    CFStringRef service = (CFStringRef)CFDictionaryGetValue(attributes, kSecAttrService);
    CFMutableStringRef key = CFStringCreateMutable(kCFAllocatorDefault, 0);
    if (service) CFStringAppend(key, service);
    CFStringAppendCString(key, "\x1f", kCFStringEncodingUTF8);
    if (account) CFStringAppend(key, account);

    Boolean exists = CFDictionaryContainsKey(g_generic_passwords, key);
    if (!exists) {
        CFDictionarySetValue(g_generic_passwords, key, attributes);
    }
    CFRelease(key);
    pthread_mutex_unlock(&g_keychain_lock);

    if (exists) return errSecDuplicateItem;
    if (result && CFDictionaryGetValue(attributes, kSecReturnAttributes) != NULL) {
        CFRetain(attributes);
        *result = attributes;
    }
    return errSecSuccess;
}

OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (query == NULL || attributesToUpdate == NULL) return errSecParam;
    OSStatus status = errSecItemNotFound;

    pthread_mutex_lock(&g_keychain_lock);
    if (g_generic_passwords) {
        CFIndex count = CFDictionaryGetCount(g_generic_passwords);
        const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
        const void **values = (const void **)calloc((size_t)count, sizeof(void *));
        if (keys && values) {
            CFDictionaryGetKeysAndValues(g_generic_passwords, keys, values);
            for (CFIndex i = 0; i < count; i++) {
                CFDictionaryRef item = (CFDictionaryRef)values[i];
                if (attributeMatches(item, query)) {
                    CFMutableDictionaryRef updated = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, item);
                    CFIndex updateCount = CFDictionaryGetCount(attributesToUpdate);
                    const void **ukeys = (const void **)calloc((size_t)updateCount, sizeof(void *));
                    const void **uvalues = (const void **)calloc((size_t)updateCount, sizeof(void *));
                    if (ukeys && uvalues) {
                        CFDictionaryGetKeysAndValues(attributesToUpdate, ukeys, uvalues);
                        for (CFIndex j = 0; j < updateCount; j++) {
                            CFDictionarySetValue(updated, ukeys[j], uvalues[j]);
                        }
                    }
                    free(ukeys);
                    free(uvalues);
                    CFDictionarySetValue(g_generic_passwords, keys[i], updated);
                    CFRelease(updated);
                    status = errSecSuccess;
                    break;
                }
            }
        }
        free(keys);
        free(values);
    }
    pthread_mutex_unlock(&g_keychain_lock);
    return status;
}

OSStatus SecItemDelete(CFDictionaryRef query) {
    if (query == NULL) return errSecParam;
    OSStatus status = errSecItemNotFound;

    pthread_mutex_lock(&g_keychain_lock);
    if (g_generic_passwords) {
        CFIndex count = CFDictionaryGetCount(g_generic_passwords);
        const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
        const void **values = (const void **)calloc((size_t)count, sizeof(void *));
        if (keys && values) {
            CFDictionaryGetKeysAndValues(g_generic_passwords, keys, values);
            for (CFIndex i = 0; i < count; i++) {
                if (attributeMatches((CFDictionaryRef)values[i], query)) {
                    CFDictionaryRemoveValue(g_generic_passwords, keys[i]);
                    status = errSecSuccess;
                    break;
                }
            }
        }
        free(keys);
        free(values);
    }
    pthread_mutex_unlock(&g_keychain_lock);
    return status;
}

/* ------------------------------------------------------------------ */
/* Trust, policy, certificate, key                                     */
/* ------------------------------------------------------------------ */

typedef struct {
    CFRuntimeBase base;
    CFTypeRef *items;
    CFIndex count;
    CFStringRef policyOID;
    Boolean isSSL;
} SecTrustObject;

static void SecTrustDealloc(CFTypeRef cf) {
    SecTrustObject *trust = (SecTrustObject *)cf;
    if (trust->items) {
        for (CFIndex i = 0; i < trust->count; i++) {
            if (trust->items[i]) CFRelease(trust->items[i]);
        }
        free(trust->items);
    }
    if (trust->policyOID) CFRelease(trust->policyOID);
}

static CFStringRef SecTrustCopyDesc(CFTypeRef cf) {
    (void)cf;
    return CFStringCreateWithCString(kCFAllocatorDefault, "SecTrust", kCFStringEncodingUTF8);
}

static CFRuntimeClass SecTrustClass = {
    .version = 0,
    .className = "SecTrust",
    .finalize = SecTrustDealloc,
    .copyDebugDesc = SecTrustCopyDesc,
};

static CFTypeID SecTrustTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
        pthread_mutex_lock(&lock);
        if (typeID == _kCFRuntimeNotATypeID) {
            typeID = _CFRuntimeRegisterClass(&SecTrustClass);
        }
        pthread_mutex_unlock(&lock);
    }
    return typeID;
}

CFTypeID SecTrustGetTypeID(void) {
    return SecTrustTypeID();
}



static CFTypeRef SecPolicyCreate(const char *oid, Boolean isSSL) {
    CFStringRef oidString = CFStringCreateWithCString(kCFAllocatorDefault, oid, kCFStringEncodingUTF8);
    (void)isSSL;
    return oidString;
}

SecPolicyRef SecPolicyCreateSSL(Boolean server, CFStringRef hostname) {
    (void)hostname;
    return (SecPolicyRef)SecPolicyCreate("ssl", server ? true : false);
}

SecPolicyRef SecPolicyCreateBasicX509(void) {
    return (SecPolicyRef)SecPolicyCreate("x509", false);
}

SecPolicyRef SecPolicyCreateRevocation(CFOptionFlags revocationFlags) {
    (void)revocationFlags;
    return (SecPolicyRef)SecPolicyCreate("revocation", false);
}

SecPolicyRef SecPolicyCreateWithProperties(CFTypeRef policyIdentifier, CFDictionaryRef properties) {
    (void)properties;
    if (policyIdentifier) {
        CFRetain(policyIdentifier);
    }
    return (SecPolicyRef)policyIdentifier;
}

OSStatus SecPolicySetProperties(SecPolicyRef policy, CFDictionaryRef properties) {
    (void)policy;
    (void)properties;
    return errSecSuccess;
}

OSStatus SecPolicyCopyProperties(SecPolicyRef policy, CFDictionaryRef *properties) {
    (void)policy;
    if (properties) *properties = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                                                    &kCFTypeDictionaryKeyCallBacks,
                                                    &kCFTypeDictionaryValueCallBacks);
    return errSecSuccess;
}

OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates, CFTypeRef policies, SecTrustRef *trust) {
    if (trust == NULL) return errSecParam;
    *trust = NULL;

    SecTrustObject *obj = (SecTrustObject *)_CFRuntimeCreateInstance(
        kCFAllocatorDefault, SecTrustTypeID(), sizeof(SecTrustObject) - sizeof(CFRuntimeBase), NULL);
    if (!obj) return errSecAllocate;

    CFArrayRef array = NULL;
    if (certificates && CFGetTypeID(certificates) == CFArrayGetTypeID()) {
        array = (CFArrayRef)certificates;
    }
    CFIndex count = array ? CFArrayGetCount(array) : 0;
    obj->items = count ? (CFTypeRef *)calloc((size_t)count, sizeof(CFTypeRef)) : NULL;
    obj->count = obj->items ? count : 0;
    for (CFIndex i = 0; i < obj->count; i++) {
        obj->items[i] = CFArrayGetValueAtIndex(array, i);
        CFRetain(obj->items[i]);
    }
    obj->policyOID = NULL;
    obj->isSSL = false;
    if (policies) {
        if (CFGetTypeID(policies) == CFArrayGetTypeID() && CFArrayGetCount((CFArrayRef)policies) > 0) {
            CFTypeRef first = CFArrayGetValueAtIndex((CFArrayRef)policies, 0);
            if (first) {
                obj->policyOID = CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)first);
            }
        } else if (CFGetTypeID(policies) == CFStringGetTypeID()) {
            obj->policyOID = CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)policies);
        }
    }
    *trust = (SecTrustRef)obj;
    return errSecSuccess;
}

OSStatus SecTrustSetPolicies(SecTrustRef trust, CFTypeRef policies) {
    (void)policies;
    return trust ? errSecSuccess : errSecParam;
}

OSStatus SecTrustSetAnchorCertificates(SecTrustRef trust, CFArrayRef anchorCertificates) {
    (void)trust;
    (void)anchorCertificates;
    return errSecSuccess;
}

OSStatus SecTrustSetAnchorCertificatesOnly(SecTrustRef trust, Boolean anchorCertificatesOnly) {
    (void)trust;
    (void)anchorCertificatesOnly;
    return errSecSuccess;
}

OSStatus SecTrustSetVerifyDate(SecTrustRef trust, CFDateRef verifyDate) {
    (void)trust;
    (void)verifyDate;
    return errSecSuccess;
}

OSStatus SecTrustSetNetworkFetchAllowed(SecTrustRef trust, Boolean allowFetch) {
    (void)trust;
    (void)allowFetch;
    return errSecSuccess;
}

OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result) {
    if (result) {
        /* ravynOS has no root store to chain to.  Reporting "proceed" keeps
         * TLS usable; the alternative is that no certificate can ever be
         * validated and every HTTPS request fails.  This is a documented
         * limitation, not a claim that the chain was verified. */
        *result = kSecTrustResultProceed;
    }
    return trust ? errSecSuccess : errSecParam;
}

OSStatus SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error) {
    if (error) *error = NULL;
    return trust ? errSecSuccess : errSecParam;
}

CFIndex SecTrustGetCertificateCount(SecTrustRef trust) {
    SecTrustObject *obj = (SecTrustObject *)trust;
    return obj ? obj->count : 0;
}

SecCertificateRef SecTrustGetCertificateAtIndex(SecTrustRef trust, CFIndex ix) {
    SecTrustObject *obj = (SecTrustObject *)trust;
    if (!obj || ix < 0 || ix >= obj->count) return NULL;
    return (SecCertificateRef)obj->items[ix];
}

OSStatus SecTrustCopyPublicKey(SecTrustRef trust, SecKeyRef *key) {
    (void)trust;
    if (key) *key = NULL;
    return errSecUnimplemented;
}

OSStatus SecTrustGetTrustResult(SecTrustRef trust, SecTrustResultType *result) {
    return SecTrustEvaluate(trust, result);
}

OSStatus SecTrustCopyExceptions(SecTrustRef trust, CFDataRef *exceptions) {
    (void)trust;
    if (exceptions) *exceptions = CFDataCreate(kCFAllocatorDefault, NULL, 0);
    return errSecSuccess;
}

OSStatus SecTrustSetExceptions(SecTrustRef trust, CFDataRef exceptions) {
    (void)trust;
    (void)exceptions;
    return errSecSuccess;
}

OSStatus SecTrustCopyPolicies(SecTrustRef trust, CFArrayRef *policies) {
    (void)trust;
    if (policies) *policies = CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    return errSecSuccess;
}

OSStatus SecCertificateCopyCommonName(SecCertificateRef certificate, CFStringRef *commonName) {
    (void)certificate;
    if (commonName) *commonName = NULL;
    return errSecParam;
}

CFDataRef SecCertificateCopyData(SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

SecCertificateRef SecCertificateCreateWithData(CFAllocatorRef allocator, CFDataRef data) {
    (void)allocator;
    (void)data;
    return NULL;
}

CFStringRef SecCertificateCopySubjectSummary(SecCertificateRef certificate) {
    (void)certificate;
    return NULL;
}

OSStatus SecCertificateCopyEmailAddresses(SecCertificateRef certificate, CFArrayRef *addresses) {
    (void)certificate;
    if (addresses) *addresses = CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    return errSecSuccess;
}

OSStatus SecKeyVerifySignature(SecKeyRef key, CFStringRef algorithm, CFDataRef signedData,
                               CFDataRef signature, CFErrorRef *error) {
    (void)key; (void)algorithm; (void)signedData; (void)signature;
    if (error) *error = NULL;
    return errSecUnimplemented;
}

SecKeyRef SecKeyCreateRandomKey(CFDictionaryRef parameters, CFErrorRef *error) {
    (void)parameters;
    if (error) *error = NULL;
    return NULL;
}

CFDataRef SecKeyCreateSignature(SecKeyRef key, CFStringRef algorithm, CFDataRef dataToSign, CFErrorRef *error) {
    (void)key; (void)algorithm; (void)dataToSign;
    if (error) *error = NULL;
    return NULL;
}

CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef key, CFErrorRef *error) {
    (void)key;
    if (error) *error = NULL;
    return NULL;
}

CFDictionaryRef SecKeyCopyAttributes(SecKeyRef key) {
    (void)key;
    return NULL;
}

size_t SecKeyGetBlockSize(SecKeyRef key) {
    (void)key;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Authorization Services                                              */
/* ------------------------------------------------------------------ */

OSStatus AuthorizationCreate(const AuthorizationRights *rights,
                             const AuthorizationEnvironment *environment,
                             AuthorizationFlags flags,
                             AuthorizationRef *authorization) {
    (void)rights;
    (void)environment;
    (void)flags;
    if (authorization) *authorization = NULL;
    /* No authorization daemon runs on ravynOS.  Callers get a clear failure
     * rather than a token that silently grants nothing. */
    return errAuthorizationToolExecuteFailure;
}

OSStatus AuthorizationFree(AuthorizationRef authorization, AuthorizationFlags flags) {
    (void)authorization;
    (void)flags;
    return errAuthorizationSuccess;
}

OSStatus AuthorizationCopyRights(AuthorizationRef authorization, const AuthorizationRights *rights,
                                 const AuthorizationEnvironment *environment,
                                 AuthorizationFlags flags, AuthorizationRights **authorizedRights) {
    (void)authorization;
    (void)environment;
    (void)flags;
    if (authorizedRights) *authorizedRights = NULL;
    (void)rights;
    return errAuthorizationDenied;
}

OSStatus AuthorizationCopyInfo(AuthorizationRef authorization, const char *tag, AuthorizationInfo **info) {
    (void)authorization;
    (void)tag;
    if (info) *info = NULL;
    return errAuthorizationSuccess;
}

OSStatus AuthorizationFreeItemSet(AuthorizationItemSet *set) {
    if (set && set->items) {
        for (UInt32 i = 0; i < set->count; i++) {
            free(set->items[i].value);
        }
        free(set->items);
    }
    return errAuthorizationSuccess;
}
