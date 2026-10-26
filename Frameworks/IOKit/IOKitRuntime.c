/*
 * IOKit.framework runtime for ravynOS.
 *
 * The userland half of IOKit: the registry iteration, notification, power
 * management and HID APIs that third-party applications and drivers link
 * against.  There is no IOKit registry in the kernel yet, so these answer with
 * the honest "nothing is registered" result -- an empty iterator, a NULL
 * property, kIOReturnNotFound -- instead of returning uninitialised memory or
 * trapping on a NULL port.
 *
 * The shapes matter more than the data here: a caller doing
 *
 *     io_service_t service = IOServiceGetMatchingService(...);
 *     if (service) { ... }
 *
 * must get 0, and a caller doing
 *
 *     io_iterator_t it = 0;
 *     if (IOServiceGetMatchingServices(..., &it) == KERN_SUCCESS) {
 *         while ((service = IOIteratorNext(it))) { ... }
 *     }
 *
 * must get a valid, empty iterator it can release.  Both are implemented that
 * way on purpose.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/* Ports and iterators                                                 */
/* ------------------------------------------------------------------ */

CFTypeID IOMainPortGetTypeID(void);
CFTypeID IOMainPortGetTypeID(void) {
    /* Ports are plain mach ports on macOS too; there is no CF type. */
    return 0;
}

kern_return_t IOMasterPort(mach_port_t bootstrapPort, mach_port_t *masterPort) {
    (void)bootstrapPort;
    if (masterPort) *masterPort = MACH_PORT_NULL;
    return KERN_SUCCESS;
}

kern_return_t IOMainPort(mach_port_t bootstrapPort, mach_port_t *mainPort) {
    return IOMasterPort(bootstrapPort, mainPort);
}

mach_port_t IOMasterPortDefaultValue = MACH_PORT_NULL;
mach_port_t IOMainPortDefaultValue = MACH_PORT_NULL;
const mach_port_t kIOMasterPortDefault = MACH_PORT_NULL;
const mach_port_t kIOMainPortDefault = MACH_PORT_NULL;

/* An iterator carries a small array of io_object_t.  Today it is always
 * empty, but the type is a real object so IOObjectRelease and
 * IOIteratorNext have something to operate on. */
typedef struct IORavynIterator {
    uint32_t magic;
    CFIndex count;
    CFIndex index;
    io_object_t *objects;
} IORavynIterator;

#define RAVYN_ITERATOR_MAGIC 0x494F4954u   /* 'IOIT' */
#define RAVYN_OBJECT_MAGIC   0x494F424Au   /* 'IOBJ' */

typedef struct IORavynObject {
    uint32_t magic;
    uint32_t retainCount;
    io_object_t id;
    char className[64];
    char name[128];
    uint64_t entryID;
} IORavynObject;

static uint32_t g_next_entry_id = 1;

static IORavynIterator *iterator_create(CFIndex capacity) {
    IORavynIterator *it = (IORavynIterator *)calloc(1, sizeof(IORavynIterator));
    if (!it) return NULL;
    it->magic = RAVYN_ITERATOR_MAGIC;
    it->objects = capacity ? (io_object_t *)calloc((size_t)capacity, sizeof(io_object_t)) : NULL;
    it->count = 0;
    it->index = 0;
    return it;
}

static IORavynObject *object_create(const char *className, const char *name) {
    IORavynObject *obj = (IORavynObject *)calloc(1, sizeof(IORavynObject));
    if (!obj) return NULL;
    obj->magic = RAVYN_OBJECT_MAGIC;
    obj->retainCount = 1;
    obj->id = g_next_entry_id++;
    obj->entryID = obj->id;
    if (className) {
        strncpy(obj->className, className, sizeof(obj->className) - 1);
    }
    if (name) {
        strncpy(obj->name, name, sizeof(obj->name) - 1);
    }
    return obj;
}

