/*
 * SDL2 Timer, Thread, Mutex/Semaphore/Cond, RWops, Dynamic Loading, and
 * Dummy Audio backend implementation for ravynOS.
 */

#include "SDL_ravynos_internal.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <dlfcn.h>
#include <mach/mach_time.h>

/* ------------------------------------------------------------------ */
/* Timers                                                             */
/* ------------------------------------------------------------------ */

static Uint64 g_start_nanos = 0;

/* clock_gettime(CLOCK_MONOTONIC) rather than mach_absolute_time plus
 * mach_timebase_info: the conversion is integer-exact on this platform, while
 * the mach timebase has to be queried and its numer/denom divided -- and a
 * failed query leaves denom at zero, turning every timestamp into a division
 * by zero.  nanosleep in this libSystem already takes the clock_gettime path,
 * so this matches what the rest of the system does. */
static Uint64 now_nanos(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
            return 0;
        }
    }
    return (Uint64)ts.tv_sec * 1000000000ULL + (Uint64)ts.tv_nsec;
}

static void ensure_timebase(void) {
    if (g_start_nanos == 0) {
        g_start_nanos = now_nanos();
    }
}

Uint32 SDL_GetTicks(void) {
    ensure_timebase();
    return (Uint32)((now_nanos() - g_start_nanos) / 1000000ULL);
}

Uint64 SDL_GetTicks64(void) {
    ensure_timebase();
    return (now_nanos() - g_start_nanos) / 1000000ULL;
}

Uint64 SDL_GetPerformanceCounter(void) {
    return now_nanos();
}

Uint64 SDL_GetPerformanceFrequency(void) {
    return 1000000000ULL;
}

void SDL_Delay(Uint32 ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

void SDL_DelayNS(Uint64 ns) {
    struct timespec ts;
    ts.tv_sec = (time_t)(ns / 1000000000ULL);
    ts.tv_nsec = (long)(ns % 1000000000ULL);
    nanosleep(&ts, NULL);
}

void SDL_DelayPrecise(Uint64 ns) {
    SDL_DelayNS(ns);
}

typedef struct RavynTimer {
    SDL_TimerID id;
    Uint32 interval;
    SDL_TimerCallback callback;
    void *param;
    pthread_t thread;
    SDL_bool active;
    SDL_bool running;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    struct RavynTimer *next;
} RavynTimer;

static RavynTimer *g_timers = NULL;
static SDL_TimerID g_next_timer_id = 1;
static pthread_mutex_t g_timers_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t g_timebase_once = PTHREAD_ONCE_INIT;

static void timebase_init(void) { ensure_timebase(); }

static void *timer_thread_main(void *arg) {
    RavynTimer *t = (RavynTimer *)arg;
    pthread_mutex_lock(&t->lock);
    while (t->running) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += t->interval / 1000;
        ts.tv_nsec += (long)(t->interval % 1000) * 1000000L;
        if (ts.tv_nsec >= 1000000000L) {
            ts.tv_sec++;
            ts.tv_nsec -= 1000000000L;
        }
        int rc = 0;
        while (t->running && rc == 0) {
            rc = pthread_cond_timedwait(&t->cond, &t->lock, &ts);
        }
        if (!t->running) break;
        pthread_mutex_unlock(&t->lock);
        Uint32 next = t->callback(t->interval, t->param);
        pthread_mutex_lock(&t->lock);
        if (next == 0) {
            t->active = SDL_FALSE;
            break;
        }
        t->interval = next;
    }
    pthread_mutex_unlock(&t->lock);
    return NULL;
}

SDL_TimerID SDL_AddTimer(Uint32 interval, SDL_TimerCallback callback, void *param) {
    if (!callback || interval == 0) return 0;
    pthread_once(&g_timebase_once, timebase_init);
    RavynTimer *t = (RavynTimer *)calloc(1, sizeof(RavynTimer));
    if (!t) return 0;
    t->interval = interval;
    t->callback = callback;
    t->param = param;
    t->active = SDL_TRUE;
    t->running = SDL_TRUE;
    pthread_mutex_init(&t->lock, NULL);
    pthread_cond_init(&t->cond, NULL);

    pthread_mutex_lock(&g_timers_lock);
    t->id = g_next_timer_id++;
    t->next = g_timers;
    g_timers = t;
    pthread_mutex_unlock(&g_timers_lock);

    if (pthread_create(&t->thread, NULL, timer_thread_main, t) != 0) {
        pthread_mutex_lock(&g_timers_lock);
        RavynTimer **pp = &g_timers;
        while (*pp) {
            if (*pp == t) { *pp = t->next; break; }
            pp = &((*pp)->next);
        }
        pthread_mutex_unlock(&g_timers_lock);
        free(t);
        return 0;
    }
    return t->id;
}

