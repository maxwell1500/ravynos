/*
 * SDL2 2D Software Renderer for ravynOS.
 */

#include "SDL_ravynos_internal.h"
#include <stdlib.h>
#include <string.h>

struct SDL_Texture {
    Uint32 format;
    int access;
    int w, h;
    SDL_Texture *next;
    void *pixels;
    int pitch;
    SDL_BlendMode blendMode;
    Uint8 r, g, b, a;
};

struct SDL_Renderer {
    SDL_Window *window;
    SDL_Surface *target;
    SDL_Texture *textures;
    SDL_Texture *render_target;
    SDL_Rect viewport;
    SDL_Rect clip_rect;
    SDL_bool use_clip;
    Uint8 r, g, b, a;
    SDL_BlendMode blendMode;
    SDL_bool vsync;
    int logical_w, logical_h;
    float scale_x, scale_y;
    char *name;
};

static SDL_RendererInfo g_sw_renderer_info = {
    "software",
    1,
    { SDL_PIXELFORMAT_ARGB8888 },
    0,
    0,
    0
};

SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, int index, Uint32 flags) {
    (void)index;
    (void)flags;
    if (!window) {
        SDL_SetError("Invalid window");
        return NULL;
    }
    SDL_Renderer *r = (SDL_Renderer *)calloc(1, sizeof(SDL_Renderer));
    if (!r) {
        SDL_OutOfMemory();
        return NULL;
    }
    r->window = window;
    r->r = r->g = r->b = r->a = 255;
    r->blendMode = SDL_BLENDMODE_NONE;
    r->viewport.x = 0;
    r->viewport.y = 0;
    r->viewport.w = window->w;
    r->viewport.h = window->h;
    r->clip_rect = r->viewport;
    r->scale_x = 1.0f;
    r->scale_y = 1.0f;
    r->name = strdup("software");
    r->target = NULL;

    window->renderer = (SDL_Renderer *)r;
    return (SDL_Renderer *)r;
}

SDL_Renderer *SDL_CreateSoftwareRenderer(SDL_Surface *surface) {
    if (!surface) {
        SDL_SetError("Invalid surface");
        return NULL;
    }
    SDL_Renderer *r = (SDL_Renderer *)calloc(1, sizeof(SDL_Renderer));
    if (!r) return NULL;
    r->target = surface;
    r->r = r->g = r->b = r->a = 255;
    r->viewport.x = 0;
    r->viewport.y = 0;
    r->viewport.w = surface->w;
    r->viewport.h = surface->h;
    r->clip_rect = r->viewport;
    r->scale_x = 1.0f;
    r->scale_y = 1.0f;
    r->name = strdup("software");
    return (SDL_Renderer *)r;
}

SDL_Renderer *SDL_GetRenderer(SDL_Window *window) {
    return window ? window->renderer : NULL;
}

int SDL_GetRendererInfo(SDL_Renderer *renderer, SDL_RendererInfo *info) {
    if (!renderer || !info) return -1;
    *info = g_sw_renderer_info;
    return 0;
}

int SDL_GetRendererOutputSize(SDL_Renderer *renderer, int *w, int *h) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    if (r->target) {
        if (w) *w = r->target->w;
        if (h) *h = r->target->h;
    } else if (r->window) {
        if (w) *w = r->window->w;
        if (h) *h = r->window->h;
    } else {
        if (w) *w = 0;
        if (h) *h = 0;
    }
    return 0;
}

static SDL_Surface *renderer_target_surface(SDL_Renderer *r) {
    if (r->target) return r->target;
    if (r->window) {
        return SDL_GetWindowSurface(r->window);
    }
    return NULL;
}

void SDL_DestroyRenderer(SDL_Renderer *renderer) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return;
    SDL_Texture *tex = r->textures;
    while (tex) {
        SDL_Texture *next = tex->next;
        free(tex->pixels);
        free(tex);
        tex = next;
    }
    if (r->window) {
        r->window->renderer = NULL;
    }
    free(r->name);
    free(r);
}

