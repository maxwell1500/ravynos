/*
 * AVFoundation -- Objective-C classes a stock application binds at load time.
 *
 * Firefox's XUL records _OBJC_CLASS_$_<name> for each of these, and dyld
 * resolves class references eagerly: a missing class stops the application
 * before it runs ("Symbol not found: _OBJC_CLASS_$_...").  The classes here
 * exist with no behaviour -- implementing them is separate work -- and every
 * method they do not implement raises the usual unrecognized-selector
 * exception rather than pretending to succeed.
 *
 * Subclasses are declared with the superclass the framework documents, so
 * type checks and isKindOfClass: in framework code behave.
 */
#import <Foundation/Foundation.h>

@interface AVAssetReader : NSObject
@end

@implementation AVAssetReader
@end

@interface AVAssetReaderTrackOutput : NSObject
@end

@implementation AVAssetReaderTrackOutput
@end

@interface AVCaptureDevice : NSObject
@end

@implementation AVCaptureDevice
@end

@interface AVCaptureDeviceInput : NSObject
@end

@implementation AVCaptureDeviceInput
@end

@interface AVCaptureSession : NSObject
@end

@implementation AVCaptureSession
@end

@interface AVCaptureVideoDataOutput : NSObject
@end

@implementation AVCaptureVideoDataOutput
@end

@interface AVSampleBufferDisplayLayer : NSObject
@end

@implementation AVSampleBufferDisplayLayer
@end

@interface AVURLAsset : NSObject
@end

@implementation AVURLAsset
@end