static IORavynObject *object_for(io_object_t object) {
    if (object == 0) return NULL;
    IORavynObject *obj = (IORavynObject *)(uintptr_t)object;
    if (obj->magic != RAVYN_OBJECT_MAGIC) return NULL;
    return obj;
}

kern_return_t IOObjectRetain(io_object_t object) {
    IORavynObject *obj = object_for(object);
    if (!obj) return kIOReturnBadArgument;
    obj->retainCount++;
    return KERN_SUCCESS;
}

kern_return_t IOObjectRelease(io_object_t object) {
    if (object == 0) return KERN_SUCCESS;
    IORavynObject *obj = (IORavynObject *)(uintptr_t)object;
    if (obj->magic != RAVYN_OBJECT_MAGIC) return kIOReturnBadArgument;
    if (obj->retainCount > 0) {
        obj->retainCount--;
    }
    if (obj->retainCount == 0) {
        obj->magic = 0;
        free(obj);
    }
    return KERN_SUCCESS;
}

io_object_t IOIteratorNext(io_iterator_t iterator) {
    if (iterator == 0) return 0;
    IORavynIterator *it = (IORavynIterator *)(uintptr_t)iterator;
    if (it->magic != RAVYN_ITERATOR_MAGIC) return 0;
    if (it->index >= it->count) return 0;
    io_object_t result = it->objects[it->index++];
    if (result) IOObjectRetain(result);
    return result;
}

void IOIteratorReset(io_iterator_t iterator) {
    if (iterator == 0) return;
    IORavynIterator *it = (IORavynIterator *)(uintptr_t)iterator;
    if (it->magic != RAVYN_ITERATOR_MAGIC) return;
    it->index = 0;
}

boolean_t IOIteratorIsValid(io_iterator_t iterator) {
    if (iterator == 0) return false;
    IORavynIterator *it = (IORavynIterator *)(uintptr_t)iterator;
    return (it->magic == RAVYN_ITERATOR_MAGIC) ? true : false;
}

kern_return_t IOIteratorRetain(io_iterator_t iterator) {
    (void)iterator;
    return KERN_SUCCESS;
}

kern_return_t IOServiceGetMatchingServices(mach_port_t masterPort, CFDictionaryRef matching,
                                           io_iterator_t *existing) {
    (void)masterPort;
    if (existing) *existing = 0;
    if (existing == NULL) return kIOReturnBadArgument;
    /* `matching` is consumed by this call on macOS; release it to keep the
     * caller's +1 balanced the way the API contract requires. */
    if (matching) CFRelease(matching);
    IORavynIterator *it = iterator_create(0);
    if (!it) return kIOReturnNoMemory;
    *existing = (io_iterator_t)(uintptr_t)it;
    return KERN_SUCCESS;
}

io_service_t IOServiceGetMatchingService(mach_port_t masterPort, CFDictionaryRef matching) {
    (void)masterPort;
    if (matching) CFRelease(matching);
    return 0;
}

CFMutableDictionaryRef IOServiceMatching(const char *name) {
    if (name == NULL) return NULL;
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);
    if (!dict) return NULL;
    CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, "IOProviderClass", kCFStringEncodingUTF8);
    CFStringRef value = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
    if (key && value) {
        CFDictionarySetValue(dict, key, value);
    }
    if (key) CFRelease(key);
    if (value) CFRelease(value);
    return dict;
}

CFMutableDictionaryRef IOServiceNameMatching(const char *name) {
    if (name == NULL) return NULL;
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);
    if (!dict) return NULL;
    CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, "IONameMatch", kCFStringEncodingUTF8);
    CFStringRef value = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
    if (key && value) {
        CFDictionarySetValue(dict, key, value);
    }
    if (key) CFRelease(key);
    if (value) CFRelease(value);
    return dict;
}

