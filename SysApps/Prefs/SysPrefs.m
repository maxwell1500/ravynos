/*
 * Copyright (C) 2024-2026 ravynOS Project
 *
 * System Settings - Modern split-view Preferences application
 */

#import "SysPrefs.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
 #include <fcntl.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <pwd.h>
#include <grp.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach.h>
#include <WindowServer/message.h>

extern void bootstrap_init(void);
extern kern_return_t bootstrap_look_up(mach_port_t bp, const char *service_name, mach_port_t *sp);

/* OSS mixer ioctls -- <sys/soundcard.h> is not available in the SDK */
#ifndef SOUND_MIXER_WRITE_VOLUME
#define SOUND_MIXER_WRITE_VOLUME _IOWR('M', 0, int)
#endif
#ifndef SOUND_MIXER_READ_VOLUME
#define SOUND_MIXER_READ_VOLUME _IOWR('M', 1, int)
#endif


/* ---- SHA-256 (passwords stored as $sha256$<salt>$<hex>) ---- */

typedef struct {
    uint32_t state[8];
    uint64_t bitlen;
    uint8_t data[64];
    size_t datalen;
} SysSha256;

static uint32_t sys_rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }

static void sys_sha256_transform(SysSha256 *ctx, const uint8_t data[]) {
    static const uint32_t k[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
    uint32_t m[64], a, b, c, d, e, f, g, h, t1, t2;
    int i;

    for(i = 0; i < 16; i++)
        m[i] = ((uint32_t)data[i*4] << 24) | ((uint32_t)data[i*4+1] << 16) |
               ((uint32_t)data[i*4+2] << 8) | (uint32_t)data[i*4+3];
    for(i = 16; i < 64; i++) {
        uint32_t s0 = sys_rotr(m[i-15], 7) ^ sys_rotr(m[i-15], 18) ^ (m[i-15] >> 3);
        uint32_t s1 = sys_rotr(m[i-2], 17) ^ sys_rotr(m[i-2], 19) ^ (m[i-2] >> 10);
        m[i] = m[i-16] + s0 + m[i-7] + s1;
    }

    a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
    e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];

    for(i = 0; i < 64; i++) {
        uint32_t S1 = sys_rotr(e, 6) ^ sys_rotr(e, 11) ^ sys_rotr(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t S0 = sys_rotr(a, 2) ^ sys_rotr(a, 13) ^ sys_rotr(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        t1 = h + S1 + ch + k[i] + m[i];
        t2 = S0 + maj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }

    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void sys_sha256_init(SysSha256 *ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667; ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372; ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f; ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab; ctx->state[7] = 0x5be0cd19;
}

static void sys_sha256_update(SysSha256 *ctx, const uint8_t *data, size_t len) {
    size_t i;

    for(i = 0; i < len; i++) {
        ctx->data[ctx->datalen++] = data[i];
        if(ctx->datalen == 64) {
            sys_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void sys_sha256_final(SysSha256 *ctx, uint8_t hash[32]) {
    size_t i = ctx->datalen;

    ctx->data[i++] = 0x80;
    if(i > 56) {
        while(i < 64) ctx->data[i++] = 0;
        sys_sha256_transform(ctx, ctx->data);
        i = 0;
    }
    while(i < 56) ctx->data[i++] = 0;
    ctx->bitlen += (uint64_t)ctx->datalen * 8;
    for(i = 0; i < 8; i++)
        ctx->data[63 - i] = (uint8_t)(ctx->bitlen >> (8 * i));
    sys_sha256_transform(ctx, ctx->data);

    for(i = 0; i < 4; i++) {
        int j;
        for(j = 0; j < 8; j++)
            hash[i + 4*j] = (uint8_t)(ctx->state[j] >> (24 - i * 8));
    }
}

static NSString *sys_password_hash(NSString *password, NSString *salt) {
    SysSha256 ctx;
    uint8_t digest[32];
    const char *pw = [password UTF8String];
    const char *saltBytes = [salt UTF8String];
    NSMutableString *hex = [NSMutableString stringWithFormat:@"$sha256$%@$", salt];

    sys_sha256_init(&ctx);
    sys_sha256_update(&ctx, (const uint8_t *)saltBytes, strlen(saltBytes));
    sys_sha256_update(&ctx, (const uint8_t *)pw, strlen(pw));
    sys_sha256_final(&ctx, digest);

    for(int i = 0; i < 32; i++)
        [hex appendFormat:@"%02x", digest[i]];
    return hex;
}
static void ensureDir(NSString *p) {
    [[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
}

@implementation SystemPreferences

- (void)writePlist:(NSDictionary *)dict toPath:(NSString *)path {
    ensureDir([path stringByDeletingLastPathComponent]);
    [dict writeToFile:path atomically:YES];
}

- (void)broadcastPrefsChanged {
    if (bootstrap_port == MACH_PORT_NULL) bootstrap_init();
    mach_port_t port = MACH_PORT_NULL;
    if (bootstrap_look_up(bootstrap_port, WINDOWSERVER_SVC_NAME, &port) != KERN_SUCCESS) return;
    Message msg = {0};
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = CODE_PREFS_CHANGED;
    msg.pid = getpid();
    strncpy(msg.bundleID, "com.ravynos.Preferences", sizeof(msg.bundleID));
    mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG|MACH_SEND_TIMEOUT,
             sizeof(msg) - sizeof(mach_msg_trailer_t), 0, MACH_PORT_NULL, 100, MACH_PORT_NULL);
}

- (void)applicationWillFinishLaunching:(NSNotification *)note {
    categories = @[@"Displays", @"Network", @"Users & Groups", @"Appearance & Dock", @"Keyboard & Mouse", @"Sound"];

    NSRect frame = NSMakeRect(120, 100, 760, 520);
    window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setTitle:@"System Preferences"];
    [window center];

    NSView *contentView = [window contentView];

    NSScrollView *sidebarScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 520)];
    [sidebarScroll setHasVerticalScroller:YES];
    [sidebarScroll setBorderType:NSNoBorder];

    sidebarView = [[NSTableView alloc] initWithFrame:[[sidebarScroll contentView] bounds]];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"Category"];
    [[col headerCell] setStringValue:@"Settings"];
    [col setWidth:180];
    [sidebarView addTableColumn:col];
    [sidebarView setHeaderView:nil];
    [sidebarView setDataSource:self];
    [sidebarView setDelegate:self];
    [sidebarScroll setDocumentView:sidebarView];
    [contentView addSubview:sidebarScroll];

    detailContainer = [[NSView alloc] initWithFrame:NSMakeRect(210, 10, 540, 500)];
    [contentView addSubview:detailContainer];

    [self selectCategoryAtIndex:0];
    [sidebarView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    [window makeKeyAndOrderFront:self];
}

- (int)numberOfRowsInTableView:(NSTableView *)tv {
    if (tv == sidebarView) return (int)[categories count];
    if (tv == usersTable) return (int)[usersList count];
    if (tv == loginItemsTable) return (int)[loginItemsList count];
    if (tv == soundOutTable) return (int)[soundOutDevices count];
    if (tv == soundInTable) return (int)[soundInDevices count];
    return 0;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(int)row {
    if (tv == sidebarView) {
        if (row >= 0 && row < (int)[categories count]) return [categories objectAtIndex:row];
        return nil;
    }
    if (tv == usersTable) {
        if (row >= 0 && row < (int)[usersList count]) {
            NSDictionary *u = [usersList objectAtIndex:row];
            return [NSString stringWithFormat:@"%@ (%@) UID %d - %@",
                    [u objectForKey:@"full"], [u objectForKey:@"name"],
                    [[u objectForKey:@"uid"] intValue],
                    [[u objectForKey:@"admin"] boolValue] ? @"Admin" : @"Standard"];
        }
        return nil;
    }
    if (tv == loginItemsTable) {
        if (row >= 0 && row < (int)[loginItemsList count]) return [loginItemsList objectAtIndex:row];
        return nil;
    }
    if (tv == soundOutTable) {
        if (row >= 0 && row < (int)[soundOutDevices count]) return [soundOutDevices objectAtIndex:row];
        return nil;
    }
    if (tv == soundInTable) {
        if (row >= 0 && row < (int)[soundInDevices count]) return [soundInDevices objectAtIndex:row];
        return nil;
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    NSTableView *tv = [note object];
    if (tv == sidebarView) {
        int row = (int)[sidebarView selectedRow];
        if (row >= 0 && row < (int)[categories count]) [self selectCategoryAtIndex:row];
    }
}

- (void)selectCategoryAtIndex:(int)index {
    if (currentPaneView != nil) {
        [currentPaneView removeFromSuperview];
        currentPaneView = nil;
    }
    switch (index) {
        case 0: currentPaneView = [self createDisplaysPane]; break;
        case 1: currentPaneView = [self createNetworkPane]; break;
        case 2: currentPaneView = [self createUsersPane]; break;
        case 3: currentPaneView = [self createAppearancePane]; break;
        case 4: currentPaneView = [self createKeyboardPane]; break;
        case 5: currentPaneView = [self createSoundPane]; break;
        default: currentPaneView = [self createDisplaysPane]; break;
    }
    if (currentPaneView != nil) {
        [detailContainer addSubview:currentPaneView];
        [detailContainer setNeedsDisplay:YES];
    }
}

/* ---------------- Displays ---------------- */
- (NSView *)createDisplaysPane {
    NSView *v = [[NSView alloc] initWithFrame:[detailContainer bounds]];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 400, 30)];
    [title setStringValue:@"Displays"];
    [title setFont:[NSFont boldSystemFontOfSize:18]];
    [title setEditable:NO]; [title setSelectable:NO]; [title setBezeled:NO]; [title setDrawsBackground:NO];
    [v addSubview:title];

    displayID = CGMainDisplayID();
    NSRect drect = CGDisplayBounds(displayID);
    size_t curW = (size_t)drect.size.width;
    size_t curH = (size_t)drect.size.height;
    double curRate = 60.0;

    dispCurrentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 420, 500, 24)];
    [dispCurrentLabel setStringValue:[NSString stringWithFormat:@"Current: %zu × %zu @ %.0f Hz", curW, curH, curRate]];
    [dispCurrentLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [dispCurrentLabel setEditable:NO]; [dispCurrentLabel setSelectable:NO]; [dispCurrentLabel setBezeled:NO]; [dispCurrentLabel setDrawsBackground:NO];
    [v addSubview:dispCurrentLabel];

    /* CGDisplayCopyAllDisplayModes/CGGetActiveDisplayList RPC their way back
     * through WindowServer and stall this pane on the boot image; a fixed
     * list keeps the UI working. Upgrade back to enumeration once those RPCs
     * are reliable. */
    displayModeTitles = [NSMutableArray array];
    displayModeRefs = [NSMutableArray array];
    static const char *modeNames[] = {"1920 × 1080", "1600 × 900", "1280 × 720",
                                      "1152 × 864", "1024 × 768", "960 × 640", "800 × 600"};
    for(int mi = 0; mi < (int)(sizeof(modeNames) / sizeof(modeNames[0])); ++mi) {
        [displayModeTitles addObject:[NSString stringWithCString:modeNames[mi] encoding:NSUTF8StringEncoding]];
        [displayModeRefs addObject:[NSValue valueWithPointer:NULL]];
    }
    // radio list
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 230, 260, 170)];
    [scroll setHasVerticalScroller:YES];
    NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0,0,240, (int)[displayModeTitles count]*30)];
    for (int i = 0; i < (int)[displayModeTitles count]; i++) {
        NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, ([displayModeTitles count]-1-i)*30, 240, 28)];
        [b setTitle:[displayModeTitles objectAtIndex:i]];
        [b setButtonType:NSRadioButton];
        size_t w = 0, h = 0;
        NSString *t = [displayModeTitles objectAtIndex:i];
        sscanf([t UTF8String], "%zu × %zu", &w, &h);
        if (w == curW && h == curH) { [b setState:NSOnState]; selectedDisplayMode = i; }
        [b setTag:i];
        [b setTarget:self];
        [b setAction:@selector(displayModeSelected:)];
        [doc addSubview:b];
    }
    [scroll setDocumentView:doc];
    [v addSubview:scroll];

    // refresh rate popup
    NSTextField *rrLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(300, 390, 200, 20)];
    [rrLabel setStringValue:@"Refresh Rate:"];
    [rrLabel setEditable:NO]; [rrLabel setSelectable:NO]; [rrLabel setBezeled:NO]; [rrLabel setDrawsBackground:NO];
    [v addSubview:rrLabel];
    dispRefreshPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(300, 360, 200, 28) pullsDown:NO];
    [dispRefreshPopup addItemWithTitle:[NSString stringWithFormat:@"%.0f Hz", curRate]];
    [v addSubview:dispRefreshPopup];

    // scaling
    NSTextField *scLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(300, 320, 200, 20)];
    [scLabel setStringValue:@"UI Scaling:"];
    [scLabel setEditable:NO]; [scLabel setSelectable:NO]; [scLabel setBezeled:NO]; [scLabel setDrawsBackground:NO];
    [v addSubview:scLabel];
    dispScalePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(300, 290, 200, 28) pullsDown:NO];
    [dispScalePopup addItemsWithTitles:@[@"100%", @"125%", @"150%", @"200%"]];
    [v addSubview:dispScalePopup];

    // rotation
    NSTextField *rotLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(300, 250, 200, 20)];
    [rotLabel setStringValue:@"Rotation:"];
    [rotLabel setEditable:NO]; [rotLabel setSelectable:NO]; [rotLabel setBezeled:NO]; [rotLabel setDrawsBackground:NO];
    [v addSubview:rotLabel];
    dispRotationPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(300, 220, 200, 28) pullsDown:NO];
    [dispRotationPopup addItemsWithTitles:@[@"0°", @"90°", @"180°", @"270°"]];
    double rot = CGDisplayRotation(displayID);
    int ri = (int)(rot/90.0) % 4;
    [dispRotationPopup selectItemAtIndex:ri];
    [v addSubview:dispRotationPopup];

    NSButton *apply = [[NSButton alloc] initWithFrame:NSMakeRect(20, 180, 120, 32)];
    [apply setTitle:@"Apply"];
    [apply setBezelStyle:NSRoundedBezelStyle];
    [apply setTarget:self];
    [apply setAction:@selector(displaysApply:)];
    [v addSubview:apply];

    return v;
}

