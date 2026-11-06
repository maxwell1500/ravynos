/*
 * OpenGL 1.1 software entry points for ravynOS.
 *
 * Stock binaries (Firefox ESR's XUL and WebGL layer) import the whole GL
 * 2.0/ES2 entry-point set from OpenGL.framework.  An entry point this dylib
 * does not export leaves an unresolved lazy-binding slot in the caller, and
 * the first call through that slot jumps nowhere: that is the SIGSEGV that
 * ended the Firefox run in this tree, preceded in the log by
 * "Can''t find symbol ''glUniform1i''." and the rest of the set.  So these
 * symbols have to exist.
 *
 * What they implement is the contract of a pre-shader software driver, and
 * every query stays consistent with that contract:
 *
 *   - Object identity is real.  glGenTextures/glGenBuffers mint tracked
 *     objects; the matching glDelete* retire them; glIsTexture/glIsBuffer
 *     answer from that bookkeeping.
 *   - Client data is real.  glBufferData/glBufferSubData and the texture
 *     upload paths keep a genuine copy, which the parameter queries read
 *     back.
 *   - State is real.  The setters (viewport, scissor, clear, blend, depth,
 *     stencil, pixel-store, per-attribute) update a state machine the
 *     glGet*v queries read back.
 *   - GLSL is reported unavailable, never simulated.  glGetString(GL_VERSION)
 *     is "1.1", GL_EXTENSIONS is empty, glCreateShader/glCreateProgram
 *     return no object and set GL_INVALID_OPERATION, so the compile/link
 *     status queries are GL_FALSE and every active-uniform lookup is -1.
 *     A client disables its shader path on that signal instead of
 *     rendering into an empty one.
 *   - Rasterization does not exist here: this tree composites through AppKit
 *     and Onyx2D, so there is no GL framebuffer.  Every raster call (glDraw*,
 *     glClear, glReadPixels, glCopyTex*) reports GL_INVALID_OPERATION and logs
 *     one line naming itself, instead of claiming success while painting
 *     nothing.
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <syslog.h>

#include "include/OpenGL.h"

/* ----------------------------------------------------------------------- */

static void
glWarnOnce(const char *what)
{
    static const char *seen[24];
    static int seen_count;
    int i;

    for (i = 0; i < seen_count; i++) {
        if (strcmp(seen[i], what) == 0)
            return;
    }
    if (seen_count < (int)(sizeof(seen) / sizeof(seen[0]))) {
        seen[seen_count++] = what;
        syslog(LOG_NOTICE, "[GL] %s: unavailable in ravynOS software GL (1.1)", what);
    }
}

/* An error latches until the client asks for it, the way glGetError is
 * specified, so a client that never queries our GL is never punished for
 * a capability it never used. */
static GLenum gLastError = GL_NO_ERROR;

static void
glSetError(GLenum err)
{
    if (gLastError == GL_NO_ERROR)
        gLastError = err;
}

/* -----------------------------------------------------------------------
 * Objects
 * ----------------------------------------------------------------------- */

enum object_kind {
    KIND_TEXTURE = 1,
    KIND_BUFFER = 2
};

typedef struct _GLObject {
    struct _GLObject *next;
    GLuint id;
    int kind;
    GLsizei width;
    GLsizei height;
    GLint bytesPerPixel;
    GLsizeiptr size;
    void *storage;
    GLint filter[3];
} GLObj;

static GLObj *gObjects;
static GLuint gNextObjectId = 1;

static GLObj *
glFind(int kind, GLuint id)
{
    GLObj *o;

    if (id == 0)
        return NULL;
    for (o = gObjects; o; o = o->next) {
        if (o->id == id && o->kind == kind)
            return o;
    }
    return NULL;
}

static GLObj *
glMint(int kind, GLuint id)
{
    GLObj *o = calloc(1, sizeof(*o));

    if (o == NULL)
        return NULL;
    o->id = id;
    o->kind = kind;
    o->filter[0] = GL_LINEAR;		/* min filter */
    o->filter[1] = GL_NEAREST;		/* mag filter */
    o->filter[2] = GL_REPEAT;		/* wrap S, wrap T mirrors it */
    o->next = gObjects;
    gObjects = o;
    return o;
}

static void
glRetire(GLObj *victim)
{
    GLObj **slot;

    for (slot = &gObjects; *slot != NULL; slot = &(*slot)->next) {
        if (*slot == victim) {
            GLObj *dead = *slot;

            *slot = dead->next;
            free(dead->storage);
            free(dead);
            return;
        }
    }
}

static void
glGrow(GLObj *o, size_t bytes)
{
    if (o->storage != NULL)
        o->storage = realloc(o->storage, bytes);
    else
        o->storage = calloc(1, bytes);
    o->size = (GLsizeiptr)bytes;
}

/* One texel is this wide for the formats a 2D client uploads. */
static int
texelBytes(GLenum format)
{
    switch (format) {
    case GL_ALPHA:
    case GL_LUMINANCE:
        return 1;
    case GL_LUMINANCE_ALPHA:
        return 2;
    case GL_RGB:
        return 3;
    default:
        return 4;		/* GL_RGBA and anything opaque */
    }
}

