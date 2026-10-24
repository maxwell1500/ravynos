/*
 * WSInput.m -- WindowServer input handling.
 *
 * The event source is Linux-only: libinput over udev, with the keymap
 * coming from xkbcommon. ravynOS has no /dev/input provider (the kernel
 * creates no input nodes) and WindowServer is not linked against libinput,
 * so on Darwin the whole event path is compiled out and the class degrades
 * to a no-op that still answers the geometry/pointer accessors WindowServer
 * calls. The xkb keymap code is cross-platform and stays.
 */

#include <mach/mach.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
#import "common.h"
#import "message.h"
#import "WSInput.h"

double clipTo(double val, double min, double max) {
    if(val < min) val = min;
    else if(val > max) val = max;
    return val;
}

static unichar translateKeySym(xkb_keysym_t keysym) {
     switch(keysym) {
        case XKB_KEY_Home:
        case XKB_KEY_KP_Home: return NSHomeFunctionKey;
        case XKB_KEY_Left:
        case XKB_KEY_KP_Left: return NSLeftArrowFunctionKey;
        case XKB_KEY_Up:
        case XKB_KEY_KP_Up: return NSUpArrowFunctionKey;
        case XKB_KEY_Right:
        case XKB_KEY_KP_Right: return NSRightArrowFunctionKey;
        case XKB_KEY_Down:
        case XKB_KEY_KP_Down: return NSDownArrowFunctionKey;
        default: return 0;
    }
}

#if !defined(__linux__)
/*
 * AT scan code set 1 (make codes) -> US keyboard layout. Index is the make
 * code. 0 means no printable character.
 */
static const char kbd_unshifted[0x54] = {
    /* 0x00 */ 0, 0x1b, '1', '2', '3', '4', '5', '6',
    /* 0x08 */ '7', '8', '9', '0', '-', '=', 0x7f, '\t',
    /* 0x10 */ 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i',
    /* 0x18 */ 'o', 'p', '[', ']', '\r', 0, 'a', 's',
    /* 0x20 */ 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';',
    /* 0x28 */ '\'', '`', 0, '\\', 'z', 'x', 'c', 'v',
    /* 0x30 */ 'b', 'n', 'm', ',', '.', '/', 0, '*',
    /* 0x38 */ 0, ' ', 0, 0, 0, 0, 0, 0,
    /* 0x40 */ 0, 0, 0, 0, 0, 0, 0, '7',
    /* 0x48 */ '8', '9', '-', '4', '5', '6', '+', '1',
    /* 0x50 */ '2', '3', '0', '.'
};

static const char kbd_shifted[0x54] = {
    /* 0x00 */ 0, 0x1b, '!', '@', '#', '$', '%', '^',
    /* 0x08 */ '&', '*', '(', ')', '_', '+', 0x7f, '\t',
    /* 0x10 */ 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I',
    /* 0x18 */ 'O', 'P', '{', '}', '\r', 0, 'A', 'S',
    /* 0x20 */ 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':',
    /* 0x28 */ '"', '~', 0, '|', 'Z', 'X', 'C', 'V',
    /* 0x30 */ 'B', 'N', 'M', '<', '>', '?', 0, '*',
    /* 0x38 */ 0, ' ', 0, 0, 0, 0, 0, 0,
    /* 0x40 */ 0, 0, 0, 0, 0, 0, 0, '7',
    /* 0x48 */ '8', '9', '-', '4', '5', '6', '+', '1',
    /* 0x50 */ '2', '3', '0', '.'
};

/* Arrow/home keys map to the AppKit private-use symbols */
static unichar kbd_arrowsym(uint8_t make) {
    switch(make) {
        case 0x48: return NSUpArrowFunctionKey;
        case 0x50: return NSDownArrowFunctionKey;
        case 0x4B: return NSLeftArrowFunctionKey;
        case 0x4D: return NSRightArrowFunctionKey;
        case 0x47: return NSHomeFunctionKey;
        default: return 0;
    }
}

