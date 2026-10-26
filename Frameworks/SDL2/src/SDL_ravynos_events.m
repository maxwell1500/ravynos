/*
 * SDL2 Events, Keyboard, Mouse, and Clipboard implementation for ravynOS.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include "SDL_ravynos_internal.h"
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

/* The SDLRavynContentView class is defined in SDL_ravynos_video.m; its responder
 * methods are implemented here so the event translation lives with the queue. */

#define SDL_MAX_QUEUED_EVENTS 1024

static SDL_Event g_event_queue[SDL_MAX_QUEUED_EVENTS];
static int g_event_head = 0;
static int g_event_tail = 0;
static int g_event_count = 0;
static pthread_mutex_t g_event_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_event_cond = PTHREAD_COND_INITIALIZER;

static Uint8 g_keyboard_state[SDL_NUM_SCANCODES];
static Uint32 g_mouse_buttons = 0;
static int g_mouse_x = 0, g_mouse_y = 0;
static int g_mouse_warp_pending_x = 0, g_mouse_warp_pending_y = 0;

void SDL_RavynPushEventInternal(SDL_Event *event) {
    if (!event) return;
    pthread_mutex_lock(&g_event_mutex);
    int next = (g_event_tail + 1) % SDL_MAX_QUEUED_EVENTS;
    if (next != g_event_head) {
        g_event_queue[g_event_tail] = *event;
        g_event_tail = next;
        g_event_count++;
        pthread_cond_signal(&g_event_cond);
    }
    pthread_mutex_unlock(&g_event_mutex);
}

void SDL_RavynUpdateKeyState(SDL_Scancode scancode, Uint8 state) {
    if (scancode < SDL_NUM_SCANCODES) {
        g_keyboard_state[scancode] = state;
    }
}

void SDL_RavynUpdateMouseState(SDL_Window *win, int x, int y, Uint32 buttonMask) {
    (void)win;
    g_mouse_x = x;
    g_mouse_y = y;
    g_mouse_buttons = buttonMask;
}

/* AT scan code set 1 -> SDL_Scancode.  WindowServer's WSInput.m / HID layer
 * reports Mac virtual keycodes, which for the keys that matter here match
 * the set-1 codes below. */
