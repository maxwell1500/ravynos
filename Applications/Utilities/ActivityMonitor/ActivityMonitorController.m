#import "ActivityMonitorController.h"
#import <signal.h>
typedef struct { NSString *sortKey; BOOL asc; } AMSortCtx;

static NSInteger AMCompare(id a, id b, void *context) {
    AMSortCtx *ctx = (AMSortCtx *)context;
    NSString *key = ctx->sortKey;
    ProcessInfo *pa = (ProcessInfo *)a;
    ProcessInfo *pb = (ProcessInfo *)b;
    id va, vb;
    if ([key isEqualToString:@"name"]) { va = pa.name ?: @""; vb = pb.name ?: @""; }
    else if ([key isEqualToString:@"pid"]) { va = @(pa.pid); vb = @(pb.pid); }
    else if ([key isEqualToString:@"user"]) { va = pa.user ?: @""; vb = pb.user ?: @""; }
    else if ([key isEqualToString:@"cpu"]) { va = @(pa.cpuPercent); vb = @(pb.cpuPercent); }
    else if ([key isEqualToString:@"memory"]) { va = @(pa.memoryMB); vb = @(pb.memoryMB); }
    else if ([key isEqualToString:@"threads"]) { va = @(pa.threads); vb = @(pb.threads); }
    else { va = @(pa.pid); vb = @(pb.pid); }
    NSComparisonResult r;
    if ([va isKindOfClass:[NSString class]]) r = [va compare:vb];
    else r = [va compare:vb];
    if (!ctx->asc) r = (r == NSOrderedAscending) ? NSOrderedDescending : (r == NSOrderedDescending ? NSOrderedAscending : NSOrderedSame);
    return r;
}
static NSArray *kColumns(void) {
    return @[
        @[@"Process Name", @"name", @180.0],
        @[@"PID", @"pid", @60.0],
        @[@"User", @"user", @100.0],
        @[@"% CPU", @"cpu", @70.0],
        @[@"Memory (MB)", @"memory", @90.0],
        @[@"Threads", @"threads", @70.0],
    ];
}

@implementation ActivityMonitorController
@synthesize window, tableScroll, table, searchField, inspectButton, quitButton, tabSegment, graphView, collector, timer, sortKey, sortAscending, filtered, activeTab;

- (id)init {
    self = [super init];
    if (self) {
        collector = [[SystemMetricsCollector alloc] init];
        filtered = [NSMutableArray array];
        sortKey = @"cpu";
        sortAscending = NO;
        activeTab = 0;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self buildWindow];
    [self refresh:nil];
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(100, 80, 900, 620);
    window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [window setTitle:@"Activity Monitor"];
    [window setDelegate:self];
    [window center];

    NSView *content = [window contentView];
    NSRect cb = [content bounds];

    // Top bar: tabs + search + buttons
    NSRect barFrame = NSMakeRect(0, cb.size.height - 40, cb.size.width, 40);
    NSView *bar = [[NSView alloc] initWithFrame:barFrame];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    tabSegment = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(8, 8, 320, 24)];
    [tabSegment setSegmentCount:4];
    [tabSegment setLabel:@"CPU" forSegment:0];
    [tabSegment setLabel:@"Memory" forSegment:1];
    [tabSegment setLabel:@"Disk" forSegment:2];
    [tabSegment setLabel:@"Network" forSegment:3];
    [tabSegment setSelectedSegment:0];
    [tabSegment setTarget:self];
    [tabSegment setAction:@selector(tabChanged:)];
    [bar addSubview:tabSegment];

    searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(340, 8, 200, 24)];
    [[searchField cell] setPlaceholderString:@"Filter"];
    [searchField setTarget:self];
    [searchField setAction:@selector(searchChanged:)];
    [bar addSubview:searchField];

    inspectButton = [[NSButton alloc] initWithFrame:NSMakeRect(560, 8, 140, 24)];
    [inspectButton setTitle:@"Inspect Process"];
    [inspectButton setBezelStyle:NSRoundedBezelStyle];
    [inspectButton setTarget:self];
    [inspectButton setAction:@selector(inspectProcess:)];
    [bar addSubview:inspectButton];

    quitButton = [[NSButton alloc] initWithFrame:NSMakeRect(710, 8, 160, 24)];
    [quitButton setTitle:@"Quit / Force Quit"];
    [quitButton setBezelStyle:NSRoundedBezelStyle];
    [quitButton setTarget:self];
    [quitButton setAction:@selector(quitProcess:)];
    [bar addSubview:quitButton];

    [content addSubview:bar];

    // Table
    NSRect tableFrame = NSMakeRect(0, 110, cb.size.width, cb.size.height - 40 - 110);
    tableScroll = [[NSScrollView alloc] initWithFrame:tableFrame];
    [tableScroll setHasVerticalScroller:YES];
    [tableScroll setHasHorizontalScroller:YES];
    [tableScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    table = [[NSTableView alloc] initWithFrame:tableFrame];
    for (NSArray *c in kColumns()) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[1]];
        [col setWidth:[c[2] doubleValue]];
        [[col headerCell] setStringValue:c[0]];
        [table addTableColumn:col];
    }
    [table setDataSource:self];
    [table setDelegate:self];
    [tableScroll setDocumentView:table];
    [content addSubview:tableScroll];

    // Bottom graph panel (110 px)
    NSRect graphFrame = NSMakeRect(0, 0, cb.size.width, 110);
    graphView = [[GraphView alloc] initWithFrame:graphFrame];
    [graphView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:graphView];

    [window makeKeyAndOrderFront:nil];
}

