
#import <Foundation/Foundation.h>





#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/CATransform3D.h>
#import <QuartzCore/CAAction.h>


@class CAAnimation, CALayerContext;

enum {
    kCALayerNotSizable = 0x00,
    kCALayerMinXMargin = 0x01,
    kCALayerWidthSizable = 0x02,
    kCALayerMaxXMargin = 0x04,
    kCALayerMinYMargin = 0x08,
    kCALayerHeightSizable = 0x10,
    kCALayerMaxYMargin = 0x20,
};

CA_EXPORT NSString *const kCAFilterLinear;
CA_EXPORT NSString *const kCAFilterNearest;
CA_EXPORT NSString *const kCAFilterTrilinear;

@interface CALayer : NSObject {
     CALayerContext *_context;
    CALayer *_superlayer;
    NSArray *_sublayers;
    id _delegate;
    CGPoint _anchorPoint;
    CGPoint _position;
    CGRect _bounds;
    float _opacity;
    BOOL _opaque;
    id _contents;
    int _contentsKind;
    CATransform3D _transform;
    CATransform3D _sublayerTransform;
    NSString *_minificationFilter;
    NSString *_magnificationFilter;
    BOOL _needsDisplay;
    NSMutableDictionary *_animations;
    NSNumber *_textureId;

    NSString *_contentsGravity;
    CGFloat _contentsScale;
    BOOL _masksToBounds;
    BOOL _contentsOpaque;
    BOOL _geometryFlipped;
    unsigned _edgeAntialiasingMask;
    CGRect _contentsRect;
}

+ layer;

@property(readonly) CALayer *superlayer;
@property(copy) NSArray *sublayers;
@property(assign) id delegate;
@property CGPoint anchorPoint;
@property CGPoint position;
@property CGRect bounds;
@property CGRect frame;
@property float opacity;
@property(copy) NSString *contentsGravity;
@property CGFloat contentsScale;
@property BOOL masksToBounds;
@property BOOL contentsOpaque;
@property BOOL geometryFlipped;
@property unsigned edgeAntialiasingMask;
@property CGRect contentsRect;
@property BOOL opaque;
@property(retain) id contents;
//@property CATransform3D transform;
@property CATransform3D sublayerTransform;

@property(copy) NSString *minificationFilter;
@property(copy) NSString *magnificationFilter;

- init;

- (void)addSublayer:(CALayer *)layer;
- (void)replaceSublayer:(CALayer *)layer with:(CALayer *)other;
- (void)display;
- (void)displayIfNeeded;
- (void)drawInContext:(CGContextRef)context;
- (BOOL)needsDisplay;
- (void)removeFromSuperlayer;
- (void)setNeedsDisplay;
- (void)setNeedsDisplayInRect:(CGRect)rect;

- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key;
- (CAAnimation *)animationForKey:(NSString *)key;
- (void)removeAllAnimations;
- (void)removeAnimationForKey:(NSString *)key;
- (NSArray *)animationKeys;

- (id<CAAction>)actionForKey:(NSString *)key;

@end

@interface NSObject (CALayerDelegate)

- (void)displayLayer:(CALayer *)layer;
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context;

@end
