#import "LogCollector.h"
#import "ConsoleController.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <time.h>

static NSString *levelFromSyslogPri(int pri) {
    int sev = pri & 7;
    switch (sev) {
        case 0: case 1: case 2: return @"Fault";
        case 3: return @"Error";
        case 4: return @"Warning";
        case 5: return @"Notice";
        case 6: return @"Info";
        case 7: return @"Debug";
    }
    return @"Default";
}

static NSString *monthName(int m) {
    static const char *names[] = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
    if (m < 1 || m > 12) return @"Jan";
    return [NSString stringWithUTF8String:names[m-1]];
}

@implementation LogEntry
@synthesize timestamp, process, pid, level, message, raw, source;
@end

@interface LogCollector () {
    NSTimer *_timer;
    int _sock;
    NSMutableDictionary *_fileOffsets;   // path -> NSNumber offset
    NSMutableSet *_seenKernel;
    NSMutableSet *_seenCrash;
    NSString *_lastKernelBuf;
    NSMutableArray *_tmpFiles;
}
@end

@implementation LogCollector

- (id)initWithController:(ConsoleController *)controller {
    self = [super init];
    if (self) {
        _controller = controller;
        _fileOffsets = [NSMutableDictionary dictionary];
        _seenKernel = [NSMutableSet set];
        _seenCrash = [NSMutableSet set];
        _tmpFiles = [NSMutableArray array];
        _sock = -1;
        _lastKernelBuf = @"";
    }
    return self;
}

/* Read the kernel message buffer.  sysctl kern.msgbuf only reports or sets
 * the buffer SIZE; the contents come from proc_info with the
 * PROC_INFO_CALL_KERNMSGBUF call, which is what /sbin/dmesg uses. */
extern int __proc_info(int callnum, int pid, uint32_t flavor, uint64_t arg,
                       void *buffer, int32_t buffersize);

/* The build SDK's proc_info.h predates the kernel-log call; the number is
 * ABI (xnu bsd/sys/proc_info.h). */
#ifndef PROC_INFO_CALL_KERNMSGBUF
#define PROC_INFO_CALL_KERNMSGBUF 0x4
#endif

- (void)start {
    NSLog(@"[Console] log collector started");

    // bind datagram socket
    unlink("/var/run/syslog");
    mkdir("/var/run", 0755);
    _sock = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (_sock >= 0) {
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, "/var/run/syslog", sizeof(addr.sun_path)-1);
        if (bind(_sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
            close(_sock); _sock = -1;
        } else {
            int flags = fcntl(_sock, F_GETFL, 0);
            fcntl(_sock, F_SETFL, flags | O_NONBLOCK);
        }
    }
    mkdir("/var/log", 0755);
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
    [self tick:nil];
}

- (void)stop {
    if (_timer) { [_timer invalidate]; _timer = nil; }
    if (_sock >= 0) { close(_sock); _sock = -1; unlink("/var/run/syslog"); }
}

- (void)deliver:(NSArray *)batch {
    if (batch.count == 0) return;
    if ([NSThread isMainThread]) {
        [_controller appendEntries:batch];
    } else {
        [self performSelectorOnMainThread:@selector(deliver:) withObject:batch waitUntilDone:NO];
    }
}

- (LogEntry *)entryWithTimestamp:(NSString *)ts process:(NSString *)proc pid:(int)pid level:(NSString *)lvl message:(NSString *)msg raw:(NSString *)raw source:(NSString *)src {
    LogEntry *e = [LogEntry new];
    e.timestamp = ts ? ts : @"";
    e.process = proc ? proc : @"";
    e.pid = pid;
    e.level = lvl ? lvl : @"Default";
    e.message = msg ? msg : @"";
    e.raw = raw ? raw : @"";
    e.source = src ? src : @"";
    return e;
}

- (NSString *)nowTimestamp {
    NSDateFormatter *f = [NSDateFormatter new];
    [f setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    return [f stringFromDate:[NSDate date]];
}

- (void)tailFile:(NSString *)path source:(NSString *)source {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return;
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    unsigned long long size = [attrs fileSize];
    NSNumber *offNum = _fileOffsets[path];
    unsigned long long offset = offNum ? [offNum unsignedLongLongValue] : 0;
    if (size < offset) offset = 0; // rotated
    if (size == offset) return;
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return;
    [fh seekToFileOffset:offset];
    NSData *data = [fh readDataToEndOfFile];
    [fh closeFile];
    if (!data || data.length == 0) return;
    NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!chunk) chunk = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (!chunk) return;
    _fileOffsets[path] = [NSNumber numberWithUnsignedLongLong:size];
    // split lines
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *l in [chunk componentsSeparatedByString:@"\n"]) {
        if (l.length > 0) [lines addObject:l];
    }
    NSMutableArray *batch = [NSMutableArray array];
    for (NSString *line in lines) {
        LogEntry *e = [self parseLine:line source:source];
        [batch addObject:e];
    }
    [self deliver:batch];
}

