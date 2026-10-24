#import "CalcController.h"
#import <math.h>

@implementation CalcKeyView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
    if (self.keyDelegate && [self.keyDelegate respondsToSelector:@selector(handleKeyDown:)]) {
        [self.keyDelegate performSelector:@selector(handleKeyDown:) withObject:event];
    }
}
@end

@implementation CalcController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.engine = [CalcEngine new];
        self.bitButtons = [NSMutableArray array];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self buildMainMenu];
    [self buildWindow];
    [self rebuildUI];
    [self.window display];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildMainMenu {
    NSMenu *mainMenu = [NSMenu new];
    // App menu
    NSMenuItem *appItem = [NSMenuItem new];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Calculator"];
    [appMenu addItemWithTitle:@"About Calculator" action:nil keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Calculator" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setTitle:@"Calculator"];
    [appItem setSubmenu:appMenu];
    [appMenu setValue:@"NSAppleMenu" forKey:@"name"];
    [mainMenu addItem:appItem];

    // Edit menu
    NSMenuItem *editItem = [NSMenuItem new];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editItem setTitle:@"Edit"];
    [editItem setSubmenu:editMenu];
    [mainMenu addItem:editItem];

    // View menu
    NSMenuItem *viewItem = [NSMenuItem new];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *m1 = [viewMenu addItemWithTitle:@"Standard" action:@selector(switchStandard:) keyEquivalent:@"1"];
    [m1 setKeyEquivalentModifierMask:NSCommandKeyMask];
    NSMenuItem *m2 = [viewMenu addItemWithTitle:@"Scientific" action:@selector(switchScientific:) keyEquivalent:@"2"];
    [m2 setKeyEquivalentModifierMask:NSCommandKeyMask];
    NSMenuItem *m3 = [viewMenu addItemWithTitle:@"Programmer" action:@selector(switchProgrammer:) keyEquivalent:@"3"];
    [m3 setKeyEquivalentModifierMask:NSCommandKeyMask];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *mt = [viewMenu addItemWithTitle:@"Show Paper Tape" action:@selector(toggleTape:) keyEquivalent:@"t"];
    [mt setKeyEquivalentModifierMask:NSCommandKeyMask];
    [viewItem setTitle:@"View"];
    [viewItem setSubmenu:viewMenu];
    [mainMenu addItem:viewItem];

    [NSApp setMainMenu:mainMenu];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(200, 200, 300, 420);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [self.window setDelegate:self];
    [self.window setTitle:@"Calculator"];
    CalcKeyView *cv = [[CalcKeyView alloc] initWithFrame:NSMakeRect(0,0,300,420)];
    cv.keyDelegate = self;
    [self.window setContentView:cv];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)rebuildUI {
    CalcKeyView *content = (CalcKeyView *)[self.window contentView];
    // remove subviews
    for (NSView *v in [[content subviews] copy]) [v removeFromSuperview];
    self.bitButtons = [NSMutableArray array];

    NSInteger mode = self.engine.mode;
    NSSize newSize;
    if (mode == CalcModeStandard) newSize = NSMakeSize(300, 420);
    else if (mode == CalcModeScientific) newSize = NSMakeSize(520, 420);
    else newSize = NSMakeSize(520, 480);

    // resize window keeping top-left
    NSRect wf = self.window.frame;
    NSRect nf = NSMakeRect(wf.origin.x, wf.origin.y + (wf.size.height - newSize.height), newSize.width, newSize.height);
    [self.window setFrame:nf display:YES];
    [content setFrame:NSMakeRect(0,0,newSize.width,newSize.height)];

    CGFloat w = newSize.width;
    CGFloat h = newSize.height;

    // Mode segmented
    self.modeSeg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(10, h-32, w-20, 24)];
    [self.modeSeg setSegmentCount:3];
    [self.modeSeg setLabel:@"Standard" forSegment:0];
    [self.modeSeg setLabel:@"Scientific" forSegment:1];
    [self.modeSeg setLabel:@"Programmer" forSegment:2];
    [self.modeSeg setSelectedSegment:mode];
    [self.modeSeg setTarget:self];
    [self.modeSeg setAction:@selector(modeSegChanged:)];
    [content addSubview:self.modeSeg];

    // Display
    self.displayField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, h-78, w-20, 40)];
    [self.displayField setEditable:NO];
    [self.displayField setSelectable:NO];
    [self.displayField setBezeled:YES];
    [self.displayField setDrawsBackground:YES];
    [self.displayField setFont:[NSFont systemFontOfSize:24]];
    [self.displayField setAlignment:NSRightTextAlignment];
    [content addSubview:self.displayField];

    CGFloat y = h - 90;
    if (mode == CalcModeStandard) {
        [self buildStandard:content topY:y width:w];
    } else if (mode == CalcModeScientific) {
        [self buildScientific:content topY:y width:w];
    } else {
        [self buildProgrammer:content topY:y width:w height:h];
    }
    [self refreshDisplay];
}

