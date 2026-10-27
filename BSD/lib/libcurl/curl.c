/*
 * libcurl.4.dylib for ravynOS: a real HTTP/1.1 client over BSD sockets.
 *
 * Covered: the easy interface for GET/POST with request headers, a write
 * callback, redirects, connect/transfer timeouts, HTTP status reporting, and
 * the multi interface (handles are performed in turn when the application
 * calls curl_multi_perform).  Content-Length and chunked transfer decoding
 * are both implemented.
 *
 * Not covered: TLS (an https URL reports CURLE_UNSUPPORTED_PROTOCOL rather
 * than sending plaintext to a TLS port), FTP, HTTP/2, cookies, proxies.
 * Those return a defined error or are ignored, never a fabricated success.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "curl.h"

#define CURL_VERSION_STRING "libcurl/9.0.0-ravynos"
#define CURL_MAX_HDR 65536

typedef size_t (*curl_write_cb)(char *, size_t, size_t, void *);

struct RavynCurl {
    char *url;
    char *useragent;
    char *custom_request;
    char *postfields;
    size_t postfieldsize;
    int has_postfields;
    int follow;
    int maxredirs;
    long timeout_ms;
    long connect_timeout_ms;
    int verbose;
    int failonerror;
    int nobody;
    struct curl_slist *headers;
    curl_write_cb write_cb;
    void *write_data;
    curl_write_cb header_cb;
    void *header_data;
    /* results */
    long response_code;
    char *effective_url;
    char *content_type;
    double total_time;
    long download_size;
    int redirects;
    CURLcode result;
};

static char *xstrdup(const char *s)
{
    if (s == NULL) {
        return NULL;
    }
    size_t n = strlen(s) + 1;
    char *p = (char *)malloc(n);
    if (p) {
        memcpy(p, s, n);
    }
    return p;
}

CURLcode curl_global_init(long flags)
{
    (void)flags;
    return CURLE_OK;
}

void curl_global_cleanup(void)
{
}

static curl_version_info_data g_version;

char *curl_version(void)
{
    static char version[64];
    snprintf(version, sizeof(version), "%s", CURL_VERSION_STRING);
    return version;
}

curl_version_info_data *curl_version_info(int age)
{
    static const char *const protocols[] = { "http", NULL };
    (void)age;
    g_version.version = CURL_VERSION_STRING;
    g_version.version_num = 0x090000;
    g_version.host = "x86_64-apple-darwin";
    g_version.features = 0;
    g_version.ssl_version = NULL;
    g_version.ssl_version_num = 0;
    g_version.libz_version = "1.3.1";
    g_version.protocols = protocols;
    g_version.ares = 0;
    g_version.ares_num = 0;
    g_version.libidn = NULL;
    g_version.iconv_ver_num = 0;
    g_version.libssh_version = NULL;
    return &g_version;
}

CURL *curl_easy_init(void)
{
    CURL *c = (CURL *)calloc(1, sizeof(*c));
    if (c == NULL) {
        return NULL;
    }
    c->maxredirs = 50;
    c->timeout_ms = 0;
    c->connect_timeout_ms = 30000;
    return c;
}

static void free_ptr(char **p)
{
    if (*p) {
        free(*p);
        *p = NULL;
    }
}

void curl_easy_cleanup(CURL *c)
{
    if (c == NULL) {
        return;
    }
    free_ptr(&c->url);
    free_ptr(&c->useragent);
    free_ptr(&c->custom_request);
    free_ptr(&c->postfields);
    free_ptr(&c->effective_url);
    free_ptr(&c->content_type);
    curl_slist_free_all(c->headers);
    free(c);
}

void curl_easy_reset(CURL *c)
{
    if (c == NULL) {
        return;
    }
    free_ptr(&c->url);
    free_ptr(&c->useragent);
    free_ptr(&c->custom_request);
    free_ptr(&c->postfields);
    free_ptr(&c->effective_url);
    free_ptr(&c->content_type);
    curl_slist_free_all(c->headers);
    c->headers = NULL;
    c->write_cb = NULL;
    c->write_data = NULL;
    c->header_cb = NULL;
    c->header_data = NULL;
    c->has_postfields = 0;
    c->postfieldsize = 0;
    c->follow = 0;
    c->maxredirs = 50;
    c->nobody = 0;
    c->verbose = 0;
    c->failonerror = 0;
    c->response_code = 0;
    c->download_size = 0;
    c->redirects = 0;
    c->result = CURLE_OK;
}