SDL_bool SDL_RemoveTimer(SDL_TimerID id) {
    pthread_mutex_lock(&g_timers_lock);
    RavynTimer *t = g_timers;
    RavynTimer *found = NULL;
    while (t) {
        if (t->id == id) { found = t; break; }
        t = t->next;
    }
    if (!found) {
        pthread_mutex_unlock(&g_timers_lock);
        return SDL_FALSE;
    }
    pthread_mutex_lock(&found->lock);
    found->running = SDL_FALSE;
    pthread_cond_broadcast(&found->cond);
    pthread_mutex_unlock(&found->lock);
    pthread_mutex_unlock(&g_timers_lock);
    /* Thread self-cleans nothing; leave the record so the id stays unique. */
    return SDL_TRUE;
}

/* ------------------------------------------------------------------ */
/* Threads                                                            */
/* ------------------------------------------------------------------ */

struct SDL_Thread {
    pthread_t thread;
    SDL_ThreadFunction fn;
    void *data;
    char *name;
    int retval;
    SDL_bool finished;
    SDL_sem *wait_sem;
    struct SDL_Thread *next;
};

static struct SDL_Thread *g_threads = NULL;
static pthread_mutex_t g_threads_lock = PTHREAD_MUTEX_INITIALIZER;

static void *thread_trampoline(void *arg) {
    struct SDL_Thread *t = (struct SDL_Thread *)arg;
    t->retval = t->fn(t->data);
    t->finished = SDL_TRUE;
    if (t->wait_sem) {
        SDL_SemPost(t->wait_sem);
    }
    return NULL;
}

SDL_Thread *SDL_CreateThread(SDL_ThreadFunction fn, const char *name, void *data) {
    if (!fn) return NULL;
    struct SDL_Thread *t = (struct SDL_Thread *)calloc(1, sizeof(struct SDL_Thread));
    if (!t) return NULL;
    t->fn = fn;
    t->data = data;
    t->name = strdup(name ? name : "SDL thread");
    t->wait_sem = SDL_CreateSemaphore(0);
    if (pthread_create(&t->thread, NULL, thread_trampoline, t) != 0) {
        SDL_DestroySemaphore(t->wait_sem);
        free(t->name);
        free(t);
        return NULL;
    }
    pthread_mutex_lock(&g_threads_lock);
    t->next = g_threads;
    g_threads = t;
    pthread_mutex_unlock(&g_threads_lock);
    return (SDL_Thread *)t;
}

SDL_Thread *SDL_CreateThreadWithStackSize(SDL_ThreadFunction fn, const char *name,
                                          const size_t stacksize, void *data) {
    (void)stacksize;
    return SDL_CreateThread(fn, name, data);
}

void SDL_WaitThread(SDL_Thread *thread, int *status) {
    struct SDL_Thread *t = (struct SDL_Thread *)thread;
    if (!t) return;
    pthread_join(t->thread, NULL);
    if (status) *status = t->retval;
    if (t->wait_sem) SDL_DestroySemaphore(t->wait_sem);
    pthread_mutex_lock(&g_threads_lock);
    struct SDL_Thread **pp = &g_threads;
    while (*pp) {
        if (*pp == t) { *pp = t->next; break; }
        pp = &((*pp)->next);
    }
    pthread_mutex_unlock(&g_threads_lock);
    free(t->name);
    free(t);
}

void SDL_DetachThread(SDL_Thread *thread) {
    struct SDL_Thread *t = (struct SDL_Thread *)thread;
    if (!t) return;
    pthread_detach(t->thread);
    if (t->wait_sem) SDL_DestroySemaphore(t->wait_sem);
    pthread_mutex_lock(&g_threads_lock);
    struct SDL_Thread **pp = &g_threads;
    while (*pp) {
        if (*pp == t) { *pp = t->next; break; }
        pp = &((*pp)->next);
    }
    pthread_mutex_unlock(&g_threads_lock);
    free(t->name);
    free(t);
}

SDL_threadID SDL_ThreadID(void) {
    return (SDL_threadID)pthread_self();
}

SDL_threadID SDL_GetThreadID(SDL_Thread *thread) {
    struct SDL_Thread *t = (struct SDL_Thread *)thread;
    return t ? (SDL_threadID)t->thread : 0;
}

const char *SDL_GetThreadName(SDL_Thread *thread) {
    struct SDL_Thread *t = (struct SDL_Thread *)thread;
    return t ? t->name : "";
}

