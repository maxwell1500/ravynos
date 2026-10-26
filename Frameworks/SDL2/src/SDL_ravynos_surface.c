/*
 * SDL2 Surface, PixelFormat, Rect, and Blit implementation for ravynOS.
 */

#include "SDL_ravynos_internal.h"
#include <stdlib.h>
#include <string.h>

typedef struct SDLSurfacePrivate {
    Uint32 color_key;
    SDL_bool has_color_key;
    Uint8 r_mod, g_mod, b_mod, a_mod;
    SDL_BlendMode blend_mode;
} SDLSurfacePrivate;

/* Rect helpers */
SDL_bool SDL_HasIntersection(const SDL_Rect *A, const SDL_Rect *B) {
    if (!A || !B || SDL_RectEmpty(A) || SDL_RectEmpty(B)) return SDL_FALSE;
    int Amin = A->x, Amax = Amin + A->w;
    int Bmin = B->x, Bmax = Bmin + B->w;
    if (Bmin > Amin) Amin = Bmin;
    if (Bmax < Amax) Amax = Bmax;
    if (Amax <= Amin) return SDL_FALSE;

    Amin = A->y; Amax = Amin + A->h;
    Bmin = B->y; Bmax = Bmin + B->h;
    if (Bmin > Amin) Amin = Bmin;
    if (Bmax < Amax) Amax = Bmax;
    if (Amax <= Amin) return SDL_FALSE;

    return SDL_TRUE;
}

SDL_bool SDL_IntersectRect(const SDL_Rect *A, const SDL_Rect *B, SDL_Rect *result) {
    if (!result) return SDL_FALSE;
    if (!A || !B || SDL_RectEmpty(A) || SDL_RectEmpty(B)) {
        result->x = result->y = result->w = result->h = 0;
        return SDL_FALSE;
    }
    int Amin = A->x, Amax = Amin + A->w;
    int Bmin = B->x, Bmax = Bmin + B->w;
    if (Bmin > Amin) Amin = Bmin;
    result->x = Amin;
    if (Bmax < Amax) Amax = Bmax;
    result->w = Amax - Amin;

    Amin = A->y; Amax = Amin + A->h;
    Bmin = B->y; Bmax = Bmin + B->h;
    if (Bmin > Amin) Amin = Bmin;
    result->y = Amin;
    if (Bmax < Amax) Amax = Bmax;
    result->h = Amax - Amin;

    return !SDL_RectEmpty(result);
}

void SDL_UnionRect(const SDL_Rect *A, const SDL_Rect *B, SDL_Rect *result) {
    if (!result) return;
    if (!A || SDL_RectEmpty(A)) {
        if (B) *result = *B;
        else result->x = result->y = result->w = result->h = 0;
        return;
    }
    if (!B || SDL_RectEmpty(B)) {
        *result = *A;
        return;
    }
    int xmin = (A->x < B->x) ? A->x : B->x;
    int ymin = (A->y < B->y) ? A->y : B->y;
    int xmax = ((A->x + A->w) > (B->x + B->w)) ? (A->x + A->w) : (B->x + B->w);
    int ymax = ((A->y + A->h) > (B->y + B->h)) ? (A->y + A->h) : (B->y + B->h);
    result->x = xmin;
    result->y = ymin;
    result->w = xmax - xmin;
    result->h = ymax - ymin;
}

SDL_bool SDL_EnclosePoints(const SDL_Point *points, int count, const SDL_Rect *clip, SDL_Rect *result) {
    if (!points || count <= 0) return SDL_FALSE;
    int minx = 0, miny = 0, maxx = 0, maxy = 0;
    SDL_bool any = SDL_FALSE;
    for (int i = 0; i < count; i++) {
        int x = points[i].x, y = points[i].y;
        if (clip && !SDL_PointInRect(&points[i], clip)) continue;
        if (!any) {
            minx = maxx = x;
            miny = maxy = y;
            any = SDL_TRUE;
        } else {
            if (x < minx) minx = x;
            if (x > maxx) maxx = x;
            if (y < miny) miny = y;
            if (y > maxy) maxy = y;
        }
    }
    if (any && result) {
        result->x = minx;
        result->y = miny;
        result->w = maxx - minx + 1;
        result->h = maxy - miny + 1;
    }
    return any;
}

SDL_bool SDL_IntersectRectAndLine(const SDL_Rect *rect, int *X1, int *Y1, int *X2, int *Y2) {
    if (!rect || !X1 || !Y1 || !X2 || !Y2 || SDL_RectEmpty(rect)) return SDL_FALSE;
    return SDL_TRUE;
}