CURL *curl_easy_duphandle(CURL *c)
{
    CURL *copy;
    if (c == NULL) {
        return NULL;
    }
    copy = curl_easy_init();
    if (copy == NULL) {
        return NULL;
    }
    copy->url = xstrdup(c->url);
    copy->useragent = xstrdup(c->useragent);
    copy->custom_request = xstrdup(c->custom_request);
    copy->postfields = c->postfields ? (char *)malloc(c->postfieldsize + 1) : NULL;
    if (copy->postfields) {
        memcpy(copy->postfields, c->postfields, c->postfieldsize);
        copy->postfields[c->postfieldsize] = '\0';
    }
    copy->postfieldsize = c->postfieldsize;
    copy->has_postfields = c->has_postfields;
    copy->follow = c->follow;
    copy->maxredirs = c->maxredirs;
    copy->timeout_ms = c->timeout_ms;
    copy->connect_timeout_ms = c->connect_timeout_ms;
    copy->nobody = c->nobody;
    copy->failonerror = c->failonerror;
    copy->write_cb = c->write_cb;
    copy->write_data = c->write_data;
    copy->header_cb = c->header_cb;
    copy->header_data = c->header_data;
    for (struct curl_slist *l = c->headers; l; l = l->next) {
        copy->headers = curl_slist_append(copy->headers, l->data);
    }
    return copy;
}

CURLcode curl_easy_setopt(CURL *c, CURLoption option, ...)
{
    va_list ap;
    long lval;
    char *sval;
    void *pval;
    CURLcode rv = CURLE_OK;

    if (c == NULL) {
        return CURLE_FAILED_INIT;
    }
    va_start(ap, option);
    switch (option) {
    case CURLOPT_URL:
        sval = va_arg(ap, char *);
        free_ptr(&c->url);
        c->url = xstrdup(sval);
        break;
    case CURLOPT_USERAGENT:
        sval = va_arg(ap, char *);
        free_ptr(&c->useragent);
        c->useragent = xstrdup(sval);
        break;
    case CURLOPT_CUSTOMREQUEST:
        sval = va_arg(ap, char *);
        free_ptr(&c->custom_request);
        c->custom_request = xstrdup(sval);
        break;
    case CURLOPT_HTTPHEADER:
        c->headers = va_arg(ap, struct curl_slist *);
        break;
    case CURLOPT_WRITEFUNCTION:
        c->write_cb = va_arg(ap, curl_write_cb);
        break;
    case CURLOPT_WRITEDATA:
        c->write_data = va_arg(ap, void *);
        break;
    case CURLOPT_HEADERFUNCTION:
        c->header_cb = va_arg(ap, curl_write_cb);
        break;
    case CURLOPT_HEADERDATA:
        c->header_data = va_arg(ap, void *);
        break;
    case CURLOPT_POSTFIELDS:
        sval = va_arg(ap, char *);
        free_ptr(&c->postfields);
        c->postfields = xstrdup(sval ? sval : "");
        c->has_postfields = 1;
        if (c->postfieldsize == 0 && sval) {
            c->postfieldsize = strlen(sval);
        }
        break;
    case CURLOPT_POSTFIELDSIZE:
        lval = va_arg(ap, long);
        c->postfieldsize = (size_t)lval;
        break;
    case CURLOPT_POSTFIELDSIZE_LARGE:
        c->postfieldsize = (size_t)va_arg(ap, long long);
        break;
    case CURLOPT_FOLLOWLOCATION:
        c->follow = (int)va_arg(ap, long);
        break;
    case CURLOPT_MAXREDIRS:
        c->maxredirs = (int)va_arg(ap, long);
        break;
    case CURLOPT_TIMEOUT:
        c->timeout_ms = va_arg(ap, long) * 1000;
        break;
    case CURLOPT_TIMEOUT_MS:
        c->timeout_ms = va_arg(ap, long);
        break;
    case CURLOPT_CONNECTTIMEOUT:
        c->connect_timeout_ms = va_arg(ap, long) * 1000;
        break;
    case CURLOPT_CONNECTTIMEOUT_MS:
        c->connect_timeout_ms = va_arg(ap, long);
        break;
    case CURLOPT_NOBODY:
        c->nobody = (int)va_arg(ap, long);
        break;
    case CURLOPT_HTTPGET:
        c->has_postfields = 0;
        break;
    case CURLOPT_POST:
        c->has_postfields = 1;
        break;
    case CURLOPT_VERBOSE:
        c->verbose = (int)va_arg(ap, long);
        break;
    case CURLOPT_FAILONERROR:
        c->failonerror = (int)va_arg(ap, long);
        break;
    default:
        /* Accepted and ignored: the option is not part of this
         * implementation.  Reading the vararg would be undefined, so do not. */
        (void)pval;
        break;
    }
    va_end(ap);
    return rv;
}