- (void)displayModeSelected:(id)sender {
     selectedDisplayMode = (int)[(NSButton *)sender tag];
}

- (void)displaysApply:(id)sender {
    if (selectedDisplayMode < 0 || selectedDisplayMode >= (int)[displayModeRefs count]) return;
    CGDisplayModeRef m = (CGDisplayModeRef)[[displayModeRefs objectAtIndex:selectedDisplayMode] pointerValue];
    size_t w = 0, h = 0;
    if(m != NULL) {
        CGDisplaySetDisplayMode(displayID, m, NULL);
        w = CGDisplayModeGetWidth(m);
        h = CGDisplayModeGetHeight(m);
    } else {
        /* Stub mode list on this image: keep the current geometry. */
        NSRect drect = CGDisplayBounds(displayID);
        w = (size_t)drect.size.width;
        h = (size_t)drect.size.height;
    }
    [dispCurrentLabel setStringValue:[NSString stringWithFormat:@"Current: %zu × %zu", w, h]];

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/com.ravynos.WindowServer.plist"]];
    [prefs setObject:[NSNumber numberWithUnsignedLong:w] forKey:@"DisplayWidth"];
    [prefs setObject:[NSNumber numberWithUnsignedLong:h] forKey:@"DisplayHeight"];
    [prefs setObject:[NSNumber numberWithInt:[dispRotationPopup indexOfSelectedItem]*90] forKey:@"DisplayRotation"];
    NSString *scale = [[dispScalePopup titleOfSelectedItem] stringByReplacingOccurrencesOfString:@"%" withString:@""];
    [prefs setObject:scale forKey:@"UIScale"];
    [self writePlist:prefs toPath:@"/Library/Preferences/com.ravynos.WindowServer.plist"];
    [self broadcastPrefsChanged];
}