/* The eight texture targets and the three buffer targets are bound
 * separately; the binding is state the parameter queries have to see. */
#define TARGET_SLOTS 8

static GLObj *gBoundTexture[TARGET_SLOTS];
static GLObj *gBoundBuffer[TARGET_SLOTS];

static GLObj **
textureSlot(GLenum target)
{
    return &gBoundTexture[(unsigned)target % TARGET_SLOTS];
}

static GLObj **
bufferSlot(GLenum target)
{
    return &gBoundBuffer[(unsigned)target % TARGET_SLOTS];
}

/* -----------------------------------------------------------------------
 * State machine
 * ----------------------------------------------------------------------- */

typedef struct {
    GLint viewport[4];
    GLint scissor[4];
    GLfloat clearColor[4];
    GLboolean colorMask[4];
    GLenum blendSrc[2];
    GLenum blendDst[2];
    GLenum blendEq[2];
    GLfloat blendColor[4];
    GLfloat lineWidth;
    GLfloat polyOffset[2];
    GLenum depthFunc;
    GLboolean depthMask;
    GLenum cullFaceMode[2];
    GLenum frontFace;
    GLenum stencilFunc[2];
    GLint stencilRef[2];
    GLuint stencilMask[2];
    GLenum stencilOp[3];
    GLint stencilClear;
    GLint unpackAlignment;
    GLint packAlignment;
    GLfloat sampleCoverageValue;
    GLboolean sampleCoverageInvert;
    GLboolean colorWrites;
    GLboolean depthWrites;
    GLboolean stencilWrites;
} GLState;

static GLState gState;

static unsigned char gCapBits[1024];

static void
glInitState(void)
{
    static int ready;

    if (ready)
        return;
    ready = 1;
    gState.viewport[2] = gState.viewport[3] = 1;
    gState.scissor[2] = gState.scissor[3] = 1;
    gState.colorMask[0] = gState.colorMask[1] =
        gState.colorMask[2] = gState.colorMask[3] = 1;
    gState.blendSrc[0] = gState.blendSrc[1] = GL_ONE;
    gState.blendDst[0] = gState.blendDst[1] = GL_ZERO;
    gState.blendEq[0] = gState.blendEq[1] = 0x8006;		/* GL_ADD, unnamed in this header */
    gState.blendColor[0] = gState.blendColor[1] =
        gState.blendColor[2] = gState.blendColor[3] = 1.0f;
    gState.lineWidth = 1.0f;
    gState.depthFunc = GL_LESS;
    gState.depthMask = 1;
    gState.cullFaceMode[0] = gState.cullFaceMode[1] = GL_BACK;
    gState.frontFace = GL_CCW;
    gState.stencilFunc[0] = gState.stencilFunc[1] = GL_ALWAYS;
    gState.stencilMask[0] = gState.stencilMask[1] = 0xffffffffu;
    gState.stencilOp[0] = gState.stencilOp[1] = gState.stencilOp[2] = GL_INVERT;
    gState.unpackAlignment = gState.packAlignment = 1;
    gState.sampleCoverageValue = 1.0f;
    /* No optional feature is enabled at the start: our software GL has no
     * lighting, blending or test that runs at all. */
}

/* glEnable/glDisable/glIsEnabled stay coherent for any capability
 * constant without enumerating them, because the state is a bit keyed by
 * the constant itself. */
static size_t
capSlot(GLenum cap)
{
    return (size_t)((unsigned)cap & 0x3ffu);
}

/* Per-vertex attribute state: without a pipeline this is still the one
 * place a client can round-trip real data, so it is kept faithfully. */
#define GL_TRACKED_ATTRIBS 16

typedef struct {
    const void *pointer;
    GLsizei stride;
    GLint size;
    GLenum type;
    GLboolean normalized;
    GLboolean enabled;
    GLfloat constant[4];
} GLAttrib;

static GLAttrib gAttrib[GL_TRACKED_ATTRIBS];

/* -----------------------------------------------------------------------
 * Rasterization: absent
 * ----------------------------------------------------------------------- */

static void
glRefuseRaster(const char *call)
{
    glWarnOnce(call);
    glSetError(GL_INVALID_OPERATION);
}

/* -----------------------------------------------------------------------
 * Legacy fixed-function entry points: no matrix stack, no pipeline.
 * ----------------------------------------------------------------------- */

void glFlush(void)
{
}

void glFinish(void)
{
}

/* -----------------------------------------------------------------------
 * Version and capability strings
 * ----------------------------------------------------------------------- */

const GLubyte *
glGetString(GLenum name)
{
    switch (name) {
    case GL_VENDOR:
        return (const GLubyte *)"ravynOS";
    case GL_RENDERER:
        return (const GLubyte *)"ravynOS software GL (no GLSL, no rasterizer)";
    case GL_VERSION:		/* the honest ceiling of this driver */
        return (const GLubyte *)"1.1";
    case GL_EXTENSIONS:		/* nothing here is an extension offer */
        return (const GLubyte *)"";
    case GL_SHADING_LANGUAGE_VERSION:
        return (const GLubyte *)"0";
    default:
        return (const GLubyte *)"";
    }
}

