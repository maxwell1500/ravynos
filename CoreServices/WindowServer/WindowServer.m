/*
 * Copyright (C) 2022-2025 Zoe Knox <zoe@pixin.net>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#define WINDOWSERVER 1

#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2ImageSource.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSGraphicsContext.h>
#import <objc/runtime.h>
#import "common.h"
#import "WindowServer.h"

#undef direction // defined in mach.h
#if defined(__linux__)
 #include <linux/input.h>
#endif
#include <poll.h>
extern void bootstrap_init(void);
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/user.h>
#include <sys/proc_info.h>
/* proc_pidpath is provided by libsystem_kernel but not declared in this
 * SDK's sys/proc_info.h. */
int proc_pidpath(pid_t pid, char *buf, uint32_t buffersize);
#include <sys/shm.h>
#include <sys/ipc.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/resource.h>

#include <launch.h>
#include <servers/bootstrap.h>

#import "rpc.h"
/* WindowServer RPC entry point, provided by libWindowServer on ravynOS. */
kern_return_t _windowServerRPC(void *data, size_t len, void *replyBuf, int *replyLen);
#include <errno.h>
/* Cross-process "this window has painted content" channel: WindowServer's
 * stderr only reaches the serial log, so dailydrivertest polls this file to
 * learn when a launched bundle is on screen before launching the next one. */
static void wsPaintedMarker(const char *bundleID) {
    if(bundleID == NULL || bundleID[0] == 0 || strcmp(bundleID, "unknown") == 0)
        return;
    int fd = open("/var/log/ws-painted.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if(fd < 0) {
        char errbuf[96];
        int m = snprintf(errbuf, sizeof(errbuf), "[WS] painted-marker open failed errno %d\n", errno);
        if(m > 0)
            write(2, errbuf, (size_t)m);
        return;
    }
    char line[128];
    int n = snprintf(line, sizeof(line), "PAINTED %s\n", bundleID);
    ssize_t wr = write(fd, line, (size_t)n);
    if(wr < 0) {
        char errbuf[96];
        int m = snprintf(errbuf, sizeof(errbuf), "[WS] painted-marker write failed errno %d\n", errno);
        if(m > 0)
            write(2, errbuf, (size_t)m);
    } else
        fprintf(stderr, "[WS] MARK wrote %s\n", bundleID);
    close(fd);
}

/* Launch and activation bookkeeping in the same cross-process file channel as
 * the painted marker.  "The canonical macOS path is the same application" is
 * a claim about processes, not about paths: opening Filer.app and then
 * Finder.app must activate one process, never fork a second copy.  The guest
 * self test can only see that if WindowServer writes it down. */
static void wsAppMarker(const char *verb, const char *bundleID, pid_t pid) {
    if(bundleID == NULL || bundleID[0] == 0 || strcmp(bundleID, "unknown") == 0)
        return;
    int fd = open("/var/log/ws-apps.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if(fd < 0)
        return;
    char line[160];
    int n = snprintf(line, sizeof(line), "%s %s %d\n", verb, bundleID, (int)pid);
    if(n > 0 && write(fd, line, (size_t)n) > 0)
        fprintf(stderr, "[WS] %s app=%s pid=%d\n", verb, bundleID, (int)pid);
    close(fd);
}

/* FreeBSD mmap hint flags the ravynOS sys/mman.h does not define. Both are
 * hints only, so 0 is the correct no-op value. */
#ifndef MAP_NOCORE
#define MAP_NOCORE 0
#endif
#ifndef MAP_NOSYNC
#define MAP_NOSYNC 0
#endif


/* This lock prevents other threads from messing with the graphics context while we
 * are in the rendering loop
 */
pthread_mutex_t renderLock;

/* Guards _sceneDirty/_damageRect: the mach service thread marks damage while the
 * render thread snapshots and clears it.  Never taken while renderLock is held in
 * the other order -- the render thread drops this lock before compositing.
 */
static pthread_mutex_t damageLock = PTHREAD_MUTEX_INITIALIZER;

/* Last menu archive received per bundle ID.  At login an app usually sends its
 * menu before SystemUIServer has registered, and the relay below drops it (the
 * NSLog is the only trace and NSLog never reaches the serial console).  The
 * menus are replayed from here when SUI registers -- see MSG_ID_PORT.  Only the
 * mach receive thread touches this, so it needs no lock. */
static NSMutableDictionary *stashedMenus = nil;

/* The apps dictionary is shared between the mach service thread (lookups on
 * every RPC), the kqueue thread (removeObjectForKey when a child exits) and
 * the shell thread (registration).  Concurrent NSMutableDictionary mutation
 * returns dangling pointers, so every access is serialised.  Held for the
 * whole RPC dispatch, because the handler uses the record after the lookup. */
static pthread_mutex_t appsLock;

/* Recursive: an RPC handler holds this across helpers (windowModify ->
 * updateClientWindowState -> notifyDock) that also take it. */
static void appsLockInit(void) {
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&appsLock, &attr);
    pthread_mutexattr_destroy(&attr);
}
static BOOL sInDrag = NO;
static WSWindowRecord *sDragWindow = nil;

/* Paint bookkeeping.  A window announces itself with "[WS] PAINTED" once its
 * surface holds real content, so the screenshot harness can wait for the
 * window instead of guessing.  Window numbers are per app, so the key is
 * (pid, window number).  "flushed" means the client sent its window state
 * while the window was NORMAL, which happens right after it drew. */
#define WS_PAINT_MAX 128
typedef struct {
    pid_t pid;
    unsigned number;
    int flushed;
    int announced;
} WSPaintEntry;

static WSPaintEntry sPaintTable[WS_PAINT_MAX];
static int sPaintCount = 0;
static pthread_mutex_t sPaintLock = PTHREAD_MUTEX_INITIALIZER;

/* A window with real content has non-zero bytes somewhere.  Sampling a few
 * spots is enough and scanning the whole buffer every frame is not
 * affordable on a single-vCPU guest. */
static BOOL WSSurfaceHasContent(void *buf, size_t size) {
    unsigned char *px = (unsigned char *)buf;
    const int samples = 32;
    if(px == NULL || size < 4)
        return NO;
    size_t step = size / (size_t)samples;
    for(int i = 0; i < samples; i++) {
        size_t off = step * (size_t)i;
        if(off + 4 > size)
            off = size - 4;
        if(px[off] || px[off+1] || px[off+2] || px[off+3])
            return YES;
    }
    return NO;
}

/* The client flushed this window while it was NORMAL. */
static void WSPaintMarkFlushed(pid_t pid, unsigned number) {
    pthread_mutex_lock(&sPaintLock);
    for(int i = 0; i < sPaintCount; i++) {
        if(sPaintTable[i].pid == pid && sPaintTable[i].number == number) {
            sPaintTable[i].flushed = 1;
            pthread_mutex_unlock(&sPaintLock);
            return;
        }
    }
    if(sPaintCount < WS_PAINT_MAX) {
        sPaintTable[sPaintCount].pid = pid;
        sPaintTable[sPaintCount].number = number;
        sPaintTable[sPaintCount].flushed = 1;
        sPaintTable[sPaintCount].announced = 0;
        sPaintCount++;
    }
    pthread_mutex_unlock(&sPaintLock);
}

/* Did the client already flush this window while it was NORMAL? */
static BOOL WSPaintWasFlushed(pid_t pid, unsigned number) {
    BOOL flushed = NO;
    pthread_mutex_lock(&sPaintLock);
    for(int i = 0; i < sPaintCount; i++) {
        if(sPaintTable[i].pid == pid && sPaintTable[i].number == number) {
            flushed = sPaintTable[i].flushed ? YES : NO;
            break;
        }
    }
    pthread_mutex_unlock(&sPaintLock);
    return flushed;
}

static inline void WSAddRoundRectPath(O2ContextRef ctx, NSRect r, float radius) {
    float x = r.origin.x;
    float y = r.origin.y;
    float w = r.size.width;
    float h = r.size.height;
    if(radius * 2.0f > w) radius = w / 2.0f;
    if(radius * 2.0f > h) radius = h / 2.0f;
    O2ContextBeginPath(ctx);
    O2ContextMoveToPoint(ctx, x + radius, y);
    O2ContextAddArcToPoint(ctx, x + w, y, x + w, y + h, radius);
    O2ContextAddArcToPoint(ctx, x + w, y + h, x, y + h, radius);
    O2ContextAddArcToPoint(ctx, x, y + h, x, y, radius);
    O2ContextAddArcToPoint(ctx, x, y, x + w, y, radius);
    O2ContextClosePath(ctx);
}

static void WSDrawArrowCursor(O2ContextRef ctx, float x, float y) {
    O2ContextSaveGState(ctx);
    // Outer black outline: classic macOS arrow
    O2ContextBeginPath(ctx);
    O2ContextMoveToPoint(ctx, x, y);
    O2ContextAddLineToPoint(ctx, x, y - 17.0f);
    O2ContextAddLineToPoint(ctx, x + 4.5f, y - 13.0f);
    O2ContextAddLineToPoint(ctx, x + 7.5f, y - 19.0f);
    O2ContextAddLineToPoint(ctx, x + 10.0f, y - 18.0f);
    O2ContextAddLineToPoint(ctx, x + 7.0f, y - 12.0f);
    O2ContextAddLineToPoint(ctx, x + 12.0f, y - 12.0f);
    O2ContextClosePath(ctx);
    O2ContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 1.0f);
    O2ContextFillPath(ctx);

    // Inner crisp white arrow
    O2ContextBeginPath(ctx);
    O2ContextMoveToPoint(ctx, x + 1.0f, y - 2.0f);
    O2ContextAddLineToPoint(ctx, x + 1.0f, y - 14.5f);
    O2ContextAddLineToPoint(ctx, x + 4.5f, y - 11.5f);
    O2ContextAddLineToPoint(ctx, x + 7.5f, y - 17.5f);
    O2ContextAddLineToPoint(ctx, x + 8.5f, y - 16.5f);
    O2ContextAddLineToPoint(ctx, x + 5.5f, y - 11.0f);
    O2ContextAddLineToPoint(ctx, x + 10.0f, y - 11.0f);
    O2ContextClosePath(ctx);
    O2ContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
    O2ContextFillPath(ctx);
    O2ContextRestoreGState(ctx);
}

/* Damage box for the vector arrow above: its tip is at (x,y) and the body
 * extends +x and -y, so a box that only grew upward from the tip (which is
 * what the cursor used to be clipped to) erased the whole arrow. */
static NSRect WSCursorDamageRect(float x, float y) {
    return NSMakeRect(x - 1.0f, y - 21.0f, 15.0f, 23.0f);
}
@implementation WindowServer

static void notifyAppExited(mach_port_t port, pid_t pid, const char *bundleID, const char *path) {
    Message msg = {0};
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = CODE_APP_EXITED;
    msg.pid = pid;
    msg.len = strlen(path);
    strncpy(msg.data, path, PATH_MAX);
    strncpy(msg.bundleID, bundleID, sizeof(msg.bundleID));
    mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
            sizeof(msg) - sizeof(mach_msg_trailer_t),
            0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
}

/* Darwin's KERN_PROC_PATHNAME is a sysctl only the kernel exports; the
 * userspace equivalent is PROC_PIDPATHINFO under the same KERN_PROC root. */
static NSString *_pathForPID(pid_t pid) {
    char buf[PROC_PIDPATHINFO_MAXSIZE + 1];
    memset(buf, 0, sizeof(buf));
    int n = proc_pidpath(pid, buf, sizeof(buf) - 1);
    if(n <= 0) {
        NSLog(@"proc_pidpath(%d): failed (n=%d errno=%d)", pid, n, errno);
        /* An app that registers its port and then exits before we look it up
         * (ESRCH) is ordinary here, and every consumer of this path sends it as
         * a C string: -[NSString UTF8String] is NULL for nil, and that NULL
         * went straight into strncpy(msg.data, path, PATH_MAX) when a launched
         * app was announced to the Dock -- strnlen(NULL, PATH_MAX) killed the
         * WindowServer and took the Dock and the menu bar down with it.  An
         * unknown path is an empty path, not a NULL one. */
        return @"";
    }
    buf[n] = '\0';
    return [NSString stringWithCString:buf];
}

/* The kvm(3) equivalent of kvm_getprocs(kvm, KERN_PROC_PID, pid, &count):
 * sysctl() under the same root returns exactly one kinfo_proc for the pid. */
static struct kinfo_proc *_procForPID(pid_t pid) {
    static struct kinfo_proc kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    size_t len = sizeof(kp);

    memset(&kp, 0, sizeof(kp));
    if(sysctl(mib, 4, &kp, &len, NULL, 0) < 0 || len == 0)
        return NULL;
    if(kp.kp_proc.p_pid != pid)
        return NULL;
    return &kp;
}

-init {
    ready = NO;
    logLevel = WS_ERROR;
    envp = NULL;
    curShell = LOADING;
    curApp = nil;
    curWindow = nil;
    pthread_mutex_init(&renderLock, NULL);
    appsLockInit();
    cursorHideCount = 0;

    write(2, "[WS] init starting\n", 19);
    if(bootstrap_port == MACH_PORT_NULL)
        bootstrap_init();
    kern_return_t kr;
    if((kr = bootstrap_check_in(bootstrap_port, WINDOWSERVER_SVC_NAME, &_servicePort)) != KERN_SUCCESS) {
        char errbuf[64];
        int n = snprintf(errbuf, sizeof(errbuf), "[WS] bootstrap_check_in failed: %d\n", kr);
        write(2, errbuf, n);
        mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &_servicePort);
        mach_port_insert_right(mach_task_self(), _servicePort, _servicePort, MACH_MSG_TYPE_MAKE_SEND);
    } else {
        write(2, "[WS] bootstrap_check_in OK\n", 27);
        /* check_in hands us the receive right only.  Add a send right under the
         * same name so that children forked from WindowServer inherit something
         * usable as RAVYN_WS_PORT (see CODE_OPEN_BUNDLE). */
        mach_port_insert_right(mach_task_self(), _servicePort, _servicePort, MACH_MSG_TYPE_MAKE_SEND);
    }
    mach_port_limits_t qlimits = {0};
    qlimits.mpl_qlimit = 128;
    mach_port_set_attributes(mach_task_self(), _servicePort, MACH_PORT_LIMITS_INFO,
                             (mach_port_info_t)&qlimits, sizeof(qlimits));

    _kq = kqueue();
    if(_kq < 0) {
        perror("kqueue");
        return nil;
    }


    displays = [NSMutableArray new];
    apps = [NSMutableDictionary new];

    for(int i = 0; i < kCGNumReservedWindowLevels; ++i)
        _windows[i] = [NSMutableArray new];

    write(2, "[WS] creating WSInput\n", 22);
    input = [WSInput new];
    [input setLogLevel:logLevel];

    // Open the kernel's framebuffer character device, NOT /dev/console.
    //
    // /dev/console on ravynOS is the serial multiplexer (`makedev(0,0)`, see
    // the devfs console node): it accepts writes and carries them to the COM
    // port, but it implements no FBIOGTYPE/FBIO_GETLINEWIDTH ioctl and it is
    // not the GOP scanout memory.  The real framebuffer is published as
    // /dev/fb0 by `devfs_make_node(makedev(fb_major, FB0_MINOR), ...,
    // "fb0")` in bsd/dev/fb0.c, and tools/bootlab/init/fb_probe.c exists to
    // measure exactly that device (open, FBIOGTYPE, FBIO_GETLINEWIDTH, mmap,
    // and a store that QEMU's screendump can see).
    //
    // Opening /dev/console here meant the compositor could never be handed a
    // real scanout, which is why every boot produced an all-black 1024x768
    // screendump regardless of how far WindowServer got.
    write(2, "[WS] creating BSDFramebuffer\n", 29);
    fb = [BSDFramebuffer new];
    write(2, "[WS] calling openFramebuffer /dev/fb0\n", 38);
    if([fb openFramebuffer:"/dev/fb0"] < 0) {
        write(2, "[WS] openFramebuffer failed\n", 28);
        return nil;
    }
    write(2, "[WS] openFramebuffer returned OK\n", 33);
    _geometry = [fb geometry];
    [displays addObject:fb];

    write(2, "[WS] calling fb clear\n", 22);
    [fb clear];
    write(2, "[WS] fb clear returned\n", 23);
    // this is to keep our X,Y from leaving the screen bounds and eventually can be used to find
    // edges when there are multiple screens
    if(input) {
        [input setGeometry:_geometry];
        [input setPointerPos:NSMakePoint(_geometry.size.width / 2, _geometry.size.height / 2)];
    }

    ready = YES;
    return self;
}

-(void)dealloc {
    curShell = NONE;
    fb = nil;
    input = nil;
}

-(void)setLogLevel:(int)level {
    logLevel = level;
    if(input)
        [input setLogLevel:level];
}

-(void)setDebugLevel:(int)level subsystem:(char)sys {
    id obj = nil;
    switch(sys) {
        case 'i': obj = input; break;
    }
#if defined(__linux__)
     if(obj)
         [obj setDebugLevel:level];
#endif
}

-(BOOL)isReady {
    return ready;
}

-(O2BitmapContext *)context {
    return [fb context];
}

-(NSRect)geometry {
    return _geometry;
}

-(void)draw {
    return [fb draw];
}

-(WSDisplay *)displayWithID:(uint32_t)ID {
    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if([d getDisplayID] == ID)
            return d;
    }
    return nil;
}

-(BOOL)setUpEnviron:(uid_t)uid {
    struct passwd *pw = getpwuid(uid);
    if(!pw)
        return NO;
    int entries = 7;
    envp = malloc(sizeof(char *) * entries);
    asprintf(&envp[0], "HOME=%s", pw->pw_dir);
    asprintf(&envp[1], "SHELL=%s", pw->pw_shell);
    asprintf(&envp[2], "USER=%s", pw->pw_name);
    asprintf(&envp[3], "LOGNAME=%s", pw->pw_name);
    asprintf(&envp[4], "PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin");
    asprintf(&envp[6], "TERM=xterm");
    envp[entries - 1] = NULL;
    return YES;
}

-(void)freeEnviron {
    if(envp == NULL)
        return;

    while(*envp != NULL)
        free(*envp++);
    free(envp);
}