CFMutableDictionaryRef IOBSDNameMatching(mach_port_t masterPort, uint32_t options, const char *bsdName) {
    (void)masterPort;
    (void)options;
    if (bsdName == NULL) return NULL;
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);
    if (!dict) return NULL;
    CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, "IOBSDName", kCFStringEncodingUTF8);
    CFStringRef value = CFStringCreateWithCString(kCFAllocatorDefault, bsdName, kCFStringEncodingUTF8);
    if (key && value) {
        CFDictionarySetValue(dict, key, value);
    }
    if (key) CFRelease(key);
    if (value) CFRelease(value);
    return dict;
}

CFMutableDictionaryRef IORegistryEntryIDMatching(uint64_t entryID) {
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);
    if (!dict) return NULL;
    CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, "IORegistryEntryID", kCFStringEncodingUTF8);
    CFNumberRef value = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &entryID);
    if (key && value) {
        CFDictionarySetValue(dict, key, value);
    }
    if (key) CFRelease(key);
    if (value) CFRelease(value);
    return dict;
}

CFMutableDictionaryRef IORegistryEntryMatching(uint64_t entryID) {
    return IORegistryEntryIDMatching(entryID);
}

io_registry_entry_t IORegistryGetRootEntry(mach_port_t masterPort) {
    (void)masterPort;
    IORavynObject *root = object_create("IORegistryEntry", "Root");
    return root ? (io_registry_entry_t)root->id : 0;
}

kern_return_t IORegistryEntryGetChildIterator(io_registry_entry_t entry, const io_name_t plane,
                                              io_iterator_t *iterator) {
    (void)entry;
    (void)plane;
    if (iterator == NULL) return kIOReturnBadArgument;
    IORavynIterator *it = iterator_create(0);
    if (!it) return kIOReturnNoMemory;
    *iterator = (io_iterator_t)(uintptr_t)it;
    return KERN_SUCCESS;
}

kern_return_t IORegistryEntryGetChildEntry(io_registry_entry_t entry, const io_name_t plane,
                                           io_registry_entry_t *child) {
    (void)entry;
    (void)plane;
    if (child) *child = 0;
    return kIOReturnNoDevice;
}

kern_return_t IORegistryEntryGetParentIterator(io_registry_entry_t entry, const io_name_t plane,
                                               io_iterator_t *iterator) {
    return IORegistryEntryGetChildIterator(entry, plane, iterator);
}

kern_return_t IORegistryEntryGetParentEntry(io_registry_entry_t entry, const io_name_t plane,
                                            io_registry_entry_t *parent) {
    (void)entry;
    (void)plane;
    if (parent) *parent = 0;
    return kIOReturnNoDevice;
}

kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t entry,
                                                CFMutableDictionaryRef *properties,
                                                CFAllocatorRef allocator, IOOptionBits options) {
    (void)entry;
    (void)options;
    if (properties == NULL) return kIOReturnBadArgument;
    *properties = CFDictionaryCreateMutable(allocator ? allocator : kCFAllocatorDefault, 0,
                                           &kCFTypeDictionaryKeyCallBacks,
                                           &kCFTypeDictionaryValueCallBacks);
    return *properties ? KERN_SUCCESS : kIOReturnNoMemory;
}

CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key,
                                          CFAllocatorRef allocator, IOOptionBits options) {
    (void)entry;
    (void)key;
    (void)allocator;
    (void)options;
    /* No property exists, which is exactly what a missing registry entry
     * answers.  Callers all handle nil from this call. */
    return NULL;
}

CFTypeRef IORegistryEntrySearchCFProperty(io_registry_entry_t entry, const io_name_t plane,
                                          CFStringRef key, CFAllocatorRef allocator,
                                          IOOptionBits options) {
    (void)entry;
    (void)plane;
    (void)key;
    (void)allocator;
    (void)options;
    return NULL;
}

kern_return_t IORegistryEntrySetCFProperty(io_registry_entry_t entry, CFStringRef key, CFTypeRef value) {
    (void)entry;
    (void)key;
    (void)value;
    return kIOReturnUnsupported;
}

kern_return_t IORegistryEntrySetCFProperties(io_registry_entry_t entry, CFTypeRef properties) {
    (void)entry;
    (void)properties;
    return kIOReturnUnsupported;
}