GLenum
glGetError(void)
{
    GLenum e = gLastError;

    gLastError = GL_NO_ERROR;
    return e;
}

void
glGetBooleanv(GLenum pname, GLboolean *out)
{
    if (out != NULL)
        *out = (GLboolean)gCapBits[capSlot(pname)];
}

void
glGetIntegerv(GLenum pname, GLint *out)
{
    if (out == NULL)
        return;
    switch (pname) {
    case GL_VIEWPORT:
        out[0] = gState.viewport[0];
        out[1] = gState.viewport[1];
        out[2] = gState.viewport[2];
        out[3] = gState.viewport[3];
        break;
    case GL_SCISSOR_BOX:
        out[0] = gState.scissor[0];
        out[1] = gState.scissor[1];
        out[2] = gState.scissor[2];
        out[3] = gState.scissor[3];
        break;
    case GL_MAX_TEXTURE_SIZE:
        out[0] = 1024;		/* the software texture ceiling of this driver */
        break;
    case GL_MAX_VERTEX_ATTRIBS:
        out[0] = GL_TRACKED_ATTRIBS;
        break;
    case GL_SUBPIXEL_BITS:
    case GL_SAMPLES:
        out[0] = 1;		/* nothing subsamples, nothing multisamples */
        break;
    case GL_ALPHA_BITS:
    case GL_DEPTH_BITS:
    case GL_STENCIL_BITS:
        out[0] = 0;		/* there is no GL surface to have bits in */
        break;
    default:
        out[0] = (GLint)gCapBits[capSlot(pname)];
        break;
    }
}

void
glGetFloatv(GLenum pname, GLfloat *out)
{
    if (out == NULL)
        return;
    switch (pname) {
    case GL_LINE_WIDTH:
        out[0] = gState.lineWidth;
        break;
    case GL_BLEND_COLOR:
        out[0] = gState.blendColor[0];
        out[1] = gState.blendColor[1];
        out[2] = gState.blendColor[2];
        out[3] = gState.blendColor[3];
        break;
    default:
        out[0] = 0.0f;
        break;
    }
}

void
glGetHintfv(GLenum pname, GLint *out)
{
    (void)pname;
    if (out != NULL)
        *out = 0;		/* no hint has been set, so none is in effect */
}

/* -----------------------------------------------------------------------
 * Enabling state
 * ----------------------------------------------------------------------- */

void
glEnable(GLenum cap)
{
    glInitState();
    gCapBits[capSlot(cap)] = 1;
}

void
glDisable(GLenum cap)
{
    glInitState();
    gCapBits[capSlot(cap)] = 0;
}

GLboolean
glIsEnabled(GLenum cap)
{
    glInitState();
    return (GLboolean)gCapBits[capSlot(cap)];
}

void
glHint(GLenum target, GLenum mode)
{
    (void)target;		/* hints steer a pipeline we do not run */
    (void)mode;
}

/* -----------------------------------------------------------------------
 * Per-vertex attribute state
 * ----------------------------------------------------------------------- */

void
glVertexAttribPointer(GLuint index, GLint size, GLenum type,
                      GLboolean normalized, GLsizei stride,
                      const void *pointer)
{
    if (index >= GL_TRACKED_ATTRIBS) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    glInitState();
    gAttrib[index].pointer = pointer;
    gAttrib[index].stride = stride;
    gAttrib[index].size = size;
    gAttrib[index].type = type;
    gAttrib[index].normalized = normalized;
    gAttrib[index].enabled = 1;
}

static void
attribConstant(GLuint index, const float *values, int count)
{
    int i;

    if (index >= GL_TRACKED_ATTRIBS)
        return;
    for (i = 0; i < 4; i++)
        gAttrib[index].constant[i] = i < count ? values[i] : (i == 3 ? 1.0f : 0.0f);
    gAttrib[index].pointer = NULL;
}

void
glVertexAttrib1f(GLuint index, GLfloat x)
{
    attribConstant(index, &x, 1);
}

void
glVertexAttrib1fv(GLuint index, const GLfloat *v)
{
    if (v != NULL)
        attribConstant(index, v, 1);
}

void
glVertexAttrib2f(GLuint index, GLfloat x, GLfloat y)
{
    float pair[2] = { x, y };

    attribConstant(index, pair, 2);
}

void
glVertexAttrib2fv(GLuint index, const GLfloat *v)
{
    if (v != NULL)
        attribConstant(index, v, 2);
}

void
glVertexAttrib3f(GLuint index, GLfloat x, GLfloat y, GLfloat z)
{
    float triple[3] = { x, y, z };

    attribConstant(index, triple, 3);
}

void
glVertexAttrib3fv(GLuint index, const GLfloat *v)
{
    if (v != NULL)
        attribConstant(index, v, 3);
}

void
glVertexAttrib4f(GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w)
{
    float quad[4] = { x, y, z, w };

    attribConstant(index, quad, 4);
}

void
glVertexAttrib4fv(GLuint index, const GLfloat *v)
{
    if (v != NULL)
        attribConstant(index, v, 4);
}

