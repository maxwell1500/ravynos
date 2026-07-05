/**
 * log.h
 * Author: Zoe Knox      Created: 2026-7-3
 *
 * Copyright (C) 2026 Zoe Knox. All rights reserved.
 * SPDX: BSD-2-Clause
 *
 * This is an original implementation of Apple's libsystem_trace.dylib based on
 * open-source code, including ASL, XNU, Swift, and other sources, and the API
 * specs on developer.apple.com.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifndef _OS_LOG_H_
#define _OS_LOG_H_

#include <stdint.h>
#include <stddef.h>
#include <stdarg.h>

#if __has_include_next(<os/log.h>)
#include_next <os/log.h>
#endif

typedef struct os_log_pack_s* os_log_pack_t;

/* --- Private Area --- */
typedef struct {
    uint8_t  type;
    uint8_t  flags;
    uint16_t reserved;
    uint32_t payload_size;
} _os_log_arg_header;

typedef enum : uint8_t {
    OS_LOG_ARG_TYPE_SCALAR = 0,
    OS_LOG_ARG_TYPE_STRING = 1, // UTF-8
    OS_LOG_ARG_TYPE_WIDESTRING = 2, // 16 or 32 bit Unicode chars
    OS_LOG_ARG_TYPE_POINTER = 3,
    OS_LOG_ARG_TYPE_OBJECT = 4, // ObjC object
    OS_LOG_ARG_TYPE_ERRNO = 5,
    OS_LOG_ARG_TYPE_BOOLEAN = 6,
    OS_LOG_ARG_TYPE_DOUBLE = 7, // also for float
    OS_LOG_ARG_TYPE_INT = 8,
} _os_log_arg_type;

typedef enum : uint8_t {
    OS_LOG_FLAG_PUBLIC = 0,
    OS_LOG_FLAG_PRIVATE = 1,
    OS_LOG_FLAG_SENSITIVE = 2
} _os_log_arg_flags;

typedef enum : uint8_t {
    OS_LOG_MASK_NUMERIC = 0x10,
    OS_LOG_MASK_STRING = 0x20,
    OS_LOG_MASK_OBJECT = 0x40,
    OS_LOG_MASK_RESERVED = 0x80
} _os_log_arg_mask;

/* --- End Private Area --- */

extern struct os_log_s _os_log_disabled;
extern struct os_log_s _os_log_null;

__BEGIN_DECLS
/**
 * @function os_log_create
 * @abstract Creates a custom log object
 * @param subsystem  An identifier in reverse DNS notation
 * @param category   A category string within the subsystem
 * @return An os_log_t object to be passed to logging functions. The object
 *         is retained and should be released when done.
 */
__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT OS_WARN_RESULT OS_OBJECT_RETURNS_RETAINED
os_log_t OS_NOTHROW os_log_create(const char* subsystem, const char* category);

__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
bool os_log_type_enabled(os_log_t log, os_log_type_t type);

__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
bool os_log_info_enabled(os_log_t log);

__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
bool os_log_debug_enabled(os_log_t log);

__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
bool os_log_shim_enabled(os_log_t log, os_log_type_t type);

/* --- Private SPIs --- */

/**
 * @function os_log_encode
 * @param buffer        Pointer to where the encoded blob will be written
 * @param buffer_size   Capacity of the storage buffer in bytes
 * @param format        A printf-like format string
 * @param args          The args to fill in the format specifiers
 * @param flags         Privacy and formatting flags
 * @return The number of bytes written to `buffer`, or 0 if an error occurs
 */
__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
size_t os_log_encode(void* buffer,
    size_t buffer_size,
    const char* format,
    va_list args,
    uint32_t flags); /*  __DARWIN_ALIAS(_os_log_encode); ?? */

/* Wrapper used by os/assumes.h */
size_t __os_log_encode(void* buffer,
    size_t buffer_size,
    const char* format,
    ...);

/**
 * @function os_log_pack_size
 * @abstract Computes and returns the number of bytes needed to store the
 *           formatted arguments and format string provided into an
 *           os_log_pack_t object.
 * @param format       printf-style format string
 * @param args         A binary buffer encoded by os_log_encode()
 * @param flags        Privacy and formatting flags
 * @return Returns the number of bytes needed for the log object
 */