/* ---------------- Network ---------------- */
- (NSView *)createNetworkPane {
    NSView *v = [[NSView alloc] initWithFrame:[detailContainer bounds]];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 400, 30)];
    [title setStringValue:@"Network"];
    [title setFont:[NSFont boldSystemFontOfSize:18]];
    [title setEditable:NO]; [title setSelectable:NO]; [title setBezeled:NO]; [title setDrawsBackground:NO];
    [v addSubview:title];

    netIfaceNames = [NSMutableArray array];
    struct ifaddrs *ifap, *ifa;
    if (getifaddrs(&ifap) == 0) {
        for (ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_name && ![netIfaceNames containsObject:[NSString stringWithUTF8String:ifa->ifa_name]])
                [netIfaceNames addObject:[NSString stringWithUTF8String:ifa->ifa_name]];
        }
        freeifaddrs(ifap);
    }
    if ([netIfaceNames count] == 0) [netIfaceNames addObject:@"en0"];

    netIfacePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 420, 200, 28) pullsDown:NO];
    [netIfacePopup addItemsWithTitles:netIfaceNames];
    [netIfacePopup setTarget:self];
    [netIfacePopup setAction:@selector(netIfaceChanged:)];
    [v addSubview:netIfacePopup];

    netStatusField = [[NSTextField alloc] initWithFrame:NSMakeRect(240, 420, 280, 28)];
    [netStatusField setEditable:NO]; [netStatusField setSelectable:NO]; [netStatusField setBezeled:NO]; [netStatusField setDrawsBackground:NO];
    [v addSubview:netStatusField];

    NSTextField *cfgLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 380, 120, 20)];
    [cfgLabel setStringValue:@"Configuration:"];
    [cfgLabel setEditable:NO]; [cfgLabel setSelectable:NO]; [cfgLabel setBezeled:NO]; [cfgLabel setDrawsBackground:NO];
    [v addSubview:cfgLabel];
    netConfigPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 376, 200, 28) pullsDown:NO];
    [netConfigPopup addItemsWithTitles:@[@"DHCP", @"Manually"]];
    [v addSubview:netConfigPopup];

    NSTextField *ipLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 340, 120, 20)];
    [ipLabel setStringValue:@"IP Address:"];
    [ipLabel setEditable:NO]; [ipLabel setSelectable:NO]; [ipLabel setBezeled:NO]; [ipLabel setDrawsBackground:NO];
    [v addSubview:ipLabel];
    netIPField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 336, 200, 24)];
    [v addSubview:netIPField];

    NSTextField *maskLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 308, 120, 20)];
    [maskLabel setStringValue:@"Subnet Mask:"];
    [maskLabel setEditable:NO]; [maskLabel setSelectable:NO]; [maskLabel setBezeled:NO]; [maskLabel setDrawsBackground:NO];
    [v addSubview:maskLabel];
    netMaskField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 304, 200, 24)];
    [v addSubview:netMaskField];

    NSTextField *routerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 276, 120, 20)];
    [routerLabel setStringValue:@"Router:"];
    [routerLabel setEditable:NO]; [routerLabel setSelectable:NO]; [routerLabel setBezeled:NO]; [routerLabel setDrawsBackground:NO];
    [v addSubview:routerLabel];
    netRouterField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 272, 200, 24)];
    [v addSubview:netRouterField];

    NSTextField *dnsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 244, 120, 20)];
    [dnsLabel setStringValue:@"DNS Servers:"];
    [dnsLabel setEditable:NO]; [dnsLabel setSelectable:NO]; [dnsLabel setBezeled:NO]; [dnsLabel setDrawsBackground:NO];
    [v addSubview:dnsLabel];
    netDNSField = [[NSTextField alloc] initWithFrame:NSMakeRect(150, 240, 200, 24)];
    [v addSubview:netDNSField];

    // read resolv.conf
    NSString *rc = [NSString stringWithContentsOfFile:@"/etc/resolv.conf" encoding:NSUTF8StringEncoding error:nil];
    NSMutableString *dns = [NSMutableString string];
    for (NSString *line in [rc componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"nameserver"]) {
            NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([parts count] >= 2) {
                if ([dns length]) [dns appendString:@", "];
                [dns appendString:[parts objectAtIndex:1]];
            }
        }
    }
    if ([dns length] == 0) dns = [NSMutableString stringWithString:@"10.0.2.3"];
    [netDNSField setStringValue:dns];

    [self netIfaceChanged:netIfacePopup];

    NSButton *apply = [[NSButton alloc] initWithFrame:NSMakeRect(20, 190, 120, 32)];
    [apply setTitle:@"Apply"];
    [apply setBezelStyle:NSRoundedBezelStyle];
    [apply setTarget:self];
    [apply setAction:@selector(networkApply:)];
    [v addSubview:apply];

    return v;
}

- (void)netIfaceChanged:(id)sender {
    NSString *name = [netIfacePopup titleOfSelectedItem];
    NSString *ipStr = @"0.0.0.0";
    NSString *maskStr = @"255.255.255.0";
    int flags = 0;
    struct ifaddrs *ifap, *ifa;
    if (getifaddrs(&ifap) == 0) {
        for (ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_name && strcmp(ifa->ifa_name, [name UTF8String]) == 0) {
                flags = ifa->ifa_flags;
                if (ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_INET) {
                    struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
                    char buf[INET_ADDRSTRLEN];
                    if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) ipStr = [NSString stringWithUTF8String:buf];
                }
                if (ifa->ifa_netmask && ifa->ifa_netmask->sa_family == AF_INET) {
                    struct sockaddr_in *msin = (struct sockaddr_in *)ifa->ifa_netmask;
                    char buf[INET_ADDRSTRLEN];
                    if (inet_ntop(AF_INET, &msin->sin_addr, buf, sizeof(buf))) maskStr = [NSString stringWithUTF8String:buf];
                }
                break;
            }
        }
        freeifaddrs(ifap);
    }
    BOOL connected = (flags & IFF_UP) && (flags & IFF_RUNNING);
    [netStatusField setStringValue:[NSString stringWithFormat:@"%@ — %@", name, connected ? @"Connected" : @"Inactive"]];
    [netIPField setStringValue:ipStr];
    [netMaskField setStringValue:maskStr];
}

- (void)networkApply:(id)sender {
    NSString *name = [netIfacePopup titleOfSelectedItem];
    const char *ifname = [name UTF8String];
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock >= 0) {
        struct ifreq ifr;
        memset(&ifr, 0, sizeof(ifr));
        strncpy(ifr.ifr_name, ifname, IFNAMSIZ-1);
        struct sockaddr_in *sin = (struct sockaddr_in *)&ifr.ifr_addr;
        sin->sin_family = AF_INET;
        inet_pton(AF_INET, [[netIPField stringValue] UTF8String], &sin->sin_addr);
        ioctl(sock, SIOCSIFADDR, &ifr);

        memset(&ifr, 0, sizeof(ifr));
        strncpy(ifr.ifr_name, ifname, IFNAMSIZ-1);
         struct sockaddr_in *msin = (struct sockaddr_in *)&ifr.ifr_addr;
        msin->sin_family = AF_INET;
        inet_pton(AF_INET, [[netMaskField stringValue] UTF8String], &msin->sin_addr);
        ioctl(sock, SIOCSIFNETMASK, &ifr);
        close(sock);
    }

    // resolv.conf
    NSMutableString *rc = [NSMutableString string];
    [rc appendFormat:@"nameserver %@\n", [netDNSField stringValue]];
    [rc appendString:@"search local\n"];
    [rc writeToFile:@"/etc/resolv.conf" atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/SystemConfiguration/preferences.plist"]];
    [prefs setObject:name forKey:@"Interface"];
    [prefs setObject:[netIPField stringValue] forKey:@"IPAddress"];
    [prefs setObject:[netMaskField stringValue] forKey:@"SubnetMask"];
    [prefs setObject:[netRouterField stringValue] forKey:@"Router"];
    [prefs setObject:[netDNSField stringValue] forKey:@"DNS"];
    [self writePlist:prefs toPath:@"/Library/Preferences/SystemConfiguration/preferences.plist"];
    [self broadcastPrefsChanged];
}