/* Pixel formats */
const char *SDL_GetPixelFormatName(Uint32 format) {
    switch (format) {
        case SDL_PIXELFORMAT_ARGB8888: return "SDL_PIXELFORMAT_ARGB8888";
        case SDL_PIXELFORMAT_RGBA8888: return "SDL_PIXELFORMAT_RGBA8888";
        case SDL_PIXELFORMAT_ABGR8888: return "SDL_PIXELFORMAT_ABGR8888";
        case SDL_PIXELFORMAT_BGRA8888: return "SDL_PIXELFORMAT_BGRA8888";
        case SDL_PIXELFORMAT_RGB888:   return "SDL_PIXELFORMAT_RGB888";
        case SDL_PIXELFORMAT_RGB24:    return "SDL_PIXELFORMAT_RGB24";
        case SDL_PIXELFORMAT_RGB565:   return "SDL_PIXELFORMAT_RGB565";
        case SDL_PIXELFORMAT_INDEX8:   return "SDL_PIXELFORMAT_INDEX8";
        default: return "SDL_PIXELFORMAT_UNKNOWN";
    }
}

SDL_bool SDL_PixelFormatEnumToMasks(Uint32 format, int *bpp, Uint32 *Rmask, Uint32 *Gmask, Uint32 *Bmask, Uint32 *Amask) {
    if (bpp) *bpp = 32;
    if (Rmask) *Rmask = 0x00FF0000;
    if (Gmask) *Gmask = 0x0000FF00;
    if (Bmask) *Bmask = 0x000000FF;
    if (Amask) *Amask = 0xFF000000;

    switch (format) {
        case SDL_PIXELFORMAT_ARGB8888:
            break;
        case SDL_PIXELFORMAT_RGB888:
            if (Amask) *Amask = 0;
            break;
        case SDL_PIXELFORMAT_RGBA8888:
            if (Rmask) *Rmask = 0xFF000000;
            if (Gmask) *Gmask = 0x00FF0000;
            if (Bmask) *Bmask = 0x0000FF00;
            if (Amask) *Amask = 0x000000FF;
            break;
        case SDL_PIXELFORMAT_ABGR8888:
            if (Rmask) *Rmask = 0x000000FF;
            if (Gmask) *Gmask = 0x0000FF00;
            if (Bmask) *Bmask = 0x00FF0000;
            if (Amask) *Amask = 0xFF000000;
            break;
        case SDL_PIXELFORMAT_BGRA8888:
            if (Bmask) *Bmask = 0xFF000000;
            if (Gmask) *Gmask = 0x00FF0000;
            if (Rmask) *Rmask = 0x0000FF00;
            if (Amask) *Amask = 0x000000FF;
            break;
        case SDL_PIXELFORMAT_RGB24:
            if (bpp) *bpp = 24;
            if (Rmask) *Rmask = 0x000000FF;
            if (Gmask) *Gmask = 0x0000FF00;
            if (Bmask) *Bmask = 0x00FF0000;
            if (Amask) *Amask = 0;
            break;
        case SDL_PIXELFORMAT_RGB565:
            if (bpp) *bpp = 16;
            if (Rmask) *Rmask = 0xF800;
            if (Gmask) *Gmask = 0x07E0;
            if (Bmask) *Bmask = 0x001F;
            if (Amask) *Amask = 0;
            break;
        case SDL_PIXELFORMAT_INDEX8:
            if (bpp) *bpp = 8;
            if (Rmask) *Rmask = 0;
            if (Gmask) *Gmask = 0;
            if (Bmask) *Bmask = 0;
            if (Amask) *Amask = 0;
            break;
        default:
            break;
    }
    return SDL_TRUE;
}

Uint32 SDL_MasksToPixelFormatEnum(int bpp, Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask) {
    (void)Gmask;
    if (bpp == 8) return SDL_PIXELFORMAT_INDEX8;
    if (bpp == 16) return SDL_PIXELFORMAT_RGB565;
    if (bpp == 24) return SDL_PIXELFORMAT_RGB24;
    if (Rmask == 0x00FF0000 && Bmask == 0x000000FF) {
        return Amask ? SDL_PIXELFORMAT_ARGB8888 : SDL_PIXELFORMAT_RGB888;
    }
    if (Rmask == 0x000000FF && Bmask == 0x00FF0000) {
        return SDL_PIXELFORMAT_ABGR8888;
    }
    return SDL_PIXELFORMAT_ARGB8888;
}

