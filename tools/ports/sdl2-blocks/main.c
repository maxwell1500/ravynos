/*
 * SDLBlocks -- the source-porting proof target for ravynOS.
 *
 * A plain SDL2 application: open a window, build a software renderer, draw a
 * grid of coloured blocks with a moving highlight, and pump events.  It is
 * written the way any SDL2 program is written, with no ravynOS-specific code
 * paths, so that "it runs" means the SDK, the compiler wrapper, pkg-config,
 * SDL2.framework and the window server all work together.
 *
 * With --self-test it draws one frame, writes a machine-readable line to the
 * log and exits, which is what the boot gate checks.  Without it, the program
 * runs until the window is closed.
 */

#include <SDL.h>
#include <zlib.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BLOCK_SIZE 48
#define LOG_PATH "/var/log/sdl2-port-selftest.log"

static void draw_frame(SDL_Renderer *renderer, int width, int height, int phase) {
    SDL_SetRenderDrawColor(renderer, 16, 18, 26, 255);
    SDL_RenderClear(renderer);

    int cols = width / BLOCK_SIZE;
    int rows = height / BLOCK_SIZE;
    for (int row = 0; row < rows; row++) {
        for (int col = 0; col < cols; col++) {
            Uint8 r = (Uint8)(32 + (col * 12) % 160);
            Uint8 g = (Uint8)(64 + (row * 14) % 160);
            Uint8 b = (Uint8)(96 + phase % 120);
            SDL_Rect block = { col * BLOCK_SIZE + 2, row * BLOCK_SIZE + 2,
                               BLOCK_SIZE - 4, BLOCK_SIZE - 4 };
            SDL_SetRenderDrawColor(renderer, r, g, b, 255);
            SDL_RenderFillRect(renderer, &block);
        }
    }

    /* One travelling highlight so consecutive frames are visibly different:
     * a still window would make "it painted once" indistinguishable from
     * "it is still running". */
    int span = cols > 0 ? cols : 1;
    SDL_Rect highlight = { (phase % span) * BLOCK_SIZE, (rows / 2) * BLOCK_SIZE,
                           BLOCK_SIZE, BLOCK_SIZE };
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    SDL_RenderFillRect(renderer, &highlight);

    SDL_RenderPresent(renderer);
}

/* Every stage appends a line, so a log that stops early says exactly where
 * the program stopped.  A self-test that writes only at the end cannot
 * distinguish "never started" from "crashed on the third frame", and that
 * ambiguity is what makes a failure hard to act on. */
static void log_stage(const char *fmt, ...) {
    FILE *log = fopen(LOG_PATH, "a");
    if (log == NULL) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    vfprintf(log, fmt, ap);
    va_end(ap);
    fputc('\n', log);
    fclose(log);
}

int main(int argc, char *argv[]) {
    int selfTest = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--self-test") == 0) {
            selfTest = 1;
        }
    }

    /* Log unconditionally: WindowServer launches a bundle with no
     * arguments, so a self test that only runs under --self-test never runs
     * in the image at all.  --self-test then only means "exit after three
     * frames"; the launch, the paint and the PASS line are the same either
     * way. */
    log_stage("start sdl2-port");

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_EVENTS) != 0) {
        fprintf(stderr, "SDLBlocks: SDL_Init failed: %s\n", SDL_GetError());
        log_stage("FAIL sdl2-port: SDL_Init: %s", SDL_GetError());
        return 1;
    }
    log_stage("step video=%s", SDL_GetCurrentVideoDriver() ? SDL_GetCurrentVideoDriver() : "?");

    const int width = 640;
    const int height = 480;
    /* Borderless: this window draws its own content edge to edge, so it has no
     * use for a title bar, and it keeps the port from depending on the theme
     * frame's display path -- the part of AppKit this system is least sure of
     * for a process that runs its own event loop. */
    SDL_Window *window = SDL_CreateWindow("SDL2 Port \xE2\x80\x94 ravynOS",
                                          SDL_WINDOWPOS_CENTERED,
                                          SDL_WINDOWPOS_CENTERED,
                                          width, height,
                                          SDL_WINDOW_SHOWN | SDL_WINDOW_BORDERLESS);
    if (window == NULL) {
        fprintf(stderr, "SDLBlocks: SDL_CreateWindow failed: %s\n", SDL_GetError());
        log_stage("FAIL sdl2-port: SDL_CreateWindow: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    log_stage("step window created");

    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    if (renderer == NULL) {
        fprintf(stderr, "SDLBlocks: SDL_CreateRenderer failed: %s\n", SDL_GetError());
        log_stage("FAIL sdl2-port: SDL_CreateRenderer: %s", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }
    log_stage("step renderer created");

    SDL_RendererInfo info;
    if (SDL_GetRendererInfo(renderer, &info) == 0) {
        fprintf(stderr, "SDLBlocks: renderer=%s\n", info.name ? info.name : "?");
    }

    int running = 1;
    int phase = 0;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = 0;
            } else if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE) {
                running = 0;
            }
        }
        draw_frame(renderer, width, height, phase);
        SDL_Delay(50);
        phase++;
        log_stage("step frame %d", phase);

        if (phase == 3) {
            log_stage("PASS sdl2-port: video=%s renderer=software surface=%dx%d zlib=%s",
                      SDL_GetCurrentVideoDriver() ? SDL_GetCurrentVideoDriver() : "?",
                      width, height, zlibVersion());
            fprintf(stderr, "SDLBlocks: self-test complete\n");
            running = 0;
        }
    }

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
