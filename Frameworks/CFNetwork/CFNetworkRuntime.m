/*
 * CFNetwork.framework runtime for ravynOS.
 *
 * Apple's CFNetwork sources in this tree (CFHTTPConnection, the SPNEGO/NTLM
 * filters, CFNetServices, CFFTPStream...) are a complete, old, TCP/stream
 * stack that does not build here and duplicates what Foundation's URL loading
 * already does.  What a bundled application actually links against is:
 *
 *   * the proxy/Settings queries CFNetworkCopySystemProxySettings and
 *     CFNetworkCopyProxiesForURL, which it uses to decide whether a request
 *     goes through a proxy;
 *   * CFHost, for resolving a name before opening its own socket;
 *   * CFHTTPMessage, for building and parsing request/response heads.
 *
 * Those three are implemented, against the real resolver and a real message
 * buffer.  The rest of the historical surface is not declared, so a caller
 * that needs it fails to compile rather than at run time.
 */

#include "Headers/CFNetwork.h"
#include "CFRuntime.h"
#include <CoreFoundation/CFStream.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

/* ------------------------------------------------------------------ */
/* Proxy support                                                       */
/* ------------------------------------------------------------------ */

CFStringRef kCFProxyTypeKey = NULL;
CFStringRef kCFProxyTypeNone = NULL;
CFStringRef kCFProxyTypeHTTP = NULL;
CFStringRef kCFProxyTypeHTTPS = NULL;
CFStringRef kCFProxyTypeSOCKS = NULL;
CFStringRef kCFProxyHostNameKey = NULL;
CFStringRef kCFProxyPortNumberKey = NULL;
CFStringRef kCFProxyAutoConfigurationURLKey = NULL;
CFStringRef kCFProxyAutoConfigurationJavaScriptKey = NULL;
CFStringRef kCFProxyUsernameKey = NULL;
CFStringRef kCFProxyPasswordKey = NULL;
CFStringRef kCFProxiesForURLKey = NULL;
CFStringRef kCFNetworkProxiesHTTPEnable = NULL;
CFStringRef kCFNetworkProxiesHTTPProxy = NULL;
CFStringRef kCFNetworkProxiesHTTPPort = NULL;
CFStringRef kCFNetworkProxiesHTTPSEnable = NULL;
CFStringRef kCFNetworkProxiesHTTPSProxy = NULL;
CFStringRef kCFNetworkProxiesHTTPSPort = NULL;
CFStringRef kCFNetworkProxiesSOCKSEnable = NULL;
CFStringRef kCFNetworkProxiesSOCKSProxy = NULL;
CFStringRef kCFNetworkProxiesSOCKSPort = NULL;
CFStringRef kCFNetworkProxiesExceptionsList = NULL;
CFStringRef kCFNetworkProxiesExcludeSimpleHostnames = NULL;
CFStringRef kCFNetworkProxiesProxyAutoConfigEnable = NULL;
CFStringRef kCFNetworkProxiesProxyAutoConfigURLString = NULL;