int SDL_SetThreadPriority(SDL_ThreadPriority priority) {
    (void)priority;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Mutexes, semaphores, conditions, TLS                                */
/* ------------------------------------------------------------------ */

SDL_mutex *SDL_CreateMutex(void) {
    pthread_mutex_t *m = (pthread_mutex_t *)calloc(1, sizeof(pthread_mutex_t));
    if (m) pthread_mutex_init(m, NULL);
    return (SDL_mutex *)m;
}

int SDL_LockMutex(SDL_mutex *mutex) SDL_NO_THREAD_SAFETY_ANALYSIS {
    return mutex ? pthread_mutex_lock((pthread_mutex_t *)mutex) : -1;
}

int SDL_TryLockMutex(SDL_mutex *mutex) {
    return mutex ? pthread_mutex_trylock((pthread_mutex_t *)mutex) : -1;
}

int SDL_UnlockMutex(SDL_mutex *mutex) SDL_NO_THREAD_SAFETY_ANALYSIS {
    return mutex ? pthread_mutex_unlock((pthread_mutex_t *)mutex) : -1;
}

void SDL_DestroyMutex(SDL_mutex *mutex) {
    if (!mutex) return;
    pthread_mutex_destroy((pthread_mutex_t *)mutex);
    free(mutex);
}

SDL_sem *SDL_CreateSemaphore(Uint32 initial_value) {
    pthread_mutex_t *m = (pthread_mutex_t *)calloc(1, sizeof(pthread_mutex_t));
    pthread_cond_t *c = (pthread_cond_t *)calloc(1, sizeof(pthread_cond_t));
    Uint32 *count = (Uint32 *)calloc(1, sizeof(Uint32));
    if (!m || !c || !count) {
        free(m); free(c); free(count);
        return NULL;
    }
    pthread_mutex_init(m, NULL);
    pthread_cond_init(c, NULL);
    *count = initial_value;
    void **bundle = (void **)calloc(3, sizeof(void *));
    if (!bundle) {
        free(m); free(c); free(count);
        return NULL;
    }
    bundle[0] = m; bundle[1] = c; bundle[2] = count;
    return (SDL_sem *)bundle;
}

int SDL_SemWait(SDL_sem *sem) {
    if (!sem) return -1;
    void **b = (void **)sem;
    pthread_mutex_t *m = (pthread_mutex_t *)b[0];
    pthread_cond_t *c = (pthread_cond_t *)b[1];
    Uint32 *count = (Uint32 *)b[2];
    pthread_mutex_lock(m);
    while (*count == 0) pthread_cond_wait(c, m);
    (*count)--;
    pthread_mutex_unlock(m);
    return 0;
}

int SDL_SemTryWait(SDL_sem *sem) {
    if (!sem) return -1;
    void **b = (void **)sem;
    pthread_mutex_t *m = (pthread_mutex_t *)b[0];
    Uint32 *count = (Uint32 *)b[2];
    pthread_mutex_lock(m);
    int rc = -1;
    if (*count > 0) {
        (*count)--;
        rc = 0;
    }
    pthread_mutex_unlock(m);
    return rc;
}

int SDL_SemWaitTimeout(SDL_sem *sem, Uint32 timeout) {
    if (!sem) return -1;
    void **b = (void **)sem;
    pthread_mutex_t *m = (pthread_mutex_t *)b[0];
    pthread_cond_t *c = (pthread_cond_t *)b[1];
    Uint32 *count = (Uint32 *)b[2];
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += timeout / 1000;
    ts.tv_nsec += (long)(timeout % 1000) * 1000000L;
    if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }

    pthread_mutex_lock(m);
    int rc = 0;
    while (*count == 0) {
        if (pthread_cond_timedwait(c, m, &ts) != 0) { rc = -1; break; }
    }
    if (rc == 0) (*count)--;
    pthread_mutex_unlock(m);
    return rc;
}

int SDL_SemPost(SDL_sem *sem) {
    if (!sem) return -1;
    void **b = (void **)sem;
    pthread_mutex_t *m = (pthread_mutex_t *)b[0];
    pthread_cond_t *c = (pthread_cond_t *)b[1];
    Uint32 *count = (Uint32 *)b[2];
    pthread_mutex_lock(m);
    (*count)++;
    pthread_cond_signal(c);
    pthread_mutex_unlock(m);
    return 0;
}

Uint32 SDL_SemValue(SDL_sem *sem) {
    if (!sem) return 0;
    void **b = (void **)sem;
    Uint32 v = *(Uint32 *)b[2];
    return v;
}

void SDL_DestroySemaphore(SDL_sem *sem) {
    if (!sem) return;
    void **b = (void **)sem;
    pthread_mutex_destroy((pthread_mutex_t *)b[0]);
    pthread_cond_destroy((pthread_cond_t *)b[1]);
    free(b[0]); free(b[1]); free(b[2]); free(b);
}

SDL_cond *SDL_CreateCond(void) {
    pthread_cond_t *c = (pthread_cond_t *)calloc(1, sizeof(pthread_cond_t));
    if (c) pthread_cond_init(c, NULL);
    return (SDL_cond *)c;
}

int SDL_CondSignal(SDL_cond *cond) {
    return cond ? pthread_cond_signal((pthread_cond_t *)cond) : -1;
}

int SDL_CondBroadcast(SDL_cond *cond) {
    return cond ? pthread_cond_broadcast((pthread_cond_t *)cond) : -1;
}

int SDL_CondWait(SDL_cond *cond, SDL_mutex *mutex) {
    if (!cond || !mutex) return -1;
    return pthread_cond_wait((pthread_cond_t *)cond, (pthread_mutex_t *)mutex);
}

int SDL_CondWaitTimeout(SDL_cond *cond, SDL_mutex *mutex, Uint32 ms) {
    if (!cond || !mutex) return -1;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += ms / 1000;
    ts.tv_nsec += (long)(ms % 1000) * 1000000L;
    if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
    return pthread_cond_timedwait((pthread_cond_t *)cond, (pthread_mutex_t *)mutex, &ts);
}

