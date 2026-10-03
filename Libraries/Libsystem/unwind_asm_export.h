/* Force LLVM's libunwind assembly sources to export their symbols.
 *
 * WHY THIS EXISTS
 * ---------------
 * The two symbols libobjc needs --
 *   __unw_getcontext
 *   __libunwind_Registers_x86_64_jumpto
 * -- live only in libunwind's two hand-written assembly files,
 * UnwindRegistersSave.S and UnwindRegistersRestore.S. Both are compiled and
 * linked into libunwind.dylib by Libraries/Libsystem/Makefile. They are
 * present, and they work. What they do NOT do is leave the dylib, which is
 * the whole reason libobjc's references to them go unresolved.
 *
 * The cause is one line of LLVM's own assembly.h, the non-AIX arm of
 * DEFINE_LIBUNWIND_FUNCTION (assembly.h:258-265 upstream, and identically
 * here):
 *
 *   #define DEFINE_LIBUNWIND_FUNCTION(name)                          \
 *     .globl SYMBOL_NAME(name) SEPARATOR                             \
 *     HIDDEN_SYMBOL(SYMBOL_NAME(name)) SEPARATOR                     \  <-- this
 *     ...
 *
 * and, for Apple targets (assembly.h:118-126):
 *
 *   #define HIDDEN_SYMBOL(name) .private_extern name
 *
 * So every function these files define is emitted .globl AND
 * .private_extern. On a Mach-O dylib .private_extern is the assembler's way
 * of saying "visible to this linkage unit only": ld64 localises the symbol
 * and drops it from the export trie. Measured on the object and the result:
 *
 *   $ nm -m Libraries/Libsystem/UnwindRegistersSave.o
 *   0000000000000000 (__TEXT,__text) private external ___unw_getcontext
 *
 *   $ nm $SDK/usr/lib/system/libunwind.dylib | grep -E 'unw_getcontext|jumpto'
 *   000000000000c1f0 t ___unw_getcontext
 *   000000000000c242 t ___libunwind_Registers_x86_64_jumpto
 *
 * Lowercase `t` is the proof: the code is linked in, but not exported. So the
 * build was never "missing" these symbols in the sense of not compiling them
 * -- it was compiling them with the wrong visibility, and Apple's own shipped
 * libunwind.dylib has exactly the same shape.
 *
 * WHY APPLE'S OWN LIBUNWIND GETS AWAY WITH IT
 * -------------------------------------------
 * Apple's real libobjc really does carry the same two undefined references
 * (verified against the host-extracted image), and Apple's real libunwind
 * really does keep both private. It binds because both are members of the
 * dyld shared cache, and the cache is produced by linking every image as ONE
 * link unit -- .private_extern symbols resolve freely between members of that
 * single unit. ravynOS has no shared cache; every dylib is loaded standalone.
 * A private symbol in a standalone dylib is unreachable, so on ravynOS the
 * same arrangement that works on macOS leaves two genuinely unbound
 * references. That is the whole delta, and it is why this is a visibility
 * fix rather than a missing-code fix.
 *
 * WHY THIS OVERRIDES A MACRO INSTEAD OF EDITING THE .S FILES
 * ----------------------------------------------------------
 * Two properties are being preserved deliberately, and this keeps both:
 *
 *   - The instruction stream stays byte-for-byte upstream's. The whole
 *     hazard called out in Makefile:116-133 is that
 *     __libunwind_Registers_x86_64_jumpto hard-codes the unw_tdep_frame_t
 *     slot offsets (0 rax .. 128 rip, 56 rsp), and those offsets ARE the ABI.
 *     Nothing here touches an instruction, an offset, or a register.
 *
 *   - The vendored LLVM tree stays unmodified, so the next toolchain sync
 *     cannot silently revert this. The override lives in Libsystem and is
 *     applied at compile time.
 *
 * Nothing is stubbed, aliased or weakened: the same upstream instructions
 * run, they are just given external linkage so ld64 will export them.
 *
 * MECHANISM
 * ---------
 * DEFINE_LIBUNWIND_FUNCTION expands HIDDEN_SYMBOL at the point of USE, not at
 * the point of definition, so redefining HIDDEN_SYMBOL after assembly.h has
 * been read is sufficient to change what gets emitted.
 *
 * assembly.h guards itself with UNWIND_ASSEMBLY_H, so the #include at the top
 * of each .S becomes a no-op once this header has pulled it in first. That is
 * what makes -include (rather than editing the sources) work: the .S files are
 * processed verbatim.
 */

#include "../../Developer/Default.xctoolchain/llvm/libunwind/src/assembly.h"

#undef HIDDEN_SYMBOL
#define HIDDEN_SYMBOL(name)
