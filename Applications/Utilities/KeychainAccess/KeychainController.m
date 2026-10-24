#import "KeychainController.h"
#import "PasswordGeneratorWindow.h"

@implementation KeychainController
@synthesize window, selectedVault, vaults, keychainTable, categoryTable, itemTable, searchField, lockButton, showPasswordButton, detailField, filteredItems, selectedItem, selectedCategory;

- (id)init {
    self = [super init];
    if (self) {
        vaults = [NSMutableArray array];
        filteredItems = [NSMutableArray array];
        selectedCategory = 0;
        NSString *home = NSHomeDirectory();
        NSString *loginPath = [home stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];

        [vaults addObject:[KeychainVault vaultWithPath:loginPath]];
        [vaults addObject:[KeychainVault vaultWithPath:@"/Library/Keychains/System.keychain"]];
        selectedVault = vaults[0];

        /* First launch: create the login keychain with the account password
         * and seed one item, so the window opens showing a real, unlocked
         * keychain instead of an empty locked one. */
        if (![[NSFileManager defaultManager] fileExistsAtPath:loginPath]) {
            NSError *error = nil;
            KeychainItem *seed = [[KeychainItem alloc] init];

            seed.itemClass = @"password";
            seed.service = @"ravynOS Local Account";
            seed.account = NSUserName() ?: @"ravyn";
            seed.label = @"ravynOS Local Account";
            seed.secretData = [@"ravyn" dataUsingEncoding:NSUTF8StringEncoding];
            seed.notes = @"Created on first launch by Keychain Access.";
            if ([selectedVault unlockWithPassword:@"ravyn" error:&error])
                [selectedVault addItem:seed error:NULL];
        }

        if (!selectedVault.isLocked)
            [self refreshItems];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSError *error = nil;

    [self buildWindow];

    /* Unlock with the default login password when the vault already exists so
     * the user sees their items immediately; Lock still requires the
     * password to unlock again. */
    if (selectedVault.isLocked && selectedVault.exists)
        [selectedVault unlockWithPassword:@"ravyn" error:&error];

    [self refreshItems];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(80, 60, 980, 600);
    window = [[NSWindow alloc] initWithContentRect:frame
                                        styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [window setTitle:@"Keychain Access"];
    [window setDelegate:self];
    [window center];
    NSView *content = [window contentView];
    NSRect cb = [content bounds];

    // Left sidebar: keychains table (top) + categories (bottom)
    CGFloat sideW = 220;
    NSScrollView *ks = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, cb.size.height-180, sideW, 180)];
    [ks setHasVerticalScroller:YES];
    keychainTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,sideW,180)];
    NSTableColumn *kc = [[NSTableColumn alloc] initWithIdentifier:@"keychain"];
    [kc setWidth:sideW-10];
    [[kc headerCell] setStringValue:@"Keychains"];
    [keychainTable addTableColumn:kc];
    [keychainTable setDataSource:self];
    [keychainTable setDelegate:self];
    [keychainTable setHeaderView:nil];
    [ks setDocumentView:keychainTable];
    [content addSubview:ks];

    NSScrollView *cs = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 40, sideW, cb.size.height-220)];
    [cs setHasVerticalScroller:YES];
    categoryTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,sideW,cb.size.height-220)];
    NSTableColumn *cc = [[NSTableColumn alloc] initWithIdentifier:@"category"];
    [cc setWidth:sideW-10];
    [categoryTable addTableColumn:cc];
    [categoryTable setDataSource:self];
    [categoryTable setDelegate:self];
    [categoryTable setHeaderView:nil];
    [cs setDocumentView:categoryTable];
    [content addSubview:cs];

    // Toolbar bar
    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(sideW, cb.size.height-44, cb.size.width-sideW, 44)];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    lockButton = [[NSButton alloc] initWithFrame:NSMakeRect(8,8,100,28)];
    [lockButton setTitle:@"Lock"];
    [lockButton setBezelStyle:NSRoundedBezelStyle];
    [lockButton setTarget:self]; [lockButton setAction:@selector(lockUnlock:)];
    [bar addSubview:lockButton];

    NSButton *newBtn = [[NSButton alloc] initWithFrame:NSMakeRect(116,8,90,28)];
    [newBtn setTitle:@"New Item"];
    [newBtn setBezelStyle:NSRoundedBezelStyle];
    [newBtn setTarget:self]; [newBtn setAction:@selector(newItem:)];
    [bar addSubview:newBtn];

    NSButton *genBtn = [[NSButton alloc] initWithFrame:NSMakeRect(214,8,110,28)];
    [genBtn setTitle:@"Password Assistant"];
    [genBtn setBezelStyle:NSRoundedBezelStyle];
    [genBtn setTarget:self]; [genBtn setAction:@selector(openGenerator:)];
    [bar addSubview:genBtn];

    NSButton *delBtn = [[NSButton alloc] initWithFrame:NSMakeRect(332,8,70,28)];
    [delBtn setTitle:@"Delete"];
    [delBtn setBezelStyle:NSRoundedBezelStyle];
    [delBtn setTarget:self]; [delBtn setAction:@selector(deleteItem:)];
    [bar addSubview:delBtn];

    showPasswordButton = [[NSButton alloc] initWithFrame:NSMakeRect(410,8,120,28)];
    [showPasswordButton setTitle:@"Show Password"];
    [showPasswordButton setBezelStyle:NSRoundedBezelStyle];
    [showPasswordButton setTarget:self]; [showPasswordButton setAction:@selector(showPassword:)];
    [bar addSubview:showPasswordButton];

    searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(cb.size.width-sideW-200,8,180,28)];
    [[searchField cell] setPlaceholderString:@"Search"];
    [searchField setTarget:self]; [searchField setAction:@selector(searchChanged:)];
    [bar addSubview:searchField];
    [content addSubview:bar];

    // Item table
    NSScrollView *its = [[NSScrollView alloc] initWithFrame:NSMakeRect(sideW, 180, cb.size.width-sideW, cb.size.height-224)];
    [its setHasVerticalScroller:YES];
    [its setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    itemTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,cb.size.width-sideW, cb.size.height-224)];
    NSArray *cols = @[@[@"Name",@"name",@180], @[@"Kind",@"kind",@100], @[@"Account/Service",@"acct",@200], @[@"Modified",@"mod",@160]];
    for (NSArray *cinfo in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cinfo[1]];
        [col setWidth:[cinfo[2] floatValue]];
        [[col headerCell] setStringValue:cinfo[0]];
        [itemTable addTableColumn:col];
    }
    [itemTable setDataSource:self];
    [itemTable setDelegate:self];
    [itemTable setDoubleAction:@selector(itemDoubleClicked:)];
    [itemTable setTarget:self];
    [its setDocumentView:itemTable];
    [content addSubview:its];

    // Detail area
    detailField = [[NSTextField alloc] initWithFrame:NSMakeRect(sideW, 40, cb.size.width-sideW, 130)];
    [detailField setBezeled:YES];
    [detailField setEditable:NO];
    [detailField setSelectable:YES];
    [content addSubview:detailField];

    [window makeKeyAndOrderFront:nil];
    [keychainTable reloadData];
    [categoryTable reloadData];
}

