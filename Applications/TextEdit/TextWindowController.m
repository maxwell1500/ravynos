#import "TextWindowController.h"
#import "MarkdownHighlighter.h"

@implementation TextWindowController

@synthesize textDocument = _textDocument;
@synthesize scrollView = _scrollView;
@synthesize textView = _textView;
@synthesize fontFamilyPopup = _fontFamilyPopup;
@synthesize fontSizePopup = _fontSizePopup;
@synthesize alignmentPopup = _alignmentPopup;
@synthesize encodingPopup = _encodingPopup;
@synthesize colorWell = _colorWell;
@synthesize statusField = _statusField;
@synthesize markdownMode = _markdownMode;
@synthesize previewMode = _previewMode;
@synthesize applyingHighlight = _applyingHighlight;

- (id)initWithDocument:(TextDocument *)document {
    NSRect frame = NSMakeRect(100, 100, 720, 520);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask|NSResizableWindowMask) backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:w];
    if (self) {
        _textDocument = document;
        _markdownMode = NO;
        NSString *ext = [[[document fileURL] path] pathExtension];
        if ([ext caseInsensitiveCompare:@"md"] == NSOrderedSame) _markdownMode = YES;
        _previewMode = NO;
        _applyingHighlight = NO;
        [w setDelegate:self];
        [w setTitle:[document displayName]];
        [self buildUI:w];
        // load text
        [self loadDocumentIntoView];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidChange:) name:NSTextDidChangeNotification object:_textView];
    }
    return self;
}