/* ---------------- Users ---------------- */
static NSArray *parseUsers(void) {
    NSString *content = [NSString stringWithContentsOfFile:@"/etc/passwd" encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *out = [NSMutableArray array];
    // group membership
    NSString *gcontent = [NSString stringWithContentsOfFile:@"/etc/group" encoding:NSUTF8StringEncoding error:nil];
    NSMutableSet *admins = [NSMutableSet set];
    for (NSString *gline in [gcontent componentsSeparatedByString:@"\n"]) {
        NSArray *gf = [gline componentsSeparatedByString:@":"];
        if ([gf count] >= 4 && ([[gf objectAtIndex:0] isEqualToString:@"wheel"] || [[gf objectAtIndex:0] isEqualToString:@"admin"])) {
            NSString *members = [gf objectAtIndex:3];
            for (NSString *m in [members componentsSeparatedByString:@","]) {
                if ([m length]) [admins addObject:m];
            }
        }
    }
    for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
        if ([line length] == 0) continue;
        NSArray *f = [line componentsSeparatedByString:@":"];
        if ([f count] < 7) continue;
        NSString *name = [f objectAtIndex:0];
        int uid = [[f objectAtIndex:2] intValue];
        if (!(uid >= 500 || [name isEqualToString:@"root"] || [name isEqualToString:@"ravyn"])) continue;
        NSString *gecos = [f objectAtIndex:4];
        NSString *full = [gecos length] ? [[gecos componentsSeparatedByString:@","] objectAtIndex:0] : name;
        if ([full length] == 0) full = name;
        BOOL admin = [admins containsObject:name] || (uid == 0) || [name isEqualToString:@"ravyn"];
        [out addObject:[@{@"name":name, @"full":full, @"uid":@(uid), @"admin":@(admin)} mutableCopy]];
    }
    return out;
}

- (NSView *)createUsersPane {
    NSView *v = [[NSView alloc] initWithFrame:[detailContainer bounds]];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 400, 30)];
    [title setStringValue:@"Users & Groups"];
    [title setFont:[NSFont boldSystemFontOfSize:18]];
    [title setEditable:NO]; [title setSelectable:NO]; [title setBezeled:NO]; [title setDrawsBackground:NO];
    [v addSubview:title];

    usersList = [NSMutableArray arrayWithArray:parseUsers()];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 280, 500, 160)];
    [scroll setHasVerticalScroller:YES];
    usersTable = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"User"];
    [[col headerCell] setStringValue:@"Users"];
    [col setWidth:480];
    [usersTable addTableColumn:col];
    [usersTable setDataSource:self];
    [usersTable setDelegate:self];
    [scroll setDocumentView:usersTable];
    [v addSubview:scroll];

    // Add user sheet fields
    NSTextField *addHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 250, 200, 20)];
    [addHeader setStringValue:@"Add New User:"];
    [addHeader setFont:[NSFont boldSystemFontOfSize:12]];
    [addHeader setEditable:NO]; [addHeader setSelectable:NO]; [addHeader setBezeled:NO]; [addHeader setDrawsBackground:NO];
    [v addSubview:addHeader];

    NSTextField *fnLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 220, 110, 20)];
    [fnLabel setStringValue:@"Full Name:"];
    [fnLabel setEditable:NO]; [fnLabel setSelectable:NO]; [fnLabel setBezeled:NO]; [fnLabel setDrawsBackground:NO];
    [v addSubview:fnLabel];
    NSTextField *fullNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 218, 200, 22)];
    [fullNameField setStringValue:@""];
    [v addSubview:fullNameField];

    NSTextField *anLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 192, 110, 20)];
    [anLabel setStringValue:@"Account Name:"];
    [anLabel setEditable:NO]; [anLabel setSelectable:NO]; [anLabel setBezeled:NO]; [anLabel setDrawsBackground:NO];
    [v addSubview:anLabel];
    NSTextField *acctNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 190, 200, 22)];
    [v addSubview:acctNameField];

    NSTextField *pwLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 164, 110, 20)];
    [pwLabel setStringValue:@"Password:"];
    [pwLabel setEditable:NO]; [pwLabel setSelectable:NO]; [pwLabel setBezeled:NO]; [pwLabel setDrawsBackground:NO];
    [v addSubview:pwLabel];
    NSSecureTextField *pwField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(140, 162, 200, 22)];
    [v addSubview:pwField];

    NSTextField *vLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 136, 110, 20)];
    [vLabel setStringValue:@"Verify:"];
    [vLabel setEditable:NO]; [vLabel setSelectable:NO]; [vLabel setBezeled:NO]; [vLabel setDrawsBackground:NO];
    [v addSubview:vLabel];
    NSSecureTextField *verifyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(140, 134, 200, 22)];
    [v addSubview:verifyField];

    NSButton *adminCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 106, 260, 20)];
    [adminCheck setTitle:@"Administrator"];
    [adminCheck setButtonType:NSSwitchButton];
    [adminCheck setState:NSOffState];
    [v addSubview:adminCheck];

    NSButton *addBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 68, 120, 30)];
    [addBtn setTitle:@"Add User"];
    [addBtn setBezelStyle:NSRoundedBezelStyle];
    [addBtn setTarget:self];
    // store fields via tags? We'll use a helper closure impossible; instead read by view hierarchy is messy.
    // We'll store fields in a global-ish dictionary keyed by button tag not possible. Simpler: make addBtn action and find fields by known tags.
    [addBtn setTag:1001];
    [fullNameField setTag:2001]; [acctNameField setTag:2002]; [pwField setTag:2003]; [verifyField setTag:2004]; [adminCheck setTag:2005];
    [addBtn setAction:@selector(addUser:)];
    [v addSubview:addBtn];

    // Change password button
    NSButton *cpBtn = [[NSButton alloc] initWithFrame:NSMakeRect(160, 68, 160, 30)];
    [cpBtn setTitle:@"Change Password…"];
    [cpBtn setBezelStyle:NSRoundedBezelStyle];
    [cpBtn setTarget:self];
    [cpBtn setAction:@selector(changePassword:)];
    [v addSubview:cpBtn];

    // Auto-login
    autoLoginToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, 36, 140, 20)];
    [autoLoginToggle setTitle:@"Auto-login"];
    [autoLoginToggle setButtonType:NSSwitchButton];
    [autoLoginToggle setTarget:self];
    [autoLoginToggle setAction:@selector(autoLoginChanged:)];
    [v addSubview:autoLoginToggle];

    autoLoginPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(170, 32, 200, 28) pullsDown:NO];
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *u in usersList) [names addObject:[u objectForKey:@"name"]];
    [autoLoginPopup addItemsWithTitles:names];
    [autoLoginPopup setTarget:self];
    [autoLoginPopup setAction:@selector(autoLoginChanged:)];
    [v addSubview:autoLoginPopup];

    // Login items
    NSTextField *liHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(360, 250, 160, 20)];
    [liHeader setStringValue:@"Login Items:"];
    [liHeader setFont:[NSFont boldSystemFontOfSize:12]];
    [liHeader setEditable:NO]; [liHeader setSelectable:NO]; [liHeader setBezeled:NO]; [liHeader setDrawsBackground:NO];
    [v addSubview:liHeader];

    NSScrollView *liScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(360, 120, 160, 120)];
    [liScroll setHasVerticalScroller:YES];
    loginItemsTable = [[NSTableView alloc] initWithFrame:[[liScroll contentView] bounds]];
    NSTableColumn *licol = [[NSTableColumn alloc] initWithIdentifier:@"Item"];
    [licol setWidth:140];
    [loginItemsTable addTableColumn:licol];
    [loginItemsTable setDataSource:self];
    [loginItemsTable setDelegate:self];
    [liScroll setDocumentView:loginItemsTable];
    [v addSubview:liScroll];

    NSDictionary *lp = [NSDictionary dictionaryWithContentsOfFile:[@"~/Library/Preferences/com.ravynos.loginwindow.plist" stringByExpandingTildeInPath]];
    loginItemsList = [NSMutableArray arrayWithArray:[lp objectForKey:@"LoginItems"] ?: @[]];

    NSButton *plus = [[NSButton alloc] initWithFrame:NSMakeRect(360, 88, 40, 28)];
    [plus setTitle:@"+"];
    [plus setBezelStyle:NSRoundedBezelStyle];
    [plus setTarget:self]; [plus setAction:@selector(addLoginItem:)];
    [v addSubview:plus];
    NSButton *minus = [[NSButton alloc] initWithFrame:NSMakeRect(410, 88, 40, 28)];
    [minus setTitle:@"-"];
    [minus setBezelStyle:NSRoundedBezelStyle];
    [minus setTarget:self]; [minus setAction:@selector(removeLoginItem:)];
    [v addSubview:minus];

    return v;
}