- (void)refreshItems {
    NSString *cls = nil;
    if (selectedCategory == 1) cls = @"password";
    else if (selectedCategory == 2) cls = @"note";
    else if (selectedCategory == 3) cls = @"certificate";
    NSArray *items = [selectedVault itemsMatchingClass:cls];
    NSString *q = [[searchField stringValue] lowercaseString];
    [filteredItems removeAllObjects];
    for (KeychainItem *it in items) {
        if (q.length) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@", it.displayTitle, it.service?:@"", it.account?:@"", it.notes?:@""];
            if ([hay rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        }
        [filteredItems addObject:it];
    }
    [itemTable reloadData];
    // lock button title
    if (selectedVault.isLocked) [lockButton setTitle:@"Unlock"]; else [lockButton setTitle:@"Lock"];
}

#pragma mark - NSTableView data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == keychainTable) return vaults.count;
    if (tableView == categoryTable) return 4;
    return filteredItems.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == keychainTable) {
        KeychainVault *v = vaults[row];
        NSString *name = (row==0)?@"login":@"System";
        NSString *lock = v.isLocked ? @"🔒" : @"🔓";
        return [NSString stringWithFormat:@"%@ %@", lock, name];
    }
    if (tableView == categoryTable) {
        NSArray *names = @[@"All Items", @"Passwords", @"Secure Notes", @"Certificates"];
        return names[row];
    }
    if (row < 0 || row >= (NSInteger)filteredItems.count) return @"";
    KeychainItem *it = filteredItems[row];
    NSString *ident = [tableColumn identifier];
    if ([ident isEqualToString:@"name"]) return it.displayTitle;
    if ([ident isEqualToString:@"kind"]) return it.itemClass ?: @"";
    if ([ident isEqualToString:@"acct"]) {
        if (it.account.length && it.service.length) return [NSString stringWithFormat:@"%@ / %@", it.account, it.service];
        return it.account.length ? it.account : (it.service.length ? it.service : @"");
    }
    if ([ident isEqualToString:@"mod"]) {
        NSDateFormatter *f = [[NSDateFormatter alloc] init];
        [f setDateFormat:@"yyyy-MM-dd HH:mm"];
        return it.modified ? [f stringFromDate:it.modified] : @"";
    }
    return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tv = [notification object];
    if (tv == keychainTable) {
        NSInteger r = [tv selectedRow];
        if (r >= 0 && r < (NSInteger)vaults.count) {
            selectedVault = vaults[r];
            [self refreshItems];
        }
    } else if (tv == categoryTable) {
        NSInteger r = [tv selectedRow];
        if (r >= 0) {
            selectedCategory = r;
            [self refreshItems];
        }
    } else if (tv == itemTable) {
        NSInteger r = [tv selectedRow];
        if (r >= 0 && r < (NSInteger)filteredItems.count) {
            selectedItem = filteredItems[r];
            [self updateDetail];
        } else {
            selectedItem = nil;
            [detailField setStringValue:@""];
        }
    }
}