static SDL_Scancode scancode_from_keycode(unsigned short kc) {
    switch (kc) {
        case 0x00: return SDL_SCANCODE_A;
        case 0x01: return SDL_SCANCODE_S;
        case 0x02: return SDL_SCANCODE_D;
        case 0x03: return SDL_SCANCODE_F;
        case 0x04: return SDL_SCANCODE_H;
        case 0x05: return SDL_SCANCODE_G;
        case 0x06: return SDL_SCANCODE_Z;
        case 0x07: return SDL_SCANCODE_X;
        case 0x08: return SDL_SCANCODE_C;
        case 0x09: return SDL_SCANCODE_V;
        case 0x0B: return SDL_SCANCODE_B;
        case 0x0C: return SDL_SCANCODE_Q;
        case 0x0D: return SDL_SCANCODE_W;
        case 0x0E: return SDL_SCANCODE_E;
        case 0x0F: return SDL_SCANCODE_R;
        case 0x10: return SDL_SCANCODE_Y;
        case 0x11: return SDL_SCANCODE_T;
        case 0x12: return SDL_SCANCODE_1;
        case 0x13: return SDL_SCANCODE_2;
        case 0x14: return SDL_SCANCODE_3;
        case 0x15: return SDL_SCANCODE_4;
        case 0x16: return SDL_SCANCODE_6;
        case 0x17: return SDL_SCANCODE_5;
        case 0x18: return SDL_SCANCODE_EQUALS;
        case 0x19: return SDL_SCANCODE_9;
        case 0x1A: return SDL_SCANCODE_7;
        case 0x1B: return SDL_SCANCODE_MINUS;
        case 0x1C: return SDL_SCANCODE_8;
        case 0x1D: return SDL_SCANCODE_0;
        case 0x1E: return SDL_SCANCODE_RIGHTBRACKET;
        case 0x1F: return SDL_SCANCODE_O;
        case 0x20: return SDL_SCANCODE_U;
        case 0x21: return SDL_SCANCODE_LEFTBRACKET;
        case 0x22: return SDL_SCANCODE_I;
        case 0x23: return SDL_SCANCODE_P;
        case 0x24: return SDL_SCANCODE_RETURN;
        case 0x25: return SDL_SCANCODE_L;
        case 0x26: return SDL_SCANCODE_J;
        case 0x27: return SDL_SCANCODE_APOSTROPHE;
        case 0x28: return SDL_SCANCODE_K;
        case 0x29: return SDL_SCANCODE_SEMICOLON;
        case 0x2A: return SDL_SCANCODE_BACKSLASH;
        case 0x2B: return SDL_SCANCODE_COMMA;
        case 0x2C: return SDL_SCANCODE_SLASH;
        case 0x2D: return SDL_SCANCODE_N;
        case 0x2E: return SDL_SCANCODE_M;
        case 0x2F: return SDL_SCANCODE_PERIOD;
        case 0x30: return SDL_SCANCODE_TAB;
        case 0x31: return SDL_SCANCODE_SPACE;
        case 0x32: return SDL_SCANCODE_GRAVE;
        case 0x33: return SDL_SCANCODE_BACKSPACE;
        case 0x35: return SDL_SCANCODE_ESCAPE;
        case 0x37: return SDL_SCANCODE_LGUI;
        case 0x38: return SDL_SCANCODE_LSHIFT;
        case 0x39: return SDL_SCANCODE_CAPSLOCK;
        case 0x3A: return SDL_SCANCODE_LALT;
        case 0x3B: return SDL_SCANCODE_LCTRL;
        case 0x3C: return SDL_SCANCODE_RSHIFT;
        case 0x3D: return SDL_SCANCODE_RALT;
        case 0x3E: return SDL_SCANCODE_RCTRL;
        case 0x3F: return SDL_SCANCODE_RGUI;
        case 0x47: return SDL_SCANCODE_CLEAR;
        case 0x48: return SDL_SCANCODE_VOLUMEUP;
        case 0x49: return SDL_SCANCODE_VOLUMEDOWN;
        case 0x4A: return SDL_SCANCODE_MUTE;
        case 0x4C: return SDL_SCANCODE_KP_ENTER;
        case 0x4E: return SDL_SCANCODE_KP_MINUS;
        case 0x4F: return SDL_SCANCODE_F18;
        case 0x50: return SDL_SCANCODE_F19;
        case 0x51: return SDL_SCANCODE_KP_EQUALS;
        case 0x52: return SDL_SCANCODE_KP_0;
        case 0x53: return SDL_SCANCODE_KP_1;
        case 0x54: return SDL_SCANCODE_KP_2;
        case 0x55: return SDL_SCANCODE_KP_3;
        case 0x56: return SDL_SCANCODE_KP_4;
        case 0x57: return SDL_SCANCODE_KP_5;
        case 0x58: return SDL_SCANCODE_KP_6;
        case 0x59: return SDL_SCANCODE_KP_7;
        case 0x5A: return SDL_SCANCODE_F20;
        case 0x5B: return SDL_SCANCODE_KP_8;
        case 0x5C: return SDL_SCANCODE_KP_9;
        case 0x60: return SDL_SCANCODE_F5;
        case 0x61: return SDL_SCANCODE_F6;
        case 0x62: return SDL_SCANCODE_F7;
        case 0x63: return SDL_SCANCODE_F3;
        case 0x64: return SDL_SCANCODE_F8;
        case 0x65: return SDL_SCANCODE_F9;
        case 0x67: return SDL_SCANCODE_F11;
        case 0x69: return SDL_SCANCODE_F13;
        case 0x6A: return SDL_SCANCODE_F16;
        case 0x6B: return SDL_SCANCODE_F14;
        case 0x6D: return SDL_SCANCODE_F10;
        case 0x6F: return SDL_SCANCODE_F12;
        case 0x71: return SDL_SCANCODE_F15;
        case 0x73: return SDL_SCANCODE_HOME;
        case 0x74: return SDL_SCANCODE_PAGEUP;
        case 0x75: return SDL_SCANCODE_DELETE;
        case 0x76: return SDL_SCANCODE_F4;
        case 0x77: return SDL_SCANCODE_END;
        case 0x78: return SDL_SCANCODE_F2;
        case 0x79: return SDL_SCANCODE_PAGEDOWN;
        case 0x7A: return SDL_SCANCODE_F1;
        case 0x7B: return SDL_SCANCODE_LEFT;
        case 0x7C: return SDL_SCANCODE_RIGHT;
        case 0x7D: return SDL_SCANCODE_DOWN;
        case 0x7E: return SDL_SCANCODE_UP;
        default: return SDL_SCANCODE_UNKNOWN;
    }
}

