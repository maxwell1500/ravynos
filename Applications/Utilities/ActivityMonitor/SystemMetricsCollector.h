#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface ProcessInfo : NSObject
@property (assign) pid_t pid;
@property (assign) pid_t ppid;
@property (copy) NSString *name;
@property (copy) NSString *user;
@property (assign) double cpuPercent;
@property (assign) double memoryMB;
@property (assign) int threads;
@property (assign) uint64_t totalUserTime;
@property (assign) uint64_t totalSystemTime;
@end

@interface SystemMetricsCollector : NSObject
@property (assign) double cpuUserPercent;
@property (assign) double cpuSystemPercent;
@property (assign) double cpuIdlePercent;
@property (assign) uint64_t memoryTotal;
@property (assign) uint64_t memoryWired;
@property (assign) uint64_t memoryActive;
@property (assign) uint64_t memoryInactive;
@property (assign) uint64_t memoryFree;
@property (assign) double memoryPressure;
@property (strong) NSArray *processes;
@property (strong) NSArray *volumes;
@property (assign) double netInKBPerSec;
@property (assign) double netOutKBPerSec;
@property (assign) double netInPacketsPerSec;
@property (assign) double netOutPacketsPerSec;

- (void)refresh;
- (NSArray *)openFileDescriptorsForPid:(pid_t)pid;
- (NSString *)executablePathForPid:(pid_t)pid;
@end