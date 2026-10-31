#define _XOPEN_SOURCE 700
#define _DARWIN_C_SOURCE 1

#include <sys/types.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFRuntime.h>
#include <DirectoryService/DirServicesTypes.h>
#include <pwd.h>
#include <grp.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <CFOpenDirectory/CFOpenDirectoryConstants.h>
const CFStringRef kODSessionLocalPath = CFSTR("/Local/Default");
const CFStringRef kODSessionProxyAddress = CFSTR("ProxyAddress");
const CFStringRef kODSessionProxyPassword = CFSTR("ProxyPassword");
const CFStringRef kODSessionProxyPort = CFSTR("ProxyPort");
const CFStringRef kODSessionProxyUsername = CFSTR("ProxyUsername");

tDirStatus ODConvertToLegacyErrorCode(SInt32 inCode) {
    if (inCode == 0) return 0;
    if (inCode == kODErrorNodeUnknownName || inCode == kODErrorRecordNoLongerExists) return -14136; /* eDSRecordNotFound */
    return -14000; /* eDSOpenFailed */
}

/* Opaque CF Types */
typedef struct __ODSession {
    CFRuntimeBase _base;
    CFStringRef name;
} *ODSessionRef;

typedef struct __ODNode {
    CFRuntimeBase _base;
    ODSessionRef session;
    CFStringRef name;
} *ODNodeRef;

typedef struct __ODRecord {
    CFRuntimeBase _base;
    ODNodeRef node;
    CFStringRef recordType;
    CFStringRef recordName;
    CFMutableDictionaryRef attributes;
} *ODRecordRef;

typedef struct __ODQuery {
    CFRuntimeBase _base;
    ODNodeRef node;
    CFMutableArrayRef results;
} *ODQueryRef;

typedef struct __ODContext {
    CFRuntimeBase _base;
} *ODContextRef;

static CFTypeID _kODSessionTypeID = 0;
static CFTypeID _kODNodeTypeID = 0;
static CFTypeID _kODRecordTypeID = 0;
static CFTypeID _kODQueryTypeID = 0;
static CFTypeID _kODContextTypeID = 0;

static void _ODSessionFinalize(CFTypeRef cf) {
    ODSessionRef s = (ODSessionRef)cf;
    if (s->name) CFRelease(s->name);
}

static void _ODNodeFinalize(CFTypeRef cf) {
    ODNodeRef n = (ODNodeRef)cf;
    if (n->session) CFRelease(n->session);
    if (n->name) CFRelease(n->name);
}

static void _ODRecordFinalize(CFTypeRef cf) {
    ODRecordRef r = (ODRecordRef)cf;
    if (r->node) CFRelease(r->node);
    if (r->recordType) CFRelease(r->recordType);
    if (r->recordName) CFRelease(r->recordName);
    if (r->attributes) CFRelease(r->attributes);
}

static void _ODQueryFinalize(CFTypeRef cf) {
    ODQueryRef q = (ODQueryRef)cf;
    if (q->node) CFRelease(q->node);
    if (q->results) CFRelease(q->results);
}

__attribute__((constructor))
static void _ODInitRuntime(void) {
    static const CFRuntimeClass sessionClass = { 0, "ODSession", NULL, NULL, _ODSessionFinalize, NULL, NULL, NULL, NULL };
    static const CFRuntimeClass nodeClass = { 0, "ODNode", NULL, NULL, _ODNodeFinalize, NULL, NULL, NULL, NULL };
    static const CFRuntimeClass recordClass = { 0, "ODRecord", NULL, NULL, _ODRecordFinalize, NULL, NULL, NULL, NULL };
    static const CFRuntimeClass queryClass = { 0, "ODQuery", NULL, NULL, _ODQueryFinalize, NULL, NULL, NULL, NULL };
    static const CFRuntimeClass contextClass = { 0, "ODContext", NULL, NULL, NULL, NULL, NULL, NULL, NULL };

    _kODSessionTypeID = _CFRuntimeRegisterClass(&sessionClass);
    _kODNodeTypeID = _CFRuntimeRegisterClass(&nodeClass);
    _kODRecordTypeID = _CFRuntimeRegisterClass(&recordClass);
    _kODQueryTypeID = _CFRuntimeRegisterClass(&queryClass);
    _kODContextTypeID = _CFRuntimeRegisterClass(&contextClass);
}

