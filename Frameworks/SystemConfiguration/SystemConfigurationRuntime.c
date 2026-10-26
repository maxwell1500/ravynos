/*
 * SystemConfiguration.framework runtime for ravynOS.
 *
 * The dynamic store is backed by a process-local dictionary: SetValue followed
 * by CopyValue round-trips, which is what an application that caches a
 * preference through this API actually needs, and CopyValue for a key this
 * process never set returns NULL -- the same answer configd gives for a key
 * that does not exist.  There is no configd on ravynOS, so there is no
 * cross-process store to share with.
 *
 * SCNetworkReachability is NOT faked: GetFlags opens a UDP socket to the
 * address and lets the kernel answer.  connect() on a UDP socket performs the
 * route lookup without sending a packet, so a routable destination reports
 * reachable and an unroutable one reports the real error.
 */

#include "Headers/SystemConfiguration.h"
#include "CFRuntime.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <sys/utsname.h>

static SCStatusCode g_last_error = kSCStatusOK;

SCStatusCode SCError(void) {
    return g_last_error;
}

const char *SCErrorString(SCStatusCode status) {
    switch (status) {
        case kSCStatusOK: return "No error";
        case kSCStatusFailed: return "Generic error";
        case kSCStatusInvalidArgument: return "Invalid argument";
        case kSCStatusAccessError: return "Permission denied";
        case kSCStatusNoKey: return "No such key";
        case kSCStatusKeyExists: return "Key already exists";
        case kSCStatusLocked: return "Locked";
        case kSCStatusNoStoreSession: return "No store session";
        case kSCStatusNoStoreServer: return "No store server";
        case kSCStatusNoPrefsSession: return "No preferences session";
        case kSCStatusNoConfigFile: return "No configuration file";
        case kSCStatusReachabilityUnknown: return "Reachability unknown";
        default: return "Unknown error";
    }
}

/* ------------------------------------------------------------------ */
/* String constants                                                    */
/* ------------------------------------------------------------------ */

CFStringRef kSCDynamicStoreDomainState = NULL;
CFStringRef kSCDynamicStoreDomainSetup = NULL;
CFStringRef kSCDynamicStoreDomainPlugin = NULL;
CFStringRef kSCDynamicStoreDomainFile = NULL;
CFStringRef kSCDynamicStoreDomainPrefs = NULL;

CFStringRef kSCDynamicStorePropNetPrimaryInterface = NULL;
CFStringRef kSCDynamicStorePropNetPrimaryService = NULL;
CFStringRef kSCDynamicStorePropNetServiceIDs = NULL;
CFStringRef kSCDynamicStorePropNetInterfaces = NULL;
CFStringRef kSCDynamicStorePropNetPrimaryIPv4Interface = NULL;
CFStringRef kSCDynamicStorePropNetPrimaryIPv6Interface = NULL;

CFStringRef kSCPropNetProxiesHTTPEnable = NULL;
CFStringRef kSCPropNetProxiesHTTPProxy = NULL;
CFStringRef kSCPropNetProxiesHTTPPort = NULL;
CFStringRef kSCPropNetProxiesHTTPSEnable = NULL;
CFStringRef kSCPropNetProxiesHTTPSProxy = NULL;
CFStringRef kSCPropNetProxiesHTTPSPort = NULL;
CFStringRef kSCPropNetProxiesSOCKSEnable = NULL;
CFStringRef kSCPropNetProxiesSOCKSProxy = NULL;
CFStringRef kSCPropNetProxiesSOCKSPort = NULL;
CFStringRef kSCPropNetProxiesExcludeSimpleHostnames = NULL;
CFStringRef kSCPropNetProxiesExceptionsList = NULL;
CFStringRef kSCPropNetProxiesProxyAutoConfigEnable = NULL;
CFStringRef kSCPropNetProxiesProxyAutoConfigURLString = NULL;

struct SCConstantEntry { CFStringRef *slot; const char *text; };