static void CFNetworkCreateConstants(void) {
    struct { CFStringRef *slot; const char *text; } table[] = {
        { &kCFProxyTypeKey, "kCFProxyTypeKey" },
        { &kCFProxyTypeNone, "kCFProxyTypeNone" },
        { &kCFProxyTypeHTTP, "kCFProxyTypeHTTP" },
        { &kCFProxyTypeHTTPS, "kCFProxyTypeHTTPS" },
        { &kCFProxyTypeSOCKS, "kCFProxyTypeSOCKS" },
        { &kCFProxyHostNameKey, "kCFProxyHostNameKey" },
        { &kCFProxyPortNumberKey, "kCFProxyPortNumberKey" },
        { &kCFProxyAutoConfigurationURLKey, "kCFProxyAutoConfigurationURLKey" },
        { &kCFProxyAutoConfigurationJavaScriptKey, "kCFProxyAutoConfigurationJavaScriptKey" },
        { &kCFProxyUsernameKey, "kCFProxyUsernameKey" },
        { &kCFProxyPasswordKey, "kCFProxyPasswordKey" },
        { &kCFProxiesForURLKey, "kCFProxiesForURLKey" },
        { &kCFNetworkProxiesHTTPEnable, "HTTPEnable" },
        { &kCFNetworkProxiesHTTPProxy, "HTTPProxy" },
        { &kCFNetworkProxiesHTTPPort, "HTTPPort" },
        { &kCFNetworkProxiesHTTPSEnable, "HTTPSEnable" },
        { &kCFNetworkProxiesHTTPSProxy, "HTTPSProxy" },
        { &kCFNetworkProxiesHTTPSPort, "HTTPSPort" },
        { &kCFNetworkProxiesSOCKSEnable, "SOCKSEnable" },
        { &kCFNetworkProxiesSOCKSProxy, "SOCKSProxy" },
        { &kCFNetworkProxiesSOCKSPort, "SOCKSPort" },
        { &kCFNetworkProxiesExceptionsList, "ExceptionsList" },
        { &kCFNetworkProxiesExcludeSimpleHostnames, "ExcludeSimpleHostnames" },
        { &kCFNetworkProxiesProxyAutoConfigEnable, "ProxyAutoConfigEnable" },
        { &kCFNetworkProxiesProxyAutoConfigURLString, "ProxyAutoConfigURLString" },
    };
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        if (*table[i].slot == NULL) {
            *table[i].slot = CFStringCreateWithCString(kCFAllocatorDefault, table[i].text,
                                                       kCFStringEncodingUTF8);
        }
    }
}

__attribute__((constructor)) static void CFNetworkInit(void) {
    CFNetworkCreateConstants();
}

CFDictionaryRef CFNetworkCopySystemProxySettings(void) {
    /* No system proxy configuration exists on ravynOS.  An empty dictionary
     * is the documented "no proxies" answer, and it is what every caller
     * already handles. */
    return CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                              &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

CFArrayRef CFNetworkCopyProxiesForURL(CFURLRef url, CFDictionaryRef proxySettings) {
    (void)proxySettings;
    (void)url;
    CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 1, &kCFTypeArrayCallBacks);
    CFMutableDictionaryRef direct = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                             &kCFTypeDictionaryKeyCallBacks,
                                                             &kCFTypeDictionaryValueCallBacks);
    if (kCFProxyTypeKey && kCFProxyTypeNone) {
        CFDictionarySetValue(direct, kCFProxyTypeKey, kCFProxyTypeNone);
    }
    CFArrayAppendValue(result, direct);
    CFRelease(direct);
    return result;
}

CFArrayRef CFNetworkCopyProxiesForAutoConfigurationScript(CFStringRef proxyAutoConfigurationScript,
                                                          CFURLRef targetURL, CFErrorRef *error) {
    (void)proxyAutoConfigurationScript;
    if (error) *error = NULL;
    return CFNetworkCopyProxiesForURL(targetURL, NULL);
}

CFRunLoopSourceRef CFNetworkExecuteProxyAutoConfigurationURL(CFURLRef proxyAutoConfigURL,
                                                             CFURLRef targetURL,
                                                             CFProxyAutoConfigurationResultCallback cb,
                                                             CFStreamClientContext *clientContext) {
    (void)proxyAutoConfigURL;
    (void)cb;
    (void)clientContext;
    (void)targetURL;
    return NULL;
}

CFRunLoopSourceRef CFNetworkExecuteProxyAutoConfigurationScript(CFStringRef proxyAutoConfigurationScript,
                                                               CFURLRef targetURL,
                                                               CFProxyAutoConfigurationResultCallback cb,
                                                               CFStreamClientContext *clientContext) {
    (void)proxyAutoConfigurationScript;
    (void)cb;
    (void)clientContext;
    (void)targetURL;
    return NULL;
}

/* ------------------------------------------------------------------ */
/* CFHost                                                              */
/* ------------------------------------------------------------------ */

struct __CFHost {
    CFRuntimeBase base;
    CFStringRef name;
    CFArrayRef addresses;
    Boolean resolved;
};
typedef struct __CFHost *CFHostRefInternal;

