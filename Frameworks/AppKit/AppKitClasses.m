/*
 * AppKit -- Objective-C classes a stock application binds at load time.
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
#import "NSView.h"
#import "NSViewController.h"

@interface NSAppearance : NSObject
@end

@implementation NSAppearance
@end

@interface NSCustomTouchBarItem : NSObject
@end

@implementation NSCustomTouchBarItem
@end

@interface NSDraggingItem : NSObject
@end

@implementation NSDraggingItem
@end

@interface NSLayoutConstraint : NSObject
@end

@implementation NSLayoutConstraint
@end

@interface NSOpenGLContext : NSObject
@end

@implementation NSOpenGLContext
@end

@interface NSOpenGLPixelFormat : NSObject
@end

@implementation NSOpenGLPixelFormat
@end

@interface NSPasteboardItem : NSObject
@end

@implementation NSPasteboardItem
@end

@interface NSPopoverTouchBarItem : NSObject
@end

@implementation NSPopoverTouchBarItem
@end

@interface NSRunningApplication : NSObject
@end

@implementation NSRunningApplication
@end

@interface NSSharingService : NSObject
@end

@implementation NSSharingService
@end

@interface NSSharingServicePickerTouchBarItem : NSObject
@end

@implementation NSSharingServicePickerTouchBarItem
@end

@interface NSSpeechSynthesizer : NSObject
@end

@implementation NSSpeechSynthesizer
@end

@interface NSTextInputContext : NSObject
@end

@implementation NSTextInputContext
@end

@interface NSTitlebarAccessoryViewController : NSViewController {
    BOOL _accessoryHidden;
    NSInteger _layoutAttribute;
    CGFloat _fullScreenMinHeight;
}
@end

@implementation NSTitlebarAccessoryViewController
/* Gecko's FullscreenTitlebarTracker subclasses this controller and sends
 * -setHidden:, which is the hidden property macOS gives the class.  The
 * controller is not laid out into the titlebar yet, so the flag is
 * remembered and the view is hidden from its superview when present. */
-(BOOL)isHidden {
   return _accessoryHidden;
}

-(void)setHidden:(BOOL)hidden {
   _accessoryHidden = hidden ? YES : NO;
   [[self view] setHidden:_accessoryHidden];
}

-(NSInteger)layoutAttribute {
   return _layoutAttribute;
}

-(void)setLayoutAttribute:(NSInteger)attribute {
   _layoutAttribute = attribute;
}

-(CGFloat)fullScreenMinHeight {
   return _fullScreenMinHeight;
}

-(void)setFullScreenMinHeight:(CGFloat)height {
   _fullScreenMinHeight = height;
}
@end

@interface NSTouchBar : NSObject
@end

@implementation NSTouchBar
@end

@interface NSVisualEffectView : NSView
@end

@implementation NSVisualEffectView
@end