CFTypeID ODSessionGetTypeID(void) { return _kODSessionTypeID; }
CFTypeID ODNodeGetTypeID(void) { return _kODNodeTypeID; }
CFTypeID ODRecordGetTypeID(void) { return _kODRecordTypeID; }
CFTypeID ODQueryGetTypeID(void) { return _kODQueryTypeID; }
CFTypeID ODContextGetTypeID(void) { return _kODContextTypeID; }

/* Session */
ODSessionRef ODSessionCreate(CFAllocatorRef allocator, CFDictionaryRef options, CFErrorRef *error) {
    ODSessionRef s = (ODSessionRef)_CFRuntimeCreateInstance(allocator, _kODSessionTypeID, sizeof(struct __ODSession) - sizeof(CFRuntimeBase), NULL);
    if (s) {
        s->name = CFSTR("/Local/Default");
        CFRetain(s->name);
    }
    return s;
}

ODSessionRef _ODSessionGetShared(void) {
    static ODSessionRef shared = NULL;
    if (!shared) shared = ODSessionCreate(kCFAllocatorDefault, NULL, NULL);
    return shared;
}

CFArrayRef ODSessionCopyNodeNames(ODSessionRef session, CFErrorRef *error) {
    const void *names[] = { CFSTR("/Local/Default") };
    return CFArrayCreate(kCFAllocatorDefault, names, 1, &kCFTypeArrayCallBacks);
}

/* Node */
ODNodeRef ODNodeCreateWithName(CFAllocatorRef allocator, ODSessionRef session, CFStringRef name, CFErrorRef *error) {
    ODNodeRef n = (ODNodeRef)_CFRuntimeCreateInstance(allocator, _kODNodeTypeID, sizeof(struct __ODNode) - sizeof(CFRuntimeBase), NULL);
    if (n) {
        n->session = session ? (ODSessionRef)CFRetain(session) : _ODSessionGetShared();
        n->name = name ? CFStringCreateCopy(allocator, name) : CFSTR("/Local/Default");
    }
    return n;
}

ODNodeRef ODNodeCreateWithNodeType(CFAllocatorRef allocator, ODSessionRef session, ODNodeType type, CFErrorRef *error) {
    return ODNodeCreateWithName(allocator, session, CFSTR("/Local/Default"), error);
}

CFStringRef ODNodeGetName(ODNodeRef node) {
    return node ? node->name : NULL;
}

CFDictionaryRef ODNodeCopyDetails(ODNodeRef node, CFArrayRef keys, CFErrorRef *error) {
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (node && node->name) CFDictionarySetValue(d, CFSTR("NodeName"), node->name);
    return d;
}

CFArrayRef ODNodeCopySubnodeNames(ODNodeRef node, CFErrorRef *error) {
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
}

CFArrayRef ODNodeCopySupportedAttributes(ODNodeRef node, ODRecordType recordType, CFErrorRef *error) {
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
}

CFArrayRef ODNodeCopySupportedRecordTypes(ODNodeRef node, CFErrorRef *error) {
    const void *types[] = { kODRecordTypeUsers, kODRecordTypeGroups };
    return CFArrayCreate(kCFAllocatorDefault, types, 2, &kCFTypeArrayCallBacks);
}

CFArrayRef ODNodeCopyUnreachableSubnodeNames(ODNodeRef node, CFErrorRef *error) {
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
}