- (LogEntry *)parseLine:(NSString *)line source:(NSString *)source {
    // Try NSLog format: "YYYY-MM-DD HH:MM:SS.mmm Process[PID] <Level>: message" or "Process[PID] ..."
    // Fallback: whole line as message, level Default
    NSString *ts = @"";
    NSString *proc = @"";
    int pid = 0;
    NSString *level = @"Default";
    NSString *msg = line;
    // syslog format: "<PRI>MMM DD HH:MM:SS host tag[pid]: message"
    if ([line hasPrefix:@"<"]) {
        NSRange gt = [line rangeOfString:@">"];
        if (gt.location != NSNotFound) {
            int pri = [[line substringWithRange:NSMakeRange(1, gt.location-1)] intValue];
            level = levelFromSyslogPri(pri);
            NSString *rest = [line substringFromIndex:gt.location+1];
            // parse
            // MMM DD HH:MM:SS
            // simple: take first 15 chars as timestamp-ish
            if (rest.length > 15) {
                ts = [rest substringToIndex:15];
                rest = [rest substringFromIndex:16]; // skip space
            }
            // host
            NSRange sp = [rest rangeOfString:@" "];
            if (sp.location != NSNotFound) {
                rest = [rest substringFromIndex:sp.location+1];
            }
            // tag[pid]:
            NSRange colon = [rest rangeOfString:@": "];
            if (colon.location != NSNotFound) {
                NSString *tagpart = [rest substringToIndex:colon.location];
                msg = [rest substringFromIndex:colon.location+2];
                // tag[pid]
                NSRange bracket = [tagpart rangeOfString:@"["];
                if (bracket.location != NSNotFound) {
                    proc = [tagpart substringToIndex:bracket.location];
                    NSString *pidstr = [tagpart substringFromIndex:bracket.location+1];
                    pidstr = [pidstr stringByReplacingOccurrencesOfString:@"]" withString:@""];
                    pid = [pidstr intValue];
                } else {
                    proc = tagpart;
                }
            } else {
                msg = rest;
            }
        }
    } else {
        // NSLog format detection: starts with date?
        // "YYYY-MM-DD HH:MM:SS.mmm Process[PID] <Level>: message" or "YYYY-MM-DD ... Process[PID]: message"
        // Try regex-ish manual
        if (line.length > 23 && [line characterAtIndex:4] == '-' && [line characterAtIndex:7] == '-') {
            ts = [line substringToIndex:23];
            NSString *rest = (line.length > 24) ? [line substringFromIndex:24] : @"";
            // Process[PID]
            NSRange bracket = [rest rangeOfString:@"["];
            NSRange closeB = [rest rangeOfString:@"]"];
            if (bracket.location != NSNotFound && closeB.location > bracket.location) {
                proc = [rest substringToIndex:bracket.location];
                NSString *pidstr = [rest substringWithRange:NSMakeRange(bracket.location+1, closeB.location-bracket.location-1)];
                pid = [pidstr intValue];
                rest = (closeB.location+1 < rest.length) ? [rest substringFromIndex:closeB.location+1] : @"";
                // skip space
                if (rest.length > 0 && [rest characterAtIndex:0] == ' ') rest = [rest substringFromIndex:1];
                // level in <>
                if (rest.length > 0 && [rest characterAtIndex:0] == '<') {
                    NSRange gt = [rest rangeOfString:@">"];
                    if (gt.location != NSNotFound) {
                        level = [rest substringWithRange:NSMakeRange(1, gt.location-1)];
                        rest = (gt.location+1 < rest.length) ? [rest substringFromIndex:gt.location+1] : @"";
                        if (rest.length > 0 && [rest characterAtIndex:0] == ':') rest = [rest substringFromIndex:1];
                        if (rest.length > 0 && [rest characterAtIndex:0] == ' ') rest = [rest substringFromIndex:1];
                    }
                } else if (rest.length > 0 && [rest characterAtIndex:0] == ':') {
                    rest = [rest substringFromIndex:1];
                    if (rest.length > 0 && [rest characterAtIndex:0] == ' ') rest = [rest substringFromIndex:1];
                }
                msg = rest;
            } else {
                msg = line;
            }
        }
    }
    if (level.length == 0) level = @"Default";
    return [self entryWithTimestamp:ts process:proc pid:pid level:level message:msg raw:line source:source];
}