- (void)addUser:(id)sender {
    NSView *v = [sender superview];
    NSTextField *fnField = (NSTextField *)[v viewWithTag:2001];
    NSTextField *anField = (NSTextField *)[v viewWithTag:2002];
    NSSecureTextField *pwField = (NSSecureTextField *)[v viewWithTag:2003];
    NSSecureTextField *vfField = (NSSecureTextField *)[v viewWithTag:2004];
    NSButton *adminCheck = (NSButton *)[v viewWithTag:2005];

    NSString *full = [fnField stringValue];
    NSString *acct = [anField stringValue];
    NSString *pw = [pwField stringValue];
     NSString *vf = [vfField stringValue];
    if ([acct length] == 0) return;
    if (![pw isEqualToString:vf]) {
        NSAlert *a = [NSAlert alertWithMessageText:@"Passwords do not match" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [a runModal];
        return;
    }
    // determine uid
    int maxUid = 500;
    for (NSDictionary *u in usersList) if ([[u objectForKey:@"uid"] intValue] > maxUid) maxUid = [[u objectForKey:@"uid"] intValue];
    int newUid = maxUid + 1;
    NSString *home = [NSString stringWithFormat:@"/Users/%@", acct];
    ensureDir(home);

    NSString *hash = sys_password_hash(pw, @"ravynOS");

    NSString *gecos = [full length] ? full : acct;
    NSString *passwdLine = [NSString stringWithFormat:@"%@:%@:%d:%d:%@:%@:/bin/sh\n", acct, @"*", newUid, 20, gecos, home];
    NSString *masterLine = [NSString stringWithFormat:@"%@:%@:%d:%d::0:0:%@:%@:/bin/sh\n", acct, hash, newUid, 20, gecos, home];

    // append
    NSData *d1 = [passwdLine dataUsingEncoding:NSUTF8StringEncoding];
    // Use NSFileManager append via fileHandleForUpdating
    NSFileHandle *h = [NSFileHandle fileHandleForUpdatingAtPath:@"/etc/passwd"];
    [h seekToEndOfFile];
    [h writeData:d1];
    [h closeFile];

    NSFileHandle *h2 = [NSFileHandle fileHandleForUpdatingAtPath:@"/etc/master.passwd"];
    [h2 seekToEndOfFile];
    [h2 writeData:[masterLine dataUsingEncoding:NSUTF8StringEncoding]];
    [h2 closeFile];

    if([adminCheck state] == NSOnState) {
        /* Administrators are members of wheel. */
        NSString *group = [NSString stringWithContentsOfFile:@"/etc/group"
                                                    encoding:NSUTF8StringEncoding error:nil];
        NSMutableArray *lines = [NSMutableArray arrayWithArray:
            [group componentsSeparatedByString:@"\n"]];
        int i;

        for(i = 0; i < (int)[lines count]; i++) {
            NSString *line = [lines objectAtIndex:i];
            NSArray *f = [line componentsSeparatedByString:@":"];

            if([f count] >= 4 && [[f objectAtIndex:0] isEqualToString:@"wheel"]) {
                NSString *members = [f objectAtIndex:3];
                if([members rangeOfString:acct].location == NSNotFound) {
                    NSString *updated = [NSString stringWithFormat:@"%@:%@:%@:%@,%@",
                        [f objectAtIndex:0], [f objectAtIndex:1],
                        [f objectAtIndex:2],
                        [members length] ? members : @"", acct];
                    [lines replaceObjectAtIndex:i withObject:updated];
                }
            }
        }
        [[lines componentsJoinedByString:@"\n"] writeToFile:@"/etc/group"
                                                   atomically:YES
                                                     encoding:NSUTF8StringEncoding error:nil];
    }

    usersList = [NSMutableArray arrayWithArray:parseUsers()];
    [usersTable reloadData];
}

- (void)changePassword:(id)sender {
    NSAlert *prompt = [NSAlert alertWithMessageText:@"Change Password" defaultButton:@"OK" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"Enter username:newpass (e.g. ravyn:newpass)"];
    // We'll use a text field accessory? Simpler: ask via two fields not possible. Use NSAlert with accessory? Skip fancy; read from a small input dialog impossible.
    // Implement minimal: change password for selected user using an alert with input field.
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,200,24)];
    [input setStringValue:@"username:newpassword"];
    NSAlert *a = [NSAlert alertWithMessageText:@"Change Password" defaultButton:@"OK" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"username:newpassword"];
    [a setAccessoryView:input];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    NSString *val = [input stringValue];
    NSArray *parts = [val componentsSeparatedByString:@":"];
    if ([parts count] < 2) return;
    NSString *user = [parts objectAtIndex:0];
    NSString *newpw = [parts objectAtIndex:1];
     NSString *hash = sys_password_hash(newpw, @"ravynOS");

    // update /etc/master.passwd
    NSString *content = [NSString stringWithContentsOfFile:@"/etc/master.passwd" encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *lines = [NSMutableArray arrayWithArray:[content componentsSeparatedByString:@"\n"]];
    for (int i = 0; i < (int)[lines count]; i++) {
        NSString *line = [lines objectAtIndex:i];
        NSArray *f = [line componentsSeparatedByString:@":"];
        if ([f count] >= 2 && [[f objectAtIndex:0] isEqualToString:user]) {
            NSMutableArray *mf = [NSMutableArray arrayWithArray:f];
            [mf replaceObjectAtIndex:1 withObject:hash];
            [lines replaceObjectAtIndex:i withObject:[mf componentsJoinedByString:@":"]];
        }
    }
    [[lines componentsJoinedByString:@"\n"] writeToFile:@"/etc/master.passwd" atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // /etc/passwd keeps '*' usually; leave as is.
    NSAlert *done = [NSAlert alertWithMessageText:@"Password updated" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
    [done runModal];
}

- (void)autoLoginChanged:(id)sender {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/com.ravynos.WindowServer.plist"]];
    if ([autoLoginToggle state] == NSOnState) {
        [prefs setObject:[autoLoginPopup titleOfSelectedItem] forKey:@"autoLoginUser"];
    } else {
        [prefs removeObjectForKey:@"autoLoginUser"];
    }
    [self writePlist:prefs toPath:@"/Library/Preferences/com.ravynos.WindowServer.plist"];
    [self broadcastPrefsChanged];
}

- (void)addLoginItem:(id)sender {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setCanChooseFiles:YES];
    [op setCanChooseDirectories:NO];
    if ([op runModalForDirectory:@"/Applications" file:nil types:nil] == 1) {
         NSString *path = ([op filenames] && [[op filenames] count]) ? [[op filenames] objectAtIndex:0] : nil;
        if (path) {
            [loginItemsList addObject:path];
            NSString *p = [@"~/Library/Preferences/com.ravynos.loginwindow.plist" stringByExpandingTildeInPath];
            NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:p]];
            [d setObject:loginItemsList forKey:@"LoginItems"];
            [self writePlist:d toPath:p];
            [loginItemsTable reloadData];
        }
    }
}