void SDL_DestroyCond(SDL_cond *cond) {
    if (!cond) return;
    pthread_cond_destroy((pthread_cond_t *)cond);
    free(cond);
}

SDL_TLSID SDL_TLSCreate(void) {
    pthread_key_t *key = (pthread_key_t *)calloc(1, sizeof(pthread_key_t));
    if (!key) return 0;
    if (pthread_key_create(key, NULL) != 0) {
        free(key);
        return 0;
    }
    return (SDL_TLSID)((uintptr_t)key);
}

void *SDL_TLSGet(SDL_TLSID id) {
    if (!id) return NULL;
    pthread_key_t *key = (pthread_key_t *)(uintptr_t)id;
    return pthread_getspecific(*key);
}

int SDL_TLSSet(SDL_TLSID id, const void *value, void (*destructor)(void *)) {
    (void)destructor;
    if (!id) return -1;
    pthread_key_t *key = (pthread_key_t *)(uintptr_t)id;
    return pthread_setspecific(*key, value);
}

/* ------------------------------------------------------------------ */
/* RWops                                                              */
/* ------------------------------------------------------------------ */

typedef struct RavynRWops {
    SDL_RWops ops;
    FILE *fp;
    Uint8 *mem;
    size_t mem_size;
    size_t mem_pos;
    SDL_bool is_mem;
    SDL_bool owns_mem;
} RavynRWops;

static Sint64 rw_size(SDL_RWops *context) {
    RavynRWops *r = (RavynRWops *)context;
    if (!r) return -1;
    if (r->is_mem) return (Sint64)r->mem_size;
    if (!r->fp) return -1;
    long cur = ftell(r->fp);
    fseek(r->fp, 0, SEEK_END);
    long end = ftell(r->fp);
    fseek(r->fp, cur, SEEK_SET);
    return (Sint64)end;
}

static Sint64 rw_seek(SDL_RWops *context, Sint64 offset, int whence) {
    RavynRWops *r = (RavynRWops *)context;
    if (!r) return -1;
    if (r->is_mem) {
        Sint64 base = 0;
        if (whence == RW_SEEK_CUR) base = (Sint64)r->mem_pos;
        else if (whence == RW_SEEK_END) base = (Sint64)r->mem_size;
        Sint64 pos = base + offset;
        if (pos < 0 || (size_t)pos > r->mem_size) return -1;
        r->mem_pos = (size_t)pos;
        return pos;
    }
    if (!r->fp) return -1;
    int w = (whence == RW_SEEK_SET) ? SEEK_SET : (whence == RW_SEEK_CUR) ? SEEK_CUR : SEEK_END;
    if (fseek(r->fp, (long)offset, w) != 0) return -1;
    return (Sint64)ftell(r->fp);
}

static Sint64 rw_tell(SDL_RWops *context) {
    return rw_seek(context, 0, RW_SEEK_CUR);
}

static size_t rw_read(SDL_RWops *context, void *ptr, size_t size, size_t nmemb) {
    RavynRWops *r = (RavynRWops *)context;
    if (!r || !ptr) return 0;
    if (r->is_mem) {
        size_t bytes = size * nmemb;
        size_t avail = (r->mem_pos < r->mem_size) ? (r->mem_size - r->mem_pos) : 0;
        if (bytes > avail) bytes = avail;
        memcpy(ptr, r->mem + r->mem_pos, bytes);
        r->mem_pos += bytes;
        return size ? bytes / size : 0;
    }
    if (!r->fp) return 0;
    return fread(ptr, size, nmemb, r->fp);
}

static size_t rw_write(SDL_RWops *context, const void *ptr, size_t size, size_t nmemb) {
    RavynRWops *r = (RavynRWops *)context;
    if (!r || !ptr) return 0;
    if (r->is_mem) {
        size_t bytes = size * nmemb;
        if (r->mem_pos + bytes > r->mem_size) {
            size_t new_size = r->mem_pos + bytes;
            Uint8 *nb = (Uint8 *)realloc(r->mem, new_size);
            if (!nb) return 0;
            r->mem = nb;
            r->mem_size = new_size;
            r->owns_mem = SDL_TRUE;
        }
        memcpy(r->mem + r->mem_pos, ptr, bytes);
        r->mem_pos += bytes;
        return nmemb;
    }
    if (!r->fp) return 0;
    return fwrite(ptr, size, nmemb, r->fp);
}

static int rw_close(SDL_RWops *context) {
    RavynRWops *r = (RavynRWops *)context;
    if (!r) return -1;
    if (r->fp) {
        fclose(r->fp);
        r->fp = NULL;
    }
    if (r->is_mem && r->owns_mem) {
        free(r->mem);
    }
    free(r);
    return 0;
}

