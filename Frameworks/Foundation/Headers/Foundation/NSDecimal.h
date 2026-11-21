/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <stdint.h>

/*
 * NSDecimal is an ABI type.  It is passed and returned **by value** across the
 * framework boundary (-[NSDecimalNumber decimalValue],
 * +decimalNumberWithDecimal:, NSDecimalAdd, ...), so its layout has to be the
 * layout the caller compiled against, byte for byte.  Apple's is 20 bytes:
 * an 8-bit signed exponent, three bitfields, and an eight-word little-endian
 * base-65536 mantissa.  Measured, not assumed:
 *
 *     1.5  -> exponent -1, length 1, mantissa {15}
 *     10   -> exponent  1, length 1, mantissa {1}
 *     -3.25-> exponent -2, length 1, isNegative 1, mantissa {325}
 *     1234567890123456789 -> exponent 0, length 4, mantissa {33045,32233,4340,4386}
 *
 * A decimal whose length is zero is "not a number".
 */
typedef struct {
    signed int   _exponent : 8;
    unsigned int _length : 4;
    unsigned int _isNegative : 1;
    unsigned int _isCompact : 1;
    unsigned int _reserved : 18;
    unsigned short _mantissa[8];
} NSDecimal;

/*
 * The representation the arithmetic in NSDecimalNumber.m actually works in:
 * one 64-bit mantissa and a decimal exponent, which is enough for the values
 * applications use and cheap to operate on.  It is deliberately *not* the
 * public type; every crossing of the API boundary converts.
 */
typedef struct {
    uint64_t mantissa;
    int16_t  exponent;
    int8_t   isNegative;
    int8_t   isNaN;
} NSDecimalValue;

#define NSDecimalValueZero ((NSDecimalValue){ 0, 0, 0, 0 })
