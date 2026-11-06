/*
 * OpenGL / CGL implementation for ravynOS.
 *
 * Implements the Core OpenGL (CGL) API surface that AppKit (NSOpenGLContext,
 * NSOpenGLPixelFormat) and stock macOS binaries (Firefox ESR XUL) bind at
 * runtime. Provides a clean software-renderer contract: pixel formats and
 * contexts can be created, queried, and managed; acceleration is reported as
 * 0 (software rasterizer), allowing applications to cleanly fall back to
 * software rendering without crashing or raising unrecognized selectors.
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <pthread.h>

#include "include/OpenGL.h"

typedef struct __IOSurface *IOSurfaceRef;

/* -------------------------------------------------------------------------
 * Internal structures
 * ------------------------------------------------------------------------- */

struct _CGLPixelFormatObject {
    int refcount;
    GLint numScreens;
    GLint colorSize;
    GLint alphaSize;
    GLint depthSize;
    GLint stencilSize;
    GLint accumSize;
    GLint doubleBuffer;
    GLint stereo;
    GLint auxBuffers;
    GLint offScreen;
    GLint fullScreen;
    GLint sampleBuffers;
    GLint samples;
    GLint rendererID;
    GLint accelerated;
    GLint window;
    GLint pbuffer;
    CGLPixelFormatAttribute *attributes;
    int numAttributes;
};

struct _CGLContextObject {
    int refcount;
    struct _CGLPixelFormatObject *pixelFormat;
    struct _CGLContextObject *shareContext;
    int lockCount;
    GLint swapInterval;
    GLint surfaceOpacity;
    GLint surfaceBackingSize[2];
    GLint surfaceBackingOrigin[2];
    GLint windowNumber;
    void *drawable;
};

struct _CGLPBufferObject {
    int refcount;
    GLsizei width;
    GLsizei height;
    GLenum target;
    GLenum internalFormat;
    GLint maxDetail;
};

/* -------------------------------------------------------------------------
 * Pixel format management
 * ------------------------------------------------------------------------- */

CGLError CGLChoosePixelFormat(const CGLPixelFormatAttribute *attributes,
                              CGLPixelFormatObj *pixelFormatp,
                              GLint *numberOfScreensp)
{
    if (!pixelFormatp || !numberOfScreensp)
        return kCGLBadValue;

    *pixelFormatp = NULL;
    *numberOfScreensp = 0;

    struct _CGLPixelFormatObject *pf = (struct _CGLPixelFormatObject *)calloc(1, sizeof(struct _CGLPixelFormatObject));
    if (!pf)
        return kCGLBadAlloc;

    pf->refcount = 1;
    pf->numScreens = 1;
    pf->colorSize = 32;
    pf->alphaSize = 8;
    pf->depthSize = 24;
    pf->stencilSize = 8;
    pf->doubleBuffer = 0;
    pf->accelerated = 0; /* Software rendering on ravynOS */
    pf->window = 1;

    if (attributes) {
        int count = 0;
        while (attributes[count] != 0) {
            CGLPixelFormatAttribute attr = attributes[count++];
            switch (attr) {
            case kCGLPFAColorSize:
            case kCGLPFAAlphaSize:
            case kCGLPFADepthSize:
            case kCGLPFAStencilSize:
            case kCGLPFAAccumSize:
            case kCGLPFAMinimumPolicy:
            case kCGLPFAMaximumPolicy:
            case kCGLPFASampleBuffers:
            case kCGLPFASamples:
            case kCGLPFARendererID:
            case kCGLPFADisplayMask:
                count++;
                break;
            default:
                break;
            }
        }
        pf->attributes = (CGLPixelFormatAttribute *)malloc((count + 1) * sizeof(CGLPixelFormatAttribute));
        if (pf->attributes) {
            memcpy(pf->attributes, attributes, (count + 1) * sizeof(CGLPixelFormatAttribute));
            pf->numAttributes = count;
        }

        int i = 0;
        while (attributes[i] != 0) {
            CGLPixelFormatAttribute attr = attributes[i++];
            switch (attr) {
            case kCGLPFAColorSize:
                pf->colorSize = (GLint)attributes[i++];
                break;
            case kCGLPFAAlphaSize:
                pf->alphaSize = (GLint)attributes[i++];
                break;
            case kCGLPFADepthSize:
                pf->depthSize = (GLint)attributes[i++];
                break;
            case kCGLPFAStencilSize:
                pf->stencilSize = (GLint)attributes[i++];
                break;
            case kCGLPFAAccumSize:
                pf->accumSize = (GLint)attributes[i++];
                break;
            case kCGLPFADoubleBuffer:
                pf->doubleBuffer = 1;
                break;
            case kCGLPFAStereo:
                pf->stereo = 1;
                break;
            case kCGLPFAAuxBuffers:
                pf->auxBuffers = 1;
                break;
            case kCGLPFAOffScreen:
                pf->offScreen = 1;
                break;
            case kCGLPFAFullScreen:
                pf->fullScreen = 1;
                break;
            case kCGLPFASampleBuffers:
                pf->sampleBuffers = (GLint)attributes[i++];
                break;
            case kCGLPFASamples:
                pf->samples = (GLint)attributes[i++];
                break;
            case kCGLPFARendererID:
                pf->rendererID = (GLint)attributes[i++];
                break;
            case kCGLPFAAccelerated:
                pf->accelerated = 0;
                break;
            case kCGLPFAWindow:
                pf->window = 1;
                break;
            case kCGLPFAPBuffer:
                pf->pbuffer = 1;
                break;
            case kCGLPFAVirtualScreenCount:
                break;
            default:
                break;
            }
        }
    }

    *pixelFormatp = pf;
    *numberOfScreensp = pf->numScreens;
    return kCGLNoError;
}

