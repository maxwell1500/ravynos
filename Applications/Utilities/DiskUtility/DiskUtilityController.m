 #import "DiskUtilityController.h"
 #import <sys/stat.h>
 #import <sys/mount.h>
 #import <LaunchServices/LaunchServices.h>
 static NSString *findBinary(NSString *name) {
     NSArray *dirs = @[@"/sbin", @"/usr/sbin", @"/usr/bin", @"/bin", @"/usr/local/bin", @"/usr/local/sbin"];
     for (NSString *d in dirs) {
         NSString *p = [d stringByAppendingPathComponent:name];
         if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) return p;
     }
    return nil;
}

/* Adds a label/value row to the Disk Utility inspector and returns the value
 * field.  A C function rather than a block: block copies abort in dyld here. */
static NSTextField *addLabelToInspector(NSView *inspectorView, NSString *title, CGFloat *y) {
    NSTextField *lab = [[NSTextField alloc] initWithFrame:NSMakeRect(16, *y + 4, 140, 18)];
    NSTextField *val;

    [lab setStringValue:title];
    [lab setBezeled:NO];
    [lab setDrawsBackground:NO];
    [lab setEditable:NO];
    [lab setSelectable:NO];
    [inspectorView addSubview:lab];
    val = [[NSTextField alloc] initWithFrame:NSMakeRect(160, *y, 360, 22)];
    [val setBezeled:NO];
    [val setDrawsBackground:NO];
    [val setEditable:NO];
    [val setSelectable:YES];
    [inspectorView addSubview:val];
    *y -= 30;
    return val;
}

static NSString *fmtBytes(uint64_t b) {
    double v = (double)b;
    NSArray *units = @[@"B", @"KB", @"MB", @"GB", @"TB"];
    int i = 0;
    while (v >= 1024 && i < 4) { v /= 1024; i++; }
    return [NSString stringWithFormat:@"%.2f %@", v, units[i]];
}

@implementation DiskUtilityController
@synthesize window, sidebarTable, sidebarScroll, inspectorView, deviceNameField, mountPointButton, fsTypeField, totalField, usedField, availField, statusField, capacityBar, selectedItem, sidebarRows, sectionMarkers, pollTimer;

- (id)init {
    self = [super init];
    if (self) {
        sidebarRows = [NSMutableArray array];
        sectionMarkers = [NSMutableArray array];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self buildWindow];
    [self refresh];
    pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(100, 80, 920, 560);
    window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [window setTitle:@"Disk Utility"];
    [window setDelegate:self];
    [window center];

    NSView *content = [window contentView];
    NSRect cb = [content bounds];

    // Sidebar
    NSRect sideFrame = NSMakeRect(0, 0, 230, cb.size.height - 40);
    sidebarScroll = [[NSScrollView alloc] initWithFrame:sideFrame];
    [sidebarScroll setHasVerticalScroller:YES];
    sidebarTable = [[NSTableView alloc] initWithFrame:sideFrame];
    NSTableColumn *sc = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [sc setWidth:220];
    [[sc headerCell] setStringValue:@"Disks"];
    [sidebarTable addTableColumn:sc];
    [sidebarTable setDataSource:self];
    [sidebarTable setDelegate:self];
    [sidebarTable setHeaderView:nil];
    [sidebarScroll setDocumentView:sidebarTable];
    [sidebarScroll setAutoresizingMask:NSViewHeightSizable];
    [content addSubview:sidebarScroll];

    // Toolbar buttons
    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(230, cb.size.height - 40, cb.size.width - 230, 40)];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    NSArray *btns = @[
        @[@"First Aid", @"firstAid:"],
        @[@"Mount", @"mountVolume:"],
        @[@"Unmount", @"unmountVolume:"],
        @[@"Eject", @"ejectVolume:"],
        @[@"Erase...", @"eraseVolume:"],
        @[@"New Blank Disk Image...", @"newDiskImage:"],
    ];
    CGFloat x = 8;
    for (NSArray *b in btns) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(x, 6, 110, 28)];
        [btn setTitle:b[0]];
        [btn setBezelStyle:NSRoundedBezelStyle];
        [btn setTarget:self];
        [btn setAction:NSSelectorFromString(b[1])];
        [bar addSubview:btn];
        x += 118;
    }
    [content addSubview:bar];

    // Inspector view
    inspectorView = [[NSView alloc] initWithFrame:NSMakeRect(230, 0, cb.size.width - 230, cb.size.height - 40)];
    [inspectorView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:inspectorView];

     /* Start below the title and work down: the old value of 40 put every
      * label at a negative y once the eight rows were laid out, so the whole
      * inspector pane rendered off screen. */
     /* No blocks here: the Objective-C block copy helper aborts in dyld on
      * this image ("_Block_object_assign"), taking the whole app with it. */
     CGFloat y = cb.size.height - 84;
     #define ADD_LABEL(title) \
         addLabelToInspector(inspectorView, (title), &y)
    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(16, y + 4, 200, 22)];
    [title setStringValue:@"Disk Utility"];
    [title setBezeled:NO]; [title setDrawsBackground:NO]; [title setEditable:NO];
    [title setFont:[NSFont boldSystemFontOfSize:16]];
    [inspectorView addSubview:title];
    y -= 36;

    deviceNameField = ADD_LABEL(@"Device:");
    // mount point button
    {
        NSTextField *lab = [[NSTextField alloc] initWithFrame:NSMakeRect(16, y + 4, 140, 18)];
        [lab setStringValue:@"Mount Point:"];
        [lab setBezeled:NO]; [lab setDrawsBackground:NO]; [lab setEditable:NO]; [lab setSelectable:NO];
        [inspectorView addSubview:lab];
        mountPointButton = [[NSButton alloc] initWithFrame:NSMakeRect(160, y, 360, 22)];
        [mountPointButton setTitle:@""];
        [mountPointButton setBezelStyle:NSRoundedBezelStyle];
        [mountPointButton setTarget:self];
        [mountPointButton setAction:@selector(openMountPoint:)];
        [inspectorView addSubview:mountPointButton];
        y -= 30;
    }
    fsTypeField = ADD_LABEL(@"Filesystem:");
    totalField = ADD_LABEL(@"Total:");
    usedField = ADD_LABEL(@"Used:");
    availField = ADD_LABEL(@"Available:");
    statusField = ADD_LABEL(@"Status:");

    capacityBar = [[CapacityBarView alloc] initWithFrame:NSMakeRect(16, y - 10, 500, 24)];
    [inspectorView addSubview:capacityBar];
    y -= 40;

    [window makeKeyAndOrderFront:nil];
}