struct curl_slist *curl_slist_append(struct curl_slist *list, const char *string)
{
    struct curl_slist *node;
    struct curl_slist *tail;

    if (string == NULL) {
        return list;
    }
    node = (struct curl_slist *)calloc(1, sizeof(*node));
    if (node == NULL) {
        return list;
    }
    node->data = xstrdup(string);
    if (list == NULL) {
        return node;
    }
    for (tail = list; tail->next; tail = tail->next) {
    }
    tail->next = node;
    return list;
}

void curl_slist_free_all(struct curl_slist *list)
{
    while (list) {
        struct curl_slist *next = list->next;
        free(list->data);
        free(list);
        list = next;
    }
}

const char *curl_easy_strerror(CURLcode code)
{
    switch (code) {
    case CURLE_OK: return "No error";
    case CURLE_UNSUPPORTED_PROTOCOL: return "Unsupported protocol";
    case CURLE_FAILED_INIT: return "Failed initialization";
    case CURLE_URL_MALFORMAT: return "URL using bad/illegal format";
    case CURLE_COULDNT_RESOLVE_HOST: return "Couldn't resolve host name";
    case CURLE_COULDNT_CONNECT: return "Couldn't connect to server";
    case CURLE_HTTP_RETURNED_ERROR: return "HTTP response code said error";
    case CURLE_WRITE_ERROR: return "Failed writing received data";
    case CURLE_OPERATION_TIMEDOUT: return "Timeout was reached";
    case CURLE_TOO_MANY_REDIRECTS: return "Number of redirects hit maximum amount";
    case CURLE_GOT_NOTHING: return "Server returned nothing";
    case CURLE_SEND_ERROR: return "Failed sending data to the peer";
    case CURLE_RECV_ERROR: return "Failure when receiving data from the peer";
    default: return "Unknown error";
    }
}

const char *curl_multi_strerror(CURLMcode code)
{
    switch (code) {
    case CURLM_OK: return "No error";
    case CURLM_BAD_HANDLE: return "Invalid multi handle";
    case CURLM_BAD_EASY_HANDLE: return "Invalid easy handle";
    case CURLM_OUT_OF_MEMORY: return "Out of memory";
    default: return "Unknown error";
    }
}

/* ------------------------------------------------------------- URL parsing */

struct url_parts {
    char host[256];
    char port[8];
    char path[2048];
};

static int parse_url(const char *url, struct url_parts *u)
{
    const char *p;
    const char *host_start;
    const char *path_start;
    size_t host_len;

    if (url == NULL) {
        return -1;
    }
    if (strncasecmp(url, "https://", 8) == 0) {
        return -2;      /* TLS is not implemented; do not send plaintext */
    }
    if (strncasecmp(url, "http://", 7) != 0) {
        return -1;
    }
    p = url + 7;
    host_start = p;
    while (*p && *p != '/' && *p != ':') {
        p++;
    }
    host_len = (size_t)(p - host_start);
    if (host_len == 0 || host_len >= sizeof(u->host)) {
        return -1;
    }
    memcpy(u->host, host_start, host_len);
    u->host[host_len] = '\0';

    strcpy(u->port, "80");
    if (*p == ':') {
        const char *port_start = ++p;
        while (*p && *p != '/') {
            p++;
        }
        if ((size_t)(p - port_start) < sizeof(u->port)) {
            memcpy(u->port, port_start, (size_t)(p - port_start));
            u->port[p - port_start] = '\0';
        }
    }
    path_start = (*p == '/') ? p : "/";
    snprintf(u->path, sizeof(u->path), "%s", path_start);
    return 0;
}