static void calc_shift_loss(Uint32 mask, Uint8 *shift, Uint8 *loss) {
    *shift = 0;
    *loss = 8;
    if (!mask) return;
    Uint32 m = mask;
    while (!(m & 1U)) {
        m >>= 1;
        (*shift)++;
    }
    while (m & 1U) {
        m >>= 1;
        (*loss)--;
    }
}

SDL_PixelFormat *SDL_AllocFormat(Uint32 pixel_format) {
    SDL_PixelFormat *fmt = (SDL_PixelFormat *)calloc(1, sizeof(SDL_PixelFormat));
    if (!fmt) return NULL;
    int bpp = 32;
    Uint32 rm = 0, gm = 0, bm = 0, am = 0;
    SDL_PixelFormatEnumToMasks(pixel_format, &bpp, &rm, &gm, &bm, &am);
    fmt->format = pixel_format ? pixel_format : SDL_PIXELFORMAT_ARGB8888;
    fmt->BitsPerPixel = (Uint8)bpp;
    fmt->BytesPerPixel = (Uint8)((bpp + 7) / 8);
    fmt->Rmask = rm;
    fmt->Gmask = gm;
    fmt->Bmask = bm;
    fmt->Amask = am;
    calc_shift_loss(rm, &fmt->Rshift, &fmt->Rloss);
    calc_shift_loss(gm, &fmt->Gshift, &fmt->Gloss);
    calc_shift_loss(bm, &fmt->Bshift, &fmt->Bloss);
    calc_shift_loss(am, &fmt->Ashift, &fmt->Aloss);
    fmt->refcount = 1;
    if (bpp <= 8) {
        fmt->palette = SDL_AllocPalette(256);
    }
    return fmt;
}

void SDL_FreeFormat(SDL_PixelFormat *format) {
    if (!format) return;
    if (--format->refcount > 0) return;
    if (format->palette) SDL_FreePalette(format->palette);
    free(format);
}

SDL_Palette *SDL_AllocPalette(int ncolors) {
    if (ncolors <= 0) ncolors = 256;
    SDL_Palette *pal = (SDL_Palette *)calloc(1, sizeof(SDL_Palette));
    if (!pal) return NULL;
    pal->colors = (SDL_Color *)calloc((size_t)ncolors, sizeof(SDL_Color));
    pal->ncolors = ncolors;
    pal->version = 1;
    pal->refcount = 1;
    for (int i = 0; i < ncolors; i++) {
        pal->colors[i].r = pal->colors[i].g = pal->colors[i].b = (Uint8)i;
        pal->colors[i].a = 255;
    }
    return pal;
}

int SDL_SetPixelFormatPalette(SDL_PixelFormat *format, SDL_Palette *palette) {
    if (!format) return -1;
    if (palette) palette->refcount++;
    if (format->palette) SDL_FreePalette(format->palette);
    format->palette = palette;
    return 0;
}

int SDL_SetPaletteColors(SDL_Palette *palette, const SDL_Color *colors, int firstcolor, int ncolors) {
    if (!palette || !colors || firstcolor < 0 || firstcolor + ncolors > palette->ncolors) return -1;
    memcpy(palette->colors + firstcolor, colors, (size_t)ncolors * sizeof(SDL_Color));
    palette->version++;
    return 0;
}

void SDL_FreePalette(SDL_Palette *palette) {
    if (!palette) return;
    if (--palette->refcount > 0) return;
    free(palette->colors);
    free(palette);
}

Uint32 SDL_MapRGB(const SDL_PixelFormat *format, Uint8 r, Uint8 g, Uint8 b) {
    return SDL_MapRGBA(format, r, g, b, 255);
}

Uint32 SDL_MapRGBA(const SDL_PixelFormat *format, Uint8 r, Uint8 g, Uint8 b, Uint8 a) {
    if (!format) {
        return ((Uint32)a << 24) | ((Uint32)r << 16) | ((Uint32)g << 8) | (Uint32)b;
    }
    if (format->palette) {
        return r;
    }
    return ((Uint32)(r >> format->Rloss) << format->Rshift) |
           ((Uint32)(g >> format->Gloss) << format->Gshift) |
           ((Uint32)(b >> format->Bloss) << format->Bshift) |
           (((Uint32)(a >> format->Aloss) << format->Ashift) & format->Amask);
}

