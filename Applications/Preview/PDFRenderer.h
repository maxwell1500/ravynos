#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFPage.h>

@interface PDFRenderer : NSObject
@property (nonatomic, assign) CGPDFDocumentRef document;
@property (nonatomic, assign) size_t pageCount;

- (id)initWithData:(NSData *)data;
- (id)initWithURL:(NSURL *)url;
- (CGSize)pageSizeAtIndex:(NSUInteger)index;
- (void)drawPageAtIndex:(NSUInteger)index inContext:(CGContextRef)ctx rect:(CGRect)rect;
- (NSString *)textForPageAtIndex:(NSUInteger)index;
@end