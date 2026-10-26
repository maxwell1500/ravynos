/*
 * MacIntakeCore -- the @rpath-linked embedded dylib of MacOSIntakeProbe.
 * Its only job is to be found through LC_RPATH and to prove it was loaded.
 */

#include "MacIntakeCore.h"

int MacIntakeCoreMagic(void) {
    return 0x4D414349;   /* 'MACI' */
}
