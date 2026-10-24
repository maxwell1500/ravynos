#import <AppKit/AppKit.h>

typedef struct {
    uint32_t codepoint;
    uint32_t fg;
    uint32_t bg;
    uint16_t attrs;
} TermCell;

#define TERM_SCROLLBACK 2000

@interface TerminalView : NSView {
    int _masterFd;
    pid_t _shellPid;
    BOOL _shellRunning;
    int _rows;
    int _cols;
    TermCell *_grid;          // current (primary or alt) cell buffer
    TermCell *_primary;
    TermCell *_alternate;
    BOOL _onAlternate;
    int _row;
    int _col;
    int _savedRow;
    int _savedCol;
    int _scrollTop;
    int _scrollBottom;
    BOOL _cursorVisible;
    uint16_t _curAttrs;
    BOOL _cursorKeysApp;
    BOOL _bracketedPaste;
    uint32_t _fg;
    uint32_t _bg;
    uint32_t _defaultFg;
    uint32_t _defaultBg;
    int _theme;
    CGFloat _fontSize;

    // utf8 + parser state
    unsigned char _utf8Buf[4];
    int _utf8Len;
    int _utf8Need;
    int _escState;            // 0 normal,1 esc,2 csi,3 osc,4 charset
    char _escBuf[512];
    int _escLen;
    char _oscBuf[512];
    int _oscLen;
    BOOL _oscEsc;             // seen ESC in OSC (ST)

    // scrollback ring
    TermCell *_scrollback[TERM_SCROLLBACK];
    int _scrollbackCount;
    int _scrollbackHead;

    NSFont *_font;
    float _cellWidth;
    float _cellHeight;

    NSTimer *_blinkTimer;
    NSTimer *_readTimer;
    NSTimer *_fallbackTimer;

    /* Built-in line discipline.  Used when the PTY child produces no output
     * (this image's /bin/sh exits without a prompt in some sessions), so the
     * window is never a blank pane.  Command output is read from _cmdFd by the
     * same timer that drains the PTY. */
    BOOL _fallbackShell;
    BOOL _ptyProducedOutput;
    NSMutableString *_inputLine;
    int _cmdFd;
    char *_cmdBuffer;
    size_t _cmdLength;
    size_t _cmdCapacity;
    unsigned long _bytesRead;

    // selection (simple)
    BOOL _hasSelection;
}

- (void)startShell;
- (void)terminateShell;
- (void)writeInput:(const char *)s length:(size_t)len;
- (void)copyToPasteboard;
- (void)pasteFromPasteboard;
- (void)clearScreen;
- (void)selectAll;
- (void)setFontSize:(CGFloat)size;
- (void)setTheme:(int)theme;
- (void)applyThemeDefaults;

@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) int theme;
@end
