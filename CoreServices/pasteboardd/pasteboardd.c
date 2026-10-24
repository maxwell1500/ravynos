/*
 * pasteboardd - the ravynOS system pasteboard server.
 *
 * One daemon owns every named pasteboard (general, drag, find, ...).  Clients
 * (AppKit's NSPasteboard) talk to it over Mach messages; payload bytes are
 * kept in POSIX shared memory segments so a large image or RTF payload does
 * not have to travel inside a Mach message.
 *
 * The service is registered under two names, "com.ravynos.pasteboardd" and
 * "com.apple.pboard", on the SAME port: a native ravynOS app and an app that
 * knows only the canonical macOS name must see one shared pasteboard.
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <mach/mach.h>
#include <servers/bootstrap.h>

#include "pasteboard_ipc.h"

extern mach_port_t bootstrap_port;
extern void bootstrap_init(void);

#define PBOARD_MAX_BOARDS 16
#define PBOARD_MAX_ITEMS  64
#define PBOARD_MAX_TYPES  32
#define PBOARD_TYPE_LEN   128
#define PBOARD_NAME_LEN   64

typedef struct {
    char     type[PBOARD_TYPE_LEN];
    char     shmName[96];
    uint32_t len;
} PBoardItem;

typedef struct {
    char       name[PBOARD_NAME_LEN];
    int32_t    changeCount;
    uint32_t   generation;
    char       types[PBOARD_MAX_TYPES][PBOARD_TYPE_LEN];
    int        nTypes;
    PBoardItem items[PBOARD_MAX_ITEMS];
    int        nItems;
} PBoard;

static PBoard g_boards[PBOARD_MAX_BOARDS];
static int    g_nBoards = 0;

static void logmsg(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    fflush(stderr);
}

static PBoard *boardFor(const char *name, int create) {
    int i;
    for (i = 0; i < g_nBoards; i++)
        if (strcmp(g_boards[i].name, name) == 0)
            return &g_boards[i];
    if (!create || g_nBoards >= PBOARD_MAX_BOARDS)
        return NULL;
    PBoard *b = &g_boards[g_nBoards++];
    memset(b, 0, sizeof(*b));
    snprintf(b->name, sizeof(b->name), "%s", name);
    return b;
}

static PBoardItem *itemFor(PBoard *b, const char *type, int create) {
    int i;
    for (i = 0; i < b->nItems; i++)
        if (strcmp(b->items[i].type, type) == 0)
            return &b->items[i];
    if (!create || b->nItems >= PBOARD_MAX_ITEMS)
        return NULL;
    PBoardItem *it = &b->items[b->nItems++];
    memset(it, 0, sizeof(*it));
    snprintf(it->type, sizeof(it->type), "%s", type);
    return it;
}

static void addType(PBoard *b, const char *type) {
    int i;
    for (i = 0; i < b->nTypes; i++)
        if (strcmp(b->types[i], type) == 0)
            return;
    if (b->nTypes >= PBOARD_MAX_TYPES)
        return;
    snprintf(b->types[b->nTypes++], PBOARD_TYPE_LEN, "%s", type);
}

/* Publish len bytes as a fresh shared memory segment.  The previous
 * generation of this item's segment is unlinked first: xnu allows exactly
 * one ftruncate() per shm object, so a payload can never be resized in
 * place. */
static int publishData(PBoardItem *it, const uint8_t *bytes, uint32_t len,
                        const char *board, uint32_t generation, int index) {
    char name[96];
    int fd;
    void *map;

    if (it->shmName[0])
        shm_unlink(it->shmName);

    snprintf(name, sizeof(name), "/pboard_%s_%u_%d", board, generation, index);
    fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) {
        logmsg("[pboardd] shm_open(%s) failed: %d", name, errno);
        return -1;
    }
    if (ftruncate(fd, (off_t)len) != 0) {
        logmsg("[pboardd] ftruncate(%s, %u) failed: %d", name, len, errno);
        close(fd);
        shm_unlink(name);
        return -1;
    }
    map = mmap(NULL, len ? len : 1, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        logmsg("[pboardd] mmap(%s) failed: %d", name, errno);
        close(fd);
        shm_unlink(name);
        return -1;
    }
    if (len)
        memcpy(map, bytes, len);
    munmap(map, len ? len : 1);
    close(fd);

    snprintf(it->shmName, sizeof(it->shmName), "%s", name);
    it->len = len;
    return 0;
}