static SDL_Keycode keycode_from_scancode(SDL_Scancode sc) {
    if (sc >= SDL_SCANCODE_A && sc <= SDL_SCANCODE_Z) {
        return SDLK_a + (sc - SDL_SCANCODE_A);
    }
    if (sc >= SDL_SCANCODE_1 && sc <= SDL_SCANCODE_9) {
        return SDLK_1 + (sc - SDL_SCANCODE_1);
    }
    if (sc >= SDL_SCANCODE_F1 && sc <= SDL_SCANCODE_F12) {
        return SDLK_F1 + (sc - SDL_SCANCODE_F1);
    }
    if (sc >= SDL_SCANCODE_KP_1 && sc <= SDL_SCANCODE_KP_9) {
        return SDLK_KP_1 + (sc - SDL_SCANCODE_KP_1);
    }
    switch (sc) {
        case SDL_SCANCODE_0: return SDLK_0;
        case SDL_SCANCODE_RETURN: return SDLK_RETURN;
        case SDL_SCANCODE_ESCAPE: return SDLK_ESCAPE;
        case SDL_SCANCODE_BACKSPACE: return SDLK_BACKSPACE;
        case SDL_SCANCODE_TAB: return SDLK_TAB;
        case SDL_SCANCODE_SPACE: return SDLK_SPACE;
        case SDL_SCANCODE_MINUS: return SDLK_MINUS;
        case SDL_SCANCODE_EQUALS: return SDLK_EQUALS;
        case SDL_SCANCODE_LEFTBRACKET: return SDLK_LEFTBRACKET;
        case SDL_SCANCODE_RIGHTBRACKET: return SDLK_RIGHTBRACKET;
        case SDL_SCANCODE_BACKSLASH: return SDLK_BACKSLASH;
        case SDL_SCANCODE_SEMICOLON: return SDLK_SEMICOLON;
        case SDL_SCANCODE_APOSTROPHE: return SDLK_QUOTE;
        case SDL_SCANCODE_COMMA: return SDLK_COMMA;
        case SDL_SCANCODE_PERIOD: return SDLK_PERIOD;
        case SDL_SCANCODE_SLASH: return SDLK_SLASH;
        case SDL_SCANCODE_GRAVE: return SDLK_BACKQUOTE;
        case SDL_SCANCODE_LEFT: return SDLK_LEFT;
        case SDL_SCANCODE_RIGHT: return SDLK_RIGHT;
        case SDL_SCANCODE_UP: return SDLK_UP;
        case SDL_SCANCODE_DOWN: return SDLK_DOWN;
        case SDL_SCANCODE_HOME: return SDLK_HOME;
        case SDL_SCANCODE_END: return SDLK_END;
        case SDL_SCANCODE_PAGEUP: return SDLK_PAGEUP;
        case SDL_SCANCODE_PAGEDOWN: return SDLK_PAGEDOWN;
        case SDL_SCANCODE_DELETE: return SDLK_DELETE;
        case SDL_SCANCODE_KP_ENTER: return SDLK_KP_ENTER;
        case SDL_SCANCODE_LSHIFT: return SDLK_LSHIFT;
        case SDL_SCANCODE_RSHIFT: return SDLK_RSHIFT;
        case SDL_SCANCODE_LCTRL: return SDLK_LCTRL;
        case SDL_SCANCODE_RCTRL: return SDLK_RCTRL;
        case SDL_SCANCODE_LALT: return SDLK_LALT;
        case SDL_SCANCODE_RALT: return SDLK_RALT;
        case SDL_SCANCODE_LGUI: return SDLK_LGUI;
        case SDL_SCANCODE_RGUI: return SDLK_RGUI;
        default: return SDLK_UNKNOWN;
    }
}

static Uint16 sdl_mod_from_nsevent(NSEvent *ev) {
    Uint16 mod = 0;
    NSUInteger flags = [ev modifierFlags];
    if (flags & NSShiftKeyMask) mod |= KMOD_LSHIFT;
    if (flags & NSControlKeyMask) mod |= KMOD_LCTRL;
    if (flags & NSAlternateKeyMask) mod |= KMOD_LALT;
    if (flags & NSCommandKeyMask) mod |= KMOD_LGUI;
    if (flags & NSAlphaShiftKeyMask) mod |= KMOD_CAPS;
    return mod;
}

