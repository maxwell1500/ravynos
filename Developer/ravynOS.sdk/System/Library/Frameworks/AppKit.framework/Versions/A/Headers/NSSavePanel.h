/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSPanel.h>

@class NSView;

enum {
    NSFileHandlingPanelCancelButton = NSCancelButton,
    NSFileHandlingPanelOKButton = NSOKButton,
};

@interface NSSavePanel : NSPanel {
    NSString *_dialogTitle;

    NSString *_filename;
    NSString *_directory;
    NSString *_requiredFileType;
    NSString *_message;
    NSString *_prompt;

    BOOL _treatsFilePackagesAsDirectories;
    NSView *_accessoryView;

    BOOL _canCreateDirectories;
    BOOL _allowsOtherFileTypes;
    BOOL _showsHiddenFiles;
    NSArray *_allowedFileTypes;
    NSString *_nameFieldStringValue;
}

+ (NSSavePanel *)savePanel;

- (NSURL *)URL;
- (NSString *)filename;

- (int)runModalForDirectory:(NSString *)directory file:(NSString *)file;
- (int)runModal;

- (NSString *)directory;
- (BOOL)treatsFilePackagesAsDirectories;
- (NSView *)accessoryView;

- (void)setTitle:(NSString *)title;

- (void)setDirectory:(NSString *)directory;

- (void)setRequiredFileType:(NSString *)type;
- (void)setTreatsFilePackagesAsDirectories:(BOOL)flag;

- (void)setAccessoryView:(NSView *)view;
- (void)setCanCreateDirectories:(BOOL)value;
- (BOOL)canCreateDirectories;
- (void)setAllowedFileTypes:(NSArray *)value;
- (NSArray *)allowedFileTypes;
- (void)setAllowsOtherFileTypes:(BOOL)value;
- (BOOL)allowsOtherFileTypes;
- (void)setShowsHiddenFiles:(BOOL)value;
- (BOOL)showsHiddenFiles;
- (void)setNameFieldStringValue:(NSString *)value;
- (NSString *)nameFieldStringValue;

/* Internal: runs the file browser for this panel. */
- (int)_runRavynModalForDirectory:(NSString *)directory file:(NSString *)file types:(NSArray *)types;

/* Internal: the browser asks the panel how it has to behave.  NSOpenPanel
 * overrides these to enable directory and multiple selection. */
- (BOOL)_panelIsOpenPanel;
- (BOOL)_panelCanChooseFiles;
- (BOOL)_panelCanChooseDirectories;
- (BOOL)_panelAllowsMultipleSelection;
- (void)_panelDidChoosePaths:(NSArray *)paths;

- (void)setMessage:(NSString *)message;
- (NSString *)message;

- (void)setPrompt:(NSString *)message;
- (NSString *)prompt;

- (void)beginSheetForDirectory:(NSString *)path
                          file:(NSString *)name
                modalForWindow:(NSWindow *)docWindow
                 modalDelegate:(id)modalDelegate
                didEndSelector:(SEL)didEndSelector
                   contextInfo:(void *)contextInfo;
@end