- (void)removeLoginItem:(id)sender {
    int row = (int)[loginItemsTable selectedRow];
    if (row >= 0 && row < (int)[loginItemsList count]) {
        [loginItemsList removeObjectAtIndex:row];
        NSString *p = [@"~/Library/Preferences/com.ravynos.loginwindow.plist" stringByExpandingTildeInPath];
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:p]];
        [d setObject:loginItemsList forKey:@"LoginItems"];
        [self writePlist:d toPath:p];
        [loginItemsTable reloadData];
    }
}

/* ---------------- Appearance ---------------- */
- (NSView *)createAppearancePane {
    NSView *v = [[NSView alloc] initWithFrame:[detailContainer bounds]];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 400, 30)];
    [title setStringValue:@"Appearance & Dock"];
    [title setFont:[NSFont boldSystemFontOfSize:18]];
    [title setEditable:NO]; [title setSelectable:NO]; [title setBezeled:NO]; [title setDrawsBackground:NO];
    [v addSubview:title];

    NSDictionary *gp = [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/.GlobalPreferences.plist"];
    NSString *style = [gp objectForKey:@"AppleInterfaceStyle"] ?: @"Light";
    BOOL dark = [style isEqualToString:@"Dark"];

    NSTextField *modeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 420, 200, 20)];
    [modeLabel setStringValue:@"Appearance:"];
    [modeLabel setEditable:NO]; [modeLabel setSelectable:NO]; [modeLabel setBezeled:NO]; [modeLabel setDrawsBackground:NO];
    [v addSubview:modeLabel];

    appearanceLightBtn = [[NSButton alloc] initWithFrame:NSMakeRect(30, 390, 120, 28)];
    [appearanceLightBtn setTitle:@"Light"];
    [appearanceLightBtn setButtonType:NSRadioButton];
    if (!dark) [appearanceLightBtn setState:NSOnState];
    [appearanceLightBtn setTarget:self]; [appearanceLightBtn setAction:@selector(appearanceChanged:)];
    [v addSubview:appearanceLightBtn];

    appearanceDarkBtn = [[NSButton alloc] initWithFrame:NSMakeRect(160, 390, 120, 28)];
    [appearanceDarkBtn setTitle:@"Dark"];
    [appearanceDarkBtn setButtonType:NSRadioButton];
    if (dark) [appearanceDarkBtn setState:NSOnState];
    [appearanceDarkBtn setTarget:self]; [appearanceDarkBtn setAction:@selector(appearanceChanged:)];
    [v addSubview:appearanceDarkBtn];

    // accent swatches
    NSTextField *accentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 355, 200, 20)];
    [accentLabel setStringValue:@"Accent Color:"];
    [accentLabel setEditable:NO]; [accentLabel setSelectable:NO]; [accentLabel setBezeled:NO]; [accentLabel setDrawsBackground:NO];
    [v addSubview:accentLabel];
    NSArray *accents = @[@"Blue", @"Purple", @"Pink", @"Red", @"Orange", @"Yellow", @"Green", @"Graphite"];
    for (int i = 0; i < (int)[accents count]; i++) {
        NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(30 + i*60, 325, 56, 24)];
        [b setTitle:[accents objectAtIndex:i]];
        [b setButtonType:NSRadioButton];
        if (i == 0) [b setState:NSOnState];
        [b setTag:3000+i];
        [b setTarget:self]; [b setAction:@selector(appearanceChanged:)];
        [v addSubview:b];
    }

    // Dock settings
    NSTextField *dockLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 285, 200, 20)];
    [dockLabel setStringValue:@"Dock:"];
    [dockLabel setFont:[NSFont boldSystemFontOfSize:12]];
    [dockLabel setEditable:NO]; [dockLabel setSelectable:NO]; [dockLabel setBezeled:NO]; [dockLabel setDrawsBackground:NO];
    [v addSubview:dockLabel];

    NSTextField *sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 255, 120, 20)];
    [sizeLabel setStringValue:@"Icon Size:"];
    [sizeLabel setEditable:NO]; [sizeLabel setSelectable:NO]; [sizeLabel setBezeled:NO]; [sizeLabel setDrawsBackground:NO];
    [v addSubview:sizeLabel];
    /* The Dock stores its settings in its own NSUserDefaults domain
     * (~/Library/Preferences/com.ravynos.Dock.plist) under the keys the Dock
     * itself reads: "tilesize", "autohide" and "Location".  Read those, so
     * the pane shows the Dock's real state. */
    /* The Dock reads /Library/Preferences/Dock.plist; keep both locations in
     * sync so the pane always shows the state the Dock is using. */
    NSDictionary *dp = [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/Dock.plist"];
    if(dp == nil)
        dp = [NSDictionary dictionaryWithContentsOfFile:[@"~/Library/Preferences/com.ravynos.Dock.plist" stringByExpandingTildeInPath]];
    CGFloat curSize = [[dp objectForKey:@"tilesize"] doubleValue];
    if (curSize < 32) curSize = 48;
    dockSizeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(140, 255, 200, 24)];
    [dockSizeSlider setMinValue:32]; [dockSizeSlider setMaxValue:96];
    [dockSizeSlider setDoubleValue:curSize];
    [dockSizeSlider setTarget:self]; [dockSizeSlider setAction:@selector(appearanceChanged:)];
    [v addSubview:dockSizeSlider];

    dockMagnifyCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 225, 200, 20)];
    [dockMagnifyCheck setTitle:@"Magnification"];
    [dockMagnifyCheck setButtonType:NSSwitchButton];
    [dockMagnifyCheck setState:[[dp objectForKey:@"magnification"] boolValue] ? NSOnState : NSOffState];
    [dockMagnifyCheck setTarget:self]; [dockMagnifyCheck setAction:@selector(appearanceChanged:)];
    [v addSubview:dockMagnifyCheck];

    dockAutoHideCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 195, 200, 20)];
    [dockAutoHideCheck setTitle:@"Auto-hide Dock"];
    [dockAutoHideCheck setButtonType:NSSwitchButton];
    [dockAutoHideCheck setState:[[dp objectForKey:@"autohide"] boolValue] ? NSOnState : NSOffState];
    [dockAutoHideCheck setTarget:self]; [dockAutoHideCheck setAction:@selector(appearanceChanged:)];
    [v addSubview:dockAutoHideCheck];

    NSTextField *posLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 165, 120, 20)];
    [posLabel setStringValue:@"Position:"];
    [posLabel setEditable:NO]; [posLabel setSelectable:NO]; [posLabel setBezeled:NO]; [posLabel setDrawsBackground:NO];
    [v addSubview:posLabel];
    int posValue = [[dp objectForKey:@"Location"] intValue];
    NSString *pos = posValue == 1 ? @"Left" : (posValue == 2 ? @"Right" : @"Bottom");
    dockPosBottom = [[NSButton alloc] initWithFrame:NSMakeRect(140, 165, 90, 24)];
    [dockPosBottom setTitle:@"Bottom"]; [dockPosBottom setButtonType:NSRadioButton];
    if ([pos isEqualToString:@"Bottom"]) [dockPosBottom setState:NSOnState];
    [dockPosBottom setTarget:self]; [dockPosBottom setAction:@selector(appearanceChanged:)];
    [v addSubview:dockPosBottom];
    dockPosLeft = [[NSButton alloc] initWithFrame:NSMakeRect(230, 165, 70, 24)];
    [dockPosLeft setTitle:@"Left"]; [dockPosLeft setButtonType:NSRadioButton];
    if ([pos isEqualToString:@"Left"]) [dockPosLeft setState:NSOnState];
    [dockPosLeft setTarget:self]; [dockPosLeft setAction:@selector(appearanceChanged:)];
    [v addSubview:dockPosLeft];
    dockPosRight = [[NSButton alloc] initWithFrame:NSMakeRect(300, 165, 70, 24)];
    [dockPosRight setTitle:@"Right"]; [dockPosRight setButtonType:NSRadioButton];
    if ([pos isEqualToString:@"Right"]) [dockPosRight setState:NSOnState];
    [dockPosRight setTarget:self]; [dockPosRight setAction:@selector(appearanceChanged:)];
    [v addSubview:dockPosRight];

    return v;
}