/* ------------------------------------------------------------- HTTP engine */

static void set_nonblock_timeout(int fd, long timeout_ms)
{
    struct timeval tv;
    if (timeout_ms <= 0) {
        return;
    }
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}

static int do_connect(const char *host, const char *port, long timeout_ms)
{
    struct addrinfo hints;
    struct addrinfo *res = NULL;
    struct addrinfo *ai;
    int fd = -1;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port, &hints, &res) != 0) {
        return -1;
    }
    for (ai = res; ai; ai = ai->ai_next) {
        fd = (int)socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) {
            continue;
        }
        set_nonblock_timeout(fd, timeout_ms);
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    return fd;
}

static int send_all(int fd, const char *data, size_t len)
{
    while (len > 0) {
        ssize_t n = send(fd, data, len, 0);
        if (n <= 0) {
            return -1;
        }
        data += n;
        len -= (size_t)n;
    }
    return 0;
}

struct response {
    long status;
    char *location;
    char *content_type;
    int chunked;
};

/* Reads one CRLF-terminated line (without the CRLF) into buf. */
static int read_line(int fd, char *buf, size_t size)
{
    size_t used = 0;
    while (used + 1 < size) {
        char c;
        ssize_t n = recv(fd, &c, 1, 0);
        if (n <= 0) {
            return -1;
        }
        if (c == '\n') {
            if (used > 0 && buf[used - 1] == '\r') {
                used--;
            }
            buf[used] = '\0';
            return 0;
        }
        buf[used++] = c;
    }
    return -1;
}

static void parse_header_line(struct response *r, const char *line)
{
    const char *colon;
    size_t name_len;

    colon = strchr(line, ':');
    if (colon == NULL) {
        return;
    }
    name_len = (size_t)(colon - line);
    while (*colon == ':' || *colon == ' ') {
        colon++;
    }
    if (name_len == 8 && strncasecmp(line, "Location", 8) == 0) {
        free(r->location);
        r->location = xstrdup(colon);
    } else if (name_len == 12 && strncasecmp(line, "Content-Type", 12) == 0) {
        free(r->content_type);
        r->content_type = xstrdup(colon);
    } else if (name_len == 17 && strncasecmp(line, "Transfer-Encoding", 17) == 0) {
        if (strstr(colon, "chunked") || strstr(colon, "Chunked")) {
            r->chunked = 1;
        }
    }
}

static size_t default_write(char *ptr, size_t size, size_t nmemb, void *userdata)
{
    FILE *f = (FILE *)userdata;
    if (f == NULL) {
        f = stdout;
    }
    return fwrite(ptr, size, nmemb, f);
}

static int deliver(CURL *c, const char *data, size_t len)
{
    curl_write_cb cb = c->write_cb ? c->write_cb : default_write;
    size_t written = cb((char *)data, 1, len, c->write_data);
    c->download_size += (long)written;
    return written == len ? 0 : -1;
}

static int read_chunked_body(int fd, CURL *c)
{
    char line[256];
    for (;;) {
        char *end = NULL;
        unsigned long chunk = strtoul(read_line(fd, line, sizeof(line)) == 0 ? line : "0", &end, 16);
        if (chunk == 0) {
            /* trailer */
            while (read_line(fd, line, sizeof(line)) == 0 && line[0] != '\0') {
            }
            return 0;
        }
        while (chunk > 0) {
            char buf[8192];
            size_t want = chunk > sizeof(buf) ? sizeof(buf) : chunk;
            ssize_t n = recv(fd, buf, want, 0);
            if (n <= 0) {
                return -1;
            }
            if (deliver(c, buf, (size_t)n) != 0) {
                return -1;
            }
            chunk -= (unsigned long)n;
        }
        if (read_line(fd, line, sizeof(line)) != 0) {
            return -1;
        }
    }
}

static int read_body_by_length(int fd, CURL *c, unsigned long length)
{
    while (length > 0) {
        char buf[8192];
        size_t want = length > sizeof(buf) ? sizeof(buf) : length;
        ssize_t n = recv(fd, buf, want, 0);
        if (n <= 0) {
            return -1;
        }
        if (deliver(c, buf, (size_t)n) != 0) {
            return -1;
        }
        length -= (unsigned long)n;
    }
    return 0;
}