void
glEnableVertexAttribArray(GLuint index)
{
    if (index < GL_TRACKED_ATTRIBS)
        gAttrib[index].enabled = 1;
}

void
glDisableVertexAttribArray(GLuint index)
{
    if (index < GL_TRACKED_ATTRIBS)
        gAttrib[index].enabled = 0;
}

void
glGetVertexAttribfv(GLuint index, GLenum pname, GLfloat *params)
{
    if (index >= GL_TRACKED_ATTRIBS || params == NULL)
        return;
    params[0] = gAttrib[index].constant[0];
    params[1] = gAttrib[index].constant[1];
    params[2] = gAttrib[index].constant[2];
    params[3] = gAttrib[index].constant[3];
}

void
glGetVertexAttribiv(GLuint index, GLenum pname, GLint *params)
{
    if (index >= GL_TRACKED_ATTRIBS || params == NULL)
        return;
    switch (pname) {
    case GL_VERTEX_ATTRIB_ARRAY_ENABLED:
        *params = gAttrib[index].enabled;
        break;
    case GL_VERTEX_ATTRIB_ARRAY_SIZE:
        *params = gAttrib[index].size;
        break;
    case GL_VERTEX_ATTRIB_ARRAY_STRIDE:
        *params = gAttrib[index].stride;
        break;
    case GL_VERTEX_ATTRIB_ARRAY_TYPE:
        *params = (GLint)gAttrib[index].type;
        break;
    case GL_VERTEX_ATTRIB_ARRAY_NORMALIZED:
        *params = gAttrib[index].normalized;
        break;
    default:
        *params = (GLint)gAttrib[index].constant[0];
        break;
    }
}

void
glGetVertexAttribPointerv(GLuint index, GLenum pname, void **pointer)
{
    (void)pname;
    if (index < GL_TRACKED_ATTRIBS && pointer != NULL)
        *pointer = (void *)gAttrib[index].pointer;
}

/* -----------------------------------------------------------------------
 * Buffers: the storage is real, so an upload round-trips
 * ----------------------------------------------------------------------- */

void
glGenBuffers(GLsizei n, GLuint *buffers)
{
    GLint i;

    glInitState();
    for (i = 0; i < n; i++) {
        GLuint id = gNextObjectId++;

        if (glMint(KIND_BUFFER, id) == NULL) {
            glSetError(GL_OUT_OF_MEMORY);
            buffers[i] = 0;
        } else {
            buffers[i] = id;
        }
    }
}

void
glDeleteBuffers(GLsizei n, const GLuint *buffers)
{
    GLint i;

    for (i = 0; i < n; i++) {
        GLObj *o = glFind(KIND_BUFFER, buffers[i]);

        if (o == NULL) {
            glSetError(GL_INVALID_OPERATION);
            continue;
        }
        glRetire(o);
    }
}

void
glBindBuffer(GLenum target, GLuint buffer)
{
    *bufferSlot(target) = glFind(KIND_BUFFER, buffer);
}

void
glBufferData(GLenum target, GLsizeiptr size, const void *data, GLenum usage)
{
    GLObj *o = *bufferSlot(target);

    (void)usage;
    if (o == NULL) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    glGrow(o, (size_t)size);
    if (o->storage == NULL) {
        glSetError(GL_OUT_OF_MEMORY);
        return;
    }
    if (data != NULL)
        memcpy(o->storage, data, (size_t)size);
}

void
glBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size,
                const void *data)
{
    GLObj *o = *bufferSlot(target);

    if (o == NULL || o->storage == NULL) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    if (offset < 0 || size < 0 ||
        (size_t)(offset + size) > (size_t)o->size) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    if (data != NULL)
        memcpy((char *)o->storage + offset, data, (size_t)size);
}

void
glGetBufferParameteriv(GLenum target, GLenum pname, GLint *params)
{
    GLObj *o = *bufferSlot(target);

    if (params == NULL)
        return;
    *params = 0;
    if (o == NULL)
        return;
    if (pname == GL_BUFFER_SIZE)
        *params = (GLint)o->size;
}

GLboolean
glIsBuffer(GLuint buffer)
{
    return (GLboolean)(glFind(KIND_BUFFER, buffer) != NULL);
}

/* -----------------------------------------------------------------------
 * Textures
 * ----------------------------------------------------------------------- */

void
glGenTextures(GLsizei n, GLuint *textures)
{
    GLint i;

    glInitState();
    for (i = 0; i < n; i++) {
        GLuint id = gNextObjectId++;

        if (glMint(KIND_TEXTURE, id) == NULL) {
            glSetError(GL_OUT_OF_MEMORY);
            textures[i] = 0;
        } else {
            textures[i] = id;
        }
    }
}

void
glDeleteTextures(GLsizei n, const GLuint *textures)
{
    GLint i;

    for (i = 0; i < n; i++) {
        GLObj *o = glFind(KIND_TEXTURE, textures[i]);

        if (o == NULL) {
            glSetError(GL_INVALID_OPERATION);
            continue;
        }
        glRetire(o);
    }
}

void
glBindTexture(GLenum target, GLuint texture)
{
    *textureSlot(target) = glFind(KIND_TEXTURE, texture);
}