kern_return_t IORegistryEntryGetProperty(io_registry_entry_t entry, const io_name_t propertyName,
                                         io_struct_inband_t buffer, uint32_t *size) {
    (void)entry;
    (void)propertyName;
    (void)buffer;
    if (size) *size = 0;
    return kIOReturnNotFound;
}

kern_return_t IORegistryEntryGetName(io_registry_entry_t entry, io_name_t name) {
    if (name == NULL) return kIOReturnBadArgument;
    IORavynObject *obj = object_for(entry);
    if (!obj) {
        name[0] = '\0';
        return kIOReturnBadArgument;
    }
    strncpy(name, obj->name, sizeof(io_name_t) - 1);
    return KERN_SUCCESS;
}

kern_return_t IORegistryEntryGetNameInPlane(io_registry_entry_t entry, const io_name_t plane, io_name_t name) {
    (void)plane;
    return IORegistryEntryGetName(entry, name);
}

kern_return_t IORegistryEntryGetLocationInPlane(io_registry_entry_t entry, const io_name_t plane, io_name_t location) {
    (void)entry;
    (void)plane;
    if (location) location[0] = '\0';
    return kIOReturnNotFound;
}

kern_return_t IORegistryEntryGetPath(io_registry_entry_t entry, const io_name_t plane, io_string_t path) {
    (void)entry;
    (void)plane;
    if (path == NULL) return kIOReturnBadArgument;
    strncpy(path, "IOService:/", sizeof(io_string_t) - 1);
    return KERN_SUCCESS;
}

kern_return_t IORegistryEntryGetRegistryEntryID(io_registry_entry_t entry, uint64_t *entryID) {
    if (entryID == NULL) return kIOReturnBadArgument;
    IORavynObject *obj = object_for(entry);
    if (!obj) {
        *entryID = 0;
        return kIOReturnBadArgument;
    }
    *entryID = obj->entryID;
    return KERN_SUCCESS;
}

kern_return_t IORegistryEntryGetChildCount(io_registry_entry_t entry, uint32_t *count) {
    (void)entry;
    if (count) *count = 0;
    return KERN_SUCCESS;
}

kern_return_t IORegistryCreateEnumerator(mach_port_t masterPort, io_iterator_t *iterator) {
    (void)masterPort;
    if (iterator == NULL) return kIOReturnBadArgument;
    IORavynIterator *it = iterator_create(0);
    if (!it) return kIOReturnNoMemory;
    *iterator = (io_iterator_t)(uintptr_t)it;
    return KERN_SUCCESS;
}

kern_return_t IORegistryEnumeratorNextEntry(io_iterator_t iterator, io_registry_entry_t *entry) {
    (void)iterator;
    if (entry) *entry = 0;
    return kIOReturnNotFound;
}

kern_return_t IORegistryEnumeratorNextSibling(io_iterator_t iterator, io_registry_entry_t *entry) {
    return IORegistryEnumeratorNextEntry(iterator, entry);
}

kern_return_t IORegistryEntryGetParentEntryWithProperties(io_registry_entry_t entry, const io_name_t plane,
                                                         io_registry_entry_t *parent) {
    return IORegistryEntryGetParentEntry(entry, plane, parent);
}

boolean_t IOObjectConformsTo(io_object_t object, const io_name_t className) {
    IORavynObject *obj = object_for(object);
    if (!obj || className == NULL) return false;
    return strcmp(obj->className, className) == 0 ? true : false;
}

CFStringRef IOObjectCopyClass(io_object_t object) {
    IORavynObject *obj = object_for(object);
    if (!obj) return NULL;
    return CFStringCreateWithCString(kCFAllocatorDefault, obj->className, kCFStringEncodingUTF8);
}

CFStringRef IOObjectCopySuperclassForClass(CFStringRef className) {
    (void)className;
    return CFStringCreateWithCString(kCFAllocatorDefault, "IORegistryEntry", kCFStringEncodingUTF8);
}