/* Encode one BMP code point as UTF-8 into out (must hold 4 bytes), NUL-filled */
static void ws_unichar_to_utf8(unichar ch, char *out) {
    memset(out, 0, 4);
    if(ch < 0x80) {
        out[0] = (char)ch;
    } else if(ch < 0x800) {
        out[0] = (char)(0xC0 | (ch >> 6));
        out[1] = (char)(0x80 | (ch & 0x3F));
    } else {
        out[0] = (char)(0xE0 | (ch >> 12));
        out[1] = (char)(0x80 | ((ch >> 6) & 0x3F));
        out[2] = (char)(0x80 | (ch & 0x3F));
    }
}
#endif /* !__linux__ */

@implementation WSInput

-init {
#if defined(__linux__)
    udev = udev_new();
    li = libinput_udev_create_context(&interface, NULL, udev);
    libinput_udev_assign_seat(li, "seat0");
#else
    mouseFd = open("/dev/mouse", O_RDONLY | O_NONBLOCK);
    if(mouseFd < 0) {
        mouseFd = open("/dev/psm0", O_RDONLY | O_NONBLOCK);
    }
    if(mouseFd >= 0) {
        write(2, "[WSInput] opened /dev/mouse successfully\n", 41);
    } else {
        write(2, "[WSInput] /dev/mouse not available\n", 35);
    }
    kbdFd = open("/dev/keyboard", O_RDONLY | O_NONBLOCK);
    if(kbdFd < 0) {
        kbdFd = open("/dev/kbd", O_RDONLY | O_NONBLOCK);
    }
    if(kbdFd >= 0) {
        write(2, "[WSInput] opened /dev/keyboard successfully\n", 44);
    } else {
        write(2, "[WSInput] /dev/keyboard not available\n", 39);
    }
    kbdExtended = NO;
    shiftDown = NO;
    ctrlDown = NO;
    altDown = NO;
    capsLockOn = NO;
    cmdDown = NO;
    packetBytes = 0;
    trackingSpeed = 1.0f;
    naturalScrolling = NO;
    swapCmdOpt = NO;
    capsLockAction = 0;
    [self reloadInputPreferences];
#endif

#if defined(__linux__)
    xkbCtx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    xkb_state = xkb_state_unmodified = NULL;
    xkb_keymap = NULL;
    [self setKeymap];
#else
    xkbCtx = NULL;
    xkb_state = xkb_state_unmodified = NULL;
    xkb_keymap = NULL;
#endif

    return self;
}

-(void)dealloc {
    xkb_keymap_unref(xkb_keymap);
    xkb_state_unref(xkb_state);
    xkb_state_unref(xkb_state_unmodified);
    xkb_context_unref(xkbCtx);
#if defined(__linux__)
    libinput_unref(li);
    udev_unref(udev);
#else
    if(mouseFd >= 0) {
        close(mouseFd);
        mouseFd = -1;
    }
#endif
}
-(void)setLogLevel:(int)level {
    logLevel = level;
}

/* Input preferences written by System Preferences (Keyboard & Mouse pane).
 * Called at startup and again whenever WindowServer forwards
 * CODE_PREFS_CHANGED, so tracking speed and modifier remapping take effect
 * without restarting the session. */
-(void)reloadInputPreferences {
#if !defined(__linux__)
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/Library/Preferences/com.ravynos.Input.plist"];
    id value;

    if(prefs == nil)
        return;

    value = [prefs objectForKey:@"TrackingSpeed"];
    if(value != nil) {
        float speed = [value floatValue];
        if(speed < 0.25f) speed = 0.25f;
        if(speed > 3.0f) speed = 3.0f;
        trackingSpeed = speed;
    }

    value = [prefs objectForKey:@"NaturalScrolling"];
    if(value != nil)
        naturalScrolling = [value boolValue];

    value = [prefs objectForKey:@"SwapCmdOpt"];
    if(value != nil)
        swapCmdOpt = [value boolValue];

    {
        NSString *action = [prefs objectForKey:@"CapsLockAction"];
        if([action isEqualToString:@"Control"]) capsLockAction = 1;
        else if([action isEqualToString:@"Escape"]) capsLockAction = 2;
        else if([action isEqualToString:@"No Action"]) capsLockAction = 3;
        else capsLockAction = 0;
    }
#endif
}