- (NSArray *)sortedFiltered {
    NSString *q = [[searchField stringValue] lowercaseString];
    NSMutableArray *out = [NSMutableArray array];
    for (ProcessInfo *pi in collector.processes) {
        if ([q length] > 0) {
            NSString *name = [pi.name lowercaseString];
            NSString *user = [pi.user lowercaseString];
            if (!(([name rangeOfString:q].location != NSNotFound) || ([user rangeOfString:q].location != NSNotFound))) continue;
        }
        [out addObject:pi];
    }
    AMSortCtx ctx = { sortKey, sortAscending };
    NSArray *sorted = [out sortedArrayUsingFunction:AMCompare context:&ctx];
    return [NSMutableArray arrayWithArray:sorted];
    return out;
}

- (void)tabChanged:(id)sender {
    int tab = (int)[tabSegment selectedSegment];
    static const char *keys[] = { "cpu", "memory", "pid", "name" };

    activeTab = tab;
    if (tab >= 0 && tab < 4)
        sortKey = [NSString stringWithUTF8String:keys[tab]];
    sortAscending = (tab >= 2);
    [graphView setMode:tab];
    [self refresh:nil];
}

- (NSString *)summaryForTab:(int)tab {
    if (tab == 0)
        return [NSString stringWithFormat:@"User %.1f%%   System %.1f%%",
                collector.cpuUserPercent, collector.cpuSystemPercent];
    if (tab == 1)
        return [NSString stringWithFormat:@"Memory pressure %.0f%%   Free %.0f MB",
                collector.memoryPressure,
                (double)collector.memoryFree / (1024.0 * 1024.0)];
    if (tab == 2) {
        NSMutableString *text = [NSMutableString string];
        for (id vol in collector.volumes) {
            if ([text length] > 0) [text appendString:@"   "];
            [text appendFormat:@"%@ %.0f%%",
                [vol valueForKey:@"mountPoint"],
                [[vol valueForKey:@"usedBytes"] doubleValue] * 100.0 /
                    (([[vol valueForKey:@"totalBytes"] doubleValue] > 1.0)
                     ? [[vol valueForKey:@"totalBytes"] doubleValue] : 1.0)];
        }
        return [text length] ? text : @"No volumes";
    }
    return [NSString stringWithFormat:@"In %.1f KB/s   Out %.1f KB/s",
            collector.netInKBPerSec, collector.netOutKBPerSec];
}