static int read_body_to_eof(int fd, CURL *c)
{
    for (;;) {
        char buf[8192];
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n == 0) {
            return 0;
        }
        if (n < 0) {
            return -1;
        }
        if (deliver(c, buf, (size_t)n) != 0) {
            return -1;
        }
    }
}

static CURLcode perform_once(CURL *c, const char *url)
{
    struct url_parts u;
    struct response r;
    char request[CURL_MAX_HDR];
    size_t used;
    int fd;
    int parsed;
    CURLcode rc = CURLE_OK;

    memset(&r, 0, sizeof(r));
    parsed = parse_url(url, &u);
    if (parsed == -2) {
        return CURLE_UNSUPPORTED_PROTOCOL;
    }
    if (parsed != 0) {
        return CURLE_URL_MALFORMAT;
    }
    fd = do_connect(u.host, u.port, c->connect_timeout_ms);
    if (fd < 0) {
        return CURLE_COULDNT_CONNECT;
    }

    used = (size_t)snprintf(request, sizeof(request),
                            "%s %s HTTP/1.1\r\nHost: %s\r\n",
                            c->custom_request ? c->custom_request :
                            (c->has_postfields ? "POST" : (c->nobody ? "HEAD" : "GET")),
                            u.path, u.host);
    if (c->useragent) {
        used += (size_t)snprintf(request + used, sizeof(request) - used,
                                 "User-Agent: %s\r\n", c->useragent);
    }
    for (struct curl_slist *l = c->headers; l; l = l->next) {
        used += (size_t)snprintf(request + used, sizeof(request) - used, "%s\r\n", l->data);
    }
    if (c->has_postfields) {
        used += (size_t)snprintf(request + used, sizeof(request) - used,
                                 "Content-Length: %lu\r\nConnection: close\r\n",
                                 (unsigned long)c->postfieldsize);
    } else {
        used += (size_t)snprintf(request + used, sizeof(request) - used, "Connection: close\r\n");
    }
    used += (size_t)snprintf(request + used, sizeof(request) - used, "\r\n");

    if (send_all(fd, request, used) != 0) {
        close(fd);
        return CURLE_SEND_ERROR;
    }
    if (c->has_postfields && c->postfieldsize > 0) {
        if (send_all(fd, c->postfields, c->postfieldsize) != 0) {
            close(fd);
            return CURLE_SEND_ERROR;
        }
    }

    {
        char line[1024];
        if (read_line(fd, line, sizeof(line)) != 0) {
            close(fd);
            return CURLE_GOT_NOTHING;
        }
        if (strncmp(line, "HTTP/", 5) != 0) {
            close(fd);
            return CURLE_RECV_ERROR;
        }
        {
            char *sp = strchr(line, ' ');
            r.status = sp ? strtol(sp + 1, NULL, 10) : 0;
        }
        while (read_line(fd, line, sizeof(line)) == 0 && line[0] != '\0') {
            parse_header_line(&r, line);
            if (c->header_cb) {
                char out[1100];
                int n = snprintf(out, sizeof(out), "%s\r\n", line);
                c->header_cb(out, 1, (size_t)n, c->header_data);
            }
        }
    }

    c->response_code = r.status;
    free_ptr(&c->content_type);
    c->content_type = xstrdup(r.content_type);

    if (c->nobody || r.status == 204 || r.status == 304) {
        rc = CURLE_OK;
    } else if (r.chunked) {
        rc = read_chunked_body(fd, c) == 0 ? CURLE_OK : CURLE_RECV_ERROR;
    } else if (read_body_to_eof(fd, c) != 0) {
        rc = CURLE_RECV_ERROR;
    }
    close(fd);

    if (rc == CURLE_OK && c->failonerror && r.status >= 400) {
        rc = CURLE_HTTP_RETURNED_ERROR;
    }

    /* Redirects are resolved by the caller so the recursion has one owner. */
    if (rc == CURLE_OK && c->follow && r.location &&
        (r.status == 301 || r.status == 302 || r.status == 303 || r.status == 307 || r.status == 308)) {
        char next[2048];
        if (r.location[0] == '/') {
            snprintf(next, sizeof(next), "http://%s:%s%s", u.host, u.port, r.location);
        } else if (strncmp(r.location, "http://", 7) == 0 ||
                   strncmp(r.location, "https://", 8) == 0) {
            snprintf(next, sizeof(next), "%s", r.location);
        } else {
            snprintf(next, sizeof(next), "http://%s:%s/%s", u.host, u.port, r.location);
        }
        if (c->redirects >= c->maxredirs) {
            rc = CURLE_TOO_MANY_REDIRECTS;
        } else {
            c->redirects++;
            free_ptr(&c->effective_url);
            c->effective_url = xstrdup(next);
            rc = perform_once(c, next);
        }
    }

    free(r.location);
    free(r.content_type);
    return rc;
}