- (NSButton *)makeButton:(NSString *)title frame:(NSRect)f {
    NSButton *b = [[NSButton alloc] initWithFrame:f];
    [b setTitle:title];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setTarget:self];
    [b setAction:@selector(buttonPressed:)];
    return b;
}

- (void)buildStandard:(NSView *)content topY:(CGFloat)topY width:(CGFloat)w {
    // 5 columns? Layout simple 4-wide
    NSArray *rows = @[
        @[@"AC",@"CE",@"⌫",@"÷"],
        @[@"7",@"8",@"9",@"×"],
        @[@"4",@"5",@"6",@"-"],
        @[@"1",@"2",@"3",@"+"],
        @[@"0",@".",@"±",@"="],
        @[@"%",@"(",@")",@"M+"],
    ];
    CGFloat bw = (w - 20) / 4.0;
    CGFloat bh = 44;
    CGFloat y = topY - 10;
    for (NSArray *row in rows) {
        CGFloat x = 10;
        for (NSString *t in row) {
            NSButton *b = [self makeButton:t frame:NSMakeRect(x, y, bw-4, bh-4)];
            [content addSubview:b];
            x += bw;
        }
        y -= bh;
    }
    // memory row extra
    NSArray *mem = @[@"MC",@"MR",@"M-"];
    CGFloat x = 10;
    for (NSString *t in mem) {
        NSButton *b = [self makeButton:t frame:NSMakeRect(x, y, bw-4, bh-4)];
        [content addSubview:b];
        x += bw;
    }
}

- (void)buildScientific:(NSView *)content topY:(CGFloat)topY width:(CGFloat)w {
    // Left scientific functions (2 cols) + standard keypad
    CGFloat bw = (w - 20) / 7.0;
    CGFloat bh = 36;
    NSArray *sci = @[
        @[@"sin",@"cos",@"tan",@"ln",@"log",@"x^y",@"("],
        @[@"asin",@"acos",@"atan",@"e^x",@"10^x",@"x!",@" )"],
        @[@"√",@"∛",@"1/x",@"x²",@"x³",@"π",@"e"],
        @[@"EE",@"±",@"%",@"(",@")",@"MC",@"MR"],
    ];
    CGFloat y = topY - 10;
    for (NSArray *row in sci) {
        CGFloat x = 10;
        for (NSString *t in row) {
            NSButton *b = [self makeButton:t frame:NSMakeRect(x, y, bw-4, bh-4)];
            [content addSubview:b];
            x += bw;
        }
        y -= bh;
    }
    // Standard keypad on right? Add a 4-col block
    NSArray *rows = @[
        @[@"AC",@"CE",@"⌫",@"÷"],
        @[@"7",@"8",@"9",@"×"],
        @[@"4",@"5",@"6",@"-"],
        @[@"1",@"2",@"3",@"+"],
        @[@"0",@".",@"M+",@"="],
    ];
    CGFloat x0 = 10 + 4*bw;
    CGFloat yy = y - 10;
    for (NSArray *row in rows) {
        CGFloat x = x0;
        for (NSString *t in row) {
            NSButton *b = [self makeButton:t frame:NSMakeRect(x, yy, bw-4, bh-4)];
            [content addSubview:b];
            x += bw;
        }
        yy -= bh;
    }
    // memory extra
    NSArray *mem = @[@"M-"];
    CGFloat x = x0;
    for (NSString *t in mem) {
        NSButton *b = [self makeButton:t frame:NSMakeRect(x, yy, bw-4, bh-4)];
        [content addSubview:b];
        x += bw;
    }
}