- (void)buildUI:(NSWindow *)w {
    NSView *content = [w contentView];
    CGFloat width = NSWidth([content bounds]);
    CGFloat height = NSHeight([content bounds]);
    CGFloat toolbarH = 34;
    CGFloat statusH = 22;

    // Toolbar container
    NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, height-toolbarH, width, toolbarH)];
    toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:toolbar];

    CGFloat x = 8;
    // Font family popup
    _fontFamilyPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 5, 150, 24) pullsDown:NO];
    [_fontFamilyPopup addItemsWithTitles:[[NSFontManager sharedFontManager] availableFontFamilies]];
    [_fontFamilyPopup setTarget:self];
    [_fontFamilyPopup setAction:@selector(fontFamilyChanged:)];
    [toolbar addSubview:_fontFamilyPopup];
    x += 158;

    // Font size popup
    _fontSizePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 5, 60, 24) pullsDown:NO];
    [_fontSizePopup addItemsWithTitles:@[@"8",@"9",@"10",@"11",@"12",@"14",@"16",@"18",@"24",@"36"]];
    [_fontSizePopup selectItemWithTitle:@"12"];
    [_fontSizePopup setTarget:self];
    [_fontSizePopup setAction:@selector(fontSizeChanged:)];
    [toolbar addSubview:_fontSizePopup];
    x += 68;

    // Bold
    NSButton *bold = [[NSButton alloc] initWithFrame:NSMakeRect(x, 5, 30, 24)];
    [bold setTitle:@"B"];
    [bold setTarget:self]; [bold setAction:@selector(toggleBold:)];
    [toolbar addSubview:bold];
    x += 34;
    NSButton *italic = [[NSButton alloc] initWithFrame:NSMakeRect(x, 5, 30, 24)];
    [italic setTitle:@"I"];
    [italic setTarget:self]; [italic setAction:@selector(toggleItalic:)];
    [toolbar addSubview:italic];
    x += 34;
    NSButton *underline = [[NSButton alloc] initWithFrame:NSMakeRect(x, 5, 30, 24)];
    [underline setTitle:@"U"];
    [underline setTarget:self]; [underline setAction:@selector(toggleUnderline:)];
    [toolbar addSubview:underline];
    x += 38;

    /* A color well opens the (nib-less) color panel the moment it is created,
     * which crashed TextEdit at launch in this image; a button that asks for
     * the panel on click gives the same command without the eager window. */
    NSButton *colorBtn = [[NSButton alloc] initWithFrame:NSMakeRect(x, 5, 40, 24)];
    [colorBtn setTitle:@"Color"];
    [colorBtn setTarget:self];
    [colorBtn setAction:@selector(showColorPanel:)];
    [toolbar addSubview:colorBtn];
    x += 48;

    // Alignment popup
    _alignmentPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 5, 90, 24) pullsDown:NO];
    [_alignmentPopup addItemsWithTitles:@[@"Left",@"Center",@"Right"]];
    [_alignmentPopup setTarget:self];
    [_alignmentPopup setAction:@selector(alignmentChanged:)];
    [toolbar addSubview:_alignmentPopup];
    x += 98;

    // Plain/Rich toggle
    NSButton *modeBtn = [[NSButton alloc] initWithFrame:NSMakeRect(x, 5, 90, 24)];
    [modeBtn setTitle:@"Rich Text"];
    [modeBtn setTarget:self]; [modeBtn setAction:@selector(toggleRichMode:)];
    [toolbar addSubview:modeBtn];
    x += 98;

    // Preview toggle (markdown)
    NSButton *previewBtn = [[NSButton alloc] initWithFrame:NSMakeRect(x, 5, 80, 24)];
    [previewBtn setTitle:@"Preview"];
    [previewBtn setTarget:self]; [previewBtn setAction:@selector(togglePreview:)];
    [toolbar addSubview:previewBtn];
    x += 88;

    // Encoding popup
    _encodingPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 5, 90, 24) pullsDown:NO];
    [_encodingPopup addItemsWithTitles:@[@"UTF-8",@"ASCII",@"ISO Latin-1"]];
    [_encodingPopup setTarget:self];
    [_encodingPopup setAction:@selector(encodingChanged:)];
    [toolbar addSubview:_encodingPopup];

    // Scroll view + text view
    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, statusH, width, height-toolbarH-statusH)];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,width,height-toolbarH-statusH)];
    _textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    /* Undo registration goes through NSUndoManager's forwarding proxy, which
     * this runtime cannot dispatch; enabling it crashed the first setString:
     * in loadDocumentIntoView. */
    _textView.allowsUndo = NO;
    _textView.richText = YES;
    _textView.usesFontPanel = NO;
    [_scrollView setDocumentView:_textView];
    [content addSubview:_scrollView];

    // Status bar
    _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, width, statusH)];
    _statusField.editable = NO;
    _statusField.bordered = NO;
    _statusField.autoresizingMask = NSViewWidthSizable;
    [content addSubview:_statusField];

    // Menu
    [self buildMenu];
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    // App menu
    NSMenuItem *appItem = [mainMenu addItemWithTitle:@"TextEdit" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"TextEdit"];
    [appMenu addItemWithTitle:@"Quit TextEdit" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    // File menu
    NSMenuItem *fileItem = [mainMenu addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New" action:@selector(newDocument:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Save As…" action:@selector(saveDocumentAs:) keyEquivalent:@"S"];
    NSMenuItem *saveAsItem = [[fileMenu itemArray] lastObject];
    [saveAsItem setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [fileMenu addItemWithTitle:@"Revert" action:@selector(revertDocumentToSaved:) keyEquivalent:@""];
    [fileItem setSubmenu:fileMenu];
    // Edit menu
    NSMenuItem *editItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    NSMenuItem *redoItem = [[editMenu itemArray] lastObject];
    [redoItem setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@""];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editItem setSubmenu:editMenu];
    // Format menu
    NSMenuItem *fmtItem = [mainMenu addItemWithTitle:@"Format" action:NULL keyEquivalent:@""];
    NSMenu *fmtMenu = [[NSMenu alloc] initWithTitle:@"Format"];
    [fmtMenu addItemWithTitle:@"Bold" action:@selector(toggleBold:) keyEquivalent:@"b"];
    [fmtMenu addItemWithTitle:@"Italic" action:@selector(toggleItalic:) keyEquivalent:@"i"];
    [fmtMenu addItemWithTitle:@"Underline" action:@selector(toggleUnderline:) keyEquivalent:@"u"];
    NSMenuItem *plainRich = [fmtMenu addItemWithTitle:@"Plain/Rich Text" action:@selector(toggleRichMode:) keyEquivalent:@"T"];
    [plainRich setKeyEquivalentModifierMask:(NSCommandKeyMask|NSShiftKeyMask)];
    [fmtItem setSubmenu:fmtMenu];
    // View menu
    NSMenuItem *viewItem = [mainMenu addItemWithTitle:@"View" action:NULL keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *previewItem = [viewMenu addItemWithTitle:@"Preview Markdown" action:@selector(togglePreview:) keyEquivalent:@""];
    [viewItem setSubmenu:viewMenu];
    [[NSApplication sharedApplication] setMainMenu:mainMenu];
}

- (void)loadDocumentIntoView {
    /* Install the document text through the storage, not -setString:.
     * -setString: runs NSTextView's replacement path (undo registration,
     * temporary attributes, selection sync), which faults in this AppKit. */
    if (_textDocument.richTextMode) {
        [_textView.textStorage setAttributedString:_textDocument.textStorage];
    } else {
        NSFont *plainFont = [NSFont systemFontOfSize:12];
        NSDictionary *attrs = [NSDictionary dictionaryWithObject:
            plainFont ?: [NSFont fontWithName:@"Inter-Regular" size:12]
            forKey:NSFontAttributeName];
        NSAttributedString *as = [[NSAttributedString alloc] initWithString:
                [_textDocument.textStorage string] ?: @"" attributes:attrs];
        [_textView.textStorage setAttributedString:as];
    }
    if (_markdownMode) {
        [self applyMarkdownHighlighting];
    }
    [self updateStatus];
}

/* Store the live text view back into the document.  Everything the document
 * saves comes from _textDocument.textStorage, which until now only ever held
 * what readFromData: put there: Cmd-S wrote an empty file for a new document
 * and silently dropped every edit to an opened one. */
- (void)syncDocumentStorage {
    if (_textDocument.textStorage == nil)
        _textDocument.textStorage = [[NSMutableAttributedString alloc] init];
    if (_textView.textStorage != nil)
        [_textDocument.textStorage setAttributedString:_textView.textStorage];
    else
        [_textDocument.textStorage setAttributedString:
            [[NSAttributedString alloc] initWithString:[_textView string] ?: @""]];
}

- (void)textDidChange:(NSNotification *)note {
    if (_applyingHighlight) return;
    [self syncDocumentStorage];
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
    if (_markdownMode && !_previewMode) {
        [self applyMarkdownHighlighting];
    }
    [self updateStatus];
}

- (void)applyMarkdownHighlighting {
    _applyingHighlight = YES;
    NSRange sel = _textView.selectedRange;
    NSString *str = _textView.string;
    NSFont *base = [NSFont systemFontOfSize:12];
    NSAttributedString *attr = [MarkdownHighlighter highlightedStringForMarkdown:str baseFont:base];
    [_textView.textStorage setAttributedString:attr];
    [_textView setSelectedRange:sel];
    _applyingHighlight = NO;
}

- (void)updateStatus {
    NSString *str = _textView.string ?: @"";
    NSUInteger chars = [str length];
    NSUInteger words = 0, lines = 0;
    BOOL inWord = NO;

    /* Counted by hand: NSScanner faults on this string in this Foundation. */
    for(NSUInteger i = 0; i < chars; i++) {
        unichar c = [str characterAtIndex:i];
        BOOL space = (c == ' ' || c == '\t' || c == '\n' || c == '\r');

        if(space) {
            inWord = NO;
        } else if(!inWord) {
            inWord = YES;
            words++;
        }
        if(c == '\n')
            lines++;
    }
    if(chars > 0 && [str characterAtIndex:chars - 1] != '\n')
        lines++;
    NSString *encLabel = @"UTF-8";
    if (_textDocument.encoding == NSASCIIStringEncoding) encLabel = @"ASCII";
    else if (_textDocument.encoding == NSISOLatin1StringEncoding) encLabel = @"ISO Latin-1";
    [_statusField setStringValue:[NSString stringWithFormat:@"Lines: %lu  Words: %lu  Characters: %lu    Encoding: %@", (unsigned long)lines, (unsigned long)words, (unsigned long)chars, encLabel]];
}

// Toolbar actions
- (void)fontFamilyChanged:(id)sender {
    NSString *family = [_fontFamilyPopup titleOfSelectedItem];
    CGFloat size = [[_fontSizePopup titleOfSelectedItem] floatValue];
    if (size <= 0) size = 12;
    /* The popup lists family names; fontWithName: wants a PostScript name. */
    NSFont *font = [[NSFontManager sharedFontManager] fontWithFamily:family
                       traits:0 weight:5 size:size];
    if (!font) font = [NSFont fontWithName:family size:size];
    if (!font) font = [NSFont systemFontOfSize:size];
    NSRange sel = _textView.selectedRange;
    if (sel.length > 0) {
        [_textView.textStorage addAttribute:NSFontAttributeName value:font range:sel];
    } else {
        NSMutableDictionary *ta = [[_textView typingAttributes] mutableCopy];
        if (ta == nil) ta = [NSMutableDictionary dictionary];
        ta[NSFontAttributeName] = font;
        _textView.typingAttributes = ta;
    }
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
    [self updateStatus];
}

- (void)fontSizeChanged:(id)sender {
    CGFloat size = [[_fontSizePopup titleOfSelectedItem] floatValue];
    if (size <= 0) size = 12;
    NSRange sel = _textView.selectedRange;
    if (sel.length > 0) {
        // apply size keeping family
        NSFont *f = [_textView.textStorage attribute:NSFontAttributeName atIndex:sel.location effectiveRange:NULL];
        if (!f) f = [NSFont systemFontOfSize:size];
        NSFont *nf = [NSFont fontWithName:[f fontName] size:size];
        if (!nf) nf = [NSFont systemFontOfSize:size];
        [_textView.textStorage addAttribute:NSFontAttributeName value:nf range:sel];
    } else {
        NSFont *f = _textView.typingAttributes[NSFontAttributeName];
        if (!f) f = [NSFont systemFontOfSize:size];
        NSFont *nf = [NSFont fontWithName:[f fontName] size:size];
        if (!nf) nf = [NSFont systemFontOfSize:size];
        _textView.typingAttributes = @{NSFontAttributeName: nf};
    }
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)toggleBold:(id)sender {
    NSRange sel = _textView.selectedRange;
    NSFontManager *fm = [NSFontManager sharedFontManager];
    if (sel.length == 0) {
        NSFont *f = [_textView typingAttributes][NSFontAttributeName];
        if (!f) f = [NSFont systemFontOfSize:12];
        NSFont *nf = ([fm traitsOfFont:f] & NSBoldFontMask)
            ? [fm convertFont:f toNotHaveTrait:NSBoldFontMask]
            : [fm convertFont:f toHaveTrait:NSBoldFontMask];
        NSMutableDictionary *ta = [[_textView typingAttributes] mutableCopy];
        if (ta == nil) ta = [NSMutableDictionary dictionary];
        ta[NSFontAttributeName] = nf;
        _textView.typingAttributes = ta;
        return;
    }
    NSFont *f = [_textView.textStorage attribute:NSFontAttributeName atIndex:sel.location effectiveRange:NULL];
    if (!f) f = [NSFont systemFontOfSize:12];
    NSFontTraitMask traits = [fm traitsOfFont:f];
    NSFont *nf;
    if (traits & NSBoldFontMask) nf = [fm convertFont:f toNotHaveTrait:NSBoldFontMask];
    else nf = [fm convertFont:f toHaveTrait:NSBoldFontMask];
    [_textView.textStorage addAttribute:NSFontAttributeName value:nf range:sel];
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)toggleItalic:(id)sender {
    NSRange sel = _textView.selectedRange;
    NSFontManager *fm = [NSFontManager sharedFontManager];
    if (sel.length == 0) {
        NSFont *f = [_textView typingAttributes][NSFontAttributeName];
        if (!f) f = [NSFont systemFontOfSize:12];
        NSFont *nf = ([fm traitsOfFont:f] & NSItalicFontMask)
            ? [fm convertFont:f toNotHaveTrait:NSItalicFontMask]
            : [fm convertFont:f toHaveTrait:NSItalicFontMask];
        NSMutableDictionary *ta = [[_textView typingAttributes] mutableCopy];
        if (ta == nil) ta = [NSMutableDictionary dictionary];
        ta[NSFontAttributeName] = nf;
        _textView.typingAttributes = ta;
        return;
    }
    NSFont *f = [_textView.textStorage attribute:NSFontAttributeName atIndex:sel.location effectiveRange:NULL];
    if (!f) f = [NSFont systemFontOfSize:12];
    NSFontTraitMask traits = [fm traitsOfFont:f];
    NSFont *nf;
    if (traits & NSItalicFontMask) nf = [fm convertFont:f toNotHaveTrait:NSItalicFontMask];
    else nf = [fm convertFont:f toHaveTrait:NSItalicFontMask];
    [_textView.textStorage addAttribute:NSFontAttributeName value:nf range:sel];
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)toggleUnderline:(id)sender {
    NSRange sel = _textView.selectedRange;
    if (sel.length == 0) {
        NSMutableDictionary *ta = [[_textView typingAttributes] mutableCopy];
        if (ta == nil) ta = [NSMutableDictionary dictionary];
        BOOL on = (ta[NSUnderlineStyleAttributeName] != nil);
        if (on) [ta removeObjectForKey:NSUnderlineStyleAttributeName];
        else ta[NSUnderlineStyleAttributeName] = [NSNumber numberWithInt:NSUnderlineStyleSingle];
        _textView.typingAttributes = ta;
        return;
    }
    // check first char
    id val = [_textView.textStorage attribute:NSUnderlineStyleAttributeName atIndex:sel.location effectiveRange:NULL];
    int newVal = (val) ? 0 : NSUnderlineStyleSingle;
    if (newVal == 0) [_textView.textStorage removeAttribute:NSUnderlineStyleAttributeName range:sel];
    else [_textView.textStorage addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt:newVal] range:sel];
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)showColorPanel:(id)sender {
    [NSApp orderFrontColorPanel:self];
}

