#import <AppKit/AppKit.h>
#import "TextDocument.h"

@interface TextWindowController : NSWindowController
@property (nonatomic, strong) TextDocument *textDocument;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSPopUpButton *fontFamilyPopup;
@property (nonatomic, strong) NSPopUpButton *fontSizePopup;
@property (nonatomic, strong) NSPopUpButton *alignmentPopup;
@property (nonatomic, strong) NSPopUpButton *encodingPopup;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSTextField *statusField;
@property (nonatomic, assign) BOOL markdownMode;
@property (nonatomic, assign) BOOL previewMode;
@property (nonatomic, assign) BOOL applyingHighlight;

- (id)initWithDocument:(TextDocument *)document;
- (void)newDocument:(id)sender;
- (void)openDocument:(id)sender;
- (void)saveDocument:(id)sender;
- (void)saveDocumentAs:(id)sender;
- (void)revertDocumentToSaved:(id)sender;
- (void)performClose:(id)sender;
@end