- (void)buildProgrammer:(NSView *)content topY:(CGFloat)topY width:(CGFloat)w height:(CGFloat)h {
    // Readouts
    CGFloat rw = w - 20;
    self.hexField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, topY-20, rw, 20)];
    [self.hexField setEditable:NO]; [content addSubview:self.hexField];
    self.decField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, topY-42, rw, 20)];
    [self.decField setEditable:NO]; [content addSubview:self.decField];
    self.octField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, topY-64, rw, 20)];
    [self.octField setEditable:NO]; [content addSubview:self.octField];
    self.binField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, topY-86, rw, 20)];
    [self.binField setEditable:NO]; [content addSubview:self.binField];

    // Base selector
    self.basePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(10, topY-112, 120, 24) pullsDown:NO];
    [self.basePopup addItemWithTitle:@"Hex"];
    [self.basePopup addItemWithTitle:@"Dec"];
    [self.basePopup addItemWithTitle:@"Oct"];
    [self.basePopup addItemWithTitle:@"Bin"];
    [self.basePopup selectItemWithTitle:@"Hex"];
    self.engine.inputBase = 16; /* the popup defaults to Hex; the engine must agree */
    [self.basePopup setTarget:self];
    [self.basePopup setAction:@selector(baseChanged:)];
    [content addSubview:self.basePopup];

    // Word size selector via segmented
    NSSegmentedControl *wordSeg = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(140, topY-112, 200, 24)];
    [wordSeg setSegmentCount:4];
    [wordSeg setLabel:@"QWORD" forSegment:0];
    [wordSeg setLabel:@"DWORD" forSegment:1];
    [wordSeg setLabel:@"WORD" forSegment:2];
    [wordSeg setLabel:@"BYTE" forSegment:3];
    [wordSeg setSelectedSegment:0];
    [wordSeg setTarget:self];
    [wordSeg setAction:@selector(wordChanged:)];
    [content addSubview:wordSeg];

    CGFloat y = topY - 140;
    // Bit grid: 8 columns x 8 rows (64 bits)
    CGFloat bw = (w - 20) / 8.0;
    CGFloat bh = 22;
    self.bitButtons = [NSMutableArray array];
    for (int row = 0; row < 8; row++) {
        for (int col = 0; col < 8; col++) {
            int bit = (7 - row) * 8 + (7 - col);
            NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(10 + col*bw, y - row*bh, bw-2, bh-2)];
            [b setTitle:@"0"];
            [b setBezelStyle:NSRoundedBezelStyle];
            [b setTag:bit];
            [b setTarget:self];
            [b setAction:@selector(bitClicked:)];
            [content addSubview:b];
            [self.bitButtons addObject:b];
        }
    }

    // Keypad
    CGFloat ky = y - 8*bh - 10;
    NSArray *rows = @[
        @[@"AC",@"CE",@"⌫",@"÷"],
        @[@"D",@"E",@"F",@"×"],
        @[@"A",@"B",@"C",@"-"],
        @[@"7",@"8",@"9",@"+"],
        @[@"4",@"5",@"6",@"&"],
        @[@"1",@"2",@"3",@"|"],
        @[@"0",@".",@"^",@"="],
    ];
    CGFloat kbw = (w - 20) / 4.0;
    CGFloat kbh = 34;
    for (NSArray *row in rows) {
        CGFloat x = 10;
        for (NSString *t in row) {
            NSButton *b = [self makeButton:t frame:NSMakeRect(x, ky, kbw-4, kbh-4)];
            [content addSubview:b];
            x += kbw;
        }
        ky -= kbh;
    }
    // extra ops row
    NSArray *ops = @[@"~",@"<<",@">>",@"%",@"rol",@"ror",@"nor",@"M+"];
    CGFloat x = 10;
    for (NSString *t in ops) {
        NSButton *b = [self makeButton:t frame:NSMakeRect(x, ky, kbw-4, kbh-4)];
        [content addSubview:b];
        x += kbw;
        if (x > w - 20) { x = 10; ky -= kbh; }
    }
    // memory row
    NSArray *mem = @[@"MC",@"MR",@"M-"];
    x = 10;
    for (NSString *t in mem) {
        NSButton *b = [self makeButton:t frame:NSMakeRect(x, ky, kbw-4, kbh-4)];
        [content addSubview:b];
        x += kbw;
    }
}

- (void)modeSegChanged:(id)sender {
    NSInteger sel = [self.modeSeg selectedSegment];
    CalcMode m = (CalcMode)sel;
    [self.engine clear];
    self.engine.mode = m;
    [self rebuildUI];
}