__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
size_t os_log_pack_size(const char* format, void* args, uint32_t flags);

/**
 * @function os_log_pack_fill
 * @abstract Adds metadata (timestamps, return address, mach_header) to the
 *           memory pointed to by pack, which has the capacity pack_size.
 *           The required size should be found by calling os_log_pack_size()
 *           first.
 * @param pack         Pointer to a os_log_pack_t buffer
 * @param pack_size    Size allocated to the pack
 * @param saved_errno  Contents of errno at the time of the call
 * @param dso          Return address of the caller
 * @param format       printf-style format string
 * @return Returns a pointer to the start of the payload area. The caller
 *         must copy the buffer from os_log_encode() to this address before
 *         calling os_log_pack_send(). Returns NULL on error.
 */
/* Internal ABI for 10.14+ */
__OSX_AVAILABLE_STARTING(__MAC_10_14, __IPHONE_12_0)
OS_EXPORT
uint8_t* os_log_pack_fill(void* pack,
    size_t pack_size,
    int saved_errno,
    const void* dso,
    const char* format);

/**
 * @function os_log_pack_send
 * @param pack A completed log pack object
 * @param log  Log object that will receive the pack
 * @param type Type of log message (debug, info, error, etc)
 *
 */
__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
void os_log_pack_send(os_log_pack_t pack,
    os_log_t log,
    os_log_type_t type
);

/**
 * @function _os_log_pack_init
 * @param pack          Pointer to the output buffer
 * @param pack_size     Capacity of the output buffer in bytes
 * @param saved_errno   The value of errno at the time of the call
 * @param dso           Return address of the caller
 * @param format        A printf-like format string
 * @param args          The args to fill in the format specifiers
 * @return The number of bytes written to `buffer`, or 0 if an error occurs
 */
__OSX_AVAILABLE_STARTING(__MAC_10_12, __IPHONE_10_0)
OS_EXPORT
size_t _os_log_pack_init(void* pack,
    size_t pack_size,
    int saved_errno,
    const void* dso,
    const char* format,
    va_list args);


/**
 * @function __os_log_impl
 * @param dso       Return address of caller
 * @param log       Log object to receive the message
 * @param type      Type of log message (error, debug, etc)
 * @param format    A printf-like format string
 * @param buffer    Pointer to storage for the encoded args
 */
void __os_log_impl(void* dso,
    os_log_t log,
    os_log_type_t type,
    const char* format,
    uint8_t* buffer,
    uint32_t buffer_size) __DARWIN_ALIAS(_os_log_impl);

void __os_log_error_impl(void* dso,
    os_log_t log,
    const char* format,
    uint8_t* buffer,
    uint32_t buffer_size);

void __os_log_fault_impl(void* dso,
    os_log_t log,
    const char* format,
    uint8_t* buffer,
    uint32_t buffer_size);

size_t _os_trace_encode(void* buffer,
    size_t buffer_size,
    const char* format,
    va_list args,
    uint32_t flags);

void _os_trace_encode_and_send(void* dso,
    os_log_t log,
    os_log_type_t type,
    const char* format,
    va_list args,
    uint32_t flags);
void _os_trace_debug(const char* message);
void _os_trace_error(const char* message);

void _os_log_error(void* dso, os_log_t log, const char* format, ...);
void _os_log_fault(void* dso, os_log_t log, const char* format, ...);
void _os_log_info(void* dso, os_log_t log, const char* format, ...);
void _os_log_debug(void* dso, os_log_t log, const char* format, ...);

void _os_log_simple(void* dso,
    os_log_t log,
    os_log_type_t type,
    const char* message);

void _os_log_simple_impl(void* dso,
    os_log_t log,
    os_log_type_t type,
    const char* message);

void _os_log_set_mode(uint32_t mode);
uint32_t _os_log_get_mode(void);
void _os_log_preferences_refresh(void);


__END_DECLS

#endif // _OS_LOG_H_
