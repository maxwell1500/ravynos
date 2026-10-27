/*
 * <curl/curl.h> for ravynOS: the libcurl 4 ABI surface this system ships.
 *
 * The implementation is a real HTTP/1.1 client over BSD sockets.  It is not
 * libcurl: it covers the easy interface an application uses for GET/POST with
 * headers, redirects and a write callback, and the multi interface through a
 * synchronous drain.  Options outside that set are accepted and ignored, which
 * is why the option enum below mirrors libcurl's numbering rather than
 * inventing one.
 */
#ifndef _CURL_CURL_H_
#define _CURL_CURL_H_

#include <sys/cdefs.h>
#include <stddef.h>
#include <stdint.h>

__BEGIN_DECLS

typedef struct RavynCurl CURL;
typedef struct RavynCurlMulti CURLM;

typedef enum {
    CURLE_OK = 0,
    CURLE_UNSUPPORTED_PROTOCOL = 1,
    CURLE_FAILED_INIT = 2,
    CURLE_URL_MALFORMAT = 3,
    CURLE_COULDNT_RESOLVE_HOST = 6,
    CURLE_COULDNT_CONNECT = 7,
    CURLE_HTTP_RETURNED_ERROR = 22,
    CURLE_WRITE_ERROR = 23,
    CURLE_OPERATION_TIMEDOUT = 28,
    CURLE_ABORTED_BY_CALLBACK = 42,
    CURLE_TOO_MANY_REDIRECTS = 47,
    CURLE_GOT_NOTHING = 52,
    CURLE_SEND_ERROR = 55,
    CURLE_RECV_ERROR = 56
} CURLcode;

typedef enum {
    CURLM_OK = 0,
    CURLM_BAD_HANDLE = 1,
    CURLM_BAD_EASY_HANDLE = 2,
    CURLM_OUT_OF_MEMORY = 3,
    CURLM_INTERNAL_ERROR = 4,
    CURLM_UNKNOWN_OPTION = 6
} CURLMcode;

typedef struct {
    int msg;                /* CURLMSG_NONE / CURLMSG_DONE */
    CURL *easy_handle;
    union {
        void *whatever;
        CURLcode result;
    } data;
} CURLMsg;

#define CURLMSG_NONE 0
#define CURLMSG_DONE 1

#define CURL_GLOBAL_DEFAULT 3
#define CURL_GLOBAL_ALL 3

typedef int CURLoption;
enum {
    CURLOPT_WRITEDATA = 10001,
    CURLOPT_URL = 10002,
    CURLOPT_WRITEFUNCTION = 20011,
    CURLOPT_HEADERFUNCTION = 20079,
    CURLOPT_HEADERDATA = 10029,
    CURLOPT_POSTFIELDS = 10015,
    CURLOPT_POSTFIELDSIZE = 60,
    CURLOPT_POSTFIELDSIZE_LARGE = 30120,
    CURLOPT_USERAGENT = 10018,
    CURLOPT_HTTPHEADER = 10023,
    CURLOPT_FOLLOWLOCATION = 52,
    CURLOPT_TIMEOUT = 13,
    CURLOPT_CONNECTTIMEOUT = 78,
    CURLOPT_TIMEOUT_MS = 155,
    CURLOPT_CONNECTTIMEOUT_MS = 156,
    CURLOPT_MAXREDIRS = 68,
    CURLOPT_NOBODY = 44,
    CURLOPT_HTTPGET = 80,
    CURLOPT_POST = 47,
    CURLOPT_CUSTOMREQUEST = 10036,
    CURLOPT_POSTFIELDSIZE_LARGE_ = 30120,
    CURLOPT_VERBOSE = 41,
    CURLOPT_FAILONERROR = 45,
    CURLOPT_SSL_VERIFYPEER = 64,
    CURLOPT_SSL_VERIFYHOST = 81,
    CURLOPT_CAINFO = 10065,
    CURLOPT_ACCEPT_ENCODING = 10102,
    CURLOPT_USERNAME = 10173,
    CURLOPT_PASSWORD = 10174,
    CURLOPT_HTTPAUTH = 107,
    CURLOPT_PROXY = 10004,
    CURLOPT_NOSIGNAL = 99,
    CURLOPT_TCP_KEEPALIVE = 213,
    CURLOPT_RESOLVE = 10203,
    CURLOPT_REFERER = 10016,
    CURLOPT_COOKIE = 10022,
    CURLOPT_INFILESIZE_LARGE = 30115,
    CURLOPT_UPLOAD = 46,
    CURLOPT_RANGE = 10007,
    CURLOPT_LOW_SPEED_LIMIT = 19,
    CURLOPT_LOW_SPEED_TIME = 20
};