static RavynRWops *alloc_rwops(void) {
    RavynRWops *r = (RavynRWops *)calloc(1, sizeof(RavynRWops));
    if (!r) return NULL;
    r->ops.size = rw_size;
    r->ops.seek = rw_seek;
    r->ops.read = rw_read;
    r->ops.write = rw_write;
    r->ops.close = rw_close;
    return r;
}

SDL_RWops *SDL_RWFromFile(const char *file, const char *mode) {
    if (!file || !mode) return NULL;
    RavynRWops *r = alloc_rwops();
    if (!r) return NULL;
    r->fp = fopen(file, mode);
    if (!r->fp) {
        free(r);
        SDL_SetError("Couldn't open %s", file);
        return NULL;
    }
    return (SDL_RWops *)r;
}

SDL_RWops *SDL_RWFromFP(FILE *fp, SDL_bool autoclose) {
    (void)autoclose;
    RavynRWops *r = alloc_rwops();
    if (!r) return NULL;
    r->fp = fp;
    return (SDL_RWops *)r;
}

SDL_RWops *SDL_RWFromMem(void *mem, int size) {
    if (!mem || size < 0) return NULL;
    RavynRWops *r = alloc_rwops();
    if (!r) return NULL;
    r->is_mem = SDL_TRUE;
    r->mem = (Uint8 *)mem;
    r->mem_size = (size_t)size;
    return (SDL_RWops *)r;
}

SDL_RWops *SDL_RWFromConstMem(const void *mem, int size) {
    return SDL_RWFromMem((void *)mem, size);
}

SDL_RWops *SDL_AllocRW(void) {
    /* A zeroed RWops with working function pointers but no backing store. */
    return (SDL_RWops *)alloc_rwops();
}

void SDL_FreeRW(SDL_RWops *area) {
    if (area) free(area);
}

Sint64 SDL_RWsize(SDL_RWops *context) { return rw_size(context); }
Sint64 SDL_RWseek(SDL_RWops *context, Sint64 offset, int whence) { return rw_seek(context, offset, whence); }
Sint64 SDL_RWtell(SDL_RWops *context) { return rw_tell(context); }
size_t SDL_RWread(SDL_RWops *context, void *ptr, size_t size, size_t maxnum) { return rw_read(context, ptr, size, maxnum); }
size_t SDL_RWwrite(SDL_RWops *context, const void *ptr, size_t size, size_t num) { return rw_write(context, ptr, size, num); }
int SDL_RWclose(SDL_RWops *context) { return rw_close(context); }

void *SDL_LoadFile_RW(SDL_RWops *src, size_t *datasize, int freesrc) {
    if (!src) return NULL;
    size_t sz = (size_t)rw_size(src);
    void *buf = malloc(sz + 1);
    if (!buf) {
        if (freesrc) SDL_RWclose(src);
        return NULL;
    }
    size_t got = rw_read(src, buf, 1, sz);
    ((char *)buf)[got] = '\0';
    if (datasize) *datasize = got;
    if (freesrc) SDL_RWclose(src);
    return buf;
}

void *SDL_LoadFile(const char *file, size_t *datasize) {
    SDL_RWops *rw = SDL_RWFromFile(file, "rb");
    if (!rw) return NULL;
    return SDL_LoadFile_RW(rw, datasize, 1);
}

Uint8 SDL_ReadU8(SDL_RWops *src) { Uint8 v = 0; SDL_RWread(src, &v, 1, 1); return v; }
Uint16 SDL_ReadLE16(SDL_RWops *src) { Uint16 v = 0; SDL_RWread(src, &v, 2, 1); return v; }
Uint16 SDL_ReadBE16(SDL_RWops *src) { Uint16 v = 0; Uint8 b[2] = {0}; SDL_RWread(src, b, 2, 1); v = (Uint16)((b[0] << 8) | b[1]); return v; }
Uint32 SDL_ReadLE32(SDL_RWops *src) { Uint32 v = 0; SDL_RWread(src, &v, 4, 1); return v; }
Uint32 SDL_ReadBE32(SDL_RWops *src) { Uint8 b[4] = {0}; SDL_RWread(src, b, 4, 1); return ((Uint32)b[0] << 24) | ((Uint32)b[1] << 16) | ((Uint32)b[2] << 8) | b[3]; }
Uint64 SDL_ReadLE64(SDL_RWops *src) { Uint64 v = 0; SDL_RWread(src, &v, 8, 1); return v; }
Uint64 SDL_ReadBE64(SDL_RWops *src) {
    Uint8 b[8] = {0};
    SDL_RWread(src, b, 8, 1);
    Uint64 v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | b[i];
    return v;
}
size_t SDL_WriteU8(SDL_RWops *dst, Uint8 value) { return SDL_RWwrite(dst, &value, 1, 1); }
size_t SDL_WriteLE16(SDL_RWops *dst, Uint16 value) { return SDL_RWwrite(dst, &value, 2, 1); }
size_t SDL_WriteBE16(SDL_RWops *dst, Uint16 value) {
    Uint8 b[2] = { (Uint8)(value >> 8), (Uint8)value };
    return SDL_RWwrite(dst, b, 2, 1);
}
size_t SDL_WriteLE32(SDL_RWops *dst, Uint32 value) { return SDL_RWwrite(dst, &value, 4, 1); }
size_t SDL_WriteBE32(SDL_RWops *dst, Uint32 value) {
    Uint8 b[4] = { (Uint8)(value >> 24), (Uint8)(value >> 16), (Uint8)(value >> 8), (Uint8)value };
    return SDL_RWwrite(dst, b, 4, 1);
}
size_t SDL_WriteLE64(SDL_RWops *dst, Uint64 value) { return SDL_RWwrite(dst, &value, 8, 1); }
size_t SDL_WriteBE64(SDL_RWops *dst, Uint64 value) {
    Uint8 b[8];
    for (int i = 0; i < 8; i++) b[i] = (Uint8)(value >> (56 - 8 * i));
    return SDL_RWwrite(dst, b, 8, 1);
}

