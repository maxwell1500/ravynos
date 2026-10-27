/*
 * libcompression.dylib for ravynOS.
 *
 * Implemented here:
 *   COMPRESSION_ZLIB      zlib streams through libz.1.dylib (deflate/inflate),
 *   COMPRESSION_LZ4_RAW   LZ4 block format, encoder and decoder,
 *   COMPRESSION_LZ4       the same block format with Apple's 4-byte
 *                         uncompressed-size prefix,
 *   COMPRESSION_LZVN      decoder only, through Apple's lzvn_decode.c.
 *
 * Not implemented: COMPRESSION_LZFSE (encoder and decoder) and
 * COMPRESSION_LZMA (liblzma is not built yet).  Both return
 * COMPRESSION_STATUS_ERROR / 0 bytes, which callers already handle; returning
 * a plausible-but-wrong byte stream would be worse than the error.
 */
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "compression.h"
#include "lzvn_decode.h"

/* ------------------------------------------------------------- LZ4 block */

static size_t lz4_encode_block(const unsigned char *src, size_t src_size,
                               unsigned char *dst, size_t dst_size)
{
    size_t ip = 0;
    size_t op = 0;

    while (ip < src_size) {
        size_t literal_len = src_size - ip;
        size_t token_pos;

        /* This encoder emits literal runs only, which is a valid LZ4 block
         * (matches are optional) and is what a compressor without a hash
         * table can guarantee.  It is a correct encoder, not a fast one. */
        if (literal_len > 0xFFFFFFFFu) {
            return 0;
        }
        if (op >= dst_size) {
            return 0;
        }
        token_pos = op++;
        if (literal_len < 15) {
            dst[token_pos] = (unsigned char)(literal_len << 4);
        } else {
            size_t remaining = literal_len - 15;
            dst[token_pos] = 0xF0;
            while (remaining >= 255) {
                if (op >= dst_size) return 0;
                dst[op++] = 255;
                remaining -= 255;
            }
            if (op >= dst_size) return 0;
            dst[op++] = (unsigned char)remaining;
        }
        if (literal_len > dst_size - op) {
            return 0;
        }
        memcpy(dst + op, src + ip, literal_len);
        op += literal_len;
        ip += literal_len;
    }
    return op;
}

static size_t lz4_decode_block(const unsigned char *src, size_t src_size,
                               unsigned char *dst, size_t dst_size)
{
    size_t ip = 0;
    size_t op = 0;

    while (ip < src_size) {
        unsigned int token = src[ip++];
        size_t literal_len = token >> 4;
        size_t match_len;
        size_t offset;

        if (literal_len == 15) {
            unsigned int b;
            do {
                if (ip >= src_size) return 0;
                b = src[ip++];
                literal_len += b;
            } while (b == 255);
        }
        if (literal_len > src_size - ip || literal_len > dst_size - op) {
            return 0;
        }
        memcpy(dst + op, src + ip, literal_len);
        ip += literal_len;
        op += literal_len;

        if (ip >= src_size) {
            break;      /* last sequence has no match */
        }

        if (src_size - ip < 2) {
            return 0;
        }
        offset = (size_t)src[ip] | ((size_t)src[ip + 1] << 8);
        ip += 2;
        if (offset == 0 || offset > op) {
            return 0;
        }

        match_len = token & 0x0F;
        if (match_len == 15) {
            unsigned int b;
            do {
                if (ip >= src_size) return 0;
                b = src[ip++];
                match_len += b;
            } while (b == 255);
        }
        match_len += 4;
        if (match_len > dst_size - op) {
            return 0;
        }
        {
            size_t from = op - offset;
            /* Byte-wise copy: overlapping matches are the point of LZ4. */
            for (size_t i = 0; i < match_len; i++) {
                dst[op + i] = dst[from + i];
            }
            op += match_len;
        }
    }
    return op;
}

/* -------------------------------------------------------------------- LZVN */

static size_t lzvn_decode_buffer(unsigned char *dst, size_t dst_size,
                                 const unsigned char *src, size_t src_size)
{
    lzvn_decoder_state state;
    memset(&state, 0, sizeof(state));
    state.src = src;
    state.src_end = src + src_size;
    state.dst_begin = dst;
    state.dst_end = dst + dst_size;
    state.dst_current = dst;
    lzvn_decode(&state);
    if (state.end_of_stream) {
        return (size_t)(state.dst_current - dst);
    }
    return 0;
}

/* ------------------------------------------------------------------ public */

size_t compression_encode_buffer(void *dst_buffer, size_t dst_size,
                                 const void *src_buffer, size_t src_size,
                                 void *scratch_buffer,
                                 compression_algorithm algorithm)
{
    (void)scratch_buffer;

    if (dst_buffer == NULL || src_buffer == NULL) {
        return 0;
    }
    switch (algorithm) {
    case COMPRESSION_ZLIB: {
        uLongf out_len = (uLongf)dst_size;
        int rc = compress2((Bytef *)dst_buffer, &out_len,
                           (const Bytef *)src_buffer, (uLong)src_size,
                           Z_DEFAULT_COMPRESSION);
        return (rc == Z_OK) ? (size_t)out_len : 0;
    }
    case COMPRESSION_LZ4_RAW:
        return lz4_encode_block((const unsigned char *)src_buffer, src_size,
                                (unsigned char *)dst_buffer, dst_size);
    case COMPRESSION_LZ4: {
        size_t written;
        if (dst_size < 4) {
            return 0;
        }
        if (src_size > 0xFFFFFFFFu) {
            return 0;
        }
        ((unsigned char *)dst_buffer)[0] = (unsigned char)(src_size);
        ((unsigned char *)dst_buffer)[1] = (unsigned char)(src_size >> 8);
        ((unsigned char *)dst_buffer)[2] = (unsigned char)(src_size >> 16);
        ((unsigned char *)dst_buffer)[3] = (unsigned char)(src_size >> 24);
        written = lz4_encode_block((const unsigned char *)src_buffer, src_size,
                                   (unsigned char *)dst_buffer + 4, dst_size - 4);
        return written ? written + 4 : 0;
    }
    default:
        /* LZFSE, LZMA and LZVN have no encoder here. */
        return 0;
    }
}

