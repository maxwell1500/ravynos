/*
 * CFNotificationCenter.h -- local notification center.
 *
 * Only the local center is real: observers are stored in-process and
 * notifications are delivered synchronously on the posting thread.  The
 * distributed and Darwin notify centers are aliases of the local center
 * until a system-wide notification service exists; they do not silently
 * pretend to deliver across processes.
 */
#ifndef _CFNOTIFICATIONCENTER_H
#define _CFNOTIFICATIONCENTER_H

#include <CoreFoundation/CFBase.h>
#include <CoreFoundation/CFDictionary.h>


typedef struct __CFNotificationCenter *CFNotificationCenterRef;

typedef void (*CFNotificationCallback)(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo);

typedef CF_ENUM(CFIndex, CFNotificationSuspensionBehavior) {
    CFNotificationSuspensionBehaviorDrop = 1,
    CFNotificationSuspensionBehaviorCoalesce = 2,
    CFNotificationSuspensionBehaviorHoldUntilIdle = 3,
    CFNotificationSuspensionBehaviorDeliverImmediately = 4
};

CF_EXPORT CFNotificationCenterRef CFNotificationCenterGetLocalCenter(void);
CF_EXPORT CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);
CF_EXPORT CFNotificationCenterRef CFNotificationCenterGetDarwinNotifyCenter(void);

CF_EXPORT void CFNotificationCenterAddObserver(CFNotificationCenterRef center,
                                               const void *observer,
                                               CFNotificationCallback callBack,
                                               CFStringRef name,
                                               const void *object,
                                               CFNotificationSuspensionBehavior suspensionBehavior);

CF_EXPORT void CFNotificationCenterRemoveObserver(CFNotificationCenterRef center,
                                                  const void *observer,
                                                  CFStringRef name,
                                                  const void *object);

CF_EXPORT void CFNotificationCenterRemoveEveryObserver(CFNotificationCenterRef center,
                                                       const void *observer);

CF_EXPORT void CFNotificationCenterPostNotification(CFNotificationCenterRef center,
                                                    CFStringRef name,
                                                    const void *object,
                                                    CFDictionaryRef userInfo,
                                                    Boolean deliverImmediately);

CF_EXPORT void CFNotificationCenterPostNotificationWithOptions(CFNotificationCenterRef center,
                                                               CFStringRef name,
                                                               const void *object,
                                                               CFDictionaryRef userInfo,
                                                               CFOptionFlags options);


#endif /* _CFNOTIFICATIONCENTER_H */