- (void)appearanceChanged:(id)sender {
    BOOL dark = ([appearanceDarkBtn state] == NSOnState);
    NSMutableDictionary *gp = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/.GlobalPreferences.plist"]];
    [gp setObject:(dark ? @"Dark" : @"Light") forKey:@"AppleInterfaceStyle"];

    // accent
    for (int i = 0; i < 8; i++) {
        NSButton *b = (NSButton *)[[sender superview] viewWithTag:3000+i];
        if (b && [b state] == NSOnState) [gp setObject:[b title] forKey:@"AppleAccentColor"];
    }

    NSString *pos = @"Bottom";
    if ([dockPosLeft state] == NSOnState) pos = @"Left";
    if ([dockPosRight state] == NSOnState) pos = @"Right";
    /* Update the Dock's own domain in place: the file also holds the Dock's
     * tile list, which must survive a preference change. */
    NSMutableDictionary *dp = [NSMutableDictionary dictionaryWithDictionary:
        ([NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/Dock.plist"] != nil ?
         [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/Dock.plist"] :
         ([NSDictionary dictionaryWithContentsOfFile:
            [@"~/Library/Preferences/com.ravynos.Dock.plist" stringByExpandingTildeInPath]] ?: [NSDictionary dictionary]))];
    [dp setObject:[NSNumber numberWithInt:(int)[dockSizeSlider doubleValue]] forKey:@"tilesize"];
    [dp setObject:[NSNumber numberWithBool:([dockMagnifyCheck state]==NSOnState)] forKey:@"magnification"];
    [dp setObject:[NSNumber numberWithBool:([dockAutoHideCheck state]==NSOnState)] forKey:@"autohide"];
    [dp setObject:[NSNumber numberWithInt:([pos isEqualToString:@"Left"] ? 1 :
                                           ([pos isEqualToString:@"Right"] ? 2 : 0))]
           forKey:@"Location"];

    [self writePlist:gp toPath:@"/Library/Preferences/.GlobalPreferences.plist"];
    [self writePlist:dp toPath:@"/Library/Preferences/Dock.plist"];
    [self writePlist:dp toPath:[@"~/Library/Preferences/com.ravynos.Dock.plist" stringByExpandingTildeInPath]];
    [self broadcastPrefsChanged];
}

/* ---------------- Keyboard ---------------- */
- (NSView *)createKeyboardPane {
    NSView *v = [[NSView alloc] initWithFrame:[detailContainer bounds]];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 400, 30)];
    [title setStringValue:@"Keyboard & Mouse"];
    [title setFont:[NSFont boldSystemFontOfSize:18]];
    [title setEditable:NO]; [title setSelectable:NO]; [title setBezeled:NO]; [title setDrawsBackground:NO];
    [v addSubview:title];

    NSDictionary *ip = [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/com.ravynos.Input.plist"];
    double kr = [[ip objectForKey:@"KeyRepeat"] doubleValue]; if (kr < 15) kr = 40;
    double kd = [[ip objectForKey:@"KeyDelay"] doubleValue]; if (kd < 150) kd = 500;
    double ts = [[ip objectForKey:@"TrackingSpeed"] doubleValue]; if (ts < 0.25) ts = 1.0;
    NSString *caps = [ip objectForKey:@"CapsLockAction"] ?: @"Caps Lock";
    BOOL swap = [[ip objectForKey:@"SwapCmdOpt"] boolValue];
    BOOL nat = [[ip objectForKey:@"NaturalScrolling"] boolValue];

    NSTextField *krLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 420, 200, 20)];
    [krLabel setStringValue:@"Key Repeat Rate (ms):"];
    [krLabel setEditable:NO]; [krLabel setSelectable:NO]; [krLabel setBezeled:NO]; [krLabel setDrawsBackground:NO];
    [v addSubview:krLabel];
    keyRepeatSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 395, 260, 24)];
    [keyRepeatSlider setMinValue:15]; [keyRepeatSlider setMaxValue:120];
    [keyRepeatSlider setDoubleValue:kr];
    [keyRepeatSlider setTarget:self]; [keyRepeatSlider setAction:@selector(keyboardChanged:)];
    [v addSubview:keyRepeatSlider];

    NSTextField *kdLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 360, 200, 20)];
    [kdLabel setStringValue:@"Delay Until Repeat (ms):"];
    [kdLabel setEditable:NO]; [kdLabel setSelectable:NO]; [kdLabel setBezeled:NO]; [kdLabel setDrawsBackground:NO];
    [v addSubview:kdLabel];
    keyDelaySlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 335, 260, 24)];
    [keyDelaySlider setMinValue:150]; [keyDelaySlider setMaxValue:1000];
    [keyDelaySlider setDoubleValue:kd];
    [keyDelaySlider setTarget:self]; [keyDelaySlider setAction:@selector(keyboardChanged:)];
    [v addSubview:keyDelaySlider];

    NSTextField *capsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 300, 120, 20)];
    [capsLabel setStringValue:@"Caps Lock:"];
    [capsLabel setEditable:NO]; [capsLabel setSelectable:NO]; [capsLabel setBezeled:NO]; [capsLabel setDrawsBackground:NO];
    [v addSubview:capsLabel];
    capsLockPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 296, 200, 28) pullsDown:NO];
    [capsLockPopup addItemsWithTitles:@[@"Caps Lock", @"Control", @"Escape", @"No Action"]];
    [capsLockPopup selectItemWithTitle:caps];
    [capsLockPopup setTarget:self]; [capsLockPopup setAction:@selector(keyboardChanged:)];
    [v addSubview:capsLockPopup];

    swapCmdOptCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 265, 220, 20)];
    [swapCmdOptCheck setTitle:@"Swap Command and Option"];
    [swapCmdOptCheck setButtonType:NSSwitchButton];
    [swapCmdOptCheck setState:swap ? NSOnState : NSOffState];
    [swapCmdOptCheck setTarget:self]; [swapCmdOptCheck setAction:@selector(keyboardChanged:)];
    [v addSubview:swapCmdOptCheck];

    NSTextField *tsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 230, 200, 20)];
    [tsLabel setStringValue:@"Tracking Speed:"];
    [tsLabel setEditable:NO]; [tsLabel setSelectable:NO]; [tsLabel setBezeled:NO]; [tsLabel setDrawsBackground:NO];
    [v addSubview:tsLabel];
    trackingSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 205, 260, 24)];
    [trackingSlider setMinValue:0.25]; [trackingSlider setMaxValue:3.0];
    [trackingSlider setDoubleValue:ts];
    [trackingSlider setTarget:self]; [trackingSlider setAction:@selector(keyboardChanged:)];
    [v addSubview:trackingSlider];

    naturalScrollCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 175, 220, 20)];
    [naturalScrollCheck setTitle:@"Natural Scrolling"];
    [naturalScrollCheck setButtonType:NSSwitchButton];
    [naturalScrollCheck setState:nat ? NSOnState : NSOffState];
    [naturalScrollCheck setTarget:self]; [naturalScrollCheck setAction:@selector(keyboardChanged:)];
    [v addSubview:naturalScrollCheck];

    return v;
}

- (void)keyboardChanged:(id)sender {
    NSMutableDictionary *ip = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/com.ravynos.Input.plist"]];
    [ip setObject:[NSNumber numberWithDouble:[keyRepeatSlider doubleValue]] forKey:@"KeyRepeat"];
    [ip setObject:[NSNumber numberWithDouble:[keyDelaySlider doubleValue]] forKey:@"KeyDelay"];
    [ip setObject:[capsLockPopup titleOfSelectedItem] forKey:@"CapsLockAction"];
    [ip setObject:[NSNumber numberWithBool:([swapCmdOptCheck state]==NSOnState)] forKey:@"SwapCmdOpt"];
    [ip setObject:[NSNumber numberWithDouble:[trackingSlider doubleValue]] forKey:@"TrackingSpeed"];
    [ip setObject:[NSNumber numberWithBool:([naturalScrollCheck state]==NSOnState)] forKey:@"NaturalScrolling"];
    [self writePlist:ip toPath:@"/Library/Preferences/com.ravynos.Input.plist"];
    [self broadcastPrefsChanged];
}