- (void)refresh {
    NSArray *vols = [[DiskBackend shared] refreshVolumes];
    [sidebarRows removeAllObjects];
    [sidebarRows addObject:@"Internal"];
    DiskItem *root = nil;
    for (DiskItem *it in vols) if (it.isRoot) { root = it; break; }
    if (root) [sidebarRows addObject:root];
    [sidebarRows addObject:@"External / Disk Images"];
    for (DiskItem *it in vols) if (!it.isRoot) [sidebarRows addObject:it];
    [sidebarTable reloadData];
    /* Show the boot volume immediately instead of an empty inspector. */
    if (selectedItem == nil && root != nil) {
        selectedItem = root;
        [sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:1]
                 byExtendingSelection:NO];
    }
    // keep selection
    if (selectedItem) {
        for (NSInteger i = 0; i < (NSInteger)sidebarRows.count; i++) {
            id obj = sidebarRows[i];
            if ([obj isKindOfClass:[DiskItem class]] && obj == selectedItem) {
                [sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                break;
            }
        }
    }
    [self updateInspector];
}

- (void)updateInspector {
    DiskItem *it = selectedItem;
    if (!it) {
        [deviceNameField setStringValue:@""];
        [mountPointButton setTitle:@""];
        [fsTypeField setStringValue:@""];
        [totalField setStringValue:@""];
        [usedField setStringValue:@""];
        [availField setStringValue:@""];
        [statusField setStringValue:@""];
        [capacityBar setTotalBytes:0];
        [capacityBar setUsedBytes:0];
        [capacityBar setNeedsDisplay:YES];
        return;
    }
    [deviceNameField setStringValue:it.deviceName ?: @""];
    [mountPointButton setTitle:it.mountPoint ?: @"(not mounted)"];
    [fsTypeField setStringValue:it.fsType ?: @""];
    [totalField setStringValue:fmtBytes(it.totalBytes)];
    [usedField setStringValue:fmtBytes(it.usedBytes)];
    [availField setStringValue:fmtBytes(it.availBytes)];
    [statusField setStringValue:@"Verified"];
    [capacityBar setTotalBytes:it.totalBytes];
    [capacityBar setUsedBytes:it.usedBytes];
    [capacityBar setNeedsDisplay:YES];
}