-(void)setDebugLevel:(int)level {
    logLevel = level;
#if defined(__linux__)
    switch(level) {
        case WS_WARNING: level = LIBINPUT_LOG_PRIORITY_INFO; break;
        case WS_INFO: level = LIBINPUT_LOG_PRIORITY_DEBUG; break; 
        default: level = LIBINPUT_LOG_PRIORITY_ERROR;
    }
    libinput_log_set_priority(li, level);
#endif
}

#if defined(__linux__)

-(int)run:(id)target {
    struct libinput_event *event = NULL;
    int events = 0;

    libinput_dispatch(li);
    while((event = libinput_get_event(li)) != NULL) {
        [self processEvent:event target:target];
        libinput_event_destroy(event);
        libinput_dispatch(li);
        ++events;
    }
    return events;
}

/* event is destroyed after this function returns */
-(void)processEvent:(struct libinput_event *)event target:(NSObject *)target {
    enum libinput_event_type etype = libinput_event_get_type(event);
    if(logLevel > WS_INFO)
        NSLog(@"input event: device %s type %d",
        libinput_device_get_name(libinput_event_get_device(event)), etype);
    
    struct mach_event me;
    memset(&me, 0, sizeof(struct mach_event));

    switch(etype) {
        case LIBINPUT_EVENT_KEYBOARD_KEY: {
            struct libinput_event_keyboard *ke = libinput_event_get_keyboard_event(event);
            uint32_t keycode = libinput_event_keyboard_get_key(ke);
            enum libinput_key_state state = libinput_event_keyboard_get_key_state(ke);
            if(logLevel >= WS_INFO)
                NSLog(@"Input event: type=KEY key=%u state=%u", keycode, state);

            keycode += 8; // evdev keycode offset
            xkb_keysym_t sym = xkb_state_key_get_one_sym(xkb_state, keycode);
            if(sym == XKB_KEY_NoSymbol)
                return;
            xkb_state_update_key(xkb_state, keycode, state == LIBINPUT_KEY_STATE_PRESSED
                    ? XKB_KEY_DOWN : XKB_KEY_UP);
            unichar nskey = translateKeySym(sym);
        /* The keysym for the digit keys is XKB_KEY_3/4/5; with Shift held the
         * server reports the shifted symbol (#, $, %).  Accept both. */
        if((sym == XKB_KEY_3 || sym == XKB_KEY_numbersign ||
            sym == XKB_KEY_4 || sym == XKB_KEY_dollar ||
            sym == XKB_KEY_5 || sym == XKB_KEY_percent) &&
           cmdDown && shiftDown) {
            if(sym == XKB_KEY_3 || sym == XKB_KEY_numbersign)
                [target captureScreenshotWithMode:0];
            else if(sym == XKB_KEY_4 || sym == XKB_KEY_dollar)
                [target captureScreenshotWithMode:1];
            else
                [target captureScreenshotWithMode:2];
            return;
        }

            me.code = (state == LIBINPUT_KEY_STATE_PRESSED ? NSKeyDown : NSKeyUp);
            me.keycode = keycode;
            me.mods = [self modifierFlagsForState:xkb_state];
            me.state = me.code;

            // Intercept keycodes reserved for WindowServer itself
            if(me.mods == (NSCommandKeyMask|NSShiftKeyMask) && nskey == 'Q') { // FIXME: remove
                [target signalQuit];
                return;
            }
            /* Global screen capture: Cmd+Shift+3 (whole display),
             * Cmd+Shift+4 (selection) and Cmd+Shift+5 (HUD). */
            if(me.mods == (NSCommandKeyMask | NSShiftKeyMask) && me.code == NSKeyDown &&
               (nskey == '3' || nskey == '4' || nskey == '5')) {
                [target captureScreenshotWithMode:(nskey - '0')];
                return;
            }
            if((me.mods == NSCommandKeyMask) && sym == XKB_KEY_Tab) {
                if(me.code == NSKeyDown)
                    [target switchApp];
                return;
            }

            if(nskey == sym) { // we did not translate, look up the utf8
                char buf[8];
                xkb_state_key_get_utf8(xkb_state, keycode, buf, sizeof(buf));
                memcpy(me.chars, buf, sizeof(me.chars));
                xkb_state_key_get_utf8(xkb_state_unmodified, keycode, buf, sizeof(buf));
                memcpy(me.charsIg, buf, sizeof(me.charsIg));
            } else {
                memset(me.chars, 0, sizeof(me.chars));
                utf16_to_utf8(nskey, me.chars);
                memcpy(me.charsIg, me.chars, sizeof(me.charsIg));
            }

            // FIXME: handle autorepeat
            me.repeat = 0;

            [target sendEventToApp:&me];
            break;
        }
        case LIBINPUT_EVENT_POINTER_MOTION: {
            if(buttonDown[0] == YES)
                me.code = NSLeftMouseDragged;
            else if(buttonDown[1] == YES)
                me.code = NSRightMouseDragged;
            else
                me.code = NSMouseMoved;
            struct libinput_event_pointer *pe = libinput_event_get_pointer_event(event);
            me.dx = libinput_event_pointer_get_dx_unaccelerated(pe);
            me.dy = (-1) * libinput_event_pointer_get_dy_unaccelerated(pe); // our origin is lower left
            me.mods = [self modifierFlagsForState:xkb_state];
            pointerX = clipTo(pointerX + me.dx, geometry.origin.x, geometry.size.width);
            pointerY = clipTo(pointerY + me.dy, geometry.origin.y, geometry.size.height);
            me.x = pointerX;
            me.y = pointerY;
            if(logLevel >= WS_INFO)
                NSLog(@"Input event: type=MOTION dx=%.2f dy=%.2f pos=%.2f,%.2f", me.dx, me.dy,
                        pointerX, pointerY);

            [target sendEventToApp:&me];
            break;
        }
        case LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE: {
            if(buttonDown[0] == YES)
                me.code = NSLeftMouseDragged;
            else if(buttonDown[1] == YES)
                me.code = NSRightMouseDragged;
            else
                me.code = NSMouseMoved;
            struct libinput_event_pointer *pe = libinput_event_get_pointer_event(event);
            me.mods = [self modifierFlagsForState:xkb_state];
            me.x = libinput_event_pointer_get_absolute_x_transformed(pe, geometry.size.width);
            me.y = geometry.size.height -
                libinput_event_pointer_get_absolute_y_transformed(pe, geometry.size.height);
            pointerX = me.x;
            pointerY = me.y;
            if(logLevel >= WS_INFO)
                NSLog(@"Input event: type=MOTION x=%.2f y=%.2f", me.x, me.y);

            [target sendEventToApp:&me];
            break;
        }
        case LIBINPUT_EVENT_POINTER_BUTTON: {
            struct libinput_event_pointer *pe = libinput_event_get_pointer_event(event);
            uint32_t button = libinput_event_pointer_get_button(pe);
            uint32_t state = libinput_event_pointer_get_button_state(pe);
            if(logLevel >= WS_INFO)
                NSLog(@"Input event: type=BUTTON button=%u state=%u", button, state);
            if(button == BTN_LEFT)
                me.code = (state == 1) ? NSLeftMouseDown : NSLeftMouseUp;
            else if(button == BTN_RIGHT)
                me.code = (state == 1) ? NSRightMouseDown : NSRightMouseUp;
            else
                return;
            buttonDown[button == BTN_LEFT ? 0 : 1] = (BOOL)state;
            me.mods = [self modifierFlagsForState:xkb_state];
            me.x = pointerX;
            me.y = pointerY;

            [target sendEventToApp:&me];
            break;
        }
        case LIBINPUT_EVENT_POINTER_SCROLL_WHEEL:
        case LIBINPUT_EVENT_POINTER_SCROLL_FINGER:
        case LIBINPUT_EVENT_POINTER_SCROLL_CONTINUOUS:
            if(logLevel >= WS_INFO)
                NSLog(@"scroll event");
            break;
        case LIBINPUT_EVENT_NONE:
            return;

        case LIBINPUT_EVENT_DEVICE_ADDED:
        case LIBINPUT_EVENT_DEVICE_REMOVED:
        case LIBINPUT_EVENT_TOUCH_DOWN:
        case LIBINPUT_EVENT_TOUCH_UP:
        case LIBINPUT_EVENT_TOUCH_MOTION:
        case LIBINPUT_EVENT_TOUCH_CANCEL:
        case LIBINPUT_EVENT_TOUCH_FRAME:
            if(logLevel >= WS_INFO)
                NSLog(@"touch event");
            break;

        case LIBINPUT_EVENT_GESTURE_SWIPE_BEGIN:
        case LIBINPUT_EVENT_GESTURE_SWIPE_UPDATE:
        case LIBINPUT_EVENT_GESTURE_SWIPE_END:
        case LIBINPUT_EVENT_GESTURE_PINCH_BEGIN:
        case LIBINPUT_EVENT_GESTURE_PINCH_UPDATE:
        case LIBINPUT_EVENT_GESTURE_PINCH_END:
        case LIBINPUT_EVENT_GESTURE_HOLD_BEGIN:
        case LIBINPUT_EVENT_GESTURE_HOLD_END:
            if(logLevel >= WS_INFO)
                NSLog(@"gesture event");
            return;

        default:
            if(logLevel >= WS_WARNING)
                NSLog(@"Unhandled input event type %u", etype);
            return;
    }
}