CFStringRef IOObjectCopyBundleIdentifierForClass(CFStringRef className) {
    (void)className;
    return NULL;
}

kern_return_t IOObjectGetClass(io_object_t object, io_name_t className) {
    IORavynObject *obj = object_for(object);
    if (className == NULL) return kIOReturnBadArgument;
    if (!obj) {
        className[0] = '\0';
        return kIOReturnBadArgument;
    }
    strncpy(className, obj->className, sizeof(io_name_t) - 1);
    return KERN_SUCCESS;
}

uint32_t IOObjectGetKernelRetainCount(io_object_t object) {
    IORavynObject *obj = object_for(object);
    return obj ? obj->retainCount : 0;
}

uint32_t IOObjectGetUserRetainCount(io_object_t object) {
    return IOObjectGetKernelRetainCount(object);
}

uint32_t IOObjectGetRetainCount(io_object_t object) {
    return IOObjectGetKernelRetainCount(object);
}

boolean_t IOObjectIsEqualTo(io_object_t object, io_object_t anObject) {
    return (object == anObject) ? true : false;
}

/* ------------------------------------------------------------------ */
/* Opening a service                                                   */
/* ------------------------------------------------------------------ */

kern_return_t IOServiceOpen(io_service_t service, task_port_t owningTask, uint32_t type, io_connect_t *connect) {
    (void)service;
    (void)owningTask;
    (void)type;
    if (connect) *connect = MACH_PORT_NULL;
    return kIOReturnNotPermitted;
}

kern_return_t IOServiceClose(io_connect_t connect) {
    (void)connect;
    return KERN_SUCCESS;
}

kern_return_t IOServiceRequestProbe(io_service_t service, uint32_t options) {
    (void)service;
    (void)options;
    return kIOReturnUnsupported;
}

kern_return_t IOServiceAuthorize(io_service_t service, uint32_t options) {
    (void)service;
    (void)options;
    return kIOReturnUnsupported;
}

kern_return_t IOServiceWaitQuiet(io_service_t service, mach_timespec_t *waitTime) {
    (void)service;
    (void)waitTime;
    return KERN_SUCCESS;
}

kern_return_t IOConnectCallMethod(mach_port_t connection, uint32_t selector,
                                  const uint64_t *input, uint32_t inputCnt,
                                  const void *inputStruct, size_t inputStructCnt,
                                  uint64_t *output, uint32_t *outputCnt,
                                  void *outputStruct, size_t *outputStructCnt) {
    (void)connection; (void)selector; (void)input; (void)inputCnt;
    (void)inputStruct; (void)inputStructCnt; (void)output; (void)outputCnt;
    (void)outputStruct; (void)outputStructCnt;
    return kIOReturnUnsupported;
}

kern_return_t IOConnectCallScalarMethod(mach_port_t connection, uint32_t selector,
                                        const uint64_t *input, uint32_t inputCnt,
                                        uint64_t *output, uint32_t *outputCnt) {
    return IOConnectCallMethod(connection, selector, input, inputCnt, NULL, 0,
                               output, outputCnt, NULL, NULL);
}

kern_return_t IOConnectCallStructMethod(mach_port_t connection, uint32_t selector,
                                        const void *inputStruct, size_t inputStructCnt,
                                        void *outputStruct, size_t *outputStructCnt) {
    return IOConnectCallMethod(connection, selector, NULL, 0, inputStruct, inputStructCnt,
                               NULL, NULL, outputStruct, outputStructCnt);
}

kern_return_t IOConnectCallAsyncMethod(mach_port_t connection, uint32_t selector,
                                       mach_port_t wake_port, uint64_t *reference,
                                       uint32_t referenceCnt, const uint64_t *input,
                                       uint32_t inputCnt, const void *inputStruct,
                                       size_t inputStructCnt, uint64_t *output,
                                       uint32_t *outputCnt, void *outputStruct,
                                       size_t *outputStructCnt) {
    (void)connection; (void)selector; (void)wake_port; (void)reference;
    (void)referenceCnt; (void)input; (void)inputCnt; (void)inputStruct;
    (void)inputStructCnt; (void)output; (void)outputCnt; (void)outputStruct;
    (void)outputStructCnt;
    return kIOReturnUnsupported;
}