SDL_Texture *SDL_CreateTexture(SDL_Renderer *renderer, Uint32 format, int access, int w, int h) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r || w <= 0 || h <= 0) return NULL;
    SDL_Texture *t = (SDL_Texture *)calloc(1, sizeof(SDL_Texture));
    if (!t) return NULL;
    t->format = format ? format : SDL_PIXELFORMAT_ARGB8888;
    t->access = access;
    t->w = w;
    t->h = h;
    t->blendMode = SDL_BLENDMODE_NONE;
    t->r = t->g = t->b = t->a = 255;
    SDL_PixelFormat *fmt = SDL_AllocFormat(t->format);
    t->pitch = w * (fmt ? fmt->BytesPerPixel : 4);
    if (fmt) SDL_FreeFormat(fmt);
    t->pixels = calloc(1, (size_t)t->pitch * (size_t)h);
    t->next = r->textures;
    r->textures = t;
    return (SDL_Texture *)t;
}

SDL_Texture *SDL_CreateTextureFromSurface(SDL_Renderer *renderer, SDL_Surface *surface) {
    if (!surface) return NULL;
    SDL_Texture *t = SDL_CreateTexture(renderer, surface->format ? surface->format->format : SDL_PIXELFORMAT_ARGB8888,
                                       SDL_TEXTUREACCESS_STATIC, surface->w, surface->h);
    if (t) {
        SDL_UpdateTexture(t, NULL, surface->pixels, surface->pitch);
    }
    return t;
}

int SDL_QueryTexture(SDL_Texture *texture, Uint32 *format, int *access, int *w, int *h) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t) return -1;
    if (format) *format = t->format;
    if (access) *access = t->access;
    if (w) *w = t->w;
    if (h) *h = t->h;
    return 0;
}

int SDL_SetTextureColorMod(SDL_Texture *texture, Uint8 r, Uint8 g, Uint8 b) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t) return -1;
    t->r = r; t->g = g; t->b = b;
    return 0;
}

int SDL_GetTextureColorMod(SDL_Texture *texture, Uint8 *r, Uint8 *g, Uint8 *b) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t) return -1;
    if (r) *r = t->r;
    if (g) *g = t->g;
    if (b) *b = t->b;
    return 0;
}

int SDL_SetTextureAlphaMod(SDL_Texture *texture, Uint8 alpha) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t) return -1;
    t->a = alpha;
    return 0;
}

int SDL_GetTextureAlphaMod(SDL_Texture *texture, Uint8 *alpha) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t) return -1;
    if (alpha) *alpha = t->a;
    return 0;
}

int SDL_SetTextureBlendMode(SDL_Texture *texture, SDL_BlendMode blendMode) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t) return -1;
    t->blendMode = blendMode;
    return 0;
}

int SDL_GetTextureBlendMode(SDL_Texture *texture, SDL_BlendMode *blendMode) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t) return -1;
    if (blendMode) *blendMode = t->blendMode;
    return 0;
}

int SDL_SetTextureScaleMode(SDL_Texture *texture, SDL_ScaleMode scaleMode) {
    (void)texture; (void)scaleMode;
    return 0;
}

int SDL_GetTextureScaleMode(SDL_Texture *texture, SDL_ScaleMode *scaleMode) {
    (void)texture;
    if (scaleMode) *scaleMode = SDL_ScaleModeNearest;
    return 0;
}

int SDL_SetTextureUserData(SDL_Texture *texture, void *userdata) {
    (void)texture; (void)userdata;
    return 0;
}

void *SDL_GetTextureUserData(SDL_Texture *texture) {
    (void)texture;
    return NULL;
}

int SDL_UpdateTexture(SDL_Texture *texture, const SDL_Rect *rect, const void *pixels, int pitch) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t || !pixels) return -1;
    int x = rect ? rect->x : 0;
    int y = rect ? rect->y : 0;
    int w = rect ? rect->w : t->w;
    int h = rect ? rect->h : t->h;
    if (x < 0 || y < 0 || x + w > t->w || y + h > t->h) return -1;

    SDL_PixelFormat *fmt = SDL_AllocFormat(t->format);
    int bpp = fmt ? fmt->BytesPerPixel : 4;
    if (fmt) SDL_FreeFormat(fmt);
    for (int row = 0; row < h; row++) {
        memcpy((Uint8 *)t->pixels + (y + row) * t->pitch + x * bpp,
               (const Uint8 *)pixels + row * pitch, (size_t)w * (size_t)bpp);
    }
    return 0;
}

