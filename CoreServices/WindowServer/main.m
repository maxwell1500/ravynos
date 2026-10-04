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
#import "common.h"
#import "WindowServer.h"
#import <sys/event.h>
#import <servers/bootstrap.h>
#import "message.h"

extern int optopt;
static jmp_buf jb;

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
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    int logLevel = WS_ERROR;
    srandomdev();
    int curShell = LOADING;
    WindowServer *ws = nil;
    [pool drain];

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

    /* Drop our controlling terminal - we're gonna switch */
    /* This is the recommended but sucky way. Using TIOCNOTTY isn't working */
    pid_t pid = fork();
    int status;
    switch(pid) {
        case -1: NSLog(@"fork: %s", strerror(errno)); exit(1);
        case 0: break; // let child continue
        default: NSLog(@"parent: waiting"); waitpid(pid, &status, 0); exit(status); // parent
    }

    pthread_t machSvcThread;
    pthread_t kqThread;
    bool svcThreadLive = false, kqThreadLive = false;

    setsid(); // Start a new session

    /* FreeBSD allocated a private vt(4) here and switched the console onto it.
     * Darwin has neither vt(4) nor syscons: there is no VT_GETACTIVE /
     * VT_OPENQRY / VT_SETMODE / CONS_MOUSECTL, no vtmode_t and no tcsetsid.
     * On ravynOS the display is reached directly through /dev/console, which
     * WindowServer's BSDFramebuffer opens for itself, so there is no console
     * handover for us to perform.
     */
    if(setjmp(jb) != 0)
        goto __finish; // sighandler must have caught something - get out

    ws = [WindowServer new];
    if(ws == nil)
        exit(1);

    while(getopt(argc, argv, "LxvD:") != -1) {
        switch(optopt) {
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

    svcThreadLive = pthread_create(&machSvcThread, NULL, machSvcLoop, (__bridge void *)ws) == 0;
    kqThreadLive = pthread_create(&kqThread, NULL, kqSvcLoop, (__bridge void *)ws) == 0;
    [ws setShell:curShell];
    [ws run];
    ws = nil;

__finish:
    if(svcThreadLive)
        pthread_cancel(machSvcThread);
    if(kqThreadLive)
        pthread_cancel(kqThread);
    exit(0);
}

