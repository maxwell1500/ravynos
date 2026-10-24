#import <AppKit/AppKit.h>
#import "TerminalView.h"

@interface TerminalWindowController : NSWindowController {
    NSTabView *_tabView;
}
@property (nonatomic, strong) NSTabView *tabView;

- (void)newTab:(id)sender;
- (void)closeTab:(id)sender;
- (void)nextTab:(id)sender;
- (void)previousTab:(id)sender;
- (void)splitVertical:(id)sender;
- (void)splitHorizontal:(id)sender;
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)zoomReset:(id)sender;
- (void)setThemeAction:(id)sender;
- (void)clearAll:(id)sender;

- (TerminalView *)currentPane;
- (TerminalView *)firstTerminalViewIn:(NSView *)view;
- (void)applyThemeToAllPanes:(int)tag;
- (void)createTab;
@end
