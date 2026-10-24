#import "SystemMetricsCollector.h"
#import <sys/sysctl.h>
#import <sys/proc.h>
#import <sys/proc_info.h>
#import <libproc.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/processor_info.h>
#import <mach/vm_statistics.h>
 #import <mach/mach_time.h>
#import <ifaddrs.h>
#import <sys/mount.h>
#import <pwd.h>
#import <unistd.h>
#import <stdlib.h>
#import <string.h>

@implementation ProcessInfo
@synthesize pid, ppid, name, user, cpuPercent, memoryMB, threads, totalUserTime, totalSystemTime;
@end

@interface SystemMetricsCollector () {
    NSMutableDictionary *_prevTimes; // pid -> NSNumber total mach time
    CFAbsoluteTime _lastSampleTime;
    // CPU ticks
    uint64_t _prevCPUTicks[4];
    BOOL _hasPrevCPUTicks;
    // Network
    uint64_t _prevNetInBytes, _prevNetOutBytes, _prevNetInPackets, _prevNetOutPackets;
    CFAbsoluteTime _lastNetTime;
    BOOL _hasPrevNet;
}
@end

@implementation SystemMetricsCollector

- (id)init {
    self = [super init];
    if (self) {
        _prevTimes = [NSMutableDictionary dictionary];
        _lastSampleTime = 0;
        _hasPrevCPUTicks = NO;
        _hasPrevNet = NO;
        memset(_prevCPUTicks, 0, sizeof(_prevCPUTicks));
    }
    return self;
}

static uint64_t _nsFromMach(uint64_t t) {
    mach_timebase_info_data_t info = {0};
    mach_timebase_info(&info);
    if (info.denom == 0) return t;
    return t * info.numer / info.denom;
}

