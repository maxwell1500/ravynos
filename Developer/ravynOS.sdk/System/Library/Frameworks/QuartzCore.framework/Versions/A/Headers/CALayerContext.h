#import <Foundation/NSObject.h>
#import <CoreGraphics/CGGeometry.h>
#if defined(__linux__)
#import <OpenGL/OpenGL.h>
#endif

@class CARenderer, CALayer, CGLPixelSurface, NSTimer, NSMutableArray, NSNumber;

@interface CALayerContext : NSObject {
    CGRect _frame;
#if defined(__linux__)
    CGLPixelFormatObj _pixelFormat;
    CGLContextObj _glContext;
#endif
    CALayer *_layer;
    CARenderer *_renderer;


    NSMutableArray *_deleteTextureIds;

    NSTimer *_timer;
}

- initWithFrame:(CGRect)rect;

- (void)setFrame:(CGRect)value;
- (void)setLayer:(CALayer *)layer;

- (void)invalidate;

- (void)render;

- (void)startTimerIfNeeded;

- (void)deleteTextureId:(NSNumber *)textureId;

@end

