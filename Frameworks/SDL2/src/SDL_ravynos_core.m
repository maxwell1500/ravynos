/*
 * SDL2 Core, Error, Hints, Log, Version, CPUInfo, Power, Filesystem, and MessageBox
 * implementation for ravynOS.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include "SDL_ravynos_internal.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <mach-o/dyld.h>

static Uint32 g_sdl_initialized_subsystems = 0;
static __thread char g_sdl_error_buf[1024];

typedef struct SDLHintNode {
    char *name;
    char *value;
    SDL_HintPriority priority;
    struct SDLHintNode *next;
} SDLHintNode;

static SDLHintNode *g_hints = NULL;
static pthread_mutex_t g_hints_mutex = PTHREAD_MUTEX_INITIALIZER;

int SDL_InitSubSystem(Uint32 flags) {
    if ((flags & SDL_INIT_VIDEO) && !(g_sdl_initialized_subsystems & SDL_INIT_VIDEO)) {
        if (SDL_RavynVideoInit() < 0) {
            return -1;
        }
    }
    g_sdl_initialized_subsystems |= flags;
    return 0;
}

int SDL_Init(Uint32 flags) {
    return SDL_InitSubSystem(flags);
}

void SDL_QuitSubSystem(Uint32 flags) {
    if ((flags & SDL_INIT_VIDEO) && (g_sdl_initialized_subsystems & SDL_INIT_VIDEO)) {
        SDL_RavynVideoQuit();
    }
    g_sdl_initialized_subsystems &= ~flags;
}

Uint32 SDL_WasInit(Uint32 flags) {
    if (flags == 0) {
        return g_sdl_initialized_subsystems;
    }
    return g_sdl_initialized_subsystems & flags;
}

void SDL_Quit(void) {
    SDL_QuitSubSystem(g_sdl_initialized_subsystems);
    g_sdl_initialized_subsystems = 0;
}

int SDL_SetError(SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    if (fmt) {
        va_list ap;
        va_start(ap, fmt);
        vsnprintf(g_sdl_error_buf, sizeof(g_sdl_error_buf), fmt, ap);
        va_end(ap);
    } else {
        g_sdl_error_buf[0] = '\0';
    }
    return -1;
}

const char *SDL_GetError(void) {
    return g_sdl_error_buf;
}

char *SDL_GetErrorMsg(char *errstr, int maxlen) {
    if (errstr && maxlen > 0) {
        snprintf(errstr, (size_t)maxlen, "%s", g_sdl_error_buf);
    }
    return errstr;
}

/* A line-per-call trace that survives a crash.
 *
 * stderr is block-buffered when launchd redirects it to a file, so the last
 * dozen messages before a fault are lost -- which is exactly the window a
 * crash needs to be diagnosable.  Each line here is opened, written and closed,
 * so whatever reached the disk is what actually executed. */
void SDL_RavynTrace(const char *fmt, ...) {
    /* Off unless asked for.  The per-present line would otherwise write a
     * line per frame for the life of the process; the window-creation lines
     * are what a launch failure needs, and they can be had on demand with
     * SDL_RAVYNOS_TRACE=1. */
    static int enabled = -1;
    if (enabled < 0) {
        const char *value = getenv("SDL_RAVYNOS_TRACE");
        enabled = (value != NULL && *value != '\0') ? 1 : 0;
    }
    if (!enabled) {
        return;
    }
    FILE *f = fopen("/var/log/sdl2-diag.log", "a");
    if (f == NULL) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

void SDL_ClearError(void) {
    g_sdl_error_buf[0] = '\0';
}

int SDL_Error(SDL_errorcode code) {
    switch (code) {
        case SDL_ENOMEM: return SDL_SetError("Out of memory");
        case SDL_EFREAD: return SDL_SetError("Error reading from datastream");
        case SDL_EFWRITE: return SDL_SetError("Error writing to datastream");
        case SDL_EFSEEK: return SDL_SetError("Error seeking in datastream");
        case SDL_UNSUPPORTED: return SDL_SetError("That operation is not supported");
        default: return SDL_SetError("Unknown SDL error");
    }
}

void SDL_GetVersion(SDL_version *ver) {
    if (ver) {
        ver->major = 2;
        ver->minor = 32;
        ver->patch = 10;
    }
}

const char *SDL_GetRevision(void) {
    return "SDL-2.32.10-ravynOS";
}

int SDL_GetRevisionNumber(void) {
    return 0;
}

const char *SDL_GetPlatform(void) {
    return "ravynOS";
}

/* Hints */
SDL_bool SDL_SetHintWithPriority(const char *name, const char *value, SDL_HintPriority priority) {
    if (!name) return SDL_FALSE;
    pthread_mutex_lock(&g_hints_mutex);
    SDLHintNode *curr = g_hints;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            if (priority < curr->priority) {
                pthread_mutex_unlock(&g_hints_mutex);
                return SDL_FALSE;
            }
            free(curr->value);
            curr->value = value ? strdup(value) : NULL;
            curr->priority = priority;
            pthread_mutex_unlock(&g_hints_mutex);
            return SDL_TRUE;
        }
        curr = curr->next;
    }
    SDLHintNode *node = (SDLHintNode *)calloc(1, sizeof(SDLHintNode));
    if (!node) {
        pthread_mutex_unlock(&g_hints_mutex);
        return SDL_FALSE;
    }
    node->name = strdup(name);
    node->value = value ? strdup(value) : NULL;
    node->priority = priority;
    node->next = g_hints;
    g_hints = node;
    pthread_mutex_unlock(&g_hints_mutex);
    return SDL_TRUE;
}

