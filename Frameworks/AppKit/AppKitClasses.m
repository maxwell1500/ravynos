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

@interface NSAppearance : NSObject {
    NSString *_name;
}
- (instancetype)initWithName:(NSString *)name;
@end

static NSAppearance *sCurrentAppearance = nil;

@implementation NSAppearance
/* Gecko resolves NSAppearanceNameAqua and asks for it by name.  This tree
 * renders one (light) appearance; requesting a known appearance returns
 * an object carrying that name so -name and equality behave, requesting an
 * unknown one returns nil exactly as AppKit does. */
- (instancetype)initWithName:(NSString *)name {
    self = [super init];
    if (self != nil)
        _name = [name copy];
    return self;
}

- (void)dealloc {
    [_name release];
    [super dealloc];
}

+ (NSAppearance *)appearanceNamed:(NSString *)name {
    static NSString * const known[] = {
        @"NSAppearanceNameAqua",
        @"NSAppearanceNameDarkAqua",
        @"NSAppearanceNameVibrantLight",
        @"NSAppearanceNameVibrantDark",
        @"NSAppearanceNameAccessibilityHighContrastAqua",
        @"NSAppearanceNameAccessibilityHighContrastDarkAqua",
        @"NSAppearanceNameAccessibilityHighContrastVibrantLight",
        @"NSAppearanceNameAccessibilityHighContrastVibrantDark",
        nil
    };
    int i;
    if (name == nil)
        return nil;
    for (i = 0; known[i] != nil; i++)
        if ([name isEqualToString:known[i]])
            return [[[NSAppearance alloc] initWithName:name] autorelease];
    return nil;
}

+ (NSAppearance *)currentAppearance {
    if (sCurrentAppearance != nil)
        return sCurrentAppearance;
    return [self appearanceNamed:@"NSAppearanceNameAqua"];
}

+ (void)setCurrentAppearance:(NSAppearance *)appearance {
    if (sCurrentAppearance != appearance) {
        [sCurrentAppearance release];
        sCurrentAppearance = [appearance retain];
    }
}

- (NSString *)bestMatchFromAppearancesWithNames:(NSArray *)names {
    NSUInteger i, count = [names count];
    NSString *current = [_name isEqualToString:@"NSAppearanceNameDarkAqua"]
        ? @"NSAppearanceNameDarkAqua" : @"NSAppearanceNameAqua";
    for (i = 0; i < count; i++) {
        NSString *candidate = [names objectAtIndex:i];
        if ([candidate isEqualToString:current])
            return candidate;
    }
    return count > 0 ? [names objectAtIndex:0] : nil;
}

/* Called with a list of appearance names a view could adopt; return the
 * one that matches this system's (only) appearance. */
+ (NSString *)bestMatchFromAppearancesWithNames:(NSArray *)names {
    NSUInteger i, count = [names count];
    for (i = 0; i < count; i++) {
        NSString *name = [names objectAtIndex:i];
        if ([name isEqualToString:@"NSAppearanceNameAqua"])
            return name;
    }
    return count > 0 ? [names objectAtIndex:0] : nil;
}

- (NSString *)name {
    return _name;
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[NSAppearance class]])
        return NO;
    return [_name isEqualToString:[(NSAppearance *)other name]];
}

- (NSUInteger)hash {
    return [_name hash];
}
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
