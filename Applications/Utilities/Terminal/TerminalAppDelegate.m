#import "TerminalAppDelegate.h"

@implementation TerminalAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _wc = [[TerminalWindowController alloc] init];
    [_wc showWindow:nil];
    [self buildMenu];
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    // App
    NSMenuItem *appItem = [mainMenu addItemWithTitle:@"Terminal" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Terminal"];
    [appMenu addItemWithTitle:@"Quit Terminal" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    // File
    NSMenuItem *fileItem = [mainMenu addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
    [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeTab:) keyEquivalent:@"w"];
    [fileItem setSubmenu:fileMenu];
    // Edit
    NSMenuItem *editItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItemWithTitle:@"Clear" action:@selector(clearScreen:) keyEquivalent:@"k"];
    [editItem setSubmenu:editMenu];
    // View
    NSMenuItem *viewItem = [mainMenu addItemWithTitle:@"View" action:NULL keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *zi = [viewMenu addItemWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"="];
    [zi setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    [viewMenu addItemWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    [viewMenu addItemWithTitle:@"Actual Size" action:@selector(zoomReset:) keyEquivalent:@"0"];
    NSMenuItem *themes = [viewMenu addItemWithTitle:@"Theme" action:NULL keyEquivalent:@""];
    NSMenu *themeMenu = [[NSMenu alloc] initWithTitle:@"Theme"];
    NSArray *names = @[@"ravynOS Dark",@"Classic Black",@"Solarized Dark",@"Light Paper"];
    for (int i = 0; i < 4; i++) {
        NSMenuItem *it = [themeMenu addItemWithTitle:names[i] action:@selector(setThemeAction:) keyEquivalent:@""];
        [it setTag:i];
        [it setTarget:_wc];
    }
    [themes setSubmenu:themeMenu];
    [viewItem setSubmenu:viewMenu];
    // Window
    NSMenuItem *winItem = [mainMenu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [winMenu addItemWithTitle:@"Next Tab" action:@selector(nextTab:) keyEquivalent:@"]"];
    NSMenuItem *prev = [winMenu addItemWithTitle:@"Previous Tab" action:@selector(previousTab:) keyEquivalent:@"["];
    [prev setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    // fix next tab modifier
    NSMenuItem *nextItem = [[winMenu itemArray] objectAtIndex:0];
    [nextItem setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    [winMenu addItemWithTitle:@"Split Vertical" action:@selector(splitVertical:) keyEquivalent:@"d"];
    NSMenuItem *hs = [winMenu addItemWithTitle:@"Split Horizontal" action:@selector(splitHorizontal:) keyEquivalent:@"D"];
    [hs setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    [winItem setSubmenu:winMenu];

    // set targets for window-level actions to _wc
    for (NSMenuItem *mi in [fileMenu itemArray]) [mi setTarget:_wc];
    for (NSMenuItem *mi in [winMenu itemArray]) [mi setTarget:_wc];
    // view zoom items target _wc
    for (NSMenuItem *mi in [viewMenu itemArray]) {
        if ([mi action] == @selector(zoomIn:) || [mi action] == @selector(zoomOut:) || [mi action] == @selector(zoomReset:)) [mi setTarget:_wc];
    }

    [[NSApplication sharedApplication] setMainMenu:mainMenu];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

@end