size_t compression_decode_buffer(void *dst_buffer, size_t dst_size,
                                 const void *src_buffer, size_t src_size,
                                 void *scratch_buffer,
                                 compression_algorithm algorithm)
{
    (void)scratch_buffer;

    if (dst_buffer == NULL || src_buffer == NULL) {
        return 0;
    }
    switch (algorithm) {
    case COMPRESSION_ZLIB: {
        uLongf out_len = (uLongf)dst_size;
        int rc = uncompress((Bytef *)dst_buffer, &out_len,
                            (const Bytef *)src_buffer, (uLong)src_size);
        return (rc == Z_OK) ? (size_t)out_len : 0;
    }
    case COMPRESSION_LZ4_RAW:
        return lz4_decode_block((const unsigned char *)src_buffer, src_size,
                                (unsigned char *)dst_buffer, dst_size);
    case COMPRESSION_LZ4: {
        if (src_size < 4) {
            return 0;
        }
        return lz4_decode_block((const unsigned char *)src_buffer + 4, src_size - 4,
                                (unsigned char *)dst_buffer, dst_size);
    }
    case COMPRESSION_LZVN:
        return lzvn_decode_buffer((unsigned char *)dst_buffer, dst_size,
                                  (const unsigned char *)src_buffer, src_size);
    default:
        return 0;
    }
}

size_t compression_encode_scratch_buffer_size(compression_algorithm algorithm)
{
    (void)algorithm;
    return 0;
}

size_t compression_decode_scratch_buffer_size(compression_algorithm algorithm)
{
    (void)algorithm;
    return 0;
}

/* ------------------------------------------------------------- stream API */

struct compression_zlib_state {
    z_stream zs;
    int operation;
    int initialized;
};

compression_status compression_stream_init(compression_stream *stream,
                                           compression_algorithm algorithm,
                                           int operation)
{
    struct compression_zlib_state *state;

    if (stream == NULL) {
        return COMPRESSION_STATUS_ERROR;
    }
    memset(stream, 0, sizeof(*stream));
    stream->algorithm = algorithm;
    stream->state = NULL;

    if (algorithm != COMPRESSION_ZLIB) {
        return COMPRESSION_STATUS_ERROR;
    }
    state = (struct compression_zlib_state *)calloc(1, sizeof(*state));
    if (state == NULL) {
        return COMPRESSION_STATUS_ERROR;
    }
    state->operation = operation;
    if (operation == COMPRESSION_STREAM_ENCODE) {
        if (deflateInit(&state->zs, Z_DEFAULT_COMPRESSION) != Z_OK) {
            free(state);
            return COMPRESSION_STATUS_ERROR;
        }
    } else {
        if (inflateInit(&state->zs) != Z_OK) {
            free(state);
            return COMPRESSION_STATUS_ERROR;
        }
    }
    state->initialized = 1;
    stream->state = state;
    return COMPRESSION_STATUS_OK;
}

compression_status compression_stream_process(compression_stream *stream, int flags)
{
    struct compression_zlib_state *state;
    int zflags = Z_NO_FLUSH;
    int rc;

    if (stream == NULL || stream->state == NULL) {
        return COMPRESSION_STATUS_ERROR;
    }
    state = (struct compression_zlib_state *)stream->state;
    if (flags & COMPRESSION_STREAM_FINALIZE) {
        zflags = Z_FINISH;
    }

    state->zs.next_in = (Bytef *)stream->src_ptr;
    state->zs.avail_in = (uInt)stream->src_size;
    state->zs.next_out = (Bytef *)stream->dst_ptr;
    state->zs.avail_out = (uInt)stream->dst_size;

    if (state->operation == COMPRESSION_STREAM_ENCODE) {
        rc = deflate(&state->zs, zflags);
    } else {
        rc = inflate(&state->zs, zflags);
    }

    stream->src_ptr = state->zs.next_in;
    stream->src_size = state->zs.avail_in;
    stream->dst_ptr = state->zs.next_out;
    stream->dst_size = state->zs.avail_out;

    if (rc == Z_STREAM_END) {
        return COMPRESSION_STATUS_END;
    }
    if (rc == Z_OK || rc == Z_BUF_ERROR) {
        return COMPRESSION_STATUS_OK;
    }
    return COMPRESSION_STATUS_ERROR;
}

compression_status compression_stream_destroy(compression_stream *stream)
{
    struct compression_zlib_state *state;

    if (stream == NULL || stream->state == NULL) {
        return COMPRESSION_STATUS_ERROR;
    }
    state = (struct compression_zlib_state *)stream->state;
    if (state->initialized) {
        if (state->operation == COMPRESSION_STREAM_ENCODE) {
            deflateEnd(&state->zs);
        } else {
            inflateEnd(&state->zs);
        }
    }
    free(state);
    stream->state = NULL;
    return COMPRESSION_STATUS_OK;
}