- (void)switchStandard:(id)sender { self.engine.mode = CalcModeStandard; [self.engine clear]; [self rebuildUI]; }
- (void)switchScientific:(id)sender { self.engine.mode = CalcModeScientific; [self.engine clear]; [self rebuildUI]; }
- (void)switchProgrammer:(id)sender { self.engine.mode = CalcModeProgrammer; [self.engine clear]; [self rebuildUI]; }

- (void)baseChanged:(id)sender {
    NSString *t = [self.basePopup titleOfSelectedItem];
    if ([t isEqualToString:@"Hex"]) self.engine.inputBase = 16;
    else if ([t isEqualToString:@"Dec"]) self.engine.inputBase = 10;
    else if ([t isEqualToString:@"Oct"]) self.engine.inputBase = 8;
    else if ([t isEqualToString:@"Bin"]) self.engine.inputBase = 2;
}

- (void)wordChanged:(id)sender {
    // sender is segmented control
    NSSegmentedControl *seg = (NSSegmentedControl *)sender;
    NSInteger sel = [seg selectedSegment];
    self.engine.wordSize = (WordSize)sel;
    self.engine.progValue &= [self.engine wordMask];
    [self refreshDisplay];
}

- (void)bitClicked:(id)sender {
    NSButton *b = (NSButton *)sender;
    int bit = (int)[b tag];
    unsigned long long mask = 1ULL << bit;
    BOOL cur = (self.engine.progValue & mask) != 0;
    [self.engine setBit:bit value:!cur];
    [self refreshDisplay];
}