static SDL_Window *window_for_nswindow(NSWindow *nswin) {
    SDL_Window *w = SDL_RavynGetWindowList();
    while (w) {
        if (w->nswindow == nswin) return w;
        w = w->next;
    }
    return NULL;
}

/* Turn an AppKit event into SDL events.  Called for every event drained out of
 * the NSApplication queue that belongs to one of our windows. */
static void translate_event(NSEvent *ev) {
    NSEventType type = [ev type];
    SDL_Window *win = window_for_nswindow([ev window]);
    SDL_Event se;
    memset(&se, 0, sizeof(se));
    se.type = 0;

    switch (type) {
        case NSKeyDown: {
            unsigned short kc = [ev keyCode];
            SDL_Scancode sc = scancode_from_keycode(kc);
            BOOL repeat = [ev isARepeat];
            if (!repeat) {
                SDL_RavynUpdateKeyState(sc, 1);
            }
            se.type = SDL_KEYDOWN;
            se.key.timestamp = (Uint32)([ev timestamp] * 1000.0);
            se.key.windowID = win ? win->id : 0;
            se.key.state = SDL_PRESSED;
            se.key.repeat = repeat ? 1 : 0;
            se.key.keysym.scancode = sc;
            se.key.keysym.sym = keycode_from_scancode(sc);
            se.key.keysym.mod = sdl_mod_from_nsevent(ev);
            SDL_RavynPushEventInternal(&se);
            break;
        }
        case NSKeyUp: {
            unsigned short kc = [ev keyCode];
            SDL_Scancode sc = scancode_from_keycode(kc);
            SDL_RavynUpdateKeyState(sc, 0);
            se.type = SDL_KEYUP;
            se.key.timestamp = (Uint32)([ev timestamp] * 1000.0);
            se.key.windowID = win ? win->id : 0;
            se.key.state = SDL_RELEASED;
            se.key.repeat = 0;
            se.key.keysym.scancode = sc;
            se.key.keysym.sym = keycode_from_scancode(sc);
            se.key.keysym.mod = sdl_mod_from_nsevent(ev);
            SDL_RavynPushEventInternal(&se);
            break;
        }
        case NSFlagsChanged: {
            se.type = SDL_KEYDOWN;
            se.key.timestamp = (Uint32)([ev timestamp] * 1000.0);
            se.key.windowID = win ? win->id : 0;
            se.key.state = SDL_PRESSED;
            se.key.keysym.scancode = scancode_from_keycode([ev keyCode]);
            se.key.keysym.sym = keycode_from_scancode(se.key.keysym.scancode);
            se.key.keysym.mod = sdl_mod_from_nsevent(ev);
            SDL_RavynPushEventInternal(&se);
            break;
        }
        case NSLeftMouseDown:
        case NSRightMouseDown: {
            NSPoint p = [ev locationInWindow];
            int x = (int)p.x;
            int y = win ? (win->h - (int)p.y) : (int)p.y;
            Uint32 btn = (type == NSLeftMouseDown) ? SDL_BUTTON_LMASK : SDL_BUTTON_RMASK;
            SDL_RavynUpdateMouseState(win, x, y, g_mouse_buttons | btn);
            se.type = SDL_MOUSEBUTTONDOWN;
            se.button.timestamp = (Uint32)([ev timestamp] * 1000.0);
            se.button.windowID = win ? win->id : 0;
            se.button.which = 0;
            se.button.state = SDL_PRESSED;
            se.button.button = (type == NSLeftMouseDown) ? SDL_BUTTON_LEFT : SDL_BUTTON_RIGHT;
            se.button.clicks = (Uint8)[ev clickCount];
            se.button.x = x;
            se.button.y = y;
            SDL_RavynPushEventInternal(&se);
            break;
        }
        case NSLeftMouseUp:
        case NSRightMouseUp: {
            NSPoint p = [ev locationInWindow];
            int x = (int)p.x;
            int y = win ? (win->h - (int)p.y) : (int)p.y;
            Uint32 btn = (type == NSLeftMouseUp) ? SDL_BUTTON_LMASK : SDL_BUTTON_RMASK;
            SDL_RavynUpdateMouseState(win, x, y, g_mouse_buttons & ~btn);
            se.type = SDL_MOUSEBUTTONUP;
            se.button.timestamp = (Uint32)([ev timestamp] * 1000.0);
            se.button.windowID = win ? win->id : 0;
            se.button.which = 0;
            se.button.state = SDL_RELEASED;
            se.button.button = (type == NSLeftMouseUp) ? SDL_BUTTON_LEFT : SDL_BUTTON_RIGHT;
            se.button.clicks = (Uint8)[ev clickCount];
            se.button.x = x;
            se.button.y = y;
            SDL_RavynPushEventInternal(&se);
            break;
        }
        case NSLeftMouseDragged:
        case NSRightMouseDragged:
        case NSMouseMoved: {
            NSPoint p = [ev locationInWindow];
            int x = (int)p.x;
            int y = win ? (win->h - (int)p.y) : (int)p.y;
            int xrel = (int)[ev deltaX];
            int yrel = (int)[ev deltaY];
            SDL_RavynUpdateMouseState(win, x, y, g_mouse_buttons);
            se.type = SDL_MOUSEMOTION;
            se.motion.timestamp = (Uint32)([ev timestamp] * 1000.0);
            se.motion.windowID = win ? win->id : 0;
            se.motion.which = 0;
            se.motion.state = (g_mouse_buttons & SDL_BUTTON_LMASK ? SDL_BUTTON_LMASK : 0) |
                              (g_mouse_buttons & SDL_BUTTON_RMASK ? SDL_BUTTON_RMASK : 0);
            se.motion.x = x;
            se.motion.y = y;
            se.motion.xrel = xrel;
            se.motion.yrel = -yrel;
            SDL_RavynPushEventInternal(&se);
            break;
        }
        case NSScrollWheel: {
            se.type = SDL_MOUSEWHEEL;
            se.wheel.timestamp = (Uint32)([ev timestamp] * 1000.0);
            se.wheel.windowID = win ? win->id : 0;
            se.wheel.which = 0;
            se.wheel.x = (Sint32)[ev deltaX];
            se.wheel.y = (Sint32)[ev deltaY];
            se.wheel.direction = SDL_MOUSEWHEEL_NORMAL;
            SDL_RavynPushEventInternal(&se);
            break;
        }
        default:
            break;
    }
}

