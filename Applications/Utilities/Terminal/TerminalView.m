#import "TerminalView.h"

#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>
#include <dispatch/dispatch.h>

static uint32_t color256(int n) {
    static const uint32_t table16[16] = {
        0x000000,0x800000,0x008000,0x808000,0x000080,0x800080,0x008080,0xc0c0c0,
        0x808080,0xff0000,0x00ff00,0xffff00,0x0000ff,0xff00ff,0x00ffff,0xffffff
    };
    if (n < 16) return table16[n];
    if (n < 232) {
        int idx = n - 16;
        int r = idx / 36, g = (idx / 6) % 6, b = idx % 6;
        int rv = (r == 0) ? 0 : 55 + r * 40;
        int gv = (g == 0) ? 0 : 55 + g * 40;
        int bv = (b == 0) ? 0 : 55 + b * 40;
        return ((uint32_t)rv << 16) | ((uint32_t)gv << 8) | (uint32_t)bv;
    }
    int v = 8 + (n - 232) * 10;
    return ((uint32_t)v << 16) | ((uint32_t)v << 8) | (uint32_t)v;
}

static NSColor *nsColor(uint32_t rgb) {
    return [NSColor colorWithDeviceRed:((rgb>>16)&0xff)/255.0
                                green:((rgb>>8)&0xff)/255.0
                                 blue:(rgb&0xff)/255.0 alpha:1.0];
}

static const char *shellEscape(const char *in) {
    // returns static-ish buffer? We'll build NSString instead.
    return in;
}

@implementation TerminalView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;

    _masterFd = -1;
    _cmdFd = -1;
    _cmdBuffer = NULL;
    _cmdLength = 0;
    _cmdCapacity = 0;
    _fallbackShell = NO;
    _ptyProducedOutput = NO;
    _bytesRead = 0;
    _shellPid = -1;
    _shellRunning = NO;
    _rows = 24;
    _cols = 80;
    _row = 0; _col = 0;
    _savedRow = 0; _savedCol = 0;
    _scrollTop = 0; _scrollBottom = _rows - 1;
    _cursorVisible = YES;
    _cursorKeysApp = NO;
    _bracketedPaste = NO;
    _escState = 0; _escLen = 0; _oscLen = 0; _oscEsc = NO;
    _utf8Len = 0; _utf8Need = 0;
    _scrollbackCount = 0; _scrollbackHead = 0;
    _hasSelection = NO;

    // theme from defaults
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    _theme = (int)[ud integerForKey:@"TerminalTheme"];
    if (_theme < 0 || _theme > 3) _theme = 0;
    CGFloat fs = [ud floatForKey:@"TerminalFontSize"];
    if (fs <= 0) fs = 13.0;
    _fontSize = fs;

    [self applyThemeDefaults];

    _font = [NSFont fontWithName:@"NimbusMonoPS-Regular" size:_fontSize];
    if (_font == nil) _font = [NSFont systemFontOfSize:_fontSize];

    NSSize advance = [@"M" sizeWithAttributes:@{ NSFontAttributeName: _font }];
    _cellWidth = (advance.width > 1.0f) ? advance.width : 8.0f;
    _cellHeight = (advance.height > 1.0f) ? advance.height : 16.0f;

    size_t n = (size_t)_rows * _cols;
    _primary = calloc(n, sizeof(TermCell));
    _alternate = calloc(n, sizeof(TermCell));
    _grid = _primary;
    for (size_t i = 0; i < n; i++) {
        _primary[i].codepoint = ' ';
        _primary[i].fg = _defaultFg;
        _primary[i].bg = _defaultBg;
        _alternate[i].codepoint = ' ';
        _alternate[i].fg = _defaultFg;
        _alternate[i].bg = _defaultBg;
    }

    [self registerForDraggedTypes:@[NSFilenamesPboardType, NSPasteboardTypeFileURL]];

    return self;
}

- (void)dealloc {
    [_blinkTimer invalidate];
    if (_readTimer) { [_readTimer invalidate]; _readTimer = nil; }
    if (_fallbackTimer) { [_fallbackTimer invalidate]; _fallbackTimer = nil; }
    if (_cmdFd >= 0) close(_cmdFd);
    free(_cmdBuffer);
    if (_masterFd >= 0) close(_masterFd);
    free(_primary); free(_alternate);
    for (int i = 0; i < TERM_SCROLLBACK; i++) free(_scrollback[i]);
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)needsPanelToBecomeKey { return YES; }
- (void)mouseDown:(NSEvent *)event {
    [[self window] makeFirstResponder:self];
}
- (BOOL)isOpaque { return YES; }

- (void)applyThemeDefaults {
    switch (_theme) {
        case 0: // ravynOS Dark
            _defaultBg = 0x1a1b26; _defaultFg = 0xd7dae8; break;
        case 1: // Classic Black
            _defaultBg = 0x000000; _defaultFg = 0xd9d9d9; break;
        case 2: // Solarized Dark
            _defaultBg = 0x002b36; _defaultFg = 0x839496; break;
        case 3: // Light Paper
            _defaultBg = 0xf7f7f5; _defaultFg = 0x1a1a1a; break;
        default:
            _defaultBg = 0x1a1b26; _defaultFg = 0xd7dae8; break;
    }
    _fg = _defaultFg;
    _bg = _defaultBg;
}

- (void)setTheme:(int)theme {
    _theme = theme;
    [[NSUserDefaults standardUserDefaults] setInteger:theme forKey:@"TerminalTheme"];
    [self applyThemeDefaults];
    [self resetScreen];
    [self setNeedsDisplay:YES];
}

- (void)setFontSize:(CGFloat)size {
    if (size < 6) size = 6;
    if (size > 48) size = 48;
    _fontSize = size;
    [[NSUserDefaults standardUserDefaults] setFloat:size forKey:@"TerminalFontSize"];
    _font = [NSFont fontWithName:@"NimbusMonoPS-Regular" size:size];
    if (_font == nil) _font = [NSFont systemFontOfSize:size];
    NSSize advance = [@"M" sizeWithAttributes:@{ NSFontAttributeName: _font }];
    _cellWidth = (advance.width > 1.0f) ? advance.width : 8.0f;
    _cellHeight = (advance.height > 1.0f) ? advance.height : 16.0f;
    /* Recompute the grid for the new cell size and tell the child. */
    [self setFrameSize:[self frame].size];
    [self setNeedsDisplay:YES];
}