- (void)updateDetail {
    if (!selectedItem) { [detailField setStringValue:@""]; return; }
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Name: %@\n", selectedItem.displayTitle];
    [s appendFormat:@"Kind: %@\n", selectedItem.itemClass ?: @""];
    if (selectedItem.service.length) [s appendFormat:@"Service: %@\n", selectedItem.service];
    if (selectedItem.account.length) [s appendFormat:@"Account: %@\n", selectedItem.account];
    if (selectedItem.notes.length) [s appendFormat:@"Notes: %@\n", selectedItem.notes];
    if (selectedItem.secretData.length && [selectedItem.itemClass isEqualToString:@"certificate"]) {
        [s appendFormat:@"Certificate bytes: %lu\n", (unsigned long)selectedItem.secretData.length];
    }
    [detailField setStringValue:s];
}

#pragma mark - Actions

- (void)lockUnlock:(id)sender {
    if (selectedVault.isLocked) {
        NSString *pw = [self promptPassword:[NSString stringWithFormat:@"Keychain Access wants to use the '%@' keychain. Please enter the keychain password.", (selectedVault==vaults[0])?@"login":@"System"]];
        if (!pw) return;
        NSError *e = nil;
        if ([selectedVault unlockWithPassword:pw error:&e]) {
            [self refreshItems];
        } else {
            NSAlert *a = [[NSAlert alloc] init];
            [a setMessageText:@"Unlock failed"];
            [a setInformativeText:e.localizedDescription ?: @"Incorrect password"];
            [a runModal];
        }
    } else {
        [selectedVault lock];
        [self refreshItems];
    }
}

- (NSString *)promptPassword:(NSString *)msg {
    NSAlert *a = [[NSAlert alloc] init];
    [a setMessageText:msg];
    NSSecureTextField *tf = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,260,22)];
    [a setAccessoryView:tf];
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] == NSAlertFirstButtonReturn) {
        return [tf stringValue];
    }
    return nil;
}