CGLPixelFormatObj CGLRetainPixelFormat(CGLPixelFormatObj pixelFormat)
{
    if (pixelFormat)
        pixelFormat->refcount++;
    return pixelFormat;
}

void CGLReleasePixelFormat(CGLPixelFormatObj pixelFormat)
{
    if (pixelFormat && --pixelFormat->refcount <= 0)
        CGLDestroyPixelFormat(pixelFormat);
}

CGLError CGLDestroyPixelFormat(CGLPixelFormatObj pixelFormat)
{
    if (!pixelFormat)
        return kCGLBadPixelFormat;
    if (pixelFormat->attributes)
        free(pixelFormat->attributes);
    free(pixelFormat);
    return kCGLNoError;
}

GLuint CGLGetPixelFormatRetainCount(CGLPixelFormatObj pixelFormat)
{
    if (!pixelFormat)
        return 0;
    return (GLuint)pixelFormat->refcount;
}

CGLError CGLDescribePixelFormat(CGLPixelFormatObj pixelFormat,
                                GLint screenNumber,
                                CGLPixelFormatAttribute attribute,
                                GLint *valuep)
{
    if (!pixelFormat || !valuep)
        return kCGLBadPixelFormat;
    if (screenNumber < 0 || screenNumber >= pixelFormat->numScreens)
        return kCGLBadValue;

    switch (attribute) {
    case kCGLPFAColorSize:
        *valuep = pixelFormat->colorSize;
        break;
    case kCGLPFAAlphaSize:
        *valuep = pixelFormat->alphaSize;
        break;
    case kCGLPFADepthSize:
        *valuep = pixelFormat->depthSize;
        break;
    case kCGLPFAStencilSize:
        *valuep = pixelFormat->stencilSize;
        break;
    case kCGLPFAAccumSize:
        *valuep = pixelFormat->accumSize;
        break;
    case kCGLPFADoubleBuffer:
        *valuep = pixelFormat->doubleBuffer;
        break;
    case kCGLPFAStereo:
        *valuep = pixelFormat->stereo;
        break;
    case kCGLPFAAuxBuffers:
        *valuep = pixelFormat->auxBuffers;
        break;
    case kCGLPFAOffScreen:
        *valuep = pixelFormat->offScreen;
        break;
    case kCGLPFAFullScreen:
        *valuep = pixelFormat->fullScreen;
        break;
    case kCGLPFASampleBuffers:
        *valuep = pixelFormat->sampleBuffers;
        break;
    case kCGLPFASamples:
        *valuep = pixelFormat->samples;
        break;
    case kCGLPFARendererID:
        *valuep = pixelFormat->rendererID;
        break;
    case kCGLPFAAccelerated:
        *valuep = pixelFormat->accelerated;
        break;
    case kCGLPFAWindow:
        *valuep = pixelFormat->window;
        break;
    case kCGLPFAPBuffer:
        *valuep = pixelFormat->pbuffer;
        break;
    case kCGLPFAVirtualScreenCount:
        *valuep = pixelFormat->numScreens;
        break;
    default:
        *valuep = 0;
        break;
    }
    return kCGLNoError;
}