void SDL_GetRGB(Uint32 pixel, const SDL_PixelFormat *format, Uint8 *r, Uint8 *g, Uint8 *b) {
    Uint8 a;
    SDL_GetRGBA(pixel, format, r, g, b, &a);
}

void SDL_GetRGBA(Uint32 pixel, const SDL_PixelFormat *format, Uint8 *r, Uint8 *g, Uint8 *b, Uint8 *a) {
    if (!format) {
        if (a) *a = (Uint8)((pixel >> 24) & 0xFF);
        if (r) *r = (Uint8)((pixel >> 16) & 0xFF);
        if (g) *g = (Uint8)((pixel >> 8) & 0xFF);
        if (b) *b = (Uint8)(pixel & 0xFF);
        return;
    }
    if (format->palette) {
        Uint8 idx = (Uint8)(pixel & 0xFF);
        if (idx < format->palette->ncolors) {
            SDL_Color c = format->palette->colors[idx];
            if (r) *r = c.r;
            if (g) *g = c.g;
            if (b) *b = c.b;
            if (a) *a = c.a;
            return;
        }
    }
    if (r) {
        Uint32 v = (pixel & format->Rmask) >> format->Rshift;
        *r = (Uint8)((v << format->Rloss) + (v >> (8 - (format->Rloss << 1))));
    }
    if (g) {
        Uint32 v = (pixel & format->Gmask) >> format->Gshift;
        *g = (Uint8)((v << format->Gloss) + (v >> (8 - (format->Gloss << 1))));
    }
    if (b) {
        Uint32 v = (pixel & format->Bmask) >> format->Bshift;
        *b = (Uint8)((v << format->Bloss) + (v >> (8 - (format->Bloss << 1))));
    }
    if (a) {
        if (format->Amask) {
            Uint32 v = (pixel & format->Amask) >> format->Ashift;
            *a = (Uint8)((v << format->Aloss) + (v >> (8 - (format->Aloss << 1))));
        } else {
            *a = 255;
        }
    }
}

/* Surfaces */
SDL_Surface *SDL_CreateRGBSurfaceWithFormat(Uint32 flags, int width, int height, int depth, Uint32 format) {
    (void)flags;
    if (width < 0 || height < 0) return NULL;
    if (format == 0) {
        format = (depth == 8) ? SDL_PIXELFORMAT_INDEX8 : SDL_PIXELFORMAT_ARGB8888;
    }
    SDL_Surface *surf = (SDL_Surface *)calloc(1, sizeof(SDL_Surface));
    if (!surf) return NULL;

    surf->format = SDL_AllocFormat(format);
    if (!surf->format) {
        free(surf);
        return NULL;
    }
    surf->w = width;
    surf->h = height;
    surf->pitch = width * surf->format->BytesPerPixel;
    size_t sz = (size_t)surf->pitch * (size_t)(height > 0 ? height : 1);
    surf->pixels = calloc(1, sz > 0 ? sz : 4);
    surf->clip_rect.x = 0;
    surf->clip_rect.y = 0;
    surf->clip_rect.w = width;
    surf->clip_rect.h = height;
    surf->refcount = 1;

    SDLSurfacePrivate *priv = (SDLSurfacePrivate *)calloc(1, sizeof(SDLSurfacePrivate));
    if (priv) {
        priv->r_mod = priv->g_mod = priv->b_mod = priv->a_mod = 255;
        priv->blend_mode = SDL_BLENDMODE_NONE;
        surf->map = (struct SDL_BlitMap *)priv;
    }
    return surf;
}

SDL_Surface *SDL_CreateRGBSurface(Uint32 flags, int width, int height, int depth,
                                  Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask) {
    Uint32 fmt = SDL_MasksToPixelFormatEnum(depth, Rmask, Gmask, Bmask, Amask);
    return SDL_CreateRGBSurfaceWithFormat(flags, width, height, depth, fmt);
}

SDL_Surface *SDL_CreateRGBSurfaceWithFormatFrom(void *pixels, int width, int height, int depth, int pitch, Uint32 format) {
    SDL_Surface *surf = SDL_CreateRGBSurfaceWithFormat(0, 0, 0, depth, format);
    if (!surf) return NULL;
    free(surf->pixels);
    surf->flags |= SDL_PREALLOC;
    surf->pixels = pixels;
    surf->w = width;
    surf->h = height;
    surf->pitch = pitch;
    surf->clip_rect.x = 0;
    surf->clip_rect.y = 0;
    surf->clip_rect.w = width;
    surf->clip_rect.h = height;
    return surf;
}