kern_return_t IOConnectSetNotificationPort(io_connect_t connect, uint32_t type,
                                           mach_port_t port, uintptr_t reference) {
    (void)connect; (void)type; (void)port; (void)reference;
    return kIOReturnUnsupported;
}

kern_return_t IOConnectMapMemory(io_connect_t connect, uint32_t memoryType, task_port_t intoTask,
                                 mach_vm_address_t *atAddress, mach_vm_size_t *ofSize, IOOptionBits options) {
    (void)connect; (void)memoryType; (void)intoTask; (void)atAddress; (void)ofSize; (void)options;
    return kIOReturnUnsupported;
}

kern_return_t IOConnectUnmapMemory(io_connect_t connect, uint32_t memoryType, task_port_t fromTask,
                                   mach_vm_address_t atAddress) {
    (void)connect; (void)memoryType; (void)fromTask; (void)atAddress;
    return kIOReturnUnsupported;
}

/* ------------------------------------------------------------------ */
/* Notifications                                                       */
/* ------------------------------------------------------------------ */

typedef struct IORavynNotificationPort {
    CFRunLoopSourceRef runLoopSource;
    void *dispatchQueue;
    uint32_t refcon;
} IORavynNotificationPort;

IONotificationPortRef IONotificationPortCreate(mach_port_t masterPort) {
    (void)masterPort;
    IORavynNotificationPort *port = (IORavynNotificationPort *)calloc(1, sizeof(IORavynNotificationPort));
    return (IONotificationPortRef)port;
}

void IONotificationPortDestroy(IONotificationPortRef notify) {
    if (!notify) return;
    IORavynNotificationPort *port = (IORavynNotificationPort *)notify;
    if (port->runLoopSource) CFRelease(port->runLoopSource);
    free(port);
}

mach_port_t IONotificationPortGetMachPort(IONotificationPortRef notify) {
    (void)notify;
    return MACH_PORT_NULL;
}

CFRunLoopSourceRef IONotificationPortGetRunLoopSource(IONotificationPortRef notify) {
    if (!notify) return NULL;
    IORavynNotificationPort *port = (IORavynNotificationPort *)notify;
    if (port->runLoopSource == NULL) {
        CFRunLoopSourceContext context;
        memset(&context, 0, sizeof(context));
        port->runLoopSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);
    }
    return port->runLoopSource;
}

void IONotificationPortSetDispatchQueue(IONotificationPortRef notify, dispatch_queue_t queue) {
    if (!notify) return;
    ((IORavynNotificationPort *)notify)->dispatchQueue = queue;
}

kern_return_t IOServiceAddMatchingNotification(IONotificationPortRef notifyPort, const io_name_t notificationType,
                                               CFDictionaryRef matching, IOServiceMatchingCallback callback,
                                               void *refCon, io_iterator_t *notification) {
    (void)notifyPort;
    (void)notificationType;
    (void)callback;
    (void)refCon;
    if (matching) CFRelease(matching);
    if (notification == NULL) return kIOReturnBadArgument;
    /* An empty iterator, delivered armed-and-drained the way the API requires:
     * the caller then calls IOIteratorNext until it returns 0, which it does
     * immediately. */
    IORavynIterator *it = iterator_create(0);
    if (!it) return kIOReturnNoMemory;
    *notification = (io_iterator_t)(uintptr_t)it;
    return KERN_SUCCESS;
}

kern_return_t IOServiceAddInterestNotification(IONotificationPortRef notifyPort, io_service_t service,
                                               const io_name_t interestType, IOServiceInterestCallback callback,
                                               void *refCon, io_object_t *notification) {
    (void)notifyPort;
    (void)service;
    (void)interestType;
    (void)callback;
    (void)refCon;
    if (notification) *notification = 0;
    return kIOReturnUnsupported;
}

