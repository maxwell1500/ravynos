#import "PasswordGeneratorWindow.h"
#include <stdlib.h>

@interface PasswordGeneratorWindow () {
    NSWindow *_window;
    NSSlider *_lengthSlider;
    NSPopUpButton *_typePopup;
    NSTextField *_passwordField;
    NSProgressIndicator *_entropyBar;
    NSTextField *_entropyLabel;
}
@end

@implementation PasswordGeneratorWindow

static NSString *randomChars(NSString *charset, int len) {
    NSMutableString *s = [NSMutableString string];
    for (int i=0;i<len;i++) {
        unichar c = [charset characterAtIndex:arc4random_uniform((uint32_t)charset.length)];
        [s appendFormat:@"%C", c];
    }
    return s;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(200,200,420,260);
    _window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSTitledWindowMask|NSClosableWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_window setTitle:@"Password Assistant"];
    NSView *c = [_window contentView];
    // Type popup
    NSTextField *tl = [[NSTextField alloc] initWithFrame:NSMakeRect(16,220,80,18)];
    [tl setStringValue:@"Type:"];
    [tl setBezeled:NO]; [tl setDrawsBackground:NO]; [tl setEditable:NO];
    [c addSubview:tl];
    _typePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(100,216,280,24) pullsDown:NO];
    [_typePopup addItemsWithTitles:@[@"Memorable", @"Alphanumeric", @"High Entropy"]];
    [_typePopup setTarget:self];
    [_typePopup setAction:@selector(generate:)];
    [c addSubview:_typePopup];

    // Length
    NSTextField *ll = [[NSTextField alloc] initWithFrame:NSMakeRect(16,188,80,18)];
    [ll setStringValue:@"Length:"];
    [ll setBezeled:NO]; [ll setDrawsBackground:NO]; [ll setEditable:NO];
    [c addSubview:ll];
    _lengthSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(100,186,280,20)];
    [_lengthSlider setMinValue:4]; [_lengthSlider setMaxValue:40]; [_lengthSlider setDoubleValue:12];
    [_lengthSlider setTarget:self]; [_lengthSlider setAction:@selector(generate:)];
    [c addSubview:_lengthSlider];

    // Password field
    _passwordField = [[NSTextField alloc] initWithFrame:NSMakeRect(16,140,384,24)];
    [_passwordField setEditable:NO];
    [_passwordField setSelectable:YES];
    [c addSubview:_passwordField];

    // Entropy bar
    NSTextField *el = [[NSTextField alloc] initWithFrame:NSMakeRect(16,108,80,18)];
    [el setStringValue:@"Entropy:"];
    [el setBezeled:NO]; [el setDrawsBackground:NO]; [el setEditable:NO];
    [c addSubview:el];
    _entropyBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(100,106,280,18)];
    [_entropyBar setMinValue:0]; [_entropyBar setMaxValue:100];
    [_entropyBar setIndeterminate:NO];
    [c addSubview:_entropyBar];
    _entropyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16,80,384,18)];
    [_entropyLabel setBezeled:NO]; [_entropyLabel setDrawsBackground:NO]; [_entropyLabel setEditable:NO];
    [c addSubview:_entropyLabel];

    // Buttons
    NSButton *genBtn = [[NSButton alloc] initWithFrame:NSMakeRect(16,30,120,28)];
    [genBtn setTitle:@"Generate"];
    [genBtn setBezelStyle:NSRoundedBezelStyle];
    [genBtn setTarget:self]; [genBtn setAction:@selector(generate:)];
    [c addSubview:genBtn];
    NSButton *copyBtn = [[NSButton alloc] initWithFrame:NSMakeRect(150,30,120,28)];
    [copyBtn setTitle:@"Copy"];
    [copyBtn setBezelStyle:NSRoundedBezelStyle];
    [copyBtn setTarget:self]; [copyBtn setAction:@selector(copyPassword:)];
    [c addSubview:copyBtn];

    [self generate:nil];
}

- (void)show {
    if (!_window) [self buildWindow];
    [_window makeKeyAndOrderFront:nil];
}

- (NSString *)generatedPassword { return [_passwordField stringValue]; }

- (void)generate:(id)sender {
    int len = (int)[_lengthSlider doubleValue];
    NSString *pw = @"";
    double charset = 26;
    int type = (int)[_typePopup indexOfSelectedItem];
    if (type == 0) {
        // memorable syllables
        NSMutableString *s = [NSMutableString string];
        NSString *cons = @"bcdfghjklmnpqrstvwxyz";
        NSString *vow = @"aeiou";
        for (int i=0;i<len;i++) {
            if (i % 3 == 2) [s appendString:@"-"];
            else if (i % 3 == 0) {
                unichar c = [cons characterAtIndex:arc4random_uniform((uint32_t)cons.length)];
                [s appendFormat:@"%C", c];
            } else {
                unichar c = [vow characterAtIndex:arc4random_uniform((uint32_t)vow.length)];
                [s appendFormat:@"%C", c];
            }
        }
        pw = s;
        charset = 21;
    } else if (type == 1) {
        NSString *cs = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        pw = randomChars(cs, len);
        charset = 62;
    } else {
        NSString *cs = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{};:,.<>?";
        pw = randomChars(cs, len);
        charset = 90;
    }
    [_passwordField setStringValue:pw];
    double entropy = len * log2(charset);
    [_entropyBar setDoubleValue:fmin(100.0, entropy)];
    [_entropyLabel setStringValue:[NSString stringWithFormat:@"%.1f bits", entropy]];
}

- (void)copyPassword:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[_passwordField stringValue] forType:NSPasteboardTypeString];
}
@end