- (void)tick:(NSTimer *)t {
    // kernel
    [self pollKernel];
    // files
    [self tailFile:@"/var/log/system.log" source:@"system.log"];
    [self tailFile:@"/var/log/windowserver.log" source:@"system.log"];
    // /tmp/*.log
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *tmpContents = [fm contentsOfDirectoryAtPath:@"/tmp" error:nil];
    for (NSString *name in tmpContents) {
        if ([name hasSuffix:@".log"]) {
            [self tailFile:[@"/tmp" stringByAppendingPathComponent:name] source:@"system.log"];
        }
    }
    // crash reports
    [self scanCrashReports];
    // socket
    [self drainSocket];
}

- (void)pollKernel {
    int bufSize = 0;
    size_t len = sizeof(bufSize);
    int got = 0;
    char *buf;
    NSString *s;

    if (sysctlbyname("kern.msgbuf", &bufSize, &len, NULL, 0) != 0 || bufSize <= 0)
        bufSize = 65536;

    buf = (char *)calloc(1, (size_t)bufSize + 1);
    if (buf == NULL) return;

    got = __proc_info(PROC_INFO_CALL_KERNMSGBUF, 0, 0, 0, buf, bufSize);
    if (got <= 0) {
        free(buf);
        /* Older kernels expose the buffer as a character device. */
        [self tailFile:@"/dev/klog" source:@"Kernel"];
        return;
    }
    if (got > bufSize) got = bufSize;
    s = [[NSString alloc] initWithBytes:buf length:(NSUInteger)got encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithBytes:buf length:(NSUInteger)got encoding:NSASCIIStringEncoding];
    free(buf);
    if (!s) return;
    if ([s isEqualToString:_lastKernelBuf]) return;
    // find new suffix
    NSString *newPart = s;
    if (_lastKernelBuf.length > 0 && s.length > _lastKernelBuf.length) {
        // if s starts with lastKernelBuf, take tail
        if ([s hasPrefix:_lastKernelBuf]) {
            newPart = [s substringFromIndex:_lastKernelBuf.length];
        }
    }
    _lastKernelBuf = s;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *l in [newPart componentsSeparatedByString:@"\n"]) {
        if (l.length > 0) [lines addObject:l];
    }
    NSMutableArray *batch = [NSMutableArray array];
    for (NSString *line in lines) {
        if ([_seenKernel containsObject:line]) continue;
        [_seenKernel addObject:line];
        LogEntry *e = [self entryWithTimestamp:[self nowTimestamp] process:@"kernel" pid:0 level:@"Default" message:line raw:line source:@"Kernel"];
        [batch addObject:e];
    }
    [self deliver:batch];
}

- (void)scanCrashReports {
    NSArray *dirs = @[
        @"/Library/Logs/DiagnosticReports",
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"]
    ];
    NSMutableArray *batch = [NSMutableArray array];
    for (NSString *dir in dirs) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *name in files) {
            if (!([name hasSuffix:@".ips"] || [name hasSuffix:@".crash"])) continue;
            NSString *path = [dir stringByAppendingPathComponent:name];
            if ([_seenCrash containsObject:path]) continue;
            [_seenCrash addObject:path];
            NSData *data = [fm contentsAtPath:path];
            if (!data) continue;
            NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!content) content = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
            if (!content) continue;
            LogEntry *e = [self entryWithTimestamp:[self nowTimestamp] process:name pid:0 level:@"Fault" message:content raw:content source:@"Crash Reports"];
            [batch addObject:e];
        }
    }
    [self deliver:batch];
}

- (void)drainSocket {
    if (_sock < 0) return;
    char buf[65536];
    NSMutableArray *batch = [NSMutableArray array];
    for (;;) {
        ssize_t n = recv(_sock, buf, sizeof(buf)-1, 0);
        if (n <= 0) break;
        buf[n] = '\0';
        NSString *s = [NSString stringWithUTF8String:buf];
        if (!s) continue;
        LogEntry *e = [self parseLine:s source:@"system.log"];
        // mark source as system.log (already)
        [batch addObject:e];
    }
    [self deliver:batch];
}

@end