SDL_Surface *SDL_CreateRGBSurfaceFrom(void *pixels, int width, int height, int depth, int pitch,
                                      Uint32 Rmask, Uint32 Gmask, Uint32 Bmask, Uint32 Amask) {
    Uint32 fmt = SDL_MasksToPixelFormatEnum(depth, Rmask, Gmask, Bmask, Amask);
    return SDL_CreateRGBSurfaceWithFormatFrom(pixels, width, height, depth, pitch, fmt);
}

void SDL_FreeSurface(SDL_Surface *surface) {
    if (!surface) return;
    if (--surface->refcount > 0) return;
    if (!(surface->flags & SDL_PREALLOC)) {
        free(surface->pixels);
    }
    if (surface->format) {
        SDL_FreeFormat(surface->format);
    }
    if (surface->map) {
        free(surface->map);
    }
    free(surface);
}

int SDL_SetSurfacePalette(SDL_Surface *surface, SDL_Palette *palette) {
    if (!surface || !surface->format) return -1;
    return SDL_SetPixelFormatPalette(surface->format, palette);
}

int SDL_LockSurface(SDL_Surface *surface) {
    if (!surface) return -1;
    surface->locked++;
    return 0;
}

void SDL_UnlockSurface(SDL_Surface *surface) {
    if (!surface) return;
    if (surface->locked > 0) surface->locked--;
}

int SDL_SetColorKey(SDL_Surface *surface, int flag, Uint32 key) {
    if (!surface || !surface->map) return -1;
    SDLSurfacePrivate *priv = (SDLSurfacePrivate *)surface->map;
    priv->has_color_key = flag ? SDL_TRUE : SDL_FALSE;
    priv->color_key = key;
    return 0;
}

SDL_bool SDL_HasColorKey(SDL_Surface *surface) {
    if (!surface || !surface->map) return SDL_FALSE;
    return ((SDLSurfacePrivate *)surface->map)->has_color_key;
}

int SDL_GetColorKey(SDL_Surface *surface, Uint32 *key) {
    if (!surface || !surface->map) return -1;
    SDLSurfacePrivate *priv = (SDLSurfacePrivate *)surface->map;
    if (!priv->has_color_key) return -1;
    if (key) *key = priv->color_key;
    return 0;
}

int SDL_SetSurfaceColorMod(SDL_Surface *surface, Uint8 r, Uint8 g, Uint8 b) {
    if (!surface || !surface->map) return -1;
    SDLSurfacePrivate *priv = (SDLSurfacePrivate *)surface->map;
    priv->r_mod = r; priv->g_mod = g; priv->b_mod = b;
    return 0;
}

int SDL_GetSurfaceColorMod(SDL_Surface *surface, Uint8 *r, Uint8 *g, Uint8 *b) {
    if (!surface || !surface->map) return -1;
    SDLSurfacePrivate *priv = (SDLSurfacePrivate *)surface->map;
    if (r) *r = priv->r_mod;
    if (g) *g = priv->g_mod;
    if (b) *b = priv->b_mod;
    return 0;
}

int SDL_SetSurfaceAlphaMod(SDL_Surface *surface, Uint8 alpha) {
    if (!surface || !surface->map) return -1;
    ((SDLSurfacePrivate *)surface->map)->a_mod = alpha;
    return 0;
}

int SDL_GetSurfaceAlphaMod(SDL_Surface *surface, Uint8 *alpha) {
    if (!surface || !surface->map) return -1;
    if (alpha) *alpha = ((SDLSurfacePrivate *)surface->map)->a_mod;
    return 0;
}

int SDL_SetSurfaceBlendMode(SDL_Surface *surface, SDL_BlendMode blendMode) {
    if (!surface || !surface->map) return -1;
    ((SDLSurfacePrivate *)surface->map)->blend_mode = blendMode;
    return 0;
}

int SDL_GetSurfaceBlendMode(SDL_Surface *surface, SDL_BlendMode *blendMode) {
    if (!surface || !surface->map) return -1;
    if (blendMode) *blendMode = ((SDLSurfacePrivate *)surface->map)->blend_mode;
    return 0;
}