/* ------------------------------------------------------------------ */
/* Dynamic loading                                                    */
/* ------------------------------------------------------------------ */

void *SDL_LoadObject(const char *sofile) {
    if (!sofile) return NULL;
    void *h = dlopen(sofile, RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        SDL_SetError("Failed loading %s: %s", sofile, dlerror());
    }
    return h;
}

void *SDL_LoadFunction(void *handle, const char *name) {
    if (!handle || !name) return NULL;
    void *sym = dlsym(handle, name);
    if (!sym) {
        SDL_SetError("Failed loading %s: %s", name, dlerror());
    }
    return sym;
}

void SDL_UnloadObject(void *handle) {
    if (handle) dlclose(handle);
}

/* ------------------------------------------------------------------ */
/* Dummy audio backend                                                */
/* ------------------------------------------------------------------ */

#define RAVYN_MAX_AUDIO_DEVICES 8

typedef struct RavynAudioDevice {
    SDL_AudioSpec spec;
    SDL_AudioCallback callback;
    void *userdata;
    SDL_bool opened;
    SDL_bool paused;
    Uint8 *queue;
    size_t queue_size;
    size_t queue_capacity;
    pthread_t thread;
    SDL_bool thread_running;
    pthread_mutex_t lock;
} RavynAudioDevice;

static RavynAudioDevice g_audio_devices[RAVYN_MAX_AUDIO_DEVICES];
static int g_audio_device_count = 0;
static pthread_mutex_t g_audio_lock = PTHREAD_MUTEX_INITIALIZER;

static void *audio_thread_main(void *arg) {
    RavynAudioDevice *dev = (RavynAudioDevice *)arg;
    Uint32 frame_bytes = (Uint32)(dev->spec.channels * (dev->spec.format == AUDIO_F32 ? 4 : 2));
    Uint32 buffer_bytes = dev->spec.samples * frame_bytes;
    if (buffer_bytes == 0) buffer_bytes = 4096;
    Uint8 *buffer = (Uint8 *)calloc(1, buffer_bytes);
    if (!buffer) return NULL;
    double period = (double)dev->spec.samples / (double)dev->spec.freq;
    if (period <= 0.0) period = 1.0 / 60.0;

    while (dev->thread_running) {
        if (!dev->paused && dev->callback) {
            dev->callback(dev->userdata, buffer, (int)buffer_bytes);
        }
        struct timespec ts;
        ts.tv_sec = (time_t)period;
        ts.tv_nsec = (long)((period - (double)ts.tv_sec) * 1e9);
        nanosleep(&ts, NULL);
    }
    free(buffer);
    return NULL;
}

int SDL_GetNumAudioDrivers(void) { return 1; }
const char *SDL_GetAudioDriver(int index) { return (index == 0) ? "ravynos" : NULL; }
const char *SDL_GetCurrentAudioDriver(void) { return "ravynos"; }
int SDL_AudioInit(const char *driver_name) { (void)driver_name; return 0; }
void SDL_AudioQuit(void) {}

int SDL_GetNumAudioDevices(int iscapture) {
    (void)iscapture;
    return 1;
}

const char *SDL_GetAudioDeviceName(int index, int iscapture) {
    (void)iscapture;
    return (index == 0) ? "ravynOS Default Audio" : NULL;
}

int SDL_GetAudioDeviceSpec(int index, int iscapture, SDL_AudioSpec *spec) {
    (void)iscapture;
    if (index != 0 || !spec) return -1;
    memset(spec, 0, sizeof(*spec));
    spec->freq = 44100;
    spec->format = AUDIO_S16LSB;
    spec->channels = 2;
    spec->samples = 1024;
    return 0;
}

int SDL_GetDefaultAudioInfo(char **name, SDL_AudioSpec *spec, int iscapture) {
    (void)iscapture;
    if (name) *name = strdup("ravynOS Default Audio");
    if (spec) {
        memset(spec, 0, sizeof(*spec));
        spec->freq = 44100;
        spec->format = AUDIO_S16LSB;
        spec->channels = 2;
        spec->samples = 1024;
    }
    return 0;
}