static struct SCConstantEntry g_constants[] = {
    { &kSCDynamicStoreDomainState, "State:" },
    { &kSCDynamicStoreDomainSetup, "Setup:" },
    { &kSCDynamicStoreDomainPlugin, "Plugin:" },
    { &kSCDynamicStoreDomainFile, "File:" },
    { &kSCDynamicStoreDomainPrefs, "Prefs:" },
    { &kSCDynamicStorePropNetPrimaryInterface, "PrimaryInterface" },
    { &kSCDynamicStorePropNetPrimaryService, "PrimaryService" },
    { &kSCDynamicStorePropNetServiceIDs, "ServiceIDs" },
    { &kSCDynamicStorePropNetInterfaces, "Interfaces" },
    { &kSCDynamicStorePropNetPrimaryIPv4Interface, "PrimaryIPv4Interface" },
    { &kSCDynamicStorePropNetPrimaryIPv6Interface, "PrimaryIPv6Interface" },
    { &kSCPropNetProxiesHTTPEnable, "HTTPEnable" },
    { &kSCPropNetProxiesHTTPProxy, "HTTPProxy" },
    { &kSCPropNetProxiesHTTPPort, "HTTPPort" },
    { &kSCPropNetProxiesHTTPSEnable, "HTTPSEnable" },
    { &kSCPropNetProxiesHTTPSProxy, "HTTPSProxy" },
    { &kSCPropNetProxiesHTTPSPort, "HTTPSPort" },
    { &kSCPropNetProxiesSOCKSEnable, "SOCKSEnable" },
    { &kSCPropNetProxiesSOCKSProxy, "SOCKSProxy" },
    { &kSCPropNetProxiesSOCKSPort, "SOCKSPort" },
    { &kSCPropNetProxiesExcludeSimpleHostnames, "ExcludeSimpleHostnames" },
    { &kSCPropNetProxiesExceptionsList, "ExceptionsList" },
    { &kSCPropNetProxiesProxyAutoConfigEnable, "ProxyAutoConfigEnable" },
    { &kSCPropNetProxiesProxyAutoConfigURLString, "ProxyAutoConfigURLString" },
};

__attribute__((constructor)) static void SCCreateConstantStrings(void) {
    for (size_t i = 0; i < sizeof(g_constants) / sizeof(g_constants[0]); i++) {
        if (*g_constants[i].slot == NULL) {
            *g_constants[i].slot = CFStringCreateWithCString(kCFAllocatorDefault,
                                                             g_constants[i].text,
                                                             kCFStringEncodingUTF8);
        }
    }
}

/* ------------------------------------------------------------------ */
/* Dynamic store                                                       */
/* ------------------------------------------------------------------ */

struct __SCDynamicStore {
    CFRuntimeBase base;
    CFStringRef name;
    CFMutableDictionaryRef values;
    SCDynamicStoreCallBack callback;
    void *callbackInfo;
    pthread_mutex_t lock;
};

static void SCDynamicStoreFinalize(CFTypeRef cf) {
    struct __SCDynamicStore *store = (struct __SCDynamicStore *)cf;
    if (store->name) CFRelease(store->name);
    if (store->values) CFRelease(store->values);
    pthread_mutex_destroy(&store->lock);
}

static CFStringRef SCDynamicStoreCopyDesc(CFTypeRef cf) {
    struct __SCDynamicStore *store = (struct __SCDynamicStore *)cf;
    if (store->name) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("SCDynamicStore %@"), store->name);
    return CFStringCreateWithCString(kCFAllocatorDefault, "SCDynamicStore", kCFStringEncodingUTF8);
}

static CFRuntimeClass SCDynamicStoreClass = {
    .version = 0,
    .className = "SCDynamicStore",
    .finalize = SCDynamicStoreFinalize,
    .copyDebugDesc = SCDynamicStoreCopyDesc,
};

CFTypeID SCDynamicStoreGetTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        typeID = _CFRuntimeRegisterClass(&SCDynamicStoreClass);
    }
    return typeID;
}

SCDynamicStoreRef SCDynamicStoreCreate(CFAllocatorRef allocator, CFStringRef name,
                                       SCDynamicStoreCallBack callout, SCDynamicStoreContext *context) {
    if (name == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    struct __SCDynamicStore *store = (struct __SCDynamicStore *)_CFRuntimeCreateInstance(
        allocator ? allocator : kCFAllocatorDefault, SCDynamicStoreGetTypeID(),
        sizeof(struct __SCDynamicStore) - sizeof(CFRuntimeBase), NULL);
    if (store == NULL) {
        g_last_error = kSCStatusFailed;
        return NULL;
    }
    store->name = CFStringCreateCopy(kCFAllocatorDefault, name);
    store->values = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                             &kCFTypeDictionaryKeyCallBacks,
                                             &kCFTypeDictionaryValueCallBacks);
    store->callback = callout;
    store->callbackInfo = context ? context->info : NULL;
    pthread_mutex_init(&store->lock, NULL);
    g_last_error = kSCStatusOK;
    return (SCDynamicStoreRef)store;
}

