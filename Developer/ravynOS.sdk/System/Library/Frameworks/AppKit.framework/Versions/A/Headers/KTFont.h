#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font.h>

@interface KTFont : NSObject {
    O2Font *_font;
    CGFloat _size;
}
- (id)init;
- (id)initWithFont:(O2Font *)font size:(CGFloat)size;
- (O2Font *)font;
- (CGFloat)size;
@end