void SDL_CalculateAudioSpec(SDL_AudioSpec *spec) {
    if (!spec) return;
    Uint32 frame = (Uint32)(spec->channels * ((spec->format == AUDIO_F32) ? 4 : 2));
    spec->size = (Uint32)spec->samples * frame;
}

SDL_AudioDeviceID SDL_OpenAudioDevice(const char *device, int iscapture,
                                      const SDL_AudioSpec *desired, SDL_AudioSpec *obtained,
                                      int allowed_changes) {
    (void)device;
    (void)allowed_changes;
    if (iscapture) {
        SDL_SetError("Audio capture is not available");
        return 0;
    }
    if (!desired) return 0;

    pthread_mutex_lock(&g_audio_lock);
    if (g_audio_device_count >= RAVYN_MAX_AUDIO_DEVICES) {
        pthread_mutex_unlock(&g_audio_lock);
        return 0;
    }
    RavynAudioDevice *dev = &g_audio_devices[g_audio_device_count];
    memset(dev, 0, sizeof(*dev));
    dev->spec = *desired;
    if (dev->spec.freq <= 0) dev->spec.freq = 44100;
    if (dev->spec.channels <= 0) dev->spec.channels = 2;
    if (dev->spec.samples <= 0) dev->spec.samples = 1024;
    if (dev->spec.format == 0) dev->spec.format = AUDIO_S16LSB;
    dev->callback = desired->callback;
    dev->userdata = desired->userdata;
    dev->opened = SDL_TRUE;
    dev->paused = SDL_TRUE;   /* SDL opens paused; SDL_PauseAudioDevice starts it */
    dev->thread_running = SDL_TRUE;
    pthread_mutex_init(&dev->lock, NULL);
    if (obtained) *obtained = dev->spec;
    int id = ++g_audio_device_count;
    if (pthread_create(&dev->thread, NULL, audio_thread_main, dev) != 0) {
        dev->thread_running = SDL_FALSE;
        g_audio_device_count--;
        pthread_mutex_unlock(&g_audio_lock);
        SDL_SetError("Could not start the audio thread");
        return 0;
    }
    pthread_mutex_unlock(&g_audio_lock);
    return (SDL_AudioDeviceID)id;
}

int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained) {
    SDL_AudioDeviceID id = SDL_OpenAudioDevice(NULL, 0, desired, obtained, 0);
    return (id > 0) ? 0 : -1;
}

SDL_AudioStatus SDL_GetAudioDeviceStatus(SDL_AudioDeviceID dev) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return SDL_AUDIO_STOPPED;
    RavynAudioDevice *d = &g_audio_devices[dev - 1];
    if (!d->opened) return SDL_AUDIO_STOPPED;
    return d->paused ? SDL_AUDIO_PAUSED : SDL_AUDIO_PLAYING;
}

SDL_AudioStatus SDL_GetAudioStatus(void) {
    return SDL_GetAudioDeviceStatus(1);
}

void SDL_PauseAudioDevice(SDL_AudioDeviceID dev, int pause_on) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return;
    g_audio_devices[dev - 1].paused = pause_on ? SDL_TRUE : SDL_FALSE;
}

void SDL_PauseAudio(int pause_on) {
    SDL_PauseAudioDevice(1, pause_on);
}

void SDL_LockAudioDevice(SDL_AudioDeviceID dev) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return;
    pthread_mutex_lock(&g_audio_devices[dev - 1].lock);
}

void SDL_UnlockAudioDevice(SDL_AudioDeviceID dev) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return;
    pthread_mutex_unlock(&g_audio_devices[dev - 1].lock);
}

void SDL_LockAudio(void) { SDL_LockAudioDevice(1); }
void SDL_UnlockAudio(void) { SDL_UnlockAudioDevice(1); }

void SDL_CloseAudioDevice(SDL_AudioDeviceID dev) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return;
    RavynAudioDevice *d = &g_audio_devices[dev - 1];
    if (!d->opened) return;
    d->thread_running = SDL_FALSE;
    pthread_join(d->thread, NULL);
    free(d->queue);
    pthread_mutex_destroy(&d->lock);
    memset(d, 0, sizeof(*d));
}

void SDL_CloseAudio(void) { SDL_CloseAudioDevice(1); }

int SDL_QueueAudio(SDL_AudioDeviceID dev, const void *data, Uint32 len) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return -1;
    RavynAudioDevice *d = &g_audio_devices[dev - 1];
    if (len == 0) return 0;
    if (d->queue_size + len > d->queue_capacity) {
        size_t cap = d->queue_capacity ? d->queue_capacity : 4096;
        while (cap < d->queue_size + len) cap *= 2;
        Uint8 *nq = (Uint8 *)realloc(d->queue, cap);
        if (!nq) return -1;
        d->queue = nq;
        d->queue_capacity = cap;
    }
    memcpy(d->queue + d->queue_size, data, len);
    d->queue_size += len;
    return 0;
}

Uint32 SDL_DequeueAudio(SDL_AudioDeviceID dev, void *data, Uint32 len) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count || !data) return 0;
    RavynAudioDevice *d = &g_audio_devices[dev - 1];
    Uint32 n = (len < d->queue_size) ? len : (Uint32)d->queue_size;
    memcpy(data, d->queue, n);
    memmove(d->queue, d->queue + n, d->queue_size - n);
    d->queue_size -= n;
    return n;
}

