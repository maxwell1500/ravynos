/*
 * PortRunner.m - MacPorts background task execution engine with streaming output
 *
 * The reader runs on its own NSThread and hands every line to the main thread
 * with performSelectorOnMainThread:.  Do not "simplify" this to dispatch_async
 * on the main queue: nothing in this tree's AppKit drains the libdispatch main
 * queue, so those blocks never run and installs silently do nothing.
 */
#import "PortRunner.h"

@interface PortRunner () {
    NSTask *_currentTask;
    NSPipe *_outputPipe;
    BOOL _isRunning;
    NSString *_currentPort;
}
- (void)_deliverLine:(NSString *)line;
- (void)_deliverFinish:(NSNumber *)status;
- (void)_readerThreadMain:(NSFileHandle *)readHandle;
@end

@implementation PortRunner

@synthesize isRunning = _isRunning;
@synthesize currentPort = _currentPort;

+ (instancetype)sharedRunner {
    static PortRunner *s_instance = nil;
    @synchronized([PortRunner class]) {
        if (s_instance == nil)
            s_instance = [[PortRunner alloc] init];
    }
    return s_instance;
}

- (BOOL)_launchPortWithArguments:(NSArray<NSString *> *)arguments forPort:(NSString *)portName {
    if (_isRunning) {
        return NO;
    }
    _isRunning = YES;
    _currentPort = [portName copy];

    NSString *portBin = @"/opt/local/bin/port";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:portBin]) {
        // Fallback for testing/uninstalled environment
        portBin = @"/usr/bin/port";
    }

    _outputPipe = [NSPipe pipe];
    _currentTask = [[NSTask alloc] init];
    [_currentTask setLaunchPath:portBin];
    [_currentTask setArguments:arguments];
    [_currentTask setStandardOutput:_outputPipe];
    [_currentTask setStandardError:_outputPipe];

    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    env[@"PATH"] = @"/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
    env[@"COLUMNS"] = @"120";
    [_currentTask setEnvironment:env];

    NSFileHandle *readHandle = [_outputPipe fileHandleForReading];

    @try {
        [_currentTask launch];
    } @catch (NSException *ex) {
        _isRunning = NO;
        _currentPort = nil;
        _currentTask = nil;
        _outputPipe = nil;
        [self _handleOutputLine:[NSString stringWithFormat:@"Error launching port: %@", ex.reason]];
        return NO;
    }

    [self performSelectorInBackground:@selector(_readerThreadMain:) withObject:readHandle];
    return YES;
}

- (void)_readerThreadMain:(NSFileHandle *)readHandle {
    NSTask *task = _currentTask;
    NSMutableData *lineBuffer = [[NSMutableData alloc] init];
    NSData *data;

    while (1) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        data = [readHandle availableData];
        if ([data length] == 0) {
            [pool drain];
            break;
        }
        [lineBuffer appendData:data];

        const char *bytes = [lineBuffer bytes];
        NSUInteger len = [lineBuffer length];
        NSUInteger start = 0;

        for (NSUInteger i = 0; i < len; i++) {
            if (bytes[i] == '\n' || bytes[i] == '\r') {
                if (i > start) {
                    NSData *chunk = [lineBuffer subdataWithRange:NSMakeRange(start, i - start)];
                    NSString *line = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
                    if (line && [line length] > 0) {
                        [self performSelectorOnMainThread:@selector(_deliverLine:)
                                               withObject:line
                                            waitUntilDone:NO];
                    }
                }
                start = i + 1;
            }
        }
        if (start > 0) {
            [lineBuffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
        }
        [pool drain];
    }

    if ([lineBuffer length] > 0) {
        NSString *line = [[NSString alloc] initWithData:lineBuffer encoding:NSUTF8StringEncoding];
        if (line && [line length] > 0) {
            [self performSelectorOnMainThread:@selector(_deliverLine:) withObject:line waitUntilDone:NO];
        }
    }

    [task waitUntilExit];
    int status = [task terminationStatus];
    [self performSelectorOnMainThread:@selector(_deliverFinish:)
                           withObject:[NSNumber numberWithInt:status]
                        waitUntilDone:NO];
}

- (void)_deliverLine:(NSString *)line {
    if ([self.delegate respondsToSelector:@selector(portRunnerDidOutputLine:)]) {
        [self.delegate portRunnerDidOutputLine:line];
    }
    [self _handleOutputLine:line];
}

- (void)_deliverFinish:(NSNumber *)statusNumber {
    int status = [statusNumber intValue];
    _isRunning = NO;
    _currentPort = nil;
    _currentTask = nil;
    _outputPipe = nil;

    if ([self.delegate respondsToSelector:@selector(portRunnerDidFinishWithSuccess:exitCode:)]) {
        [self.delegate portRunnerDidFinishWithSuccess:(status == 0) exitCode:status];
    }
}

- (void)_handleOutputLine:(NSString *)line {
    if (![self.delegate respondsToSelector:@selector(portRunnerDidUpdateStatus:progress:)]) {
        return;
    }

    if ([line rangeOfString:@"--->  Computing dependencies"].location != NSNotFound) {
        [self _updateProgress:0.15 status:@"Computing dependencies..."];
    } else if ([line rangeOfString:@"--->  Fetching archive"].location != NSNotFound) {
        [self _updateProgress:0.35 status:@"Fetching precompiled package..."];
    } else if ([line rangeOfString:@"--->  Verifying checksums"].location != NSNotFound) {
        [self _updateProgress:0.50 status:@"Verifying package checksums..."];
    } else if ([line rangeOfString:@"--->  Extracting"].location != NSNotFound) {
        [self _updateProgress:0.65 status:@"Extracting files..."];
    } else if ([line rangeOfString:@"--->  Installing"].location != NSNotFound) {
        [self _updateProgress:0.80 status:@"Installing package..."];
    } else if ([line rangeOfString:@"--->  Activating"].location != NSNotFound) {
        [self _updateProgress:0.95 status:@"Activating package..."];
    } else if ([line rangeOfString:@"--->  Cleaning"].location != NSNotFound) {
        [self _updateProgress:1.00 status:@"Finalizing installation..."];
    }
}

- (void)_updateProgress:(double)prog status:(NSString *)status {
    if ([self.delegate respondsToSelector:@selector(portRunnerDidUpdateStatus:progress:)]) {
        [self.delegate portRunnerDidUpdateStatus:status progress:prog];
    }
}

- (BOOL)installPort:(NSString *)portName {
    return [self _launchPortWithArguments:@[@"-v", @"install", portName] forPort:portName];
}

- (BOOL)uninstallPort:(NSString *)portName {
    return [self _launchPortWithArguments:@[@"-v", @"uninstall", portName] forPort:portName];
}

- (BOOL)syncPorts {
    return [self _launchPortWithArguments:@[@"-v", @"selfupdate"] forPort:@"selfupdate"];
}

- (void)cancelCurrentOperation {
    if (_isRunning && _currentTask) {
        [_currentTask terminate];
    }
}

@end