-(uint32_t)windowCreate:(struct wsRPCWindow *)data forApp:(WSAppRecord *)app {
    fprintf(stderr, "[WS] CREATE app=%s win=%u level=%d frame=%d,%d %dx%d\n",
        ([[app bundleID] UTF8String] != NULL) ? (const char *)[[app bundleID] UTF8String] : "(nil)",
        (unsigned)data->windowID, (int)data->level,
        (int)data->x, (int)data->y, (int)data->w, (int)data->h);
    struct kinfo_proc *kp;

    if(data->state < 0 || data->state >= WIN_STATE_MAX) {
        NSLog(@"windowCreate called with invalid state");
        data->state = NORMAL;
    }

    if([app windowWithID:data->windowID] != nil) {
        /* Re-sent create after a lost reply: the window already exists, so
         * report it instead of failing the RPC, which would leave AppKit
         * with a nil window over a live server record that never paints. */
        return data->windowID;
    }

    WSWindowRecord *winrec = [WSWindowRecord new];
    winrec.app = app;
    winrec.number = data->windowID;
    winrec.state = data->state;
    winrec.styleMask = data->style;
    winrec.geometry = NSMakeRect(data->x, data->y, data->w, data->h); // FIXME: bounds check?
    if([app.bundleID isEqualToString:@"com.ravynos.LoginWindow"])
        winrec.level = kCGOverlayWindowLevelKey;
    else if(data->level >= kCGMinimumWindowLevelKey && data->level <= kCGMaximumWindowLevelKey)
        winrec.level = data->level;
    int len = 0;
    while(data->title[len] != '\0' && len < sizeof(data->title)) ++len;
    winrec.title = [NSString stringWithCString:data->title length:len];
    winrec.icon = nil;

    /* A client that computes its frame from a not-yet-laid-out view can ask
     * for a nonsense size; mapping hundreds of MB of zeroed shm (and wrapping
     * it in an O2Surface) then hangs the server under TCG.  Treat such a
     * request as the smallest legal frame. */
    if(data->w <= 0 || data->h <= 0 || data->w > 8192 || data->h > 8192) {
        data->w = (data->w <= 0 || data->w > 8192) ? 1 : data->w;
        data->h = (data->h <= 0 || data->h > 8192) ? 1 : data->h;
        winrec.geometry = NSMakeRect(data->x, data->y, data->w, data->h);
    }
    winrec.shmPath = [NSString stringWithFormat:@"/win_%u_%u", [app pid], winrec.number];
    winrec.bufSize = ([fb getDepth]/8) * data->w * data->h;

    int shmfd = shm_open([winrec.shmPath cString], O_RDWR|O_CREAT, 0666);
    if(shmfd < 0) {
        NSLog(@"Cannot open shm fd: %s", strerror(errno));
        return 0;
    }

    if(ftruncate(shmfd, winrec.bufSize) < 0)
        NSLog(@"shmfd ftruncate failed: %s", strerror(errno));

    /* shm is already 0666, no need for fchown via failing sysctl */

    winrec.surfaceBuf = mmap(NULL, winrec.bufSize, PROT_WRITE|PROT_READ, MAP_SHARED|MAP_NOCORE, shmfd, 0);
    close(shmfd);

    if(winrec.surfaceBuf == MAP_FAILED) {
        winrec.bufSize = 0;
        NSLog(@"Cannot alloc surface memory! %s", strerror(errno));
        return 0;
    }
    winrec.surface = [[O2Surface alloc] initWithBytes:winrec.surfaceBuf width:data->w
            height:data->h bitsPerComponent:8 bytesPerRow:4*(data->w)
            colorSpace:[fb colorSpace]
            bitmapInfo:kCGBitmapByteOrderDefault|kCGImageAlphaPremultipliedFirst];
    winrec.frame = winrec.geometry;

    [app addWindow:winrec];
    [self addWindowByLevel:winrec];
    /* The app that creates a window becomes the active one so key events have
     * a destination; without this curApp stays nil until the Dock activates it. */
    if(curApp != app)
        curApp = app;
    curWindow = winrec;    if(logLevel >= WS_INFO)
        NSLog(@"windowCreate: success! %@", winrec);
    return winrec.number;
}

-(void)windowModify:(struct wsRPCWindow *)data forApp:(WSAppRecord *)app {
    fprintf(stderr, "[WS] MODIFY app=%s win=%u level=%d frame=%d,%d %dx%d\n",
        ([[app bundleID] UTF8String] != NULL) ? (const char *)[[app bundleID] UTF8String] : "(nil)",
        (unsigned)data->windowID, (int)data->level,
        (int)data->x, (int)data->y, (int)data->w, (int)data->h);
    if(data->state < 0 || data->state >= WIN_STATE_MAX) {
        NSLog(@"windowModify called with invalid state");
        data->state = NORMAL;
    }

    WSWindowRecord *winrec = [app windowWithID:data->windowID];
    if(winrec == nil) {
        NSLog(@"windowModify: winrec is nil for windowID %llu", data->windowID);
        return;
    }
    int oldState = winrec.state;
    winrec.state = data->state;
    winrec.styleMask = data->style;
    NSRect oldFrame = winrec.geometry;
    if(!sInDrag || winrec != sDragWindow) {
        winrec.geometry = NSMakeRect(data->x, data->y, data->w, data->h); // FIXME: bounds check?
    }
    if(!NSEqualSizes(winrec.geometry.size, oldFrame.size)) {
        /* The window resized, so its shared surface buffer has to be rebuilt at the
         * new size. Two things used to go wrong here and both left a live window
         * pointing at memory that was no longer mapped -- Onyx2D then faulted in the
         * middle of a drawImage span read:
         *   1) munmap() was called with the NEW bufSize (it had already been
         *      overwritten above), so shrinking only unmapped part of the old
         *      mapping and growing failed with EINVAL, leaking the old mapping.
         *   2) when the remap failed we bailed out early while winrec.surface still
         *      wrapped the buffer we had just unmapped; the next frame drew it.
         * So remember the OLD size for munmap(), and on any remap failure drop the
         * surface (NULL means "not drawable", which the draw loop already honours). */
        size_t oldBufSize = winrec.bufSize;
        int oldW = (int)oldFrame.size.width, oldH = (int)oldFrame.size.height;

        pthread_mutex_lock(&renderLock);
        winrec.bufSize = ([fb getDepth]/8) * data->w * data->h;

        shm_unlink([winrec.shmPath cString]);
        int shmfd = shm_open([winrec.shmPath cString], O_RDWR|O_CREAT|O_EXCL, 0666);
        if(shmfd < 0)
            shmfd = shm_open([winrec.shmPath cString], O_RDWR|O_CREAT, 0666);
        if(shmfd < 0) {
            int err = errno;
            pthread_mutex_unlock(&renderLock);
            fprintf(stderr, "[WS] REMAP-FAIL win=%u %dx%d->%dx%d open errno=%d\n",
                (unsigned)data->windowID, oldW, oldH, (int)data->w, (int)data->h, err);
            NSLog(@"Cannot open shm fd: %s", strerror(errno));
            return;
        }

        if(ftruncate(shmfd, winrec.bufSize) < 0) {
            int err = errno;
            close(shmfd);
            /* The new mapping does not exist: the old surface wrapped memory we are
             * about to unmap, so it has to stop being reachable before that happens. */
            munmap(winrec.surfaceBuf, oldBufSize);
            winrec.surfaceBuf = NULL;
            winrec.surface = NULL;
            winrec.bufSize = 0;
            pthread_mutex_unlock(&renderLock);
            fprintf(stderr, "[WS] REMAP-FAIL win=%u %dx%d->%dx%d ftrunc errno=%d\n",
                (unsigned)data->windowID, oldW, oldH, (int)data->w, (int)data->h, err);
            NSLog(@"shmfd ftruncate failed: %s", strerror(errno));
            return;
        }

        if(winrec.surfaceBuf != NULL)
            munmap(winrec.surfaceBuf, oldBufSize);

        winrec.surfaceBuf = mmap(NULL, winrec.bufSize, PROT_WRITE|PROT_READ,
                MAP_SHARED|MAP_NOCORE, shmfd, 0);
        int mapErr = (winrec.surfaceBuf == NULL) ? errno : 0;
        close(shmfd);

        if(winrec.surfaceBuf == NULL) {
            /* No mapping: the OLD surface wrapped the region we just unmapped, so it
             * must not stay reachable -- drawing it is what faulted before. */
            winrec.surface = NULL;
            winrec.bufSize = 0;
            pthread_mutex_unlock(&renderLock);
            fprintf(stderr, "[WS] REMAP-FAIL win=%u %dx%d->%dx%d mmap errno=%d\n",
                (unsigned)data->windowID, oldW, oldH, (int)data->w, (int)data->h, mapErr);
            NSLog(@"Cannot alloc surface memory! %s", strerror(errno));
            return;
        }

        if(logLevel < WS_INFO)
            fprintf(stderr, "[WS] REMAP win=%u %dx%d->%dx%d buf=0x%zx size=0x%zx\n",
                (unsigned)data->windowID, oldW, oldH, (int)data->w, (int)data->h,
                (size_t)winrec.surfaceBuf, (size_t)winrec.bufSize);

        winrec.surface = [[O2Surface alloc] initWithBytes:winrec.surfaceBuf width:data->w
            height:data->h bitsPerComponent:8 bytesPerRow:4*(data->w)
            colorSpace:[fb colorSpace]
            bitmapInfo:kCGBitmapByteOrderDefault|kCGImageAlphaPremultipliedFirst];
        pthread_mutex_unlock(&renderLock);
    }

    int len = 0;
    while(data->title[len] != '\0' && len < sizeof(data->title)) ++len;
    winrec.title = [NSString stringWithCString:data->title length:len];
    winrec.icon = nil;
    winrec.frame = winrec.geometry;

    if(![app.bundleID isEqualToString:@"com.ravynos.LoginWindow"]) {
        if(data->level >= kCGMinimumWindowLevelKey && data->level <= kCGMaximumWindowLevelKey
            && data->level != winrec.level) {
            [self removeWindowByLevel:winrec];
            winrec.level = data->level;
            [self addWindowByLevel:winrec];
        }
    }

    if(logLevel >= WS_INFO)
        NSLog(@"windowModify %@ win %@", app, winrec);

    /* A window that becomes visible again goes in front of the others: the
     * compositor draws the windows of a level in array order, so the last one
     * is the frontmost.  Only a window that just became visible (or one of
     * the active app) is moved: a background app that merely repaints must
     * not jump in front of the app the user is looking at. */
    if(winrec.state == NORMAL && oldState != NORMAL) {
        [self bringWindowToFront:winrec];
        if(app != nil && ![app skipSwitcher]) {
            curApp = app;
            curWindow = winrec;
        }
    }

    /* The client flushes its window (this very RPC) right after it drew, so
     * the window holds content even if every pixel is black. */
    if(winrec.state == NORMAL)
        WSPaintMarkFlushed((pid_t)[app pid], (unsigned)winrec.number);

    /* Anything a client can change through here (frame, level, state) changes
     * what the compositor must paint; without this mark a client repaint that
     * only moved/resized its window would leave the old pixels on screen. */
    [self markDamageRect:NSInsetRect(NSUnionRect(oldFrame, winrec.geometry), -16, -16)];

    if(oldState == MINIMIZED && winrec.state != MINIMIZED)
        [self notifyDock:data length:sizeof(struct wsRPCWindow) 
                withCode:CODE_WINDOW_STATE forApp:app];
}

-(void)addWindowByLevel:(WSWindowRecord *)window {
    if(window == nil) return;
    if(logLevel < WS_INFO) fprintf(stderr,"[WS] ADD win=%u lvl=%d frame=%d,%d %dx%d\n",
        (unsigned)window.number,(int)window.level,
        (int)window.frame.origin.x,(int)window.frame.origin.y,
        (int)window.frame.size.width,(int)window.frame.size.height);

    if(window.level < 0 || window.level >= kCGNumReservedWindowLevels) {
        /* A level outside the table means the window is invisible to hit-testing AND
         * drawing -- a silent no-op that is very hard to diagnose from the app side. */
        fprintf(stderr,"[WS] DROPPED window level=%d (table size %d)\n",
            (int)window.level, kCGNumReservedWindowLevels);
        return;
    }
    pthread_mutex_lock(&renderLock);
    [_windows[window.level] addObject:window];
    pthread_mutex_unlock(&renderLock);
    if(window.level == kCGNormalWindowLevelKey && window.app != nil) {
        const char *bid = [[window.app bundleID] UTF8String];
        fprintf(stderr, "[WS] FRONT app=%s win=%u\n", bid ? bid : "unknown", (unsigned)window.number);
        fflush(stderr);
    }
    [self markDamageRect:NSInsetRect(window.geometry, -16, -16)];
}

-(void)removeWindowByLevel:(WSWindowRecord *)window {
    if(window == nil) return;
    if(logLevel < WS_INFO) fprintf(stderr,"[WS] REM win=%u lvl=%d frame=%d,%d %dx%d\n",
        (unsigned)window.number,(int)window.level,
        (int)window.frame.origin.x,(int)window.frame.origin.y,
        (int)window.frame.size.width,(int)window.frame.size.height);

    if(window.level < 0 || window.level >= kCGNumReservedWindowLevels) {
        /* A level outside the table means the window is invisible to hit-testing AND
         * drawing -- a silent no-op that is very hard to diagnose from the app side. */
        fprintf(stderr,"[WS] DROPPED window level=%d (table size %d)\n",
            (int)window.level, kCGNumReservedWindowLevels);
        return;
    }
    pthread_mutex_lock(&renderLock);
    [_windows[window.level] removeObject:window];
    pthread_mutex_unlock(&renderLock);
    [self markDamageRect:NSInsetRect(window.geometry, -16, -16)];
}

-(void)removeWindowFromAllLevels:(WSWindowRecord *)window {
    const char *bid = (window.app && [window.app bundleID]) ? [[window.app bundleID] UTF8String] : "(nil)";
    fprintf(stderr,"[WS] DESTROY win=%u app=%s lvl=%d frame=%d,%d %dx%d\n",
        (unsigned)window.number, bid, (int)window.level,
        (int)window.frame.origin.x,(int)window.frame.origin.y,
        (int)window.frame.size.width,(int)window.frame.size.height);
    if(logLevel >= WS_INFO)
        NSLog(@"removeWindowFromAllLevels %@", window);
    pthread_mutex_lock(&renderLock);
    for(int i = 0; i < kCGNumReservedWindowLevels; ++i)
        [_windows[i] removeObject:window];
    pthread_mutex_unlock(&renderLock);
    if(window != nil)
        [self markDamageRect:NSInsetRect(window.geometry, -16, -16)];
}

-(void)setShell:(int)shell {
    curShell = shell;
}

static void *shellSvcLoop(void *arg) {
    WindowServer *ws = (__bridge WindowServer *)arg;
    [ws launchShell:nil];
    return NULL;
}

-(void)launchShell:(id)object {
    int status;
    siginfo_t siginfo = {0};
    NSString *lwPath = nil;
    uid_t uid = 0;
    gid_t gid = 0;

    write(2, "[WS] launchShell entered\n", 25);
    while(curShell != NONE) {
        switch(curShell) {
            case LOADING: {
                static const char *candidates[] = {
                    "/System/Library/CoreServices/WindowServer.app/Contents/Resources/LoadingWindow.app/Contents/ravynOS/LoadingWindow",
                    "/System/Library/CoreServices/WindowServer.app/Contents/Resources/LoadingWindow.app/LoadingWindow",
                    NULL
                };
                const char *exec_path = NULL;
                for(int i = 0; candidates[i] != NULL; ++i) {
                    if(access(candidates[i], X_OK) == 0) {
                        exec_path = candidates[i];
                        break;
                    }
                }
                if(exec_path == NULL) {
                    write(2, "[WS] LoadingWindow not found\n", 29);
                    curShell = LOGINWINDOW;
                    break;
                }

                char msgbuf[256];
                int n = snprintf(msgbuf, sizeof(msgbuf), "[WS] spawning LoadingWindow at %s\n", exec_path);
                write(2, msgbuf, n);

                pid_t pid = fork();
                if(!pid) { // child
                    // Keep root permissions during early boot so Mach IPC succeeds
                    execl(exec_path, "LoadingWindow", (char *)0);
                    write(2, "[WS] execl LoadingWindow failed\n", 32);
                    exit(1);
                } else if(pid < 0) {
                    write(2, "[WS] LoadingWindow fork() failed\n", 33);
                    break;
                }

                n = snprintf(msgbuf, sizeof(msgbuf), "[WS] LoadingWindow spawned as PID %d, waiting\n", pid);
                write(2, msgbuf, n);
                int wret;
                while((wret = waitpid(pid, &status, 0)) < 0 && errno == EINTR) {}
                n = snprintf(msgbuf, sizeof(msgbuf), "[WS] LoadingWindow exited ret=%d status=%d errno=%d\n", wret, status, errno);
                write(2, msgbuf, n);
                if(WIFEXITED(status) && WEXITSTATUS(status) == 0)
                    curShell = LOGINWINDOW;
                break;
            }
            case LOGINWINDOW:
                // FIXME: can we use load_launchd_jobs_at_loginwindow_prompt() here?
                lwPath = [[NSBundle mainBundle] pathForResource:@"LoginWindow" ofType:@"app"];
                if(!lwPath) {
                    NSLog(@"missing LoginWindow.app!");
                    sleep(1);
                    break;
                }
                lwPath = [[NSBundle bundleWithPath:lwPath] executablePath];
                if(!lwPath) {
                    NSLog(@"missing LoginWindow.app!");
                    sleep(1);
                    break;
                }

                int fds[2];
                pipe(fds);
                pid_t pid = fork();
                if(!pid) { // child
                    close(fds[0]);
                    char fdbuf[12];
                    sprintf(fdbuf, "%d", fds[1]);
                    setuid(65534); // nobody
                    execle([lwPath UTF8String], [[lwPath lastPathComponent] UTF8String], fdbuf, NULL, NULL);
                    exit(1);
                } else {
                    /* While it's running, try to read creds from the pipe. Validate them and
                     * set uid if correct. Return error if not and continue
                     */
                    close(fds[1]);

                    fd_set readfds;
                    FD_ZERO(&readfds);
                    FD_SET(fds[0], &readfds);
                    struct timeval tv = {0, 100000};
                    char credbuf[64];
                    BOOL loggedIn = NO;

                    while(!loggedIn && waitpid(pid, &status, WEXITED|WNOHANG) == 0) {
                        FD_SET(fds[0], &readfds);
                        int ret = select(fds[0] + 1, &readfds, NULL, NULL, &tv);
                        switch(ret) {
                            case -1: perror("select");
                                     kill(pid, SIGTERM);
                                     close(fds[0]);
                                     break;
                            case 0: continue;
                        }
                        int bytes = read(fds[0], credbuf, sizeof(credbuf));
                        credbuf[bytes - 1] = 0;
                        char *pass = &credbuf[strlen(credbuf) + 1];
                        if(pass > (credbuf + bytes)) {
                            NSLog(@"Malformed auth input");
                            continue;
                        }

                        struct passwd *pw = getpwnam(credbuf);
                        if(!pw) {
                            if(logLevel >= WS_WARNING)
                                NSLog(@"Bad username or password (%s)", credbuf);
                            write(fds[0], "FAIL", 5);
                            continue;
                        }
                        char *enc = crypt(pass, pw->pw_passwd);
                        if(strcmp(enc, pw->pw_passwd)) {
                            if(logLevel >= WS_WARNING)
                                NSLog(@"Bad username or password (%s)", credbuf);
                            write(fds[0], "FAIL", 5);
                            continue;
                        }

                        // it must be valid since we got here!
                        uid = pw->pw_uid;
                        gid = pw->pw_gid;
                        write(fds[0], "AUTH", 5);
                        close(fds[0]);
                        close(fds[1]);
                        kill(pid, SIGTERM);
                        loggedIn = YES;
                    }

                    if(loggedIn && uid != 0) {
                        if(logLevel >= WS_WARNING)
                            NSLog(@"Logged in user %u:%u", uid, gid);
                        curShell = DESKTOP;
                    } else
                        NSLog(@"LoginWindow exited without authenticating");
                    break;
                }
                break;
            case DESKTOP: {
                static BOOL desktopLaunched = NO;
                if(!desktopLaunched) {
                    desktopLaunched = YES;
                    // Launch Filer
                    if(fork() == 0) {
                        char *argv[] = { "Filer", NULL };
                        char *envp[] = { "RAVYN_BUNDLE_ID=com.ravynos.Filer", NULL };
                        execve("/System/Library/CoreServices/Filer.app/Contents/ravynOS/Filer", argv, envp);
                        _exit(1);
                    }
                    // Launch Dock
                    if(fork() == 0) {
                        char *argv[] = { "Dock", NULL };
                        char *envp[] = { "RAVYN_BUNDLE_ID=com.ravynos.Dock", NULL };
                        execve("/System/Library/CoreServices/Dock.app/Contents/ravynOS/Dock", argv, envp);
                        _exit(1);
                    }
                    // Launch SystemUIServer
                    if(fork() == 0) {
                        char *argv[] = { "SystemUIServer", NULL };
                        char *envp[] = { "RAVYN_BUNDLE_ID=com.ravynos.SystemUIServer", NULL };
                        execve("/System/Library/CoreServices/WindowServer.app/Contents/Resources/SystemUIServer.app/Contents/ravynOS/SystemUIServer", argv, envp);
                        execve("/System/Library/CoreServices/WindowServer.app/Contents/Resources/SystemUIServer.app/SystemUIServer", argv, envp);
                        execve("/System/Library/CoreServices/SystemUIServer.app/Contents/ravynOS/SystemUIServer", argv, envp);
                        _exit(1);
                    }
                }
                sleep(60);
                continue;

            }
            break;
        }

    }
    [[NSThread currentThread] cancel];
}