/* -------------------------------------------------------------------------
 * Context management
 * ------------------------------------------------------------------------- */

static _Thread_local CGLContextObj sCurrentCGLContext = NULL;

CGLContextObj CGLGetCurrentContext(void)
{
    return sCurrentCGLContext;
}

CGLError CGLSetCurrentContext(CGLContextObj context)
{
    sCurrentCGLContext = context;
    return kCGLNoError;
}

CGLError CGLCreateContext(CGLPixelFormatObj pixelFormat,
                         CGLContextObj share,
                         CGLContextObj *result)
{
    if (!pixelFormat || !result)
        return kCGLBadPixelFormat;

    struct _CGLContextObject *ctx = (struct _CGLContextObject *)calloc(1, sizeof(struct _CGLContextObject));
    if (!ctx)
        return kCGLBadAlloc;

    ctx->refcount = 1;
    ctx->pixelFormat = CGLRetainPixelFormat(pixelFormat);
    if (share)
        ctx->shareContext = CGLRetainContext(share);
    ctx->swapInterval = 1;
    ctx->surfaceOpacity = 1;

    *result = ctx;
    return kCGLNoError;
}

CGLContextObj CGLRetainContext(CGLContextObj context)
{
    if (context)
        context->refcount++;
    return context;
}

void CGLReleaseContext(CGLContextObj context)
{
    if (context && --context->refcount <= 0)
        CGLDestroyContext(context);
}

GLuint CGLGetContextRetainCount(CGLContextObj context)
{
    if (!context)
        return 0;
    return (GLuint)context->refcount;
}

CGLError CGLDestroyContext(CGLContextObj context)
{
    if (!context)
        return kCGLBadContext;
    if (CGLGetCurrentContext() == context)
        CGLSetCurrentContext(NULL);
    if (context->pixelFormat)
        CGLReleasePixelFormat(context->pixelFormat);
    if (context->shareContext)
        CGLReleaseContext(context->shareContext);
    free(context);
    return kCGLNoError;
}

CGLError CGLLockContext(CGLContextObj context)
{
    if (!context)
        return kCGLBadContext;
    context->lockCount++;
    return kCGLNoError;
}

CGLError CGLUnlockContext(CGLContextObj context)
{
    if (!context)
        return kCGLBadContext;
    if (context->lockCount > 0)
        context->lockCount--;
    return kCGLNoError;
}

CGLError CGLSetParameter(CGLContextObj context, CGLContextParameter parameter, const GLint *value)
{
    if (!context || !value)
        return kCGLBadContext;

    switch (parameter) {
    case kCGLCPSwapInterval:
        context->swapInterval = *value;
        break;
    case kCGLCPSurfaceOpacity:
        context->surfaceOpacity = *value;
        break;
    case kCGLCPSurfaceBackingSize:
        context->surfaceBackingSize[0] = value[0];
        context->surfaceBackingSize[1] = value[1];
        break;
    case kCGLCPWindowNumber:
        context->windowNumber = *value;
        break;
    default:
        break;
    }
    return kCGLNoError;
}