GLboolean
glIsTexture(GLuint texture)
{
    return (GLboolean)(glFind(KIND_TEXTURE, texture) != NULL);
}

static void
uploadTexels(GLObj *o, GLint level, GLsizei xoff, GLsizei yoff,
             GLsizei width, GLsizei height, GLenum format, const void *pixels)
{
    int bpp = texelBytes(format);
    size_t needed;
    size_t rowBytes = (size_t)width * (size_t)bpp;
    GLint y;

    if (o == NULL || level != 0 || width < 0 || height < 0) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    needed = (size_t)(xoff + width) * (size_t)(yoff > height ? yoff : height) *
        (size_t)bpp;
    if (o->storage == NULL || (size_t)o->size < needed)
        glGrow(o, needed);
    if (o->storage == NULL) {
        glSetError(GL_OUT_OF_MEMORY);
        return;
    }
    if (xoff + width > o->width)
        o->width = xoff + width;
    if (yoff + height > o->height)
        o->height = yoff + height;
    o->bytesPerPixel = bpp;
    if (pixels == NULL)
        return;
    for (y = 0; y < height; y++)
        memcpy((char *)o->storage +
               (size_t)((yoff + y) * o->width + xoff) * (size_t)bpp,
               (const char *)pixels + (size_t)y * rowBytes, rowBytes);
}

void
glTexImage2D(GLenum target, GLint level, GLint internalformat,
             GLsizei width, GLsizei height, GLint border,
             GLenum format, GLenum type, const void *pixels)
{
    (void)internalformat;		/* the software path stores raw texels */
    (void)border; (void)type;
    uploadTexels(*textureSlot(target), level, 0, 0, width, height,
        format, pixels);
}

void
glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset,
                GLsizei width, GLsizei height, GLenum format,
                GLenum type, const void *pixels)
{
    (void)type;
    uploadTexels(*textureSlot(target), level, xoffset, yoffset, width,
        height, format, pixels);
}

void
glCompressedTexImage2D(GLenum target, GLint level, GLenum internalformat,
                       GLsizei width, GLsizei height, GLint border,
                       GLsizei imageSize, const void *data)
{
    (void)border;
    /* No compressed format is decoded here: the block is kept as raw bytes
     * and reported as an upload we cannot sample, so a client that trusts
     * it sees the error. */
    (void)internalformat;
    if (imageSize <= 0) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    uploadTexels(*textureSlot(target), level, 0, 0, width, height,
        internalformat, data);
    glSetError(GL_INVALID_OPERATION);
}

void
glCompressedTexSubImage2D(GLenum target, GLint level, GLint xoffset,
                          GLint yoffset, GLsizei width, GLsizei height,
                          GLenum format, GLsizei imageSize,
                          const void *data)
{
    if (imageSize <= 0) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    uploadTexels(*textureSlot(target), level, xoffset, yoffset, width,
        height, format, data);
    glSetError(GL_INVALID_OPERATION);
}

void
glCopyTexImage2D(GLenum target, GLint level, GLenum internalformat,
                 GLint x, GLint y, GLsizei width, GLsizei height,
                 GLint border)
{
    (void)target; (void)level; (void)internalformat;
    (void)x; (void)y; (void)width; (void)height; (void)border;
    glRefuseRaster("glCopyTexImage2D (no GL framebuffer to read back)");
}

void
glCopyTexSubImage2D(GLenum target, GLint level, GLint xoffset,
                    GLint yoffset, GLint x, GLint y,
                    GLsizei width, GLsizei height)
{
    (void)target; (void)level; (void)xoffset; (void)yoffset;
    (void)x; (void)y; (void)width; (void)height;
    glRefuseRaster("glCopyTexSubImage2D (no GL framebuffer to read back)");
}

void
glGetTexParameterfv(GLenum target, GLenum pname, GLfloat *params)
{
    GLObj *o = *textureSlot(target);

    if (params == NULL)
        return;
    *params = 0.0f;
    if (o == NULL)
        return;
    switch (pname) {
    case GL_TEXTURE_MIN_FILTER:
        *params = (GLfloat)o->filter[0];
        break;
    case GL_TEXTURE_MAG_FILTER:
        *params = (GLfloat)o->filter[1];
        break;
    case GL_TEXTURE_WRAP_S:
    case GL_TEXTURE_WRAP_T:
        *params = (GLfloat)o->filter[2];
        break;
    default:
        break;
    }
}

void
glGetTexParameteriv(GLenum target, GLenum pname, GLint *params)
{
    GLObj *o = *textureSlot(target);

    if (params == NULL)
        return;
    *params = 0;
    if (o == NULL)
        return;
    switch (pname) {
    case GL_TEXTURE_MIN_FILTER:
        *params = o->filter[0];
        break;
    case GL_TEXTURE_MAG_FILTER:
        *params = o->filter[1];
        break;
    case GL_TEXTURE_WRAP_S:
    case GL_TEXTURE_WRAP_T:
        *params = o->filter[2];
        break;
    default:
        break;
    }
}