Uint32 SDL_GetQueuedAudioSize(SDL_AudioDeviceID dev) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return 0;
    return (Uint32)g_audio_devices[dev - 1].queue_size;
}

void SDL_ClearQueuedAudio(SDL_AudioDeviceID dev) {
    if (dev == 0 || dev > (SDL_AudioDeviceID)g_audio_device_count) return;
    g_audio_devices[dev - 1].queue_size = 0;
}

int SDL_BuildAudioCVT(SDL_AudioCVT *cvt, SDL_AudioFormat src_format, Uint8 src_channels, int src_rate,
                      SDL_AudioFormat dst_format, Uint8 dst_channels, int dst_rate) {
    if (!cvt) return -1;
    memset(cvt, 0, sizeof(*cvt));
    cvt->src_format = src_format;
    cvt->dst_format = dst_format;
    cvt->needed = (src_format != dst_format || src_channels != dst_channels || src_rate != dst_rate) ? 1 : 0;
    cvt->len_mult = 1;
    cvt->len_ratio = 1.0;
    return cvt->needed;
}

int SDL_ConvertAudio(SDL_AudioCVT *cvt) {
    (void)cvt;
    return 0;
}

void SDL_MixAudioFormat(Uint8 *dst, const Uint8 *src, SDL_AudioFormat format, Uint32 len, int volume) {
    if (!dst || !src || volume <= 0) return;
    if (volume > SDL_MIX_MAXVOLUME) volume = SDL_MIX_MAXVOLUME;
    if (format == AUDIO_S16LSB || format == AUDIO_S16MSB) {
        Sint16 *d = (Sint16 *)dst;
        const Sint16 *s = (const Sint16 *)src;
        for (Uint32 i = 0; i < len / 2; i++) {
            Sint32 m = d[i] + (s[i] * volume) / SDL_MIX_MAXVOLUME;
            if (m > 32767) m = 32767;
            if (m < -32768) m = -32768;
            d[i] = (Sint16)m;
        }
    } else if (format == AUDIO_U8) {
        for (Uint32 i = 0; i < len; i++) {
            Sint32 m = (Sint32)dst[i] + (((Sint32)src[i] - 128) * volume) / SDL_MIX_MAXVOLUME;
            if (m > 255) m = 255;
            if (m < 0) m = 0;
            dst[i] = (Uint8)m;
        }
    } else {
        memcpy(dst, src, len);
    }
}

void SDL_MixAudio(Uint8 *dst, const Uint8 *src, Uint32 len, int volume) {
    SDL_MixAudioFormat(dst, src, AUDIO_S16LSB, len, volume);
}

SDL_AudioSpec *SDL_LoadWAV_RW(SDL_RWops *src, int freesrc, SDL_AudioSpec *spec, Uint8 **audio_buf, Uint32 *audio_len) {
    if (!src || !spec) {
        if (freesrc && src) SDL_RWclose(src);
        return NULL;
    }
    Uint8 hdr[44];
    if (SDL_RWread(src, hdr, 1, 44) != 44 ||
        memcmp(hdr, "RIFF", 4) != 0 || memcmp(hdr + 8, "WAVE", 4) != 0) {
        if (freesrc) SDL_RWclose(src);
        SDL_SetError("Not a WAV file");
        return NULL;
    }
    Uint16 channels = (Uint16)(hdr[22] | (hdr[23] << 8));
    Uint32 rate = (Uint32)hdr[24] | ((Uint32)hdr[25] << 8) | ((Uint32)hdr[26] << 16) | ((Uint32)hdr[27] << 24);
    Uint16 bits = (Uint16)(hdr[34] | (hdr[35] << 8));
    Uint32 data_len = (Uint32)hdr[40] | ((Uint32)hdr[41] << 8) | ((Uint32)hdr[42] << 16) | ((Uint32)hdr[43] << 24);

    Uint8 *buf = (Uint8 *)malloc(data_len ? data_len : 1);
    if (!buf) {
        if (freesrc) SDL_RWclose(src);
        return NULL;
    }
    size_t got = SDL_RWread(src, buf, 1, data_len);
    if (freesrc) SDL_RWclose(src);

    memset(spec, 0, sizeof(*spec));
    spec->freq = (int)rate;
    spec->channels = (Uint8)channels;
    spec->format = (bits == 8) ? AUDIO_U8 : AUDIO_S16LSB;
    *audio_buf = buf;
    *audio_len = (Uint32)got;
    return spec;
}

/* SDL_LoadWAV is a macro in SDL_audio.h that expands to SDL_LoadWAV_RW, so
 * there is no function symbol by that name to define here. */

void SDL_FreeWAV(Uint8 *audio_buf) {
    free(audio_buf);
}

/* Joystick, game controller, sensor and haptic entry points live in
 * SDL_ravynos_devices_stubs.c, generated from the public headers. */
