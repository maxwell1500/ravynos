/*
 * Shim: <corecrypto/cc_abort.h>
 *
 * The genuine header lives at
 *     Kernel/Extensions/corecrypto/cc_abort.h
 * but the sources include it as <corecrypto/cc_abort.h>, which resolves to
 *     Kernel/Extensions/corecrypto/include/corecrypto/cc_abort.h
 * where it is absent. The file is simply misfiled: the kext keeps 48 headers
 * under include/corecrypto/ and this one sits at the kext root instead.
 *
 * That misfiling blocks four otherwise-fine userspace sources:
 *     cc_functions.c  cc_digest.c  algorithms/aes_cbc.c  algorithms/aes_ecb.c
 * which failed with "fatal error: 'corecrypto/cc_abort.h' file not found".
 *
 * This file defines nothing. It forwards to the real header by relative path
 * so that cc_abort, its signature, and the CC_KERNEL branch that selects
 * panic() over fprintf/abort all come from the genuine 10-line original. Do
 * not copy its contents here, do not re-implement cc_abort, and do not
 * "simplify" this to an empty file -- an empty shim would leave the four
 * sources with an undefined cc_abort rather than a misfiled one.
 */

#include "../../../../../Kernel/Extensions/corecrypto/cc_abort.h"