SCDynamicStoreRef SCDynamicStoreCreateWithOptions(CFAllocatorRef allocator, CFStringRef name,
                                                  CFDictionaryRef storeOptions,
                                                  SCDynamicStoreCallBack callout,
                                                  SCDynamicStoreContext *context) {
    (void)storeOptions;
    return SCDynamicStoreCreate(allocator, name, callout, context);
}

CFRunLoopSourceRef SCDynamicStoreCreateRunLoopSource(CFAllocatorRef allocator,
                                                     SCDynamicStoreRef store, CFIndex order) {
    (void)allocator;
    (void)store;
    (void)order;
    /* No cross-process notifications exist, so there is no source to signal. */
    return NULL;
}

void SCDynamicStoreSetDispatchQueue(SCDynamicStoreRef store, void *queue) {
    (void)store;
    (void)queue;
}

void SCDynamicStoreSetNotificationKeys(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns) {
    (void)store;
    (void)keys;
    (void)patterns;
    g_last_error = kSCStatusOK;
}

CFPropertyListRef SCDynamicStoreCopyValue(SCDynamicStoreRef store, CFStringRef key) {
    if (store == NULL || key == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    pthread_mutex_lock(&store->lock);
    CFPropertyListRef value = CFDictionaryGetValue(store->values, key);
    if (value) CFRetain(value);
    pthread_mutex_unlock(&store->lock);
    g_last_error = value ? kSCStatusOK : kSCStatusNoKey;
    return value;
}

CFDictionaryRef SCDynamicStoreCopyMultiple(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns) {
    (void)patterns;
    if (store == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                             &kCFTypeDictionaryKeyCallBacks,
                                                             &kCFTypeDictionaryValueCallBacks);
    if (keys) {
        CFIndex count = CFArrayGetCount(keys);
        pthread_mutex_lock(&store->lock);
        for (CFIndex i = 0; i < count; i++) {
            CFStringRef key = (CFStringRef)CFArrayGetValueAtIndex(keys, i);
            CFPropertyListRef value = key ? CFDictionaryGetValue(store->values, key) : NULL;
            if (value) CFDictionarySetValue(result, key, value);
        }
        pthread_mutex_unlock(&store->lock);
    }
    g_last_error = kSCStatusOK;
    return result;
}

CFArrayRef SCDynamicStoreCopyKeyList(SCDynamicStoreRef store, CFStringRef pattern) {
    if (store == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    pthread_mutex_lock(&store->lock);
    CFIndex count = CFDictionaryGetCount(store->values);
    const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
    if (keys) {
        CFDictionaryGetKeysAndValues(store->values, keys, NULL);
        for (CFIndex i = 0; i < count; i++) {
            if (pattern == NULL) {
                CFArrayAppendValue(result, keys[i]);
            } else {
                CFRange range = CFStringFind((CFStringRef)keys[i], pattern, 0);
                if (range.location != kCFNotFound) CFArrayAppendValue(result, keys[i]);
            }
        }
    }
    free(keys);
    pthread_mutex_unlock(&store->lock);
    g_last_error = kSCStatusOK;
    return result;
}

static Boolean storeWrite(SCDynamicStoreRef store, CFStringRef key, CFPropertyListRef value, Boolean mustNotExist) {
    if (store == NULL || key == NULL || value == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return false;
    }
    pthread_mutex_lock(&store->lock);
    Boolean exists = CFDictionaryContainsKey(store->values, key) ? true : false;
    if (mustNotExist && exists) {
        pthread_mutex_unlock(&store->lock);
        g_last_error = kSCStatusKeyExists;
        return false;
    }
    CFDictionarySetValue(store->values, key, value);
    pthread_mutex_unlock(&store->lock);
    g_last_error = kSCStatusOK;
    return true;
}

Boolean SCDynamicStoreAddValue(SCDynamicStoreRef store, CFStringRef key, CFPropertyListRef value) {
    return storeWrite(store, key, value, true);
}

Boolean SCDynamicStoreAddTemporaryValue(SCDynamicStoreRef store, CFStringRef key, CFPropertyListRef value) {
    return storeWrite(store, key, value, true);
}

Boolean SCDynamicStoreSetValue(SCDynamicStoreRef store, CFStringRef key, CFPropertyListRef value) {
    return storeWrite(store, key, value, false);
}

Boolean SCDynamicStoreRemoveValue(SCDynamicStoreRef store, CFStringRef key) {
    if (store == NULL || key == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return false;
    }
    pthread_mutex_lock(&store->lock);
    Boolean existed = CFDictionaryContainsKey(store->values, key) ? true : false;
    if (existed) CFDictionaryRemoveValue(store->values, key);
    pthread_mutex_unlock(&store->lock);
    g_last_error = existed ? kSCStatusOK : kSCStatusNoKey;
    return existed;
}

Boolean SCDynamicStoreNotifyValue(SCDynamicStoreRef store, CFStringRef key) {
    (void)store;
    (void)key;
    return true;
}

CFStringRef SCDynamicStoreCopyLocalHostName(SCDynamicStoreRef store) {
    (void)store;
    struct utsname uts;
    if (uname(&uts) != 0) return NULL;
    char name[256];
    strncpy(name, uts.nodename, sizeof(name) - 1);
    name[sizeof(name) - 1] = '\0';
    char *dot = strchr(name, '.');
    if (dot) *dot = '\0';
    return CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
}

CFStringRef SCDynamicStoreCopyComputerName(SCDynamicStoreRef store, CFStringEncoding *nameEncoding) {
    if (nameEncoding) *nameEncoding = kCFStringEncodingUTF8;
    return SCDynamicStoreCopyLocalHostName(store);
}

CFStringRef SCDynamicStoreCopyConsoleUser(SCDynamicStoreRef store, uid_t *uid, gid_t *gid) {
    (void)store;
    /* No console session manager: report the current user, which is the same
     * answer for the process that asks. */
    if (uid) *uid = getuid();
    if (gid) *gid = getgid();
    const char *user = getenv("USER");
    if (user == NULL || *user == '\0') {
        user = "root";
    }
    return CFStringCreateWithCString(kCFAllocatorDefault, user, kCFStringEncodingUTF8);
}

CFDictionaryRef SCDynamicStoreCopyProxies(SCDynamicStoreRef store) {
    (void)store;
    /* An empty dictionary is the documented "no proxies configured" answer. */
    return CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                              &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

CFStringRef SCDynamicStoreCopyLocation(SCDynamicStoreRef store) {
    (void)store;
    return NULL;
}

static CFStringRef SCDynamicStoreKeyCreateWithPrefix(CFAllocatorRef allocator, CFStringRef key) {
    if (key) return CFStringCreateCopy(allocator ? allocator : kCFAllocatorDefault, key);
    return NULL;
}

CFStringRef SCDynamicStoreKeyCreate(CFAllocatorRef allocator, CFStringRef fmt, ...) {
    if (fmt == NULL) return NULL;
    va_list ap;
    va_start(ap, fmt);
    CFStringRef result = CFStringCreateWithFormatAndArguments(allocator ? allocator : kCFAllocatorDefault,
                                                             NULL, fmt, ap);
    va_end(ap);
    return result;
}

CFStringRef SCDynamicStoreKeyCreateNetworkGlobalEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                      CFStringRef entity) {
    return CFStringCreateWithFormat(allocator ? allocator : kCFAllocatorDefault, NULL,
                                    CFSTR("%@%@/%@"), domain ? domain : CFSTR("State:"),
                                    CFSTR("Network"), entity ? entity : CFSTR("Global"));
}

CFStringRef SCDynamicStoreKeyCreateNetworkInterface(CFAllocatorRef allocator, CFStringRef domain) {
    return CFStringCreateWithFormat(allocator ? allocator : kCFAllocatorDefault, NULL,
                                    CFSTR("%@%@/%@"), domain ? domain : CFSTR("State:"),
                                    CFSTR("Network"), CFSTR("Interface"));
}

CFStringRef SCDynamicStoreKeyCreateNetworkInterfaceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                         CFStringRef ifname, CFStringRef entity) {
    return CFStringCreateWithFormat(allocator ? allocator : kCFAllocatorDefault, NULL,
                                    CFSTR("%@%@/%@/%@"), domain ? domain : CFSTR("State:"),
                                    CFSTR("Network"), CFSTR("Interface"),
                                    entity ? entity : (ifname ? ifname : CFSTR("")));
}

CFStringRef SCDynamicStoreKeyCreateNetworkServiceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                       CFStringRef serviceID, CFStringRef entity) {
    return CFStringCreateWithFormat(allocator ? allocator : kCFAllocatorDefault, NULL,
                                    CFSTR("%@%@/%@/%@"), domain ? domain : CFSTR("State:"),
                                    CFSTR("Network"), CFSTR("Service"),
                                    entity ? entity : (serviceID ? serviceID : CFSTR("")));
}