SDL_bool SDL_SetClipRect(SDL_Surface *surface, const SDL_Rect *rect) {
    if (!surface) return SDL_FALSE;
    SDL_Rect full = { 0, 0, surface->w, surface->h };
    if (!rect) {
        surface->clip_rect = full;
        return SDL_TRUE;
    }
    return SDL_IntersectRect(rect, &full, &surface->clip_rect);
}

void SDL_GetClipRect(SDL_Surface *surface, SDL_Rect *rect) {
    if (surface && rect) *rect = surface->clip_rect;
}

SDL_Surface *SDL_DuplicateSurface(SDL_Surface *surface) {
    if (!surface) return NULL;
    return SDL_ConvertSurface(surface, surface->format, 0);
}

SDL_Surface *SDL_ConvertSurface(SDL_Surface *src, const SDL_PixelFormat *fmt, Uint32 flags) {
    if (!src || !fmt) return NULL;
    SDL_Surface *dst = SDL_CreateRGBSurfaceWithFormat(flags, src->w, src->h, fmt->BitsPerPixel, fmt->format);
    if (!dst) return NULL;
    SDL_UpperBlit(src, NULL, dst, NULL);
    return dst;
}

SDL_Surface *SDL_ConvertSurfaceFormat(SDL_Surface *src, Uint32 pixel_format, Uint32 flags) {
    SDL_PixelFormat *fmt = SDL_AllocFormat(pixel_format);
    if (!fmt) return NULL;
    SDL_Surface *dst = SDL_ConvertSurface(src, fmt, flags);
    SDL_FreeFormat(fmt);
    return dst;
}

int SDL_ConvertPixels(int width, int height, Uint32 src_format, const void *src, int src_pitch,
                      Uint32 dst_format, void *dst, int dst_pitch) {
    if (src_format == dst_format && src_pitch == dst_pitch) {
        memcpy(dst, src, (size_t)src_pitch * (size_t)height);
        return 0;
    }
    SDL_Surface *s = SDL_CreateRGBSurfaceWithFormatFrom((void *)src, width, height, 32, src_pitch, src_format);
    SDL_Surface *d = SDL_CreateRGBSurfaceWithFormatFrom(dst, width, height, 32, dst_pitch, dst_format);
    if (!s || !d) {
        SDL_FreeSurface(s);
        SDL_FreeSurface(d);
        return -1;
    }
    SDL_UpperBlit(s, NULL, d, NULL);
    SDL_FreeSurface(s);
    SDL_FreeSurface(d);
    return 0;
}

int SDL_FillRect(SDL_Surface *dst, const SDL_Rect *rect, Uint32 color) {
    if (!dst || !dst->pixels) return -1;
    SDL_Rect r = dst->clip_rect;
    if (rect && !SDL_IntersectRect(rect, &dst->clip_rect, &r)) {
        return 0;
    }
    int bpp = dst->format ? dst->format->BytesPerPixel : 4;
    for (int y = r.y; y < r.y + r.h; y++) {
        Uint8 *row = (Uint8 *)dst->pixels + y * dst->pitch + r.x * bpp;
        if (bpp == 4) {
            Uint32 *p = (Uint32 *)row;
            for (int x = 0; x < r.w; x++) p[x] = color;
        } else if (bpp == 2) {
            Uint16 *p = (Uint16 *)row;
            for (int x = 0; x < r.w; x++) p[x] = (Uint16)color;
        } else if (bpp == 1) {
            memset(row, (int)(color & 0xFF), (size_t)r.w);
        }
    }
    return 0;
}

int SDL_FillRects(SDL_Surface *dst, const SDL_Rect *rects, int count, Uint32 color) {
    if (!dst || !rects) return -1;
    for (int i = 0; i < count; i++) {
        SDL_FillRect(dst, &rects[i], color);
    }
    return 0;
}

static Uint32 read_pixel(const SDL_Surface *s, int x, int y) {
    const Uint8 *p = (const Uint8 *)s->pixels + y * s->pitch + x * s->format->BytesPerPixel;
    switch (s->format->BytesPerPixel) {
        case 1: return *p;
        case 2: return *(const Uint16 *)p;
        case 3: return (Uint32)p[0] | ((Uint32)p[1] << 8) | ((Uint32)p[2] << 16);
        default: return *(const Uint32 *)p;
    }
}

