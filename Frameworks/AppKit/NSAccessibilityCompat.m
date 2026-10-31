/*
 * NSAccessibilityCompat -- constants a stock application links at load time.
 *
 * These are non-lazy data references: dyld refuses to load the application
 * when any of them is absent ("Symbol not found: <name>"), so they must
 * exist as real NSString objects even where the feature behind them is not
 * implemented. Each value is the documented string for the constant; the
 * name is what applications compare against, and a dictionary key only has
 * to be a stable non-NULL string.
 */
#import <Foundation/Foundation.h>

NSString * const NSAccessibilityAnnouncementKey = @"NSAccessibilityAnnouncementKey";
NSString * const NSAccessibilityAnnouncementRequestedNotification = @"NSAccessibilityAnnouncementRequestedNotification";
NSString * const NSAccessibilityMarkedMisspelledTextAttribute = @"NSAccessibilityMarkedMisspelledTextAttribute";
NSString * const NSAccessibilityPriorityKey = @"NSAccessibilityPriorityKey";
NSString * const NSAccessibilitySwitchSubrole = @"NSAccessibilitySwitchSubrole";
NSString * const NSAccessibilityToggleSubrole = @"NSAccessibilityToggleSubrole";
NSString * const NSAppearanceNameAqua = @"NSAppearanceNameAqua";
NSString * const NSAppearanceNameVibrantLight = @"NSAppearanceNameVibrantLight";
NSString * const NSControlTintDidChangeNotification = @"NSControlTintDidChangeNotification";
NSString * const NSMarkedClauseSegmentAttributeName = @"NSMarkedClauseSegmentAttributeName";
NSString * const NSMenuWillSendActionNotification = @"NSMenuWillSendActionNotification";
NSString * const NSPrintJobSavingURL = @"NSPrintJobSavingURL";
NSString * const NSSharingServiceNamePostOnTwitter = @"NSSharingServiceNamePostOnTwitter";
NSString * const NSSpeechPitchBaseProperty = @"NSSpeechPitchBaseProperty";
NSString * const NSSpeechRateProperty = @"NSSpeechRateProperty";
NSString * const NSSpeechVolumeProperty = @"NSSpeechVolumeProperty";
NSString * const NSSystemColorsDidChangeNotification = @"NSSystemColorsDidChangeNotification";
NSString * const NSTextInputReplacementRangeAttributeName = @"NSTextInputReplacementRangeAttributeName";
NSString * const NSVerticalGlyphFormAttributeName = @"NSVerticalGlyphFormAttributeName";
NSString * const NSVoiceIdentifier = @"NSVoiceIdentifier";
NSString * const NSVoiceLocaleIdentifier = @"NSVoiceLocaleIdentifier";
NSString * const NSVoiceName = @"NSVoiceName";
NSString * const NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification = @"NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification";
NSString * const NSPreferredScrollerStyleDidChangeNotification = @"NSPreferredScrollerStyleDidChangeNotification";
NSString * const NSAppearanceNameDarkAqua = @"NSAppearanceNameDarkAqua";
NSString * const NSPasteboardNameFind = @"NSPasteboardNameFind";