// ---------- grid helpers ----------

static inline int idx(TerminalView *v, int r, int c) { return r * v->_cols + c; }

- (void)ensureScrollbackLine:(int)i {
    if (_scrollback[i] == nil) {
        _scrollback[i] = calloc((size_t)_cols, sizeof(TermCell));
    }
}

- (void)pushScrollback:(TermCell *)row {
    if (_scrollback[_scrollbackHead] == nil)
        _scrollback[_scrollbackHead] = calloc((size_t)_cols, sizeof(TermCell));
    memcpy(_scrollback[_scrollbackHead], row, (size_t)_cols * sizeof(TermCell));
    _scrollbackHead = (_scrollbackHead + 1) % TERM_SCROLLBACK;
    if (_scrollbackCount < TERM_SCROLLBACK) _scrollbackCount++;
}

- (void)resizeGridPreserving:(int)newCols :(int)newRows {
    // allocate new buffers
    size_t n = (size_t)newRows * newCols;
    TermCell *np = calloc(n, sizeof(TermCell));
    TermCell *na = calloc(n, sizeof(TermCell));
    for (size_t i = 0; i < n; i++) {
        np[i].codepoint = ' '; np[i].fg = _defaultFg; np[i].bg = _defaultBg;
        na[i].codepoint = ' '; na[i].fg = _defaultFg; na[i].bg = _defaultBg;
    }
    // copy visible region from primary
    int copyRows = (newRows < _rows) ? newRows : _rows;
    int copyCols = (newCols < _cols) ? newCols : _cols;
    for (int r = 0; r < copyRows; r++) {
        for (int c = 0; c < copyCols; c++) {
            np[r*newCols+c] = _primary[r*_cols+c];
        }
    }
    for (int r = 0; r < copyRows; r++) {
        for (int c = 0; c < copyCols; c++) {
            na[r*newCols+c] = _alternate[r*_cols+c];
        }
    }

    /* Scrollback rows were allocated with the OLD column count; pushing a
     * wider row into them after a resize overflowed the heap. */
    for(int r = 0; r < TERM_SCROLLBACK; r++) {
        if(_scrollback[r] != NULL) {
            _scrollback[r] = realloc(_scrollback[r],
                (size_t)newCols * sizeof(TermCell));
        }
    }

    free(_primary); free(_alternate);
    _primary = np;
    _alternate = na;
    _cols = newCols;
    _rows = newRows;
    _grid = _onAlternate ? _alternate : _primary;
    if (_row >= _rows) _row = _rows - 1;
    if (_col >= _cols) _col = _cols - 1;
    if (_row < 0) _row = 0;
    if (_col < 0) _col = 0;
    _scrollTop = 0;
    _scrollBottom = _rows - 1;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    int cellW = (_cellWidth > 1) ? (int)_cellWidth : 8;
    int cellH = (_cellHeight > 1) ? (int)_cellHeight : 16;
    int newCols = (int)(newSize.width / cellW);
    int newRows = (int)(newSize.height / cellH);
    if (newCols < 20) newCols = 20;
    if (newRows < 5) newRows = 5;
    if (newCols == _cols && newRows == _rows) return;

    [self resizeGridPreserving:newCols :newRows];

    if (_masterFd >= 0) {
        struct winsize ws;
        memset(&ws, 0, sizeof(ws));
        ws.ws_row = _rows;
        ws.ws_col = _cols;
        ioctl(_masterFd, TIOCSWINSZ, &ws);
        if (_shellPid > 0) kill(-_shellPid, SIGWINCH);
    }
    [self setNeedsDisplay:YES];
}

// ---------- screen ops ----------

- (void)scrollUpRegion {
    int top = _scrollTop, bot = _scrollBottom;
    // push top line to scrollback if full screen
    if (top == 0 && bot == _rows - 1) {
        [self pushScrollback:&_grid[top*_cols]];
    }
    for (int r = top; r < bot; r++) {
        memcpy(&_grid[r*_cols], &_grid[(r+1)*_cols], (size_t)_cols * sizeof(TermCell));
    }
    for (int c = 0; c < _cols; c++) {
        _grid[bot*_cols+c].codepoint = ' ';
        _grid[bot*_cols+c].fg = _defaultFg;
        _grid[bot*_cols+c].bg = _defaultBg;
        _grid[bot*_cols+c].attrs = 0;
    }
}

- (void)scrollDownRegion {
    int top = _scrollTop, bot = _scrollBottom;
    for (int r = bot; r > top; r--) {
        memcpy(&_grid[r*_cols], &_grid[(r-1)*_cols], (size_t)_cols * sizeof(TermCell));
    }
    for (int c = 0; c < _cols; c++) {
        _grid[top*_cols+c].codepoint = ' ';
        _grid[top*_cols+c].fg = _defaultFg;
        _grid[top*_cols+c].bg = _defaultBg;
        _grid[top*_cols+c].attrs = 0;
    }
}

- (void)newline {
    if (_row == _scrollBottom) {
        [self scrollUpRegion];
    } else {
        _row++;
        if (_row >= _rows) _row = _rows - 1;
    }
}

- (void)reverseIndex {
    if (_row == _scrollTop) {
        [self scrollDownRegion];
    } else {
        _row--;
        if (_row < 0) _row = 0;
    }
}

- (void)clampCursor {
    if (_row < _scrollTop) _row = _scrollTop;
    if (_row > _scrollBottom) _row = _scrollBottom;
    if (_col < 0) _col = 0;
    if (_col >= _cols) _col = _cols - 1;
}

- (void)resetScreen {
    size_t n = (size_t)_rows * _cols;
    for (size_t i = 0; i < n; i++) {
        _grid[i].codepoint = ' ';
        _grid[i].fg = _defaultFg;
        _grid[i].bg = _defaultBg;
        _grid[i].attrs = 0;
    }
    _row = 0; _col = 0;
    _scrollTop = 0; _scrollBottom = _rows - 1;
}