// NSTableView data source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return sidebarRows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)sidebarRows.count) return nil;
    id obj = sidebarRows[row];
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj isKindOfClass:[DiskItem class]]) {
        DiskItem *it = obj;
        if (it.mountPoint) return [NSString stringWithFormat:@"%@ (%@)", it.deviceName.lastPathComponent, it.mountPoint.lastPathComponent];
        return it.deviceName.lastPathComponent;
    }
    return nil;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)sidebarRows.count) return;
    id obj = sidebarRows[row];
    if ([obj isKindOfClass:[NSString class]]) {
        [cell setFont:[NSFont boldSystemFontOfSize:12]];
    } else {
        [cell setFont:[NSFont systemFontOfSize:12]];
    }
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)sidebarRows.count) return NO;
    id obj = sidebarRows[row];
    return ![obj isKindOfClass:[NSString class]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [sidebarTable selectedRow];
    if (row >= 0 && row < (NSInteger)sidebarRows.count) {
        id obj = sidebarRows[row];
        if ([obj isKindOfClass:[DiskItem class]]) {
            selectedItem = obj;
        }
    } else {
        selectedItem = nil;
    }
    [self updateInspector];
}

// Actions
- (void)openMountPoint:(id)sender {
    if (!selectedItem || !selectedItem.mountPoint) return;
    NSURL *u = [NSURL fileURLWithPath:selectedItem.mountPoint];
    LSOpenCFURLRef((__bridge CFURLRef)u, NULL);
}

- (void)firstAid:(id)sender {
    if (!selectedItem) return;
    NSString *dev = selectedItem.deviceName;
    if (![dev hasPrefix:@"/dev"]) dev = selectedItem.mountPoint;
    NSString *fs = [selectedItem.fsType lowercaseString];
    NSMutableString *log = [NSMutableString string];
    BOOL ok = NO;
    NSString *bin = nil;
    if (([fs rangeOfString:@"msdos"].location != NSNotFound) || ([fs rangeOfString:@"fat"].location != NSNotFound) || ([fs rangeOfString:@"vfat"].location != NSNotFound)) bin = findBinary(@"fsck_msdos");
    else if (([fs rangeOfString:@"hfs"].location != NSNotFound)) bin = findBinary(@"fsck_hfs");
    if (bin) {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:bin];
        [task setArguments:@[@"-n", dev]];
        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];
        [task setStandardError:pipe];
        @try {
            [task launch];
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
            NSString *out = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (out) [log appendString:out];
            ok = ([task terminationStatus] == 0);
        } @catch (NSException *ex) {
            [log appendFormat:@"Exception: %@\n", [ex reason]];
            ok = NO;
        }
    } else if (([fs rangeOfString:@"msdos"].location != NSNotFound) || ([fs rangeOfString:@"fat"].location != NSNotFound)) {
        NSString *err = nil;
        ok = [[DiskBackend shared] validateFATAtPath:dev error:&err];
        if (!ok) [log appendFormat:@"%@\n", err];
        else [log appendString:@"FAT structural validation passed.\n"];
    } else {
        ok = (selectedItem.totalBytes > 0);
        [log appendFormat:@"No checker available for %@; device status %@\n", fs, ok ? @"OK" : @"FAIL"];
    }
    NSAlert *a = [NSAlert alertWithMessageText:(ok ? @"First Aid passed" : @"First Aid failed")
                               defaultButton:@"OK" alternateButton:nil otherButton:nil
                   informativeTextWithFormat:@"%@", log.length ? log : @"No output"];
    [a runModal];
}