CGLError CGLGetParameter(CGLContextObj context, CGLContextParameter parameter, GLint *value)
{
    if (!context || !value)
        return kCGLBadContext;

    switch (parameter) {
    case kCGLCPSwapInterval:
        *value = context->swapInterval;
        break;
    case kCGLCPSurfaceOpacity:
        *value = context->surfaceOpacity;
        break;
    case kCGLCPSurfaceBackingSize:
        value[0] = context->surfaceBackingSize[0];
        value[1] = context->surfaceBackingSize[1];
        break;
    case kCGLCPWindowNumber:
        *value = context->windowNumber;
        break;
    default:
        *value = 0;
        break;
    }
    return kCGLNoError;
}

CGLError CGLFlushDrawable(CGLContextObj context)
{
    if (!context)
        return kCGLBadContext;
    return kCGLNoError;
}

/* -------------------------------------------------------------------------
 * Enables, options, and screen management
 * ------------------------------------------------------------------------- */

typedef enum {
    kCGLCESwapRectangle = 201,
    kCGLCESwapLimit = 203,
    kCGLCERasterization = 221,
    kCGLCEStateValidation = 301,
    kCGLCESurfaceBackingSize = 305,
    kCGLCEDisplay = 306,
    kCGLCEMPSafe = 307
} CGLContextEnable;

CGLError CGLEnable(CGLContextObj ctx, CGLContextEnable pname)
{
    if (!ctx)
        return kCGLBadContext;
    (void)pname;
    return kCGLNoError;
}

CGLError CGLDisable(CGLContextObj ctx, CGLContextEnable pname)
{
    if (!ctx)
        return kCGLBadContext;
    (void)pname;
    return kCGLNoError;
}

CGLError CGLIsEnabled(CGLContextObj ctx, CGLContextEnable pname, GLint *enable)
{
    if (!ctx || !enable)
        return kCGLBadContext;
    (void)pname;
    *enable = 0;
    return kCGLNoError;
}

CGLError CGLSetVirtualScreen(CGLContextObj ctx, GLint screen)
{
    if (!ctx)
        return kCGLBadContext;
    if (screen < 0 || (ctx->pixelFormat && screen >= ctx->pixelFormat->numScreens))
        return kCGLBadValue;
    return kCGLNoError;
}

CGLError CGLGetVirtualScreen(CGLContextObj ctx, GLint *screen)
{
    if (!ctx || !screen)
        return kCGLBadContext;
    *screen = 0;
    return kCGLNoError;
}

CGLError CGLUpdateContext(CGLContextObj ctx)
{
    if (!ctx)
        return kCGLBadContext;
    return kCGLNoError;
}

CGLPixelFormatObj CGLGetPixelFormat(CGLContextObj ctx)
{
    if (!ctx)
        return NULL;
    return ctx->pixelFormat;
}

CGLError CGLClearDrawable(CGLContextObj ctx)
{
    if (!ctx)
        return kCGLBadContext;
    ctx->drawable = NULL;
    return kCGLNoError;
}

CGLError CGLCopyContext(CGLContextObj src, CGLContextObj dst, GLbitfield mask)
{
    if (!src || !dst)
        return kCGLBadContext;
    (void)mask;
    return kCGLNoError;
}

void *CGLGetShareGroup(CGLContextObj ctx)
{
    (void)ctx;
    return NULL;
}

CGLError CGLGetSurface(CGLContextObj ctx, void **connection, void **window, void **surface)
{
    if (!ctx)
        return kCGLBadContext;
    (void)connection; (void)window; (void)surface;
    return kCGLNoError;
}

CGLError CGLSetSurface(CGLContextObj ctx, void *connection, void *window, void *surface)
{
    if (!ctx)
        return kCGLBadContext;
    (void)connection; (void)window; (void)surface;
    return kCGLNoError;
}

CGLError CGLGetOffScreen(CGLContextObj ctx, GLsizei *width, GLsizei *height, GLint *rowbytes, void **baseaddr)
{
    if (!ctx)
        return kCGLBadContext;
    (void)width; (void)height; (void)rowbytes; (void)baseaddr;
    return kCGLNoError;
}

