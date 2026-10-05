MK_WERROR = no

LIB = System.B
SRCS = init.c CompatibilityHacks.c stubs.c

# NOTE ON -I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall (PROVENANCE-PLAN.md §4 P5).
# This path used to be .../libsyscall/mach, which put xnu's 14-header
# KERNEL-internal mach/ generation AHEAD of the SDK's usr/include/mach, so a
# single translation unit read mach.h, mach_init.h, mach_error.h,
# mach_interface.h and vm_page_size.h from xnu while the other 58 mach/
# headers came from the SDK. Pointing at the parent instead exposes no
# top-level headers of its own (libsyscall/*.h does not exist), so
# <mach/...> resolves through -isysroot to the SDK's single generation.
# Same shape as the working precedent at tools/bootlab/isysroot-cc:196.
CFLAGS = --sysroot=${RAVYN_SDKROOT} -w \
	-mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wno-implicit-function-declaration \
	-Wno-int-conversion -Wno-implicit-int -fno-common \
	-I${.CURDIR}/libsystem_c/darwin \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/EXTERNAL_HEADERS \
	-I${RAVYN_SDKROOT}/usr/include/pthread -I${.CURDIR}/private \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/libsyscall/wrappers \
	-I${.CURDIR}/libsystem_c/include \
	-I${ROOT_BINARY_DIR}/Kernel/xnu/bsd \
	-I${ROOT_BINARY_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
	-I${ROOT_BINARY_DIR}/${CpuArch} \
	-I${RAVYN_SDKROOT}/usr/include \
	-I${RAVYN_SDKROOT}/usr/local/include \
	-D__DARWIN_UNIX03 \
	-include${.OBJDIR}/config.${CpuArch}.normal.h

# The order of the -reexport- flags below is load-bearing, and putting
# libsystem_pwdgrp ahead of libsystem_info is the whole point of it.
#
# A re-export dylib from this ld64 carries no per-symbol attribution at
# all. Measured, not assumed: dyld_info -exports on the resulting
# libSystem.B lists no re-exported name whatsoever -- not _getpwnam, and
# not _printf either, which is certainly re-exported from libsystem_c.
# Ownership is therefore decided at load time, by the first
# LC_REEXPORT_DYLIB in the list that exports the symbol.
#
# libsystem_info.dylib still exports getpwnam/getpwuid/...; it has always
# carried its own implementation, and that is the component
# MISSING_DEPS.md records as blocked. A libSystem.B that lists it first
# therefore keeps serving the passwd database from the blocked component,
# and this wiring would look complete while changing nothing at all.
# Listing libsystem_pwdgrp first makes it the owner. libsystem_info is
# still re-exported, for getaddrinfo, gethostbyname and the rest of its
# non-passwd surface.

LDFLAGS = -mmacos-version-min=${MACOS_VERSION_MIN} \
	--sysroot=${RAVYN_SDKROOT} \
	-Wl,-syslibroot,${RAVYN_SDKROOT}/usr/lib \
	-L${RAVYN_SDKROOT}/usr/lib/system \
	-L${RAVYN_SDKROOT}/usr/local/lib/system \
	-L${RAVYN_SDKROOT}/usr/lib -Wl,-no_warn_inits \
	-Wl,-install_name,/usr/lib/libSystem.B.dylib \
	-Wl,-current_version,1254 \
	-Wl,-compatibility_version,1.0.0 \
	-nodefaultlibs -dylib -Wl,-search_paths_first \
	-Wl,-reexport-lsystem_c -Wl,-reexport-lsystem_blocks \
	-Wl,-reexport-lsystem_asl -Wl,-reexport-lCrashReporterClient \
	-Wl,-reexport-lsystem_malloc -Wl,-reexport-lsystem_platform \
	-Wl,-reexport-lsystem_darwin -Wl,-reexport-lsystem_pthread \
	-Wl,-reexport-lsystem_kernel -Wl,-reexport-lcompiler_rt \
	-Wl,-reexport-lunwind -Wl,-reexport-lxpc -Wl,-reexport-ldyld \
	-Wl,-reexport-llaunch -Wl,-reexport-ldispatch \
	-Wl,-reexport-lsystem_m -Wl,-reexport-lsystem_coreservices \
	-Wl,-reexport-lsystem_notify \
	-Wl,-reexport-lsystem_pwdgrp -Wl,-reexport-lsystem_info \
	-Wl,-reexport-lsystem_termcap \
	-Wl,-reexport-lcopyfile -Wl,-reexport-lmacho \
	-Wl,-reexport-lremovefile -Wl,-reexport-lsystem_trace \
	-Wl,-reexport-lsystem_dnssd -Wl,-reexport-lcorecrypto \
	-lcompiler_rt -ldyld -lsystem_c -lc++ -lCrashReporterClient\
	-lsystem_platform -lsystem_kernel -lsystem_blocks -lsystem_malloc \
	-lsystem_info -lsystem_notify -lsystem_trace -lsystem_asl \
	-lsystem_blocks -lsystem_pthread -ldispatch -lxpc -llaunch -lsystem_m \
	-lsystem_pwdgrp -lsystem_termcap

all: lib${LIB}.dylib

${.OBJDIR}/config.${CpuArch}.normal.h:
	DEVELOPER_DIR=${ROOT_BINARY_DIR}/Developer \
	RUNTIME_SPEC_PATH=${TOOLCHAIN}/Library/Xcode/Specifications \
	PATH=${TOOLS}:${PATH} \
	${.CURDIR}/xcodescripts/linker_arguments.sh \
	${CpuArch} normal ${.OBJDIR} ${RAVYN_SDKROOT} ${.CURDIR}

${OBJS}: ${.OBJDIR}/config.${CpuArch}.normal.h ${SRCS}
#-----------------------------------------------------------------------------
#              THE THREE OBJECTS THIS TREE NEVER BUILT
#-----------------------------------------------------------------------------
# Four symbols reached the linked closure undefined, all of them because a
# canonical upstream source file was never compiled here rather than because
# anything is missing from LLVM. None of them is hand-written below: every one
# is built from the LLVM sources that are already vendored in
# Developer/Default.xctoolchain/llvm, at the same version the rest of the
# toolchain is.
#
# __libcxx_exp_memrsc_init -- libc++.a's init.o (__libcxx_init) calls three
# libc++ static-initialization chunk functions, and this dylib links libc++.a,
# so all three land here. Two of them (__libcxx_memrsc_init, __libcxx_ios_init)
# are defined by libc++.a itself. The third is defined in
# llvm/libcxx/src/experimental/memory_resource.cpp, which upstream builds into
# libc++experimental.a -- an archive this tree never produced:
# Libraries/llvm_target/libcxx/lib/ holds libc++.a and nothing else. Compiling
# that translation unit is the fix; a C stub cannot be, and not because of
# convenience. __default_memory_resource() keeps the default resource in a
# function-local `static constinit atomic<memory_resource*>` that lives in the
# DEFINING translation unit, so a second definition would be a distinct object
# that no caller of std::experimental::fundamentals_v1::pmr::get_default_resource()
# ever reads. Compiling the real unit supplies the symbol and the storage it
# initializes, which is the whole point of the function.
#
# It is linked into libSystem.B rather than into libsystem_c (where cxa_guard.c
# went) because its only caller lives here and its dependencies --
# _VSTD::__libcpp_allocate, __throw_bad_alloc, std::__1::__cxx_atomic_* -- are all
# satisfied by the libc++.a already on this link line. Putting it in
# libsystem_c would give libc undefined C++ symbols and a load-time cycle back
# up into the dylib that re-exports it, for no gain.
#
# __unw_getcontext / unw_getcontext / __libunwind_Registers_x86_64_jumpto --
# LLVM's libunwind keeps these three in two hand-written assembly files,
# UnwindRegistersSave.S and UnwindRegistersRestore.S. The prebuilt
# Libraries/llvm_target/libunwind/lib/libunwind.a contains only the seven C/C++
# objects; upstream's src/CMakeLists.txt lists both .S files in
# LIBUNWIND_ASM_SOURCES, so this archive was cut without them. That is exactly
# why they must be compiled from LLVM's own assembly rather than written here:
# __libunwind_Registers_x86_64_jumpto hard-codes the unw_tdep_frame_t slot
# offsets (0 rax .. 128 rip, 56 rsp), and those offsets are the ABI.
#
# Both objects go through ${CC}, the same wrapper every other component uses.

LLVM_RT = ${ROOT_SOURCE_DIR}/Developer/Default.xctoolchain/llvm

UNWIND_SAVE_S = ${LLVM_RT}/libunwind/src/UnwindRegistersSave.S
UNWIND_RESTORE_S = ${LLVM_RT}/libunwind/src/UnwindRegistersRestore.S
UNWIND_ASM_HDRS = ${LLVM_RT}/libunwind/src/assembly.h \
	${LLVM_RT}/libunwind/src/cet_unwind.h
UNWIND_ASM_OBJS = ${.OBJDIR}/UnwindRegistersSave.o \
	${.OBJDIR}/UnwindRegistersRestore.o

EXPMEMRSC_CPP = ${LLVM_RT}/libcxx/src/experimental/memory_resource.cpp
EXPMEMRSC_O = ${.OBJDIR}/experimental_memory_resource.o

# The wrapper gates its C force-includes off the .s/.S suffix, so these two
# are handed to the assembler as assembly rather than preprocessed as C.
#
# -include unwind_asm_export.h is load-bearing, not cosmetic. LLVM's
# assembly.h:258-265 emits DEFINE_LIBUNWIND_FUNCTION as ".globl" PLUS
# HIDDEN_SYMBOL, and for Apple targets assembly.h:121 defines
# HIDDEN_SYMBOL as .private_extern. Both .S files therefore compiled to
# private-external symbols, ld64 localised them, and they never reached the
# export trie -- libobjc's two references had nothing to bind to:
#   $ nm -m UnwindRegistersSave.o
#     0000000000000000 (__TEXT,__text) private external ___unw_getcontext
#   $ nm $SDK/usr/lib/system/libunwind.dylib | grep -E 'unw_getcontext|jumpto'
#     000000000000c1f0 t ___unw_getcontext
#     000000000000c242 t ___libunwind_Registers_x86_64_jumpto
# lowercase `t` -- linked in, not exported. Apple's own libunwind.dylib has
# the same shape and gets away with it only because the dyld shared cache
# links every image as one unit, where .private_extern resolves freely
# between members. ravynOS loads each dylib standalone, so they must be
# genuinely exported. The header changes only that visibility; see it for
# why it overrides a macro rather than touching the vendored LLVM tree.
${.OBJDIR}/UnwindRegistersSave.o: ${UNWIND_SAVE_S} ${UNWIND_ASM_HDRS} \
		${.CURDIR}/unwind_asm_export.h
	${CC} -c -o $@ -include ${.CURDIR}/unwind_asm_export.h ${UNWIND_SAVE_S}

${.OBJDIR}/UnwindRegistersRestore.o: ${UNWIND_RESTORE_S} ${UNWIND_ASM_HDRS} \
		${.CURDIR}/unwind_asm_export.h
	${CC} -c -o $@ -include ${.CURDIR}/unwind_asm_export.h ${UNWIND_RESTORE_S}

# -std=c++20: memory_resource.cpp uses `static constinit`, a C++20 keyword.
# At the language default clang reports "unknown type name 'constinit'" and
# produces nothing. Nothing else here depends on the language version.
# -nostdinc++ with an explicit -isystem: this tree's libc++ headers, never the
# host Command Line Tools ones. -isystem rather than -I so the C++ headers
# sort after the SDK's, which is the order the SDK itself expects.
${EXPMEMRSC_O}: ${EXPMEMRSC_CPP}
	${CC} -c -o $@ --sysroot=${RAVYN_SDKROOT} \
	  -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-incompatible-sysroot \
	  -nostdinc++ -isystem${RAVYN_SDKROOT}/usr/include/c++/v1 \
	  -D_LIBCPP_BUILDING_LIBRARY -std=c++20 -fno-rtti -fPIC \
	  ${EXPMEMRSC_CPP}

# libc++'s four buffered float-to-string internals.
#
# ICU compiles std::to_chars calls that clang lowers into out-of-line calls to
# std::__1::__d2s_buffered_n / __f2s_buffered_n / __d2exp_buffered_n /
# __d2fixed_buffered_n. Upstream libc++ defines those in src/ryu/{d2s,f2s,
# d2fixed}.cpp; this tree's libc++.a was produced without them, so every staged
# consumer of a floating-point to_chars carried four unbound libc++ symbols and
# closure_gate.py reported them unresolved. They are NOT defined by
# src/charconv.cpp -- compiling that file yields an object that *references* all
# four as undefined, which is why archiving charconv.o alone changes nothing.
#
# The flags are those of EXPMEMRSC above, verbatim, plus one addition that is
# mandatory rather than stylistic: -I${LLVM_RT}/libcxx/src. Without it
# to_chars_floating_point.h:33 fails with
#   fatal error: 'include/ryu/ryu.h' file not found
# because that header is included as "include/ryu/ryu.h" relative to src/.
#
# These objects go INTO libc++.a rather than onto the libSystem link line. They
# are libc++ internals, not libSystem exports: putting them on the link would
# give the dylib the wrong linkage for symbols whose callers are already bound
# to libc++.a's copies, and would duplicate the definitions.
#
# The archive is written to ${RAVYN_SDKROOT}/usr/lib/libc++.a because that is
# the exact file -lc++ resolves against (LDFLAGS carries -L${RAVYN_SDKROOT}/usr/lib),
# so updating it here is what changes what the link below actually picks up.
LIBCXX_A_TREE = ${ROOT_SOURCE_DIR}/Libraries/llvm_target/libcxx/lib/libc++.a
LIBCXX_A = ${RAVYN_SDKROOT}/usr/lib/libc++.a
RYU_DIR = ${LLVM_RT}/libcxx/src/ryu
RYU_CPP = ${RYU_DIR}/d2s.cpp ${RYU_DIR}/f2s.cpp ${RYU_DIR}/d2fixed.cpp
RYU_O = ${.OBJDIR}/ryu_d2s.o ${.OBJDIR}/ryu_f2s.o ${.OBJDIR}/ryu_d2fixed.o
LIBCXX_SRC_DIR = ${LLVM_RT}/libcxx/src

${.OBJDIR}/ryu_d2s.o: ${RYU_DIR}/d2s.cpp
	${CC} -c -o $@ --sysroot=${RAVYN_SDKROOT} \
	  -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-incompatible-sysroot \
	  -nostdinc++ -isystem${RAVYN_SDKROOT}/usr/include/c++/v1 \
	  -I${LIBCXX_SRC_DIR} \
	  -D_LIBCPP_BUILDING_LIBRARY -std=c++20 -fno-rtti -fPIC \
	  ${RYU_DIR}/d2s.cpp

${.OBJDIR}/ryu_f2s.o: ${RYU_DIR}/f2s.cpp
	${CC} -c -o $@ --sysroot=${RAVYN_SDKROOT} \
	  -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-incompatible-sysroot \
	  -nostdinc++ -isystem${RAVYN_SDKROOT}/usr/include/c++/v1 \
	  -I${LIBCXX_SRC_DIR} \
	  -D_LIBCPP_BUILDING_LIBRARY -std=c++20 -fno-rtti -fPIC \
	  ${RYU_DIR}/f2s.cpp

${.OBJDIR}/ryu_d2fixed.o: ${RYU_DIR}/d2fixed.cpp
	${CC} -c -o $@ --sysroot=${RAVYN_SDKROOT} \
	  -mmacos-version-min=${MACOS_VERSION_MIN} -Wno-incompatible-sysroot \
	  -nostdinc++ -isystem${RAVYN_SDKROOT}/usr/include/c++/v1 \
	  -I${LIBCXX_SRC_DIR} \
	  -D_LIBCPP_BUILDING_LIBRARY -std=c++20 -fno-rtti -fPIC \
	  ${RYU_DIR}/d2fixed.cpp

# Two steps, and the first is not optional. `ar r` on a path that does not exist
# CREATES a fresh archive containing only the members named -- so without the
# seed below, building into an empty SDK would leave a libc++.a holding three
# ryu objects and none of libc++, and every libc++ reference in libSystem would
# then be undefined. The seed restores the canonical archive first, so the rule
# works both against a populated SDK and against an empty one.
#
# `ar r` replaces a member of the same name and adds a new one otherwise, so
# this is idempotent: re-running does not accumulate duplicates.
${LIBCXX_A}: ${LIBCXX_A_TREE} ${RYU_O}
	@cp -f ${LIBCXX_A_TREE} ${LIBCXX_A}
	@${AR} r ${LIBCXX_A} ${RYU_O}

# WHY THIS LINKS INTO ${.CURDIR} AND NOT STRAIGHT INTO THE SDK.
#
# This target used to write straight to ${RAVYN_SDKROOT}/usr/lib/system/,
# which made the SDK the build OUTPUT directory rather than an install
# destination. That is invisible while the SDK happens to live inside the
# build tree, and it is exactly what left tools/bootlab/manifest_cpmv.json
# un-relocatable: mkimage.py resolves "file" relative to tools/bootlab and
# cannot expand ${RAVYN_SDKROOT}, so the only way to name this dylib was a
# path that escaped the repo (../../../build/.../ravynOS.sdk/usr/lib/system/
# ...). The manifest then named a machine-specific tree and PROVENANCE-PLAN
# P0 could not close.
#
# The fix is the shape the rest of this closure already uses: link into
# ${.CURDIR} -- an in-repo build product, already covered by the
# /Libsystem/**/*.dylib rule in Libraries/.gitignore -- and `cp` it into the
# SDK as an INSTALL step. Every other entry in the manifest names a
# ${.CURDIR}/<component>/<lib>.dylib build product for the same reason.

UNWIND_TARGET = ${.CURDIR}/libunwind.dylib

libunwind.dylib: ${.OBJDIR}/../llvm_target/libunwind/lib/libunwind.a \
	${UNWIND_ASM_OBJS}
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	${CC} -umbrella System -Wl,-all_load -fuse-ld=${LD} -shared \
	  -dylib -o ${UNWIND_TARGET} \
	  -Wl,-install_name,/usr/lib/system/libunwind.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,35.4 \
	  -L${RAVYN_SDKROOT}/usr/lib -L${RAVYN_SDKROOT}/usr/lib/system \
	  -mmacosx-version-min=${MACOS_VERSION_MIN} ${.ALLSRC} \
	  -lsystem_c -lsystem_pthread -lsystem_platform -lcompiler_rt \
	  -lsystem_malloc -ldyld
	cp -f ${UNWIND_TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	# cp returns 1 when source and destination are the same file, and
	# SYSROOT_DIR and RAVYN_SDKROOT can resolve to the same tree (they are
	# both environment-supplied). That turned this "copy" into a hard build
	# failure with only "cp: ... are identical (not copied)" to show for it,
	# after the real work had already succeeded. Skip the copy when the files
	# already match; cmp also fails when the destination is missing, so a
	# genuine first copy still happens.
	@cmp -s ${RAVYN_SDKROOT}/usr/lib/system/libunwind.dylib \
	    ${SYSROOT_DIR}/usr/lib/system/libunwind.dylib 2>/dev/null || \
	cp -f ${UNWIND_TARGET} ${SYSROOT_DIR}/usr/lib/system/

#-----------------------------------------------------------------------------
#                    libcompiler_rt.dylib -- THE MISSING PRODUCER
#-----------------------------------------------------------------------------
# libSystem.B LC_REEXPORT_DYLIBs this, and liblaunch, libsystem_pthread,
# libsystem_notify, libsystem_info, libsystem_c, libsystem_malloc and
# libunwind all link -lcompiler_rt, so the closure is INCOMPLETE without it.
# Nothing in this repository used to produce it: Libraries/Makefile's
# `compiler_rt` target only verifies the ARCHIVE libclang_rt.osx.a through
# require_real_archive.sh, and that archive is itself only ever produced out
# of tree. The dylib's bytes existed at $RAVYN_SDKROOT/usr/lib/system/ with no
# rule that could regenerate them, which is why
# tools/bootlab/manifest_cpmv.json had to name them by an out-of-repo path
# (PROVENANCE-PLAN P0, "P6 UNKNOWN").
#
# So this target builds it for real, from the vendored compiler-rt sources,
# and installs it like every other member above.
#
# The inputs, and why each flag is here:
#
#  * -fvisibility=default. compiler-rt's own Darwin build passes
#    -fvisibility=hidden -DVISIBILITY_HIDDEN, which is correct for an archive
#    that a CONSUMER links (only the builtins it references get pulled in).
#    It is wrong for the dylib: built here, every object came out private
#    external, ld64 exported nothing at all, and the result was a 4 KB image
#    with an empty export trie. Measured, both ways.
#
#  * -fno-stack-protector. The reference objects import no __stack_chk_*.
#
#  * -D__DARWIN_UNIX03 -DXNU_PLATFORM_MacOSX
#    -D__DARWIN_ONLY_UNIX_CONFORMANCE=0. This is the same header problem
#    build-libraries.sh already injects the first two of for: the SDK's
#    sys/cdefs.h wraps every symbol-versioning suffix in __DARWIN_ONLY_*, and
#    userspace never defines those. Without the override, __DARWIN_SUF_UNIX03
#    expands to nothing and enable_execute_stack.c imports _mprotect instead
#    of _mprotect$UNIX2003. The reference imports the $UNIX2003 spelling.
#    Both spellings exist in this closure, so either binds -- but the suffixed
#    one is what libsystem_c actually exports under that name.
#
#  * -nodefaultlibs and -Wl,-not_for_dyld_shared_cache. ${CC} is
#    tools/bootlab/isysroot-cc, which injects -nodefaultlibs because clang
#    otherwise adds -lSystem to every dylib link -- and in this tree
#    libSystem is assembled FROM these very libraries. ld64 in turn refuses
#    -undefined dynamic_lookup on a shared-cache-eligible dylib, which is why
#    the flag is spelled out here as well.
#
#  * -Wl,-force_load,<archive> rather than -Wl,-all_load <archive>. This is
#    not cosmetic. clang's driver recognises an input whose basename is
#    libclang_rt.osx.a as "the compiler runtime" and silently REPLACES it with
#    the host CommandLineTools copy -- the argument never reaches ld64, the
#    link succeeds, and the output is the host's runtime with our install
#    name on it. Verified: -v shows the CLT path substituted, the link
#    produces a 4 KB image with 0 exports, and the identical archive under
#    any other name links to 560 symbols. -force_load passes the path through
#    as linker input, so the name cannot be intercepted.
#
# COMPILER_RT_SOURCES is not "every .c under lib/builtins". It is the exact
# x86_64/macOS set, derived from upstream's own lib/builtins/CMakeLists.txt
# source lists, and it differs from a naive glob in four ways that all matter:
#   - GENERIC_TF_SOURCES and x86_80_BIT_SOURCES are included (the 80-bit long
#     double builtins).
#   - filter_builtin_sources() drops the generic C file wherever an
#     x86_64/i386-specific one exists: i386/fp_mode.c and
#     x86_64/floatdidf.c, floatdisf.c, floatdixf.c, floatundidf.S,
#     floatundisf.S, floatundixf.S.
#   - upstream's Darwin-excludes/osx.txt removes seven sources, on the
#     assumption that macOS's own libSystem exports those builtins. ravynOS's
#     does NOT: measured, `nm -g -j libSystem.B.dylib` finds 0 of __addtf3,
#     __divtf3, __multf3, __powitf2, __subtf3, __trampoline_setup. They are
#     therefore KEPT here, and so is apple_versioning.c, whose $ld$hide$os*
#     aliases are the versioning surface this dylib has always carried.
#     atomic.c is kept for the same reason (COMPILER_RT_EXCLUDE_ATOMIC_BUILTIN
#     defaults ON upstream for exactly that libSystem assumption).
#   - os_version_check.c is dropped. It #includes <dispatch/dispatch.h>,
#     which the ravynOS SDK cannot satisfy ("'os/object.h' file not found"),
#     and it contributed no symbol to the reference archive either.
#
# The resulting export trie is identical to the reference dylib's: 529 names,
# byte-for-byte the same set, verified with dyld_info -exports and diffed.

RT_BUILTINS_DIR = ${LLVM_RT}/compiler-rt/lib/builtins

COMPILER_RT_SOURCES = \
	absvdi2.c absvsi2.c absvti2.c adddf3.c addsf3.c addtf3.c \
	addvdi3.c addvsi3.c addvti3.c apple_versioning.c ashldi3.c ashlti3.c \
	ashrdi3.c ashrti3.c atomic.c atomic_flag_clear.c \
	atomic_flag_clear_explicit.c atomic_flag_test_and_set.c \
	atomic_flag_test_and_set_explicit.c atomic_signal_fence.c \
	atomic_thread_fence.c bswapdi2.c bswapsi2.c clear_cache.c clzdi2.c \
	clzsi2.c clzti2.c cmpdi2.c cmpti2.c comparedf2.c comparesf2.c \
	comparetf2.c ctzdi2.c ctzsi2.c ctzti2.c divdc3.c divdf3.c divdi3.c \
	divmoddi4.c divmodsi4.c divmodti4.c divsc3.c divsf3.c divsi3.c divtc3.c \
	divtf3.c divti3.c divxc3.c emutls.c enable_execute_stack.c eprintf.c \
	extenddftf2.c extendhfsf2.c extendhftf2.c extendsfdf2.c extendsftf2.c \
	ffsdi2.c ffssi2.c ffsti2.c fixdfdi.c fixdfsi.c fixdfti.c fixsfdi.c \
	fixsfsi.c fixsfti.c fixtfdi.c fixtfsi.c fixtfti.c fixunsdfdi.c \
	fixunsdfsi.c fixunsdfti.c fixunssfdi.c fixunssfsi.c fixunssfti.c \
	fixunstfdi.c fixunstfsi.c fixunstfti.c fixunsxfdi.c fixunsxfsi.c \
	fixunsxfti.c fixxfdi.c fixxfti.c floatditf.c floatsidf.c floatsisf.c \
	floatsitf.c floattidf.c floattisf.c floattitf.c floattixf.c floatunditf.c \
	floatunsidf.c floatunsisf.c floatunsitf.c floatuntidf.c floatuntisf.c \
	floatuntitf.c floatuntixf.c gcc_personality_v0.c i386/fp_mode.c \
	int_util.c lshrdi3.c lshrti3.c moddi3.c modsi3.c modti3.c muldc3.c \
	muldf3.c muldi3.c mulodi4.c mulosi4.c muloti4.c mulsc3.c mulsf3.c \
	multc3.c multf3.c multi3.c mulvdi3.c mulvsi3.c mulvti3.c mulxc3.c \
	negdf2.c negdi2.c negsf2.c negti2.c negvdi2.c negvsi2.c negvti2.c \
	paritydi2.c paritysi2.c parityti2.c popcountdi2.c popcountsi2.c \
	popcountti2.c powidf2.c powisf2.c powitf2.c powixf2.c subdf3.c \
	subsf3.c subtf3.c subvdi3.c subvsi3.c subvti3.c trampoline_setup.c \
	truncdfbf2.c truncdfhf2.c truncdfsf2.c truncsfbf2.c truncsfhf2.c \
	trunctfdf2.c trunctfhf2.c trunctfsf2.c ucmpdi2.c ucmpti2.c udivdi3.c \
	udivmoddi4.c udivmodsi4.c udivmodti4.c udivsi3.c udivti3.c umoddi3.c \
	umodsi3.c umodti3.c x86_64/floatdidf.c x86_64/floatdisf.c \
	x86_64/floatdixf.c x86_64/floatundidf.S x86_64/floatundisf.S \
	x86_64/floatundixf.S

# The -I below is a search-order fix, not a dependency, and it is load-bearing
# for exactly one file: atomic.c.
#
# atomic.c does `#include <libkern/OSAtomic.h>`. isysroot-cc injects
# `-I${ROOT_SOURCE_DIR}/Kernel/xnu/libkern` into EVERY userspace compile, for
# the components that genuinely want kernel headers, and that -I resolves the
# include to the xnu KERNEL copy. The two disagree on their include guard --
# the SDK's is _OSATOMIC_H_, the kernel's is _OS_OSATOMIC_H -- so the kernel
# copy suppresses nothing in the SDK's and contributes no OSSpinLockLock /
# OSSpinLockUnlock declarations. atomic.c then fails outright:
#   atomic.c:88:40: error: call to undeclared function 'OSSpinLockUnlock'
# and it is the only source in this list that fails.
#
# Neither ${RAVYN_SDKROOT}/usr/include nor naming libkern/libkern fixes it: the
# wrapper appends its own -I after ours, and both tested forms still resolved
# to the kernel header (verified, both ways).
#
# What does work is a directory in the build tree holding a `libkern' symlink
# to the SDK's, placed on the search path ahead of the wrapper's.
# <libkern/OSAtomic.h> then resolves to the SDK's copy for this target while
# every other component keeps resolving it to the kernel's. Verified: with it
# atomic.c compiles, imports _OSSpinLockLock/_OSSpinLockUnlock, and keeps
# ___atomic_* external -- exactly what the reference archive's atomic.o does.
RT_INCDIR = ${.OBJDIR}/compiler_rt/include

${RT_INCDIR}/libkern:
	@mkdir -p ${RT_INCDIR}
	@rm -f ${RT_INCDIR}/libkern
	ln -s ${RAVYN_SDKROOT}/usr/include/libkern ${RT_INCDIR}/libkern

COMPILER_RT_CFLAGS = --sysroot=${RAVYN_SDKROOT} \
	-mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wno-incompatible-sysroot \
	-fPIC -O2 -fvisibility=default -fno-stack-protector \
	-D__DARWIN_UNIX03 -DXNU_PLATFORM_MacOSX \
	-D__DARWIN_ONLY_UNIX_CONFORMANCE=0 \
	-I${RT_INCDIR} \
	-I${RT_BUILTINS_DIR}

COMPILER_RT_TARGET = ${.CURDIR}/libcompiler_rt.dylib
RT_OBJDIR = ${.OBJDIR}/compiler_rt

# Two .for passes, not a modifier chain. The obvious one-liner
# ${SRCS:S/^/${OBJDIR}/rt/:S/.c$/.o/} cannot be written here: bmake reads the
# first ':' as the start of another modifier, so the embedded '/' in the
# replacement is misparsed ("Unknown modifier \":rt/\"") -- verified, and the
# same for the '#' delimiter form. Deriving the list in one loop and emitting
# the dependency rules from a second loop over the same list is the boring
# shape that actually parses.
#
# The object path mirrors the source path, so i386/fp_mode.c and
# x86_64/floatundidf.S land in their own subdirectories rather than beside a
# same-named generic builtin.
COMPILER_RT_OBJS =
.for _crt_src in ${COMPILER_RT_SOURCES}
COMPILER_RT_OBJS += ${RT_OBJDIR}/${_crt_src:S/.c$/.o/:S/.S$/.o/}
.endfor

.for _crt_src in ${COMPILER_RT_SOURCES}
${RT_OBJDIR}/${_crt_src:S/.c$/.o/:S/.S$/.o/}: ${RT_BUILTINS_DIR}/${_crt_src} \
	${RT_INCDIR}/libkern
	@mkdir -p ${RT_OBJDIR}/${_crt_src:H}
	${CC} -c -o ${RT_OBJDIR}/${_crt_src:S/.c$/.o/:S/.S$/.o/} \
	  ${COMPILER_RT_CFLAGS} ${RT_BUILTINS_DIR}/${_crt_src}
.endfor

libcompiler_rt.dylib: ${COMPILER_RT_OBJS}
	mkdir -p ${RAVYN_SDKROOT}/usr/lib/system ${SYSROOT_DIR}/usr/lib/system
	${CC} -shared -dylib -o ${COMPILER_RT_TARGET} \
	  -Wl,-force_load,${COMPILER_RT_OBJS} \
	  -Wl,-install_name,/usr/lib/system/libcompiler_rt.dylib \
	  -Wl,-compatibility_version,1.0.0 -Wl,-current_version,1.0.0 \
	  -mmacosx-version-min=${MACOS_VERSION_MIN} \
	  -Wl,-undefined,dynamic_lookup -Wl,-not_for_dyld_shared_cache
	cp -f ${COMPILER_RT_TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	@cmp -s ${RAVYN_SDKROOT}/usr/lib/system/libcompiler_rt.dylib \
	    ${SYSROOT_DIR}/usr/lib/system/libcompiler_rt.dylib 2>/dev/null || \
	cp -f ${COMPILER_RT_TARGET} ${SYSROOT_DIR}/usr/lib/system/

${.OBJDIR}/lib${LIB}.dylib: ${.OBJDIR}/config.${CpuArch}.normal.h \
lib${LIB}.a libunwind.dylib libcompiler_rt.dylib copyfile ${EXPMEMRSC_O} \
	${LIBCXX_A}
	${CC} -fuse-ld=${LD} -shared -dylib -o ${.TARGET} ${OBJS} \
	  ${EXPMEMRSC_O} ${LDFLAGS}
	${.CURDIR}/xcodescripts/create_dylib_symlinks.sh \
	  ${RAVYN_SDKROOT} install normal
	${.CURDIR}/xcodescripts/create_dylib_symlinks.sh \
	  ${SYSROOT_DIR} install normal
	${.CURDIR}/xcodescripts/create_system_framework.sh \
	  ${SYSROOT_DIR} - - - normal
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/
	mkdir -p \
	  ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/Resources \
	  ${SYSROOT_DIR}/System/Library/Frameworks/System.framework/Versions/B/Resources
	cp -f ${.CURDIR}/Info.plist \
	  ${RAVYN_SDKROOT}/System/Library/Frameworks/System.framework/Versions/B/Resources/
	cp -f ${.CURDIR}/Info.plist \
	  ${SYSROOT_DIR}/System/Library/Frameworks/System.framework/Versions/B/Resources/

lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.dylib

SUBDIR = copyfile removefile libdispatch libsystem_blocks libsystem_kernel \
	libsystem_platform libsystem_malloc libsystem_pthread libsystem_notify \
	libsystem_info libsystem_c libsystem_asl libsystem_trace \
	libsystem_dnssd libxpc liblaunch libsystem_m libsystem_darwin \
	libsystem_coreservices libmacho libsystem_pwdgrp libsystem_termcap \
	#CommonCrypto

# Why libsystem_termcap is wired the same way libsystem_pwdgrp is, and the one
# way it is not.
#
# The same: both are components this tree has to own because the archive that
# used to export the symbols is not reachable. pwdgrp's libinfo.o is
# self-referential onto a framework with no build target (see
# libsystem_info/MISSING_DEPS.md); termcap simply did not exist in ravynOS at
# all -- no <termcap.h> in the SDK and no tget* in any Libsystem archive --
# and BSD/lib/libedit/src/terminal.c calls all six entry points
# unconditionally from terminal_set(), so nothing that uses line editing could
# build without it.
#
# NOT the same, and deliberately: the -reexport flag's POSITION is not
# load-bearing for termcap. It is for pwdgrp, because libsystem_info.dylib
# still exports getpwnam and friends and the first LC_REEXPORT_DYLIB that has
# a symbol owns it (see the long note above). Nothing else in this tree
# exports tgetent/tgetflag/tgetnum/tgetstr/tgoto/tputs, so there is no
# competitor to order against. The flag sits next to pwdgrp's for
# readability, not because a symbol resolves differently either way.
#
# One thing this component does that no other does: its Makefile installs
# <termcap.h> into the SDK's usr/include. That is not an extra, it is the half
# that makes the component usable. libedit's src/sys.h includes config.h into
# every translation unit and config.h has HAVE_TERMCAP_H 1, so
# src/terminal.c:57 does `#include <termcap.h>' -- and terminal.c declares the
# six prototypes itself only under `#if defined(__sun)' (src/terminal.c:71-78),
# so without the header the ravynOS build takes an IMPLICIT `int tgetstr()'
# and truncates the returned pointer to 32 bits on x86_64. That is not a
# warning; it is a wrong library.
#
# See libsystem_termcap/README.md.

# Library versions within libsystem were taken from Monterey System.tbd
# libcache.dylib 83
# libcommonCrypto.dylib 60165
# libcompiler_rt.dylib 101.2
# libcorecrypto.dylib 866.0.10
# libdispatch.dylib 1173.0.3
# libdyld.dylib 732.2
# libkeymgr.dylib 30
# liblaunch.dylib 1738.0.17
# libmacho.dylib 949.0.1
# libquarantine.dylib 110.0.3
# libremovefile.dylib 48
# libsystem_asl.dylib 377.0.1
# libsystem_blocks.dylib 74
# libsystem_c.dylib 1353.0.10
# libsystem_configuration.dylib 1061.0.2
# libsystem_coreservices.dylib 114
# libsystem_dnssd.dylib 1096.0.2
# libsystem_featureflags.dylib 17
# libsystem_kernel.dylib 6153.0.168
# libsystem_m.dylib 3178
# libsystem_malloc.dylib 283
# libsystem_notify.dylib 241
# libsystem_platform.dylib 220
# libsystem_pthread.dylib 416.0.6
# libsystem_sandbox.dylib 1217.0.27
# libsystem_secinit.dylib 62.0.2
# libsystem_trace.dylib 1147.0.3
# libunwind.dylib 35.4
# libxpc.dylib 1738.0.17
# libSystem.B.dylib 1281

.include <bsd.lib.mk>
.include <bsd.subdir.mk>