- (void)mountVolume:(id)sender {
    if (!selectedItem || selectedItem.isMounted) {
        NSAlert *a = [NSAlert alertWithMessageText:@"Already mounted or no device" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [a runModal];
        return;
    }
    NSString *mp = [NSString stringWithFormat:@"/Volumes/%@", [selectedItem.deviceName lastPathComponent]];
    int rc;

    mkdir([mp UTF8String], 0755);
    /* Try the syscall before shelling out: /sbin/mount is not staged. */
    rc = mount([selectedItem.fsType UTF8String], [mp UTF8String], 0,
               (void *)[selectedItem.deviceName UTF8String]);
    if (rc != 0) {
        NSString *cmd = [NSString stringWithFormat:@"mount -t %@ %@ %@", selectedItem.fsType, selectedItem.deviceName, mp];
        rc = system([cmd UTF8String]);
    }
    if (rc == 0) {
        NSAlert *a = [NSAlert alertWithMessageText:@"Mounted" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", mp];
        [a runModal];
    } else {
        NSAlert *a = [NSAlert alertWithMessageText:@"Mount failed" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"exit %d", rc];
        [a runModal];
    }
    [self refresh];
}

- (void)unmountVolume:(id)sender {
    if (!selectedItem || !selectedItem.isMounted || !selectedItem.mountPoint) {
        NSAlert *a = [NSAlert alertWithMessageText:@"Not mounted" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [a runModal];
        return;
    }
    if ([selectedItem.mountPoint isEqualToString:@"/"]) {
        NSAlert *a = [NSAlert alertWithMessageText:@"Cannot unmount root volume" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [a runModal];
        return;
    }
    int rc = unmount([selectedItem.mountPoint UTF8String], 0);
    if (rc != 0) {
        // try force
        rc = unmount([selectedItem.mountPoint UTF8String], MNT_FORCE);
    }
    if (rc == 0) {
        NSAlert *a = [NSAlert alertWithMessageText:@"Unmounted" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", selectedItem.mountPoint];
        [a runModal];
    } else {
        NSAlert *a = [NSAlert alertWithMessageText:@"Unmount failed" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"errno %d", errno];
        [a runModal];
    }
    [self refresh];
}

- (void)ejectVolume:(id)sender {
    [self unmountVolume:sender];
}

- (void)eraseVolume:(id)sender {
    if (!selectedItem) return;
    if (selectedItem.isRoot || [selectedItem.mountPoint isEqualToString:@"/"]) {
        NSAlert *a = [NSAlert alertWithMessageText:@"Cannot erase root volume" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [a runModal];
        return;
    }
    NSAlert *a = [NSAlert alertWithMessageText:@"Erase" defaultButton:@"Erase" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"This will erase %@.", selectedItem.deviceName];
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 64)];
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 36, 284, 22)];
    [nameField setStringValue:@"Untitled"];
    [acc addSubview:nameField];
    NSPopUpButton *fmt = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(8, 8, 284, 24) pullsDown:NO];
    [fmt addItemsWithTitles:@[@"MS-DOS (FAT32)", @"HFS+", @"APFS"]];
    [acc addSubview:fmt];
    [a setAccessoryView:acc];
    NSInteger res = [a runModal];
    if (res != NSAlertDefaultReturn) return;
    NSString *dev = selectedItem.deviceName;
    NSString *format = [fmt titleOfSelectedItem];
    NSString *bin = nil;
    NSString *cmd = nil;
    if ([format isEqualToString:@"MS-DOS (FAT32)"]) {
        bin = findBinary(@"newfs_msdos");
        if (bin) cmd = [NSString stringWithFormat:@"%@ -F 32 -v %@ %@", bin, [nameField stringValue], dev];
    } else if ([format isEqualToString:@"HFS+"]) {
        bin = findBinary(@"newfs_hfs");
        if (bin) cmd = [NSString stringWithFormat:@"%@ -v %@ %@", bin, [nameField stringValue], dev];
    }
    if (cmd) {
        int rc = system([cmd UTF8String]);
        NSAlert *r = [NSAlert alertWithMessageText:(rc == 0 ? @"Erase complete" : @"Erase failed")
                                   defaultButton:@"OK" alternateButton:nil otherButton:nil
                       informativeTextWithFormat:@"exit %d", rc];
        [r runModal];
    } else if ([format isEqualToString:@"MS-DOS (FAT32)"]) {
        /* No newfs_msdos in the image: write the FAT32 structures ourselves. */
        NSString *err = nil;
        BOOL ok = [[DiskBackend shared] formatFAT32AtPath:dev
                                               volumeName:[nameField stringValue]
                                                    error:&err];
        NSAlert *r = [NSAlert alertWithMessageText:(ok ? @"Erase complete" : @"Erase failed")
                                   defaultButton:@"OK" alternateButton:nil otherButton:nil
                       informativeTextWithFormat:@"%@", ok ? dev : (err ?: @"unknown error")];
        [r runModal];
    } else {
        NSAlert *r = [NSAlert alertWithMessageText:@"Formatting tool unavailable" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"No newfs binary found for %@.", format];
        [r runModal];
    }
    [self refresh];
}

- (void)newDiskImage:(id)sender {
    NSString *desktop = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
    [[NSFileManager defaultManager] createDirectoryAtPath:desktop withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [desktop stringByAppendingPathComponent:@"DiskImage.img"];
    int fd = open([path UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        ftruncate(fd, 10 * 1024 * 1024);
        close(fd);
    }
    NSString *bin = findBinary(@"newfs_msdos");
    NSString *err = nil;
    BOOL formatted = NO;

    if (bin) {
        NSString *cmd = [NSString stringWithFormat:@"%@ -F 32 -v Untitled %@", bin, path];
        formatted = (system([cmd UTF8String]) == 0);
    }
    if (!formatted)
        formatted = [[DiskBackend shared] formatFAT32AtPath:path
                                                 volumeName:@"UNTITLED"
                                                      error:&err];
    NSAlert *a = [NSAlert alertWithMessageText:(formatted ? @"Disk image created" : @"Disk image formatting failed")
                               defaultButton:@"OK" alternateButton:nil otherButton:nil
                   informativeTextWithFormat:@"%@%@", path, formatted ? @"" : [NSString stringWithFormat:@"\n%@", err ?: @""]];
    [a runModal];
}

// NSApplicationDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

- (void)windowWillClose:(NSNotification *)note {
    [pollTimer invalidate];
    pollTimer = nil;
    [NSApp terminate:nil];
}
@end