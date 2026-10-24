 #import "PDFRenderer.h"
#import <Onyx2D/O2PDFContentStream.h>
#import <Onyx2D/O2PDFOperatorTable.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFString.h>
#import <CoreGraphics/CGPDFDocument.h>
#import <CoreGraphics/CGPDFPage.h>
#import <CoreGraphics/CGContext.h>

 @interface _PreviewPDFArray : NSObject
 - (unsigned)count;
 - (BOOL)getStringAtIndex:(unsigned)index value:(O2PDFString **)stringp;
 - (BOOL)getNumberAtIndex:(unsigned)index value:(float *)valuep;
 @end
 typedef struct { NSMutableString *text; } ExtractInfo;

static NSString *stringFromPDFString(O2PDFString *s) {
    if (!s) return nil;
    unsigned len = [s length];
    const unsigned char *bytes = [s bytes];
    if (len >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return [[NSString alloc] initWithData:[NSData dataWithBytes:bytes+2 length:len-2] encoding:NSUTF16BigEndianStringEncoding];
    }
    NSString *str = [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
    if (!str) str = [[NSString alloc] initWithBytes:bytes length:len encoding:NSISOLatin1StringEncoding];
    return str;
}

static void extract_Tj(O2PDFScanner *scanner, void *info) {
    O2PDFString *s = nil;
    if (O2PDFScannerPopString(scanner, &s)) {
        ExtractInfo *ei = (ExtractInfo *)info;
        NSString *str = stringFromPDFString(s);
        if (str) [ei->text appendString:str];
        [ei->text appendString:@" "];
    }
}

static void extract_TJ(O2PDFScanner *scanner, void *info) {
    id arr = nil;
    if (O2PDFScannerPopArray(scanner, (O2PDFArray **)&arr)) {
        ExtractInfo *ei = (ExtractInfo *)info;
        unsigned c = [(_PreviewPDFArray *)arr count];
        for (unsigned i = 0; i < c; i++) {
            O2PDFString *s = nil;
            if ([(_PreviewPDFArray *)arr getStringAtIndex:i value:&s]) {
                NSString *str = stringFromPDFString(s);
                if (str) [ei->text appendString:str];
            } else {
                O2PDFReal num = 0;
                if ([(_PreviewPDFArray *)arr getNumberAtIndex:i value:&num]) {
                    if (num < -100) [ei->text appendString:@" "];
                }
            }
        }
        [ei->text appendString:@" "];
    }
}

@interface PDFRenderer () {
    NSMutableArray *_texts;
}
@end

@implementation PDFRenderer
- (id)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        CGDataProviderRef prov = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        _document = CGPDFDocumentCreateWithProvider(prov);
        CGDataProviderRelease(prov);
        _pageCount = _document ? CGPDFDocumentGetNumberOfPages(_document) : 0;
        _texts = [[NSMutableArray alloc] initWithCapacity:_pageCount];
        for (size_t i = 0; i < _pageCount; i++) [_texts addObject:[NSNull null]];
    }
    return self;
}

 - (id)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        CGDataProviderRef prov = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        _document = CGPDFDocumentCreateWithProvider(prov);
        CGDataProviderRelease(prov);
        _pageCount = _document ? CGPDFDocumentGetNumberOfPages(_document) : 0;
        _texts = [[NSMutableArray alloc] initWithCapacity:_pageCount];
        for (size_t i = 0; i < _pageCount; i++) [_texts addObject:[NSNull null]];
    }
    return self;
 }

- (void)dealloc {
    if (_document) CGPDFDocumentRelease(_document);
}

- (CGSize)pageSizeAtIndex:(NSUInteger)index {
    if (!_document || index >= _pageCount) return CGSizeMake(100, 100);
    CGPDFPageRef page = CGPDFDocumentGetPage(_document, index + 1);
    CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    return box.size;
}

- (void)drawPageAtIndex:(NSUInteger)index inContext:(CGContextRef)ctx rect:(CGRect)rect {
    if (!_document || index >= _pageCount) return;
    CGPDFPageRef page = CGPDFDocumentGetPage(_document, index + 1);
    CGSize sz = [self pageSizeAtIndex:index];
    if (sz.width <= 0 || sz.height <= 0) return;
    CGContextSaveGState(ctx);
    CGFloat sx = rect.size.width / sz.width;
    CGFloat sy = rect.size.height / sz.height;
    CGFloat s = (sx < sy) ? sx : sy;
    CGContextTranslateCTM(ctx, rect.origin.x + (rect.size.width - sz.width*s)/2.0, rect.origin.y + (rect.size.height - sz.height*s)/2.0);
    CGContextScaleCTM(ctx, s, s);
    CGContextDrawPDFPage(ctx, page);
    CGContextRestoreGState(ctx);
}

- (NSString *)textForPageAtIndex:(NSUInteger)index {
    if (!_document || index >= _pageCount) return @"";
    if (index < [_texts count] && ![[[_texts objectAtIndex:index] class] isEqual:[NSNull class]]) {
        return [_texts objectAtIndex:index];
    }
    CGPDFPageRef page = CGPDFDocumentGetPage(_document, index + 1);
    O2PDFPage *opage = (__bridge O2PDFPage *)page;
    O2PDFContentStream *cs = [[O2PDFContentStream alloc] initWithPage:opage];
    O2PDFOperatorTable *table = [[O2PDFOperatorTable alloc] init];
    [table setCallback:extract_Tj forName:"Tj"];
    [table setCallback:extract_TJ forName:"TJ"];
    NSMutableString *ms = [NSMutableString string];
    ExtractInfo ei = { ms };
    O2PDFScanner *scanner = [[O2PDFScanner alloc] initWithContentStream:cs operatorTable:table info:&ei];
    [scanner scan];
    NSString *result = [NSString stringWithString:ms];
    if (index < [_texts count]) [_texts replaceObjectAtIndex:index withObject:result];
    return result;
}

@end