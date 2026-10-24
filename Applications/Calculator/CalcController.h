#import <AppKit/AppKit.h>
#import "CalcEngine.h"

@interface CalcKeyView : NSView
@property (nonatomic, assign) id keyDelegate;
@end
@interface CalcController : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSWindow *tapeWindow;
@property (strong) NSTextView *tapeView;
@property (strong) NSTextField *displayField;
@property (strong) NSSegmentedControl *modeSeg;
@property (strong) CalcEngine *engine;
@property (strong) NSView *bitPanel;
@property (strong) NSMutableArray *bitButtons;
@property (strong) NSTextField *hexField;
@property (strong) NSTextField *decField;
@property (strong) NSTextField *octField;
@property (strong) NSTextField *binField;
@property (strong) NSPopUpButton *basePopup;

- (void)rebuildUI;
- (void)refreshDisplay;
- (void)appendTapeLine:(NSString *)line;
@end