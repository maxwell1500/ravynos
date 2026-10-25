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

#import <unistd.h>
#import <sys/sysctl.h>
#import "common.h"
#import "WindowServer.h"
#import <sys/event.h>
#import <servers/bootstrap.h>
#import "message.h"

extern void bootstrap_init(void);
extern int optopt;
static jmp_buf jb;

static void initSysvShmLimits(void) {
    /* XNU defaults shmmax to 4MB and shmall to 1024 pages (4MB total), which
     * rejects any full-screen capture segment for 1920x1080 (8.29MB).
     * Bump to 64MB / 32768 pages (128MB) so captures succeed. */
    int64_t max = 64 * 1024 * 1024;
    int64_t all = (128 * 1024 * 1024) / 4096;
    sysctlbyname("kern.sysv.shmmax", NULL, NULL, &max, sizeof(max));
    sysctlbyname("kern.sysv.shmall", NULL, NULL, &all, sizeof(all));
}

void *machSvcLoop(void *arg) {
    WindowServer *ws = (__bridge WindowServer *)arg;
    while(1)
        [ws receiveMachMessage];
}

void *kqSvcLoop(void *arg) {
    WindowServer *ws = (__bridge WindowServer *)arg;
    while(1)
        [ws processKernelQueue];
} 

static void crashHandler(int sig) {
    longjmp(jb, SIGSEGV);
}

int main(int argc, const char *argv[]) {
    write(2, "[WS] main entered\n", 18);
    bootstrap_init();
    write(2, "[WS] bootstrap_init done\n", 25);
    initSysvShmLimits();
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    write(2, "[WS] pool created\n", 18);
    int logLevel = WS_ERROR;
    int curShell = DESKTOP; /* ravynOS: auto-login root, skip Loading/Login */
    WindowServer *ws = nil;
    [pool drain];
    write(2, "[WS] pool drained\n", 18);

    /* Become immortal. Mwahahahaha! 
     * Note: don't trap SIGCHLD - we need it to wait on process exits
     */
    signal(SIGHUP, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGALRM, SIG_IGN);
    signal(SIGTTIN, SIG_IGN);
    signal(SIGTTOU, SIG_IGN);
    signal(SIGTSTP, SIG_IGN);
    signal(SIGUSR1, SIG_IGN);
    signal(SIGUSR2, SIG_IGN);
    write(2, "[WS] signals ignored OK\n", 24);
    pthread_t machSvcThread;
    pthread_t kqThread;
    bool svcThreadLive = false, kqThreadLive = false;
    write(2, "[WS] creating WindowServer instance\n", 36);
    ws = [WindowServer new];
    if(ws == nil) {
        write(2, "[WS] WindowServer new returned nil\n", 35);
        exit(1);
    }
    write(2, "[WS] WindowServer instance created OK\n", 38);
    int opt;
    while((opt = getopt(argc, (char * const *)argv, "LxvD:")) != -1) {
        switch(opt) {
            case 'L': // bypass loginwindow, run desktop for current user
                curShell = DESKTOP;
                break;
            case 'x': // just run the compositor
                curShell = NONE;
                break;
            case 'v':
                logLevel++;
                break;
            case 'D':
                if(optarg != NULL) {
                    if(optarg[1] != '=') break;
                    int level = MAX(0, optarg[2] - '0');
                    level = MIN(level, WS_INFO);
                    [ws setDebugLevel:level subsystem:optarg[0]];
                }
                break;
        }
    }
    [ws setLogLevel:logLevel];

    /* Message/RPC structs are 128 KB each and the receive path nests
     * several of them (receiveMachMessage -> deactivateApp:/notifyDock: ...),
     * so the service threads need far more than the pthread default or they
     * die with a stack-overflow fault the moment an app registers. */
    pthread_attr_t svcAttr;
    pthread_attr_init(&svcAttr);
    pthread_attr_setstacksize(&svcAttr, 8 * 1024 * 1024);
    svcThreadLive = pthread_create(&machSvcThread, &svcAttr, machSvcLoop, (__bridge void *)ws) == 0;
    kqThreadLive = pthread_create(&kqThread, &svcAttr, kqSvcLoop, (__bridge void *)ws) == 0;
    pthread_attr_destroy(&svcAttr);
    [ws setShell:curShell];
    write(2, "[WS] entering ws run\n", 22);
    [ws run];
    ws = nil;

__finish:
    if(svcThreadLive)
        pthread_cancel(machSvcThread);
    if(kqThreadLive)
        pthread_cancel(kqThread);
    exit(0);
}