ODNodeRef ODNodeCreateCopy(CFAllocatorRef allocator, ODNodeRef node, CFErrorRef *error) {
    return node ? ODNodeCreateWithName(allocator, node->session, node->name, error) : NULL;
}

bool ODNodeCustomCall(ODNodeRef node, int code, CFDataRef inData, CFDataRef *outData, CFErrorRef *error) {
    if (outData) *outData = NULL;
    return true;
}

bool ODNodeSetCredentials(ODNodeRef node, ODRecordType recordType, CFStringRef recordName, CFStringRef password, CFErrorRef *error) {
    return true;
}

bool ODNodeSetCredentialsExtended(ODNodeRef node, ODRecordType recordType, ODAuthenticationType authType, CFArrayRef authItems, CFArrayRef *outAuthItems, ODContextRef *outContext, CFErrorRef *error) {
    return true;
}

bool ODNodeSetCredentialsUsingKerberosCache(ODNodeRef node, CFStringRef cacheName, CFErrorRef *error) {
    return true;
}

bool ODNodeVerifyCredentialsExtended(ODNodeRef node, ODRecordType recordType, ODAuthenticationType authType, CFArrayRef authItems, CFArrayRef *outAuthItems, ODContextRef *outContext, CFErrorRef *error) {
    return true;
}