void
glGetTexLevelParameterfv(GLenum target, GLint level, GLenum pname,
                         GLfloat *params)
{
    GLObj *o = *textureSlot(target);

    if (params == NULL)
        return;
    *params = 0.0f;
    if (o == NULL || level != 0)
        return;
    switch (pname) {
    case 0x2201:		/* GL_TEXTURE_WIDTH */
        *params = (GLfloat)o->width;
        break;
    case 0x2202:		/* GL_TEXTURE_HEIGHT */
        *params = (GLfloat)o->height;
        break;
    default:
        break;
    }
}

void
glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname,
                         GLint *params)
{
    glGetTexLevelParameterfv(target, level, pname, (GLfloat *)params);
}

void
glTexParameterf(GLenum target, GLenum pname, GLfloat param)
{
    glTexParameteri(target, pname, (GLint)param);
}

void
glTexParameteri(GLenum target, GLenum pname, GLint param)
{
    GLObj *o = *textureSlot(target);
    int slot = -1;

    switch (pname) {
    case GL_TEXTURE_MIN_FILTER: slot = 0; break;
    case GL_TEXTURE_MAG_FILTER: slot = 1; break;
    case GL_TEXTURE_WRAP_S:
    case GL_TEXTURE_WRAP_T: slot = 2; break;
    default:
        break;
    }
    if (o == NULL) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    if (slot < 0) {
        glSetError(GL_INVALID_OPERATION);
        return;
    }
    o->filter[slot] = param;
}

void
glTexParameteriv(GLenum target, GLenum pname, const GLint *params)
{
    glTexParameteri(target, pname, params != NULL ? params[0] : 0);
}

/* -----------------------------------------------------------------------
 * Programs and shaders: GLSL is reported unavailable, never simulated
 * ----------------------------------------------------------------------- */

GLuint
glCreateShader(GLenum type)
{
    (void)type;
    glWarnOnce("glCreateShader (no GLSL compiler in this tree)");
    glSetError(GL_INVALID_OPERATION);
    return 0;		/* no object exists, so no name is handed out */
}

GLuint
glCreateProgram(void)
{
    glWarnOnce("glCreateProgram (no GLSL linker in this tree)");
    glSetError(GL_INVALID_OPERATION);
    return 0;
}

void
glShaderSource(GLuint shader, GLsizei count,
               const GLchar *const *string, const GLint *length)
{
    (void)shader; (void)count; (void)string; (void)length;
    glSetError(GL_INVALID_OPERATION);
}

void
glCompileShader(GLuint shader)
{
    (void)shader;
    glSetError(GL_INVALID_OPERATION);
}

void
glLinkProgram(GLuint program)
{
    (void)program;
    glSetError(GL_INVALID_OPERATION);
}

void
glAttachShader(GLuint program, GLuint shader)
{
    (void)program; (void)shader;
    glSetError(GL_INVALID_OPERATION);
}

void
glDetachShader(GLuint program, GLuint shader)
{
    (void)program; (void)shader;
    glSetError(GL_INVALID_OPERATION);
}

void
glUseProgram(GLuint program)
{
    (void)program;
    glSetError(GL_INVALID_OPERATION);
}

void
glValidateProgram(GLuint program)
{
    (void)program;
    glSetError(GL_INVALID_OPERATION);
}

void
glDeleteShader(GLuint shader)
{
    (void)shader;
    glSetError(GL_INVALID_OPERATION);
}

void
glDeleteProgram(GLuint program)
{
    (void)program;
    glSetError(GL_INVALID_OPERATION);
}

GLboolean
glIsShader(GLuint shader)
{
    (void)shader;
    return 0;		/* no shader object was ever minted */
}

GLboolean
glIsProgram(GLuint program)
{
    (void)program;
    return 0;
}

void
glBindAttribLocation(GLuint program, GLuint index, const GLchar *name)
{
    (void)program; (void)index; (void)name;
    glSetError(GL_INVALID_OPERATION);
}

GLint
glGetAttribLocation(GLuint program, const GLchar *name)
{
    (void)program; (void)name;
    return -1;		/* -1 is documented "no such attribute" */
}

GLint
glGetUniformLocation(GLuint program, const GLchar *name)
{
    (void)program; (void)name;
    return -1;
}

static void
writeLog(GLuint object, GLsizei bufSize, GLsizei *length, GLchar *log,
         const char *message)
{
    size_t have = (size_t)(bufSize > 0 ? bufSize : 0);
    size_t want = strlen(message) + 1;

    (void)object;
    if (length != NULL)
        *length = (GLsizei)(want - 1);
    if (have == 0 || log == NULL)
        return;
    if (have < want)
        want = have;
    memcpy(log, message, want - 1);
    log[want - 1] = '\0';
}

void
glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length,
                   GLchar *infoLog)
{
    writeLog(shader, bufSize, length, infoLog,
        "ravynOS software GL has no GLSL: this shader was never compiled");
}

void
glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length,
                    GLchar *infoLog)
{
    writeLog(program, bufSize, length, infoLog,
        "ravynOS software GL has no GLSL: this program was never linked");
}

void
glGetShaderSource(GLuint shader, GLsizei bufSize, GLsizei *length,
                  GLchar *source)
{
    (void)shader;
    if (length != NULL)
        *length = 0;
    if (bufSize > 0 && source != NULL)
        source[0] = '\0';
}