int SDL_UpdateYUVTexture(SDL_Texture *texture, const SDL_Rect *rect,
                         const Uint8 *Yplane, int Ypitch,
                         const Uint8 *Uplane, int Upitch,
                         const Uint8 *Vplane, int Vpitch) {
    (void)texture; (void)rect; (void)Yplane; (void)Ypitch;
    (void)Uplane; (void)Upitch; (void)Vplane; (void)Vpitch;
    return 0;
}

int SDL_UpdateNVTexture(SDL_Texture *texture, const SDL_Rect *rect,
                        const Uint8 *Yplane, int Ypitch,
                        const Uint8 *UVplane, int UVpitch) {
    (void)texture; (void)rect; (void)Yplane; (void)Ypitch; (void)UVplane; (void)UVpitch;
    return 0;
}

int SDL_LockTexture(SDL_Texture *texture, const SDL_Rect *rect, void **pixels, int *pitch) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t || !pixels) return -1;
    int x = rect ? rect->x : 0;
    int y = rect ? rect->y : 0;
    SDL_PixelFormat *fmt = SDL_AllocFormat(t->format);
    int bpp = fmt ? fmt->BytesPerPixel : 4;
    if (fmt) SDL_FreeFormat(fmt);
    *pixels = (Uint8 *)t->pixels + y * t->pitch + x * bpp;
    if (pitch) *pitch = t->pitch;
    return 0;
}

int SDL_LockTextureToSurface(SDL_Texture *texture, const SDL_Rect *rect, SDL_Surface **surface) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!t || !surface) return -1;
    *surface = SDL_CreateRGBSurfaceWithFormatFrom(t->pixels, t->w, t->h, 32, t->pitch, t->format);
    return 0;
}

void SDL_UnlockTexture(SDL_Texture *texture) {
    (void)texture;
}

void SDL_DestroyTexture(SDL_Texture *texture) {
    if (!texture) return;
    SDL_Texture *t = (SDL_Texture *)texture;
    /* Detach from any renderer list lazily; textures are freed with the renderer. */
    free(t->pixels);
    free(t);
}

int SDL_SetRenderTarget(SDL_Renderer *renderer, SDL_Texture *texture) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    r->render_target = texture;
    return 0;
}

SDL_Texture *SDL_GetRenderTarget(SDL_Renderer *renderer) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    return r ? r->render_target : NULL;
}

int SDL_RenderSetViewport(SDL_Renderer *renderer, const SDL_Rect *rect) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    if (rect) {
        r->viewport = *rect;
    } else {
        SDL_GetRendererOutputSize(renderer, &r->viewport.w, &r->viewport.h);
        r->viewport.x = 0;
        r->viewport.y = 0;
    }
    return 0;
}

void SDL_RenderGetViewport(SDL_Renderer *renderer, SDL_Rect *rect) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (r && rect) *rect = r->viewport;
}

int SDL_RenderSetClipRect(SDL_Renderer *renderer, const SDL_Rect *rect) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    if (rect) {
        r->clip_rect = *rect;
        r->use_clip = SDL_TRUE;
    } else {
        r->clip_rect = r->viewport;
        r->use_clip = SDL_FALSE;
    }
    return 0;
}

void SDL_RenderGetClipRect(SDL_Renderer *renderer, SDL_Rect *rect) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (r && rect) *rect = r->clip_rect;
}

SDL_bool SDL_RenderIsClipEnabled(SDL_Renderer *renderer) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    return r ? r->use_clip : SDL_FALSE;
}

int SDL_RenderSetLogicalSize(SDL_Renderer *renderer, int w, int h) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    r->logical_w = w;
    r->logical_h = h;
    if (w > 0 && h > 0) {
        int out_w = 0, out_h = 0;
        SDL_GetRendererOutputSize(renderer, &out_w, &out_h);
        r->scale_x = (float)out_w / (float)w;
        r->scale_y = (float)out_h / (float)h;
    } else {
        r->scale_x = 1.0f;
        r->scale_y = 1.0f;
    }
    return 0;
}

void SDL_RenderGetLogicalSize(SDL_Renderer *renderer, int *w, int *h) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return;
    if (w) *w = r->logical_w;
    if (h) *h = r->logical_h;
}

int SDL_RenderSetIntegerScale(SDL_Renderer *renderer, SDL_bool enable) {
    (void)renderer; (void)enable;
    return 0;
}