SDL_bool SDL_SetHint(const char *name, const char *value) {
    return SDL_SetHintWithPriority(name, value, SDL_HINT_NORMAL);
}

const char *SDL_GetHint(const char *name) {
    if (!name) return NULL;
    const char *env = getenv(name);
    if (env) return env;
    pthread_mutex_lock(&g_hints_mutex);
    SDLHintNode *curr = g_hints;
    while (curr) {
        if (strcmp(curr->name, name) == 0) {
            const char *v = curr->value;
            pthread_mutex_unlock(&g_hints_mutex);
            return v;
        }
        curr = curr->next;
    }
    pthread_mutex_unlock(&g_hints_mutex);
    return NULL;
}

SDL_bool SDL_GetHintBoolean(const char *name, SDL_bool default_value) {
    const char *hint = SDL_GetHint(name);
    if (!hint || !*hint) return default_value;
    if (strcasecmp(hint, "0") == 0 || strcasecmp(hint, "false") == 0) return SDL_FALSE;
    return SDL_TRUE;
}

SDL_bool SDL_ResetHint(const char *name) {
    if (!name) return SDL_FALSE;
    return SDL_SetHintWithPriority(name, NULL, SDL_HINT_OVERRIDE);
}

void SDL_ResetHints(void) {
    pthread_mutex_lock(&g_hints_mutex);
    SDLHintNode *curr = g_hints;
    while (curr) {
        SDLHintNode *next = curr->next;
        free(curr->name);
        free(curr->value);
        free(curr);
        curr = next;
    }
    g_hints = NULL;
    pthread_mutex_unlock(&g_hints_mutex);
}

void SDL_AddHintCallback(const char *name, SDL_HintCallback callback, void *userdata) {
    if (callback) {
        const char *val = SDL_GetHint(name);
        callback(userdata, name, val, val);
    }
}

void SDL_DelHintCallback(const char *name, SDL_HintCallback callback, void *userdata) {
    (void)name;
    (void)callback;
    (void)userdata;
}

void SDL_ClearHints(void) {
    SDL_ResetHints();
}

/* Logging */
void SDL_LogMessageV(int category, SDL_LogPriority priority, const char *fmt, va_list ap) {
    (void)category;
    const char *pstr = "INFO";
    switch (priority) {
        case SDL_LOG_PRIORITY_VERBOSE: pstr = "VERBOSE"; break;
        case SDL_LOG_PRIORITY_DEBUG:   pstr = "DEBUG"; break;
        case SDL_LOG_PRIORITY_INFO:    pstr = "INFO"; break;
        case SDL_LOG_PRIORITY_WARN:    pstr = "WARN"; break;
        case SDL_LOG_PRIORITY_ERROR:   pstr = "ERROR"; break;
        case SDL_LOG_PRIORITY_CRITICAL:pstr = "CRITICAL"; break;
        default: break;
    }
    fprintf(stderr, "[SDL2 %s] ", pstr);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
}

void SDL_LogMessage(int category, SDL_LogPriority priority, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(category, priority, fmt, ap);
    va_end(ap);
}

void SDL_Log(SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_INFO, fmt, ap);
    va_end(ap);
}

void SDL_LogVerbose(int category, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(category, SDL_LOG_PRIORITY_VERBOSE, fmt, ap);
    va_end(ap);
}