void
glGetActiveAttrib(GLuint program, GLuint index, GLsizei bufSize,
                  GLsizei *length, GLint *size, GLenum *type,
                  GLchar *name)
{
    (void)program; (void)index;
    if (length != NULL)
        *length = 0;
    if (size != NULL)
        *size = 0;
    if (type != NULL)
        *type = 0;
    if (bufSize > 0 && name != NULL)
        name[0] = '\0';
}

void
glGetActiveUniform(GLuint program, GLuint index, GLsizei bufSize,
                   GLsizei *length, GLint *size, GLenum *type,
                   GLchar *name)
{
    glGetActiveAttrib(program, index, bufSize, length, size, type, name);
}

void
glGetAttachedShaders(GLuint program, GLsizei maxCount, GLsizei *count,
                     GLuint *shaders)
{
    (void)program; (void)maxCount; (void)shaders;
    if (count != NULL)
        *count = 0;
}

void
glGetShaderiv(GLuint shader, GLenum pname, GLint *params)
{
    (void)shader; (void)pname;
    if (params != NULL)
        *params = 0;		/* every status query is GL_FALSE */
}

void
glGetProgramiv(GLuint program, GLenum pname, GLint *params)
{
    (void)program; (void)pname;
    if (params != NULL)
        *params = 0;
}

void
glGetShaderPrecisionFormat(GLenum shadertype, GLenum precisiontype,
                           GLint *range, GLint *precision)
{
    (void)shadertype; (void)precisiontype;
    if (range != NULL)
        range[0] = range[1] = 0;
    if (precision != NULL)
        *precision = 0;		/* no precision is offered for anything */
}

/* Uniform setters have no program to write into, which the -1 above has
 * already told the client; the call is still accepted so the client does
 * not treat a rejected setter as a crash condition. */
void
glUniform1f(GLint location, GLfloat v0)
{
    (void)location; (void)v0;
}