static int readSegment(const char *name, uint8_t *out, uint32_t maxLen,
                        uint32_t *outLen) {
    int fd;
    struct stat st;
    void *map;
    uint32_t len;

    fd = shm_open(name, O_RDONLY, 0600);
    if (fd < 0)
        return -1;
    if (fstat(fd, &st) != 0) {
        close(fd);
        return -1;
    }
    len = (uint32_t)st.st_size;
    if (len > maxLen)
        len = maxLen;
    map = mmap(NULL, len ? len : 1, PROT_READ, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        close(fd);
        return -1;
    }
    if (len)
        memcpy(out, map, len);
    munmap(map, len ? len : 1);
    close(fd);
    if (outLen)
        *outLen = len;
    return 0;
}

/* The type list travels as a NUL separated string. */
static void parseTypeList(PBoard *b, const char *buf, uint32_t len) {
    uint32_t off = 0;
    while (off < len && buf[off]) {
        uint32_t n = (uint32_t)strlen(buf + off);
        if (off + n >= len)
            break;
        addType(b, buf + off);
        off += n + 1;
    }
}

static void handleDeclare(PBoard *b, PBoardMessage *m) {
    int i;
    b->changeCount++;
    b->generation++;
    /* A new declaration starts a new generation: the old payloads are gone. */
    for (i = 0; i < b->nItems; i++)
        if (b->items[i].shmName[0]) {
            shm_unlink(b->items[i].shmName);
            b->items[i].shmName[0] = 0;
            b->items[i].len = 0;
        }
    b->nItems = 0;
    b->nTypes = 0;
    parseTypeList(b, m->data, m->dataLen);
}

static void handleAddTypes(PBoard *b, PBoardMessage *m) {
    b->changeCount++;
    parseTypeList(b, m->data, m->dataLen);
}

static void handleSetData(PBoard *b, PBoardMessage *m) {
    PBoardItem *it = itemFor(b, m->type, 1);
    if (!it)
        return;
    b->changeCount++;
    b->generation++;
    addType(b, m->type);

    if ((m->flags & PBOARD_F_SHM_UPLOAD) && m->shmName[0] && m->totalLen > 0) {
        /* Large payload: the client staged it in shared memory because it does
         * not fit in the message.  Copy it into the board's segment, then
         * release the client's.  A missing or short segment leaves the item
         * unpublished rather than storing a truncated value. */
        uint8_t *buf = (uint8_t *)malloc(m->totalLen);
        uint32_t got = 0;

        if (buf != NULL &&
            readSegment(m->shmName, buf, m->totalLen, &got) == 0 &&
            got == m->totalLen) {
            publishData(it, buf, got, b->name, b->generation,
                        (int)(it - b->items));
        }
        free(buf);
        shm_unlink(m->shmName);
        return;
    }

    publishData(it, (const uint8_t *)m->data, m->dataLen, b->name,
                b->generation, (int)(it - b->items));
}

static void handleGetData(PBoard *b, PBoardMessage *m) {
    PBoardItem *it = itemFor(b, m->type, 0);
    m->totalLen = 0;
    m->dataLen = 0;
    m->flags = 0;
    m->shmName[0] = 0;
    if (!it || it->len == 0)
        return;
    snprintf(m->shmName, sizeof(m->shmName), "%s", it->shmName);
    m->totalLen = it->len;
    if (it->len <= PBOARD_INLINE_MAX) {
        uint32_t got = 0;
        if (readSegment(it->shmName, (uint8_t *)m->data, PBOARD_INLINE_MAX, &got) == 0) {
            m->dataLen = got;
            m->flags = PBOARD_F_INLINE;
        }
    }
}

static void handleGetTypes(PBoard *b, PBoardMessage *m) {
    size_t off = 0;
    int i;
    for (i = 0; i < b->nTypes; i++) {
        size_t n = strlen(b->types[i]) + 1;
        if (off + n >= PBOARD_INLINE_MAX)
            break;
        memcpy(m->data + off, b->types[i], n);
        off += n;
    }
    m->dataLen = (uint32_t)off;
    m->count = (uint32_t)b->nTypes;
}