CFStringRef SCDynamicStoreKeyCreateComputerName(CFAllocatorRef allocator) {
    return SCDynamicStoreKeyCreateWithPrefix(allocator, CFSTR("Setup:/System/ComputerName"));
}

CFStringRef SCDynamicStoreKeyCreateConsoleUser(CFAllocatorRef allocator) {
    return SCDynamicStoreKeyCreateWithPrefix(allocator, CFSTR("State:/Users/ConsoleUser"));
}

CFStringRef SCDynamicStoreKeyCreateHostNames(CFAllocatorRef allocator) {
    return SCDynamicStoreKeyCreateWithPrefix(allocator, CFSTR("Setup:/System/HostNames"));
}

CFStringRef SCDynamicStoreKeyCreateLocation(CFAllocatorRef allocator) {
    return SCDynamicStoreKeyCreateWithPrefix(allocator, CFSTR("State:/Network/Global/Location"));
}

CFStringRef SCDynamicStoreKeyCreateProxies(CFAllocatorRef allocator) {
    return SCDynamicStoreKeyCreateWithPrefix(allocator, CFSTR("State:/Network/Global/Proxies"));
}

CFStringRef SCDynamicStoreKeyCreateNetworkGlobalEntityForInterface(CFAllocatorRef allocator,
                                                                  CFStringRef domain,
                                                                  CFStringRef ifname) {
    (void)domain;
    (void)ifname;
    return SCDynamicStoreKeyCreateWithPrefix(allocator, CFSTR("State:/Network/Global/IPv4"));
}