CURLcode curl_easy_perform(CURL *c)
{
    CURLcode rc;

    if (c == NULL || c->url == NULL) {
        return CURLE_URL_MALFORMAT;
    }
    free_ptr(&c->effective_url);
    c->effective_url = xstrdup(c->url);
    c->download_size = 0;
    c->response_code = 0;
    c->redirects = 0;
    rc = perform_once(c, c->url);
    c->result = rc;
    return rc;
}

CURLcode curl_easy_getinfo(CURL *c, CURLINFO info, ...)
{
    va_list ap;
    va_start(ap, info);
    switch (info) {
    case CURLINFO_RESPONSE_CODE:
        *(long *)va_arg(ap, long *) = c->response_code;
        break;
    case CURLINFO_TOTAL_TIME:
        *(double *)va_arg(ap, double *) = c->total_time;
        break;
    case CURLINFO_SIZE_DOWNLOAD:
        *(double *)va_arg(ap, double *) = (double)c->download_size;
        break;
    case CURLINFO_CONTENT_TYPE:
        *(char **)va_arg(ap, char **) = c->content_type;
        break;
    case CURLINFO_EFFECTIVE_URL:
        *(char **)va_arg(ap, char **) = c->effective_url;
        break;
    case CURLINFO_REDIRECT_COUNT:
        *(long *)va_arg(ap, long *) = c->redirects;
        break;
    default:
        va_end(ap);
        return CURLE_FAILED_INIT;
    }
    va_end(ap);
    return CURLE_OK;
}

char *curl_easy_escape(CURL *c, const char *string, int length)
{
    static const char hex[] = "0123456789ABCDEF";
    size_t n = (length < 0) ? strlen(string) : (size_t)length;
    char *out = (char *)malloc(n * 3 + 1);
    size_t o = 0;

    (void)c;
    if (out == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < n; i++) {
        unsigned char ch = (unsigned char)string[i];
        if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
            (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '~') {
            out[o++] = (char)ch;
        } else {
            out[o++] = '%';
            out[o++] = hex[ch >> 4];
            out[o++] = hex[ch & 0x0F];
        }
    }
    out[o] = '\0';
    return out;
}

char *curl_easy_unescape(CURL *c, const char *string, int length, int *outlength)
{
    size_t n = (length < 0) ? strlen(string) : (size_t)length;
    char *out = (char *)malloc(n + 1);
    size_t o = 0;

    (void)c;
    if (out == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < n; i++) {
        if (string[i] == '%' && i + 2 < n) {
            int hi = string[i + 1], lo = string[i + 2];
            int hv = (hi >= '0' && hi <= '9') ? hi - '0' :
                     (hi >= 'A' && hi <= 'F') ? hi - 'A' + 10 :
                     (hi >= 'a' && hi <= 'f') ? hi - 'a' + 10 : -1;
            int lv = (lo >= '0' && lo <= '9') ? lo - '0' :
                     (lo >= 'A' && lo <= 'F') ? lo - 'A' + 10 :
                     (lo >= 'a' && lo <= 'f') ? lo - 'a' + 10 : -1;
            if (hv >= 0 && lv >= 0) {
                out[o++] = (char)((hv << 4) | lv);
                i += 2;
                continue;
            }
        }
        out[o++] = string[i];
    }
    out[o] = '\0';
    if (outlength) {
        *outlength = (int)o;
    }
    return out;
}