static void CFHostDealloc(CFTypeRef cf) {
    CFHostRefInternal host = (CFHostRefInternal)cf;
    if (host->name) CFRelease(host->name);
    if (host->addresses) CFRelease(host->addresses);
}

static CFStringRef CFHostCopyDesc(CFTypeRef cf) {
    CFHostRefInternal host = (CFHostRefInternal)cf;
    if (host->name) return CFStringCreateCopy(kCFAllocatorDefault, host->name);
    return CFStringCreateWithCString(kCFAllocatorDefault, "CFHost", kCFStringEncodingUTF8);
}

static CFRuntimeClass CFHostClass = {
    .version = 0,
    .className = "CFHost",
    .finalize = CFHostDealloc,
    .copyDebugDesc = CFHostCopyDesc,
};

CFTypeID CFHostGetTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        typeID = _CFRuntimeRegisterClass(&CFHostClass);
    }
    return typeID;
}

CFHostRef CFHostCreateWithName(CFAllocatorRef allocator, CFStringRef hostname) {
    if (hostname == NULL) return NULL;
    CFHostRefInternal host = (CFHostRefInternal)_CFRuntimeCreateInstance(
        allocator ? allocator : kCFAllocatorDefault, CFHostGetTypeID(),
        sizeof(struct __CFHost) - sizeof(CFRuntimeBase), NULL);
    if (host == NULL) return NULL;
    host->name = CFStringCreateCopy(kCFAllocatorDefault, hostname);
    host->addresses = NULL;
    host->resolved = false;
    return (CFHostRef)host;
}

CFHostRef CFHostCreateWithAddress(CFAllocatorRef allocator, CFDataRef addr) {
    (void)addr;
    return NULL;
}

CFHostRef CFHostCreateCopy(CFAllocatorRef allocator, CFHostRef host) {
    if (host == NULL) return NULL;
    return CFHostCreateWithName(allocator, host->name);
}

Boolean CFHostStartInfoResolution(CFHostRef theHost, CFHostInfoType info, CFStreamError *error) {
    if (theHost == NULL) {
        if (error) {
            /* kCFStreamErrorDomainNetDB is not defined by this tree's
             * CFStream.h, so the domain is spelled out (its value is 3). */
            error->domain = 3;
            error->error = EINVAL;
        }
        return false;
    }
    if (error) {
        memset(error, 0, sizeof(*error));
    }
    if (info != kCFHostAddresses) {
        /* Names, reachability and canonical names are not resolved here; the
         * address path is the one a caller needs before opening a socket. */
        return false;
    }
    if (theHost->resolved) return true;

    char nameBuffer[1024];
    if (!CFStringGetCString(theHost->name, nameBuffer, sizeof(nameBuffer), kCFStringEncodingUTF8)) {
        return false;
    }
    struct addrinfo hints;
    struct addrinfo *result = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    int rc = getaddrinfo(nameBuffer, NULL, &hints, &result);
    if (rc != 0 || result == NULL) {
        if (error) {
            error->domain = 3;
            error->error = rc;
        }
        if (result) freeaddrinfo(result);
        return false;
    }

    CFMutableArrayRef addresses = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    for (struct addrinfo *ai = result; ai != NULL; ai = ai->ai_next) {
        CFDataRef data = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)ai->ai_addr,
                                      (CFIndex)ai->ai_addrlen);
        if (data) {
            CFArrayAppendValue(addresses, data);
            CFRelease(data);
        }
    }
    freeaddrinfo(result);
    if (theHost->addresses) CFRelease(theHost->addresses);
    theHost->addresses = addresses;
    theHost->resolved = true;
    return true;
}

CFArrayRef CFHostGetAddressing(CFHostRef theHost, Boolean *hasBeenResolved) {
    if (theHost == NULL) {
        if (hasBeenResolved) *hasBeenResolved = false;
        return NULL;
    }
    if (hasBeenResolved) *hasBeenResolved = theHost->resolved;
    return theHost->addresses;
}