SDL_bool SDL_RenderGetIntegerScale(SDL_Renderer *renderer) {
    (void)renderer;
    return SDL_FALSE;
}

int SDL_RenderSetScale(SDL_Renderer *renderer, float scaleX, float scaleY) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    r->scale_x = scaleX;
    r->scale_y = scaleY;
    return 0;
}

void SDL_RenderGetScale(SDL_Renderer *renderer, float *scaleX, float *scaleY) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return;
    if (scaleX) *scaleX = r->scale_x;
    if (scaleY) *scaleY = r->scale_y;
}

int SDL_RenderSetVSync(SDL_Renderer *renderer, int vsync) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    r->vsync = vsync ? SDL_TRUE : SDL_FALSE;
    return 0;
}

int SDL_SetRenderDrawColor(SDL_Renderer *renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a) {
    SDL_Renderer *rr = (SDL_Renderer *)renderer;
    if (!rr) return -1;
    rr->r = r; rr->g = g; rr->b = b; rr->a = a;
    return 0;
}

int SDL_GetRenderDrawColor(SDL_Renderer *renderer, Uint8 *r, Uint8 *g, Uint8 *b, Uint8 *a) {
    SDL_Renderer *rr = (SDL_Renderer *)renderer;
    if (!rr) return -1;
    if (r) *r = rr->r;
    if (g) *g = rr->g;
    if (b) *b = rr->b;
    if (a) *a = rr->a;
    return 0;
}

int SDL_SetRenderDrawBlendMode(SDL_Renderer *renderer, SDL_BlendMode blendMode) {
    SDL_Renderer *rr = (SDL_Renderer *)renderer;
    if (!rr) return -1;
    rr->blendMode = blendMode;
    return 0;
}

int SDL_GetRenderDrawBlendMode(SDL_Renderer *renderer, SDL_BlendMode *blendMode) {
    SDL_Renderer *rr = (SDL_Renderer *)renderer;
    if (!rr) return -1;
    if (blendMode) *blendMode = rr->blendMode;
    return 0;
}

static void draw_pixel(SDL_Surface *s, int x, int y, Uint8 r, Uint8 g, Uint8 b, Uint8 a, SDL_BlendMode mode) {
    if (x < 0 || y < 0 || x >= s->w || y >= s->h) return;
    Uint32 *row = (Uint32 *)((Uint8 *)s->pixels + y * s->pitch);
    if (mode == SDL_BLENDMODE_BLEND && a < 255) {
        Uint32 d = row[x];
        Uint8 dr = (d >> 16) & 0xFF, dg = (d >> 8) & 0xFF, db = d & 0xFF;
        r = (Uint8)(((int)r * a + (int)dr * (255 - a)) / 255);
        g = (Uint8)(((int)g * a + (int)dg * (255 - a)) / 255);
        b = (Uint8)(((int)b * a + (int)db * (255 - a)) / 255);
        a = 255;
    }
    row[x] = ((Uint32)a << 24) | ((Uint32)r << 16) | ((Uint32)g << 8) | (Uint32)b;
}

int SDL_RenderClear(SDL_Renderer *renderer) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r) return -1;
    SDL_Surface *s = renderer_target_surface(r);
    if (!s) return -1;
    Uint32 color = ((Uint32)r->a << 24) | ((Uint32)r->r << 16) | ((Uint32)r->g << 8) | (Uint32)r->b;
    SDL_Rect vp = r->viewport;
    return SDL_FillRect(s, &vp, color);
}

int SDL_RenderDrawPoint(SDL_Renderer *renderer, int x, int y) {
    return SDL_RenderDrawPoints(renderer, &(SDL_Point){(int)x, (int)y}, 1);
}

int SDL_RenderDrawPoints(SDL_Renderer *renderer, const SDL_Point *points, int count) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r || !points) return -1;
    SDL_Surface *s = renderer_target_surface(r);
    if (!s) return -1;
    for (int i = 0; i < count; i++) {
        int px = (int)(points[i].x * r->scale_x) + r->viewport.x;
        int py = (int)(points[i].y * r->scale_y) + r->viewport.y;
        draw_pixel(s, px, py, r->r, r->g, r->b, r->a, r->blendMode);
    }
    return 0;
}