-(void)performLogout:(uid_t)uid {
      WSAppRecord *app;

      NSString *cmd = [NSString stringWithFormat:
          @"/bin/launchctl remove com.apple.launchd.peruser.%d", uid];
      system([cmd UTF8String]);

      NSEnumerator *appEnum = [apps objectEnumerator];
      while((app = [appEnum nextObject]) != nil)
          kill(app.pid, SIGTERM);
}

/*
 * KEEP THIS RUN LOOP EFFICIENT! It is called every frame to render the entire screen contents.
 */
#define _cursor_height 24
/* Pending bundle launches.  Several clients ask for apps at once (the Dock,
 * the self test, Filer) and the single slot that used to hold the request
 * dropped all but the last one, so those apps never launched.  A small FIFO
 * keeps every request.  The spawn itself happens in the main loop with no
 * lock held: a child forked from a locked section inherits the locked mutex
 * and never completes its launch handshake. */
typedef struct {
    char path[1024];
    char name[256];
    char bundleID[256];
    char args[16][256];
    int argc;
} PendingBundleItem;

#define WS_PENDING_QUEUE_SIZE 32
static PendingBundleItem _pendingQueue[WS_PENDING_QUEUE_SIZE];
static int _pendingHead = 0;
static int _pendingTail = 0;
static int _pendingCount = 0;
static pthread_mutex_t _pendingLock = PTHREAD_MUTEX_INITIALIZER;

/* Resolve a bundle's executable the way the desktop stage does:
 * Contents/ravynOS/<name>, Contents/MacOS/<name> or <bundle>/<name>. */
-(BOOL)resolveBundleExecutable:(NSString *)bundlePath into:(char *)out size:(size_t)size {
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *exeName = [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    if(exeName == nil || [exeName length] == 0)
        exeName = [[bundlePath lastPathComponent] stringByDeletingPathExtension];
    if([exeName hasSuffix:@".app"])
        exeName = [exeName stringByDeletingPathExtension];

    NSMutableArray *names = [NSMutableArray arrayWithObject:exeName];
    NSString *underscore = [exeName stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    if(![names containsObject:underscore]) [names addObject:underscore];
    NSString *spaced = [exeName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    if(![names containsObject:spaced]) [names addObject:spaced];

    for(NSString *name in names) {
        NSString *cands[3] = {
            [NSString stringWithFormat:@"%@/Contents/ravynOS/%@", bundlePath, name],
            [NSString stringWithFormat:@"%@/Contents/MacOS/%@", bundlePath, name],
            [NSString stringWithFormat:@"%@/%@", bundlePath, name]
        };
        for(int i = 0; i < 3; i++) {
            const char *c = [cands[i] UTF8String];
            if(c != NULL && access(c, X_OK) == 0) {
                snprintf(out, size, "%s", c);
                return YES;
            }
        }
    }
    return NO;
}

/* Move a window to the top of its level's stack.  The compositor draws the
 * windows of a level in array order, so the last one is the frontmost. */
-(void)bringWindowToFront:(WSWindowRecord *)winrec {
    if(winrec == nil)
        return;
    if(winrec.level < 0 || winrec.level >= kCGNumReservedWindowLevels)
        return;
    pthread_mutex_lock(&renderLock);
    NSMutableArray *list = _windows[winrec.level];
    if([list containsObject:winrec]) {
        [list removeObject:winrec];
        [list addObject:winrec];
        if(winrec.level == kCGNormalWindowLevelKey && winrec.app != nil) {
            const char *bid = [[winrec.app bundleID] UTF8String];
            fprintf(stderr, "[WS] FRONT app=%s win=%u\n", bid ? bid : "unknown", (unsigned)winrec.number);
            fflush(stderr);
        }
    }
    pthread_mutex_unlock(&renderLock);
    /* The window now covers whatever was in front of it: repaint its area. */
    [self markDamageRect:NSInsetRect(winrec.geometry, -16, -16)];
}

/* An app that is already running must not be forked a second time: the Dock
 * and the self test both "open" apps that launchd already started, and the
 * duplicate instance built a second desktop window and a second Filer window.
 * Activate the existing instance instead (same effect as clicking its Dock
 * tile), and only fork when nothing is registered under that bundle id. */
-(BOOL)activateRunningAppWithBundleID:(NSString *)bundleID {
    if(bundleID == nil)
        return NO;
    pthread_mutex_lock(&appsLock);
    WSAppRecord *app = [apps objectForKey:bundleID];
    if(app == nil || ![app isKindOfClass:[WSAppRecord class]]) {
        pthread_mutex_unlock(&appsLock);
        return NO;
    }
    /* Do not probe with kill(pid, 0): on this libc the empty signal op is not
     * dependable.  The task-death notifier already drops dead app records, and
     * a record without a reply port cannot receive events, so those are the
     * only conditions worth treating as "not running". */
    if([app port] == MACH_PORT_NULL) {
        [apps removeObjectForKey:bundleID];
        pthread_mutex_unlock(&appsLock);
        return NO;
    }
    NSArray *wins = [app windows];
    WSWindowRecord *winrec = nil, *restore = nil;
    for(unsigned x = 0; x < [wins count]; ++x) {
        WSWindowRecord *w = [wins objectAtIndex:x];
        if(w.state != MINIMIZED && w.state != HIDDEN && w.state != CLOSED) { winrec = w; break; }
        if(w.state == MINIMIZED) restore = w;
    }
    if(winrec == nil && restore != nil) {
        restore.state = restore.prevState;
        winrec = restore;
    }
    /* Activating an app shows its windows and puts them in front of the
     * others, otherwise the launch request looks like it did nothing. */
    for(unsigned x = 0; x < [wins count]; ++x) {
        WSWindowRecord *w = [wins objectAtIndex:x];
        if(w.state == CLOSED || w.state == HIDDEN)
            continue;
        if(w.state == MINIMIZED)
            w.state = (w.prevState != MINIMIZED) ? w.prevState : NORMAL;
        w.state = NORMAL;
        [self bringWindowToFront:w];
        /* The window was painted before the request (the app is running), so
         * say so again: whoever asked for the app waits for this line to
         * know the window is on screen. */
        if(w.surfaceBuf != NULL &&
           (WSPaintWasFlushed((pid_t)[app pid], (unsigned)w.number) ||
            WSSurfaceHasContent(w.surfaceBuf, w.bufSize))) {
            const char *bid = [[app bundleID] UTF8String];
            fprintf(stderr, "[WS] PAINTED app=%s win=%u\n",
                    bid != NULL ? bid : "unknown", (unsigned)w.number);
            fflush(stderr);
            wsPaintedMarker(bid);
        }
    }
    WSAppRecord *oldApp = curApp;
    curApp = app;
    [self switchFromApp:oldApp toWindow:winrec];
    if(winrec != nil)
        [self updateClientWindowState:winrec];
    struct wsRPCWindow data;
    memset(&data, 0, sizeof(data));
    data.windowID = winrec != nil ? winrec.number : 0;
    data.state = winrec != nil ? winrec.state : 0;
    [self notifyDock:&data length:sizeof(data) withCode:CODE_WINDOW_STATE forApp:app];
    pthread_mutex_unlock(&appsLock);
    fprintf(stderr, "[WS] open bundle: %s already running pid %d, activated\n",
            [bundleID UTF8String], (int)[app pid]);
    wsAppMarker("ACTIVATE", [bundleID UTF8String], (pid_t)[app pid]);
    return YES;
}

/* Queue a bundle launch.  The spawn itself happens in the main loop, with
 * no registry lock held: a child forked from a locked section inherits the
 * locked mutex and never completes its launch handshake. */
-(void)queueBundleLaunch:(NSString *)bundlePath bundleID:(NSString *)bundleID args:(NSArray *)args {
    char exe[1024];
    unsigned i;
    PendingBundleItem item;

    if(bundlePath == nil)
        return;
    /* An app that is already running is activated, not forked again. */
    if(bundleID != nil && [bundleID length] > 0) {
        if([self activateRunningAppWithBundleID:bundleID])
            return;
    }
    if(![self resolveBundleExecutable:bundlePath into:exe size:sizeof(exe)]) {
        fprintf(stderr, "[WS] open bundle: no executable for %s\n", [bundlePath UTF8String]);
        return;
    }

    memset(&item, 0, sizeof(item));
    snprintf(item.path, sizeof(item.path), "%s", exe);
    const char *slash = strrchr(exe, '/');
    snprintf(item.name, sizeof(item.name), "%s", slash ? slash + 1 : exe);
    snprintf(item.bundleID, sizeof(item.bundleID), "%s",
             bundleID != nil ? [bundleID UTF8String] : "com.ravynos.unknown");
    for(i = 0; args != nil && i < [args count]; i++) {
        NSString *a = [args objectAtIndex:i];
        if(item.argc >= 16)
            break;
        if([a isKindOfClass:[NSString class]])
            snprintf(item.args[item.argc], sizeof(item.args[0]), "%s", [a UTF8String]);
        item.argc++;
    }

    pthread_mutex_lock(&_pendingLock);
    if(_pendingCount >= WS_PENDING_QUEUE_SIZE) {
        pthread_mutex_unlock(&_pendingLock);
        fprintf(stderr, "[WS] open bundle: launch queue full, dropping %s\n", item.path);
        return;
    }
    _pendingQueue[_pendingTail] = item;
    _pendingTail = (_pendingTail + 1) % WS_PENDING_QUEUE_SIZE;
    _pendingCount++;
    pthread_mutex_unlock(&_pendingLock);
    fprintf(stderr, "[WS] open bundle: queued %s\n", item.path);
}

/* Global screen capture shortcut (Cmd+Shift+3/4/5): launch Screenshot.app
 * with the requested mode. */
-(void)captureScreenshotWithMode:(int)mode {
    NSString *bundlePath = @"/Applications/Utilities/Screenshot.app";
    NSString *modeArg = mode == 3 ? @"full" : (mode == 4 ? @"rect" : @"hud");
    [self queueBundleLaunch:bundlePath bundleID:@"com.ravynos.Screenshot"
                        args:[NSArray arrayWithObjects:@"--mode", modeArg, nil]];
}

/* Runs from the main loop, i.e. with no registry lock held, exactly like the
 * DESKTOP stage that spawns Filer/Dock/SystemUIServer.  One queued launch is
 * taken from the FIFO per call, so a burst of requests all get their app. */
-(void)_spawnPendingBundle {
    PendingBundleItem item;

    pthread_mutex_lock(&_pendingLock);
    if(_pendingCount == 0) {
        pthread_mutex_unlock(&_pendingLock);
        return;
    }
    item = _pendingQueue[_pendingHead];
    _pendingHead = (_pendingHead + 1) % WS_PENDING_QUEUE_SIZE;
    _pendingCount--;
    pthread_mutex_unlock(&_pendingLock);

    pid_t pid = fork();
    if(pid != 0) {
        fprintf(stderr, "[WS] open bundle: forked pid %d (%s)\n", (int)pid, item.path);
        if(pid > 0)
            wsAppMarker("SPAWN", item.bundleID, pid);
        return;
    }

    char idbuf[192];
    snprintf(idbuf, sizeof(idbuf), "RAVYN_BUNDLE_ID=%s", item.bundleID);

    /* argv: the bundle name followed by the bundle's own launch arguments
     * (Info.plist RAVYNLaunchArguments), so an app that needs flags gets
     * them: Chrome dies without --no-sandbox on this kernel. */
    char *argv[24];
    int ac = 0;
    argv[ac++] = item.name;
    for(int i = 0; i < item.argc && ac < 23; i++)
        argv[ac++] = item.args[i];
    argv[ac] = NULL;

    /* Environment: everything WindowServer itself has (HOME, PATH, TMPDIR
     * from launchd) plus the bundle id.  The old one-variable environment
     * left children with no HOME and no TMPDIR. */
    static char *envp[128];
    int ec = 0;
    extern char **environ;
    for(char **e = environ; e && *e && ec < 125; e++)
        envp[ec++] = *e;
    envp[ec++] = idbuf;
    envp[ec] = NULL;

    execve(item.path, argv, envp);
    _exit(1);
}

-(void)run {
    pthread_t shellThread;
    pthread_create(&shellThread, NULL, shellSvcLoop, (__bridge void *)self);

    // FIXME: lock this to vsync of actual display
    pthread_mutex_lock(&renderLock);
    O2BitmapContext *ctx = [fb context];
    pthread_mutex_unlock(&renderLock);

    O2ImageRef cursor = NULL;
    NSString *cursorPath = [[NSBundle mainBundle] pathForResource:@"arrowCursor" ofType:@"png"];
    if(!cursorPath)
        cursorPath = @"/System/Library/CoreServices/WindowServer.app/Contents/Resources/arrowCursor.png";
    if([[NSFileManager defaultManager] fileExistsAtPath:cursorPath]) {
        O2ImageSourceRef is = [O2ImageSource newImageSourceWithURL:[NSURL fileURLWithPath:cursorPath] options:nil];
        if(is) {
            cursor = [is createImageAtIndex:0 options:nil];
            fprintf(stderr, "[WS] loaded arrow cursor: %p (%zux%zu)\n",
                cursor, O2ImageGetWidth(cursor), O2ImageGetHeight(cursor));
        }
    }
    if(cursor == NULL)
        write(2, "[WS] using fallback vector cursor\n", 34);
    NSRect cursorRect = NSMakeRect(0, 0, _cursor_height, _cursor_height);

    struct pollfd fds[2];
    fds[0].fd = [input fileDescriptor];
    fds[0].events = POLLIN;
    fds[1].fd = [input keyboardFileDescriptor];
    fds[1].events = POLLIN;
    write(2, "[WS] run loop entered\n", 22);
    int frame_count = 0;
    NSPoint lastCursorPos = cursorRect.origin;
    BOOL haveCursorPos = NO;
    [self markFullSceneDirty];
    while(ready == YES) {
        [self _spawnPendingBundle];
        int nfds = (fds[0].fd >= 0) + (fds[1].fd >= 0);
        if(nfds > 0 && poll(fds, 2, 16) > 0) {
            /* /dev/mouse reports itself readable even with no packet queued, so
             * this branch fires every iteration.  Sleeping only when nothing
             * was consumed stops the loop pinning a whole CPU. */
            if([input run:self] == 0)
                usleep(2000);
        } else {
            usleep(16666); // ~60 FPS
        }
        if(input)
            cursorRect.origin = [input pointerPos];
        else
            cursorRect.origin = NSMakePoint(_geometry.size.width / 2, _geometry.size.height / 2);

        /* Pointer movement invalidates only the old and new cursor boxes. Every
         * other scene change (window create/move/resize/state, client content
         * flush, cursor hide/show) marks its own damage.  Without this the
         * compositor repainted all of 1080p and memcpy'd the whole scanout every
         * iteration, leaving a single-vCPU TCG guest no cycles for the apps. */
        if(!haveCursorPos || !NSEqualPoints(lastCursorPos, cursorRect.origin)) {
            NSRect oldCursor = WSCursorDamageRect(lastCursorPos.x, lastCursorPos.y);
            NSRect newCursor = WSCursorDamageRect(cursorRect.origin.x, cursorRect.origin.y);
            [self markDamageRect:haveCursorPos ? NSUnionRect(oldCursor, newCursor) : newCursor];
            lastCursorPos = cursorRect.origin;
            haveCursorPos = YES;
        }

        // FIXME: handle multiple displays here. Use a thread per display?
        pthread_mutex_lock(&renderLock);
        ctx = [fb context];
        pid_t capturedPID = [fb captured];
        if(capturedPID == 0) {
            pthread_mutex_lock(&damageLock);
            NSRect damage = NSIntersectionRect(_damageRect, _geometry);
            _damageRect = NSZeroRect;
            _sceneDirty = NO;
            pthread_mutex_unlock(&damageLock);

            if(!NSIsEmptyRect(damage)) {
            O2ContextSaveGState(ctx);
            O2ContextClipToRect(ctx, (O2Rect)damage);
            O2ContextSetRGBFillColor(ctx, 0.15, 0.25, 0.35, 1);
            O2ContextFillRect(ctx, (O2Rect)damage);
            for(int level = 0; level < kCGNumReservedWindowLevels; ++level) {
                NSArray *wins = [_windows[level] copy];
                NSInteger count = [wins count];
                for(int i = 0; i < count; ++i) {
                    WSWindowRecord *win = [wins objectAtIndex:i];
                    if(win.state == HIDDEN || win.state == MINIMIZED || win.state == CLOSED)
                        continue;
                    /* A window whose shm surface never mapped (shm_open or
                     * mmap failed) has a NULL surface; drawing it faults. */
                    if(win.surface != NULL) {
                        /* Paint readiness: announce a window once its surface
                         * holds real content, so the screenshot harness can
                         * wait for it instead of guessing.  A window whose
                         * pixels are all zero is NOT announced unless the
                         * client flushed it while NORMAL (which happens right
                         * after it drew, even an all-black window). */
                        if(win.surfaceBuf != NULL && win.state == NORMAL) {
                            WSAppRecord *winApp = (win.app != nil &&
                                    [win.app isKindOfClass:[WSAppRecord class]]) ?
                                (WSAppRecord *)win.app : nil;
                            pid_t winPid = winApp != nil ? (pid_t)[winApp pid] : 0;
                            BOOL announce = NO;
                            pthread_mutex_lock(&sPaintLock);
                            int entry = -1;
                            for(int z = 0; z < sPaintCount; z++) {
                                if(sPaintTable[z].pid == winPid &&
                                   sPaintTable[z].number == (unsigned)win.number) { entry = z; break; }
                            }
                            if(entry < 0 && sPaintCount < WS_PAINT_MAX) {
                                entry = sPaintCount++;
                                sPaintTable[entry].pid = winPid;
                                sPaintTable[entry].number = (unsigned)win.number;
                                sPaintTable[entry].flushed = 0;
                                sPaintTable[entry].announced = 0;
                            }
                            if(entry >= 0 && !sPaintTable[entry].announced) {
                                if(sPaintTable[entry].flushed ||
                                   WSSurfaceHasContent(win.surfaceBuf, win.bufSize)) {
                                    sPaintTable[entry].announced = 1;
                                    announce = YES;
                                }
                            }
                            pthread_mutex_unlock(&sPaintLock);
                            if(announce) {
                                NSString *bid = winApp != nil ? [winApp bundleID] : nil;
                                const char *bidc = (bid != nil) ? [bid UTF8String] : NULL;
                                fprintf(stderr, "[WS] PAINTED app=%s win=%u\n",
                                        bidc != NULL ? bidc : "unknown",
                                        (unsigned)win.number);
                                fflush(stderr);
                                wsPaintedMarker(bidc);
                            }
                        }
                        if(level >= kCGNormalWindowLevelKey && level <= kCGFloatingWindowLevelKey) {
                            for(int s = 3; s >= 1; --s) {
                                float d = (float)s * 2.0f;
                                float x = win.geometry.origin.x;
                                float y = win.geometry.origin.y;
                                float w = win.geometry.size.width;
                                float h = win.geometry.size.height;
                                O2ContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 0.10f);
                                O2ContextFillRect(ctx, NSMakeRect(x - d, y - d, w + d * 2.0f, d));
                                O2ContextFillRect(ctx, NSMakeRect(x - d, y + h, w + d * 2.0f, d));
                                O2ContextFillRect(ctx, NSMakeRect(x - d, y, d, h));
                                O2ContextFillRect(ctx, NSMakeRect(x + w, y, d, h));
                            }
                        }
                        if(level == kCGNormalWindowLevelKey && (win.styleMask & NSTitledWindowMask) &&
                           win.geometry.size.width > 20 && win.geometry.size.height > 20) {
                            O2ContextSaveGState(ctx);
                            WSAddRoundRectPath(ctx, win.geometry, 8.0f);
                            O2ContextClip(ctx);
                            [ctx drawImage:win.surface inRect:win.geometry];
                            O2ContextRestoreGState(ctx);
                            // Subtle 1px border stroke around normal titled windows
                            O2ContextSetRGBStrokeColor(ctx, 0.0f, 0.0f, 0.0f, 0.22f);
                            O2ContextSetLineWidth(ctx, 1.0f);
                            WSAddRoundRectPath(ctx, NSInsetRect(win.geometry, 0.5f, 0.5f), 8.0f);
                            O2ContextStrokePath(ctx);
                        } else {
                            [ctx drawImage:win.surface inRect:win.geometry];
                        }
                    }
                }
            }

                if(cursorHideCount == 0) {
                    WSDrawArrowCursor(ctx, cursorRect.origin.x, cursorRect.origin.y);
                }
                O2ContextRestoreGState(ctx);
                /* What the frame about to be presented puts on top, logged
                 * with its damage rect.  This is the compositor's own answer
                 * to "which window is frontmost", and it is the only way to
                 * tell a z-order mistake from a stale frame: a screenshot that
                 * disagrees with the last line before it was taken is a
                 * present/scanout problem, one that agrees is a z-order
                 * problem.  Throttled to a change or every 60 presents so a
                 * repainting client cannot drown the console. */
                {
                    static char diagLast[128] = "";
                    static int diagPresents = 0;
                    NSArray *diagWins = _windows[kCGNormalWindowLevelKey];
                    const char *diagFront = "(none)";
                    for(NSInteger di = (NSInteger)[diagWins count] - 1; di >= 0; --di) {
                        WSWindowRecord *dw = [diagWins objectAtIndex:(NSUInteger)di];

                        if(dw.state == HIDDEN || dw.state == MINIMIZED || dw.state == CLOSED)
                            continue;
                        WSAppRecord *da = (dw.app != nil &&
                                [dw.app isKindOfClass:[WSAppRecord class]]) ?
                            (WSAppRecord *)dw.app : nil;
                        NSString *db = (da != nil) ? [da bundleID] : nil;

                        diagFront = (db != nil) ? [db UTF8String] : "unknown";
                        break;
                    }
                    if(strcmp(diagFront, diagLast) != 0 || diagPresents >= 60) {
                        fprintf(stderr, "[WS] PRESENT front=%s win=%u rect=%d,%d %dx%d\n",
                                diagFront, (unsigned)frame_count,
                                (int)damage.origin.x, (int)damage.origin.y,
                                (int)damage.size.width, (int)damage.size.height);
                        fflush(stderr);
                        strncpy(diagLast, diagFront, sizeof(diagLast) - 1);
                        diagLast[sizeof(diagLast) - 1] = '\0';
                        diagPresents = 0;
                    }
                    ++diagPresents;
                }
                [fb drawRect:damage];
            }
        } else {
            [fb draw];
        }
        pthread_mutex_unlock(&renderLock);
        ++frame_count;
    }
}

- (void)rpcMainDisplayID:(PortMessage *)msg {
    uint32_t ID = [(WSDisplay *)fb getDisplayID];
    struct wsRPCSimple reply = { kCGMainDisplayID, sizeof(uint32_t)*4, ID, 0, 0, 0 };
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

- (void)rpcGetOnlineDisplayList:(PortMessage *)msg {
    size_t size = sizeof(struct wsRPCBase) + sizeof(uint32_t)*[displays count];
    uint8_t *list = malloc(size);
    struct wsRPCBase *p = (struct wsRPCBase *)list;
    p->code = kCGGetOnlineDisplayList;
    p->len = 0;
    uint32_t *q = (uint32_t *)(list + sizeof(struct wsRPCBase));
    int j = 0;
    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if([d isOnline])
            q[j++] = [d getDisplayID];
    }
    p->len = j * sizeof(uint32_t);
    [self sendInlineData:list length:size withCode:MSG_ID_RPC toPort:msg->descriptor.name];
    free(list);
}

- (void)rpcGetActiveDisplayList:(PortMessage *)msg {
    size_t size = sizeof(struct wsRPCBase) + sizeof(uint32_t)*[displays count];
    uint8_t *list = malloc(size);
    struct wsRPCBase *p = (struct wsRPCBase *)list;
    p->code = kCGGetActiveDisplayList;
    p->len = 0;
    uint32_t *q = (uint32_t *)(list + sizeof(struct wsRPCBase));
    int j = 0;
    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if([d isActive])
            q[j++] = [d getDisplayID];
    }
    p->len = j * sizeof(uint32_t);
    [self sendInlineData:list length:size withCode:MSG_ID_RPC toPort:msg->descriptor.name];
    free(list);
}

- (void)rpcGetDisplaysWithOpenGLDisplayMask:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    CGOpenGLDisplayMask mask = args->val1;

    size_t size = sizeof(struct wsRPCBase) + sizeof(uint32_t)*[displays count];
    uint8_t *list = malloc(size);
    struct wsRPCBase *p = (struct wsRPCBase *)list;
    p->code = kCGGetDisplaysWithOpenGLDisplayMask;
    p->len = 0;
    uint32_t *q = (uint32_t *)(list + sizeof(struct wsRPCBase));
    int j = 0;
    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if([d openGLMask] & mask)
            q[j++] = [d getDisplayID];
    }
    p->len = j * sizeof(uint32_t);
    [self sendInlineData:list length:size withCode:MSG_ID_RPC toPort:msg->descriptor.name];
    free(list);
}