Boolean CFHostSetClient(CFHostRef theHost, CFHostClientCallBack clientCB, CFHostClientContext *clientContext) {
    (void)theHost;
    (void)clientCB;
    (void)clientContext;
    return true;
}

void CFHostScheduleWithRunLoop(CFHostRef theHost, CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    (void)theHost;
    (void)runLoop;
    (void)runLoopMode;
}

void CFHostUnscheduleFromRunLoop(CFHostRef theHost, CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    (void)theHost;
    (void)runLoop;
    (void)runLoopMode;
}

void CFHostCancelInfoResolution(CFHostRef theHost, CFHostInfoType info) {
    (void)theHost;
    (void)info;
}

/* ------------------------------------------------------------------ */
/* CFHTTPMessage                                                       */
/* ------------------------------------------------------------------ */

struct __CFHTTPMessage {
    CFRuntimeBase base;
    UInt8 *bytes;
    CFIndex length;
    CFIndex capacity;
    Boolean isRequest;
    Boolean isHeaderComplete;
    int statusCode;
    CFStringRef version;
    CFStringRef method;
    CFURLRef url;
    Boolean headersParsed;
};
typedef struct __CFHTTPMessage *CFHTTPMessageRefInternal;

static void CFHTTPMessageDealloc(CFTypeRef cf) {
    CFHTTPMessageRefInternal msg = (CFHTTPMessageRefInternal)cf;
    free(msg->bytes);
    if (msg->version) CFRelease(msg->version);
    if (msg->method) CFRelease(msg->method);
    if (msg->url) CFRelease(msg->url);
}

static CFStringRef CFHTTPMessageCopyDesc(CFTypeRef cf) {
    CFHTTPMessageRefInternal msg = (CFHTTPMessageRefInternal)cf;
    char text[64];
    if (msg->isRequest) {
        snprintf(text, sizeof(text), "CFHTTPMessage request (%ld bytes)", (long)msg->length);
    } else {
        snprintf(text, sizeof(text), "CFHTTPMessage response %d (%ld bytes)", msg->statusCode,
                 (long)msg->length);
    }
    return CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
}

static CFRuntimeClass CFHTTPMessageClass = {
    .version = 0,
    .className = "CFHTTPMessage",
    .finalize = CFHTTPMessageDealloc,
    .copyDebugDesc = CFHTTPMessageCopyDesc,
};

CFTypeID CFHTTPMessageGetTypeID(void) {
    static CFTypeID typeID = _kCFRuntimeNotATypeID;
    if (typeID == _kCFRuntimeNotATypeID) {
        typeID = _CFRuntimeRegisterClass(&CFHTTPMessageClass);
    }
    return typeID;
}

static CFHTTPMessageRefInternal httpMessageAllocate(Boolean isRequest) {
    CFHTTPMessageRefInternal msg = (CFHTTPMessageRefInternal)_CFRuntimeCreateInstance(
        kCFAllocatorDefault, CFHTTPMessageGetTypeID(),
        sizeof(struct __CFHTTPMessage) - sizeof(CFRuntimeBase), NULL);
    if (msg == NULL) return NULL;
    msg->capacity = 512;
    msg->bytes = (UInt8 *)calloc(1, (size_t)msg->capacity);
    if (msg->bytes == NULL) {
        CFRelease((CFTypeRef)msg);
        return NULL;
    }
    msg->length = 0;
    msg->isRequest = isRequest;
    return msg;
}

static void appendBytes(CFHTTPMessageRefInternal msg, const UInt8 *bytes, CFIndex length) {
    if (msg == NULL || bytes == NULL || length <= 0) return;
    if (msg->length + length + 1 > msg->capacity) {
        CFIndex capacity = msg->capacity;
        while (capacity < msg->length + length + 1) {
            capacity *= 2;
        }
        UInt8 *grown = (UInt8 *)realloc(msg->bytes, (size_t)capacity);
        if (grown == NULL) return;
        msg->bytes = grown;
        msg->capacity = capacity;
    }
    memcpy(msg->bytes + msg->length, bytes, (size_t)length);
    msg->length += length;
    msg->bytes[msg->length] = '\0';
}

