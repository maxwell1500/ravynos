#import "TextDocument.h"
#import "TextWindowController.h"
#import <AppKit/NSTextStorage.h>

@implementation TextDocument

@synthesize encoding = _encoding;
@synthesize richTextMode = _richTextMode;
@synthesize textStorage = _textStorage;

- (id)init {
    self = [super init];
    if (self) {
        _encoding = NSUTF8StringEncoding;
        _richTextMode = NO;
        _textStorage = [[NSTextStorage alloc] initWithString:@""];
    }
    return self;
}

- (void)makeWindowControllers {
    TextWindowController *wc = [[TextWindowController alloc] initWithDocument:self];
    [self addWindowController:wc];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error {
    NSString *ext = [[[self fileURL] path] pathExtension];
    if ([ext caseInsensitiveCompare:@"rtf"] == NSOrderedSame || (data.length > 5 && [[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 5)] encoding:NSASCIIStringEncoding] hasPrefix:@"{\\rtf"])) {
        _richTextMode = YES;
        NSAttributedString *as = [[NSAttributedString alloc] initWithRTF:data documentAttributes:NULL];
        if (as) {
            [_textStorage setAttributedString:as];
        } else {
            NSString *s = [[NSString alloc] initWithData:data encoding:_encoding];
            if (s) { [_textStorage setAttributedString:[[NSAttributedString alloc] initWithString:s]]; }
        }
    } else {
        _richTextMode = NO;
        NSStringEncoding enc = _encoding;
        const unsigned char *bytes = (const unsigned char *)[data bytes];
        NSUInteger len = [data length];
        NSUInteger offset = 0;
        if (len >= 3 && bytes[0]==0xEF && bytes[1]==0xBB && bytes[2]==0xBF) { enc = NSUTF8StringEncoding; offset = 3; }
        else if (len >= 2 && bytes[0]==0xFF && bytes[1]==0xFE) { enc = NSUnicodeStringEncoding; offset = 2; }
        else if (len >= 2 && bytes[0]==0xFE && bytes[1]==0xFF) { enc = NSUnicodeStringEncoding; offset = 2; }
        NSData *payload = (offset>0) ? [data subdataWithRange:NSMakeRange(offset, len-offset)] : data;
        NSString *s = [[NSString alloc] initWithData:payload encoding:enc];
        if (!s) s = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
        if (!s) s = [[NSString alloc] initWithData:payload encoding:NSISOLatin1StringEncoding];
        if (s) {
            [_textStorage setAttributedString:[[NSAttributedString alloc] initWithString:s]];
        }
        _encoding = enc;
    }
    return YES;
}

- (NSData *)dataOfType:(NSString *)type error:(NSError **)error {
    if (_richTextMode) {
        return [_textStorage RTFFromRange:NSMakeRange(0, [_textStorage length]) documentAttributes:nil];
    }
    NSString *s = [_textStorage string];
    NSData *d = [s dataUsingEncoding:_encoding allowLossyConversion:YES];
    if (d == nil) d = [s dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    return d;
}

- (void)setEncoding:(NSStringEncoding)encoding {
    _encoding = encoding;
    [self updateChangeCount:NSChangeDone];
}

- (NSStringEncoding)encoding {
    return _encoding;
}

@end