/* Helper to build a record from struct passwd */
static ODRecordRef _ODRecordCreateFromPasswd(ODNodeRef node, struct passwd *pw) {
    if (!pw) return NULL;
    ODRecordRef r = (ODRecordRef)_CFRuntimeCreateInstance(kCFAllocatorDefault, _kODRecordTypeID, sizeof(struct __ODRecord) - sizeof(CFRuntimeBase), NULL);
    if (!r) return NULL;
    r->node = node ? (ODNodeRef)CFRetain(node) : NULL;
    r->recordType = CFRetain(kODRecordTypeUsers);
    r->recordName = CFStringCreateWithCString(kCFAllocatorDefault, pw->pw_name, kCFStringEncodingUTF8);
    r->attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, pw->pw_name, kCFStringEncodingUTF8);
    CFArrayRef names = CFArrayCreate(kCFAllocatorDefault, (const void **)&name, 1, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(r->attributes, kODAttributeTypeRecordName, names);
    CFRelease(name); CFRelease(names);

    char uid_str[32]; snprintf(uid_str, sizeof(uid_str), "%u", (unsigned)pw->pw_uid);
    CFStringRef uid_cf = CFStringCreateWithCString(kCFAllocatorDefault, uid_str, kCFStringEncodingUTF8);
    CFArrayRef uids = CFArrayCreate(kCFAllocatorDefault, (const void **)&uid_cf, 1, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(r->attributes, kODAttributeTypeUniqueID, uids);
    CFRelease(uid_cf); CFRelease(uids);

    char gid_str[32]; snprintf(gid_str, sizeof(gid_str), "%u", (unsigned)pw->pw_gid);
    CFStringRef gid_cf = CFStringCreateWithCString(kCFAllocatorDefault, gid_str, kCFStringEncodingUTF8);
    CFArrayRef gids = CFArrayCreate(kCFAllocatorDefault, (const void **)&gid_cf, 1, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(r->attributes, kODAttributeTypePrimaryGroupID, gids);
    CFRelease(gid_cf); CFRelease(gids);

    if (pw->pw_dir) {
        CFStringRef dir = CFStringCreateWithCString(kCFAllocatorDefault, pw->pw_dir, kCFStringEncodingUTF8);
        CFArrayRef dirs = CFArrayCreate(kCFAllocatorDefault, (const void **)&dir, 1, &kCFTypeArrayCallBacks);
        CFDictionarySetValue(r->attributes, kODAttributeTypeNFSHomeDirectory, dirs);
        CFRelease(dir); CFRelease(dirs);
    }
    if (pw->pw_gecos) {
        CFStringRef gecos = CFStringCreateWithCString(kCFAllocatorDefault, pw->pw_gecos, kCFStringEncodingUTF8);
        CFArrayRef fulls = CFArrayCreate(kCFAllocatorDefault, (const void **)&gecos, 1, &kCFTypeArrayCallBacks);
        CFDictionarySetValue(r->attributes, kODAttributeTypeFullName, fulls);
        CFRelease(gecos); CFRelease(fulls);
    }
    return r;
}

/* Helper to build a record from struct group */
static ODRecordRef _ODRecordCreateFromGroup(ODNodeRef node, struct group *gr) {
    if (!gr) return NULL;
    ODRecordRef r = (ODRecordRef)_CFRuntimeCreateInstance(kCFAllocatorDefault, _kODRecordTypeID, sizeof(struct __ODRecord) - sizeof(CFRuntimeBase), NULL);
    if (!r) return NULL;
    r->node = node ? (ODNodeRef)CFRetain(node) : NULL;
    r->recordType = CFRetain(kODRecordTypeGroups);
    r->recordName = CFStringCreateWithCString(kCFAllocatorDefault, gr->gr_name, kCFStringEncodingUTF8);
    r->attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, gr->gr_name, kCFStringEncodingUTF8);
    CFArrayRef names = CFArrayCreate(kCFAllocatorDefault, (const void **)&name, 1, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(r->attributes, kODAttributeTypeRecordName, names);
    CFRelease(name); CFRelease(names);

    char gid_str[32]; snprintf(gid_str, sizeof(gid_str), "%u", (unsigned)gr->gr_gid);
    CFStringRef gid_cf = CFStringCreateWithCString(kCFAllocatorDefault, gid_str, kCFStringEncodingUTF8);
    CFArrayRef gids = CFArrayCreate(kCFAllocatorDefault, (const void **)&gid_cf, 1, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(r->attributes, kODAttributeTypePrimaryGroupID, gids);
    CFRelease(gid_cf); CFRelease(gids);

    CFMutableArrayRef members = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (gr->gr_mem) {
        for (char **m = gr->gr_mem; *m; ++m) {
            CFStringRef ms = CFStringCreateWithCString(kCFAllocatorDefault, *m, kCFStringEncodingUTF8);
            if (ms) { CFArrayAppendValue(members, ms); CFRelease(ms); }
        }
    }
    CFDictionarySetValue(r->attributes, kODAttributeTypeGroupMembers, members);
    CFRelease(members);
    return r;
}

ODRecordRef ODNodeCopyRecord(ODNodeRef node, ODRecordType recordType, CFStringRef recordName, CFTypeRef attributes, CFErrorRef *error) {
    if (!recordType || !recordName) return NULL;
    char name_buf[256];
    if (!CFStringGetCString(recordName, name_buf, sizeof(name_buf), kCFStringEncodingUTF8)) return NULL;

    if (CFEqual(recordType, kODRecordTypeUsers)) {
        struct passwd *pw = getpwnam(name_buf);
        if (pw) return _ODRecordCreateFromPasswd(node, pw);
    } else if (CFEqual(recordType, kODRecordTypeGroups)) {
        struct group *gr = getgrnam(name_buf);
        if (gr) return _ODRecordCreateFromGroup(node, gr);
    }
    return NULL;
}

ODRecordRef ODNodeCreateRecord(ODNodeRef node, ODRecordType recordType, CFStringRef recordName, CFDictionaryRef attributeDict, CFErrorRef *error) {
    ODRecordRef r = (ODRecordRef)_CFRuntimeCreateInstance(kCFAllocatorDefault, _kODRecordTypeID, sizeof(struct __ODRecord) - sizeof(CFRuntimeBase), NULL);
    if (r) {
        r->node = node ? (ODNodeRef)CFRetain(node) : NULL;
        r->recordType = recordType ? (CFStringRef)CFRetain(recordType) : CFRetain(kODRecordTypeUsers);
        r->recordName = recordName ? (CFStringRef)CFRetain(recordName) : CFSTR("unknown");
        r->attributes = attributeDict ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, attributeDict) : CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    return r;
}

CFStringRef ODRecordGetRecordName(ODRecordRef record) { return record ? record->recordName : NULL; }
ODRecordType ODRecordGetRecordType(ODRecordRef record) { return record ? record->recordType : NULL; }

CFArrayRef ODRecordCopyValues(ODRecordRef record, ODAttributeType attribute, CFErrorRef *error) {
    if (!record || !record->attributes || !attribute) return NULL;
    CFArrayRef vals = (CFArrayRef)CFDictionaryGetValue(record->attributes, attribute);
    return vals ? (CFArrayRef)CFRetain(vals) : NULL;
}

bool ODRecordSetValue(ODRecordRef record, ODAttributeType attribute, CFTypeRef valueOrValues, CFErrorRef *error) {
    if (!record || !record->attributes || !attribute) return false;
    CFArrayRef arr = NULL;
    if (CFGetTypeID(valueOrValues) == CFArrayGetTypeID()) {
        arr = (CFArrayRef)CFRetain(valueOrValues);
    } else {
        arr = CFArrayCreate(kCFAllocatorDefault, &valueOrValues, 1, &kCFTypeArrayCallBacks);
    }
    CFDictionarySetValue(record->attributes, attribute, arr);
    CFRelease(arr);
    return true;
}

bool ODRecordAddValue(ODRecordRef record, ODAttributeType attribute, CFTypeRef value, CFErrorRef *error) {
    if (!record || !record->attributes || !attribute || !value) return false;
    CFMutableArrayRef arr = (CFMutableArrayRef)CFDictionaryGetValue(record->attributes, attribute);
    if (!arr || CFGetTypeID(arr) != CFArrayGetTypeID()) {
        arr = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        CFDictionarySetValue(record->attributes, attribute, arr);
        CFRelease(arr);
    }
    CFArrayAppendValue(arr, value);
    return true;
}

bool ODRecordRemoveValue(ODRecordRef record, ODAttributeType attribute, CFTypeRef value, CFErrorRef *error) { return true; }
bool ODRecordDelete(ODRecordRef record, CFErrorRef *error) { return true; }
bool ODRecordSynchronize(ODRecordRef record, CFErrorRef *error) { return true; }
bool ODRecordAddMember(ODRecordRef record, ODRecordRef newMember, CFErrorRef *error) { return true; }
bool ODRecordRemoveMember(ODRecordRef record, ODRecordRef member, CFErrorRef *error) { return true; }
bool ODRecordContainsMember(ODRecordRef record, ODRecordRef member, CFErrorRef *error) { return false; }
bool ODRecordContainsMemberRefresh(ODRecordRef record, ODRecordRef member, bool refresh, CFErrorRef *error) { return false; }
CFDictionaryRef ODRecordCopyDetails(ODRecordRef record, CFArrayRef keys, CFErrorRef *error) { return record && record->attributes ? (CFDictionaryRef)CFRetain(record->attributes) : NULL; }
CFDictionaryRef ODRecordCopyPasswordPolicy(ODRecordRef record, CFErrorRef *error) { return NULL; }
bool ODRecordChangePassword(ODRecordRef record, CFStringRef oldPassword, CFStringRef newPassword, CFErrorRef *error) { return true; }
bool ODRecordVerifyPassword(ODRecordRef record, CFStringRef password, CFErrorRef *error) { return true; }
bool ODRecordVerifyPasswordExtended(ODRecordRef record, ODAuthenticationType authType, CFArrayRef authItems, CFArrayRef *outAuthItems, ODContextRef *outContext, CFErrorRef *error) { return true; }
bool ODRecordSetNodeCredentials(ODRecordRef record, CFStringRef password, CFErrorRef *error) { return true; }
bool ODRecordSetNodeCredentialsExtended(ODRecordRef record, ODRecordType recordType, ODAuthenticationType authType, CFArrayRef authItems, CFArrayRef *outAuthItems, ODContextRef *outContext, CFErrorRef *error) { return true; }
bool ODRecordSetNodeCredentialsUsingKerberosCache(ODRecordRef record, CFStringRef cacheName, CFErrorRef *error) { return true; }

/* Query */
ODQueryRef ODQueryCreateWithNode(CFAllocatorRef allocator, ODNodeRef node, CFTypeRef recordTypeOrList, ODAttributeType attribute, ODMatchType matchType, CFTypeRef queryValueOrList, CFTypeRef returnAttributeOrList, CFIndex maxResults, CFErrorRef *error) {
    ODQueryRef q = (ODQueryRef)_CFRuntimeCreateInstance(allocator, _kODQueryTypeID, sizeof(struct __ODQuery) - sizeof(CFRuntimeBase), NULL);
    if (!q) return NULL;
    q->node = node ? (ODNodeRef)CFRetain(node) : NULL;
    q->results = CFArrayCreateMutable(allocator, 0, &kCFTypeArrayCallBacks);

    setpwent();
    struct passwd *pw;
    while ((pw = getpwent()) != NULL) {
        ODRecordRef r = _ODRecordCreateFromPasswd(node, pw);
        if (r) {
            CFArrayAppendValue(q->results, r);
            CFRelease(r);
        }
        if (maxResults > 0 && CFArrayGetCount(q->results) >= maxResults) break;
    }
    endpwent();

    setgrent();
    struct group *gr;
    while ((gr = getgrent()) != NULL) {
        ODRecordRef r = _ODRecordCreateFromGroup(node, gr);
        if (r) {
            CFArrayAppendValue(q->results, r);
            CFRelease(r);
        }
        if (maxResults > 0 && CFArrayGetCount(q->results) >= maxResults) break;
    }
    endgrent();

    return q;
}

CFArrayRef ODQueryCopyResults(ODQueryRef query, bool allowPartial, CFErrorRef *error) {
    return query && query->results ? (CFArrayRef)CFRetain(query->results) : NULL;
}

void ODQueryScheduleWithRunLoop(ODQueryRef query, CFRunLoopRef runLoop, CFStringRef runLoopMode) {}
void ODQueryUnscheduleFromRunLoop(ODQueryRef query, CFRunLoopRef runLoop, CFStringRef runLoopMode) {}
void ODQuerySetCallback(ODQueryRef query, void *callback, void *context) {}
void ODQuerySetDispatchQueue(ODQueryRef query, void *queue) {}
bool ODQuerySynchronize(ODQueryRef query, CFErrorRef *error) { return true; }

/* Internal stubs */
const char *_NodeGetNodeTypeName(ODNodeType type) { return "/Local/Default"; }
void _ODInitialize(void) {}
ODNodeRef _ODNodeCreate(CFAllocatorRef a, ODSessionRef s, CFStringRef n, CFErrorRef *e) { return ODNodeCreateWithName(a, s, n, e); }
void _ODNodeInit(void) {}
ODQueryRef _ODQueryCreate(CFAllocatorRef a, ODNodeRef n, CFTypeRef t, ODAttributeType at, ODMatchType m, CFTypeRef v, CFTypeRef r, CFIndex mx, CFErrorRef *e) { return ODQueryCreateWithNode(a, n, t, at, m, v, r, mx, e); }
void *_ODQueryGetDelegate(ODQueryRef q) { return NULL; }
void *_ODQueryGetOperationQueue(ODQueryRef q) { return NULL; }
void _ODQueryInit(void) {}
void _ODQuerySetDelegate(ODQueryRef q, void *d) {}
void _ODQuerySetOperationQueue(ODQueryRef q, void *oq) {}
ODSessionRef _ODSessionCreate(CFAllocatorRef a, CFDictionaryRef o, CFErrorRef *e) { return ODSessionCreate(a, o, e); }
void _ODSessionInit(void) {}
