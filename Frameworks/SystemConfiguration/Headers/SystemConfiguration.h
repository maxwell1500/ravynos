/*
 * SystemConfiguration.framework public header for ravynOS.
 *
 * Covers the pieces an application links against in practice: the dynamic
 * store (with an in-process backing store, so a value a process sets can be
 * read back), SCPreferences, and SCNetworkReachability, which is implemented
 * against a real BSD socket so its answers reflect the machine's routing
 * table rather than a guess.
 *
 * Not present: the network-configuration editing API (SCNetworkInterface
 * configuration, VPN, PPP, DHCP leases, captive-network probes).  Those need
 * a configd daemon and a preferences store that this system does not have.
 */

#ifndef _RAVYNOS_SYSTEMCONFIGURATION_H_
#define _RAVYNOS_SYSTEMCONFIGURATION_H_

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFRunLoop.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Errors                                                              */
/* ------------------------------------------------------------------ */

typedef int32_t SCStatusCode;

enum {
    kSCStatusOK = 0,
    kSCStatusFailed = 1001,
    kSCStatusInvalidArgument = 1002,
    kSCStatusAccessError = 1003,
    kSCStatusNoKey = 1004,
    kSCStatusKeyExists = 1005,
    kSCStatusLocked = 1006,
    kSCStatusNeedLock = 1007,
    kSCStatusNoStoreSession = 2001,
    kSCStatusNoStoreServer = 2002,
    kSCStatusNotifierActive = 2003,
    kSCStatusNoPrefsSession = 3001,
    kSCStatusPrefsBusy = 3002,
    kSCStatusNoConfigFile = 3003,
    kSCStatusNoLink = 3004,
    kSCStatusStale = 3005,
    kSCStatusMaxLink = 3006,
    kSCStatusReachabilityUnknown = 4001,
    kSCStatusConnectionNoService = 5001,
    kSCStatusConnectionIgnore = 5002,
};

SCStatusCode SCError(void);
const char *SCErrorString(SCStatusCode status);

/* ------------------------------------------------------------------ */
/* Dynamic store                                                       */
/* ------------------------------------------------------------------ */

typedef struct __SCDynamicStore *SCDynamicStoreRef;

typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} SCDynamicStoreContext;

typedef void (*SCDynamicStoreCallBack)(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info);

CFTypeID SCDynamicStoreGetTypeID(void);
SCDynamicStoreRef SCDynamicStoreCreate(CFAllocatorRef allocator, CFStringRef name,
                                       SCDynamicStoreCallBack callout, SCDynamicStoreContext *context);
SCDynamicStoreRef SCDynamicStoreCreateWithOptions(CFAllocatorRef allocator, CFStringRef name,
                                                  CFDictionaryRef storeOptions,
                                                  SCDynamicStoreCallBack callout,
                                                  SCDynamicStoreContext *context);
CFRunLoopSourceRef SCDynamicStoreCreateRunLoopSource(CFAllocatorRef allocator,
                                                     SCDynamicStoreRef store, CFIndex order);
void SCDynamicStoreSetDispatchQueue(SCDynamicStoreRef store, void *queue);
void SCDynamicStoreSetNotificationKeys(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns);
CFPropertyListRef SCDynamicStoreCopyValue(SCDynamicStoreRef store, CFStringRef key);
CFDictionaryRef SCDynamicStoreCopyMultiple(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns);
CFArrayRef SCDynamicStoreCopyKeyList(SCDynamicStoreRef store, CFStringRef pattern);
Boolean SCDynamicStoreAddValue(SCDynamicStoreRef store, CFStringRef key, CFPropertyListRef value);
Boolean SCDynamicStoreAddTemporaryValue(SCDynamicStoreRef store, CFStringRef key, CFPropertyListRef value);
Boolean SCDynamicStoreSetValue(SCDynamicStoreRef store, CFStringRef key, CFPropertyListRef value);
Boolean SCDynamicStoreRemoveValue(SCDynamicStoreRef store, CFStringRef key);
Boolean SCDynamicStoreNotifyValue(SCDynamicStoreRef store, CFStringRef key);

CFStringRef SCDynamicStoreCopyLocalHostName(SCDynamicStoreRef store);
CFStringRef SCDynamicStoreCopyComputerName(SCDynamicStoreRef store, CFStringEncoding *nameEncoding);
CFStringRef SCDynamicStoreCopyConsoleUser(SCDynamicStoreRef store, uid_t *uid, gid_t *gid);
CFDictionaryRef SCDynamicStoreCopyProxies(SCDynamicStoreRef store);
CFStringRef SCDynamicStoreCopyLocation(SCDynamicStoreRef store);