- (void)clearLine:(int)mode {
    if (mode == 2) {
        for (int c = 0; c < _cols; c++) {
            _grid[_row*_cols+c].codepoint = ' ';
            _grid[_row*_cols+c].fg = _defaultFg;
            _grid[_row*_cols+c].bg = _defaultBg;
            _grid[_row*_cols+c].attrs = 0;
        }
        return;
    }
    if (mode == 1) {
        for (int c = 0; c <= _col && c < _cols; c++) {
            _grid[_row*_cols+c].codepoint = ' ';
            _grid[_row*_cols+c].fg = _defaultFg;
            _grid[_row*_cols+c].bg = _defaultBg;
            _grid[_row*_cols+c].attrs = 0;
        }
        return;
    }
    for (int c = _col; c < _cols; c++) {
        _grid[_row*_cols+c].codepoint = ' ';
        _grid[_row*_cols+c].fg = _defaultFg;
        _grid[_row*_cols+c].bg = _defaultBg;
        _grid[_row*_cols+c].attrs = 0;
    }
}

- (void)clearDisplay:(int)mode {
    if (mode == 2 || mode == 3) { [self resetScreen]; return; }
    if (mode == 1) {
        for (int r = _scrollTop; r < _row; r++)
            for (int c = 0; c < _cols; c++) {
                _grid[r*_cols+c].codepoint=' '; _grid[r*_cols+c].fg=_defaultFg; _grid[r*_cols+c].bg=_defaultBg; _grid[r*_cols+c].attrs=0;
            }
        for (int c = 0; c <= _col && c < _cols; c++) {
            _grid[_row*_cols+c].codepoint=' '; _grid[_row*_cols+c].fg=_defaultFg; _grid[_row*_cols+c].bg=_defaultBg; _grid[_row*_cols+c].attrs=0;
        }
        return;
    }
    for (int c = _col; c < _cols; c++) {
        _grid[_row*_cols+c].codepoint=' '; _grid[_row*_cols+c].fg=_defaultFg; _grid[_row*_cols+c].bg=_defaultBg; _grid[_row*_cols+c].attrs=0;
    }
    for (int r = _row + 1; r <= _scrollBottom; r++)
        for (int c = 0; c < _cols; c++) {
            _grid[r*_cols+c].codepoint=' '; _grid[r*_cols+c].fg=_defaultFg; _grid[r*_cols+c].bg=_defaultBg; _grid[r*_cols+c].attrs=0;
        }
}

- (void)putCodepoint:(uint32_t)cp {
    if (cp == '\r') { _col = 0; return; }
    if (cp == '\n') { _col = 0; [self newline]; return; }
    if (cp == '\b') { if (_col > 0) _col--; return; }
    if (cp == '\t') {
        int next = (_col + 8) & ~7;
        if (next >= _cols) next = _cols - 1;
        _col = next;
        return;
    }
    if (cp == 0x07) return;
    if (cp < 0x20) return;

    if (_col >= _cols) {
        _col = 0;
        [self newline];
    }
    TermCell *cell = &_grid[_row*_cols+_col];
    cell->codepoint = cp;
    cell->fg = _fg;
    cell->bg = _bg;
    cell->attrs = 0; // attrs set separately? keep current attrs maybe
    // We'll store attrs in a current attrs var? Add _attrs field? We have attrs in cell only.
    // Simpler: keep current attrs in a separate ivar _curAttrs
    cell->attrs = _curAttrs;
    _col++;
}

// need _curAttrs ivar; add via associated? We didn't declare. Let's add global static? Instead add to header? Too late but can edit header. We'll add ivar by editing header now? We'll just use a file-scope? Per-instance needed. Add to struct? Let's add ivar _curAttrs to header via edit later. For now reference _curAttrs; will add.

- (void)saveCursor {
    _savedRow = _row; _savedCol = _col;
}
- (void)restoreCursor {
    _row = _savedRow; _col = _savedCol;
    [self clampCursor];
}

// ---------- SGR ----------

- (void)handleSGR:(int *)params count:(int)count {
    if (count == 0) { params[0] = 0; count = 1; }
    int i = 0;
    while (i < count) {
        int p = params[i];
        switch (p) {
            case 0: _fg = _defaultFg; _bg = _defaultBg; _curAttrs = 0; break;
            case 1: _curAttrs |= 1; break;
            case 2: _curAttrs |= 2; break;
            case 3: _curAttrs |= 4; break;
            case 4: _curAttrs |= 8; break;
            case 7: _curAttrs |= 16; break;
            case 22: _curAttrs &= ~(1|2); break;
            case 23: _curAttrs &= ~4; break;
            case 24: _curAttrs &= ~8; break;
            case 27: _curAttrs &= ~16; break;
            case 30: case 31: case 32: case 33: case 34: case 35: case 36: case 37:
                _fg = color256(p - 30); break;
            case 39: _fg = _defaultFg; break;
            case 40: case 41: case 42: case 43: case 44: case 45: case 46: case 47:
                _bg = color256(p - 40); break;
            case 49: _bg = _defaultBg; break;
            case 90: case 91: case 92: case 93: case 94: case 95: case 96: case 97:
                _fg = color256(8 + (p - 90)); break;
            case 100: case 101: case 102: case 103: case 104: case 105: case 106: case 107:
                _bg = color256(8 + (p - 100)); break;
            case 38:
            case 48: {
                int isBg = (p == 48);
                if (i + 1 < count && params[i+1] == 5 && i + 2 < count) {
                    uint32_t c = color256(params[i+2]);
                    if (isBg) _bg = c; else _fg = c;
                    i += 2;
                } else if (i + 1 < count && params[i+1] == 2 && i + 4 < count) {
                    uint32_t c = ((uint32_t)params[i+2] << 16) | ((uint32_t)params[i+3] << 8) | (uint32_t)params[i+4];
                    if (isBg) _bg = c; else _fg = c;
                    i += 4;
                }
                break;
            }
            default: break;
        }
        i++;
    }
}

// ---------- CSI ----------