- (void)rpcGetDisplaysWithPoint:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    NSPoint point = NSMakePoint(args->val1, args->val2);

    size_t size = sizeof(struct wsRPCBase) + sizeof(uint32_t)*[displays count];
    uint8_t *list = malloc(size);
    struct wsRPCBase *p = (struct wsRPCBase *)list;
    p->code = kCGGetDisplaysWithPoint;
    p->len = 0;
    uint32_t *q = (uint32_t *)(list + sizeof(struct wsRPCBase));
    int j = 0;
    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if(NSPointInRect(point, [d geometry])) // FIXME: this should refer to global coordinates
            q[j++] = [d getDisplayID];
    }
    p->len = j * sizeof(uint32_t);
    [self sendInlineData:list length:size withCode:MSG_ID_RPC toPort:msg->descriptor.name];
    free(list);
}

- (void)rpcGetDisplaysWithRect:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    NSRect rect = NSMakeRect(args->val1, args->val2, args->val3, args->val4);

    size_t size = sizeof(struct wsRPCBase) + sizeof(uint32_t)*[displays count];
    uint8_t *list = malloc(size);
    struct wsRPCBase *p = (struct wsRPCBase *)list;
    p->code = kCGGetDisplaysWithRect;
    p->len = 0;
    uint32_t *q = (uint32_t *)(list + sizeof(struct wsRPCBase));
    int j = 0;
    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if(NSIntersectsRect([d geometry], rect)) // FIXME: this should refer to global coordinates
            q[j++] = [d getDisplayID];
    }
    p->len = j * sizeof(uint32_t);
    [self sendInlineData:list length:size withCode:MSG_ID_RPC toPort:msg->descriptor.name];
    free(list);
}

- (void)rpcOpenGLDisplayMaskToDisplayID:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    CGOpenGLDisplayMask mask = args->val1;

    struct wsRPCSimple reply = {0};
    reply.base.code = kCGOpenGLDisplayMaskToDisplayID;
    reply.val1 = kCGNullDirectDisplay;
    reply.base.len = 4;

    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if([d openGLMask] & mask)
            reply.val1 = [d getDisplayID];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

- (void)rpcDisplayIDToOpenGLDisplayMask:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    CGDirectDisplayID ID = args->val1;

    struct wsRPCSimple reply = {0};
    reply.base.code = kCGDisplayIDToOpenGLDisplayMask;
    reply.base.len = 4;

    for(int i = 0; i < [displays count]; ++i) {
        WSDisplay *d = [displays objectAtIndex:i];
        if([d getDisplayID] == ID)
            reply.val1 = [d openGLMask];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

- (void)rpcDisplayCapture:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    WSDisplay *display = [self displayWithID:args->val1];
    struct wsRPCSimple reply = { {kCGDisplayCaptureWithOptions, 4}, kCGErrorSuccess };
    if(!display || [display capture:msg->pid withOptions:args->val2] != YES)
        reply.val1 = kCGErrorFailure;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

- (void)rpcDisplayRelease:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    WSDisplay *display = [self displayWithID:args->val1];
    struct wsRPCSimple reply = { {kCGDisplayRelease, 4}, kCGErrorSuccess };
    if(!display)
        reply.val1 = kCGErrorFailure;
    else
        [display releaseCapture];
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

- (void)rpcCaptureAllDisplays:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    WSDisplay *display = nil;
    struct wsRPCSimple reply = { {kCGCaptureAllDisplaysWithOptions, 4}, kCGErrorSuccess };
    for(int i = 0; i < [displays count]; ++i) {
        display = [displays objectAtIndex:i];
        if([display capture:msg->pid withOptions:args->val1] != YES) {
            [displays makeObjectsPerformSelector:@selector(releaseCapture)];
            reply.val1 = kCGErrorFailure;
            break;
        }
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

- (void)rpcReleaseAllDisplays:(PortMessage *)msg {
    [displays makeObjectsPerformSelector:@selector(releaseCapture)];
    struct wsRPCSimple reply = { {kCGReleaseAllDisplays, 4}, kCGErrorSuccess };
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

/* Conceptually, this function returns a pointer to the graphics context
 * owned by WindowServer, that the client app can then write to. Apple
 * probably does this with Mach shared memory, which we don't have. We do
 * it with SysV SHM segments
 */
- (void)rpcDisplayGetDrawingContext:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayGetDrawingContext, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.val1 = [display getCapturedContextID];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

// FIXME: I think this is supposed to be only for apps that have captured the display?
- (void)rpcDisplayCreateImageForRect:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayCreateImageForRect, 4}, 0 };
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        O2Rect rect;
        rect.origin.x = (args->val2 & 0xFFFF0000) >> 16;
        rect.origin.y = (args->val2 & 0xFFFF);
        rect.size.width = (args->val3 & 0xFFFF0000) >> 16;
        rect.size.height = (args->val3 & 0xFFFF);
        O2ImageRef img = [display imageForRect:rect];
        int imglen = 0;
        if(img) {
            imglen = O2ImageGetBytesPerRow(img) * O2ImageGetHeight(img);
            reply.val1 = shmget(args->val1 ^ random(), imglen, IPC_CREAT|0666);
        }
        if(reply.val1) {
            uint8_t *p = shmat(reply.val1, NULL, 0);
            if(!p)
                shmctl(reply.val1, IPC_RMID, NULL);
            else {
                memcpy(p, [img directBytes], imglen);
                shmdt(p);
            }
        }
        if(img)
            O2ImageRelease(img);
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

/* Copy one window's surface into a SysV shared memory segment.  args->val1 is
 * the window number, or 0 for the topmost visible normal window that is not
 * the caller's own.  Reply: val1 = shmid (0 on failure), val2 = width,
 * val3 = height, val4 = bytes per row. */
-(void)rpcWindowCreateImage:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kWSWindowCreateImage, 16}, 0, 0, 0, 0 };
    WSWindowRecord *target = nil;
    int level, i;
    pid_t callerPID = msg->pid;

    pthread_mutex_lock(&renderLock);
    for(level = kCGNumReservedWindowLevels - 1; level >= 0 && target == nil; --level) {
        NSArray *wins = _windows[level];
        NSInteger count = [wins count];

        for(i = 0; i < count; ++i) {
            WSWindowRecord *win = [wins objectAtIndex:i];

            if(win.state == HIDDEN || win.state == MINIMIZED || win.state == CLOSED)
                continue;
            if(win.surface == NULL || win.surfaceBuf == NULL)
                continue;
            if(args->val1 != 0) {
                if((uint32_t)[win number] == args->val1)
                    target = win;
            } else {
                WSAppRecord *owner = win.app;
                if(owner != nil && [owner pid] == callerPID)
                    continue;
                if(win.level >= kCGDockWindowLevelKey)
                    continue;
                target = win;
            }
            if(target != nil)
                break;
        }
    }

    if(target != nil) {
        int w = (int)target.geometry.size.width;
        int h = (int)target.geometry.size.height;
        int bpr = (int)((size_t)w * 4);
        size_t imglen = (size_t)bpr * (size_t)h;
        int shmid = shmget(IPC_PRIVATE, imglen, IPC_CREAT | 0666);

        if(shmid >= 0) {
            uint8_t *p = shmat(shmid, NULL, 0);
            if(p == NULL) {
                shmctl(shmid, IPC_RMID, NULL);
            } else {
                /* The window surface is BGRA in window coordinates; copy the
                 * live pixels straight out of the mapped buffer. */
                size_t copyLen = imglen;
                size_t surfaceBytes = (size_t)bpr * (size_t)h;

                if(target.bufSize < copyLen)
                    copyLen = MIN(surfaceBytes, (size_t)target.bufSize);
                memcpy(p, target.surfaceBuf, copyLen);
                shmdt(p);
                reply.val1 = (uint32_t)shmid;
                reply.val2 = (uint32_t)w;
                reply.val3 = (uint32_t)h;
                reply.val4 = (uint32_t)bpr;
            }
        }
    }
    pthread_mutex_unlock(&renderLock);

    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

/* Screen position of the pointer.  Clients need this to track the cursor
 * outside their own windows (the Dock's autohide, for one); NSEvent only ever
 * sees the last event delivered to the process. */