-(int)fileDescriptor {
    return libinput_get_fd(li);
}

#else /* !__linux__ */

-(int)fileDescriptor {
    return mouseFd;
}

-(int)keyboardFileDescriptor {
    return kbdFd;
}

/*
 * Translate one raw AT scan code (set 1) into an NSEvent and hand it to the
 * WindowServer for delivery to the focused window's app.
 */
-(void)processKeyByte:(uint8_t)code target:(NSObject *)target {
    struct mach_event me;
    memset(&me, 0, sizeof(me));

    if(code == 0xE0 || code == 0xE1) { // extended prefix, next byte is the key
        kbdExtended = YES;
        return;
    }

    BOOL released = (code & 0x80) ? YES : NO;
    uint8_t make = code & 0x7F;

    switch(make) {
        case 0x2A: // L shift
        case 0x36: // R shift
            shiftDown = !released;
            kbdExtended = NO;
            return;
        case 0x1D: // ctrl (L, or R when 0xE0-prefixed)
            ctrlDown = !released;
            kbdExtended = NO;
            return;
        case 0x38: // alt (L, or R when 0xE0-prefixed)
            altDown = !released;
            kbdExtended = NO;
            return;
        case 0x5B: // L GUI / Command
        case 0x5C: // R GUI / Command
            cmdDown = !released;
            kbdExtended = NO;
            return;
        case 0x3A: // caps lock
            /* The Keyboard pane may remap Caps Lock.  Remap 0 toggles the
             * modifier (the stock behaviour); the others synthesize the
             * chosen key instead. */
            if(capsLockAction == 0) {
                if(!released)
                    capsLockOn = !capsLockOn;
                kbdExtended = NO;
                return;
            }
            if(capsLockAction == 3) { /* No Action */
                kbdExtended = NO;
                return;
            }
            if(capsLockAction == 1) {
                ctrlDown = !released;
                kbdExtended = NO;
                return;
            }
            /* Escape */
            make = 0x01;
            break;
        default:
            break;
    }
    kbdExtended = NO;

    /* Global capture shortcuts.  These must be handled before the event is
     * forwarded: the focused app would otherwise receive Cmd+Shift+3/4/5 and
     * the capture would never happen. */
    if(!released && cmdDown && shiftDown) {
        if(make == 0x04) { /* 3 */
            [target captureScreenshotWithMode:0];
            return;
        }
        if(make == 0x05) { /* 4 */
            [target captureScreenshotWithMode:1];
            return;
        }
        if(make == 0x06) { /* 5 */
            [target captureScreenshotWithMode:2];
            return;
        }
    }

    me.code = released ? NSKeyUp : NSKeyDown;
    me.keycode = make;
    me.repeat = 0;
    me.x = pointerX;
    me.y = pointerY;
    me.mods = (shiftDown ? NSShiftKeyMask : 0)
        | (ctrlDown ? NSControlKeyMask : 0)
        | (((swapCmdOpt ? cmdDown : altDown)) ? NSAlternateKeyMask : 0)
        | (((swapCmdOpt ? altDown : cmdDown)) ? NSCommandKeyMask : 0)
        | (capsLockOn ? NSAlphaShiftKeyMask : 0);
    unichar sym = kbd_arrowsym(make);
    if(sym != 0) {
        ws_unichar_to_utf8(sym, (char *)me.chars);
        memcpy(me.charsIg, me.chars, sizeof(me.charsIg));
    } else {
        char ch = 0;
        char unshifted = 0;
        if(make < sizeof(kbd_unshifted)) {
            unshifted = kbd_unshifted[make];
            ch = shiftDown ? kbd_shifted[make] : unshifted;
            // Caps Lock only affects letters
            if(capsLockOn && ch >= 'a' && ch <= 'z')
                ch -= 32;
            else if(capsLockOn && ch >= 'A' && ch <= 'Z')
                ch += 32;
        }
        if(ch != 0) {
            me.chars[0] = ch;
            me.chars[1] = 0;
            /* charactersIgnoringModifiers must not carry the shift result:
             * Cmd+Shift+. arrives as '>' in chars and '.' here, and AppKit's
             * hidden-file toggle matches on '.'. */
            me.charsIg[0] = (unshifted != 0) ? unshifted : ch;
            me.charsIg[1] = 0;
        }
    }

    [target sendEventToApp:&me];
}