int SDL_RenderDrawLine(SDL_Renderer *renderer, int x1, int y1, int x2, int y2) {
    SDL_Point pts[2] = {{x1, y1}, {x2, y2}};
    return SDL_RenderDrawLines(renderer, pts, 2);
}

int SDL_RenderDrawLines(SDL_Renderer *renderer, const SDL_Point *points, int count) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r || !points || count < 2) return -1;
    SDL_Surface *s = renderer_target_surface(r);
    if (!s) return -1;
    for (int i = 0; i < count - 1; i++) {
        int x0 = (int)(points[i].x * r->scale_x) + r->viewport.x;
        int y0 = (int)(points[i].y * r->scale_y) + r->viewport.y;
        int x1 = (int)(points[i + 1].x * r->scale_x) + r->viewport.x;
        int y1 = (int)(points[i + 1].y * r->scale_y) + r->viewport.y;
        int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
        int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
        int err = dx + dy;
        while (1) {
            draw_pixel(s, x0, y0, r->r, r->g, r->b, r->a, r->blendMode);
            if (x0 == x1 && y0 == y1) break;
            int e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
    }
    return 0;
}

int SDL_RenderDrawRect(SDL_Renderer *renderer, const SDL_Rect *rect) {
    if (!rect) return -1;
    SDL_Rect tmp = *rect;
    return SDL_RenderDrawRects(renderer, &tmp, 1);
}

int SDL_RenderDrawRects(SDL_Renderer *renderer, const SDL_Rect *rects, int count) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r || !rects) return -1;
    SDL_Surface *s = renderer_target_surface(r);
    if (!s) return -1;
    for (int i = 0; i < count; i++) {
        int x0 = (int)(rects[i].x * r->scale_x) + r->viewport.x;
        int y0 = (int)(rects[i].y * r->scale_y) + r->viewport.y;
        int x1 = x0 + (int)(rects[i].w * r->scale_x);
        int y1 = y0 + (int)(rects[i].h * r->scale_y);
        for (int x = x0; x < x1; x++) {
            draw_pixel(s, x, y0, r->r, r->g, r->b, r->a, r->blendMode);
            draw_pixel(s, x, y1 - 1, r->r, r->g, r->b, r->a, r->blendMode);
        }
        for (int y = y0; y < y1; y++) {
            draw_pixel(s, x0, y, r->r, r->g, r->b, r->a, r->blendMode);
            draw_pixel(s, x1 - 1, y, r->r, r->g, r->b, r->a, r->blendMode);
        }
    }
    return 0;
}

int SDL_RenderFillRect(SDL_Renderer *renderer, const SDL_Rect *rect) {
    if (!rect) return -1;
    SDL_Rect tmp = *rect;
    return SDL_RenderFillRects(renderer, &tmp, 1);
}

int SDL_RenderFillRects(SDL_Renderer *renderer, const SDL_Rect *rects, int count) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r || !rects) return -1;
    SDL_Surface *s = renderer_target_surface(r);
    if (!s) return -1;
    for (int i = 0; i < count; i++) {
        int x0 = (int)(rects[i].x * r->scale_x) + r->viewport.x;
        int y0 = (int)(rects[i].y * r->scale_y) + r->viewport.y;
        int w = (int)(rects[i].w * r->scale_x);
        int h = (int)(rects[i].h * r->scale_y);
        for (int y = y0; y < y0 + h; y++) {
            for (int x = x0; x < x0 + w; x++) {
                if (x < r->clip_rect.x || x >= r->clip_rect.x + r->clip_rect.w ||
                    y < r->clip_rect.y || y >= r->clip_rect.y + r->clip_rect.h) {
                    continue;
                }
                draw_pixel(s, x, y, r->r, r->g, r->b, r->a, r->blendMode);
            }
        }
    }
    return 0;
}