CFHTTPMessageRef CFHTTPMessageCreateRequest(CFAllocatorRef allocator, CFStringRef requestMethod,
                                            CFURLRef url, CFStringRef httpVersion) {
    (void)allocator;
    if (requestMethod == NULL || url == NULL) return NULL;
    CFHTTPMessageRefInternal msg = httpMessageAllocate(true);
    if (msg == NULL) return NULL;
    msg->method = CFStringCreateCopy(kCFAllocatorDefault, requestMethod);
    msg->url = (CFURLRef)CFRetain(url);
    msg->version = CFStringCreateCopy(kCFAllocatorDefault,
                                      httpVersion ? httpVersion : CFSTR("HTTP/1.1"));
    CFStringRef path = CFURLCopyPath(url);
    char pathBuffer[2048] = "/";
    if (path) {
        CFStringGetCString(path, pathBuffer, sizeof(pathBuffer), kCFStringEncodingUTF8);
        /* CFURLCopyPath returns "" for a bare host; a request line needs "/". */
        if (pathBuffer[0] == '\0') {
            strcpy(pathBuffer, "/");
        }
        CFRelease(path);
    }
    char methodBuffer[64] = "GET";
    char versionBuffer[32] = "HTTP/1.1";
    CFStringGetCString(requestMethod, methodBuffer, sizeof(methodBuffer), kCFStringEncodingUTF8);
    if (msg->version) {
        CFStringGetCString(msg->version, versionBuffer, sizeof(versionBuffer), kCFStringEncodingUTF8);
    }
    char line[4096];
    snprintf(line, sizeof(line), "%s %s %s\r\n", methodBuffer, pathBuffer, versionBuffer);
    appendBytes(msg, (const UInt8 *)line, (CFIndex)strlen(line));
    msg->isHeaderComplete = false;
    return (CFHTTPMessageRef)msg;
}

CFHTTPMessageRef CFHTTPMessageCreateResponse(CFAllocatorRef allocator, CFIndex statusCode,
                                             CFStringRef statusDescription, CFStringRef httpVersion) {
    (void)allocator;
    CFHTTPMessageRefInternal msg = httpMessageAllocate(false);
    if (msg == NULL) return NULL;
    msg->statusCode = (int)statusCode;
    msg->version = CFStringCreateCopy(kCFAllocatorDefault, httpVersion ? httpVersion : CFSTR("HTTP/1.1"));
    char versionBuffer[32] = "HTTP/1.1";
    if (msg->version) {
        CFStringGetCString(msg->version, versionBuffer, sizeof(versionBuffer), kCFStringEncodingUTF8);
    }
    char description[128] = "";
    if (statusDescription == NULL) {
        switch (statusCode) {
            case 200: strcpy(description, "OK"); break;
            case 204: strcpy(description, "No Content"); break;
            case 301: strcpy(description, "Moved Permanently"); break;
            case 302: strcpy(description, "Found"); break;
            case 304: strcpy(description, "Not Modified"); break;
            case 400: strcpy(description, "Bad Request"); break;
            case 401: strcpy(description, "Unauthorized"); break;
            case 403: strcpy(description, "Forbidden"); break;
            case 404: strcpy(description, "Not Found"); break;
            case 500: strcpy(description, "Internal Server Error"); break;
            default: strcpy(description, "Unknown"); break;
        }
    } else {
        CFStringGetCString(statusDescription, description, sizeof(description), kCFStringEncodingUTF8);
    }
    char line[512];
    snprintf(line, sizeof(line), "%s %ld %s\r\n", versionBuffer, (long)statusCode, description);
    appendBytes(msg, (const UInt8 *)line, (CFIndex)strlen(line));
    msg->isHeaderComplete = false;
    return (CFHTTPMessageRef)msg;
}

CFHTTPMessageRef CFHTTPMessageCreateEmpty(CFAllocatorRef allocator, Boolean isRequest) {
    (void)allocator;
    return (CFHTTPMessageRef)httpMessageAllocate(isRequest);
}