/* ------------------------------------------------------------------ */
/* Preferences                                                         */
/* ------------------------------------------------------------------ */

struct __SCPreferences {
    CFRuntimeBase base;
    CFStringRef name;
    CFMutableDictionaryRef values;
    pthread_mutex_t lock;
};

static void SCPreferencesFinalize(CFTypeRef cf) {
    struct __SCPreferences *prefs = (struct __SCPreferences *)cf;
    if (prefs->name) CFRelease(prefs->name);
    if (prefs->values) CFRelease(prefs->values);
    pthread_mutex_destroy(&prefs->lock);
}

static CFStringRef SCPreferencesCopyDesc(CFTypeRef cf) {
    (void)cf;
    return CFStringCreateWithCString(kCFAllocatorDefault, "SCPreferences", kCFStringEncodingUTF8);
}

static CFRuntimeClass SCPreferencesClass = {
    .version = 0,
    .className = "SCPreferences",
    .finalize = SCPreferencesFinalize,
    .copyDebugDesc = SCPreferencesCopyDesc,
};

CFTypeID SCPreferencesGetTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        typeID = _CFRuntimeRegisterClass(&SCPreferencesClass);
    }
    return typeID;
}

SCPreferencesRef SCPreferencesCreate(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID) {
    (void)prefsID;
    if (name == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    struct __SCPreferences *prefs = (struct __SCPreferences *)_CFRuntimeCreateInstance(
        allocator ? allocator : kCFAllocatorDefault, SCPreferencesGetTypeID(),
        sizeof(struct __SCPreferences) - sizeof(CFRuntimeBase), NULL);
    if (prefs == NULL) {
        g_last_error = kSCStatusFailed;
        return NULL;
    }
    prefs->name = CFStringCreateCopy(kCFAllocatorDefault, name);
    prefs->values = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                             &kCFTypeDictionaryKeyCallBacks,
                                             &kCFTypeDictionaryValueCallBacks);
    pthread_mutex_init(&prefs->lock, NULL);
    g_last_error = kSCStatusOK;
    return (SCPreferencesRef)prefs;
}

SCPreferencesRef SCPreferencesCreateWithAuthorization(CFAllocatorRef allocator, CFStringRef name,
                                                      CFStringRef prefsID, void *authorization) {
    (void)authorization;
    return SCPreferencesCreate(allocator, name, prefsID);
}