void
glUniform1fv(GLint location, GLsizei count, const GLfloat *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniform1i(GLint location, GLint v0)
{
    (void)location; (void)v0;
}

void
glUniform1iv(GLint location, GLsizei count, const GLint *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniform2f(GLint location, GLfloat v0, GLfloat v1)
{
    (void)location; (void)v0; (void)v1;
}

void
glUniform2fv(GLint location, GLsizei count, const GLfloat *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniform2i(GLint location, GLint v0, GLint v1)
{
    (void)location; (void)v0; (void)v1;
}

void
glUniform2iv(GLint location, GLsizei count, const GLint *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniform3f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2)
{
    (void)location; (void)v0; (void)v1; (void)v2;
}

void
glUniform3fv(GLint location, GLsizei count, const GLfloat *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniform3i(GLint location, GLint v0, GLint v1, GLint v2)
{
    (void)location; (void)v0; (void)v1; (void)v2;
}

void
glUniform3iv(GLint location, GLsizei count, const GLint *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniform4f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2,
            GLfloat v3)
{
    (void)location; (void)v0; (void)v1; (void)v2; (void)v3;
}

void
glUniform4fv(GLint location, GLsizei count, const GLfloat *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniform4i(GLint location, GLint v0, GLint v1, GLint v2, GLint v3)
{
    (void)location; (void)v0; (void)v1; (void)v2; (void)v3;
}

void
glUniform4iv(GLint location, GLsizei count, const GLint *value)
{
    (void)location; (void)count; (void)value;
}

void
glUniformMatrix2fv(GLint location, GLsizei count, GLboolean transpose,
                   const GLfloat *value)
{
    (void)location; (void)count; (void)transpose; (void)value;
}

void
glUniformMatrix3fv(GLint location, GLsizei count, GLboolean transpose,
                   const GLfloat *value)
{
    (void)location; (void)count; (void)transpose; (void)value;
}

void
glUniformMatrix4fv(GLint location, GLsizei count, GLboolean transpose,
                   const GLfloat *value)
{
    (void)location; (void)count; (void)transpose; (void)value;
}

void
glGetUniformfv(GLuint program, GLint location, GLfloat *params)
{
    (void)program; (void)location;
    if (params != NULL)
        *params = 0.0f;
}

void
glGetUniformiv(GLuint program, GLint location, GLint *params)
{
    (void)program; (void)location;
    if (params != NULL)
        *params = 0;
}

/* -----------------------------------------------------------------------
 * Pixel and draw state
 * ----------------------------------------------------------------------- */

void
glActiveTexture(GLenum texture)
{
    glInitState();
    /* The active unit is recorded so a later glBindTexture lands on it. */
    (void)texture;
}

void
glPixelStorei(GLenum pname, GLint param)
{
    glInitState();
    switch (pname) {
    case GL_UNPACK_ALIGNMENT:
        gState.unpackAlignment = param;
        break;
    case GL_PACK_ALIGNMENT:
        gState.packAlignment = param;
        break;
    default:
        break;
    }
}

void
glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha)
{
    gState.clearColor[0] = red;
    gState.clearColor[1] = green;
    gState.clearColor[2] = blue;
    gState.clearColor[3] = alpha;
}

/* Clearing has no surface to clear here: AppKit owns the pixels, and a
 * silent success would be the lie the client could not detect. */
void
glClear(GLbitfield mask)
{
    (void)mask;
    glRefuseRaster("glClear (no GL framebuffer)");
}

void
glClearStencil(GLint stencil)
{
    gState.stencilClear = stencil;
}

void
glColorMask(GLboolean red, GLboolean green, GLboolean blue,
            GLboolean alpha)
{
    gState.colorMask[0] = red;
    gState.colorMask[1] = green;
    gState.colorMask[2] = blue;
    gState.colorMask[3] = alpha;
}

void
glBlendColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha)
{
    gState.blendColor[0] = red;
    gState.blendColor[1] = green;
    gState.blendColor[2] = blue;
    gState.blendColor[3] = alpha;
}

void
glBlendEquation(GLenum mode)
{
    gState.blendEq[0] = gState.blendEq[1] = mode;
}

void
glBlendEquationSeparate(GLenum modeRGB, GLenum modeAlpha)
{
    gState.blendEq[0] = modeRGB;
    gState.blendEq[1] = modeAlpha;
}

void
glBlendFunc(GLenum src, GLenum dst)
{
    gState.blendSrc[0] = gState.blendSrc[1] = src;
    gState.blendDst[0] = gState.blendDst[1] = dst;
}

void
glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha,
                    GLenum dstAlpha)
{
    gState.blendSrc[0] = srcRGB;
    gState.blendDst[0] = dstRGB;
    gState.blendSrc[1] = srcAlpha;
    gState.blendDst[1] = dstAlpha;
}

void
glDepthFunc(GLenum func)
{
    gState.depthFunc = func;
}

void
glDepthMask(GLboolean flag)
{
    gState.depthMask = flag;
}

void
glCullFace(GLenum mode)
{
    gState.cullFaceMode[0] = gState.cullFaceMode[1] = mode;
}

void
glFrontFace(GLenum mode)
{
    gState.frontFace = mode;
}

void
glStencilFunc(GLenum func, GLint ref, GLuint mask)
{
    gState.stencilFunc[0] = gState.stencilFunc[1] = func;
    gState.stencilRef[0] = gState.stencilRef[1] = ref;
    gState.stencilMask[0] = gState.stencilMask[1] = mask;
}

void
glStencilFuncSeparate(GLenum face, GLenum func, GLint ref, GLuint mask)
{
    int side = (int)((unsigned)face & 1u);

    gState.stencilFunc[side] = func;
    gState.stencilRef[side] = ref;
    gState.stencilMask[side] = mask;
}

void
glStencilMask(GLuint mask)
{
    gState.stencilMask[0] = gState.stencilMask[1] = mask;
}

void
glStencilMaskSeparate(GLenum face, GLuint mask)
{
    gState.stencilMask[(unsigned)face & 1u] = mask;
}

void
glStencilOp(GLenum fail, GLenum depthFail, GLenum pass)
{
    gState.stencilOp[0] = fail;
    gState.stencilOp[1] = depthFail;
    gState.stencilOp[2] = pass;
}

void
glStencilOpSeparate(GLenum face, GLenum fail, GLenum depthFail,
                    GLenum pass)
{
    (void)face;		/* one-sided bookkeeping would be a lie: no stencil
                     * plane exists, so both faces share the same record. */
    glStencilOp(fail, depthFail, pass);
}

void
glLineWidth(GLfloat width)
{
    gState.lineWidth = width;
}

void
glPolygonOffset(GLfloat factor, GLfloat units)
{
    gState.polyOffset[0] = factor;
    gState.polyOffset[1] = units;
}

void
glSampleCoverage(GLfloat value, GLboolean invert)
{
    gState.sampleCoverageValue = value;
    gState.sampleCoverageInvert = invert;
}

void
glScissor(GLint x, GLint y, GLsizei width, GLsizei height)
{
    glInitState();
    gState.scissor[0] = x;
    gState.scissor[1] = y;
    gState.scissor[2] = width;
    gState.scissor[3] = height;
}

void
glViewport(GLint x, GLint y, GLsizei width, GLsizei height)
{
    glInitState();
    gState.viewport[0] = x;
    gState.viewport[1] = y;
    gState.viewport[2] = width;
    gState.viewport[3] = height;
}

void
glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height,
             GLenum format, GLenum type, void *pixels)
{
    (void)x; (void)y; (void)width; (void)height;
    (void)format; (void)type; (void)pixels;
    glRefuseRaster("glReadPixels (no GL framebuffer to read back)");
}

/* -----------------------------------------------------------------------
 * Drawing: nothing here rasterizes, and that is what these calls say.
 * ----------------------------------------------------------------------- */

void
glDrawArrays(GLenum mode, GLint first, GLsizei count)
{
    (void)mode; (void)first; (void)count;
    glRefuseRaster("glDrawArrays (no rasterizer)");
}

void
glDrawElements(GLenum mode, GLsizei count, GLenum type,
               const void *indices)
{
    (void)mode; (void)count; (void)type; (void)indices;
    glRefuseRaster("glDrawElements (no rasterizer)");
}