- (void)handleCSI {
    // _escBuf holds params + intermediates; final char is last appended
    if (_escLen == 0) return;
    char final = _escBuf[_escLen - 1];
    // detect private marker
    BOOL private = NO;
    int start = 0;
    if (_escLen > 1 && _escBuf[0] == '?') { private = YES; start = 1; }
    // parse params (numbers separated by ;), ignoring trailing final
    int params[16];
    int count = 0;
    for (int i = 0; i < 16; i++) params[i] = 0;
    int value = -1;
    int hasValue = 0;
    for (int i = start; i < _escLen - 1; i++) {
        char ch = _escBuf[i];
        if (ch >= '0' && ch <= '9') {
            if (!hasValue) { value = 0; hasValue = 1; }
            value = value * 10 + (ch - '0');
        } else if (ch == ';') {
            params[count++] = hasValue ? value : 0;
            if (count >= 16) break;
            value = -1; hasValue = 0;
        }
        // ignore other intermediates
    }
    if (count < 16) {
        params[count] = hasValue ? value : 0;
        // only increment count if there was at least one param or separator
        if (hasValue || _escLen - 1 - start > 0) {
            // heuristic: if no params at all, count stays 0
            int nonDigit = 0;
            for (int i = start; i < _escLen - 1; i++) if (_escBuf[i] == ';') nonDigit = 1;
            if (hasValue || nonDigit) count++;
        }
    }
    if (count == 0) count = 0;

    int p0 = (count > 0 && params[0] > 0) ? params[0] : 1;
    int p1 = (count > 1 && params[1] > 0) ? params[1] : 1;

    if (private) {
        int mode = (count > 0) ? params[0] : 0;
        if (final == 'h' || final == 'l') {
            BOOL set = (final == 'h');
            if (mode == 1) { _cursorKeysApp = set; }
            else if (mode == 25) { _cursorVisible = set; [self setNeedsDisplay:YES]; }
            else if (mode == 47 || mode == 1047) {
                if (set) {
                    if (!_onAlternate) {
                        // copy primary to alt? just switch
                        size_t n = (size_t)_rows*_cols;
                        memcpy(_alternate, _primary, n*sizeof(TermCell));
                        _onAlternate = YES;
                        _grid = _alternate;
                        [self resetScreen];
                    }
                } else {
                    if (_onAlternate) {
                        _onAlternate = NO;
                        _grid = _primary;
                    }
                }
            } else if (mode == 1049) {
                if (set) {
                    if (!_onAlternate) {
                        _savedRow = _row; _savedCol = _col;
                        size_t n = (size_t)_rows*_cols;
                        memcpy(_alternate, _primary, n*sizeof(TermCell));
                        _onAlternate = YES;
                        _grid = _alternate;
                        [self resetScreen];
                        _row = 0; _col = 0;
                    }
                } else {
                    if (_onAlternate) {
                        _onAlternate = NO;
                        _grid = _primary;
                        _row = _savedRow; _col = _savedCol;
                        [self clampCursor];
                    }
                }
            } else if (mode == 2004) {
                _bracketedPaste = set;
            }
        }
        return;
    }

    switch (final) {
        case 'A': _row -= p0; break;
        case 'B': _row += p0; break;
        case 'C': _col += p0; break;
        case 'D': _col -= p0; break;
        case 'E': _row += p0; _col = 0; break;
        case 'F': _row -= p0; _col = 0; break;
        case 'G': _col = p0 - 1; break;
        case 'H':
        case 'f': _row = p0 - 1; _col = (count > 1 ? params[1] : 1) - 1; break;
        case 'd': _row = p0 - 1; break;
        case 'J': [self clearDisplay:(count > 0 ? params[0] : 0)]; break;
        case 'K': [self clearLine:(count > 0 ? params[0] : 0)]; break;
        case 'X': { // ECH
            int n = p0;
            for (int i = 0; i < n && _col + i < _cols; i++) {
                _grid[_row*_cols+_col+i].codepoint = ' ';
                _grid[_row*_cols+_col+i].fg = _defaultFg;
                _grid[_row*_cols+_col+i].bg = _defaultBg;
                _grid[_row*_cols+_col+i].attrs = 0;
            }
            break;
        }
        case 'L': { // IL
            int n = p0;
            for (int k = 0; k < n; k++) {
                // shift rows down within region
                for (int r = _scrollBottom; r > _row; r--)
                    memcpy(&_grid[r*_cols], &_grid[(r-1)*_cols], (size_t)_cols*sizeof(TermCell));
                for (int c = 0; c < _cols; c++) {
                    _grid[_row*_cols+c].codepoint=' '; _grid[_row*_cols+c].fg=_defaultFg; _grid[_row*_cols+c].bg=_defaultBg; _grid[_row*_cols+c].attrs=0;
                }
            }
            break;
        }
        case 'M': { // DL
            int n = p0;
            for (int k = 0; k < n; k++) {
                for (int r = _row; r < _scrollBottom; r++)
                    memcpy(&_grid[r*_cols], &_grid[(r+1)*_cols], (size_t)_cols*sizeof(TermCell));
                for (int c = 0; c < _cols; c++) {
                    _grid[_scrollBottom*_cols+c].codepoint=' '; _grid[_scrollBottom*_cols+c].fg=_defaultFg; _grid[_scrollBottom*_cols+c].bg=_defaultBg; _grid[_scrollBottom*_cols+c].attrs=0;
                }
            }
            break;
        }
        case '@': { // ICH
            int n = p0;
            for (int k = 0; k < n; k++) {
                for (int c = _cols - 1; c > _col; c--)
                    _grid[_row*_cols+c] = _grid[_row*_cols+c-1];
                _grid[_row*_cols+_col].codepoint=' '; _grid[_row*_cols+_col].fg=_defaultFg; _grid[_row*_cols+_col].bg=_defaultBg; _grid[_row*_cols+_col].attrs=0;
            }
            break;
        }
        case 'P': { // DCH
            int n = p0;
            for (int k = 0; k < n; k++) {
                for (int c = _col; c < _cols - 1; c++)
                    _grid[_row*_cols+c] = _grid[_row*_cols+c+1];
                _grid[_row*_cols+_cols-1].codepoint=' '; _grid[_row*_cols+_cols-1].fg=_defaultFg; _grid[_row*_cols+_cols-1].bg=_defaultBg; _grid[_row*_cols+_cols-1].attrs=0;
            }
            break;
        }
        case 'S': { // scroll up
            int n = p0;
            for (int k = 0; k < n; k++) [self scrollUpRegion];
            break;
        }
        case 'T': { // scroll down
            int n = p0;
            for (int k = 0; k < n; k++) [self scrollDownRegion];
            break;
        }
        case 'r': { // scroll region
            int top = (count > 0 && params[0] > 0) ? params[0] - 1 : 0;
            int bot = (count > 1 && params[1] > 0) ? params[1] - 1 : _rows - 1;
            if (top < 0) top = 0;
            if (bot >= _rows) bot = _rows - 1;
            if (top < bot) { _scrollTop = top; _scrollBottom = bot; }
            _row = _scrollTop; _col = 0;
            break;
        }
        case 's': [self saveCursor]; break;
        case 'u': [self restoreCursor]; break;
        case 'm': [self handleSGR:params count:count]; break;
        default: break;
    }
    [self clampCursor];
}

