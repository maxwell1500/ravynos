/*
 * pasteboard_ipc.h - wire protocol between AppKit's NSPasteboard and the
 * system-wide pasteboard daemon (pasteboardd).
 *
 * The daemon is a Mach service registered under two names -- the native
 * "com.ravynos.pasteboardd" and the canonical macOS "com.apple.pboard" --
 * both resolving to the SAME port, so a native ravynOS app and an app built
 * against the canonical name share one pasteboard.
 *
 * Payload bytes live in POSIX shared memory segments named
 * /pboard_<board>_<generation>_<index>.  The segment is created with
 * O_CREAT|O_EXCL and ftruncate()d exactly once: xnu's POSIX shm allows only
 * one ftruncate() per object lifetime, so a new payload always means a new
 * segment and the previous generation is unlinked first.
 */

#ifndef PASTEBOARD_IPC_H
#define PASTEBOARD_IPC_H

#include <mach/mach.h>
#include <stdint.h>

#define PBOARD_SVC_NAME       "com.ravynos.pasteboardd"
#define PBOARD_SVC_NAME_APPLE "com.apple.pboard"

/* Payload bytes up to this size travel inline in the reply message; larger
 * payloads are read from the shared memory segment named in the reply. */
#define PBOARD_INLINE_MAX (64 * 1024)

enum {
    PBOARD_OP_DECLARE_TYPES    = 1,
    PBOARD_OP_ADD_TYPES        = 2,
    PBOARD_OP_SET_DATA         = 3,
    PBOARD_OP_GET_DATA         = 4,
    PBOARD_OP_GET_TYPES        = 5,
    PBOARD_OP_GET_CHANGE_COUNT = 6,
    PBOARD_OP_CLEAR            = 7
};

/* flags */
#define PBOARD_F_INLINE 0x00000001u   /* data[] carries the payload */
/* SET_DATA with a payload larger than the inline buffer: data[] names a POSIX
 * shm segment the client created, totalLen is its length, and the daemon copies
 * it into the board's own segment and unlinks the client's. */
#define PBOARD_F_SHM_UPLOAD 0x00000002u

typedef struct {
    mach_msg_header_t header;
    uint32_t op;
    uint32_t flags;
    int32_t  changeCount;
    uint32_t dataLen;    /* bytes of payload present in data[] */
    uint32_t totalLen;   /* total payload length */
    uint32_t count;      /* number of types (GET_TYPES) */
    char     board[64];
    char     type[128];
    char     shmName[96];
    char     data[PBOARD_INLINE_MAX];
} PBoardMessage;

#endif /* PASTEBOARD_IPC_H */
