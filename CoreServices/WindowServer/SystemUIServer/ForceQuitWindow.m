/*
 * ForceQuitWindow - Force Quit Applications dialog for SystemUIServer
 *
 * Copyright (c) 2026 ravynOS Project
 */

#import <AppKit/AppKit.h>
#import "ForceQuitWindow.h"
#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <signal.h>
#include <unistd.h>

int proc_pidpath(pid_t pid, void *buffer, uint32_t buffersize);

@implementation ForceQuitWindow

- (ForceQuitWindow *)init {
    self = [super initWithContentRect:NSMakeRect(0, 0, 380, 320)
                            styleMask:NSTitledWindowMask | NSClosableWindowMask
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (!self)
        return nil;

    [self setTitle:@"Force Quit Applications"];
    [self center];

    _apps = [NSMutableArray new];

    NSView *content = [self contentView];

    NSTextField *desc = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 260, 340, 44)];
    [desc setEditable:NO];
    [desc setSelectable:NO];
    [desc setBezeled:NO];
    [desc setDrawsBackground:NO];
    [desc setFont:[NSFont systemFontOfSize:11]];
    [desc setStringValue:@"If an app doesn't respond for a while, select its name and click Force Quit."];
    [content addSubview:desc];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 340, 195)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];

    _tableView = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [[col headerCell] setStringValue:@"Applications"];
    [col setWidth:310];
    [_tableView addTableColumn:col];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setTarget:self];
    [_tableView setDoubleAction:@selector(forceQuitSelected:)];

    [scroll setDocumentView:_tableView];
    [content addSubview:scroll];

    _forceQuitButton = [[NSButton alloc] initWithFrame:NSMakeRect(240, 15, 120, 30)];
    [_forceQuitButton setTitle:@"Force Quit"];
    [_forceQuitButton setBezelStyle:NSRoundedBezelStyle];
    [_forceQuitButton setTarget:self];
    [_forceQuitButton setAction:@selector(forceQuitSelected:)];
    [content addSubview:_forceQuitButton];

    NSButton *cancelBtn = [[NSButton alloc] initWithFrame:NSMakeRect(140, 15, 90, 30)];
    [cancelBtn setTitle:@"Cancel"];
    [cancelBtn setBezelStyle:NSRoundedBezelStyle];
    [cancelBtn setTarget:self];
    [cancelBtn setAction:@selector(cancel:)];
    [content addSubview:cancelBtn];

    [self refreshApps];

    return self;
}

- (void)refreshApps {
    [_apps removeAllObjects];

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) < 0 || size == 0)
        return;

    int nentries = size / sizeof(struct kinfo_proc);
    struct kinfo_proc *kps = malloc(size);
    if (!kps)
        return;

    if (sysctl(mib, 3, kps, &size, NULL, 0) >= 0) {
        nentries = size / sizeof(struct kinfo_proc);
        for (int i = 0; i < nentries; i++) {
            pid_t pid = kps[i].kp_proc.p_pid;
            if (pid <= 1)
                continue;

            char pathBuf[PROC_PIDPATHINFO_MAXSIZE];
            memset(pathBuf, 0, sizeof(pathBuf));
            int ret = proc_pidpath(pid, pathBuf, sizeof(pathBuf));
            NSString *appPath = nil;
            if (ret > 0)
                appPath = [NSString stringWithUTF8String:pathBuf];
            else
                appPath = [NSString stringWithUTF8String:kps[i].kp_proc.p_comm];

            if ([appPath rangeOfString:@".app"].location != NSNotFound ||
                [appPath rangeOfString:@"Terminal"].location != NSNotFound ||
                [appPath rangeOfString:@"Filer"].location != NSNotFound ||
                [appPath rangeOfString:@"Chrome"].location != NSNotFound) {
                NSString *appName = [[appPath lastPathComponent] stringByDeletingPathExtension];
                if ([appName isEqualToString:@"WindowServer"] || [appName isEqualToString:@"SystemUIServer"])
                    continue;

                [_apps addObject:@{
                    @"pid": [NSNumber numberWithInt:pid],
                    @"name": appName
                }];
            }
        }
    }
    free(kps);

    [_tableView reloadData];
    if ([_apps count] > 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
}

- (int)numberOfRowsInTableView:(NSTableView *)tableView {
    return (int)[_apps count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)col row:(int)row {
    if (row >= 0 && row < (int)[_apps count]) {
        return [[_apps objectAtIndex:row] objectForKey:@"name"];
    }
    return nil;
}
- (void)forceQuitSelected:(id)sender {
    NSInteger row = [_tableView selectedRow];
    if (row < 0 || row >= [_apps count])
        return;

    pid_t pid = [[[_apps objectAtIndex:row] objectForKey:@"pid"] intValue];
    NSString *name = [[_apps objectAtIndex:row] objectForKey:@"name"];
    int rc = NSRunAlertPanel(@"Force Quit Application",
        @"Do you want to force \"%@\" to quit? Any unsaved changes will be lost.",
        @"Force Quit", @"Cancel", nil, name);
    if (rc == 1) {
        fprintf(stderr, "[SUI] Force quitting %s (pid %d)\n", [name UTF8String], pid);
        kill(pid, SIGKILL);
        [self refreshApps];
    }
}

- (void)cancel:(id)sender {
    [self close];
}

@end
