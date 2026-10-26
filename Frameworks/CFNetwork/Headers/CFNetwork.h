/*
 * CFNetwork.framework public header for ravynOS.
 *
 * The proxy queries, CFHost resolution and CFHTTPMessage are implemented in
 * CFNetworkRuntime.m; everything declared here links.  The historical stream
 * stack (CFReadStreamCreateForHTTPRequest, CFNetServices, FTP, SOCKS/HTTP
 * connection objects) is not declared: Foundation's NSURLSession is the HTTP
 * client this system ships.
 */

#ifndef _RAVYNOS_CFNETWORK_H_
#define _RAVYNOS_CFNETWORK_H_

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFStream.h>
#include <CoreFoundation/CFURL.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Proxies                                                             */
/* ------------------------------------------------------------------ */

extern CFStringRef kCFProxyTypeKey;
extern CFStringRef kCFProxyTypeNone;
extern CFStringRef kCFProxyTypeHTTP;
extern CFStringRef kCFProxyTypeHTTPS;
extern CFStringRef kCFProxyTypeSOCKS;
extern CFStringRef kCFProxyHostNameKey;
extern CFStringRef kCFProxyPortNumberKey;
extern CFStringRef kCFProxyAutoConfigurationURLKey;
extern CFStringRef kCFProxyAutoConfigurationJavaScriptKey;
extern CFStringRef kCFProxyUsernameKey;
extern CFStringRef kCFProxyPasswordKey;
extern CFStringRef kCFProxiesForURLKey;

extern CFStringRef kCFNetworkProxiesHTTPEnable;
extern CFStringRef kCFNetworkProxiesHTTPProxy;
extern CFStringRef kCFNetworkProxiesHTTPPort;
extern CFStringRef kCFNetworkProxiesHTTPSEnable;
extern CFStringRef kCFNetworkProxiesHTTPSProxy;
extern CFStringRef kCFNetworkProxiesHTTPSPort;
extern CFStringRef kCFNetworkProxiesSOCKSEnable;
extern CFStringRef kCFNetworkProxiesSOCKSProxy;
extern CFStringRef kCFNetworkProxiesSOCKSPort;
extern CFStringRef kCFNetworkProxiesExceptionsList;
extern CFStringRef kCFNetworkProxiesExcludeSimpleHostnames;
extern CFStringRef kCFNetworkProxiesProxyAutoConfigEnable;
extern CFStringRef kCFNetworkProxiesProxyAutoConfigURLString;

CFDictionaryRef CFNetworkCopySystemProxySettings(void);
CFArrayRef CFNetworkCopyProxiesForURL(CFURLRef url, CFDictionaryRef proxySettings);
CFArrayRef CFNetworkCopyProxiesForAutoConfigurationScript(CFStringRef proxyAutoConfigurationScript,
                                                          CFURLRef targetURL, CFErrorRef *error);

typedef void (*CFProxyAutoConfigurationResultCallback)(void *client, CFArrayRef proxyList,
                                                       CFErrorRef error);

CFRunLoopSourceRef CFNetworkExecuteProxyAutoConfigurationURL(CFURLRef proxyAutoConfigURL,
                                                             CFURLRef targetURL,
                                                             CFProxyAutoConfigurationResultCallback cb,
                                                             CFStreamClientContext *clientContext);
CFRunLoopSourceRef CFNetworkExecuteProxyAutoConfigurationScript(CFStringRef proxyAutoConfigurationScript,
                                                               CFURLRef targetURL,
                                                               CFProxyAutoConfigurationResultCallback cb,
                                                               CFStreamClientContext *clientContext);

/* ------------------------------------------------------------------ */
/* CFHost                                                              */
/* ------------------------------------------------------------------ */

typedef struct __CFHost *CFHostRef;

typedef enum {
    kCFHostAddresses = 0,
    kCFHostNames = 1,
    kCFHostReachability = 2,
} CFHostInfoType;

typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFHostClientContext;

typedef void (*CFHostClientCallBack)(CFHostRef theHost, CFHostInfoType typeInfo,
                                     const CFStreamError *error, void *info);

CFTypeID CFHostGetTypeID(void);
CFHostRef CFHostCreateWithName(CFAllocatorRef allocator, CFStringRef hostname);
CFHostRef CFHostCreateCopy(CFAllocatorRef allocator, CFHostRef host);
Boolean CFHostStartInfoResolution(CFHostRef theHost, CFHostInfoType info, CFStreamError *error);
CFArrayRef CFHostGetAddressing(CFHostRef theHost, Boolean *hasBeenResolved);
Boolean CFHostSetClient(CFHostRef theHost, CFHostClientCallBack clientCB, CFHostClientContext *clientContext);
void CFHostScheduleWithRunLoop(CFHostRef theHost, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void CFHostUnscheduleFromRunLoop(CFHostRef theHost, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void CFHostCancelInfoResolution(CFHostRef theHost, CFHostInfoType info);

/* ------------------------------------------------------------------ */
/* CFHTTPMessage                                                       */
/* ------------------------------------------------------------------ */

typedef struct __CFHTTPMessage *CFHTTPMessageRef;

CFTypeID CFHTTPMessageGetTypeID(void);
CFHTTPMessageRef CFHTTPMessageCreateRequest(CFAllocatorRef allocator, CFStringRef requestMethod,
                                            CFURLRef url, CFStringRef httpVersion);
CFHTTPMessageRef CFHTTPMessageCreateResponse(CFAllocatorRef allocator, CFIndex statusCode,
                                             CFStringRef statusDescription, CFStringRef httpVersion);
CFHTTPMessageRef CFHTTPMessageCreateEmpty(CFAllocatorRef allocator, Boolean isRequest);
CFHTTPMessageRef CFHTTPMessageCreateCopy(CFAllocatorRef allocator, CFHTTPMessageRef message);

Boolean CFHTTPMessageIsRequest(CFHTTPMessageRef message);
CFStringRef CFHTTPMessageCopyVersion(CFHTTPMessageRef message);
CFDataRef CFHTTPMessageCopyBody(CFHTTPMessageRef message);
void CFHTTPMessageSetBody(CFHTTPMessageRef message, CFDataRef bodyData);
void CFHTTPMessageSetHeaderFieldValue(CFHTTPMessageRef message, CFStringRef headerField,
                                      CFStringRef value);
CFStringRef CFHTTPMessageCopyHeaderFieldValue(CFHTTPMessageRef message, CFStringRef headerField);
int CFHTTPMessageGetResponseStatusCode(CFHTTPMessageRef message);
CFURLRef CFHTTPMessageCopyRequestURL(CFHTTPMessageRef message);
CFStringRef CFHTTPMessageCopyRequestMethod(CFHTTPMessageRef message);
Boolean CFHTTPMessageAppendBytes(CFHTTPMessageRef message, const UInt8 *newBytes, CFIndex numBytes);
Boolean CFHTTPMessageIsHeaderComplete(CFHTTPMessageRef message);
CFDataRef CFHTTPMessageCopySerializedMessage(CFHTTPMessageRef message);

CFReadStreamRef CFReadStreamCreateForHTTPRequest(CFAllocatorRef alloc, CFHTTPMessageRef request);
CFReadStreamRef CFReadStreamCreateForStreamedHTTPRequest(CFAllocatorRef alloc,
                                                         CFHTTPMessageRef requestHeaders,
                                                         CFReadStreamRef requestBody);

#ifdef __cplusplus
}
#endif

#endif /* _RAVYNOS_CFNETWORK_H_ */