- (void)colorChanged:(id)sender {
    NSColor *c = [sender respondsToSelector:@selector(color)] ? [sender color]
                                                               : [NSColor blackColor];
    NSRange sel = _textView.selectedRange;
    if (sel.length > 0) {
        [_textView.textStorage addAttribute:NSForegroundColorAttributeName value:c range:sel];
    } else {
        NSMutableDictionary *ta = [_textView.typingAttributes mutableCopy];
        ta[NSForegroundColorAttributeName] = c;
        _textView.typingAttributes = ta;
    }
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)alignmentChanged:(id)sender {
    NSInteger idx = [_alignmentPopup indexOfSelectedItem];
    NSTextAlignment align = NSLeftTextAlignment;
    if (idx == 1) align = NSCenterTextAlignment;
    else if (idx == 2) align = NSRightTextAlignment;
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    [ps setAlignment:align];
    NSRange sel = _textView.selectedRange;
    NSRange range = (sel.length > 0) ? sel : NSMakeRange(0, [_textView.textStorage length]);
    [_textView.textStorage addAttribute:NSParagraphStyleAttributeName value:ps range:range];
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)toggleRichMode:(id)sender {
    _textDocument.richTextMode = !_textDocument.richTextMode;
    _textView.richText = _textDocument.richTextMode;
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)togglePreview:(id)sender {
    if (!_markdownMode) return;
    _previewMode = !_previewMode;
    if (_previewMode) {
        NSFont *base = [NSFont systemFontOfSize:12];
        NSAttributedString *attr = [MarkdownHighlighter renderedPreviewForMarkdown:_textView.string baseFont:base];
        _applyingHighlight = YES;
        [_textView.textStorage setAttributedString:attr];
        _textView.editable = NO;
        _applyingHighlight = NO;
    } else {
        _textView.editable = YES;
        // reload from document
        [_textView setString:_textDocument.textStorage.string];
        [self applyMarkdownHighlighting];
    }
    [_textDocument updateChangeCount:NSChangeDone];
    [[self window] setDocumentEdited:YES];
}