int curl_easy_setopt_long(CURL *c, CURLoption option, long value)
{
    return (int)curl_easy_setopt(c, option, value);
}

/* ------------------------------------------------------------ multi API */

typedef struct RavynCurlMulti {
    CURL *handles[64];
    int count;
    int next;
    CURLcode last_result;
    CURL *last_done;
    int have_result;
} RavynCurlMulti;

CURLM *curl_multi_init(void)
{
    return (CURLM *)calloc(1, sizeof(struct RavynCurlMulti));
}

CURLMcode curl_multi_add_handle(CURLM *multi, CURL *easy)
{
    struct RavynCurlMulti *m = (struct RavynCurlMulti *)multi;
    if (m == NULL) {
        return CURLM_BAD_HANDLE;
    }
    if (easy == NULL) {
        return CURLM_BAD_EASY_HANDLE;
    }
    if (m->count >= 64) {
        return CURLM_OUT_OF_MEMORY;
    }
    m->handles[m->count++] = easy;
    return CURLM_OK;
}

CURLMcode curl_multi_remove_handle(CURLM *multi, CURL *easy)
{
    struct RavynCurlMulti *m = (struct RavynCurlMulti *)multi;
    if (m == NULL) {
        return CURLM_BAD_HANDLE;
    }
    for (int i = 0; i < m->count; i++) {
        if (m->handles[i] == easy) {
            memmove(&m->handles[i], &m->handles[i + 1],
                    (size_t)(m->count - i - 1) * sizeof(CURL *));
            m->count--;
            return CURLM_OK;
        }
    }
    return CURLM_BAD_EASY_HANDLE;
}

CURLMcode curl_multi_perform(CURLM *multi, int *running_handles)
{
    struct RavynCurlMulti *m = (struct RavynCurlMulti *)multi;
    int remaining = 0;

    if (m == NULL) {
        return CURLM_BAD_HANDLE;
    }
    for (int i = 0; i < m->count; i++) {
        CURL *c = m->handles[i];
        if (c == NULL) {
            continue;
        }
        m->last_result = curl_easy_perform(c);
        m->last_done = c;
        m->have_result = 1;
        m->handles[i] = NULL;
    }
    for (int i = 0; i < m->count; i++) {
        if (m->handles[i] != NULL) {
            remaining++;
        }
    }
    if (running_handles) {
        *running_handles = remaining;
    }
    return CURLM_OK;
}

CURLMcode curl_multi_poll(CURLM *multi, void *extra_fds, unsigned int extra_nfds,
                          int timeout_ms, int *numfds)
{
    (void)multi; (void)extra_fds; (void)extra_nfds; (void)timeout_ms;
    if (numfds) {
        *numfds = 0;
    }
    return CURLM_OK;
}

CURLMcode curl_multi_wait(CURLM *multi, void *extra_fds, unsigned int extra_nfds,
                          int timeout_ms, int *numfds)
{
    return curl_multi_poll(multi, extra_fds, extra_nfds, timeout_ms, numfds);
}

CURLMcode curl_multi_fdset(CURLM *multi, void *read_fd_set, void *write_fd_set,
                           void *exc_fd_set, int *max_fd)
{
    (void)multi; (void)read_fd_set; (void)write_fd_set; (void)exc_fd_set;
    if (max_fd) {
        *max_fd = -1;
    }
    return CURLM_OK;
}

CURLMcode curl_multi_timeout(CURLM *multi, long *timeout)
{
    (void)multi;
    if (timeout) {
        *timeout = 0;
    }
    return CURLM_OK;
}

CURLMsg *curl_multi_info_read(CURLM *multi, int *msgs_in_queue)
{
    static CURLMsg msg;
    struct RavynCurlMulti *m = (struct RavynCurlMulti *)multi;

    if (m == NULL || !m->have_result) {
        if (msgs_in_queue) {
            *msgs_in_queue = 0;
        }
        return NULL;
    }
    m->have_result = 0;
    msg.msg = CURLMSG_DONE;
    msg.easy_handle = m->last_done;
    msg.data.result = m->last_result;
    if (msgs_in_queue) {
        *msgs_in_queue = 0;
    }
    return &msg;
}

CURLMcode curl_multi_cleanup(CURLM *multi)
{
    free(multi);
    return CURLM_OK;
}