-(void)rpcGetPointerPosition:(PortMessage *)msg {
    struct wsRPCSimple reply = { {kWSGetPointerPosition, 8}, 0, 0, 0, 0 };

    if(input != nil) {
        NSPoint p = [input pointerPos];
        reply.val1 = (uint32_t)(int32_t)p.x;
        reply.val2 = (uint32_t)(int32_t)p.y;
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

/* The topmost visible window under a screen point.  A drag session uses it
 * to find the window that is under the cursor. */
-(void)rpcDragHitTest:(PortMessage *)msg {
    struct wsRPCDragHitTest *args = (struct wsRPCDragHitTest *)msg->data;
    struct wsRPCDragHitTest reply;
    WSAppRecord *app = nil;
    WSWindowRecord *win;

    memset(&reply, 0, sizeof(reply));
    reply.base.code = kWSDragHitTest;
    reply.base.len = 0;
    reply.x = args->x;
    reply.y = args->y;

    win = [self windowUnderPointer:NSMakePoint(args->x, args->y) app:&app];
    if(win != nil) {
        reply.windowID = (uint32_t)[win number];
        reply.pid = app != nil ? [app pid] : 0;
        reply.found = 1;
    }

    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

// Configuring Displays
-(void)rpcCompleteDisplayConfiguration:(PortMessage *)msg {
    struct _CGDisplayConfigInner *inner = (struct _CGDisplayConfigInner *)msg->data;
    struct wsRPCSimple reply = { {kCGCompleteDisplayConfiguration, 4}, 0 };

    if(logLevel >= WS_INFO)
        NSLog(@"configuring displays. rpc={%u %u}, length %u option %u", 
                inner->rpc.code, inner->rpc.len, inner->length, inner->option);
    int i = sizeof(struct _CGDisplayConfigInner);

    CGError ret = kCGErrorSuccess; // let's be optimistic
 
    while(i < inner->length) {
        char *p = (char *)inner + i;
        int opcode = *(uint32_t *)p;
        switch(opcode) {
            case CGDISPCFG_MIRROR: {
                struct _CGDispCfgMirror *op = p;
                if(logLevel >= WS_INFO)
                    NSLog(@"mirroring: %x %x", op->display, op->primary);
                WSDisplay *display = [self displayWithID:op->display];
                WSDisplay *primary = [self displayWithID:op->primary];
                i += sizeof(struct _CGDispCfgMirror);
                if(display == nil || primary == nil) {
                    ret = kCGErrorIllegalArgument;
                    break;
                }
                if([display mirror:primary] == NO)
                    ret = kCGErrorFailure;
                break;
            }
            case CGDISPCFG_ORIGIN: {
                struct _CGDispCfgOrigin *op = p;
                if(logLevel >= WS_INFO)
                    NSLog(@"set origin: %x %d,%d", op->display, op->x, op->y);
                i += sizeof(struct _CGDispCfgOrigin);
                WSDisplay *display = [self displayWithID:op->display];
                if(display == nil) {
                    ret = kCGErrorIllegalArgument;
                    break;
                }
                if([display setOriginX:op->x Y:op->y] == NO)
                    ret = kCGErrorFailure;
                break;
            }
            case CGDISPCFG_MODE: {
                struct _CGDispCfgMode *op = p;
                if(logLevel >= WS_INFO)
                    NSLog(@"set mode: %x %u %u %.2f %08x", op->display, op->mode.width,
                            op->mode.height, op->mode.refresh, op->mode.flags);
                WSDisplay *display = [self displayWithID:op->display];
                i += sizeof(struct _CGDispCfgMode);
                if(display == nil) {
                    ret = kCGErrorIllegalArgument;
                    break;
                }
                if([display setMode:&op->mode] == NO)
                    ret = kCGErrorFailure;
                break;
            }
            default:
                 NSLog(@"Unknown display configuration command");
                 i = inner->length;
                 break;
        };

        if(ret != kCGErrorSuccess)
            break;
    }

    if(ret == kCGErrorSuccess) {
        [displays makeObjectsPerformSelector:
            inner->option == kCGConfigureForAppOnly
                ? @selector(saveAppConfig)
                : inner->option == kCGConfigureForSession
                    ? @selector(saveSessionConfig)
                    : @selector(savePermanentConfig)
            withObject:nil];
    } else {
        // FIXME: roll back any changes to our saved config if something failed
    }

    reply.val1 = ret;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcRestorePermanentDisplayConfiguration:(PortMessage *)msg {
    [displays makeObjectsPerformSelector:@selector(restorePermanentConfig) withObject:nil];
}

// Getting the Display Configuration
-(void)rpcDisplayCopyColorSpace:(PortMessage *)msg {
    // FIXME: not implemented yet
}

-(void)rpcDisplayStateFlags:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayStateFlags, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.val1 = [display flags];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayMirrorsDisplay:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayMirrorsDisplay, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        WSDisplay *primary = [display mirrorOf];
        if(primary)
            reply.val1 = [primary getDisplayID];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayModelNumber:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayModelNumber, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.val1 = [display modelNumber];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayPrimaryDisplay:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayPrimaryDisplay, 4}, args->val1};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        WSDisplay *primary = [display primaryDisplay];
        if(primary)
            reply.val1 = [primary getDisplayID];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayRotation:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayRotation, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.val1 = (uint32_t)[display rotation];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayScreenSize:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayScreenSize, 8}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        CGSize size = [display screenSizeMM];
        reply.val1 = (uint32_t)size.width;
        reply.val2 = (uint32_t)size.height;
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplaySerialNumber:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplaySerialNumber, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.val1 = [display serialNumber];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayUnitNumber:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayUnitNumber, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.val1 = [displays indexOfObject:display];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayVendorNumber:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayVendorNumber, 4}, 0};
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.val1 = [display vendorNumber];
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

// Retrieving Display Parameters
-(void)rpcDisplayBounds:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplayBounds, 16}, 0, 0, 0, 0 };
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        CGRect rect = [display geometry];
        reply.val1 = rect.origin.x;
        reply.val2 = rect.origin.y;
        reply.val3 = rect.size.width;
        reply.val4 = rect.size.height;
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