-(int)runKeyboard:(NSObject *)target {
    int bytes = 0;
    if(kbdFd < 0)
        return 0;

    uint8_t buf[128];
    ssize_t n;
    while((n = read(kbdFd, buf, sizeof(buf))) > 0) {
        for(ssize_t i = 0; i < n; i++) {
            char kb[64]; int kn = snprintf(kb, sizeof(kb), "[KBD] byte 0x%02x\n", buf[i]);
            if(kn>0) write(2, kb, kn);
            [self processKeyByte:buf[i] target:target];
        }
        bytes += (int)n;
    }
    return bytes;
}

-(int)run:(id)target {
    int events = [self runKeyboard:target];

    if(mouseFd < 0)
        return events;

    uint8_t buf[64];
    ssize_t n;
    int accumDx = 0, accumDy = 0;

    while((n = read(mouseFd, buf, sizeof(buf))) > 0) {
        for(ssize_t i = 0; i < n; i++) {
            uint8_t b = buf[i];
            packetBuf[packetBytes++] = b;

            /* Standard PS/2 packet decoding: bit 3 of first byte must be 1 */
            if(packetBytes == 1 && !(b & 0x08)) {
                packetBytes = 0;
                continue;
            }

            if(packetBytes < 3)
                continue;

            /* Full 3-byte packet received */
            packetBytes = 0;
            uint8_t b0 = packetBuf[0];
            uint8_t b1 = packetBuf[1];
            uint8_t b2 = packetBuf[2];

            int rawDx = (int)b1 - ((b0 & 0x10) ? 256 : 0);
            int rawDy = (int)b2 - ((b0 & 0x20) ? 256 : 0);

            float speed = sqrtf((float)(rawDx * rawDx + rawDy * rawDy));
            float scale = 2.5f * trackingSpeed;
            if(naturalScrolling) {
                rawDx = -rawDx;
                rawDy = -rawDy;
            }
            if (speed > 5.0f) {
                scale *= (1.0f + 0.1f * speed);
                if (scale > 5.0f)
                    scale = 5.0f;
            }
            int dx = (int)roundf(rawDx * scale);
            int dy = (int)roundf(rawDy * scale);

            BOOL leftBtn = (b0 & 0x01) ? YES : NO;
            BOOL rightBtn = (b0 & 0x02) ? YES : NO;

            pointerX = clipTo(pointerX + dx, geometry.origin.x, geometry.size.width);
            pointerY = clipTo(pointerY + dy, geometry.origin.y, geometry.size.height);

            BOOL leftEdge = (leftBtn != buttonDown[0]);
            BOOL rightEdge = (rightBtn != buttonDown[1]);

            if(leftEdge || rightEdge) {
                /* Flush any accumulated motion before the button state change */
                if(accumDx != 0 || accumDy != 0) {
                    struct mach_event me;
                    memset(&me, 0, sizeof(struct mach_event));
                    me.x = pointerX - dx;
                    me.y = pointerY - dy;
                    me.dx = accumDx;
                    me.dy = accumDy;
                    me.mods = [self modifierFlagsForState:xkb_state];
                    if (buttonDown[0])
                        me.code = NSLeftMouseDragged;
                    else if (buttonDown[1])
                        me.code = NSRightMouseDragged;
                    else
                        me.code = NSMouseMoved;
                    [target sendEventToApp:&me];
                    ++events;
                    accumDx = 0;
                    accumDy = 0;
                }

                if(leftEdge) {
                    buttonDown[0] = leftBtn;
                    struct mach_event me;
                    memset(&me, 0, sizeof(struct mach_event));
                    me.x = pointerX;
                    me.y = pointerY;
                    me.code = leftBtn ? NSLeftMouseDown : NSLeftMouseUp;
                    me.mods = [self modifierFlagsForState:xkb_state];
                    [target sendEventToApp:&me];
                    ++events;
                }
                if(rightEdge) {
                    buttonDown[1] = rightBtn;
                    struct mach_event me;
                    memset(&me, 0, sizeof(struct mach_event));
                    me.x = pointerX;
                    me.y = pointerY;
                    me.code = rightBtn ? NSRightMouseDown : NSRightMouseUp;
                    me.mods = [self modifierFlagsForState:xkb_state];
                    [target sendEventToApp:&me];
                    ++events;
                }
            } else {
                accumDx += dx;
                accumDy += dy;
            }
        }
    }

    /* Emit any trailing coalesced motion */
    if(accumDx != 0 || accumDy != 0) {
        struct mach_event me;
        memset(&me, 0, sizeof(struct mach_event));
        me.x = pointerX;
        me.y = pointerY;
        me.dx = accumDx;
        me.dy = accumDy;
        me.mods = [self modifierFlagsForState:xkb_state];
        if (buttonDown[0])
            me.code = NSLeftMouseDragged;
        else if (buttonDown[1])
            me.code = NSRightMouseDragged;
        else
            me.code = NSMouseMoved;
        [target sendEventToApp:&me];
        ++events;
    }
    return events;
}