void SDL_LogDebug(int category, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(category, SDL_LOG_PRIORITY_DEBUG, fmt, ap);
    va_end(ap);
}

void SDL_LogInfo(int category, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(category, SDL_LOG_PRIORITY_INFO, fmt, ap);
    va_end(ap);
}

void SDL_LogWarn(int category, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(category, SDL_LOG_PRIORITY_WARN, fmt, ap);
    va_end(ap);
}

void SDL_LogError(int category, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(category, SDL_LOG_PRIORITY_ERROR, fmt, ap);
    va_end(ap);
}

void SDL_LogCritical(int category, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    SDL_LogMessageV(category, SDL_LOG_PRIORITY_CRITICAL, fmt, ap);
    va_end(ap);
}

void SDL_LogSetAllPriority(SDL_LogPriority priority) { (void)priority; }
void SDL_LogSetPriority(int category, SDL_LogPriority priority) { (void)category; (void)priority; }
SDL_LogPriority SDL_LogGetPriority(int category) { (void)category; return SDL_LOG_PRIORITY_INFO; }
void SDL_LogResetPriorities(void) {}
void SDL_LogGetOutputFunction(SDL_LogOutputFunction *callback, void **userdata) {
    if (callback) *callback = NULL;
    if (userdata) *userdata = NULL;
}
void SDL_LogSetOutputFunction(SDL_LogOutputFunction callback, void *userdata) {
    (void)callback; (void)userdata;
}

/* CPU & RAM info */
int SDL_GetCPUCount(void) {
    int count = 1;
    size_t len = sizeof(count);
    if (sysctlbyname("hw.ncpu", &count, &len, NULL, 0) != 0 || count < 1) {
        count = 1;
    }
    return count;
}

int SDL_GetCPUCacheLineSize(void) { return 64; }
SDL_bool SDL_HasRDTSC(void) { return SDL_TRUE; }
SDL_bool SDL_HasAltiVec(void) { return SDL_FALSE; }
SDL_bool SDL_HasMMX(void) { return SDL_TRUE; }
SDL_bool SDL_Has3DNow(void) { return SDL_FALSE; }
SDL_bool SDL_HasSSE(void) { return SDL_TRUE; }
SDL_bool SDL_HasSSE2(void) { return SDL_TRUE; }
SDL_bool SDL_HasSSE3(void) { return SDL_TRUE; }
SDL_bool SDL_HasSSE41(void) { return SDL_TRUE; }
SDL_bool SDL_HasSSE42(void) { return SDL_TRUE; }
SDL_bool SDL_HasAVX(void) { return SDL_FALSE; }
SDL_bool SDL_HasAVX2(void) { return SDL_FALSE; }
SDL_bool SDL_HasAVX512F(void) { return SDL_FALSE; }
SDL_bool SDL_HasARMSIMD(void) { return SDL_FALSE; }
SDL_bool SDL_HasNEON(void) { return SDL_FALSE; }
SDL_bool SDL_HasLSX(void) { return SDL_FALSE; }
SDL_bool SDL_HasLASX(void) { return SDL_FALSE; }

int SDL_GetSystemRAM(void) {
    uint64_t mem = 0;
    size_t len = sizeof(mem);
    if (sysctlbyname("hw.memsize", &mem, &len, NULL, 0) == 0 && mem > 0) {
        return (int)(mem / (1024ULL * 1024ULL));
    }
    return 2048;
}

size_t SDL_SIMDGetAlignment(void) { return 16; }
void *SDL_SIMDAlloc(const size_t len) {
    void *ptr = NULL;
    if (posix_memalign(&ptr, 16, len ? len : 16) != 0) return NULL;
    return ptr;
}
void *SDL_SIMDRealloc(void *mem, const size_t len) {
    return realloc(mem, len ? len : 16);
}
void SDL_SIMDFree(void *ptr) {
    free(ptr);
}

/* Power */
SDL_PowerState SDL_GetPowerInfo(int *seconds, int *percent) {
    if (seconds) *seconds = -1;
    if (percent) *percent = 100;
    return SDL_POWERSTATE_CHARGED;
}

/* Filesystem */
char *SDL_GetBasePath(void) {
    char buf[1024];
    uint32_t sz = sizeof(buf);
    if (_NSGetExecutablePath(buf, &sz) == 0) {
        char *slash = strrchr(buf, '/');
        if (slash) {
            *(slash + 1) = '\0';
            return SDL_strdup(buf);
        }
    }
    return SDL_strdup("/Applications/");
}