// Creating and Managing Display Modes
-(void)rpcDisplayCopyDisplayMode:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct {
        struct wsRPCBase base;
        struct CGDisplayMode mode;
    } reply;
    reply.base.code = kCGDisplayCopyDisplayMode;
    reply.base.len = 0;
    
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        reply.base.len = sizeof(struct CGDisplayMode);
        struct CGDisplayMode *mode = [display currentMode];
        memcpy(&reply.mode, mode, sizeof(struct CGDisplayMode));
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayCopyAllDisplayModes:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct {
        struct wsRPCBase base;
        struct CGDisplayMode mode[32];
    } reply;
    reply.base.code = kCGDisplayCopyAllDisplayModes;
    reply.base.len = 0;
    
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        CFArrayRef allModes = [display allModes];
        for(int i = 0; i < CFArrayGetCount(allModes); ++i) {
            memcpy(&reply.mode[i], CFArrayGetValueAtIndex(allModes, i), sizeof(struct CGDisplayMode));
            reply.base.len += sizeof(struct CGDisplayMode);
        }
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplaySetDisplayMode:(PortMessage *)msg {
    struct wsRPCSimple *args = (struct wsRPCSimple *)msg->data;
    struct wsRPCSimple reply = { {kCGDisplaySetDisplayMode, 4}, kCGErrorIllegalArgument, 0, 0, 0 };
    
    WSDisplay *display = [self displayWithID:args->val1];
    if(display) {
        struct CGDisplayMode *mode = &(args->val2);
        if([display setMode:mode]) {
            reply.val1 = kCGErrorSuccess;
            /* Present the new logical size immediately: repaint everything and
             * clear the scanout so stale pixels of the old size do not show. */
            _geometry.size = NSMakeSize(mode->width, mode->height);
            [self markFullSceneDirty];
            [self markDamageRect:_geometry];
        } else
            reply.val1 = kCGErrorFailure;
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

// Adjusting Display Gamma
-(void)rpcSetDisplayTransferByFormula:(PortMessage *)msg {
    struct {
        struct wsRPCBase base;
        uint32_t display;
        CGGammaValue vals[9];
    } *data = msg->data;

    int ret = kCGErrorIllegalArgument;
    WSDisplay *display = [self displayWithID:data->display];
    int count = 0;
    if(display)
        count = [display gammaTableSize];

    float *red, *green, *blue;
    float redMin, redMax, redGamma;
    float greenMin, greenMax, greenGamma;
    float blueMin, blueMax, blueGamma;

    if(count > 0) {
        redMin = data->vals[0];
        redMax = data->vals[1];
        redGamma = data->vals[2];
        greenMin = data->vals[3];
        greenMax = data->vals[4];
        greenGamma = data->vals[5];
        blueMin = data->vals[6];
        blueMax = data->vals[7];
        blueGamma = data->vals[8];

        /* count + 1 entries: indices 0..count-1 are filled by the loop below,
         * and the final entry is written at index `count` by the
         * red[count]/green[count]/blue[count] assignments further down.
         * Allocating exactly `count` floats overflowed the heap block by one
         * float (4 bytes) on every call -- the write landed just past the
         * allocation and, depending on the heap layout, corrupted adjacent
         * metadata.  Allocate count + 1. */
        red = malloc(sizeof(float)*(count + 1));
        green = malloc(sizeof(float)*(count + 1));
        blue = malloc(sizeof(float)*(count + 1));
    }

    ret = kCGErrorFailure;
    if(red && green && blue && count > 2) {
        red[0] = redMin + ((redMax - redMin) * pow(0, redGamma)); 
        green[0] = greenMin + ((greenMax - greenMin) * pow(0.0, greenGamma)); 
        blue[0] = blueMin + ((blueMax - blueMin) * pow(0, blueGamma)); 

        float increment = 1.0/(float)(count - 2);
        int j = 1;
        for(float i = increment; j < count && i < 1.0; i += increment) {
            red[j] = redMin + ((redMax - redMin) * pow(i, redGamma));
            green[j] = greenMin + ((greenMax - greenMin) * pow(i, greenGamma));
            blue[j] = blueMin + ((blueMax - blueMin) * pow(i, blueGamma));
            ++j;
        }

        red[count] = redMin + ((redMax - redMin) * pow(1.0, redGamma)); 
        green[count] = greenMin + ((greenMax - greenMin) * pow(1.0, greenGamma)); 
        blue[count] = blueMin + ((blueMax - blueMin) * pow(1.0, blueGamma)); 
        
        ret = [display loadGammaTable:red green:green blue:blue] ? kCGErrorSuccess : kCGErrorFailure;

        free(red);
        free(green);
        free(blue);
    }

    struct wsRPCSimple reply = { {kCGSetDisplayTransferByFormula, 4}, 0, 0, 0, 0 };
    reply.val1 = ret;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcGetDisplayTransferByFormula:(PortMessage *)msg {
    struct {
        struct wsRPCBase base;
        uint32_t display;
        CGGammaValue vals[9];
    } *data = msg->data;

    int ret = kCGErrorIllegalArgument;
    WSDisplay *display = [self displayWithID:data->display];
    int count = 0;
    if(display)
        count = [display gammaTableSize];

    float *red, *green, *blue;
    if(count > 0) {
        red = malloc(sizeof(float)*count);
        green = malloc(sizeof(float)*count);
        blue = malloc(sizeof(float)*count);
    }

    ret = kCGErrorFailure;
    data->vals[0] = 1; // redMin
    data->vals[1] = 0; // redMax
    data->vals[3] = 1; // greenMin
    data->vals[4] = 0; // greenMax
    data->vals[6] = 1; // blueMin
    data->vals[7] = 0; // blueMax

    float gamma;
    if(red && green && blue && count > 0) {
        for(int i = 0; i < count; ++i) {
            gamma = red[i];
            if(gamma < data->vals[0])
                data->vals[0] = gamma; // new minimum
            if(gamma > data->vals[1])
                data->vals[1] = gamma; // new maximum

            gamma = green[i];
            if(gamma < data->vals[3])
                data->vals[0] = gamma; // new minimum
            if(gamma > data->vals[4])
                data->vals[1] = gamma; // new maximum

            gamma = blue[i];
            if(gamma < data->vals[6])
                data->vals[0] = gamma; // new minimum
            if(gamma > data->vals[7])
                data->vals[1] = gamma; // new maximum
        }

        free(red);
        free(green);
        free(blue);

        [display getGammaCoefficientRed:&data->vals[2] green:&data->vals[5] blue:&data->vals[8]];
    }

    data->base.len = 3 * count  * sizeof(CGGammaValue) + 4;
    data->display = ret;
    [self sendInlineData:msg->data length:sizeof(msg->data) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcSetDisplayTransferByTable:(PortMessage *)msg {
    struct wsRPCSimple *args = msg->data;
    int len = args->base.len - 4;
    int entries = len / (3*sizeof(CGGammaValue));

    int ret = kCGErrorIllegalArgument;
    WSDisplay *display = [self displayWithID:args->val1];

    if(display) {
        ret = kCGErrorFailure;
        int count = [display gammaTableSize];

        float *red = malloc(sizeof(float)*count);
        float *green = malloc(sizeof(float)*count);
        float *blue = malloc(sizeof(float)*count);

        float *p = &(args->val2);
        for(int i = 0; i < count && i < entries; ++i) {
            float r = *p++;
            float g = *p++;
            float b = *p++;
            if(red)
                red[i] = r;
            if(green)
                green[i] = g;
            if(blue)
                blue[i] = b;
        }
        if(red && green && blue)
            ret = [display loadGammaTable:red green:green blue:blue] ? kCGErrorSuccess : kCGErrorFailure;
    }

    struct wsRPCSimple reply = { {kCGSetDisplayTransferByTable, 4}, 0, 0, 0, 0 };
    reply.val1 = ret;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcGetDisplayTransferByTable:(PortMessage *)msg {
    struct wsRPCSimple *args = msg->data;
    WSDisplay *display = [self displayWithID:args->val1];

    struct { CGGammaValue r; CGGammaValue g; CGGammaValue b; } *vals = &(args->val1);
    if(display) {
        int count = [display gammaTableSize];

        float *red = malloc(sizeof(float)*count);
        float *green = malloc(sizeof(float)*count);
        float *blue = malloc(sizeof(float)*count);
        if(red && green && blue && count > 0) {
            [display getGammaTablesWithCapacity:count red:red green:green blue:blue];

            int i = 0;
            while(vals < (msg->data + sizeof(msg->data))) {
                vals->r = red[i];
                vals->g = green[i];
                vals->b = blue[i];
                vals += sizeof(CGGammaValue) * 3;
                ++i;
            }
        }

        free(red);
        free(green);
        free(blue);
    }
    args->base.len = (uint8_t *)vals - msg->data;
    [self sendInlineData:msg->data length:sizeof(msg->data) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcSetDisplayTransferByByteTable:(PortMessage *)msg {
    struct wsRPCSimple *args = msg->data;
    int len = args->base.len - 4;
    int entries = len / 3;

    int ret = kCGErrorIllegalArgument;
    WSDisplay *display = [self displayWithID:args->val1];

    if(display) {
        ret = kCGErrorFailure;
        int count = [display gammaTableSize];

        uint8_t *red = malloc(count);
        uint8_t *green = malloc(count);
        uint8_t *blue = malloc(count);

        float *p = &(args->val2);
        for(int i = 0; i < count && i < entries; ++i) {
            uint8_t r = *p++;
            uint8_t g = *p++;
            uint8_t b = *p++;
            if(red)
                red[i] = r;
            if(green)
                green[i] = g;
            if(blue)
                blue[i] = b;
        }
        if(red && green && blue)
            ret = [display load8BitGammaTable:red green:green blue:blue] ? kCGErrorSuccess : kCGErrorFailure;
    }

    struct wsRPCSimple reply = { {kCGSetDisplayTransferByByteTable, 4}, 0, 0, 0, 0 };
    reply.val1 = ret;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayRestoreColorSyncSettings:(PortMessage *)msg {
    [displays makeObjectsPerformSelector:@selector(loadDefaultGamma) withObject:nil];
}

-(void)rpcDisplayGammaTableCapacity:(PortMessage *)msg {
    struct wsRPCSimple *args = msg->data;
    int ret = 0;
    WSDisplay *display = [self displayWithID:args->val1];
    struct wsRPCSimple reply = { {kCGDisplayGammaTableCapacity, 4}, 0, 0, 0, 0 };
    reply.val1 = display ? [display gammaTableSize] : 0;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

// Controlling the Mouse Cursor
-(void)rpcDisplayHideCursor:(PortMessage *)msg {
    int ret = kCGErrorCannotComplete;
    if(msg->pid == [curApp pid]) {
        cursorHideCount++;
        ret = kCGErrorSuccess;
    }
    /* The cursor is drawn only when cursorHideCount == 0, so an unbalanced hide leaves
     * the pointer invisible for every later frame -- exactly what the screendump cursor
     * test reports as "no clusters". Log it because no screenshot reveals this state. */
    fprintf(stderr, "[WS] HIDE pid=%u n=%d\n", msg->pid, cursorHideCount);
    /* The cursor is part of the composited frame now that only damage is
     * repainted, so hiding it has to repaint the box it occupied. */
    if(input != nil) {
        NSPoint cp = [input pointerPos];
        [self markDamageRect:WSCursorDamageRect(cp.x, cp.y)];
    }
    struct wsRPCSimple data;
    data.base.code = kCGDisplayHideCursor;
    data.base.len = 4;
    data.val1 = ret;
    [self sendInlineData:&data length:sizeof(data) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayShowCursor:(PortMessage *)msg {
    int ret = kCGErrorCannotComplete;
    if(msg->pid == [curApp pid]) {
        /* Never let an unbalanced show drive the counter negative: hides from a later
         * app would otherwise be swallowed silently. */
        if(cursorHideCount > 0)
            cursorHideCount--;
        ret = kCGErrorSuccess;
    }
    fprintf(stderr, "[WS] SHOW pid=%u n=%d\n", msg->pid, cursorHideCount);
    if(input != nil) {
        NSPoint cp = [input pointerPos];
        [self markDamageRect:WSCursorDamageRect(cp.x, cp.y)];
    }
    struct wsRPCSimple data;
    data.base.code = kCGDisplayShowCursor;
    data.base.len = 4;
    data.val1 = ret;
    [self sendInlineData:&data length:sizeof(data) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayMoveCursorToPoint:(PortMessage *)msg {
    struct wsRPCSimple *data = msg->data;
    int ret = kCGErrorIllegalArgument;
    WSDisplay *display = [self displayWithID:data->val1];

    if(display) {
        ret = kCGErrorSuccess;
        CGRect bounds = [display geometry];
#if defined(__linux__)
         double x = clipTo(data->val2, bounds.origin.x, bounds.size.width);
         double y = clipTo(data->val3, bounds.origin.y, bounds.size.height);
         [input setPointerPos:NSMakePoint(x, y)];
#endif
    }
    struct wsRPCSimple reply;
    reply.base.code = kCGDisplayMoveCursorToPoint;
    reply.base.len = 4;
    reply.val1 = ret;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcAssociateMouseAndMouseCursorPosition:(PortMessage *)msg {
    struct wsRPCSimple data;
    int ret = kCGErrorFailure;

    WSAppRecord *app = [apps objectForKey:[NSString stringWithCString:msg->bundleID]];
    if(app == nil || ![app isKindOfClass:[WSAppRecord class]])
        app = [self findAppByPID:msg->pid];
    if(app) {
        ret = kCGErrorSuccess;
        [app mouseCursorConnected:((struct wsRPCSimple *)msg->data)->val1];
    }
    data.base.code = kCGAssociateMouseAndMouseCursorPosition;
    data.base.len = 4;
    data.val1 = ret;
    [self sendInlineData:&data length:sizeof(data) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

// FIXME: this should be in Global Coordinate Space (all displays)
-(void)rpcWarpMouseCursorPosition:(PortMessage *)msg {
    struct wsRPCSimple *data = msg->data;
    int ret = kCGErrorIllegalArgument;
    WSDisplay *display = [self displayWithID:data->val1];

    if(display) {
        ret = kCGErrorSuccess;
        CGRect bounds = [display geometry];
#if defined(__linux__)
         double x = clipTo(data->val2, bounds.origin.x, bounds.size.width);
         double y = clipTo(data->val3, bounds.origin.y, bounds.size.height);
         [input setPointerPos:NSMakePoint(x, y)];
#endif
    }

    struct wsRPCSimple reply;
    reply.base.code = kCGWarpMouseCursorPosition;
    reply.base.len = 4;
    reply.val1 = ret;
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcGetLastMouseDelta:(PortMessage *)msg {
    struct wsRPCSimple data;
#if defined(__linux__)
     NSPoint pos = [input pointerPos];
     data.val1 = pos.x;
     data.val2 = pos.y;
#endif
    [self sendInlineData:&data length:sizeof(data) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcWindowCreate:(PortMessage *)msg {
    struct wsRPCSimple reply = { {kWSWindowCreate, 4}, kWSErrorFailure, 0, 0, 0 };

    if(msg->len == sizeof(struct wsRPCWindow)) {
        struct wsRPCWindow *data = (struct wsRPCWindow*)msg->data;
        WSAppRecord *app = [apps objectForKey:[NSString stringWithCString:msg->bundleID]];
        if(app == nil || ![app isKindOfClass:[WSAppRecord class]])
            app = [self findAppByPID:msg->pid];
        if(app != nil) {
            if([self windowCreate:data forApp:app] != 0)
                reply.val1 = kWSErrorSuccess;
        } else {
            NSLog(@"No matching app for rpcWindowCreate! %s %u", msg->bundleID, msg->pid);
        }
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcWindowModifyState:(PortMessage *)msg {
    struct wsRPCSimple reply = { {kWSWindowModifyState, 4}, kWSErrorFailure, 0, 0, 0 };

    if(msg->len == sizeof(struct wsRPCWindow)) {
        struct wsRPCWindow *data = (struct wsRPCWindow*)msg->data;
        WSAppRecord *app = [apps objectForKey:[NSString stringWithCString:msg->bundleID]];
        if(app == nil || ![app isKindOfClass:[WSAppRecord class]])
            app = [self findAppByPID:msg->pid];
        if(app != nil) {
            [self windowModify:data forApp:app];
            reply.val1 = kWSErrorSuccess;
        } else {
            NSLog(@"No matching app for rpcWindowModifyState! %s %u", msg->bundleID, msg->pid);
        }
    }
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcWindowDestroy:(PortMessage *)msg {
    if(msg->len == sizeof(struct wsRPCWindow)) {
        struct wsRPCWindow *data = (struct wsRPCWindow*)msg->data;
        WSAppRecord *app = [apps objectForKey:[NSString stringWithCString:msg->bundleID]];
        if(app == nil || ![app isKindOfClass:[WSAppRecord class]])
            app = [self findAppByPID:msg->pid];
        if(app != nil) {
            WSWindowRecord *winrec = [app removeWindowWithID:data->windowID];
            [self removeWindowFromAllLevels:winrec];
        } else {
            NSLog(@"No matching app for rpcWindowDestroy! %s %u", msg->bundleID, msg->pid);
        }
    }
}

/* App management. If a window number is included (and found), make it the active
 * window. If not, just activate the app and let it choose a window. Dock calls this
 * with window = 0 to activate a running app, and with a windowID to restore a
 * miniaturized window.
 */
-(void)rpcApplicationActivate:(PortMessage *)msg {
    struct wsRPCWindow *data = (struct wsRPCWindow *)msg->data;
    const char *bundleID = (const char *)((msg->data)+sizeof(struct wsRPCWindow));
    WSAppRecord *app = [apps objectForKey:[NSString stringWithCString:bundleID]];
    if(app != nil && ![app isKindOfClass:[WSAppRecord class]])
        app = nil;

    if(app != nil) {
        WSAppRecord *oldApp = curApp;
        WSWindowRecord *winrec = [app windowWithID:data->windowID];
        if(winrec != nil)
            winrec.state = winrec.prevState; // deminiaturize to previous state 
        else {
            // Dock has called this to activate an app. Check for minimized windows.
            NSArray *wins = [app windows];
            WSWindowRecord *restore = nil;
            BOOL visWindows = NO;
            for(int x = 0; x < [wins count]; ++x) {
                winrec = [wins objectAtIndex:x];
                if(winrec.state != MINIMIZED && winrec.state != HIDDEN && winrec.state != CLOSED) {
                    visWindows = YES;
                    break;
                } else if(winrec.state == MINIMIZED)
                    restore = winrec;
            }
            if(!visWindows) {
                winrec = nil;
                if(restore != nil) {
                    // No visible windows but something is minimized - restore it
                    // Otherwise we activate the app and let it choose one
                    restore.state = restore.prevState;
                    winrec = restore;
                }
            }
        }

        if(winrec != nil)
            [self markDamageRect:NSInsetRect(winrec.geometry, -16, -16)];

        curApp = app;
        [self switchFromApp:oldApp toWindow:winrec];

        // now tell Dock and the app about the window state changes
        if(winrec != nil) {
            data->windowID = winrec.number;
            data->state = winrec.state;
            [self updateClientWindowState:winrec];
        }
        [self notifyDock:data length:sizeof(struct wsRPCWindow) 
                withCode:CODE_WINDOW_STATE forApp:app];
    } else {
        NSLog(@"No matching app for rpcApplicationActivate! %s", msg->bundleID);
    }
}

-(void)rpcApplicationList:(PortMessage *)msg {
    WSAppRecord *dock = [apps objectForKey:@"com.ravynos.Dock"];
    if(dock != nil && [dock port] != MACH_PORT_NULL) {
        for(NSString *key in [apps allKeys]) {
            if([key isEqualToString:@"com.ravynos.Dock"] ||
               [key isEqualToString:@"com.ravynos.SystemUIServer"] ||
               [key isEqualToString:@"com.ravynos.LoginWindow"])
                continue;
            WSAppRecord *rec = [apps objectForKey:key];
            if(!rec || ![rec isKindOfClass:[WSAppRecord class]] || rec.pid <= 0)
                continue;
            Message note = {0};
            note.header.msgh_remote_port = [dock port];
            note.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
            note.header.msgh_id = MSG_ID_INLINE;
            note.header.msgh_size = sizeof(note) - sizeof(mach_msg_trailer_t);
            note.code = CODE_APP_LAUNCHED;
            note.pid = rec.pid;
            note.len = [rec.path length];
            strncpy(note.data, [rec.path UTF8String], PATH_MAX);
            strncpy(note.bundleID, [rec.bundleID UTF8String], sizeof(note.bundleID));
            mach_msg((mach_msg_header_t *)&note, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                    sizeof(note) - sizeof(mach_msg_trailer_t),
                    0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
            fprintf(stderr, "[WS] replay CODE_APP_LAUNCHED to Dock for %s pid=%u\n",
                [rec.bundleID UTF8String], rec.pid);
        }
    }
    struct wsRPCSimple reply = { {kWSApplicationList, 4}, kWSErrorSuccess, 0, 0, 0 };
    [self sendInlineData:&reply length:sizeof(reply) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}
- (void)receiveMachMessage {
    ReceiveMessage msg = {0};
    mach_msg_return_t result = mach_msg((mach_msg_header_t *)&msg, MACH_RCV_MSG, 0, sizeof(msg),
        _servicePort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if(result != MACH_MSG_SUCCESS) {
        char errbuf[128];
        int n = snprintf(errbuf, sizeof(errbuf), "[WS] receiveMachMessage error 0x%x\n", result);
        write(2, errbuf, n);
    } else {
        switch(msg.msg.header.msgh_id) {
            case MSG_ID_RPC: { // new style synchronous RPC calls
                /* Serialise against the kqueue thread's app removal; the RPC
                 * handlers resolve an app record and then use it. */
                pthread_mutex_lock(&appsLock);
                mach_port_t reply = MACH_PORT_NULL;
                if(msg.portMsg.msgh_descriptor_count > 0)
                    reply = msg.portMsg.descriptor.name;
                pid_t pid = msg.portMsg.pid;
                NSString *bundleID = nil;
                if(msg.portMsg.bundleID[0] != '\0') {
                    msg.portMsg.bundleID[sizeof(msg.portMsg.bundleID) - 1] = '\0'; // ensure null terminated
                    bundleID = [NSString stringWithCString:msg.portMsg.bundleID];
                } else
                    bundleID = [NSString stringWithFormat:@"unix.%u", pid];
                struct wsRPCBase *base = (struct wsRPCBase *)msg.portMsg.data;

                if(logLevel >= WS_WARNING)
                    NSLog(@"RPC[%@ %u] reply %u data len %u code %u", bundleID, pid, reply, msg.portMsg.len, base->code);
                if(base->len > sizeof(msg.portMsg.data) - sizeof(struct wsRPCBase)) {
                    NSLog(@"RPC[%@ %u] rejected code %u request with oversized data block of %u bytes",
                            base->code, base->len);
                    pthread_mutex_unlock(&appsLock);
                    return;
                }

                switch(base->code) {
                    // Quartz Display Services (CoreGraphics)
                    case kCGMainDisplayID: [self rpcMainDisplayID:&msg.portMsg]; break;
                    case kCGGetOnlineDisplayList: [self rpcGetOnlineDisplayList:&msg.portMsg]; break;
                    case kCGGetActiveDisplayList: [self rpcGetActiveDisplayList:&msg.portMsg]; break;
                    case kCGGetDisplaysWithOpenGLDisplayMask: [self rpcGetDisplaysWithOpenGLDisplayMask:&msg.portMsg];
                                                              break;
                    case kCGGetDisplaysWithPoint: [self rpcGetDisplaysWithPoint:&msg.portMsg]; break;
                    case kCGGetDisplaysWithRect: [self rpcGetDisplaysWithRect:&msg.portMsg]; break;
                    case kCGOpenGLDisplayMaskToDisplayID: [self rpcOpenGLDisplayMaskToDisplayID:&msg.portMsg];
                                                          break;
                    case kCGDisplayIDToOpenGLDisplayMask: [self rpcDisplayIDToOpenGLDisplayMask:&msg.portMsg];
                                                          break;
                    case kCGDisplayCaptureWithOptions: [self rpcDisplayCapture:&msg.portMsg]; break;
                    case kCGDisplayRelease: [self rpcDisplayRelease:&msg.portMsg]; break;
                    case kCGCaptureAllDisplaysWithOptions: [self rpcCaptureAllDisplays:&msg.portMsg]; break;
                    case kCGReleaseAllDisplays: [self rpcReleaseAllDisplays:&msg.portMsg]; break;
                    case kCGDisplayGetDrawingContext: [self rpcDisplayGetDrawingContext:&msg.portMsg]; break;
                    case kCGDisplayCreateImageForRect: [self rpcDisplayCreateImageForRect:&msg.portMsg]; break;
                    case kWSGetPointerPosition: [self rpcGetPointerPosition:&msg.portMsg]; break;
                    case kWSWindowCreateImage: [self rpcWindowCreateImage:&msg.portMsg]; break;
                    case kCGDisplayBounds: [self rpcDisplayBounds:&msg.portMsg]; break;
                    case kCGDisplayStateFlags: [self rpcDisplayStateFlags:&msg.portMsg]; break; 
                    case kCGDisplayMirrorsDisplay: [self rpcDisplayMirrorsDisplay:&msg.portMsg]; break; 
                    case kCGDisplayModelNumber: [self rpcDisplayModelNumber:&msg.portMsg]; break; 
                    case kCGDisplayPrimaryDisplay: [self rpcDisplayPrimaryDisplay:&msg.portMsg]; break; 
                    case kCGDisplayRotation: [self rpcDisplayRotation:&msg.portMsg]; break; 
                    case kCGDisplayScreenSize: [self rpcDisplayScreenSize:&msg.portMsg]; break; 
                    case kCGDisplaySerialNumber: [self rpcDisplaySerialNumber:&msg.portMsg]; break; 
                    case kCGDisplayUnitNumber: [self rpcDisplayUnitNumber:&msg.portMsg]; break; 
                    case kCGDisplayVendorNumber: [self rpcDisplayVendorNumber:&msg.portMsg]; break; 
                    case kCGCompleteDisplayConfiguration: [self rpcCompleteDisplayConfiguration:&msg.portMsg]; break;
                    case kCGRestorePermanentDisplayConfiguration: [self rpcRestorePermanentDisplayConfiguration:&msg.portMsg]; break;
                    case kCGDisplayCopyDisplayMode: [self rpcDisplayCopyDisplayMode:&msg.portMsg]; break;
                    case kCGDisplayCopyAllDisplayModes: [self rpcDisplayCopyAllDisplayModes:&msg.portMsg]; break;
                    case kCGDisplaySetDisplayMode: [self rpcDisplaySetDisplayMode:&msg.portMsg]; break;
                    case kCGSetDisplayTransferByFormula: [self rpcSetDisplayTransferByFormula:&msg.portMsg]; break;
                    case kCGGetDisplayTransferByFormula: [self rpcGetDisplayTransferByFormula:&msg.portMsg]; break;
                    case kCGSetDisplayTransferByTable: [self rpcSetDisplayTransferByTable:&msg.portMsg]; break;
                    case kCGGetDisplayTransferByTable: [self rpcGetDisplayTransferByTable:&msg.portMsg]; break;
                    case kCGSetDisplayTransferByByteTable: [self rpcSetDisplayTransferByByteTable:&msg.portMsg]; break;
                    case kCGDisplayRestoreColorSyncSettings: [self rpcDisplayRestoreColorSyncSettings:&msg.portMsg]; break;
                    case kCGDisplayGammaTableCapacity: [self rpcDisplayGammaTableCapacity:&msg.portMsg]; break;
                    case kCGDisplayHideCursor: [self rpcDisplayHideCursor:&msg.portMsg]; break;
                    case kCGDisplayShowCursor: [self rpcDisplayShowCursor:&msg.portMsg]; break;
                    case kCGDisplayMoveCursorToPoint: [self rpcDisplayMoveCursorToPoint:&msg.portMsg]; break;
                    case kCGAssociateMouseAndMouseCursorPosition: [self rpcAssociateMouseAndMouseCursorPosition:&msg.portMsg]; break;
                    case kCGWarpMouseCursorPosition: [self rpcWarpMouseCursorPosition:&msg.portMsg]; break;
                    case kCGGetLastMouseDelta: [self rpcGetLastMouseDelta:&msg.portMsg]; break;
                    // Window Management (AppKit)
                    case kWSWindowCreate: [self rpcWindowCreate:&msg.portMsg]; break;
                    case kWSWindowDestroy: [self rpcWindowDestroy:&msg.portMsg]; break;
                    case kWSWindowModifyState: [self rpcWindowModifyState:&msg.portMsg]; break;
                    // App management (Dock)
                    case kWSApplicationActivate: [self rpcApplicationActivate:&msg.portMsg]; break;
                    case kWSApplicationList: [self rpcApplicationList:&msg.portMsg]; break;
                    case kWSDragHitTest: [self rpcDragHitTest:&msg.portMsg]; break;
                }
                pthread_mutex_unlock(&appsLock);
                break;
            }
            case MSG_ID_PORT:
            {
                mach_port_t port = msg.portMsg.descriptor.name;
                pid_t pid = msg.portMsg.pid;
                NSString *bundleID = [NSString stringWithCString:msg.portMsg.bundleID];                if(logLevel >= WS_INFO)
                    NSLog(@"Port registration received from %@ pid %u for port %u", bundleID, pid, port);
                pthread_mutex_lock(&appsLock);
                WSAppRecord *rec = [apps objectForKey:bundleID];
                if(!rec) {
                    rec = [WSAppRecord new];
                    rec.bundleID = bundleID;
                    rec.port = port;
                    if([bundleID isEqualToString:@"com.ravynos.SystemUIServer"] ||
                            [bundleID isEqualToString:@"com.ravynos.Dock"])
                        [rec skipSwitcher:YES];
                }
                rec.pid = pid;
                rec.path = _pathForPID(pid);
                if(port != rec.port && logLevel >= WS_WARNING)
                    NSLog(@"Port registration received for %@ pid %u when already registered (%u -> %u)",
                            rec.bundleID, pid, rec.port, port);
                [apps setObject:rec forKey:bundleID];
                pthread_mutex_unlock(&appsLock);


                Message msg = {0};
                pthread_mutex_lock(&appsLock);
                WSAppRecord *dock = [apps objectForKey:@"com.ravynos.Dock"];
                if(dock == nil || ![dock isKindOfClass:[WSAppRecord class]] || [dock port] == MACH_PORT_NULL) {
                    // dock is nil or not ready, skip notification quietly
                } else {
                    msg.header.msgh_remote_port = [dock port];
                    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                    msg.header.msgh_id = MSG_ID_INLINE;
                    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
                    msg.code = CODE_APP_LAUNCHED;
                    msg.pid = pid;
                    msg.len = [rec.path length];
                    strncpy(msg.data, [rec.path UTF8String], PATH_MAX);
                    strncpy(msg.bundleID, [bundleID UTF8String], sizeof(msg.bundleID));
                    mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                            sizeof(msg) - sizeof(mach_msg_trailer_t),
                            0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                }

                if([bundleID isEqualToString:@"com.ravynos.Dock"]) {
                    for(NSString *key in [apps allKeys]) {
                        if([key isEqualToString:@"com.ravynos.Dock"] ||
                           [key isEqualToString:@"com.ravynos.SystemUIServer"] ||
                           [key isEqualToString:@"com.ravynos.LoginWindow"])
                            continue;
                        WSAppRecord *other = [apps objectForKey:key];
                        if(!other || ![other isKindOfClass:[WSAppRecord class]] || other.pid <= 0)
                            continue;
                        Message note = {0};
                        note.header.msgh_remote_port = port;
                        note.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                        note.header.msgh_id = MSG_ID_INLINE;
                        note.header.msgh_size = sizeof(note) - sizeof(mach_msg_trailer_t);
                        note.code = CODE_APP_LAUNCHED;
                        note.pid = other.pid;
                        note.len = [other.path length];
                        strncpy(note.data, [other.path UTF8String], PATH_MAX);
                        strncpy(note.bundleID, [other.bundleID UTF8String], sizeof(note.bundleID));
                        mach_msg((mach_msg_header_t *)&note, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                sizeof(note) - sizeof(mach_msg_trailer_t),
                                0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                        fprintf(stderr, "[WS] Dock registered: replayed launch for %s pid=%u\n",
                            [other.bundleID UTF8String], other.pid);
                    }
                }
                pthread_mutex_unlock(&appsLock);

                if([bundleID isEqualToString:@"com.ravynos.SystemUIServer"] && [stashedMenus count] > 0) {
                    fprintf(stderr, "[WS] SUI registered; stashed menus=%d\n", (int)[stashedMenus count]);
                    /* The apps that sent menus before SUI came up.  Hand them over
                     * so the menu bar has the frontmost app's menus at login
                     * without requiring the user to click around first. */
                    for(NSString *key in stashedMenus) {
                        NSDictionary *entry = [stashedMenus objectForKey:key];
                        NSData *blob = [entry objectForKey:@"Menu"];
                        if(blob == nil)
                            continue;
                        Message menuMsg = {0};
                        menuMsg.header.msgh_remote_port = port;
                        menuMsg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                        menuMsg.header.msgh_id = MSG_ID_INLINE;
                        menuMsg.header.msgh_size = sizeof(menuMsg) - sizeof(mach_msg_trailer_t);
                        menuMsg.code = CODE_MENU_FOR_APP;
                        menuMsg.pid = [[entry objectForKey:@"PID"] intValue];
                        strncpy(menuMsg.bundleID, [key UTF8String], sizeof(menuMsg.bundleID));
                        memcpy(menuMsg.data, [blob bytes], [blob length]);
                        menuMsg.len = (int)[blob length];
                        mach_msg((mach_msg_header_t *)&menuMsg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                sizeof(menuMsg) - sizeof(mach_msg_trailer_t),
                                0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                        fprintf(stderr, "[WS] SUI registered: replayed menu for %s\n",
                            [key UTF8String]);
                    }
                }

                [self watchForProcessExit:pid];

                // A newly-launched app becomes the active one
                if(![rec skipSwitcher]) {
                    [self deactivateApp:curApp];
                    pthread_mutex_lock(&appsLock);
                    curApp = [apps objectForKey:bundleID];
                    pthread_mutex_unlock(&appsLock);
                    [self activateApp:curApp];
                }
                break;
            }
            case MSG_ID_INLINE:
            {
                switch(msg.msg.code) {
                    case CODE_MENU_FOR_APP:
                    {
                        Message menuMsg = {0};
                        if(stashedMenus == nil)
                            stashedMenus = [NSMutableDictionary new];
                        if(msg.msg.len > 0 && (size_t)msg.msg.len <= sizeof(msg.msg.data)) {
                            NSString *bid = [NSString stringWithCString:msg.msg.bundleID];
                            NSData *blob = [NSData dataWithBytes:msg.msg.data length:msg.msg.len];
                            if(bid != nil && blob != nil) {
                                NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
                                    blob, @"Menu",
                                    [NSNumber numberWithInt:msg.msg.pid], @"PID",
                                    nil];
                                [stashedMenus setObject:entry forKey:bid];
                            }
                        }
                        pthread_mutex_lock(&appsLock);
                        WSAppRecord *app = [apps objectForKey:@"com.ravynos.SystemUIServer"];
                        if(app == nil || ![app isKindOfClass:[WSAppRecord class]]) {
                            pthread_mutex_unlock(&appsLock);
                            fprintf(stderr, "[WS] MENU bundle=%s len=%d: SUI not registered, stashed\n",
                                msg.msg.bundleID, msg.msg.len);
                            break;
                        }
                        mach_port_t suiPort = [app port];
                        pthread_mutex_unlock(&appsLock);
                        menuMsg.header.msgh_remote_port = suiPort;
                        menuMsg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                        menuMsg.header.msgh_id = MSG_ID_INLINE;
                        menuMsg.header.msgh_size = sizeof(menuMsg) - sizeof(mach_msg_trailer_t);
                        menuMsg.code = msg.msg.code;
                        menuMsg.pid = msg.msg.pid;
                        strncpy(menuMsg.bundleID, msg.msg.bundleID, sizeof(menuMsg.bundleID));
                        memcpy(menuMsg.data, msg.msg.data, msg.msg.len);
                        menuMsg.len = msg.msg.len;
                        mach_msg((mach_msg_header_t *)&menuMsg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                sizeof(menuMsg) - sizeof(mach_msg_trailer_t),
                                0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                        fprintf(stderr, "[WS] MENU bundle=%s len=%d relayed to SUI\n",
                            msg.msg.bundleID, msg.msg.len);
                        break;
                    }
                    case CODE_ITEM_CLICKED:
                    {
                        if(curApp == nil) {
                            NSLog(@"Dropping menu click because curApp is nil!");
                            break;
                        }
                        [self sendInlineData:msg.msg.data
                                      length:msg.msg.len
                                    withCode:msg.msg.code
                                      toPort:[curApp port]];

                    }
                    case CODE_ADD_RECENT_ITEM:
                        // FIXME: pass to SystemUIServer
                        break;
                    case CODE_OPEN_BUNDLE:
                    {
                        /* A client (Filer) asked us to open a bundle.  Spawn it
                         * from here rather than from the client process: children
                         * forked from WindowServer inherit the launchd context
                         * the GUI apps need to find com.ravynos.WindowServer,
                         * which a client-spawned child cannot resolve. */
                        char path[1024];
                        size_t n = msg.msg.len;
                        if(n > sizeof(path) - 1)
                            n = sizeof(path) - 1;
                        memcpy(path, msg.msg.data, n);
                        path[n] = 0;
                        NSString *bundlePath = [NSString stringWithUTF8String:path];
                        NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
                        NSString *targetID = [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"];
                        if(targetID == nil && bundle == nil)
                            fprintf(stderr, "[WS] open bundle: note: [NSBundle bundleWithPath:] nil for %s, continuing\n", path);
                        NSArray *launchArgs =
                            [bundle objectForInfoDictionaryKey:@"RAVYNLaunchArguments"];
                        if(![launchArgs isKindOfClass:[NSArray class]])
                            launchArgs = nil;
                        /* Do not fork from here.  A child that inherits the
                         * locked registry mutex never completes its launch
                         * handshake -- its bootstrap_look_up for the WindowServer
                         * service fails (measured: "Failed to locate WindowServer
                         * service"), so every window-create RPC then dies with
                         * MACH_SEND_INVALID_DEST_NAME.  Queue the launch and
                         * spawn it from the main loop, outside the lock.  The
                         * queue also deduplicates: an app that is already
                         * running is activated instead of forked a second time. */
                        [self queueBundleLaunch:bundlePath bundleID:targetID args:launchArgs];
                        break;
                    }
                    case CODE_OPEN_DOCUMENTS:
                    {
                        /* Payload: NUL separated bundle path followed by the
                         * document paths to open.  A running app with the same
                         * bundle id receives the documents; otherwise the
                         * bundle is launched with the paths as arguments. */
                        NSMutableArray *parts = [NSMutableArray array];
                        size_t off = 0;
                        size_t maxlen = (size_t)msg.msg.len;

                        if(maxlen > sizeof(msg.msg.data))
                            maxlen = sizeof(msg.msg.data);
                        while(off < maxlen && msg.msg.data[off] != 0) {
                            NSString *s = [NSString stringWithUTF8String:(const char *)&msg.msg.data[off]];
                            if(s == nil)
                                break;
                            [parts addObject:s];
                            off += [s length] + 1;
                        }
                        if([parts count] == 0)
                            break;

                        {
                            NSString *bundlePath = [parts objectAtIndex:0];
                            NSArray *docPaths = [parts count] > 1 ?
                                [parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)] :
                                [NSArray array];
                            NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
                            NSString *targetID = [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"];
                            mach_port_t targetPort = MACH_PORT_NULL;
                            WSAppRecord *existing = nil;

                            if(targetID == nil)
                                targetID = [[bundlePath lastPathComponent] stringByDeletingPathExtension];

                            pthread_mutex_lock(&appsLock);
                            existing = [apps objectForKey:targetID];
                            if(existing != nil)
                                targetPort = [existing port];
                            pthread_mutex_unlock(&appsLock);

                            if(targetPort != MACH_PORT_NULL) {
                                Message docMsg = {0};
                                size_t used = 0;
                                unsigned i;

                                docMsg.header.msgh_remote_port = targetPort;
                                docMsg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                                docMsg.header.msgh_id = MSG_ID_INLINE;
                                docMsg.header.msgh_size = sizeof(docMsg) - sizeof(mach_msg_trailer_t);
                                docMsg.code = CODE_OPEN_DOCUMENTS;
                                docMsg.pid = msg.msg.pid;
                                strncpy(docMsg.bundleID, msg.msg.bundleID, sizeof(docMsg.bundleID));
                                for(i = 0; i < [docPaths count]; i++) {
                                    const char *p = [[docPaths objectAtIndex:i] UTF8String];
                                    size_t l = strlen(p) + 1;
                                    if(used + l > sizeof(docMsg.data))
                                        break;
                                    memcpy(docMsg.data + used, p, l);
                                    used += l;
                                }
                                docMsg.len = (unsigned)used;
                                mach_msg((mach_msg_header_t *)&docMsg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                        sizeof(docMsg) - sizeof(mach_msg_trailer_t),
                                        0, MACH_PORT_NULL, 200 /* ms timeout */, MACH_PORT_NULL);
                                fprintf(stderr, "[WS] open documents: routed %d file(s) to running %s\n",
                                        (int)[docPaths count], [targetID UTF8String]);
                                pthread_mutex_lock(&appsLock);
                                curApp = existing;
                                pthread_mutex_unlock(&appsLock);
                                [self activateApp:existing];
                            } else {
                                [self queueBundleLaunch:bundlePath bundleID:targetID args:docPaths];
                                fprintf(stderr, "[WS] open documents: queued launch of %s\n",
                                        [targetID UTF8String]);
                            }
                        }
                        break;
                    }
                    case CODE_DRAG_EVENT:
                    {
                        /* Route the drag event to the app that owns the
                         * target window. */
                        struct mach_drag_event ev;
                        mach_port_t targetPort = MACH_PORT_NULL;
                        WSAppRecord *owner = nil;
                        NSString *key;
                        NSEnumerator *keys;

                        memset(&ev, 0, sizeof(ev));
                        if((size_t)msg.msg.len >= sizeof(ev))
                            memcpy(&ev, msg.msg.data, sizeof(ev));

                        pthread_mutex_lock(&appsLock);
                        keys = [apps keyEnumerator];
                        while((key = [keys nextObject]) != nil) {
                            WSAppRecord *rec = [apps objectForKey:key];
                            NSArray *wins = [rec windows];
                            unsigned i;
                            for(i = 0; i < [wins count]; i++) {
                                if([[wins objectAtIndex:i] number] == (int)ev.windowID) {
                                    owner = rec;
                                    targetPort = [rec port];
                                    break;
                                }
                            }
                            if(owner != nil)
                                break;
                        }
                        pthread_mutex_unlock(&appsLock);

                        if(targetPort != MACH_PORT_NULL) {
                            Message dragMsg = {0};
                            dragMsg.header.msgh_remote_port = targetPort;
                            dragMsg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                            dragMsg.header.msgh_id = MSG_ID_INLINE;
                            dragMsg.header.msgh_size = sizeof(dragMsg) - sizeof(mach_msg_trailer_t);
                            dragMsg.code = CODE_DRAG_EVENT;
                            dragMsg.pid = msg.msg.pid;
                            strncpy(dragMsg.bundleID, msg.msg.bundleID, sizeof(dragMsg.bundleID));
                            memcpy(dragMsg.data, &ev, sizeof(ev));
                            dragMsg.len = sizeof(ev);
                            mach_msg((mach_msg_header_t *)&dragMsg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                    sizeof(dragMsg) - sizeof(mach_msg_trailer_t),
                                    0, MACH_PORT_NULL, 200 /* ms timeout */, MACH_PORT_NULL);
                        }
                        break;
                    }
                    case CODE_PREFS_CHANGED:
                    {
                        /* Broadcast to every running app so the Dock, the menu
                         * bar and the open windows can restyle themselves. */
                        NSString *key;
                        NSEnumerator *keys;

                        pthread_mutex_lock(&appsLock);
                        keys = [apps keyEnumerator];
                        while((key = [keys nextObject]) != nil) {
                            WSAppRecord *rec = [apps objectForKey:key];
                            mach_port_t port = [rec port];
                            if(port == MACH_PORT_NULL)
                                continue;
                            Message prefMsg = {0};
                            prefMsg.header.msgh_remote_port = port;
                            prefMsg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                            prefMsg.header.msgh_id = MSG_ID_INLINE;
                            prefMsg.header.msgh_size = sizeof(prefMsg) - sizeof(mach_msg_trailer_t);
                            prefMsg.code = CODE_PREFS_CHANGED;
                            prefMsg.pid = msg.msg.pid;
                            strncpy(prefMsg.bundleID, msg.msg.bundleID, sizeof(prefMsg.bundleID));
                            mach_msg((mach_msg_header_t *)&prefMsg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                    sizeof(prefMsg) - sizeof(mach_msg_trailer_t),
                                    0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                        }
                        pthread_mutex_unlock(&appsLock);
                        /* Keyboard and mouse preferences (tracking speed, modifiers, key repeat) apply immediately. */
                        if(input != nil) [input reloadInputPreferences];
                        fprintf(stderr, "[WS] preferences changed broadcast\n");
                        break;
                    }
                    case CODE_APP_HIDE:
                    {
                        pid_t pid;
                        memcpy(&pid, msg.msg.data, sizeof(int));
                        NSLog(@"CODE_APP_HIDE: pid = %d", pid);
                        // FIXME: pass to SystemUIServer
                        mach_port_t port = 0; // FIXME: get from active app
                        if(port != MACH_PORT_NULL) {
                            Message activate = {0};
                            activate.header.msgh_remote_port = port;
                            activate.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
                            activate.header.msgh_id = MSG_ID_INLINE;
                            activate.header.msgh_size = sizeof(activate) - sizeof(mach_msg_trailer_t);
                            activate.code = msg.msg.code;
                            activate.len = 0;
                            mach_msg((mach_msg_header_t *)&activate, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
                                sizeof(activate) - sizeof(mach_msg_trailer_t),
                                0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
                        }
                        break;
                    }
		    case CODE_ADD_STATUS_ITEM:
		    {
			NSData *data = [NSData
			    dataWithBytes:msg.msg.data length:msg.msg.len];
			NSObject *o = nil;
			@try {
			    o = [NSKeyedUnarchiver unarchiveObjectWithData:data];
			}
			@catch(NSException *localException) {
			    NSLog(@"%@",localException);
			}

			if(o == nil || [o isKindOfClass:[NSDictionary class]] == NO ||
			    [(NSDictionary *)o objectForKey:@"StatusItem"] == nil ||
			    [(NSDictionary *)o objectForKey:@"ProcessID"] == nil) {
			    fprintf(stderr, "archiver: bad input\n");
			    break;
			}

                        // FIXME: send to SystemUIServer
			break;
		    }
                    default:
                        NSLog(@"Unhandled WindowServer code %u", msg.msg.code);
                }
                break;
            }
        }
    }
}

// called from our kq watcher thread
- (void)processKernelQueue {
    struct kevent out[128];
    int count = kevent(_kq, NULL, 0, out, 128, NULL);

    for(int i = 0; i < count; ++i) {
        switch(out[i].filter) {
            case EVFILT_PROC:
                if((out[i].fflags & NOTE_EXIT)) {
                    //NSLog(@"PID %lu exited", out[i].ident);
                    pthread_mutex_lock(&appsLock);
                    /* findAppByPID returns an unowned pointer. Capture everything
                     * we need and take our own reference BEFORE removing the app
                     * from the dictionary: removeObjectForKey: releases the record,
                     * leaving any later use of it a use-after-free. */
                    WSAppRecord *app = [self findAppByPID:out[i].ident];
                    if(app == nil) {
                        pthread_mutex_unlock(&appsLock);
                        NSLog(@"PID %u exited, but no matching app record", out[i].ident);
                        break;
                    }
                    NSString *deadBundleID = [app.bundleID copy];
                    NSString *deadPath = [app.path copy];
                    NSArray *deadWins = [app.windows copy];
                    pthread_mutex_unlock(&appsLock);

                    if(curApp == app) {
                        [self switchApp];
                        if(curApp == app) {
                            curApp = nil; // there was nothing to switch to
                            curWindow = nil;
                        }
                    }
                    pthread_mutex_lock(&appsLock);
                    [apps removeObjectForKey:deadBundleID];
                    WSAppRecord *sysui = [apps objectForKey:@"com.ravynos.SystemUIServer"];
                    mach_port_t sysuiPort = (sysui != nil && [sysui isKindOfClass:[WSAppRecord class]])
                        ? [sysui port] : MACH_PORT_NULL;
                    WSAppRecord *dock = [apps objectForKey:@"com.ravynos.Dock"];
                    mach_port_t dockPort = (dock != nil && [dock isKindOfClass:[WSAppRecord class]])
                        ? [dock port] : MACH_PORT_NULL;
                    pthread_mutex_unlock(&appsLock);

                    for(int x = 0; x < [deadWins count]; ++x)
                        [self removeWindowFromAllLevels:[deadWins objectAtIndex:x]];

                    if(sysuiPort != MACH_PORT_NULL)
                        notifyAppExited(sysuiPort, out[i].ident,
                                [deadBundleID UTF8String], [deadPath UTF8String]);
                    if(dockPort != MACH_PORT_NULL && dockPort != sysuiPort)
                        notifyAppExited(dockPort, out[i].ident,
                                [deadBundleID UTF8String], [deadPath UTF8String]);

                    deadWins = nil;
                    deadPath = nil;
                    deadBundleID = nil;
                    app = nil;
                }
                break;
            default:
                NSLog(@"unknown filter");
        }
    }
}

- (WSWindowRecord *)windowUnderPointer:(NSPoint)pos app:(WSAppRecord **)app {
    // We need to work from foreground (highest level) to background (0) to
    // find the foremost window. Otherwise we might be choosing something
    // that is behind another.

    for(int level = kCGNumReservedWindowLevels - 1; level >= 0; --level) {
        NSArray *wins = _windows[level];
        int count = [wins count];
        for(int i = count - 1; i >= 0; --i) {
            WSWindowRecord *win = [wins objectAtIndex:i];
            if(win.state == HIDDEN || win.state == MINIMIZED || win.state == CLOSED)
                continue;
            if(NSPointInRect(pos, win.frame)) {
                *app = win.app;
                return win;
            }
        }
    }

    return nil;
}

- (BOOL)sendEventToApp:(struct mach_event *)event {
    static BOOL inResize = NO;
    static WSWindowRecord *resizeWindow = nil;
    static NSPoint resizeStart = {0, 0};
    static NSRect resizeOrigGeom = {{0, 0}, {0, 0}};
    static int resizeEdge = 0;
    NSPoint pos = NSMakePoint(event->x, event->y);

    /* Any key input goes to active window & app, even if pointer is over something else
     * Otherwise, identify the window (if any) that is under the pointer. Windows on macOS
     * seem to receive mouse and scroll inputs when not the active window.
     */
    WSAppRecord *app = curApp;
    WSWindowRecord *window = nil;
    if(event->code == NSKeyDown || event->code == NSKeyUp)
        event->windowID = curWindow.number;
    else
        window = [self windowUnderPointer:pos app:&app];

    if(event->code == NSLeftMouseDown || event->code == NSLeftMouseUp ||
            event->code == NSMouseMoved) {
        NSRect f = window ? window.frame : NSZeroRect;
        const char *bid = (app && [app bundleID]) ? [[app bundleID] UTF8String] : "(nil)";
        fprintf(stderr, "[WS] ev code=%d pos=%d,%d win=%d frame=%d,%d %dx%d app=%s\n",
            event->code, (int)pos.x, (int)pos.y, window ? window.number : -1,
            (int)f.origin.x, (int)f.origin.y, (int)f.size.width, (int)f.size.height, bid);
    }

    NSRect titleFrame = NSZeroRect;
    if(window != nil) {
        titleFrame = window.geometry;
        titleFrame.origin.y += titleFrame.size.height - WSWindowTitleHeight;
        titleFrame.size.height = WSWindowTitleHeight;
    }

    // First, check if we want to handle this event ourselves!
    switch(event->code) {
        case NSLeftMouseDragged: {
            if(inResize && resizeWindow != nil) {
                float dx = pos.x - resizeStart.x;
                float dy = pos.y - resizeStart.y;
                float newW = resizeOrigGeom.size.width;
                float newH = resizeOrigGeom.size.height;
                float newOriginX = resizeOrigGeom.origin.x;
                float newOriginY = resizeOrigGeom.origin.y;

                if(resizeEdge & 2) newW += dx;
                if(resizeEdge & 1) { newW -= dx; newOriginX += dx; }
                if(resizeEdge & 4) { newH -= dy; newOriginY += dy; }
                if(resizeEdge & 8) newH += dy;

                if(newW < 200) newW = 200;
                if(newH < 100) newH = 100;

                if((int)newW != (int)resizeWindow.geometry.size.width ||
                   (int)newH != (int)resizeWindow.geometry.size.height ||
                   (int)newOriginY != (int)resizeWindow.geometry.origin.y) {
                    [self resizeWindowSurface:resizeWindow width:(int)newW height:(int)newH];
                    resizeWindow.geometry = NSMakeRect(newOriginX, newOriginY, newW, newH);
                    resizeWindow.frame = resizeWindow.geometry;
                    [self updateClientWindowState:resizeWindow];
                }
                return YES;
            }

            if(sInDrag && sDragWindow != nil) {
                NSRect oldGeom = sDragWindow.geometry;
                [sDragWindow moveByX:event->dx Y:event->dy];
                NSRect newGeom = sDragWindow.geometry;
                NSRect dragDamage = NSInsetRect(NSUnionRect(oldGeom, newGeom), -16, -16);
                [self markDamageRect:dragDamage];
                return YES;
            }
            break;
        }
        case NSLeftMouseDown: {
            if(window == nil)
                return YES;

            if(window.level >= 0 && window.level < kCGNumReservedWindowLevels) {
                pthread_mutex_lock(&renderLock);
                [_windows[window.level] removeObject:window];
                [_windows[window.level] addObject:window];
                pthread_mutex_unlock(&renderLock);
                [self draw];
            }

            if(app != nil && ![app skipSwitcher] && app != curApp) {
                [self deactivateApp:curApp];
                curApp = app;
                curWindow = window;
                [self activateApp:curApp];
            } else if(app == curApp && window != curWindow) {
                curWindow = window;
            }

            // Check for window border/corner resize (NSResizableWindowMask = 8)
            if((window.styleMask & 8) != 0 && window.state == NORMAL) {
                NSRect f = window.frame;
                int edge = 0;
                if(pos.x >= f.origin.x + f.size.width - 8 && pos.x <= f.origin.x + f.size.width) edge |= 2;
                if(pos.x >= f.origin.x && pos.x <= f.origin.x + 8) edge |= 1;
                if(pos.y >= f.origin.y && pos.y <= f.origin.y + 8) edge |= 4;
                if(pos.y >= f.origin.y + f.size.height - 8 && pos.y <= f.origin.y + f.size.height) edge |= 8;

                if(edge != 0) {
                    inResize = YES;
                    resizeWindow = window;
                    resizeEdge = edge;
                    resizeStart = pos;
                    resizeOrigGeom = window.geometry;
                    return YES;
                }
            }

            // Did we click in the titlebar but not a button?
            NSRect noControl = titleFrame;
            noControl.origin.x += NSWindowControlSpacing*3;
            noControl.origin.x += NSWindowControlDiameter*3;
            if(window.state == NORMAL && (window.styleMask & NSTitledWindowMask) && window.level == kCGNormalWindowLevelKey && NSPointInRect(pos, noControl)) {
                sInDrag = YES;
                sDragWindow = window;
                return YES;
            }
            break;
        }
        case NSLeftMouseUp: {
            if(inResize) {
                if(resizeWindow != nil) {
                    resizeWindow.frame = resizeWindow.geometry;
                    [self updateClientWindowState:resizeWindow];
                    [self draw];
                }
                inResize = NO;
                resizeWindow = nil;
                resizeEdge = 0;
                return YES;
            }
            if(sInDrag) {
                if(sDragWindow != nil) {
                    sDragWindow.frame = sDragWindow.geometry;
                    [self updateClientWindowState:sDragWindow];
                    [self markDamageRect:NSInsetRect(sDragWindow.geometry, -16, -16)];
                    [self draw];
                }
                sInDrag = NO;
                sDragWindow = nil;
                return YES;
            }
            break;
        }
    }

    if(app == nil || ![app isKindOfClass:[WSAppRecord class]]) {
        return YES;
    }

    // Key events were already aimed at the focused window above; only mouse
    // events re-aim at whatever window the pointer is over.
    if(event->code != NSKeyDown && event->code != NSKeyUp)
        event->windowID = window.number;

    mach_port_t destPort = [app port];
    if(destPort == MACH_PORT_NULL) {
        return YES;
    }
    if(destPort == MACH_PORT_NULL)
        return YES;

    if(event->code == NSKeyDown || event->code == NSKeyUp) {
        char ktb[192]; int ktn = snprintf(ktb, sizeof(ktb),
            "[WS] key send code=%d winID=%d curApp=%p appPort=%u\n",
            (int)event->code, (int)event->windowID, curApp, destPort);
        if(ktn>0) write(2, ktb, ktn);
    }

    return [self sendInlineData:event
                         length:sizeof(struct mach_event)
                       withCode:CODE_INPUT_EVENT
                          toPort:destPort];
}

- (void)updateClientWindowState:(WSWindowRecord *)window {
    struct wsRPCWindow data = {0};
    data.base.code = kWSWindowModifyState;
    data.base.len = sizeof(data) - sizeof(struct wsRPCBase);
    data.windowID = window.number;
    data.x = window.geometry.origin.x;
    data.y = window.geometry.origin.y;
    data.w = window.geometry.size.width;
    data.h = window.geometry.size.height;
    data.style = window.styleMask;
    data.state = window.state;
    // title is ignored - only client can set it

    WSAppRecord *app = (WSAppRecord *)window.app;
    if(app != nil && [app isKindOfClass:[WSAppRecord class]]) {
        mach_port_t appPort = [app port];
        if(appPort != MACH_PORT_NULL)
            [self sendInlineData:&data length:sizeof(data) withCode:CODE_WINDOW_STATE toPort:appPort];
    } else {
        NSLog(@"Cannot send window state update to app: not found. %@", window);
    }

    // Tell Dock if the window gets minimized or closed so it can manage icons
    if(window.state == MINIMIZED || window.state == CLOSED)
        [self notifyDock:&data length:sizeof(data) withCode:CODE_WINDOW_STATE forApp:app];
}

- (BOOL)notifyDock:(void *)data length:(int)length withCode:(int)code forApp:(WSAppRecord *)app {
    pthread_mutex_lock(&appsLock);
    WSAppRecord *dock = [apps objectForKey:@"com.ravynos.Dock"];
    if(dock == nil || ![dock isKindOfClass:[WSAppRecord class]]) {
        if(logLevel >= WS_WARNING)
            NSLog(@"Cannot notify Dock - is it running?");
        pthread_mutex_unlock(&appsLock);
        return NO;
    }

    pthread_mutex_unlock(&appsLock);
    Message msg = {0};
    msg.header.msgh_remote_port = [dock port];
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = code;
    msg.pid = [app pid];
    strncpy(msg.bundleID, [app.bundleID UTF8String], sizeof(msg.bundleID)-1);

    memcpy(msg.data, data, length);
    msg.len = length;

    int ret;
    if((ret = mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
        sizeof(msg) - sizeof(mach_msg_trailer_t), 0, MACH_PORT_NULL, 50 /* ms timeout */,
        MACH_PORT_NULL)) != MACH_MSG_SUCCESS) {
        if(logLevel >= WS_WARNING)
            NSLog(@"Failed to send message to Dock: 0x%x", ret);
        return NO;
    }
    return YES;
}

- (BOOL)sendInlineData:(void *)data length:(int)length withCode:(int)code toPort:(mach_port_t)port timeout:(mach_msg_timeout_t)timeoutMs {
    Message msg = {0};
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = code;
    msg.pid = getpid();
    strncpy(msg.bundleID, WINDOWSERVER_SVC_NAME, sizeof(msg.bundleID)-1);

    if(length > 0 && data != NULL)
        memcpy(msg.data, data, MIN(length, sizeof(msg.data)));
    msg.len = length;

    /* Under QEMU TCG the receiving process is often mid-render; a single
     * timed send loses the reply and the client then builds a window that
     * never existed, so retry with escalating timeouts before giving up. */
    mach_msg_timeout_t attempt = (timeoutMs > 0) ? timeoutMs : 2000;
    int ret = MACH_MSG_SUCCESS;
    for(int tryIdx = 0; tryIdx < 4; ++tryIdx) {
        mach_msg_option_t opts = MACH_SEND_MSG | MACH_SEND_TIMEOUT;
        ret = mach_msg((mach_msg_header_t *)&msg, opts,
            sizeof(msg) - sizeof(mach_msg_trailer_t), 0, MACH_PORT_NULL, attempt,
            MACH_PORT_NULL);
        if(ret == MACH_MSG_SUCCESS)
            break;
        attempt *= 2;
    }
    if(ret != MACH_MSG_SUCCESS) {
        char errbuf[128];
        int n = snprintf(errbuf, sizeof(errbuf), "[WS] sendInlineData failed to port %u: 0x%x\n", port, ret);
        write(2, errbuf, n);
        return NO;
    }
    return YES;
}

- (BOOL)sendInlineData:(void *)data length:(int)length withCode:(int)code toPort:(mach_port_t)port {
    return [self sendInlineData:data length:length withCode:code toPort:port timeout:500];
}

- (void)watchForProcessExit:(unsigned int)pid {
    struct kevent kev[1];
    EV_SET(kev, pid, EVFILT_PROC, EV_ADD|EV_ONESHOT, NOTE_EXIT, 0, NULL);
    kevent(_kq, kev, 1, NULL, 0, NULL);
}

/* Returns a +1 reference: callers keep the record alive across
 * removeObjectForKey:, which releases the dictionary's own reference. */
- (WSAppRecord *)findAppByPID:(unsigned int)pid {
    NSEnumerator *apprecs = [apps objectEnumerator];
    id record;
    while((record = [apprecs nextObject]) != nil) {
        if(![record isKindOfClass:[WSAppRecord class]])
            continue;
        WSAppRecord *app = record;
        if(app.pid == pid)
            return (WSAppRecord *)CFRetain((CFTypeRef)app);
    }
    return nil;
}

-(void)deactivateApp:(WSAppRecord *)app {
    if(app == nil || ![app isKindOfClass:[WSAppRecord class]])
        return;

    Message msg = {0};
    struct mach_activation_data data = {0};
    pthread_mutex_lock(&appsLock);
    WSAppRecord *sysui = [apps objectForKey:@"com.ravynos.SystemUIServer"];
    if(sysui == nil || ![sysui isKindOfClass:[WSAppRecord class]] || [sysui port] == MACH_PORT_NULL) {
        pthread_mutex_unlock(&appsLock);
        return;
    }
    pthread_mutex_unlock(&appsLock);
    msg.header.msgh_remote_port = [sysui port];
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = CODE_ACTIVATION_STATE;
    msg.pid = getpid();
    strncpy(msg.bundleID, [[app bundleID] UTF8String], sizeof(msg.bundleID));
    memcpy(msg.data, &data, sizeof(data)); // window ID
    msg.len = sizeof(data);
    mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
            sizeof(msg) - sizeof(mach_msg_trailer_t),
            0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
}

-(void)activateApp:(WSAppRecord *)app {
    if(app == nil)
        return;

    Message msg = {0};
    struct mach_activation_data data = {0, 1};
    pthread_mutex_lock(&appsLock);
    WSAppRecord *sysui = [apps objectForKey:@"com.ravynos.SystemUIServer"];
    if(sysui == nil || ![sysui isKindOfClass:[WSAppRecord class]] || [sysui port] == MACH_PORT_NULL) {
        pthread_mutex_unlock(&appsLock);
        return;
    }
    pthread_mutex_unlock(&appsLock);
    msg.header.msgh_remote_port = [sysui port];
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = CODE_ACTIVATION_STATE;
    msg.pid = getpid();
    strncpy(msg.bundleID, [[app bundleID] UTF8String], sizeof(msg.bundleID));
    memcpy(msg.data, &data, sizeof(data));
    msg.len = sizeof(data);
    mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
            sizeof(msg) - sizeof(mach_msg_trailer_t),
            0, MACH_PORT_NULL, 100 /* ms timeout */, MACH_PORT_NULL);
}

// FIXME: do some visual magic here for the user
- (void)switchApp {
    WSAppRecord *oldApp = curApp;

    WSAppRecord *app;
    NSMutableArray *viableApps = [NSMutableArray new];
    NSArray *list = [apps allValues];
    for(int i = 0; i < [list count]; ++i) {
        id obj = [list objectAtIndex:i];
        if(![obj isKindOfClass:[WSAppRecord class]])
            continue;
        WSAppRecord *app = (WSAppRecord *)obj;
        if([app skipSwitcher])
            continue;
        [viableApps addObject:app];
    }

    for(int i = 0; i < [viableApps count]; ++i) {
        app = [viableApps objectAtIndex:i];
        if(app == curApp) {
            if(i+1 >= [viableApps count])
                curApp = [viableApps objectAtIndex:0];
            else
                curApp = [viableApps objectAtIndex:1+i];
            break;
        }
    }

    /* curApp may have been nil, or the app that exited is no longer in the
     * list. Fall back to the first viable app so key events have a target. */
    if(curApp == nil && [viableApps count] > 0)
        curApp = [viableApps objectAtIndex:0];

    [self switchFromApp:oldApp];
}

-(void)switchFromApp:(WSAppRecord *)oldApp toWindow:(WSWindowRecord *)win {
    struct mach_activation_data data = {0};
    if(oldApp != curApp && oldApp != nil && [oldApp isKindOfClass:[WSAppRecord class]]) {
        // Inform the old app that it has become inactive
        [self sendInlineData:&data
                      length:sizeof(data)
                    withCode:CODE_ACTIVATION_STATE
                      toPort:[oldApp port]];

        // Now tell SystemUIServer the app resigned active
        [self deactivateApp:oldApp];
    }

    curWindow = nil;
    if(curApp == nil)
        return;

    if(win != nil)
        curWindow = win;
    else {
        // Find the first non-hidden window for the newly active app
        for(int i = 0; i < [[curApp windows] count]; ++i) {
            WSWindowRecord *win = [[curApp windows] objectAtIndex:i];
            if(win.state == HIDDEN || win.state == MINIMIZED || win.state == CLOSED)
                continue;
            curWindow = win;
            break;
        }
    }

    if(curApp == oldApp)
        return;

    // Inform the now-active app of its status
    data.windowID = (curWindow == nil) ? 0 : curWindow.number;
    data.active = 1;
    if(curApp != nil && [curApp isKindOfClass:[WSAppRecord class]]) {
        [self sendInlineData:&data
                      length:sizeof(data)
                    withCode:CODE_ACTIVATION_STATE
                       toPort:[curApp port]];
    }

    // Now tell SystemUIServer the app became active
    [self activateApp:curApp];
}

-(void)switchFromApp:(WSAppRecord *)oldApp {
    [self switchFromApp:oldApp toWindow:nil];
}

-(void)signalQuit {
    [self performLogout:0];
    pid_t pid = fork();
    if(pid == 0)
        execl("/bin/launchctl", "launchctl", "remove", "com.ravynos.WindowServer", NULL);
    else
        waitpid(pid, NULL, 0);
    ready = NO;
}

- (void)markFullSceneDirty {
    pthread_mutex_lock(&damageLock);
    _sceneDirty = YES;
    _damageRect = _geometry;
    pthread_mutex_unlock(&damageLock);
}

- (void)markDamageRect:(NSRect)rect {
    if(NSIsEmptyRect(rect))
        return;
    pthread_mutex_lock(&damageLock);
    _sceneDirty = YES;
    if(NSIsEmptyRect(_damageRect))
        _damageRect = rect;
    else
        _damageRect = NSUnionRect(_damageRect, rect);
    pthread_mutex_unlock(&damageLock);
}

-(void)resizeWindowSurface:(WSWindowRecord *)winrec width:(int)w height:(int)h {
    if(winrec == nil || w <= 0 || h <= 0) return;
    /* Same discipline as windowModify:'s remap: munmap the OLD mapping with the OLD
     * size, and if the new buffer cannot be mapped, drop winrec.surface -- leaving it
     * set would keep an O2Image that wraps just-unmapped bytes alive, which is exactly
     * what faulted inside Onyx2D's span reads. */
    size_t oldBufSize = winrec.bufSize;
    int oldW = (int)winrec.geometry.size.width, oldH = (int)winrec.geometry.size.height;

    pthread_mutex_lock(&renderLock);
    winrec.bufSize = ([fb getDepth]/8) * w * h;

    shm_unlink([winrec.shmPath cString]);
    int shmfd = shm_open([winrec.shmPath cString], O_RDWR|O_CREAT|O_EXCL, 0666);
    if(shmfd < 0)
        shmfd = shm_open([winrec.shmPath cString], O_RDWR|O_CREAT, 0666);
    if(shmfd < 0) {
        int err = errno;
        pthread_mutex_unlock(&renderLock);
        fprintf(stderr, "[WS] SURF-FAIL win=%u %dx%d->%dx%d open errno=%d\n",
            (unsigned)winrec.number, oldW, oldH, w, h, err);
        return;
    }

    if(ftruncate(shmfd, winrec.bufSize) < 0) {
        int err = errno;
        close(shmfd);
        munmap(winrec.surfaceBuf, oldBufSize);
        winrec.surfaceBuf = NULL;
        winrec.surface = NULL;
        winrec.bufSize = 0;
        pthread_mutex_unlock(&renderLock);
        fprintf(stderr, "[WS] SURF-FAIL win=%u %dx%d->%dx%d ftrunc errno=%d\n",
            (unsigned)winrec.number, oldW, oldH, w, h, err);
        return;
    }

    if(winrec.surfaceBuf != NULL)
        munmap(winrec.surfaceBuf, oldBufSize);

    winrec.surfaceBuf = mmap(NULL, winrec.bufSize, PROT_WRITE|PROT_READ,
            MAP_SHARED|MAP_NOCORE, shmfd, 0);
    int mapErr = (winrec.surfaceBuf == NULL) ? errno : 0;
    close(shmfd);

    if(winrec.surfaceBuf == NULL) {
        winrec.surface = NULL;
        winrec.bufSize = 0;
        pthread_mutex_unlock(&renderLock);
        fprintf(stderr, "[WS] SURF-FAIL win=%u %dx%d->%dx%d mmap errno=%d\n",
            (unsigned)winrec.number, oldW, oldH, w, h, mapErr);
        return;
    }

    if(logLevel < WS_INFO)
        fprintf(stderr, "[WS] SURF win=%u %dx%d->%dx%d buf=0x%zx size=0x%zx\n",
            (unsigned)winrec.number, oldW, oldH, w, h,
            (size_t)winrec.surfaceBuf, (size_t)winrec.bufSize);

    winrec.surface = [[O2Surface alloc] initWithBytes:winrec.surfaceBuf width:w
        height:h bitsPerComponent:8 bytesPerRow:4*w
        colorSpace:[fb colorSpace]
        bitmapInfo:kCGBitmapByteOrderDefault|kCGImageAlphaPremultipliedFirst];
    pthread_mutex_unlock(&renderLock);
}
@end