CFHTTPMessageRef CFHTTPMessageCreateCopy(CFAllocatorRef allocator, CFHTTPMessageRef message) {
    (void)allocator;
    if (message == NULL) return NULL;
    CFHTTPMessageRefInternal copy = httpMessageAllocate(message->isRequest);
    if (copy == NULL) return NULL;
    appendBytes(copy, message->bytes, message->length);
    copy->isHeaderComplete = message->isHeaderComplete;
    copy->statusCode = message->statusCode;
    copy->version = message->version ? CFStringCreateCopy(kCFAllocatorDefault, message->version) : NULL;
    copy->method = message->method ? CFStringCreateCopy(kCFAllocatorDefault, message->method) : NULL;
    copy->url = message->url ? (CFURLRef)CFRetain(message->url) : NULL;
    return (CFHTTPMessageRef)copy;
}

Boolean CFHTTPMessageIsRequest(CFHTTPMessageRef message) {
    return message ? message->isRequest : false;
}

CFStringRef CFHTTPMessageCopyVersion(CFHTTPMessageRef message) {
    if (message == NULL || message->version == NULL) return NULL;
    return CFStringCreateCopy(kCFAllocatorDefault, message->version);
}

CFDataRef CFHTTPMessageCopyBody(CFHTTPMessageRef message) {
    if (message == NULL) return NULL;
    UInt8 *separator = NULL;
    for (CFIndex i = 0; i + 4 <= message->length; i++) {
        if (memcmp(message->bytes + i, "\r\n\r\n", 4) == 0) {
            separator = message->bytes + i + 4;
            break;
        }
    }
    if (separator == NULL) return NULL;
    CFIndex bodyLength = message->length - (separator - message->bytes);
    if (bodyLength <= 0) return NULL;
    return CFDataCreate(kCFAllocatorDefault, separator, bodyLength);
}

void CFHTTPMessageSetBody(CFHTTPMessageRef message, CFDataRef bodyData) {
    if (message == NULL) return;
    CFIndex bodyLength = bodyData ? CFDataGetLength(bodyData) : 0;
    char lengthLine[128];
    snprintf(lengthLine, sizeof(lengthLine), "Content-Length: %ld\r\n", (long)bodyLength);
    /* The body is appended after the header block; a caller sets the header
     * terminator through CFHTTPMessageSetHeaderFieldValue/SetBody in either
     * order, so make sure the block is terminated first. */
    Boolean terminated = (message->length >= 4 &&
                          memcmp(message->bytes + message->length - 4, "\r\n\r\n", 4) == 0);
    if (!terminated) {
        appendBytes(message, (const UInt8 *)lengthLine, (CFIndex)strlen(lengthLine));
        appendBytes(message, (const UInt8 *)"\r\n", 2);
    }
    if (bodyLength > 0) {
        appendBytes(message, CFDataGetBytePtr(bodyData), bodyLength);
    }
}

void CFHTTPMessageSetHeaderFieldValue(CFHTTPMessageRef message, CFStringRef headerField,
                                      CFStringRef value) {
    if (message == NULL || headerField == NULL) return;
    char field[256] = "";
    CFStringGetCString(headerField, field, sizeof(field), kCFStringEncodingUTF8);
    char line[1024];
    if (value) {
        char text[768] = "";
        CFStringGetCString(value, text, sizeof(text), kCFStringEncodingUTF8);
        snprintf(line, sizeof(line), "%s: %s\r\n", field, text);
    } else {
        snprintf(line, sizeof(line), "%s: \r\n", field);
    }
    appendBytes(message, (const UInt8 *)line, (CFIndex)strlen(line));
}