int main(int argc, char **argv) {
    mach_port_t servicePort = MACH_PORT_NULL;
    kern_return_t kr;

    (void)argc;
    (void)argv;

    signal(SIGPIPE, SIG_IGN);

    if (bootstrap_port == MACH_PORT_NULL)
        bootstrap_init();

    kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &servicePort);
    if (kr != KERN_SUCCESS) {
        logmsg("[pboardd] mach_port_allocate failed: %d", kr);
        return 1;
    }

    /* Register the native name first, then the canonical macOS name for the
     * same port.  check_in() takes the port launchd created for the job's
     * declared MachService; register() then publishes the canonical name for
     * that very port, so both names resolve to the same server.  (A second
     * check_in() would hand back a port of launchd's choosing and the alias
     * would point somewhere else than the daemon.) */
    kr = bootstrap_check_in(bootstrap_port, PBOARD_SVC_NAME, &servicePort);
    if (kr != KERN_SUCCESS) {
        logmsg("[pboardd] bootstrap_check_in(%s) failed: %d", PBOARD_SVC_NAME, kr);
        return 1;
    }
    /* register() needs a send right for the port. */
    if (mach_port_mod_refs(mach_task_self(), servicePort, MACH_PORT_RIGHT_SEND, 1) != KERN_SUCCESS)
        mach_port_insert_right(mach_task_self(), servicePort, servicePort, MACH_MSG_TYPE_MAKE_SEND);

    /* register() publishes an additional name for the port we own.  A second
     * check_in() must not be used: it hands back a port of its own choosing,
     * and the alias would then point somewhere else than the daemon. */
    kr = bootstrap_register(bootstrap_port, PBOARD_SVC_NAME_APPLE, servicePort);
    if (kr != KERN_SUCCESS) {
        logmsg("[pboardd] canonical alias %s could not be registered: %d",
               PBOARD_SVC_NAME_APPLE, kr);
        logmsg("[pboardd] serving %s only", PBOARD_SVC_NAME);
    } else {
        logmsg("[pboardd] serving %s and %s", PBOARD_SVC_NAME, PBOARD_SVC_NAME_APPLE);
    }

    for (;;) {
        PBoardMessage *msg = malloc(sizeof(PBoardMessage));
        PBoard *b;
        if (!msg)
            break;
        memset(msg, 0, sizeof(PBoardMessage));
        kr = mach_msg((mach_msg_header_t *)msg, MACH_RCV_MSG, 0, sizeof(PBoardMessage),
                      servicePort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        if (kr != MACH_MSG_SUCCESS) {
            if (kr == MACH_RCV_TIMED_OUT || kr == MACH_RCV_INTERRUPTED) {
                free(msg);
                continue;
            }
            logmsg("[pboardd] mach_msg receive failed: 0x%x", kr);
            free(msg);
            break;
        }

        if (MACH_MSGH_BITS_REMOTE(msg->header.msgh_bits) == MACH_MSG_TYPE_COPY_SEND)
            mach_port_deallocate(mach_task_self(), msg->header.msgh_remote_port);

        b = boardFor(msg->board, 1);
        if (b) {
            switch (msg->op) {
                case PBOARD_OP_DECLARE_TYPES:    handleDeclare(b, msg); break;
                case PBOARD_OP_ADD_TYPES:        handleAddTypes(b, msg); break;
                case PBOARD_OP_SET_DATA:         handleSetData(b, msg); break;
                case PBOARD_OP_GET_DATA:         handleGetData(b, msg); break;
                case PBOARD_OP_GET_TYPES:        handleGetTypes(b, msg); break;
                case PBOARD_OP_GET_CHANGE_COUNT: /* reply carries changeCount */ break;
                case PBOARD_OP_CLEAR:            handleDeclare(b, msg); break;
                default: break;
            }
        }

        msg->header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
        msg->header.msgh_local_port = MACH_PORT_NULL;
        msg->header.msgh_size = sizeof(PBoardMessage);
        msg->changeCount = b ? b->changeCount : 0;
        mach_msg((mach_msg_header_t *)msg, MACH_SEND_MSG, sizeof(PBoardMessage),
                 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        free(msg);
    }

    return 0;
}