- (void)refresh:(id)sender {
    [collector refresh];
    self.filtered = [NSMutableArray arrayWithArray:[self sortedFiltered]];
    [table reloadData];
    // update graph
    [graphView addSampleUser:collector.cpuUserPercent
                      system:collector.cpuSystemPercent
              memoryPressure:collector.memoryPressure
                     netKBps:(collector.netInKBPerSec + collector.netOutKBPerSec)];
    [graphView setSummary:[self summaryForTab:activeTab]];
}

- (void)searchChanged:(id)sender {
    [self refresh:nil];
}

 - (int)numberOfRowsInTableView:(NSTableView *)tableView {
    return [filtered count];
}

 - (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row {
    if (row < 0 || row >= (NSInteger)[filtered count]) return nil;
    ProcessInfo *pi = [filtered objectAtIndex:row];
    NSString *ident = [tableColumn identifier];
    if ([ident isEqualToString:@"name"]) return pi.name;
    if ([ident isEqualToString:@"pid"]) return @(pi.pid);
    if ([ident isEqualToString:@"user"]) return pi.user;
    if ([ident isEqualToString:@"cpu"]) return [NSString stringWithFormat:@"%.1f", pi.cpuPercent];
    if ([ident isEqualToString:@"memory"]) return [NSString stringWithFormat:@"%.1f", pi.memoryMB];
    if ([ident isEqualToString:@"threads"]) return @(pi.threads);
    return nil;
}

- (void)tableView:(NSTableView *)tableView mouseDownInHeaderOfTableColumn:(NSTableColumn *)tableColumn {
    NSString *ident = [tableColumn identifier];
    if ([sortKey isEqualToString:ident]) {
        sortAscending = !sortAscending;
    } else {
        sortKey = ident;
        sortAscending = YES;
        // default descending for cpu/memory
        if ([ident isEqualToString:@"cpu"] || [ident isEqualToString:@"memory"] || [ident isEqualToString:@"threads"] || [ident isEqualToString:@"pid"]) {
            sortAscending = NO;
        }
    }
    [self refresh:nil];
}

- (ProcessInfo *)selectedProcess {
    int row = [table selectedRow];
    if (row < 0 || row >= (NSInteger)[filtered count]) return nil;
    return [filtered objectAtIndex:row];
}

- (void)inspectProcess:(id)sender {
    ProcessInfo *pi = [self selectedProcess];
    if (!pi) return;
    NSArray *fds = [collector openFileDescriptorsForPid:pi.pid];
    NSString *path = [collector executablePathForPid:pi.pid] ?: @"(unknown)";
    NSString *fdText = [fds count] ? [fds componentsJoinedByString:@"\n"] : @"(none)";
    NSString *info = [NSString stringWithFormat:@"PID: %d\nParent PID: %d\nName: %@\nUser: %@\n%%CPU: %.1f\nMemory: %.1f MB\nThreads: %d\nExecutable: %@\n\nOpen File Descriptors:\n%@",
                      pi.pid, pi.ppid, pi.name, pi.user, pi.cpuPercent, pi.memoryMB, pi.threads, path, fdText];
    NSAlert *alert = [NSAlert alertWithMessageText:@"Process Inspector"
                                    defaultButton:@"OK"
                                  alternateButton:nil
                                      otherButton:nil
                        informativeTextWithFormat:@"%@", info];
    [alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
}

- (void)quitProcess:(id)sender {
    ProcessInfo *pi = [self selectedProcess];
    if (!pi) return;
    NSAlert *alert = [NSAlert alertWithMessageText:@"Quit Process"
                                    defaultButton:@"Quit"
                                  alternateButton:@"Force Quit"
                                      otherButton:@"Cancel"
                        informativeTextWithFormat:@"Quit %@ (PID %d)?", pi.name, pi.pid];
    NSInteger rc = [alert runModal];
    if (rc == NSAlertFirstButtonReturn) {
        kill(pi.pid, SIGTERM);
    } else if (rc == NSAlertSecondButtonReturn) {
        kill(pi.pid, SIGKILL);
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem { return YES; }

// NSApplicationDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

- (void)windowWillClose:(NSNotification *)note {
    [timer invalidate];
    timer = nil;
}

@end