typedef int CURLINFO;
enum {
    CURLINFO_RESPONSE_CODE = 0x200002,
    CURLINFO_TOTAL_TIME = 0x300003,
    CURLINFO_SIZE_DOWNLOAD = 0x300008,
    CURLINFO_CONTENT_TYPE = 0x100012,
    CURLINFO_EFFECTIVE_URL = 0x100001,
    CURLINFO_REDIRECT_COUNT = 0x200014
};

struct curl_slist {
    char *data;
    struct curl_slist *next;
};

extern CURLcode curl_global_init(long flags);
extern void curl_global_cleanup(void);
extern char *curl_version(void);
typedef struct {
    const char *version;
    unsigned int version_num;
    const char *host;
    int features;
    const char *ssl_version;
    long ssl_version_num;
    const char *libz_version;
    const char *const *protocols;
    int ares;
    int ares_num;
    const char *libidn;
    int iconv_ver_num;
    const char *libssh_version;
} curl_version_info_data;
extern curl_version_info_data *curl_version_info(int age);

extern CURL *curl_easy_init(void);
extern CURLcode curl_easy_setopt(CURL *curl, CURLoption option, ...);
extern CURLcode curl_easy_perform(CURL *curl);
extern CURLcode curl_easy_getinfo(CURL *curl, CURLINFO info, ...);
extern void curl_easy_cleanup(CURL *curl);
extern CURL *curl_easy_duphandle(CURL *curl);
extern void curl_easy_reset(CURL *curl);
extern const char *curl_easy_strerror(CURLcode code);
extern char *curl_easy_escape(CURL *curl, const char *string, int length);
extern char *curl_easy_unescape(CURL *curl, const char *string, int length,
                                int *outlength);
extern int curl_easy_setopt_long(CURL *curl, CURLoption option, long value);

extern struct curl_slist *curl_slist_append(struct curl_slist *list,
                                            const char *string);
extern void curl_slist_free_all(struct curl_slist *list);

extern CURLM *curl_multi_init(void);
extern CURLMcode curl_multi_add_handle(CURLM *multi, CURL *easy);
extern CURLMcode curl_multi_remove_handle(CURLM *multi, CURL *easy);
extern CURLMcode curl_multi_perform(CURLM *multi, int *running_handles);
extern CURLMcode curl_multi_poll(CURLM *multi, void *extra_fds, unsigned int extra_nfds,
                                 int timeout_ms, int *numfds);
extern CURLMcode curl_multi_wait(CURLM *multi, void *extra_fds, unsigned int extra_nfds,
                                 int timeout_ms, int *numfds);
extern CURLMcode curl_multi_fdset(CURLM *multi, void *read_fd_set, void *write_fd_set,
                                  void *exc_fd_set, int *max_fd);
extern CURLMcode curl_multi_timeout(CURLM *multi, long *timeout);
extern CURLMsg *curl_multi_info_read(CURLM *multi, int *msgs_in_queue);
extern CURLMcode curl_multi_cleanup(CURLM *multi);
extern const char *curl_multi_strerror(CURLMcode code);

__END_DECLS

#endif