static void write_pixel(SDL_Surface *s, int x, int y, Uint32 val) {
    Uint8 *p = (Uint8 *)s->pixels + y * s->pitch + x * s->format->BytesPerPixel;
    switch (s->format->BytesPerPixel) {
        case 1: *p = (Uint8)val; break;
        case 2: *(Uint16 *)p = (Uint16)val; break;
        case 3:
            p[0] = (Uint8)(val & 0xFF);
            p[1] = (Uint8)((val >> 8) & 0xFF);
            p[2] = (Uint8)((val >> 16) & 0xFF);
            break;
        default: *(Uint32 *)p = val; break;
    }
}

int SDL_UpperBlit(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect) {
    if (!src || !dst || !src->pixels || !dst->pixels) return -1;
    SDL_Rect sr = { 0, 0, src->w, src->h };
    if (srcrect && !SDL_IntersectRect(srcrect, &sr, &sr)) return 0;

    int dx = dstrect ? dstrect->x : 0;
    int dy = dstrect ? dstrect->y : 0;
    SDL_Rect dr = { dx, dy, sr.w, sr.h };
    SDL_Rect clipped;
    if (!SDL_IntersectRect(&dr, &dst->clip_rect, &clipped)) {
        if (dstrect) { dstrect->w = 0; dstrect->h = 0; }
        return 0;
    }
    sr.x += clipped.x - dr.x;
    sr.y += clipped.y - dr.y;
    sr.w = clipped.w;
    sr.h = clipped.h;
    if (dstrect) *dstrect = clipped;

    SDLSurfacePrivate *priv = (SDLSurfacePrivate *)src->map;
    SDL_bool has_ck = priv ? priv->has_color_key : SDL_FALSE;
    Uint32 ck = priv ? priv->color_key : 0;

    if (!has_ck && src->format->format == dst->format->format &&
        (!priv || priv->blend_mode == SDL_BLENDMODE_NONE)) {
        int bpp = src->format->BytesPerPixel;
        for (int y = 0; y < sr.h; y++) {
            const Uint8 *srow = (const Uint8 *)src->pixels + (sr.y + y) * src->pitch + sr.x * bpp;
            Uint8 *drow = (Uint8 *)dst->pixels + (clipped.y + y) * dst->pitch + clipped.x * bpp;
            memcpy(drow, srow, (size_t)sr.w * (size_t)bpp);
        }
        return 0;
    }

    for (int y = 0; y < sr.h; y++) {
        for (int x = 0; x < sr.w; x++) {
            Uint32 spx = read_pixel(src, sr.x + x, sr.y + y);
            if (has_ck && spx == ck) continue;
            Uint8 r, g, b, a;
            SDL_GetRGBA(spx, src->format, &r, &g, &b, &a);
            if (priv && priv->blend_mode == SDL_BLENDMODE_BLEND && a < 255) {
                if (a == 0) continue;
                Uint8 dr_c, dg_c, db_c, da_c;
                Uint32 dpx = read_pixel(dst, clipped.x + x, clipped.y + y);
                SDL_GetRGBA(dpx, dst->format, &dr_c, &dg_c, &db_c, &da_c);
                r = (Uint8)(((int)r * a + (int)dr_c * (255 - a)) / 255);
                g = (Uint8)(((int)g * a + (int)dg_c * (255 - a)) / 255);
                b = (Uint8)(((int)b * a + (int)db_c * (255 - a)) / 255);
                a = 255;
            }
            write_pixel(dst, clipped.x + x, clipped.y + y, SDL_MapRGBA(dst->format, r, g, b, a));
        }
    }
    return 0;
}

int SDL_LowerBlit(SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect) {
    return SDL_UpperBlit(src, srcrect, dst, dstrect);
}

int SDL_UpperBlitScaled(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect) {
    if (!src || !dst || !src->pixels || !dst->pixels) return -1;
    SDL_Rect sr = { 0, 0, src->w, src->h };
    if (srcrect && !SDL_IntersectRect(srcrect, &sr, &sr)) return 0;
    SDL_Rect dr = { 0, 0, dst->w, dst->h };
    if (dstrect) dr = *dstrect;
    if (dr.w <= 0 || dr.h <= 0 || sr.w <= 0 || sr.h <= 0) return 0;

    for (int y = 0; y < dr.h; y++) {
        int dy = dr.y + y;
        if (dy < dst->clip_rect.y || dy >= dst->clip_rect.y + dst->clip_rect.h) continue;
        int sy = sr.y + (y * sr.h) / dr.h;
        for (int x = 0; x < dr.w; x++) {
            int dx = dr.x + x;
            if (dx < dst->clip_rect.x || dx >= dst->clip_rect.x + dst->clip_rect.w) continue;
            int sx = sr.x + (x * sr.w) / dr.w;
            Uint32 spx = read_pixel(src, sx, sy);
            Uint8 r, g, b, a;
            SDL_GetRGBA(spx, src->format, &r, &g, &b, &a);
            write_pixel(dst, dx, dy, SDL_MapRGBA(dst->format, r, g, b, a));
        }
    }
    return 0;
}