CFStringRef SCDynamicStoreKeyCreate(CFAllocatorRef allocator, CFStringRef fmt, ...);
CFStringRef SCDynamicStoreKeyCreateNetworkGlobalEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                      CFStringRef entity);
CFStringRef SCDynamicStoreKeyCreateNetworkInterface(CFAllocatorRef allocator, CFStringRef domain);
CFStringRef SCDynamicStoreKeyCreateNetworkInterfaceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                         CFStringRef ifname, CFStringRef entity);
CFStringRef SCDynamicStoreKeyCreateNetworkServiceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                       CFStringRef serviceID, CFStringRef entity);
CFStringRef SCDynamicStoreKeyCreateComputerName(CFAllocatorRef allocator);
CFStringRef SCDynamicStoreKeyCreateConsoleUser(CFAllocatorRef allocator);
CFStringRef SCDynamicStoreKeyCreateHostNames(CFAllocatorRef allocator);
CFStringRef SCDynamicStoreKeyCreateLocation(CFAllocatorRef allocator);
CFStringRef SCDynamicStoreKeyCreateProxies(CFAllocatorRef allocator);

/* ------------------------------------------------------------------ */
/* Preferences                                                         */
/* ------------------------------------------------------------------ */

typedef struct __SCPreferences *SCPreferencesRef;

CFTypeID SCPreferencesGetTypeID(void);
SCPreferencesRef SCPreferencesCreate(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID);
SCPreferencesRef SCPreferencesCreateWithAuthorization(CFAllocatorRef allocator, CFStringRef name,
                                                      CFStringRef prefsID, void *authorization);
Boolean SCPreferencesLock(SCPreferencesRef prefs, Boolean wait);
Boolean SCPreferencesCommitChanges(SCPreferencesRef prefs);
Boolean SCPreferencesApplyChanges(SCPreferencesRef prefs);
void SCPreferencesUnlock(SCPreferencesRef prefs);
CFPropertyListRef SCPreferencesGetValue(SCPreferencesRef prefs, CFStringRef key);
Boolean SCPreferencesSetValue(SCPreferencesRef prefs, CFStringRef key, CFPropertyListRef value);
Boolean SCPreferencesRemoveValue(SCPreferencesRef prefs, CFStringRef key);
CFArrayRef SCPreferencesCopyKeyList(SCPreferencesRef prefs);
void SCPreferencesSynchronize(SCPreferencesRef prefs);

/* ------------------------------------------------------------------ */
/* Reachability                                                        */
/* ------------------------------------------------------------------ */

typedef struct __SCNetworkReachability *SCNetworkReachabilityRef;

typedef uint32_t SCNetworkReachabilityFlags;
enum {
    kSCNetworkReachabilityFlagsTransientConnection = 1 << 0,
    kSCNetworkReachabilityFlagsReachable = 1 << 1,
    kSCNetworkReachabilityFlagsConnectionRequired = 1 << 2,
    kSCNetworkReachabilityFlagsConnectionOnTraffic = 1 << 3,
    kSCNetworkReachabilityFlagsInterventionRequired = 1 << 4,
    kSCNetworkReachabilityFlagsConnectionOnDemand = 1 << 5,
    kSCNetworkReachabilityFlagsIsLocalAddress = 1 << 16,
    kSCNetworkReachabilityFlagsIsDirect = 1 << 17,
    kSCNetworkReachabilityFlagsIsWWAN = 1 << 18,
};

typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} SCNetworkReachabilityContext;

typedef void (*SCNetworkReachabilityCallBack)(SCNetworkReachabilityRef target,
                                             SCNetworkReachabilityFlags flags, void *info);

CFTypeID SCNetworkReachabilityGetTypeID(void);
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddress(CFAllocatorRef allocator,
                                                               const struct sockaddr *address);
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithAddressPair(CFAllocatorRef allocator,
                                                                    const struct sockaddr *localAddress,
                                                                    const struct sockaddr *remoteAddress);
SCNetworkReachabilityRef SCNetworkReachabilityCreateWithName(CFAllocatorRef allocator,
                                                             const char *nodename);
Boolean SCNetworkReachabilityGetFlags(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags);
Boolean SCNetworkReachabilitySetCallback(SCNetworkReachabilityRef target,
                                         SCNetworkReachabilityCallBack callout,
                                         SCNetworkReachabilityContext *context);
Boolean SCNetworkReachabilityScheduleWithRunLoop(SCNetworkReachabilityRef target,
                                                 CFRunLoopRef runLoop, CFStringRef runLoopMode);
Boolean SCNetworkReachabilityUnscheduleFromRunLoop(SCNetworkReachabilityRef target,
                                                   CFRunLoopRef runLoop, CFStringRef runLoopMode);
Boolean SCNetworkReachabilitySetDispatchQueue(SCNetworkReachabilityRef target, void *queue);

#ifdef __cplusplus
}
#endif

#endif /* _RAVYNOS_SYSTEMCONFIGURATION_H_ */