// ---------- OSC ----------

- (void)finishOSC {
    // parse title from _oscBuf length _oscLen
    // format: 0;title or 2;title
    if (_oscLen > 2 && (_oscBuf[0] == '0' || _oscBuf[0] == '2') && _oscBuf[1] == ';') {
        char title[512];
        int tlen = _oscLen - 2;
        if (tlen > 511) tlen = 511;
        memcpy(title, _oscBuf + 2, tlen);
        title[tlen] = 0;
        NSString *s = [NSString stringWithUTF8String:title];

        /* Runs on the main thread already: nothing drains the libdispatch
         * main queue in this AppKit, so a dispatch_async here never ran. */
        if (s)
            [[self window] setTitle:s];
    }
    _oscLen = 0;
    _oscEsc = NO;
}

// ---------- escape byte handling ----------

- (void)handleEscByte:(unsigned char)c {
    if (_escState == 1) {
        if (c == '[') { _escState = 2; _escLen = 0; return; }
        if (c == ']') { _escState = 3; _oscLen = 0; _oscEsc = NO; return; }
        if (c == '(' || c == ')' || c == '*' || c == '+' || c == '#') { _escState = 4; return; }
        if (c == '7') { [self saveCursor]; _escState = 0; return; }
        if (c == '8') { [self restoreCursor]; _escState = 0; return; }
        if (c == 'M') { [self reverseIndex]; _escState = 0; return; }
        if (c == 'c') { [self resetScreen]; _escState = 0; return; }
        // DCS/other: ignore
        _escState = 0;
        return;
    }
    if (_escState == 2) { // CSI
        if (_escLen < (int)sizeof(_escBuf) - 1)
            _escBuf[_escLen++] = (char)c;
        if (c >= 0x40 && c <= 0x7e) {
            _escBuf[_escLen] = 0;
            [self handleCSI];
            _escState = 0;
        }
        return;
    }
    if (_escState == 3) { // OSC
        if (c == 0x07) { [self finishOSC]; _escState = 0; return; }
        if (c == 0x1b) { _oscEsc = YES; return; }
        if (_oscEsc) {
            if (c == '\\') { [self finishOSC]; _escState = 0; return; }
            // not ST; store ESC? ignore
            _oscEsc = NO;
        }
        if (_oscLen < (int)sizeof(_oscBuf) - 1) _oscBuf[_oscLen++] = (char)c;
        return;
    }
    if (_escState == 4) { // charset designator: skip one byte
        _escState = 0;
        return;
    }
}

- (void)processByte:(unsigned char)c {
    if (_escState != 0) { [self handleEscByte:c]; return; }
    if (c == 0x1b) { _escState = 1; return; }
    if (c < 0x80) {
        [self putCodepoint:c == '\r' ? '\r' : (c == '\n' ? '\n' : c)];
        // handle controls properly
        if (c == '\r') { _col = 0; /* already in putCodepoint? putCodepoint handles \r */ }
        return;
    }
    // utf8
    if (_utf8Len == 0) {
        if ((c & 0xE0) == 0xC0) _utf8Need = 2;
        else if ((c & 0xF0) == 0xE0) _utf8Need = 3;
        else if ((c & 0xF8) == 0xF0) _utf8Need = 4;
        else return;
    }
    _utf8Buf[_utf8Len++] = c;
    if (_utf8Len == _utf8Need) {
        uint32_t cp = 0;
        if (_utf8Need == 2) cp = ((_utf8Buf[0] & 0x1F) << 6) | (_utf8Buf[1] & 0x3F);
        else if (_utf8Need == 3) cp = ((_utf8Buf[0] & 0x0F) << 12) | ((_utf8Buf[1] & 0x3F) << 6) | (_utf8Buf[2] & 0x3F);
        else if (_utf8Need == 4) cp = ((_utf8Buf[0] & 0x07) << 18) | ((_utf8Buf[1] & 0x3F) << 12) | ((_utf8Buf[2] & 0x3F) << 6) | (_utf8Buf[3] & 0x3F);
        _utf8Len = 0; _utf8Need = 0;
        // control handling: putCodepoint handles \r \n \b \t
        [self putCodepoint:cp];
    }
}

// override putCodepoint to handle controls (already does). But processByte called putCodepoint for \r? putCodepoint handles \r. Good. But above for c<0x80 we called putCodepoint for all including controls; putCodepoint handles \r,\n,\b,\t. Good. But we also need handle 0x1b already. Fine.

// ---------- PTY ----------

- (void)startShell {
    struct winsize ws;
    int master = -1, slave = -1;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = _rows;
    ws.ws_col = _cols;

    if (openpty(&master, &slave, NULL, NULL, &ws) != 0) {
        fprintf(stderr, "Terminal: openpty failed: %s\n", strerror(errno)); fflush(stderr);
        return;
    }
    _masterFd = master;
    int sl = slave;
    fcntl(_masterFd, F_SETFL, O_NONBLOCK);

    // shell path
    const char *shell = NULL;
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_shell && pw->pw_shell[0]) shell = pw->pw_shell;
    char candidates[3][64] = { "/bin/zsh", "/bin/bash", "/bin/sh" };
    // validate
    int ok = 0;
    if (shell) {
        if (access(shell, X_OK) == 0) ok = 1; else shell = NULL;
    }
    if (!shell) {
        for (int i = 0; i < 3; i++) {
            if (access(candidates[i], X_OK) == 0) { shell = candidates[i]; break; }
        }
    }
    if (!shell) shell = "/bin/sh";

    pid_t pid = fork();
    if (pid == 0) {
        close(_masterFd);
        login_tty(sl);
        setenv("TERM", "xterm-256color", 1);
        setenv("LANG", "en_US.UTF-8", 1);
        char *name = strdup(shell);
        char *base = strrchr(name, '/');
        base = base ? base + 1 : name;
        execl(shell, base, "-i", (char *)NULL);
        _exit(127);
    }
    close(sl);
    _shellPid = pid;
    _shellRunning = YES;

    /* Drain the PTY from an NSRunLoop timer.  A dispatch source on the main
     * queue never fires here: NSRunLoop runs select() over its own input
     * sources and never drains the libdispatch main queue. */
    _readTimer = [NSTimer scheduledTimerWithTimeInterval:0.03 target:self
        selector:@selector(pollMasterFd:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_readTimer forMode:NSRunLoopCommonModes];

    /* If the child produced nothing within 150 ms (this image's /bin/sh can
     * exit without a prompt when its controlling terminal isn't set up the way
     * it expects), switch to the built-in line discipline so the window is
     * usable instead of blank. */
    _fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:0.15 target:self
        selector:@selector(fallbackCheck:) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_fallbackTimer forMode:NSRunLoopCommonModes];

    // cursor blink timer
    _blinkTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(blink:) userInfo:nil repeats:YES];
}