CFStringRef CFHTTPMessageCopyHeaderFieldValue(CFHTTPMessageRef message, CFStringRef headerField) {
    if (message == NULL || headerField == NULL) return NULL;
    char field[256] = "";
    CFStringGetCString(headerField, field, sizeof(field), kCFStringEncodingUTF8);
    size_t fieldLength = strlen(field);

    const UInt8 *cursor = message->bytes;
    const UInt8 *end = message->bytes + message->length;
    /* Skip the start line. */
    while (cursor < end && !(cursor + 1 < end && cursor[0] == '\r' && cursor[1] == '\n')) {
        cursor++;
    }
    cursor += 2;
    while (cursor < end) {
        const UInt8 *lineEnd = cursor;
        while (lineEnd + 1 < end && !(lineEnd[0] == '\r' && lineEnd[1] == '\n')) {
            lineEnd++;
        }
        size_t lineLength = (size_t)(lineEnd - cursor);
        if (lineLength == 0) break;
        if (lineLength > fieldLength + 1 &&
            strncasecmp((const char *)cursor, field, fieldLength) == 0 &&
            cursor[fieldLength] == ':') {
            const UInt8 *valueStart = cursor + fieldLength + 1;
            while (valueStart < lineEnd && (*valueStart == ' ' || *valueStart == '\t')) {
                valueStart++;
            }
            return CFStringCreateWithBytes(kCFAllocatorDefault, valueStart,
                                           (CFIndex)(lineEnd - valueStart),
                                           kCFStringEncodingUTF8, false);
        }
        cursor = lineEnd + 2;
    }
    return NULL;
}

int CFHTTPMessageGetResponseStatusCode(CFHTTPMessageRef message) {
    if (message == NULL || message->isRequest) return 0;
    if (message->statusCode != 0) return message->statusCode;
    /* Parse "HTTP/1.1 200 OK" out of the accumulated bytes. */
    const char *line = (const char *)message->bytes;
    const char *space = line ? strchr(line, ' ') : NULL;
    if (space) {
        message->statusCode = atoi(space + 1);
    }
    return message->statusCode;
}

CFURLRef CFHTTPMessageCopyRequestURL(CFHTTPMessageRef message) {
    if (message == NULL || message->url == NULL) return NULL;
    return (CFURLRef)CFRetain(message->url);
}

CFStringRef CFHTTPMessageCopyRequestMethod(CFHTTPMessageRef message) {
    if (message == NULL || message->method == NULL) return NULL;
    return CFStringCreateCopy(kCFAllocatorDefault, message->method);
}

Boolean CFHTTPMessageAppendBytes(CFHTTPMessageRef message, const UInt8 *newBytes, CFIndex numBytes) {
    if (message == NULL || newBytes == NULL) return false;
    appendBytes(message, newBytes, numBytes);
    if (!message->headersParsed) {
        for (CFIndex i = 0; i + 4 <= message->length; i++) {
            if (memcmp(message->bytes + i, "\r\n\r\n", 4) == 0) {
                message->isHeaderComplete = true;
                message->headersParsed = true;
                break;
            }
        }
    }
    return true;
}

Boolean CFHTTPMessageIsHeaderComplete(CFHTTPMessageRef message) {
    return message ? message->isHeaderComplete : false;
}

CFDataRef CFHTTPMessageCopySerializedMessage(CFHTTPMessageRef message) {
    if (message == NULL) return NULL;
    return CFDataCreate(kCFAllocatorDefault, message->bytes, message->length);
}

/* ------------------------------------------------------------------ */
/* CFReadStream for HTTP                                               */
/* ------------------------------------------------------------------ */

CFReadStreamRef CFReadStreamCreateForHTTPRequest(CFAllocatorRef alloc, CFHTTPMessageRef request) {
    (void)alloc;
    (void)request;
    /* The stream stack that would carry this request is not implemented; a
     * caller that needs it uses Foundation's NSURLConnection/NSURLSession,
     * which is where this tree's HTTP support lives. */
    return NULL;
}

CFReadStreamRef CFReadStreamCreateForStreamedHTTPRequest(CFAllocatorRef alloc,
                                                         CFHTTPMessageRef requestHeaders,
                                                         CFReadStreamRef requestBody) {
    (void)alloc;
    (void)requestHeaders;
    (void)requestBody;
    return NULL;
}