char *SDL_GetPrefPath(const char *org, const char *app) {
    char path[1024];
    const char *home = getenv("HOME");
    if (!home || !*home) home = "/tmp";
    snprintf(path, sizeof(path), "%s/.config/%s/%s/",
             home, org && *org ? org : "org", app && *app ? app : "app");
    /* Create directories */
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    return SDL_strdup(path);
}

/* MessageBox & URL */
int SDL_ShowSimpleMessageBox(Uint32 flags, const char *title, const char *message, SDL_Window *window) {
    (void)flags;
    (void)window;
    fprintf(stderr, "[SDL2 MessageBox] %s: %s\n", title ? title : "Alert", message ? message : "");
    return 0;
}

int SDL_ShowMessageBox(const SDL_MessageBoxData *messageboxdata, int *buttonid) {
    if (messageboxdata) {
        SDL_ShowSimpleMessageBox(messageboxdata->flags, messageboxdata->title, messageboxdata->message, messageboxdata->window);
    }
    if (buttonid) *buttonid = 0;
    return 0;
}

int SDL_OpenURL(const char *url) {
    (void)url;
    return 0;
}

/* Assertions */
SDL_AssertState SDL_ReportAssertion(SDL_AssertData *data, const char *func, const char *file, int line) {
    fprintf(stderr, "[SDL2 ASSERT] %s (%s:%d in %s)\n",
            data ? data->condition : "?", file ? file : "?", line, func ? func : "?");
    return SDL_ASSERTION_IGNORE;
}
void SDL_SetAssertionHandler(SDL_AssertionHandler handler, void *userdata) { (void)handler; (void)userdata; }
SDL_AssertionHandler SDL_GetDefaultAssertionHandler(void) { return NULL; }
SDL_AssertionHandler SDL_GetAssertionHandler(void **puserdata) { if (puserdata) *puserdata = NULL; return NULL; }
const SDL_AssertData *SDL_GetAssertionReport(void) { return NULL; }
void SDL_ResetAssertionReport(void) {}

/* Standard library wrappers */
void *SDL_malloc(size_t size) { return malloc(size ? size : 1); }
void *SDL_calloc(size_t nmemb, size_t size) { return calloc(nmemb ? nmemb : 1, size ? size : 1); }
void *SDL_realloc(void *mem, size_t size) { return realloc(mem, size ? size : 1); }
void SDL_free(void *mem) { free(mem); }

char *SDL_getenv(const char *name) { return getenv(name); }
int SDL_setenv(const char *name, const char *value, int overwrite) { return setenv(name, value, overwrite); }

void *SDL_memset(SDL_OUT_BYTECAP(len) void *dst, int c, size_t len) { return memset(dst, c, len); }
void *SDL_memcpy(SDL_OUT_BYTECAP(len) void *dst, SDL_IN_BYTECAP(len) const void *src, size_t len) { return memcpy(dst, src, len); }
void *SDL_memmove(SDL_OUT_BYTECAP(len) void *dst, SDL_IN_BYTECAP(len) const void *src, size_t len) { return memmove(dst, src, len); }
int SDL_memcmp(const void *s1, const void *s2, size_t len) { return memcmp(s1, s2, len); }

size_t SDL_strlen(const char *str) { return str ? strlen(str) : 0; }
size_t SDL_strlcpy(SDL_OUT_Z_CAP(maxlen) char *dst, const char *src, size_t maxlen) { return strlcpy(dst, src ? src : "", maxlen); }
size_t SDL_strlcat(SDL_INOUT_Z_CAP(maxlen) char *dst, const char *src, size_t maxlen) { return strlcat(dst, src ? src : "", maxlen); }
char *SDL_strdup(const char *str) { return strdup(str ? str : ""); }
char *SDL_strchr(const char *str, int c) { return str ? strchr(str, c) : NULL; }
char *SDL_strrchr(const char *str, int c) { return str ? strrchr(str, c) : NULL; }
char *SDL_strstr(const char *haystack, const char *needle) { return (haystack && needle) ? strstr(haystack, needle) : NULL; }
int SDL_strcmp(const char *str1, const char *str2) { return strcmp(str1 ? str1 : "", str2 ? str2 : ""); }
int SDL_strncmp(const char *str1, const char *str2, size_t maxlen) { return strncmp(str1 ? str1 : "", str2 ? str2 : "", maxlen); }
int SDL_strcasecmp(const char *str1, const char *str2) { return strcasecmp(str1 ? str1 : "", str2 ? str2 : ""); }
int SDL_strncasecmp(const char *str1, const char *str2, size_t len) { return strncasecmp(str1 ? str1 : "", str2 ? str2 : "", len); }