int SDL_LowerBlitScaled(SDL_Surface *src, SDL_Rect *srcrect, SDL_Surface *dst, SDL_Rect *dstrect) {
    return SDL_UpperBlitScaled(src, srcrect, dst, dstrect);
}

int SDL_SoftStretch(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst, const SDL_Rect *dstrect) {
    SDL_Rect dr = dstrect ? *dstrect : (SDL_Rect){ 0, 0, dst ? dst->w : 0, dst ? dst->h : 0 };
    return SDL_UpperBlitScaled(src, srcrect, dst, &dr);
}

int SDL_SoftStretchLinear(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst, const SDL_Rect *dstrect) {
    return SDL_SoftStretch(src, srcrect, dst, dstrect);
}

int SDL_SetSurfaceRLE(SDL_Surface *surface, int flag) {
    (void)surface; (void)flag;
    return 0;
}

SDL_bool SDL_HasSurfaceRLE(SDL_Surface *surface) {
    (void)surface;
    return SDL_FALSE;
}

SDL_Surface *SDL_LoadBMP_RW(SDL_RWops *src, int freesrc) {
    if (!src) return NULL;
    Uint8 hdr[54];
    if (SDL_RWread(src, hdr, 1, 54) != 54 || hdr[0] != 'B' || hdr[1] != 'M') {
        if (freesrc) SDL_RWclose(src);
        return NULL;
    }
    Uint32 data_off = (Uint32)hdr[10] | ((Uint32)hdr[11] << 8) | ((Uint32)hdr[12] << 16) | ((Uint32)hdr[13] << 24);
    Sint32 w = (Sint32)((Uint32)hdr[18] | ((Uint32)hdr[19] << 8) | ((Uint32)hdr[20] << 16) | ((Uint32)hdr[21] << 24));
    Sint32 h = (Sint32)((Uint32)hdr[22] | ((Uint32)hdr[23] << 8) | ((Uint32)hdr[24] << 16) | ((Uint32)hdr[25] << 24));
    Uint16 bpp = (Uint16)(hdr[28] | (hdr[29] << 8));
    SDL_bool flip = (h > 0) ? SDL_TRUE : SDL_FALSE;
    if (h < 0) h = -h;

    SDL_Surface *surf = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_ARGB8888);
    if (!surf) {
        if (freesrc) SDL_RWclose(src);
        return NULL;
    }
    SDL_RWseek(src, data_off, RW_SEEK_SET);
    int row_bytes = ((w * bpp + 31) / 32) * 4;
    Uint8 *row_buf = (Uint8 *)malloc((size_t)row_bytes);
    if (row_buf) {
        for (int y = 0; y < h; y++) {
            int dst_y = flip ? (h - 1 - y) : y;
            if (SDL_RWread(src, row_buf, 1, (size_t)row_bytes) != (size_t)row_bytes) break;
            Uint32 *dst_row = (Uint32 *)((Uint8 *)surf->pixels + dst_y * surf->pitch);
            for (int x = 0; x < w; x++) {
                if (bpp == 24) {
                    Uint8 b = row_buf[x * 3 + 0];
                    Uint8 g = row_buf[x * 3 + 1];
                    Uint8 r = row_buf[x * 3 + 2];
                    dst_row[x] = 0xFF000000U | ((Uint32)r << 16) | ((Uint32)g << 8) | b;
                } else if (bpp == 32) {
                    Uint8 b = row_buf[x * 4 + 0];
                    Uint8 g = row_buf[x * 4 + 1];
                    Uint8 r = row_buf[x * 4 + 2];
                    Uint8 a = row_buf[x * 4 + 3];
                    dst_row[x] = ((Uint32)a << 24) | ((Uint32)r << 16) | ((Uint32)g << 8) | b;
                }
            }
        }
        free(row_buf);
    }
    if (freesrc) SDL_RWclose(src);
    return surf;
}

int SDL_SaveBMP_RW(SDL_Surface *surface, SDL_RWops *dst, int freedst) {
    if (!surface || !dst) return -1;
    if (freedst) SDL_RWclose(dst);
    return 0;
}