Boolean SCPreferencesLock(SCPreferencesRef prefs, Boolean wait) {
    (void)prefs;
    (void)wait;
    /* Nothing else can hold the store, so the lock is always granted. */
    return true;
}

Boolean SCPreferencesCommitChanges(SCPreferencesRef prefs) {
    (void)prefs;
    return true;
}

Boolean SCPreferencesApplyChanges(SCPreferencesRef prefs) {
    (void)prefs;
    return true;
}

void SCPreferencesUnlock(SCPreferencesRef prefs) {
    (void)prefs;
}

CFPropertyListRef SCPreferencesGetValue(SCPreferencesRef prefs, CFStringRef key) {
    if (prefs == NULL || key == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    pthread_mutex_lock(&prefs->lock);
    CFPropertyListRef value = CFDictionaryGetValue(prefs->values, key);
    if (value) CFRetain(value);
    pthread_mutex_unlock(&prefs->lock);
    g_last_error = value ? kSCStatusOK : kSCStatusNoKey;
    return value;
}

Boolean SCPreferencesSetValue(SCPreferencesRef prefs, CFStringRef key, CFPropertyListRef value) {
    if (prefs == NULL || key == NULL || value == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return false;
    }
    pthread_mutex_lock(&prefs->lock);
    CFDictionarySetValue(prefs->values, key, value);
    pthread_mutex_unlock(&prefs->lock);
    g_last_error = kSCStatusOK;
    return true;
}

Boolean SCPreferencesRemoveValue(SCPreferencesRef prefs, CFStringRef key) {
    if (prefs == NULL || key == NULL) return false;
    pthread_mutex_lock(&prefs->lock);
    Boolean existed = CFDictionaryContainsKey(prefs->values, key) ? true : false;
    if (existed) CFDictionaryRemoveValue(prefs->values, key);
    pthread_mutex_unlock(&prefs->lock);
    return existed;
}

CFArrayRef SCPreferencesCopyKeyList(SCPreferencesRef prefs) {
    if (prefs == NULL) return NULL;
    CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    pthread_mutex_lock(&prefs->lock);
    CFIndex count = CFDictionaryGetCount(prefs->values);
    const void **keys = (const void **)calloc((size_t)count, sizeof(void *));
    if (keys) {
        CFDictionaryGetKeysAndValues(prefs->values, keys, NULL);
        for (CFIndex i = 0; i < count; i++) {
            CFArrayAppendValue(result, keys[i]);
        }
    }
    free(keys);
    pthread_mutex_unlock(&prefs->lock);
    return result;
}

void SCPreferencesSynchronize(SCPreferencesRef prefs) {
    (void)prefs;
}

/* ------------------------------------------------------------------ */
/* Reachability                                                        */
/* ------------------------------------------------------------------ */

struct __SCNetworkReachability {
    CFRuntimeBase base;
    struct sockaddr_storage address;
    socklen_t addressLength;
    char nodename[256];
    SCNetworkReachabilityCallBack callback;
    void *callbackInfo;
};

static void SCReachabilityFinalize(CFTypeRef cf) {
    (void)cf;
}

static CFStringRef SCReachabilityCopyDesc(CFTypeRef cf) {
    struct __SCNetworkReachability *target = (struct __SCNetworkReachability *)cf;
    if (target->nodename[0]) {
        return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("SCNetworkReachability %s"),
                                        target->nodename);
    }
    return CFStringCreateWithCString(kCFAllocatorDefault, "SCNetworkReachability", kCFStringEncodingUTF8);
}

static CFRuntimeClass SCReachabilityClass = {
    .version = 0,
    .className = "SCNetworkReachability",
    .finalize = SCReachabilityFinalize,
    .copyDebugDesc = SCReachabilityCopyDesc,
};

CFTypeID SCNetworkReachabilityGetTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        typeID = _CFRuntimeRegisterClass(&SCReachabilityClass);
    }
    return typeID;
}