- (void)encodingChanged:(id)sender {
    NSInteger idx = [_encodingPopup indexOfSelectedItem];
    NSStringEncoding enc = NSUTF8StringEncoding;
    if (idx == 1) enc = NSASCIIStringEncoding;
    else if (idx == 2) enc = NSISOLatin1StringEncoding;
    _textDocument.encoding = enc;
    [self updateStatus];
}

// Document/window actions
- (void)newDocument:(id)sender {
    [[NSDocumentController sharedDocumentController] newDocument:sender];
}

- (void)openDocument:(id)sender {
    [[NSDocumentController sharedDocumentController] openDocument:sender];
}

- (void)saveDocument:(id)sender {
    [self syncDocumentStorage];
    [_textDocument saveDocument:sender];
    [[self window] setDocumentEdited:[_textDocument isDocumentEdited]];
}

- (void)saveDocumentAs:(id)sender {
    [self syncDocumentStorage];
    [_textDocument saveDocumentAs:sender];
    [[self window] setDocumentEdited:[_textDocument isDocumentEdited]];
    [[self window] setTitle:[_textDocument displayName]];
}

- (void)revertDocumentToSaved:(id)sender {
    [_textDocument revertDocumentToSaved:sender];
    [self loadDocumentIntoView];
}

- (void)performClose:(id)sender {
    [[self window] performClose:sender];
}

- (BOOL)windowShouldClose:(id)sender {
    if (![_textDocument isDocumentEdited]) return YES;
    NSAlert *alert = [NSAlert alertWithMessageText:@"Do you want to save changes to this document?" defaultButton:@"Save" alternateButton:@"Cancel" otherButton:@"Don't Save" informativeTextWithFormat:@"%@", [_textDocument displayName]];
    NSInteger r = [alert runModal];
    if (r == NSAlertFirstButtonReturn) {
        [_textDocument saveDocument:self];
        return ![_textDocument isDocumentEdited];
    } else if (r == NSAlertSecondButtonReturn) {
        return NO;
    } else {
        return YES;
    }
}

- (void)windowWillClose:(NSNotification *)note {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end