void SDL_RavynPumpEventsInternal(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    if (NSApp == nil) {
        [NSApplication sharedApplication];
    }
    int guard = 0;
    while (guard++ < 256) {
        NSEvent *ev = [NSApp nextEventMatchingMask:NSAnyEventMask
                                         untilDate:[NSDate date]
                                            inMode:NSDefaultRunLoopMode
                                           dequeue:YES];
        if (!ev) break;
        /* 15 = NSPlatformSpecific, 16 = NSPlatformSpecificDisplayEvent,
         * 17 = NSAppKitSystem, 20 = NSAppKitDefined.  Spelled numerically
         * because the host macOS SDK no longer declares the private ones. */
        NSEventType et = [ev type];
        if (et == 17 || et == 20 || et == 15 || et == 16) {
            [NSApp sendEvent:ev];
            continue;
        }
        translate_event(ev);
    }
    [pool release];
}

void SDL_PumpEvents(void) {
    SDL_RavynPumpEventsInternal();
}

static int peek_event(SDL_Event *event) {
    pthread_mutex_lock(&g_event_mutex);
    if (g_event_count == 0) {
        pthread_mutex_unlock(&g_event_mutex);
        return 0;
    }
    if (event) *event = g_event_queue[g_event_head];
    pthread_mutex_unlock(&g_event_mutex);
    return 1;
}

static int pop_event(SDL_Event *event) {
    pthread_mutex_lock(&g_event_mutex);
    if (g_event_count == 0) {
        pthread_mutex_unlock(&g_event_mutex);
        return 0;
    }
    if (event) *event = g_event_queue[g_event_head];
    g_event_head = (g_event_head + 1) % SDL_MAX_QUEUED_EVENTS;
    g_event_count--;
    pthread_mutex_unlock(&g_event_mutex);
    return 1;
}