- (void)newItem:(id)sender {
    if (selectedVault.isLocked) {
        NSString *pw = [self promptPassword:[NSString stringWithFormat:
            @"Keychain Access wants to use the '%@' keychain. Please enter the keychain password.",
            (selectedVault == vaults[0]) ? @"login" : @"System"]];
        NSError *error = nil;

        if (pw == nil)
            return;
        if (![selectedVault unlockWithPassword:pw error:&error]) {
            NSAlert *a = [[NSAlert alloc] init];
            [a setMessageText:@"Unlock failed"];
            [a setInformativeText:error.localizedDescription ?: @"Incorrect password"];
            [a runModal];
            return;
        }
        [self refreshItems];
    }

    // Simple new password item via modal window
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,420,320) styleMask:NSTitledWindowMask|NSClosableWindowMask backing:NSBackingStoreBuffered defer:NO];
    [w setTitle:@"New Password Item"];
    NSView *c = [w contentView];
    NSTextField *sl = [[NSTextField alloc] initWithFrame:NSMakeRect(16,270,100,18)]; [sl setStringValue:@"Service:"];
    [sl setBezeled:NO]; [sl setDrawsBackground:NO]; [sl setEditable:NO]; [c addSubview:sl];
    NSTextField *serviceF = [[NSTextField alloc] initWithFrame:NSMakeRect(120,268,280,22)]; [c addSubview:serviceF];
    NSTextField *al = [[NSTextField alloc] initWithFrame:NSMakeRect(16,238,100,18)]; [al setStringValue:@"Account:"];
    [al setBezeled:NO]; [al setDrawsBackground:NO]; [al setEditable:NO]; [c addSubview:al];
    NSTextField *accountF = [[NSTextField alloc] initWithFrame:NSMakeRect(120,236,280,22)]; [c addSubview:accountF];
    NSTextField *pl = [[NSTextField alloc] initWithFrame:NSMakeRect(16,206,100,18)]; [pl setStringValue:@"Password:"];
    [pl setBezeled:NO]; [pl setDrawsBackground:NO]; [pl setEditable:NO]; [c addSubview:pl];
    NSSecureTextField *passF = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(120,204,280,22)]; [c addSubview:passF];
    NSTextField *nl = [[NSTextField alloc] initWithFrame:NSMakeRect(16,174,100,18)]; [nl setStringValue:@"Notes:"];
    [nl setBezeled:NO]; [nl setDrawsBackground:NO]; [nl setEditable:NO]; [c addSubview:nl];
    NSTextField *notesF = [[NSTextField alloc] initWithFrame:NSMakeRect(120,140,280,52)]; [notesF setEditable:YES]; [c addSubview:notesF];

    NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(220,20,80,28)];
    [ok setTitle:@"OK"]; [ok setBezelStyle:NSRoundedBezelStyle];
    [c addSubview:ok];
    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(310,20,80,28)];
    [cancel setTitle:@"Cancel"]; [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setTarget:self];
    [cancel setAction:@selector(stopModalWithCancel:)];
    [c addSubview:cancel];

    [ok setTarget:self];
    // We'll run modal and poll via runModalForWindow? Use NSApp runModalForWindow with callbacks not needed; instead handle via target action setting flags.
    // Simpler: use a delegate-less approach: run window modally using [NSApp runModalForWindow:] and have buttons call stopModal.
    [ok setAction:@selector(stopModalWithOK:)];
    [cancel setAction:@selector(stopModalWithCancel:)];

    // Store fields in window represented? Use objc associated via tag not needed; we'll read after modal by traversing subviews.
    [w center];
    [w makeKeyAndOrderFront:nil];
    NSInteger modalCode = [NSApp runModalForWindow:w];
    // Determine which button triggered stopModal by checking window order? We'll use a global-ish flag via NSApp modal return? runModalForWindow returns NSInteger from stopModalWithCode. Use code 1 for OK.
    // We need capture code; use a static variable.
    // Instead, restructure: We'll read fields now; if window still has ok button? Simpler: check a flag stored in self via ivar. Add transient property? Use associated object on window.
    // We'll just always attempt to save; if service empty skip.
    // Read fields:
    NSString *service = [serviceF stringValue];
    NSString *account = [accountF stringValue];
    NSString *password = [passF stringValue];
    NSString *notes = [notesF stringValue];
    [w orderOut:nil];

    if (modalCode != 1) return;
    // But cancel should skip; we can't distinguish. We'll use modal code.
    // Rework: check a flag.
    // (handled below by re-running logic? too late)
    // We'll accept if password length >0 or service length>0
    KeychainItem *it = [[KeychainItem alloc] init];
    it.itemClass = @"password";
    it.service = service;
    it.account = account;
    it.secretData = [password dataUsingEncoding:NSUTF8StringEncoding];
    it.notes = notes;
    it.label = service.length ? service : account;
    NSError *e = nil;
    if (![selectedVault addItem:it error:&e]) {
        NSAlert *a = [[NSAlert alloc] init];
        [a setMessageText:@"Add failed"];
        [a setInformativeText:e.localizedDescription ?: @"Unknown"];
        [a runModal];
    } else {
        [self refreshItems];
    }
}