int SDL_RenderCopy(SDL_Renderer *renderer, SDL_Texture *texture, const SDL_Rect *srcrect, const SDL_Rect *dstrect) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    SDL_Texture *t = (SDL_Texture *)texture;
    if (!r || !t) return -1;
    SDL_Surface *s = renderer_target_surface(r);
    if (!s) return -1;

    SDL_Rect src = srcrect ? *srcrect : (SDL_Rect){0, 0, t->w, t->h};
    SDL_Rect dst = dstrect ? *dstrect : (SDL_Rect){0, 0, t->w, t->h};
    dst.x += r->viewport.x;
    dst.y += r->viewport.y;

    for (int y = 0; y < dst.h; y++) {
        int sy = src.y + (y * src.h) / (dst.h > 0 ? dst.h : 1);
        if (sy < 0 || sy >= t->h) continue;
        for (int x = 0; x < dst.w; x++) {
            int sx = src.x + (x * src.w) / (dst.w > 0 ? dst.w : 1);
            if (sx < 0 || sx >= t->w) continue;
            const Uint32 *trow = (const Uint32 *)((const Uint8 *)t->pixels + sy * t->pitch);
            Uint32 px = trow[sx];
            Uint8 a = (Uint8)((px >> 24) & 0xFF);
            Uint8 rr = (Uint8)((px >> 16) & 0xFF);
            Uint8 gg = (Uint8)((px >> 8) & 0xFF);
            Uint8 bb = (Uint8)(px & 0xFF);
            if (t->blendMode == SDL_BLENDMODE_BLEND || t->blendMode == SDL_BLENDMODE_BLEND) {
                /* keep alpha */
            } else {
                a = 255;
            }
            draw_pixel(s, dst.x + x, dst.y + y, rr, gg, bb, a, t->blendMode);
        }
    }
    return 0;
}

int SDL_RenderCopyEx(SDL_Renderer *renderer, SDL_Texture *texture, const SDL_Rect *srcrect,
                     const SDL_Rect *dstrect, const double angle,
                     const SDL_Point *center, const SDL_RendererFlip flip) {
    (void)angle; (void)center; (void)flip;
    return SDL_RenderCopy(renderer, texture, srcrect, dstrect);
}

int SDL_RenderGeometry(SDL_Renderer *renderer, SDL_Texture *texture, const SDL_Vertex *vertices, int num_vertices,
                       const int *indices, int num_indices) {
    (void)renderer; (void)texture; (void)vertices; (void)num_vertices; (void)indices; (void)num_indices;
    return 0;
}

int SDL_RenderGeometryRaw(SDL_Renderer *renderer, SDL_Texture *texture,
                          const float *xy, int xy_stride, const SDL_Color *color, int color_stride,
                          const float *uv, int uv_stride, int num_vertices,
                          const void *indices, int num_indices, int size_indices) {
    (void)renderer; (void)texture; (void)xy; (void)xy_stride; (void)color; (void)color_stride;
    (void)uv; (void)uv_stride; (void)num_vertices; (void)indices; (void)num_indices; (void)size_indices;
    return 0;
}

int SDL_RenderReadPixels(SDL_Renderer *renderer, const SDL_Rect *rect, Uint32 format, void *pixels, int pitch) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r || !pixels) return -1;
    SDL_Surface *s = renderer_target_surface(r);
    if (!s) return -1;
    SDL_Rect src = rect ? *rect : (SDL_Rect){0, 0, s->w, s->h};
    return SDL_ConvertPixels(src.w, src.h, s->format->format,
                             (Uint8 *)s->pixels + src.y * s->pitch + src.x * 4, s->pitch,
                             format, pixels, pitch);
}

void SDL_RenderPresent(SDL_Renderer *renderer) {
    SDL_Renderer *r = (SDL_Renderer *)renderer;
    if (!r || !r->window || r->target) return;
    SDL_Surface *ws = SDL_GetWindowSurface(r->window);
    if (!ws) return;
    /* Window surface IS the render target for software rendering: RenderPresent
     * pushes it out through the shared-memory surface to WindowServer. */
    SDL_UpdateWindowSurface(r->window);
}

int SDL_GetNumRenderDrivers(void) {
    return 1;
}

int SDL_GetRenderDriverInfo(int index, SDL_RendererInfo *info) {
    if (index != 0 || !info) return -1;
    *info = g_sw_renderer_info;
    return 0;
}

int SDL_RenderFlush(SDL_Renderer *renderer) {
    (void)renderer;
    return 0;
}

int SDL_BindTexture(SDL_Texture *texture, float *texw, float *texh) {
    SDL_Texture *t = (SDL_Texture *)texture;
    if (texw) *texw = 1.0f;
    if (texh) *texh = 1.0f;
    return t ? 0 : -1;
}
