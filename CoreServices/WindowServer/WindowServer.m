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
        NSLog(@"windowCreate cannot create existing window ID %u for %@", data->windowID, app);
        return 0;
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

    if(winrec.surfaceBuf == NULL) {
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
    winrec.geometry = NSMakeRect(data->x, data->y, data->w, data->h); // FIXME: bounds check?
    if(!NSEqualRects(winrec.geometry, oldFrame)) {
        // it resized, so fix up our surface to match
        pthread_mutex_lock(&renderLock);
        winrec.bufSize = ([fb getDepth]/8) * data->w * data->h;

        int shmfd = shm_open([winrec.shmPath cString], O_RDWR|O_CREAT, 0666);
        if(shmfd < 0) {
            NSLog(@"Cannot open shm fd: %s", strerror(errno));
            return;
        }

        if(ftruncate(shmfd, winrec.bufSize) < 0)
            NSLog(@"shmfd ftruncate failed: %s", strerror(errno));

        /* shm is already 0666, no need for fchown via failing sysctl */

        winrec.surfaceBuf = mmap(NULL, winrec.bufSize, PROT_WRITE|PROT_READ,
                MAP_SHARED|MAP_NOCORE, shmfd, 0);
        close(shmfd);

        if(winrec.surfaceBuf == NULL) {
            winrec.bufSize = 0;
            NSLog(@"Cannot alloc surface memory! %s", strerror(errno));
            return;
        }

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
}

-(void)removeWindowFromAllLevels:(WSWindowRecord *)window {
    fprintf(stderr,"[WS] DESTROY win=%u lvl=%d frame=%d,%d %dx%d\n",
        (unsigned)window.number,(int)window.level,
        (int)window.frame.origin.x,(int)window.frame.origin.y,
        (int)window.frame.size.width,(int)window.frame.size.height);

    if(logLevel >= WS_INFO)
        NSLog(@"removeWindowFromAllLevels %@", window);
    pthread_mutex_lock(&renderLock);
    for(int i = 0; i < kCGNumReservedWindowLevels; ++i)
        [_windows[window.level] removeObject:window];
    pthread_mutex_unlock(&renderLock);
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
-(void)run {
    pthread_t shellThread;
    pthread_create(&shellThread, NULL, shellSvcLoop, (__bridge void *)self);

    // FIXME: lock this to vsync of actual display
    pthread_mutex_lock(&renderLock);
    O2BitmapContext *ctx = [fb context];
    pthread_mutex_unlock(&renderLock);

    O2ImageRef cursor = NULL;
    write(2, "[WS] using fallback vector cursor\n", 34);
    NSRect cursorRect = NSMakeRect(0, 0, _cursor_height, _cursor_height);

    struct pollfd fds[2];
    fds[0].fd = [input fileDescriptor];
    fds[0].events = POLLIN;
    fds[1].fd = [input keyboardFileDescriptor];
    fds[1].events = POLLIN;
    write(2, "[WS] run loop entered\n", 22);
    int frame_count = 0;
    while(ready == YES) {
        int nfds = (fds[0].fd >= 0) + (fds[1].fd >= 0);
        if(nfds > 0 && poll(fds, 2, 16) > 0) {
            [input run:self];
        } else {
            usleep(16666); // ~60 FPS
        }
        if(input)
            cursorRect.origin = [input pointerPos];
        else
            cursorRect.origin = NSMakePoint(_geometry.size.width / 2, _geometry.size.height / 2);

        // FIXME: handle multiple displays here. Use a thread per display?
        pthread_mutex_lock(&renderLock);
        ctx = [fb context];
        pid_t capturedPID = [fb captured];
        if(capturedPID == 0) {
            O2ContextSetRGBFillColor(ctx, 0.15, 0.25, 0.35, 1);
            O2ContextFillRect(ctx, (O2Rect)_geometry);
            for(int level = 0; level < kCGNumReservedWindowLevels; ++level) {
                NSArray *wins = [_windows[level] copy];
                NSInteger count = [wins count];
                for(int i = 0; i < count; ++i) {
                    WSWindowRecord *win = [wins objectAtIndex:i];
                    if(win.state == HIDDEN || win.state == MINIMIZED || win.state == CLOSED)
                        continue;
                    /* A window whose shm surface never mapped (shm_open or
                     * mmap failed) has a NULL surface; drawing it faults. */
                    if(win.surface != NULL)
                        [ctx drawImage:win.surface inRect:win.geometry];
                }
            }
        }

        cursorRect.origin.y -= _cursor_height; // make sure point of arrow is on actual spot

        if(capturedPID == 0) {
            if(cursorHideCount == 0) {
                if(cursor != NULL) {
                    O2ContextSetBlendMode(ctx, kCGBlendModeNormal);
                    O2ContextDrawImage(ctx, cursorRect, cursor);
                } else {
                    /* High-contrast fallback cursor: black frame with white center */
                    O2ContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
                    O2ContextFillRect(ctx, (O2Rect)NSMakeRect(cursorRect.origin.x, cursorRect.origin.y, 14, 14));
                    O2ContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
                    O2ContextFillRect(ctx, (O2Rect)NSMakeRect(cursorRect.origin.x + 2, cursorRect.origin.y + 2, 10, 10));
                }
            }
            [fb draw];
        } else {
            if(cursorHideCount == 0 && cursor != NULL)
                [fb drawWithCursor:cursor inRect:cursorRect];
            else
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
        if([display setMode:mode])
            reply.val1 = kCGErrorSuccess;
        else
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
    struct wsRPCSimple data;
    data.base.code = kCGDisplayHideCursor;
    data.base.len = 4;
    data.val1 = ret;
    [self sendInlineData:&data length:sizeof(data) withCode:MSG_ID_RPC toPort:msg->descriptor.name];
}

-(void)rpcDisplayShowCursor:(PortMessage *)msg {
    int ret = kCGErrorCannotComplete;
    if(msg->pid == [curApp pid]) {
        cursorHideCount--;
        ret = kCGErrorSuccess;
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
                pthread_mutex_unlock(&appsLock);

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
                        pthread_mutex_lock(&appsLock);
                        WSAppRecord *app = [apps objectForKey:@"com.ravynos.SystemUIServer"];
                        if(app == nil || ![app isKindOfClass:[WSAppRecord class]]) {
                            pthread_mutex_unlock(&appsLock);
                            NSLog(@"Cannot install menus for client - is SystemUIServer running?");
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
                        if(bundle == nil) {
                            fprintf(stderr, "[WS] open bundle: no bundle at %s\n", path);
                            break;
                        }
                        NSString *exeName = [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
                        NSString *targetID = [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"];
                        if(exeName == nil)
                            exeName = [bundlePath lastPathComponent];
                        NSString *cands[3];
                        cands[0] = [NSString stringWithFormat:@"%@/Contents/ravynOS/%@", bundlePath, exeName];
                        cands[1] = [NSString stringWithFormat:@"%@/Contents/MacOS/%@", bundlePath, exeName];
                        cands[2] = [NSString stringWithFormat:@"%@/%@", bundlePath, exeName];
                        const char *exe = NULL;
                        for(int i = 0; i < 3; i++) {
                            const char *c = [cands[i] UTF8String];
                            if(c != NULL && access(c, X_OK) == 0) {
                                exe = c;
                                break;
                            }
                        }
                        if(exe == NULL) {
                            fprintf(stderr, "[WS] open bundle: no executable for %s\n", path);
                            break;
                        }
                        fprintf(stderr, "[WS] open bundle: spawning %s\n", exe);
                        /* Ask launchd to run it, exactly the way the dock and the
                         * menu bar do.  A client-spawned (fork/exec'd) child cannot
                         * bootstrap_look_up the WindowServer service, because only
                         * launchd's children can, so its window creation RPC fails
                         * with MACH_SEND_INVALID_DEST_NAME. */
                        launch_data_t job = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
                        launch_data_t args = launch_data_alloc(LAUNCH_DATA_ARRAY);
                        launch_data_array_set_index(args,
                            launch_data_new_string(exe), 0);
                        launch_data_dict_insert(job, args, "ProgramArguments" );
                        launch_data_dict_insert(job, launch_data_new_bool(true),
                            "RunAtLoad" );
                        launch_data_dict_insert(job, launch_data_new_bool(false),
                            "KeepAlive" );
                        launch_data_t envDict = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
                        launch_data_dict_insert(envDict,
                            launch_data_new_string(targetID ?
                                [targetID UTF8String] : "com.ravynos.unknown"),
                            "RAVYN_BUNDLE_ID");
                        launch_data_dict_insert(job, envDict,
                            "EnvironmentVariables" );
                        launch_data_dict_insert(job,
                            launch_data_new_string([bundlePath UTF8String]),
                            LAUNCH_JOBKEY_LABEL);

                        launch_data_t request = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
                        launch_data_dict_insert(request, job, LAUNCH_KEY_SUBMITJOB);
                        launch_data_t response = launch_msg(request);
                        int lserr = launch_data_get_errno(response);
                        if(lserr == EEXIST) {
                            launch_data_t start = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
                            launch_data_dict_insert(start,
                                launch_data_new_string([bundlePath UTF8String]),
                                LAUNCH_KEY_STARTJOB);
                            launch_msg(start);
                            launch_data_free(start);
                        }
                        launch_data_free(request);
                        fprintf(stderr, "[WS] open bundle: launchd submit label=%s err=%d\n",
                                [bundlePath UTF8String], lserr);
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
        for(int i = 0; i < count; ++i) {
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
    static BOOL inDrag = NO;
    static WSWindowRecord *dragWindow = nil;    NSPoint pos = NSMakePoint(event->x, event->y);

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
            // We are already dragging a window, so keep at it
            if(inDrag && dragWindow != nil) {
                [dragWindow moveByX:event->dx Y:event->dy];
                [self updateClientWindowState:dragWindow];
                return YES;
            }

            // Are we dragging a window at all?
            if(window == nil)
                return YES;

            // Are we dragging the titlebar?
            if(NSPointInRect(pos, titleFrame)) {
                [window moveByX:event->dx Y:event->dy];
                [self updateClientWindowState:window];
                inDrag = YES;
                dragWindow = window;
                return YES;
            }

            // Handled all WS cases - send this to the window!
            break;
        }
        case NSLeftMouseDown: {
            if(window == nil)
                return YES;
            
            // Did we click in the titlebar but not a button?
            NSRect noControl = titleFrame;
            noControl.origin.x += NSWindowControlSpacing*3;
            noControl.origin.x += NSWindowControlDiameter*3;
            if(window.state == NORMAL && NSPointInRect(pos, noControl)) {
                [window moveByX:event->dx Y:event->dy];
                //[self updateClientWindowState:window];
                inDrag = YES;
                dragWindow = window;
                return YES;
            }

            // these are just requests - the client can ignore them, so we don't
            // actually change the window until it sends us a new state message
#if 0
            } else if(NSPointInRect(pos, window.miniButtonRect)) {
                if(window.state != MINIMIZED)
                    window.prevState = window.state;
                else
                    window.prevState = NORMAL;
                window.state = MINIMIZED;
                [self updateClientWindowState:window];

                // Are there other windows active for this app?
                NSArray *wins = [app windows];
                for(int i = 0; i < [wins count]; ++i) {
                    curWindow = [wins objectAtIndex:i];
                    if(curWindow.number != window.number)
                        i = [wins count];
                }
                if(curWindow.number == window.number)
                    curWindow = nil; // app stays active though
            } else {
#endif
                // Handled all WS cases - send this to the window!
                if(![app skipSwitcher]) {
                    [self deactivateApp:curApp];
                    curApp = app;
                    curWindow = window;
                    [self activateApp:curApp];
                }
#if 0
            }
#endif
            break;
        }
        case NSLeftMouseUp: {
            if(inDrag) {
                [self updateClientWindowState:dragWindow];
                inDrag = NO;
                dragWindow = nil;
                return YES;
            }
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

    const char *appKey = [window.shmPath cString];
    char *key = appKey + 1;
    while(*key != '/' && *key != '\0')
        key++;
    int len = key - (appKey + 1);
    key = malloc(len+1);
    memcpy(key, appKey+1, len);
    key[len] = 0;

    pthread_mutex_lock(&appsLock);
    WSAppRecord *app = [apps objectForKey:[NSString stringWithCString:key]];
    if(app != nil && [app isKindOfClass:[WSAppRecord class]]) {
        mach_port_t appPort = [app port];
        pthread_mutex_unlock(&appsLock);
        [self sendInlineData:&data length:sizeof(data) withCode:CODE_WINDOW_STATE toPort:appPort];
    } else {
        pthread_mutex_unlock(&appsLock);
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

- (BOOL)sendInlineData:(void *)data length:(int)length withCode:(int)code toPort:(mach_port_t)port {
    Message msg = {0};
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = code;
    msg.pid = getpid();
    strncpy(msg.bundleID, WINDOWSERVER_SVC_NAME, sizeof(msg.bundleID)-1);

    memcpy(msg.data, data, length);
    msg.len = length;

    int ret;
    if((ret = mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
        sizeof(msg) - sizeof(mach_msg_trailer_t), 0, MACH_PORT_NULL, 2000 /* ms timeout */,
        MACH_PORT_NULL)) != MACH_MSG_SUCCESS) {
        char errbuf[128];
        int n = snprintf(errbuf, sizeof(errbuf), "[WS] sendInlineData failed to port %u: 0x%x\n", port, ret);
        write(2, errbuf, n);
        return NO;
    }
    char okbuf[128];
    int n = snprintf(okbuf, sizeof(okbuf), "[WS] sendInlineData reply OK to port %u\n", port);
    write(2, okbuf, n);
    return YES;
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

@end