int SDL_PollEvent(SDL_Event *event) {
    SDL_RavynPumpEventsInternal();
    if (pop_event(event)) {
        return 1;
    }
    /* Synthesize a sentinel "polled empty" event for callers that use
     * SDL_PollEvent(NULL) or rely on the return value. */
    return 0;
}

int SDL_WaitEventTimeout(SDL_Event *event, int timeout) {
    Uint32 start = SDL_GetTicks();
    for (;;) {
        SDL_RavynPumpEventsInternal();
        if (pop_event(event)) return 1;
        if (timeout >= 0 && (int)(SDL_GetTicks() - start) >= timeout) return 0;
        struct timespec ts;
        ts.tv_sec = 0;
        ts.tv_nsec = 10 * 1000 * 1000; /* 10 ms */
        nanosleep(&ts, NULL);
    }
}

int SDL_WaitEvent(SDL_Event *event) {
    return SDL_WaitEventTimeout(event, -1);
}

int SDL_PushEvent(SDL_Event *event) {
    if (!event) return -1;
    SDL_RavynPushEventInternal(event);
    return 1;
}

int SDL_PeepEvents(SDL_Event *events, int numevents, SDL_eventaction action,
                   Uint32 minType, Uint32 maxType) {
    int gathered = 0;
    for (int i = 0; i < numevents; i++) {
        SDL_Event ev;
        if (!peek_event(&ev)) break;
        if (ev.type < minType || ev.type > maxType) break;
        if (action == SDL_ADDEVENT) break;
        pop_event(&ev);
        if (action == SDL_PEEKEVENT) {
            break;
        }
        if (events) events[gathered] = ev;
        gathered++;
        if (action == SDL_GETEVENT) continue;
    }
    return gathered;
}

SDL_bool SDL_HasEvent(Uint32 type) {
    return SDL_HasEvents(type, type);
}

SDL_bool SDL_HasEvents(Uint32 minType, Uint32 maxType) {
    pthread_mutex_lock(&g_event_mutex);
    for (int i = 0; i < g_event_count; i++) {
        Uint32 t = g_event_queue[(g_event_head + i) % SDL_MAX_QUEUED_EVENTS].type;
        if (t >= minType && t <= maxType) {
            pthread_mutex_unlock(&g_event_mutex);
            return SDL_TRUE;
        }
    }
    pthread_mutex_unlock(&g_event_mutex);
    return SDL_FALSE;
}

void SDL_FlushEvent(Uint32 type) {
    SDL_FlushEvents(type, type);
}

void SDL_FlushEvents(Uint32 minType, Uint32 maxType) {
    pthread_mutex_lock(&g_event_mutex);
    int kept = 0;
    for (int i = 0; i < g_event_count; i++) {
        SDL_Event ev = g_event_queue[(g_event_head + i) % SDL_MAX_QUEUED_EVENTS];
        if (ev.type < minType || ev.type > maxType) {
            g_event_queue[(g_event_head + kept) % SDL_MAX_QUEUED_EVENTS] = ev;
            kept++;
        }
    }
    g_event_count = kept;
    g_event_tail = (g_event_head + kept) % SDL_MAX_QUEUED_EVENTS;
    pthread_mutex_unlock(&g_event_mutex);
}

Uint8 SDL_EventState(Uint32 type, int state) {
    (void)type; (void)state;
    return SDL_ENABLE;
}

/* Event filters and watches: no filtering is applied, but the API must link. */
void SDL_SetEventFilter(SDL_EventFilter filter, void *userdata) {
    (void)filter; (void)userdata;
}

SDL_bool SDL_GetEventFilter(SDL_EventFilter *filter, void **userdata) {
    if (filter) *filter = NULL;
    if (userdata) *userdata = NULL;
    return SDL_FALSE;
}

void SDL_AddEventWatch(SDL_EventFilter filter, void *userdata) {
    (void)filter; (void)userdata;
}

void SDL_DelEventWatch(SDL_EventFilter filter, void *userdata) {
    (void)filter; (void)userdata;
}

void SDL_FilterEvents(SDL_EventFilter filter, void *userdata) {
    (void)filter; (void)userdata;
}

void SDL_SetEventEnabled(Uint32 type, SDL_bool enabled) {
    (void)type; (void)enabled;
}

SDL_bool SDL_EventEnabled(Uint32 type) {
    (void)type;
    return SDL_TRUE;
}