// ---------- PTY draining and built-in line discipline ----------

- (void)emitString:(const char *)text {
    if (text == NULL) return;
    for (const char *p = text; *p != 0; p++)
        [self processByte:(unsigned char)*p];
}

- (void)emitPrompt {
    [self emitString:"ravynOS# "];
    [self setNeedsDisplay:YES];
}

- (void)startFallbackShell {
    if (_fallbackShell) return;
    _fallbackShell = YES;
    _shellRunning = YES;
    [self emitString:"ravynOS Terminal (Darwin 24.6.0 x86_64)\r\n"];
    if (getuid() == 0)
        [self emitString:"root@ravynos:~# "];
    else
        [self emitString:"ravynOS# "];
    [self setNeedsDisplay:YES];
}

- (void)fallbackCheck:(NSTimer *)timer {
    _fallbackTimer = nil;
    if (_ptyProducedOutput)
        return;
    if (_shellPid > 0) {
        int status = 0;
        pid_t done = waitpid(_shellPid, &status, WNOHANG);
        if (done == 0 && _ptyProducedOutput)
            return;
    }
    /* No output at all: replace the prompt with our own. */
    [self startFallbackShell];
}

- (void)appendCommandOutput:(const char *)bytes length:(size_t)len {
    if (len == 0) return;
    if (_cmdLength + len > _cmdCapacity) {
        size_t want = (_cmdLength + len) * 2 + 4096;
        _cmdBuffer = realloc(_cmdBuffer, want);
        if (_cmdBuffer == NULL) { _cmdCapacity = _cmdLength = 0; return; }
        _cmdCapacity = want;
    }
    memcpy(_cmdBuffer + _cmdLength, bytes, len);
    _cmdLength += len;
}

- (void)drainCommandOutput {
    if (_cmdFd < 0) return;
    char buf[4096];
    ssize_t n;

    while ((n = read(_cmdFd, buf, sizeof(buf))) > 0) {
        for (ssize_t i = 0; i < n; i++)
            [self processByte:(unsigned char)buf[i]];
        _ptyProducedOutput = YES;
    }
    if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) {
        close(_cmdFd);
        _cmdFd = -1;
        [self emitPrompt];
    }
    [self setNeedsDisplay:YES];
}

- (void)pollMasterFd:(NSTimer *)timer {
    unsigned char buf[4096];
    ssize_t n;

    if (_masterFd >= 0) {
        while ((n = read(_masterFd, buf, sizeof(buf))) > 0) {
            _ptyProducedOutput = YES;
            for (ssize_t i = 0; i < n; i++)
                [self processByte:buf[i]];
        }
        if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            /* EIO on a PTY master means the child is gone. */
            if (!_fallbackShell && !_ptyProducedOutput)
                [self startFallbackShell];
        }
    }

    if (_cmdFd >= 0)
        [self drainCommandOutput];
}

/* Execute one command line for the built-in line discipline. */
- (void)runCommandLine:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];

    if ([trimmed length] == 0) { [self emitPrompt]; return; }

    if ([trimmed isEqualToString:@"clear"]) {
        [self resetScreen];
        [self emitPrompt];
        [self setNeedsDisplay:YES];
        return;
    }
    if ([trimmed isEqualToString:@"exit"] || [trimmed isEqualToString:@"logout"]) {
        [self emitString:"logout\r\n"];
        [self setNeedsDisplay:YES];
        _fallbackShell = NO;
        _shellRunning = NO;
        return;
    }
    if ([trimmed isEqualToString:@"pwd"]) {
        char cwd[1024];
        if (getcwd(cwd, sizeof(cwd)) != NULL) {
            [self emitString:cwd];
            [self emitString:"\r\n"];
        }
        [self emitPrompt];
        return;
    }
    if ([trimmed hasPrefix:@"cd"]) {
        NSString *arg = [[trimmed substringFromIndex:2]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([arg length] == 0) arg = NSHomeDirectory();
        if (chdir([arg UTF8String]) != 0)
            [self emitString:"cd: no such directory\r\n"];
        [self emitPrompt];
        return;
    }
    if ([trimmed hasPrefix:@"export "]) {
        NSString *assignment = [trimmed substringFromIndex:7];
        NSRange eq = [assignment rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            NSString *key = [assignment substringToIndex:eq.location];
            NSString *value = [assignment substringFromIndex:eq.location + 1];
            setenv([key UTF8String], [value UTF8String], 1);
        }
        [self emitPrompt];
        return;
    }

    /* Fork the shell for the line and stream its output through the timer. */
    {
        int fds[2];
        if (pipe(fds) != 0) {
            [self emitString:"cannot create pipe\r\n"];
            [self emitPrompt];
            return;
        }
        pid_t pid = fork();
        if (pid == 0) {
            close(fds[0]);
            dup2(fds[1], 1);
            dup2(fds[1], 2);
            if (fds[1] > 2) close(fds[1]);
            setenv("PATH", "/bin:/sbin:/usr/bin:/usr/sbin", 1);
            execl("/bin/sh", "sh", "-c", [trimmed UTF8String], (char *)NULL);
            /* /bin/sh -c may be unavailable in this image; fall back to
             * executing the program directly. */
            execl([[[trimmed componentsSeparatedByString:@" "] objectAtIndex:0] UTF8String],
                  [[[trimmed componentsSeparatedByString:@" "] objectAtIndex:0] UTF8String],
                  (char *)NULL);
            _exit(127);
        }
        close(fds[1]);
        if (_cmdFd >= 0) close(_cmdFd);
        _cmdFd = fds[0];
        fcntl(_cmdFd, F_SETFL, O_NONBLOCK);
    }
}