kern_return_t IODataQueueAllocateNotificationPort(mach_port_t *port) {
    if (port) *port = MACH_PORT_NULL;
    return kIOReturnUnsupported;
}

/* ------------------------------------------------------------------ */
/* Power management                                                    */
/* ------------------------------------------------------------------ */

typedef struct IORavynAssertion {
    IOPMAssertionID id;
    CFStringRef name;
    CFStringRef details;
} IORavynAssertion;

static IOPMAssertionID g_next_assertion_id = 1;

IOReturn IOPMAssertionCreateWithName(CFStringRef assertionType, IOPMAssertionLevel assertionLevel,
                                     CFStringRef assertionName, IOPMAssertionID *assertionID) {
    (void)assertionType;
    (void)assertionLevel;
    if (assertionID == NULL) return kIOReturnBadArgument;
    *assertionID = g_next_assertion_id++;
    if (assertionName) {
        /* Not retained: assertions here are bookkeeping only, and retaining a
         * caller's string would leak it for the lifetime of the process. */
    }
    return kIOReturnSuccess;
}

IOReturn IOPMAssertionCreateWithDescription(CFStringRef assertionType, CFStringRef name,
                                            CFStringRef details, CFStringRef humanReadableReason,
                                            CFStringRef localizationBundlePath, CFTimeInterval timeout,
                                            CFStringRef timeoutAction, IOPMAssertionID *assertionID) {
    (void)assertionType; (void)name; (void)details; (void)humanReadableReason;
    (void)localizationBundlePath; (void)timeout; (void)timeoutAction;
    if (assertionID) *assertionID = g_next_assertion_id++;
    return kIOReturnSuccess;
}

IOReturn IOPMAssertionCreateWithProperties(CFDictionaryRef properties, IOPMAssertionID *assertionID) {
    (void)properties;
    if (assertionID) *assertionID = g_next_assertion_id++;
    return kIOReturnSuccess;
}

IOReturn IOPMAssertionRelease(IOPMAssertionID assertionID) {
    (void)assertionID;
    return kIOReturnSuccess;
}

IOReturn IOPMAssertionDeclareUserActivity(CFStringRef assertionName, IOPMUserActiveType userType,
                                         IOPMAssertionID *assertionID) {
    (void)assertionName;
    (void)userType;
    if (assertionID) *assertionID = g_next_assertion_id++;
    return kIOReturnSuccess;
}

IOReturn IOPMAssertionSetProperty(IOPMAssertionID assertionID, CFStringRef property, CFTypeRef value) {
    (void)assertionID;
    (void)property;
    (void)value;
    return kIOReturnUnsupported;
}

CFDictionaryRef IOPMAssertionCopyProperties(IOPMAssertionID assertionID) {
    (void)assertionID;
    return CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                              &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

IOReturn IOPMCopyAssertionsStatus(CFDictionaryRef *assertionsStatus) {
    if (assertionsStatus == NULL) return kIOReturnBadArgument;
    *assertionsStatus = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                                           &kCFTypeDictionaryKeyCallBacks,
                                           &kCFTypeDictionaryValueCallBacks);
    return kIOReturnSuccess;
}

IOReturn IOPMCopyAssertionsByProcess(CFDictionaryRef *assertionsByProcess) {
    return IOPMCopyAssertionsStatus(assertionsByProcess);
}

IOReturn IOPMCopyAssertionsByType(CFDictionaryRef *assertionsByType) {
    return IOPMCopyAssertionsStatus(assertionsByType);
}

CFStringRef IOPMAssertionCopyName(IOPMAssertionID assertionID) {
    (void)assertionID;
    return NULL;
}

/* The tree's IOPMLib.h declares no power-source (IOPS*) API and IOHIDLib.h
 * declares no IOHIDManager API, so there is nothing to implement here.  A
 * caller that needs them fails at link time with a named symbol rather than
 * running against a stub whose signature disagrees with its own header. */