CGLError CGLSetOffScreen(CGLContextObj ctx, GLsizei width, GLsizei height, GLint rowbytes, void *baseaddr)
{
    if (!ctx)
        return kCGLBadContext;
    (void)width; (void)height; (void)rowbytes; (void)baseaddr;
    return kCGLNoError;
}

CGLError CGLSetFullScreen(CGLContextObj ctx)
{
    if (!ctx)
        return kCGLBadContext;
    return kCGLNoError;
}

CGLError CGLSetFullScreenOnDisplay(CGLContextObj ctx, GLuint display_mask)
{
    if (!ctx)
        return kCGLBadContext;
    (void)display_mask;
    return kCGLNoError;
}

typedef enum {
    kCGLGOFormatCacheSize = 501,
    kCGLGOClearFormatCache = 502,
    kCGLGORetainRenderers = 503,
    kCGLGOResetLibrary = 504,
    kCGLGOUseTrackingRasterizer = 505,
    kCGLGORendererCacheSize = 506
} CGLGlobalOption;

CGLError CGLGetOption(CGLGlobalOption option, GLint *value)
{
    if (!value)
        return kCGLBadValue;
    *value = 0;
    return kCGLNoError;
}

CGLError CGLSetOption(CGLGlobalOption option, GLint value)
{
    (void)option; (void)value;
    return kCGLNoError;
}

CGLError CGLGetGlobalOption(CGLGlobalOption option, GLint *value)
{
    return CGLGetOption(option, value);
}

CGLError CGLSetGlobalOption(CGLGlobalOption option, GLint value)
{
    return CGLSetOption(option, value);
}

void CGLGetVersion(GLint *majorvers, GLint *minorvers)
{
    if (majorvers)
        *majorvers = 1;
    if (minorvers)
        *minorvers = 0;
}

const char *CGLErrorString(CGLError error)
{
    switch (error) {
    case kCGLNoError: return "no error";
    case kCGLBadAttribute: return "invalid pixel format attribute";
    case kCGLBadProperty: return "invalid property or parameter";
    case kCGLBadPixelFormat: return "invalid pixel format";
    case kCGLBadRendererInfo: return "invalid renderer info";
    case kCGLBadContext: return "invalid context";
    case kCGLBadDrawable: return "invalid drawable";
    case kCGLBadDisplay: return "invalid display";
    case kCGLBadState: return "invalid state";
    case kCGLBadValue: return "invalid numerical value";
    case kCGLBadMatch: return "invalid share context match";
    case kCGLBadEnumeration: return "invalid enumerant";
    case kCGLBadOffScreen: return "invalid offscreen drawable";
    case kCGLBadFullScreen: return "invalid fullscreen drawable";
    case kCGLBadWindow: return "invalid window";
    case kCGLBadAddress: return "invalid pointer";
    case kCGLBadCodeModule: return "invalid code module";
    case kCGLBadAlloc: return "out of memory";
    case kCGLBadConnection: return "invalid connection to WindowServer";
    default: return "unknown CGL error";
    }
}

/* -------------------------------------------------------------------------
 * IOSurface texture binding
 * ------------------------------------------------------------------------- */

CGLError CGLTexImageIOSurface2D(CGLContextObj ctx, GLenum target, GLenum internal_format,
                                GLsizei width, GLsizei height, GLenum format, GLenum type,
                                IOSurfaceRef ioSurface, GLuint plane)
{
    if (!ctx)
        return kCGLBadContext;
    (void)target; (void)internal_format; (void)width; (void)height;
    (void)format; (void)type; (void)ioSurface; (void)plane;
    return kCGLNoError;
}

/* -------------------------------------------------------------------------
 * Renderer info queries
 * ------------------------------------------------------------------------- */

typedef struct _CGLRendererInfoObject *CGLRendererInfoObj;

CGLError CGLQueryRendererInfo(GLuint display_mask, CGLRendererInfoObj *rend, GLint *nrend)
{
    (void)display_mask;
    if (rend)
        *rend = NULL;
    if (nrend)
        *nrend = 0;
    return kCGLNoError;
}