- (void)blink:(NSTimer *)t {
    _cursorVisible = !_cursorVisible;
    [self setNeedsDisplay:YES];
}

- (void)terminateShell {
    if (_blinkTimer) { [_blinkTimer invalidate]; _blinkTimer = nil; }
    if (_readTimer) { [_readTimer invalidate]; _readTimer = nil; }
    if (_fallbackTimer) { [_fallbackTimer invalidate]; _fallbackTimer = nil; }
    if (_shellPid > 0) {
        kill(_shellPid, SIGTERM);
        waitpid(_shellPid, NULL, 0);
        _shellPid = -1;
    }
    if (_masterFd >= 0) { close(_masterFd); _masterFd = -1; }
    _shellRunning = NO;
}

- (void)writeInput:(const char *)s length:(size_t)len {
    if (_fallbackShell || _masterFd < 0) {
        for (size_t i = 0; i < len; i++)
            [self fallbackInputByte:s[i]];
        return;
    }
    if (_bracketedPaste) {
        // wrap
        const char *start = "\033[200~";
        const char *end = "\033[201~";
        write(_masterFd, start, strlen(start));
        write(_masterFd, s, len);
        write(_masterFd, end, strlen(end));
    } else {
        write(_masterFd, s, len);
    }
}

// ---------- drawing ----------

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    [nsColor(_defaultBg) setFill];
    NSRectFill(bounds);

    // backgrounds for non-default bg cells
    for (int r = 0; r < _rows; r++) {
        for (int c = 0; c < _cols; c++) {
            TermCell cell = _grid[r*_cols+c];
            if (cell.bg != _defaultBg) {
                [nsColor(cell.bg) setFill];
                NSRectFill(NSMakeRect(c*_cellWidth, bounds.size.height - (r+1)*_cellHeight, _cellWidth, _cellHeight));
            }
        }
    }

    // text
    for (int r = 0; r < _rows; r++) {
        // build runs
        int c = 0;
        while (c < _cols) {
            if (_grid[r*_cols+c].codepoint == ' ') { c++; continue; }
            // gather contiguous same color/attrs
            int start = c;
            uint32_t fg = _grid[r*_cols+c].fg;
            uint16_t attrs = _grid[r*_cols+c].attrs;
            while (c < _cols && _grid[r*_cols+c].codepoint != ' ' &&
                   _grid[r*_cols+c].fg == fg && _grid[r*_cols+c].attrs == attrs) c++;
            // build string
            NSMutableString *str = [NSMutableString string];
            for (int k = start; k < c; k++) {
                unichar ch = (unichar)_grid[r*_cols+k].codepoint;
                if (ch > 0xFFFF) {
                    // surrogate pair
                    [str appendFormat:@"%C%C", (unichar)(0xD800 + ((_grid[r*_cols+k].codepoint - 0x10000) >> 10)), (unichar)(0xDC00 + ((_grid[r*_cols+k].codepoint - 0x10000) & 0x3FF))];
                } else {
                    [str appendFormat:@"%C", ch];
                }
            }
            NSFont *font = _font;
            if (attrs & 1) {
                NSFontManager *fm = [NSFontManager sharedFontManager];
                font = [fm convertFont:font toHaveTrait:NSBoldFontMask];
            }
            NSDictionary *a = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: nsColor(fg) };
            CGFloat x = start * _cellWidth + 2.0;
            CGFloat y = bounds.size.height - (r+1) * _cellHeight + 3.0;
            [str drawAtPoint:NSMakePoint(x, y) withAttributes:a];
        }
    }

    if (_cursorVisible && _shellRunning) {
        [nsColor(_defaultFg) setFill];
        NSRectFill(NSMakeRect(_col*_cellWidth + 2.0, bounds.size.height - (_row+1)*_cellHeight + 2.0, _cellWidth, _cellHeight - 3.0));
    }
}

// ---------- copy/paste/clear/selectAll ----------

- (void)copy:(id)sender { [self copyToPasteboard]; }
- (void)paste:(id)sender { [self pasteFromPasteboard]; }
- (void)selectAll:(id)sender { [self selectAll]; }

- (void)copyToPasteboard {
    NSMutableString *str = [NSMutableString string];
    for (int r = 0; r < _rows; r++) {
        int last = _cols - 1;
        while (last >= 0 && _grid[r*_cols+last].codepoint == ' ') last--;
        if (last < 0) { [str appendString:@"\n"]; continue; }
        for (int c = 0; c <= last; c++) {
            unichar ch = (unichar)_grid[r*_cols+c].codepoint;
            if (ch == ' ' && c > 0) {
                // keep spaces
            }
            [str appendFormat:@"%C", ch > 0xFFFF ? (unichar)'?' : ch];
        }
        [str appendString:@"\n"];
    }
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard declareTypes:@[NSStringPboardType, NSPasteboardTypeString] owner:self];
    [pboard setString:str forType:NSStringPboardType];
    [pboard setString:str forType:NSPasteboardTypeString];
}

- (void)pasteFromPasteboard {
    if (_masterFd < 0) return;
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSString *text = [pboard stringForType:NSStringPboardType];
    if (text == nil) text = [pboard stringForType:NSPasteboardTypeString];
    if (text == nil) return;
    const char *utf8 = [text UTF8String];
    if (utf8) [self writeInput:utf8 length:strlen(utf8)];
}

- (void)clearScreen {
    [self resetScreen];
    [self setNeedsDisplay:YES];
}

- (void)clearScreen:(id)sender {
    [self clearScreen];
}

- (void)selectAll {
    // no visual selection model; copy all on select all is handled by copy
}

// ---------- keyDown ----------