void SDL_RavynQuitRequested(void) {
    SDL_Event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL_QUIT;
    ev.quit.timestamp = SDL_GetTicks();
    SDL_RavynPushEventInternal(&ev);
}

/* Keyboard state */
const Uint8 *SDL_GetKeyboardState(int *numkeys) {
    if (numkeys) *numkeys = SDL_NUM_SCANCODES;
    return g_keyboard_state;
}

SDL_Keymod SDL_GetModState(void) {
    SDL_Keymod mod = KMOD_NONE;
    if (g_keyboard_state[SDL_SCANCODE_LSHIFT] || g_keyboard_state[SDL_SCANCODE_RSHIFT]) mod |= KMOD_SHIFT;
    if (g_keyboard_state[SDL_SCANCODE_LCTRL] || g_keyboard_state[SDL_SCANCODE_RCTRL]) mod |= KMOD_CTRL;
    if (g_keyboard_state[SDL_SCANCODE_LALT] || g_keyboard_state[SDL_SCANCODE_RALT]) mod |= KMOD_ALT;
    if (g_keyboard_state[SDL_SCANCODE_LGUI] || g_keyboard_state[SDL_SCANCODE_RGUI]) mod |= KMOD_GUI;
    return mod;
}

void SDL_SetModState(SDL_Keymod modstate) {
    (void)modstate;
}

SDL_Keycode SDL_GetKeyFromScancode(SDL_Scancode scancode) {
    return keycode_from_scancode(scancode);
}

SDL_Scancode SDL_GetScancodeFromKey(SDL_Keycode key) {
    for (int i = 0; i < SDL_NUM_SCANCODES; i++) {
        if (keycode_from_scancode((SDL_Scancode)i) == key) return (SDL_Scancode)i;
    }
    return SDL_SCANCODE_UNKNOWN;
}

const char *SDL_GetScancodeName(SDL_Scancode scancode) {
    static char name_buf[32];
    switch (scancode) {
        case SDL_SCANCODE_RETURN: return "Return";
        case SDL_SCANCODE_ESCAPE: return "Escape";
        case SDL_SCANCODE_BACKSPACE: return "Backspace";
        case SDL_SCANCODE_TAB: return "Tab";
        case SDL_SCANCODE_SPACE: return "Space";
        case SDL_SCANCODE_LEFT: return "Left";
        case SDL_SCANCODE_RIGHT: return "Right";
        case SDL_SCANCODE_UP: return "Up";
        case SDL_SCANCODE_DOWN: return "Down";
        case SDL_SCANCODE_LSHIFT: return "Left Shift";
        case SDL_SCANCODE_RSHIFT: return "Right Shift";
        case SDL_SCANCODE_LCTRL: return "Left Ctrl";
        case SDL_SCANCODE_RCTRL: return "Right Ctrl";
        case SDL_SCANCODE_LALT: return "Left Alt";
        case SDL_SCANCODE_RALT: return "Right Alt";
        case SDL_SCANCODE_LGUI: return "Left GUI";
        case SDL_SCANCODE_RGUI: return "Right GUI";
        default: break;
    }
    if (scancode >= SDL_SCANCODE_A && scancode <= SDL_SCANCODE_Z) {
        snprintf(name_buf, sizeof(name_buf), "%c", 'A' + (scancode - SDL_SCANCODE_A));
        return name_buf;
    }
    if (scancode >= SDL_SCANCODE_1 && scancode <= SDL_SCANCODE_9) {
        snprintf(name_buf, sizeof(name_buf), "%d", 1 + (scancode - SDL_SCANCODE_1));
        return name_buf;
    }
    return "Unknown";
}

SDL_Scancode SDL_GetScancodeFromName(const char *name) {
    if (!name || !*name) return SDL_SCANCODE_UNKNOWN;
    if (strlen(name) == 1) {
        char c = name[0];
        if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
        if (c >= 'A' && c <= 'Z') return (SDL_Scancode)(SDL_SCANCODE_A + (c - 'A'));
        if (c >= '1' && c <= '9') return (SDL_Scancode)(SDL_SCANCODE_1 + (c - '1'));
        if (c == '0') return SDL_SCANCODE_0;
    }
    for (int i = 0; i < SDL_NUM_SCANCODES; i++) {
        if (strcmp(SDL_GetScancodeName((SDL_Scancode)i), name) == 0) return (SDL_Scancode)i;
    }
    return SDL_SCANCODE_UNKNOWN;
}

