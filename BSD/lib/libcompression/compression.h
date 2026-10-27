/*
 * <compression.h> for ravynOS.
 *
 * The block and stream APIs macOS frameworks use (NSData compression, Pages,
 * Archive Utility).  Algorithm availability is honest: ZLIB and the LZ4 block
 * formats are implemented here, LZVN has a decoder (Apple's own source is in
 * Developer/Default.xctoolchain/lzvndecode), and LZFSE/LZMA answer
 * COMPRESSION_STATUS_ERROR rather than producing bytes that are not the
 * requested format.
 */
#ifndef _COMPRESSION_H_
#define _COMPRESSION_H_

#include <sys/cdefs.h>
#include <stddef.h>
#include <stdint.h>

__BEGIN_DECLS

typedef enum {
    COMPRESSION_LZ4 = 0x100,
    COMPRESSION_LZ4_RAW = 0x101,
    COMPRESSION_ZLIB = 0x205,
    COMPRESSION_LZMA = 0x306,
    COMPRESSION_LZFSE = 0x801,
    COMPRESSION_LZVN = 0x900
} compression_algorithm;

typedef enum {
    COMPRESSION_STATUS_OK = 0,
    COMPRESSION_STATUS_ERROR = 1,
    COMPRESSION_STATUS_END = 2
} compression_status;

typedef struct compression_stream {
    compression_algorithm algorithm;
    void *dst_ptr;
    size_t dst_size;
    void *src_ptr;
    size_t src_size;
    void *state;
} compression_stream;

extern size_t compression_encode_buffer(void *dst_buffer, size_t dst_size,
                                        const void *src_buffer, size_t src_size,
                                        void *scratch_buffer,
                                        compression_algorithm algorithm);
extern size_t compression_decode_buffer(void *dst_buffer, size_t dst_size,
                                        const void *src_buffer, size_t src_size,
                                        void *scratch_buffer,
                                        compression_algorithm algorithm);
extern size_t compression_encode_scratch_buffer_size(compression_algorithm algorithm);
extern size_t compression_decode_scratch_buffer_size(compression_algorithm algorithm);
extern compression_status compression_stream_init(compression_stream *stream,
                                                  compression_algorithm algorithm,
                                                  int operation);
extern compression_status compression_stream_process(compression_stream *stream,
                                                     int flags);
extern compression_status compression_stream_destroy(compression_stream *stream);

#define COMPRESSION_STREAM_ENCODE 0
#define COMPRESSION_STREAM_DECODE 1
#define COMPRESSION_STREAM_FINALIZE 0x0001

__END_DECLS

#endif