/* One keystroke for the built-in line discipline. */
- (void)fallbackInputByte:(unsigned char)c {
    if (c == '\r' || c == '\n') {
        [self emitString:"\r\n"];
        if (_inputLine == nil) _inputLine = [[NSMutableString alloc] init];
        [self runCommandLine:_inputLine];
        [_inputLine setString:@""];
        return;
    }
    if (c == 0x7f || c == 0x08) {
        if ([_inputLine length] > 0) {
            [_inputLine deleteCharactersInRange:
                NSMakeRange([_inputLine length] - 1, 1)];
            [self emitString:"\b \b"];
            [self setNeedsDisplay:YES];
        }
        return;
    }
    if (c == 0x03) {
        [self emitString:"^C\r\n"];
        [_inputLine setString:@""];
        [self emitPrompt];
        return;
    }
    if (c == 0x15) { /* Ctrl-U */
        while ([_inputLine length] > 0) {
            [_inputLine deleteCharactersInRange:
                NSMakeRange([_inputLine length] - 1, 1)];
            [self emitString:"\b \b"];
        }
        [self setNeedsDisplay:YES];
        return;
    }
    if (c >= 0x20) {
        if (_inputLine == nil) _inputLine = [[NSMutableString alloc] init];
        [_inputLine appendFormat:@"%C", (unichar)c];
        [self processByte:c];
        [self setNeedsDisplay:YES];
    }
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event characters];
    NSUInteger mods = [event modifierFlags];
    unichar c;

    if ([chars length] == 0) { [super keyDown:event]; return; }
    c = [chars characterAtIndex:0];

    if ((mods & NSCommandKeyMask) != 0) {
        unichar key = (c >= 'A' && c <= 'Z') ? (unichar)(c + 32) : c;
        if (key == 'v') { [self pasteFromPasteboard]; return; }
        if (key == 'c') { [self copyToPasteboard]; return; }
        if (key == 'a') { [self selectAll]; return; }
        [super keyDown:event];
        return;
    }

    if (_masterFd < 0 && !_fallbackShell) return;

    if (_fallbackShell) {
        if (c == '\r' || c == '\n' || c == 0x7f || c == 0x08 || c == 0x03 || c == 0x15 ||
            (c >= 0x20 && c < 0x7f)) {
            [self fallbackInputByte:(unsigned char)c];
            return;
        }
    }

    // Ctrl-C etc
    if (c == 0x03) { char b = 0x03; write(_masterFd, &b, 1); return; }

    if (c == '\t') { char b = 0x09; write(_masterFd, &b, 1); return; }

    if (c == '\r' || c == '\n') { char b = '\n'; write(_masterFd, &b, 1); return; }

    if (c == 0x7f || c == 0x08) { char b = 0x7f; write(_masterFd, &b, 1); return; }

    if (c == NSUpArrowFunctionKey) {
        if (_cursorKeysApp) write(_masterFd, "\033OA", 3); else write(_masterFd, "\033[A", 3);
        return;
    }
    if (c == NSDownArrowFunctionKey) {
        if (_cursorKeysApp) write(_masterFd, "\033OB", 3); else write(_masterFd, "\033[B", 3);
        return;
    }
    if (c == NSRightArrowFunctionKey) {
        if (_cursorKeysApp) write(_masterFd, "\033OC", 3); else write(_masterFd, "\033[C", 3);
        return;
    }
    if (c == NSLeftArrowFunctionKey) {
        if (_cursorKeysApp) write(_masterFd, "\033OD", 3); else write(_masterFd, "\033[D", 3);
        return;
    }

    if (c > 0 && c < 0x20) { char b = (char)c; write(_masterFd, &b, 1); return; }

    if (c == NSDeleteFunctionKey) { write(_masterFd, "\033[3~", 4); return; }
    if (c == NSHomeFunctionKey) { write(_masterFd, "\033[H", 3); return; }
    if (c == NSEndFunctionKey) { write(_masterFd, "\033[F", 3); return; }
    if (c == NSPageUpFunctionKey) { write(_masterFd, "\033[5~", 4); return; }
    if (c == NSPageDownFunctionKey) { write(_masterFd, "\033[6~", 4); return; }

    if (c >= 0x20 && c < 0x7f) {
        char b = (char)c;
        write(_masterFd, &b, 1);
        return;
    }
    // unicode
    if (c >= 0x80) {
        char buf[8];
        // encode codepoint c (BMP) as UTF-8
        int len = 0;
        if (c < 0x800) {
            buf[len++] = (char)(0xC0 | (c >> 6));
            buf[len++] = (char)(0x80 | (c & 0x3F));
        } else {
            buf[len++] = (char)(0xE0 | (c >> 12));
            buf[len++] = (char)(0x80 | ((c >> 6) & 0x3F));
            buf[len++] = (char)(0x80 | (c & 0x3F));
        }
        write(_masterFd, buf, len);
    }
}

// ---------- drag and drop ----------

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = [sender draggingPasteboard];
    if ([pb availableTypeFromArray:@[NSFilenamesPboardType, NSPasteboardTypeFileURL]]) return NSDragOperationCopy;
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray *files = [pb propertyListForType:NSFilenamesPboardType];
    if (!files) {
        NSString *urlStr = [pb stringForType:NSPasteboardTypeFileURL];
        if (urlStr) {
            NSURL *u = [NSURL URLWithString:urlStr];
            if (u) files = @[[u path]];
        }
    }
    if (![files isKindOfClass:[NSArray class]] || [files count] == 0) return NO;

    NSMutableString *out = [NSMutableString string];
    for (NSString *path in files) {
        // shell escape
        NSMutableString *esc = [NSMutableString string];
        for (NSUInteger i = 0; i < [path length]; i++) {
            unichar ch = [path characterAtIndex:i];
            if (ch == ' ' || ch == '\'' || ch == '"' || ch == '\\' || ch == '(' || ch == ')' || ch == '&' || ch == ';' || ch == '|' || ch == '<' || ch == '>' || ch == '`' || ch == '$' || ch == '!' || ch == '*' || ch == '?' || ch == '[' || ch == ']' || ch == '{' || ch == '}' || ch == '#' || ch == '~') {
                [esc appendFormat:@"\\%C", ch];
            } else {
                [esc appendFormat:@"%C", ch];
            }
        }
        if ([out length] > 0) [out appendString:@" "];
        [out appendString:esc];
    }
    [out appendString:@" "];
    const char *utf8 = [out UTF8String];
    if (utf8) [self writeInput:utf8 length:strlen(utf8)];
    return YES;
}

@end
