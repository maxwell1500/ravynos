/*
 * Internal definitions for ravynOS SDL2 implementation.
 */

#ifndef SDL_RAVYNOS_INTERNAL_H
#define SDL_RAVYNOS_INTERNAL_H

#include "../Headers/SDL.h"
#include "../Headers/SDL_syswm.h"
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

struct SDL_Window {
    Uint32 id;
    char *title;
    int x, y;
    int w, h;
    int min_w, min_h;
    int max_w, max_h;
    Uint32 flags;
    Uint32 brightness_bits;
    float opacity;
    SDL_Surface *surface;
    SDL_bool surface_valid;
    SDL_Renderer *renderer;
    void *nswindow;     /* NSWindow * */
    void *nsview;       /* SDLRavynContentView * */
    void *userdata;
    struct SDL_Window *next;
};

typedef struct SDLRavynDataEntry {
    char *name;
    void *value;
    struct SDLRavynDataEntry *next;
} SDLRavynDataEntry;

/* Subsystem init hooks */
int SDL_RavynVideoInit(void);
void SDL_RavynVideoQuit(void);
void SDL_RavynPumpEventsInternal(void);
void SDL_RavynPushEventInternal(SDL_Event *event);
SDL_Window *SDL_RavynGetWindowList(void);
void SDL_RavynUpdateKeyState(SDL_Scancode scancode, Uint8 state);
void SDL_RavynUpdateMouseState(SDL_Window *win, int x, int y, Uint32 buttonMask);
void SDL_RavynTrace(const char *fmt, ...);

#ifdef __cplusplus
}
#endif

#endif /* SDL_RAVYNOS_INTERNAL_H */