CGLError CGLDestroyRendererInfo(CGLRendererInfoObj rend)
{
    (void)rend;
    return kCGLNoError;
}

CGLError CGLDescribeRenderer(CGLRendererInfoObj rend, GLint rend_num, CGLPixelFormatAttribute prop, GLint *value)
{
    (void)rend; (void)rend_num; (void)prop;
    if (!value)
        return kCGLBadValue;
    *value = 0;
    return kCGLNoError;
}

/* -------------------------------------------------------------------------
 * PBuffer operations
 * ------------------------------------------------------------------------- */

CGLError CGLCreatePBuffer(GLsizei width, GLsizei height, GLenum target,
                          GLenum internalFormat, GLint maxDetail,
                          CGLPBufferObj *pbuffer)
{
    if (!pbuffer)
        return kCGLBadValue;
    struct _CGLPBufferObject *pb = (struct _CGLPBufferObject *)calloc(1, sizeof(struct _CGLPBufferObject));
    if (!pb)
        return kCGLBadAlloc;
    pb->refcount = 1;
    pb->width = width;
    pb->height = height;
    pb->target = target;
    pb->internalFormat = internalFormat;
    pb->maxDetail = maxDetail;
    *pbuffer = pb;
    return kCGLNoError;
}

CGLError CGLDescribePBuffer(CGLPBufferObj pbuffer, GLsizei *width, GLsizei *height,
                            GLenum *target, GLenum *internalFormat, GLint *mipmap)
{
    if (!pbuffer)
        return kCGLBadValue;
    if (width) *width = pbuffer->width;
    if (height) *height = pbuffer->height;
    if (target) *target = pbuffer->target;
    if (internalFormat) *internalFormat = pbuffer->internalFormat;
    if (mipmap) *mipmap = pbuffer->maxDetail;
    return kCGLNoError;
}

CGLPBufferObj CGLRetainPBuffer(CGLPBufferObj pbuffer)
{
    if (pbuffer)
        pbuffer->refcount++;
    return pbuffer;
}

void CGLReleasePBuffer(CGLPBufferObj pbuffer)
{
    if (pbuffer && --pbuffer->refcount <= 0)
        CGLDestroyPBuffer(pbuffer);
}

GLuint CGLGetPBufferRetainCount(CGLPBufferObj pbuffer)
{
    if (!pbuffer)
        return 0;
    return (GLuint)pbuffer->refcount;
}

CGLError CGLDestroyPBuffer(CGLPBufferObj pbuffer)
{
    if (!pbuffer)
        return kCGLBadValue;
    free(pbuffer);
    return kCGLNoError;
}

CGLError CGLGetPBuffer(CGLContextObj context, CGLPBufferObj *pbuffer,
                       GLenum *face, GLint *level, GLint *screen)
{
    (void)context; (void)pbuffer; (void)face; (void)level; (void)screen;
    return kCGLNoError;
}

CGLError CGLSetPBuffer(CGLContextObj context, CGLPBufferObj pbuffer,
                       GLenum face, GLint level, GLint screen)
{
    (void)context; (void)pbuffer; (void)face; (void)level; (void)screen;
    return kCGLNoError;
}

CGLError CGLTexImagePBuffer(CGLContextObj context, CGLPBufferObj pbuffer,
                            GLenum sourceBuffer)
{
    (void)context; (void)pbuffer; (void)sourceBuffer;
    return kCGLNoError;
}

/* -------------------------------------------------------------------------
 * OpenGL core entrypoints bound by clients
 * ------------------------------------------------------------------------- */

void glLoadIdentity(void)
{
}

void glMatrixMode(GLenum mode)
{
    (void)mode;
}

void glOrtho(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top,
             GLdouble nearVal, GLdouble farVal)
{
    (void)left; (void)right; (void)bottom; (void)top; (void)nearVal; (void)farVal;
}


void OpenGL(void)
{
}