int SDL_atoi(const char *str) { return str ? atoi(str) : 0; }
double SDL_atof(const char *str) { return str ? atof(str) : 0.0; }
long SDL_strtol(const char *str, char **endp, int base) { return strtol(str ? str : "0", endp, base); }
unsigned long SDL_strtoul(const char *str, char **endp, int base) { return strtoul(str ? str : "0", endp, base); }
Sint64 SDL_strtoll(const char *str, char **endp, int base) { return strtoll(str ? str : "0", endp, base); }
Uint64 SDL_strtoull(const char *str, char **endp, int base) { return strtoull(str ? str : "0", endp, base); }
double SDL_strtod(const char *str, char **endp) { return strtod(str ? str : "0", endp); }

int SDL_snprintf(SDL_OUT_Z_CAP(maxlen) char *text, size_t maxlen, SDL_PRINTF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsnprintf(text, maxlen, fmt, ap);
    va_end(ap);
    return r;
}

int SDL_vsnprintf(SDL_OUT_Z_CAP(maxlen) char *text, size_t maxlen, const char *fmt, va_list ap) {
    return vsnprintf(text, maxlen, fmt, ap);
}

int SDL_sscanf(const char *text, SDL_SCANF_FORMAT_STRING const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = vsscanf(text, fmt, ap);
    va_end(ap);
    return r;
}

int SDL_abs(int x) { return abs(x); }
double SDL_acos(double x) { return acos(x); }
float SDL_acosf(float x) { return acosf(x); }
double SDL_asin(double x) { return asin(x); }
float SDL_asinf(float x) { return asinf(x); }
double SDL_atan(double x) { return atan(x); }
float SDL_atanf(float x) { return atanf(x); }
double SDL_atan2(double y, double x) { return atan2(y, x); }
float SDL_atan2f(float y, float x) { return atan2f(y, x); }
double SDL_ceil(double x) { return ceil(x); }
float SDL_ceilf(float x) { return ceilf(x); }
double SDL_copysign(double x, double y) { return copysign(x, y); }
float SDL_copysignf(float x, float y) { return (float)copysign((double)x, (double)y); }
double SDL_cos(double x) { return cos(x); }
float SDL_cosf(float x) { return cosf(x); }
double SDL_exp(double x) { return exp(x); }
float SDL_expf(float x) { return expf(x); }
double SDL_fabs(double x) { return fabs(x); }
float SDL_fabsf(float x) { return fabsf(x); }
double SDL_floor(double x) { return floor(x); }
float SDL_floorf(float x) { return floorf(x); }
double SDL_fmod(double x, double y) { return fmod(x, y); }
float SDL_fmodf(float x, float y) { return fmodf(x, y); }
double SDL_log(double x) { return log(x); }
float SDL_logf(float x) { return logf(x); }
double SDL_log10(double x) { return log10(x); }
float SDL_log10f(float x) { return log10f(x); }
double SDL_pow(double x, double y) { return pow(x, y); }
float SDL_powf(float x, float y) { return powf(x, y); }
double SDL_round(double x) { return round(x); }
float SDL_roundf(float x) { return roundf(x); }
long SDL_lround(double x) { return lround(x); }
long SDL_lroundf(float x) { return lroundf(x); }
double SDL_scalbn(double x, int n) { return scalbn(x, n); }
float SDL_scalbnf(float x, int n) { return scalbnf(x, n); }
double SDL_sin(double x) { return sin(x); }
float SDL_sinf(float x) { return sinf(x); }
double SDL_sqrt(double x) { return sqrt(x); }
float SDL_sqrtf(float x) { return sqrtf(x); }
double SDL_tan(double x) { return tan(x); }
float SDL_tanf(float x) { return tanf(x); }
double SDL_trunc(double x) { return trunc(x); }
float SDL_truncf(float x) { return truncf(x); }

void SDL_qsort(void *base, size_t nmemb, size_t size, int (*compare)(const void *, const void *)) {
    qsort(base, nmemb, size, compare);
}
void *SDL_bsearch(const void *key, const void *base, size_t nmemb, size_t size, int (*compare)(const void *, const void *)) {
    return bsearch(key, base, nmemb, size, compare);
}