- (void)buttonPressed:(id)sender {
    NSString *t = [sender title];
    CalcEngine *e = self.engine;

    if ([t isEqualToString:@"AC"] || [t isEqualToString:@"C"]) {
        [e clear];
    } else if ([t isEqualToString:@"CE"]) {
        [e clearEntry];
    } else if ([t isEqualToString:@"⌫"]) {
        [e deleteLastDigit];
    } else if ([t isEqualToString:@"±"]) {
        [e toggleSign];
    } else if ([t isEqualToString:@"%"] && e.mode != CalcModeProgrammer) {
        [e percent];
    } else if ([t isEqualToString:@"="]) {
        if (e.mode == CalcModeProgrammer) [e inputProgrammerEquals]; else [e inputEquals];
        if (e.mode != CalcModeProgrammer) {
            NSString *line = [e lastTapeLine];
            if (line) [self appendTapeLine:line];
        }
    } else if ([t isEqualToString:@"."]) {
        [e inputDecimalPoint];
    } else if ([t isEqualToString:@"("]) {
        [e inputOpenParen];
    } else if ([t isEqualToString:@")"]) {
        [e inputCloseParen];
    } else if ([t isEqualToString:@"MC"]) {
        [e memoryClear];
    } else if ([t isEqualToString:@"MR"]) {
        [e memoryRecall];
    } else if ([t isEqualToString:@"M+"]) {
        [e memoryAdd];
    } else if ([t isEqualToString:@"M-"]) {
        [e memorySubtract];
    } else if ([t isEqualToString:@"π"]) {
        [e inputConstant:@"pi"];
    } else if ([t isEqualToString:@"e"]) {
        [e inputConstant:@"e"];
    } else if ([t isEqualToString:@"EE"]) {
        [e inputEE];
    } else if ([t isEqualToString:@"sin"]||[t isEqualToString:@"cos"]||[t isEqualToString:@"tan"]||
               [t isEqualToString:@"asin"]||[t isEqualToString:@"acos"]||[t isEqualToString:@"atan"]||
               [t isEqualToString:@"ln"]||[t isEqualToString:@"log"]) {
        [e inputFunction:t];
    } else if ([t isEqualToString:@"e^x"]) {
        [e inputFunction:@"exp"];
    } else if ([t isEqualToString:@"10^x"]) {
        [e inputFunction:@"pow10"];
    } else if ([t isEqualToString:@"√"]) {
        [e inputFunction:@"sqrt"];
    } else if ([t isEqualToString:@"∛"]) {
        [e inputFunction:@"cbrt"];
    } else if ([t isEqualToString:@"1/x"]) {
        [e inputFunction:@"inv"];
    } else if ([t isEqualToString:@"x!"]) {
        [e inputFunction:@"fact"];
    } else if ([t isEqualToString:@"x²"]) {
        [e inputFunction:@"sqr"];
    } else if ([t isEqualToString:@"x³"]) {
        [e inputFunction:@"cube"];
    } else if ([t isEqualToString:@"x^y"]) {
        [e inputOperator:@"^"];
    } else if ([t isEqualToString:@"÷"]) {
        if (e.mode == CalcModeProgrammer) [e inputProgrammerOperator:@"/"]; else [e inputOperator:@"/"];
    } else if ([t isEqualToString:@"×"]) {
        if (e.mode == CalcModeProgrammer) [e inputProgrammerOperator:@"*"]; else [e inputOperator:@"*"];
    } else if ([t isEqualToString:@"+"]) {
        if (e.mode == CalcModeProgrammer) [e inputProgrammerOperator:@"+"]; else [e inputOperator:@"+"];
    } else if ([t isEqualToString:@"-"]) {
        if (e.mode == CalcModeProgrammer) [e inputProgrammerOperator:@"-"]; else [e inputOperator:@"-"];
    } else if ([t isEqualToString:@"&"]) {
        [e inputProgrammerOperator:@"&"];
    } else if ([t isEqualToString:@"|"]) {
        [e inputProgrammerOperator:@"|"];
    } else if ([t isEqualToString:@"^"]) {
        [e inputProgrammerOperator:@"^"];
    } else if ([t isEqualToString:@"~"]) {
        [e inputProgrammerOperator:@"not"];
    } else if ([t isEqualToString:@"<<"]) {
        [e inputProgrammerOperator:@"<<"];
    } else if ([t isEqualToString:@">>"]) {
        [e inputProgrammerOperator:@">>"];
    } else if ([t isEqualToString:@"rol"]) {
        [e inputProgrammerOperator:@"rol"];
    } else if ([t isEqualToString:@"ror"]) {
        [e inputProgrammerOperator:@"ror"];
    } else if ([t isEqualToString:@"nor"]) {
        [e inputProgrammerOperator:@"nor"];
    } else if ([t isEqualToString:@"%"]) {
        if (e.mode == CalcModeProgrammer) [e inputProgrammerOperator:@"%"]; else [e percent];
    } else if (t.length == 1 && [t characterAtIndex:0] >= '0' && [t characterAtIndex:0] <= '9') {
        if (e.mode == CalcModeProgrammer) [e inputProgrammerDigit:[t intValue]];
        else [e inputDigit:[t intValue]];
    } else if (t.length == 1 && (([t characterAtIndex:0] >= 'A' && [t characterAtIndex:0] <= 'F'))) {
        int d = [t characterAtIndex:0] - 'A' + 10;
        if (e.mode == CalcModeProgrammer) [e inputProgrammerDigit:d];
        else [e inputDigit:d];
    } else if ([t isEqualToString:@"."]) {
        [e inputDecimalPoint];
    }
    [self refreshDisplay];
}

- (void)refreshDisplay {
    if (self.engine.mode == CalcModeProgrammer) {
        self.displayField.stringValue = [self.engine hexReadout];
        self.hexField.stringValue = [NSString stringWithFormat:@"HEX: %@", [self.engine hexReadout]];
        self.decField.stringValue = [NSString stringWithFormat:@"DEC: %@", [self.engine decReadout]];
        self.octField.stringValue = [NSString stringWithFormat:@"OCT: %@", [self.engine octReadout]];
        self.binField.stringValue = [NSString stringWithFormat:@"BIN: %@", [self.engine binReadout]];
        // update bit buttons
        for (NSButton *b in self.bitButtons) {
            int bit = (int)[b tag];
            BOOL on = (self.engine.progValue & (1ULL << bit)) != 0;
            [b setTitle:on ? @"1" : @"0"];
        }
    } else {
        self.displayField.stringValue = self.engine.display;
    }
}