/* ---------------- Sound ---------------- */
- (NSView *)createSoundPane {
    NSView *v = [[NSView alloc] initWithFrame:[detailContainer bounds]];

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 400, 30)];
    [title setStringValue:@"Sound"];
    [title setFont:[NSFont boldSystemFontOfSize:18]];
    [title setEditable:NO]; [title setSelectable:NO]; [title setBezeled:NO]; [title setDrawsBackground:NO];
    [v addSubview:title];

    // build device list from /dev
    soundOutDevices = [NSMutableArray array];
    soundInDevices = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *devs = [fm contentsOfDirectoryAtPath:@"/dev" error:nil];
    for (NSString *d in devs) {
        NSString *low = [d lowercaseString];
         if ([low rangeOfString:@"audio"].location != NSNotFound || [low rangeOfString:@"dsp"].location != NSNotFound || [low rangeOfString:@"pcm"].location != NSNotFound || [low rangeOfString:@"hda"].location != NSNotFound) {
            [soundOutDevices addObject:d];
            [soundInDevices addObject:d];
        }
    }
    if ([soundOutDevices count] == 0) {
        soundOutDevices = [NSMutableArray arrayWithObject:@"No audio device present"];
        soundInDevices = [NSMutableArray arrayWithObject:@"No audio device present"];
    }

    NSTextField *outLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 420, 200, 20)];
    [outLabel setStringValue:@"Output Devices:"];
    [outLabel setFont:[NSFont boldSystemFontOfSize:12]];
    [outLabel setEditable:NO]; [outLabel setSelectable:NO]; [outLabel setBezeled:NO]; [outLabel setDrawsBackground:NO];
    [v addSubview:outLabel];

    NSScrollView *outScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 330, 220, 80)];
    [outScroll setHasVerticalScroller:YES];
    soundOutTable = [[NSTableView alloc] initWithFrame:[[outScroll contentView] bounds]];
    NSTableColumn *oc = [[NSTableColumn alloc] initWithIdentifier:@"Out"];
    [oc setWidth:200];
    [soundOutTable addTableColumn:oc];
    [soundOutTable setDataSource:self];
    [outScroll setDocumentView:soundOutTable];
    [v addSubview:outScroll];

    soundVolSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 300, 220, 24)];
    [soundVolSlider setMinValue:0]; [soundVolSlider setMaxValue:100];
    NSDictionary *sp = [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/com.ravynos.Sound.plist"];
    [soundVolSlider setDoubleValue:[[sp objectForKey:@"OutputVolume"] doubleValue] ?: 75.0];
    [soundVolSlider setTarget:self]; [soundVolSlider setAction:@selector(soundChanged:)];
    [v addSubview:soundVolSlider];

    soundMuteCheck = [[NSButton alloc] initWithFrame:NSMakeRect(250, 300, 80, 24)];
    [soundMuteCheck setTitle:@"Mute"];
    [soundMuteCheck setButtonType:NSSwitchButton];
    [soundMuteCheck setState:[[sp objectForKey:@"Mute"] boolValue] ? NSOnState : NSOffState];
    [soundMuteCheck setTarget:self]; [soundMuteCheck setAction:@selector(soundChanged:)];
    [v addSubview:soundMuteCheck];

    NSTextField *alertLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 265, 200, 20)];
    [alertLabel setStringValue:@"Alert Sound:"];
    [alertLabel setFont:[NSFont boldSystemFontOfSize:12]];
    [alertLabel setEditable:NO]; [alertLabel setSelectable:NO]; [alertLabel setBezeled:NO]; [alertLabel setDrawsBackground:NO];
    [v addSubview:alertLabel];
    alertSoundPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 235, 220, 28) pullsDown:NO];
    [alertSoundPopup addItemsWithTitles:@[@"Basso", @"Blow", @"Bottle", @"Frog", @"Funk", @"Glass", @"Ping", @"Pop", @"Purr", @"Tink"]];
    [alertSoundPopup setTarget:self]; [alertSoundPopup setAction:@selector(playAlertSound:)];
    [v addSubview:alertSoundPopup];

    NSTextField *inLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(280, 420, 200, 20)];
    [inLabel setStringValue:@"Input Devices:"];
    [inLabel setFont:[NSFont boldSystemFontOfSize:12]];
    [inLabel setEditable:NO]; [inLabel setSelectable:NO]; [inLabel setBezeled:NO]; [inLabel setDrawsBackground:NO];
    [v addSubview:inLabel];

    NSScrollView *inScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(280, 330, 220, 80)];
    [inScroll setHasVerticalScroller:YES];
    soundInTable = [[NSTableView alloc] initWithFrame:[[inScroll contentView] bounds]];
    NSTableColumn *ic = [[NSTableColumn alloc] initWithIdentifier:@"In"];
    [ic setWidth:200];
    [soundInTable addTableColumn:ic];
    [soundInTable setDataSource:self];
    [inScroll setDocumentView:soundInTable];
    [v addSubview:inScroll];

    soundInputVolSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(280, 300, 220, 24)];
    [soundInputVolSlider setMinValue:0]; [soundInputVolSlider setMaxValue:100];
    [soundInputVolSlider setDoubleValue:[[sp objectForKey:@"InputVolume"] doubleValue] ?: 50.0];
    [soundInputVolSlider setTarget:self]; [soundInputVolSlider setAction:@selector(soundChanged:)];
    [v addSubview:soundInputVolSlider];

    soundLevelField = [[NSTextField alloc] initWithFrame:NSMakeRect(280, 270, 220, 20)];
    [soundLevelField setStringValue:@"Input Level: (meter)"];
    [soundLevelField setEditable:NO]; [soundLevelField setSelectable:NO]; [soundLevelField setBezeled:NO]; [soundLevelField setDrawsBackground:NO];
    [v addSubview:soundLevelField];

     if ([soundOutDevices count] == 1 && [[soundOutDevices objectAtIndex:0] isEqualToString:@"No audio device present"]) {
        NSTextField *nd = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 180, 480, 40)];
        [nd setStringValue:@"No audio device present. Sound settings are stored but no playback is available."];
        [nd setEditable:NO]; [nd setSelectable:NO]; [nd setBezeled:NO]; [nd setDrawsBackground:NO];
        [v addSubview:nd];
        soundNoDeviceLabel = nd;
    }

    return v;
}

- (void)endVisualBell:(id)sender {
    if (window != nil) {
        [window setBackgroundColor:[NSColor windowBackgroundColor]];
        [window display];
    }
}

- (void)playAlertSound:(id)sender {
    NSBeep();
    // visual bell: flash the window background, restore it shortly after
    if (window != nil) {
        [window setBackgroundColor:[NSColor colorWithCalibratedWhite:0.85 alpha:1.0]];
        [window display];
        [self performSelector:@selector(endVisualBell:) withObject:nil afterDelay:0.12];
    }
}

- (void)soundChanged:(id)sender {
    NSMutableDictionary *sp = [NSMutableDictionary dictionaryWithDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/com.ravynos.Sound.plist"]];
    [sp setObject:[NSNumber numberWithDouble:[soundVolSlider doubleValue]] forKey:@"OutputVolume"];
    [sp setObject:[NSNumber numberWithBool:([soundMuteCheck state]==NSOnState)] forKey:@"Mute"];
    [sp setObject:[NSNumber numberWithDouble:[soundInputVolSlider doubleValue]] forKey:@"InputVolume"];
    [self writePlist:sp toPath:@"/Library/Preferences/com.ravynos.Sound.plist"];
    // best-effort OSS mixer volume (ignored failures: no mixer device on most systems)
    int fd = open("/dev/mixer", O_WRONLY);
    if (fd >= 0) {
        int vol = (int)[soundVolSlider doubleValue];
        if (vol < 0) vol = 0;
        if (vol > 100) vol = 100;
        int packed = (vol & 0x7f) | ((vol & 0x7f) << 8);
        if ([soundMuteCheck state] == NSOnState) packed = 0;
        ioctl(fd, SOUND_MIXER_WRITE_VOLUME, &packed);
        close(fd);
    }
    [self broadcastPrefsChanged];
}

@end