- (void)refresh {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    // --- Process list ---
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) == 0 && size > 0) {
        struct kinfo_proc *procs = malloc(size);
        if (procs && sysctl(mib, 3, procs, &size, NULL, 0) == 0) {
            int count = (int)(size / sizeof(struct kinfo_proc));
            NSMutableArray *list = [NSMutableArray array];
            CFAbsoluteTime interval = (_lastSampleTime > 0) ? (now - _lastSampleTime) : 0;
            for (int i = 0; i < count; i++) {
                pid_t pid = procs[i].kp_proc.p_pid;
                if (pid <= 0) continue;
                struct proc_taskallinfo tai;
                memset(&tai, 0, sizeof(tai));
                int ret = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &tai, sizeof(tai));
                if (ret <= 0) {
                    // fall back to kinfo_proc fields
                }
                ProcessInfo *pi = [[ProcessInfo alloc] init];
                pi.pid = pid;
                pi.ppid = procs[i].kp_eproc.e_ppid;
                if (tai.ptinfo.pti_threadnum > 0 || ret > 0) {
                    char *comm = tai.pbsd.pbi_comm;
                    if (comm[0]) pi.name = [NSString stringWithUTF8String:comm];
                    else pi.name = [NSString stringWithUTF8String:procs[i].kp_proc.p_comm];
                    struct passwd *pw = getpwuid(tai.pbsd.pbi_uid ? tai.pbsd.pbi_uid : procs[i].kp_eproc.e_ucred.cr_uid);
                    if (pw && pw->pw_name) pi.user = [NSString stringWithUTF8String:pw->pw_name];
                    else pi.user = [NSString stringWithFormat:@"%u", (unsigned)(procs[i].kp_eproc.e_ucred.cr_uid)];
                    pi.memoryMB = (double)tai.ptinfo.pti_resident_size / (1024.0 * 1024.0);
                    pi.threads = tai.ptinfo.pti_threadnum;
                    uint64_t total = tai.ptinfo.pti_total_user + tai.ptinfo.pti_total_system;
                    pi.totalUserTime = tai.ptinfo.pti_total_user;
                    pi.totalSystemTime = tai.ptinfo.pti_total_system;
                    // CPU %
                    NSNumber *prev = _prevTimes[@(pid)];
                    if (prev && interval > 0) {
                        uint64_t prevTotal = [prev unsignedLongLongValue];
                        if (total >= prevTotal) {
                            uint64_t delta = total - prevTotal;
                            double deltaNs = (double)_nsFromMach(delta);
                            double intervalNs = interval * 1e9;
                            if (intervalNs > 0) pi.cpuPercent = (deltaNs / intervalNs) * 100.0;
                        }
                    }
                    _prevTimes[@(pid)] = @(total);
                } else {
                    pi.name = [NSString stringWithUTF8String:procs[i].kp_proc.p_comm];
                    struct passwd *pw = getpwuid(procs[i].kp_eproc.e_ucred.cr_uid);
                    if (pw && pw->pw_name) pi.user = [NSString stringWithUTF8String:pw->pw_name];
                    else pi.user = [NSString stringWithFormat:@"%u", (unsigned)procs[i].kp_eproc.e_ucred.cr_uid];
                    pi.memoryMB = 0;
                    pi.threads = 0;
                    pi.cpuPercent = 0;
                }
                [list addObject:pi];
            }
            self.processes = list;
        }
        free(procs);
    }
    _lastSampleTime = now;

    // --- Host CPU ---
    host_cpu_load_info_data_t cpuInfo;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info64_t)&cpuInfo, &count) == KERN_SUCCESS) {
        uint64_t ticks[4] = { cpuInfo.cpu_ticks[CPU_STATE_USER], cpuInfo.cpu_ticks[CPU_STATE_SYSTEM],
                             cpuInfo.cpu_ticks[CPU_STATE_IDLE], cpuInfo.cpu_ticks[CPU_STATE_NICE] };
        if (_hasPrevCPUTicks) {
            uint64_t du = ticks[0] - _prevCPUTicks[0];
            uint64_t ds = ticks[1] - _prevCPUTicks[1];
            uint64_t di = ticks[2] - _prevCPUTicks[2];
            uint64_t dn = ticks[3] - _prevCPUTicks[3];
            uint64_t total = du + ds + di + dn;
            if (total > 0) {
                self.cpuUserPercent = (double)(du + dn) / (double)total * 100.0;
                self.cpuSystemPercent = (double)ds / (double)total * 100.0;
                self.cpuIdlePercent = (double)di / (double)total * 100.0;
            }
        }
        memcpy(_prevCPUTicks, ticks, sizeof(ticks));
        _hasPrevCPUTicks = YES;
    }

    // --- Memory ---
    vm_size_t pageSize = 0;
    host_page_size(mach_host_self(), &pageSize);
    vm_statistics64_data_t vm;
    mach_msg_type_number_t vmCount = HOST_VM_INFO64_COUNT;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vm, &vmCount) == KERN_SUCCESS) {
        self.memoryWired = (uint64_t)vm.wire_count * pageSize;
        self.memoryActive = (uint64_t)vm.active_count * pageSize;
        self.memoryInactive = (uint64_t)vm.inactive_count * pageSize;
        self.memoryFree = (uint64_t)vm.free_count * pageSize;
    }
    uint64_t memsize = 0;
    size_t ms = sizeof(memsize);
    if (sysctlbyname("hw.memsize", &memsize, &ms, NULL, 0) == 0) {
        self.memoryTotal = memsize;
    }
    // memory pressure: (active+wired)/total
    if (self.memoryTotal > 0) {
        self.memoryPressure = (double)(self.memoryWired + self.memoryActive) / (double)self.memoryTotal;
        if (self.memoryPressure > 1.0) self.memoryPressure = 1.0;
    }

    // --- Volumes ---
    int fsCount = getfsstat(NULL, 0, MNT_NOWAIT);
    if (fsCount > 0) {
        size_t bufSize = fsCount * sizeof(struct statfs);
        struct statfs *bufs = malloc(bufSize);
        if (bufs) {
            int n = getfsstat(bufs, (int)bufSize, MNT_NOWAIT);
            NSMutableArray *vols = [NSMutableArray array];
            for (int i = 0; i < n; i++) {
                uint64_t total = (uint64_t)bufs[i].f_blocks * bufs[i].f_bsize;
                uint64_t avail = (uint64_t)bufs[i].f_bavail * bufs[i].f_bsize;
                uint64_t used = total - avail;
                NSDictionary *d = @{
                    @"name": [NSString stringWithUTF8String:bufs[i].f_mntonname],
                    @"from": [NSString stringWithUTF8String:bufs[i].f_mntfromname],
                    @"type": [NSString stringWithUTF8String:bufs[i].f_fstypename],
                    @"total": @(total),
                    @"used": @(used),
                    @"avail": @(avail),
                };
                [vols addObject:d];
            }
            self.volumes = vols;
            free(bufs);
        }
    }

    // --- Network ---
    struct ifaddrs *ifas = NULL;
    if (getifaddrs(&ifas) == 0) {
        uint64_t inBytes = 0, outBytes = 0, inPackets = 0, outPackets = 0;
        for (struct ifaddrs *ifa = ifas; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_data) continue;
            struct if_data *d = (struct if_data *)ifa->ifa_data;
            inBytes += d->ifi_ibytes;
            outBytes += d->ifi_obytes;
            inPackets += d->ifi_ipackets;
            outPackets += d->ifi_opackets;
        }
        if (_hasPrevNet && now > _lastNetTime) {
            double dt = now - _lastNetTime;
            if (dt > 0) {
                self.netInKBPerSec = (double)(inBytes - _prevNetInBytes) / 1024.0 / dt;
                self.netOutKBPerSec = (double)(outBytes - _prevNetOutBytes) / 1024.0 / dt;
                self.netInPacketsPerSec = (double)(inPackets - _prevNetInPackets) / dt;
                self.netOutPacketsPerSec = (double)(outPackets - _prevNetOutPackets) / dt;
            }
        }
        _prevNetInBytes = inBytes;
        _prevNetOutBytes = outBytes;
        _prevNetInPackets = inPackets;
        _prevNetOutPackets = outPackets;
        _lastNetTime = now;
        _hasPrevNet = YES;
        freeifaddrs(ifas);
    }
}

- (NSArray *)openFileDescriptorsForPid:(pid_t)pid {
    int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (size <= 0) return @[];
    int count = size / PROC_PIDLISTFD_SIZE;
    struct proc_fdinfo *fds = calloc(count + 1, sizeof(struct proc_fdinfo));
    if (!fds) return @[];
    int ret = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, size);
    NSMutableArray *out = [NSMutableArray array];
    if (ret > 0) {
        int n = ret / PROC_PIDLISTFD_SIZE;
        for (int i = 0; i < n; i++) {
            [out addObject:[NSString stringWithFormat:@"%d (type %u)", fds[i].proc_fd, fds[i].proc_fdtype]];
        }
    }
    free(fds);
    return out;
}

- (NSString *)executablePathForPid:(pid_t)pid {
    char buf[4096];
    memset(buf, 0, sizeof(buf));
    if (proc_pidpath(pid, buf, sizeof(buf)) > 0) {
        return [NSString stringWithUTF8String:buf];
    }
    return nil;
}

@end