#endif /* __linux__ */

// this reads the default system keymap. Call it after changing the default from prefs.
-(void)setKeymap {
#if defined(__linux__)
    if(xkb_keymap) {
        xkb_keymap_unref(xkb_keymap);
        xkb_keymap = NULL;
    }
    if(xkbCtx) {
        xkb_keymap = xkb_keymap_new_from_names(xkbCtx, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
    }
    if(xkb_state) {
        xkb_state_unref(xkb_state);
        xkb_state = NULL;
    }
    if(xkb_state_unmodified) {
        xkb_state_unmodified = NULL;
    }
    if(xkb_keymap) {
        xkb_state = xkb_state_new(xkb_keymap);
        xkb_state_unmodified = xkb_state_new(xkb_keymap);
    }
#endif
}

-(unsigned int)modifierFlagsForState:(struct xkb_state *)state {
#if !defined(__linux__)
    unsigned int ret = 0;
    if(shiftDown) ret |= NSShiftKeyMask;
    if(ctrlDown)  ret |= NSControlKeyMask;
    if(altDown)   ret |= NSAlternateKeyMask;
    if(cmdDown)   ret |= NSCommandKeyMask;
    if(capsLockOn) ret |= NSAlphaShiftKeyMask;
    return ret;
#else
    if(!state) return 0;
    unsigned int ret=0;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_SHIFT, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSShiftKeyMask;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_CTRL, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSControlKeyMask;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_LOGO, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSCommandKeyMask;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_ALT, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSAlternateKeyMask;
    return ret;
#endif
}

-(NSPoint)pointerPos {
    return NSMakePoint(pointerX, pointerY);
}

-(NSPoint)setPointerPos:(NSPoint)pos {
    pointerX = pos.x;
    pointerY = pos.y;
    return pos;
}

-(void)setGeometry:(NSRect)geom {
    geometry = geom;
}

@end
