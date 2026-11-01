/*
 * CFNotificationCenter.c -- in-process notification center.
 *
 * Observers are kept in a small fixed table and notified synchronously by
 * CFNotificationCenterPostNotification.  The distributed and Darwin
 * centers are aliases of the local center: they accept registrations and
 * deliver within the process, but do not claim to cross process
 * boundaries.
 */
#include "CFPriv.h"
#include "CFNotificationCenter.h"

#include <string.h>

#define CFNC_MAX_OBSERVERS 512

typedef struct {
    const void *observer;
    CFNotificationCallback callback;
    CFStringRef name;       /* NULL matches every name */
    const void *object;     /* NULL matches every object */
} CFNCObserver;

static CFNCObserver observers[CFNC_MAX_OBSERVERS];
static CFIndex observerCount;
static char localCenterStorage;

static Boolean
nameMatches(CFStringRef registered, CFStringRef posted)
{
    if (registered == NULL || posted == NULL)
        return true;
    return CFStringCompare(registered, posted, 0) == kCFCompareEqualTo;
}

static Boolean
objectMatches(const void *registered, const void *posted)
{
    if (registered == NULL || posted == NULL)
        return true;
    return registered == posted;
}

CFNotificationCenterRef
CFNotificationCenterGetLocalCenter(void)
{
    return (CFNotificationCenterRef)&localCenterStorage;
}

CFNotificationCenterRef
CFNotificationCenterGetDistributedCenter(void)
{
    /* No system-wide service yet; local delivery is the honest subset. */
    return CFNotificationCenterGetLocalCenter();
}

CFNotificationCenterRef
CFNotificationCenterGetDarwinNotifyCenter(void)
{
    return CFNotificationCenterGetLocalCenter();
}

void
CFNotificationCenterAddObserver(CFNotificationCenterRef center,
                                const void *observer,
                                CFNotificationCallback callBack,
                                CFStringRef name,
                                const void *object,
                                CFNotificationSuspensionBehavior suspensionBehavior)
{
    (void)center;
    (void)suspensionBehavior;

    if (observer == NULL || callBack == NULL)
        return;
    if (observerCount >= CFNC_MAX_OBSERVERS)
        return;

    observers[observerCount].observer = observer;
    observers[observerCount].callback = callBack;
    observers[observerCount].name = name ? CFStringCreateCopy(NULL, name) : NULL;
    observers[observerCount].object = object;
    observerCount++;
}

void
CFNotificationCenterRemoveObserver(CFNotificationCenterRef center,
                                   const void *observer,
                                   CFStringRef name,
                                   const void *object)
{
    CFIndex i;

    (void)center;
    for (i = 0; i < observerCount; ) {
        CFNCObserver *entry = &observers[i];
        if (entry->observer == observer &&
            (name == NULL || nameMatches(entry->name, name)) &&
            (object == NULL || entry->object == object)) {
            if (entry->name)
                CFRelease(entry->name);
            observers[i] = observers[--observerCount];
            memset(&observers[observerCount], 0, sizeof(CFNCObserver));
            continue;
        }
        i++;
    }
}

void
CFNotificationCenterRemoveEveryObserver(CFNotificationCenterRef center,
                                        const void *observer)
{
    CFNotificationCenterRemoveObserver(center, observer, NULL, NULL);
}

void
CFNotificationCenterPostNotification(CFNotificationCenterRef center,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo,
                                     Boolean deliverImmediately)
{
    CFIndex i;

    (void)deliverImmediately;
    for (i = 0; i < observerCount; i++) {
        CFNCObserver *entry = &observers[i];
        if (nameMatches(entry->name, name) &&
            objectMatches(entry->object, object)) {
            entry->callback(center, (void *)entry->observer, name, object,
                            userInfo);
        }
    }
}

void
CFNotificationCenterPostNotificationWithOptions(CFNotificationCenterRef center,
                                                CFStringRef name,
                                                const void *object,
                                                CFDictionaryRef userInfo,
                                                CFOptionFlags options)
{
    (void)options;
    CFNotificationCenterPostNotification(center, name, object, userInfo, true);
}