- (void)handleKeyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    unichar c = [chars length] ? [chars characterAtIndex:0] : 0;
    CalcEngine *e = self.engine;
    BOOL prog = (e.mode == CalcModeProgrammer);
    if (c >= '0' && c <= '9') {
        if (prog) [e inputProgrammerDigit:c - '0'];
        else [e inputDigit:c - '0'];
    } else if (prog && ((c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
        int d = (c >= 'a') ? c - 'a' + 10 : c - 'A' + 10;
        [e inputProgrammerDigit:d];
    } else if (c == '.') {
        [e inputDecimalPoint];
    } else if (c == '+') {
        if (prog) [e inputProgrammerOperator:@"+"]; else [e inputOperator:@"+"];
    } else if (c == '-') {
        if (prog) [e inputProgrammerOperator:@"-"]; else [e inputOperator:@"-"];
    } else if (c == '*') {
        if (prog) [e inputProgrammerOperator:@"*"]; else [e inputOperator:@"*"];
    } else if (c == '/') {
        if (prog) [e inputProgrammerOperator:@"/"]; else [e inputOperator:@"/"];
    } else if (c == '%') {
        if (prog) [e inputProgrammerOperator:@"%"]; else [e percent];
    } else if (c == '(') {
        [e inputOpenParen];
    } else if (c == ')') {
        [e inputCloseParen];
    } else if (c == '\r' || c == '\n' || c == '=') {
        if (prog) [e inputProgrammerEquals]; else [e inputEquals];
        if (!prog) {
            NSString *line = [e lastTapeLine];
            if (line) [self appendTapeLine:line];
        }
    } else if (c == 27) {
        [e clear];
    } else if (c == 'c' || c == 'C') {
        [e clear];
    } else if (c == 127 || c == 8) {
        [e deleteLastDigit];
    }
    [self refreshDisplay];
}

- (void)toggleTape:(id)sender {
    if (!self.tapeWindow) {
        NSRect f = NSMakeRect(220, 220, 360, 260);
        self.tapeWindow = [[NSWindow alloc] initWithContentRect:f styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask) backing:NSBackingStoreBuffered defer:NO];
        [self.tapeWindow setTitle:@"Paper Tape"];
        NSView *cv = [[NSView alloc] initWithFrame:NSMakeRect(0,0,360,260)];
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, 340, 200)];
        self.tapeView = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,340,200)];
        [sv setDocumentView:self.tapeView];
        [cv addSubview:sv];
        NSButton *clearBtn = [[NSButton alloc] initWithFrame:NSMakeRect(10, 10, 100, 30)];
        [clearBtn setTitle:@"Clear Tape"];
        [clearBtn setTarget:self];
        [clearBtn setAction:@selector(clearTape:)];
        [cv addSubview:clearBtn];
        NSButton *saveBtn = [[NSButton alloc] initWithFrame:NSMakeRect(120, 10, 100, 30)];
        [saveBtn setTitle:@"Save Tape…"];
        [saveBtn setTarget:self];
        [saveBtn setAction:@selector(saveTape:)];
        [cv addSubview:saveBtn];
        [self.tapeWindow setContentView:cv];
    }
    if ([self.tapeWindow isVisible]) [self.tapeWindow orderOut:nil];
    else [self.tapeWindow makeKeyAndOrderFront:nil];
}

- (void)clearTape:(id)sender {
    [self.tapeView setString:@""];
}

- (void)saveTape:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        NSString *path = [[panel URL] path];
        NSString *text = [self.tapeView string];
        [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

- (void)appendTapeLine:(NSString *)line {
    if (!self.tapeView) return;
    NSString *cur = [self.tapeView string];
    NSString *new = [cur length] ? [cur stringByAppendingFormat:@"\n%@", line] : line;
    [self.tapeView setString:new];
}

// Clipboard
- (void)copy:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
    NSString *val;
    if (self.engine.mode == CalcModeProgrammer) val = [self.engine hexReadout];
    else val = self.engine.display;
    [pb setString:val forType:NSPasteboardTypeString];
}

- (void)paste:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *s = [pb stringForType:NSPasteboardTypeString];
    if (!s) return;
    CalcEngine *e = self.engine;
    if (e.mode == CalcModeProgrammer) {
        unsigned long long v;
        if ([s hasPrefix:@"0x"] || [s hasPrefix:@"0X"]) v = strtoull([s UTF8String]+2, NULL, 16);
        else v = strtoull([s UTF8String], NULL, e.inputBase);
        e.progValue = v & [e wordMask];
        e.progEntering = NO;
        [e.progEntry setString:@""];
    } else {
        [e inputPastedString:s];
    }
    [self refreshDisplay];
}

- (void)selectAll:(id)sender {
    // no-op for calculator
}

- (void)cut:(id)sender {
    [self copy:sender];
    [self.engine clear];
    [self refreshDisplay];
}

- (void)windowWillClose:(NSNotification *)n {
    [NSApp terminate:nil];
}

@end