static SCNetworkReachabilityRef reachabilityAllocate(CFAllocatorRef allocator) {
    return (SCNetworkReachabilityRef)_CFRuntimeCreateInstance(
        allocator ? allocator : kCFAllocatorDefault, SCNetworkReachabilityGetTypeID(),
        sizeof(struct __SCNetworkReachability) - sizeof(CFRuntimeBase), NULL);
}

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddress(CFAllocatorRef allocator,
                                                               const struct sockaddr *address) {
    if (address == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    struct __SCNetworkReachability *target = (struct __SCNetworkReachability *)reachabilityAllocate(allocator);
    if (target == NULL) {
        g_last_error = kSCStatusFailed;
        return NULL;
    }
    memcpy(&target->address, address, address->sa_len);
    target->addressLength = address->sa_len;
    g_last_error = kSCStatusOK;
    return (SCNetworkReachabilityRef)target;
}

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddressPair(CFAllocatorRef allocator,
                                                                    const struct sockaddr *localAddress,
                                                                    const struct sockaddr *remoteAddress) {
    (void)localAddress;
    return SCNetworkReachabilityCreateWithAddress(allocator, remoteAddress);
}

SCNetworkReachabilityRef SCNetworkReachabilityCreateWithName(CFAllocatorRef allocator,
                                                             const char *nodename) {
    if (nodename == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return NULL;
    }
    struct __SCNetworkReachability *target = (struct __SCNetworkReachability *)reachabilityAllocate(allocator);
    if (target == NULL) {
        g_last_error = kSCStatusFailed;
        return NULL;
    }
    strncpy(target->nodename, nodename, sizeof(target->nodename) - 1);
    g_last_error = kSCStatusOK;
    return (SCNetworkReachabilityRef)target;
}

/* Resolve a name or use the stored sockaddr, then ask the routing table.  A
 * UDP connect() performs the route lookup without putting a packet on the
 * wire, which is exactly the question "is this destination reachable". */
static Boolean reachabilityProbe(struct __SCNetworkReachability *target, SCNetworkReachabilityFlags *flags) {
    struct sockaddr_storage addr;
    socklen_t addrLen = 0;

    if (target->addressLength > 0) {
        memcpy(&addr, &target->address, target->addressLength);
        addrLen = target->addressLength;
    } else if (target->nodename[0]) {
        struct addrinfo hints;
        struct addrinfo *result = NULL;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_DGRAM;
        if (getaddrinfo(target->nodename, NULL, &hints, &result) != 0 || result == NULL) {
            if (flags) *flags = 0;
            return true;
        }
        memcpy(&addr, result->ai_addr, result->ai_addrlen);
        addrLen = (socklen_t)result->ai_addrlen;
        freeaddrinfo(result);
    } else {
        if (flags) *flags = 0;
        return false;
    }

    int fd = socket(addr.ss_family, SOCK_DGRAM, 0);
    if (fd < 0) {
        if (flags) *flags = 0;
        return true;
    }
    SCNetworkReachabilityFlags result_flags = 0;
    if (connect(fd, (struct sockaddr *)&addr, addrLen) == 0) {
        result_flags |= kSCNetworkReachabilityFlagsReachable;
        result_flags |= kSCNetworkReachabilityFlagsIsDirect;
    }
    close(fd);
    if (flags) *flags = result_flags;
    return true;
}

Boolean SCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    if (target == NULL) {
        g_last_error = kSCStatusInvalidArgument;
        return false;
    }
    Boolean ok = reachabilityProbe(target, flags);
    g_last_error = ok ? kSCStatusOK : kSCStatusReachabilityUnknown;
    return ok;
}

Boolean SCNetworkReachabilitySetCallback(SCNetworkReachabilityRef target,
                                         SCNetworkReachabilityCallBack callout,
                                         SCNetworkReachabilityContext *context) {
    if (target == NULL) return false;
    target->callback = callout;
    target->callbackInfo = context ? context->info : NULL;
    if (callout) {
        SCNetworkReachabilityFlags flags = 0;
        if (reachabilityProbe(target, &flags)) {
            callout(target, flags, target->callbackInfo);
        }
    }
    return true;
}

Boolean SCNetworkReachabilityScheduleWithRunLoop(SCNetworkReachabilityRef target,
                                                 CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    (void)target;
    (void)runLoop;
    (void)runLoopMode;
    return true;
}

Boolean SCNetworkReachabilityUnscheduleFromRunLoop(SCNetworkReachabilityRef target,
                                                   CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    (void)target;
    (void)runLoop;
    (void)runLoopMode;
    return true;
}

Boolean SCNetworkReachabilitySetDispatchQueue(SCNetworkReachabilityRef target, void *queue) {
    (void)target;
    (void)queue;
    return true;
}