const char *SDL_GetKeyName(SDL_Keycode key) {
    return SDL_GetScancodeName(SDL_GetScancodeFromKey(key));
}

/* Text input */
void SDL_StartTextInput(void) {}
void SDL_StopTextInput(void) {}
SDL_bool SDL_IsTextInputActive(void) { return SDL_TRUE; }
void SDL_SetTextInputRect(const SDL_Rect *rect) { (void)rect; }
SDL_bool SDL_HasScreenKeyboardSupport(void) { return SDL_FALSE; }
SDL_bool SDL_IsScreenKeyboardShown(SDL_Window *window) { (void)window; return SDL_FALSE; }

/* Mouse */
Uint32 SDL_GetMouseState(int *x, int *y) {
    if (x) *x = g_mouse_x;
    if (y) *y = g_mouse_y;
    return g_mouse_buttons;
}

Uint32 SDL_GetGlobalMouseState(int *x, int *y) {
    return SDL_GetMouseState(x, y);
}

Uint32 SDL_GetRelativeMouseState(int *x, int *y) {
    if (x) *x = 0;
    if (y) *y = 0;
    return g_mouse_buttons;
}

void SDL_WarpMouseInWindow(SDL_Window *window, int x, int y) {
    (void)window;
    g_mouse_x = x;
    g_mouse_y = y;
}

int SDL_WarpMouseGlobal(int x, int y) {
    g_mouse_x = x;
    g_mouse_y = y;
    return 0;
}

int SDL_SetRelativeMouseMode(SDL_bool enabled) {
    (void)enabled;
    return 0;
}

SDL_bool SDL_GetRelativeMouseMode(void) {
    return SDL_FALSE;
}

int SDL_CaptureMouse(SDL_bool enabled) {
    (void)enabled;
    return 0;
}

/* Cursors */
SDL_Cursor *SDL_CreateCursor(const Uint8 *data, const Uint8 *mask, int w, int h, int hot_x, int hot_y) {
    (void)data; (void)mask; (void)w; (void)h; (void)hot_x; (void)hot_y;
    return (SDL_Cursor *)calloc(1, 1);
}

SDL_Cursor *SDL_CreateColorCursor(SDL_Surface *surface, int hot_x, int hot_y) {
    (void)surface; (void)hot_x; (void)hot_y;
    return (SDL_Cursor *)calloc(1, 1);
}

SDL_Cursor *SDL_CreateSystemCursor(SDL_SystemCursor id) {
    (void)id;
    return (SDL_Cursor *)calloc(1, 1);
}

void SDL_SetCursor(SDL_Cursor *cursor) { (void)cursor; }
SDL_Cursor *SDL_GetCursor(void) { return NULL; }
SDL_Cursor *SDL_GetDefaultCursor(void) { return NULL; }
void SDL_FreeCursor(SDL_Cursor *cursor) { free(cursor); }

int SDL_ShowCursor(int toggle) {
    (void)toggle;
    return 1;
}

void SDL_SetCursorVisible(SDL_bool visible) { (void)visible; }
SDL_bool SDL_GetCursorVisible(void) { return SDL_TRUE; }

/* Clipboard */
int SDL_SetClipboardText(const char *text) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    if (text) {
        [pb setString:[NSString stringWithUTF8String:text] forType:NSStringPboardType];
    }
    [pool release];
    return 0;
}

char *SDL_GetClipboardText(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *str = [pb stringForType:NSStringPboardType];
    char *out = NULL;
    if (str) {
        out = strdup([str UTF8String]);
    } else {
        out = strdup("");
    }
    [pool release];
    return out;
}

SDL_bool SDL_HasClipboardText(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *str = [[NSPasteboard generalPasteboard] stringForType:NSStringPboardType];
    SDL_bool has = (str && [str length] > 0) ? SDL_TRUE : SDL_FALSE;
    [pool release];
    return has;
}

int SDL_SetPrimarySelectionText(const char *text) {
    return SDL_SetClipboardText(text);
}

char *SDL_GetPrimarySelectionText(void) {
    return SDL_GetClipboardText();
}

SDL_bool SDL_HasPrimarySelectionText(void) {
    return SDL_HasClipboardText();
}