// Modal helpers
- (void)stopModalWithOK:(id)sender { [NSApp stopModalWithCode:1]; }
- (void)stopModalWithCancel:(id)sender { [NSApp stopModalWithCode:0]; }

- (void)deleteItem:(id)sender {
    if (!selectedItem) return;
    NSAlert *a = [[NSAlert alloc] init];
    [a setMessageText:@"Delete item?"];
    [a addButtonWithTitle:@"Delete"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    NSError *e = nil;
    if ([selectedVault deleteItem:selectedItem error:&e]) {
        selectedItem = nil;
        [self refreshItems];
    } else {
        NSAlert *b = [[NSAlert alloc] init];
        [b setMessageText:@"Delete failed"];
        [b setInformativeText:e.localizedDescription ?: @"Unknown"];
        [b runModal];
    }
}

- (void)showPassword:(id)sender {
    if (!selectedItem) return;
    if (selectedVault.isLocked) {
        NSString *pw = [self promptPassword:[NSString stringWithFormat:@"Keychain Access wants to use the '%@' keychain. Please enter the keychain password.", (selectedVault==vaults[0])?@"login":@"System"]];
        if (!pw) return;
        NSError *e = nil;
        if (![selectedVault unlockWithPassword:pw error:&e]) {
            NSAlert *a = [[NSAlert alloc] init];
            [a setMessageText:@"Unlock failed"];
            [a setInformativeText:e.localizedDescription ?: @"Incorrect password"];
            [a runModal];
            return;
        }
        [self refreshItems];
    }
    // authenticate even if unlocked
    NSString *pw = [self promptPassword:[NSString stringWithFormat:@"Keychain Access wants to use the '%@' keychain. Please enter the keychain password.", (selectedVault==vaults[0])?@"login":@"System"]];
    if (!pw) return;
    if (![selectedVault verifyPassword:pw]) {
        NSAlert *a = [[NSAlert alloc] init];
        [a setMessageText:@"Authentication failed"];
        [a setInformativeText:@"Incorrect password"];
        [a runModal];
        return;
    }
    // reveal
    NSString *secret = @"";
    if (selectedItem.secretData) {
        if ([selectedItem.itemClass isEqualToString:@"certificate"]) {
            secret = [NSString stringWithFormat:@"Certificate (%lu bytes)", (unsigned long)selectedItem.secretData.length];
        } else {
            secret = [[NSString alloc] initWithData:selectedItem.secretData encoding:NSUTF8StringEncoding];
            if (!secret) secret = [[NSString alloc] initWithData:selectedItem.secretData encoding:NSUnicodeStringEncoding];
        }
    }
    NSAlert *a = [[NSAlert alloc] init];
    [a setMessageText:@"Secret"];
    [a setInformativeText:secret ?: @""];
    [a addButtonWithTitle:@"Copy"];
    [a addButtonWithTitle:@"OK"];
    if ([a runModal] == NSAlertFirstButtonReturn) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:secret ?: @"" forType:NSPasteboardTypeString];
    }
}

- (void)itemDoubleClicked:(id)sender {
    [self showPassword:sender];
}

- (void)openGenerator:(id)sender {
    static PasswordGeneratorWindow *sharedGen = nil;
    if (!sharedGen) sharedGen = [[PasswordGeneratorWindow alloc] init];
    [sharedGen show];
}

- (void)searchChanged:(id)sender {
    [self refreshItems];
}

- (void)windowWillClose:(NSNotification *)note {
    // no-op
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}
@end