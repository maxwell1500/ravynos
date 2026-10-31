/*
 * QuartzCore constants a stock application binds at load time.
 *
 * XUL records kCAGravity* (and friends) as non-lazy strings; a missing
 * constant stops the load.  The values are Apple's documented ones.
 */
#import <Foundation/Foundation.h>

NSString * const kCAGravityCenter = @"center";
NSString * const kCAGravityTop = @"top";
NSString * const kCAGravityBottom = @"bottom";
NSString * const kCAGravityLeft = @"left";
NSString * const kCAGravityRight = @"right";
NSString * const kCAGravityTopLeft = @"topleft";
NSString * const kCAGravityTopRight = @"topright";
NSString * const kCAGravityBottomLeft = @"bottomleft";
NSString * const kCAGravityBottomRight = @"bottomright";
NSString * const kCAGravityResize = @"resize";
NSString * const kCAGravityResizeAspect = @"resizeAspect";
NSString * const kCAGravityResizeAspectFill = @"resizeAspectFill";
