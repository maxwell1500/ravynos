# libsystem_kernel, STATIC-LINK variant of mach_init.
#
# This is a SEPARATE build, in its own directory, and it is the only place
# the static mach_init variant is compiled. The parent directory builds the
# shared libsystem_kernel.dylib that dyld loads; this one builds an archive
# holding a single object -- the local mach_init.c -- which
# tools/bootlab/link-static.sh lists BEFORE -lsystem_kernel so that this
# variant wins and the parent's mach_init.o is never pulled.
#
# Why a variant is needed at all
# ------------------------------
# Upstream mach_init_doit() ends with `_pthread_set_self(0)`. That is safe
# upstream because mach_init() is a PRE-libpthread initializer: a dynamic
# program reaches it through libSystem_initializer() before libpthread is
# loaded, where _pthread_set_self is still Libc's no-op function-pointer
# stub. A static link has libpthread_static.a present simultaneously with
# libsystem_kernel.a, and ld64 cannot express "before", so libpthread's
# strong definition wins and dereferences the literal 0.
#
# The variant drops that one call. It is redundant here: __pthread_static_init
# (called first by ravyn_static_startup) already calls _pthread_set_self with
# the real main-thread pointer. See the comment at the divergence site in
# static/mach_init.c, and do NOT restore the line.
#
# Nothing else differs: static/mach_init.c is a copy of
# Kernel/xnu/libsyscall/mach/mach_init.c with that single call removed, and
# it publishes the same four page-size globals by reading the kernel comm
# page, exactly as upstream does. No value is hardcoded.
#
# Kernel/xnu is NOT modified. If you find yourself wanting to edit
# mach_init.c there, stop -- that is a different change.
SUBDIR =
LIB = system_kernel_static

SLF = /System/Library/Frameworks
SYSPRIVHDR = System.framework/Versions/B/PrivateHeaders
XNU = ${ROOT_SOURCE_DIR}/Kernel/xnu

# The parent's generated headers (mig_hdr) live in the PARENT's object dir.
PARENT_OBJDIR = ${.CURDIR:H}/obj

SRCS = mach_init.c

MK_WERROR = no

# Identical to the parent's CFLAGS except that ${.OBJDIR} is this directory
# and the generated-header paths point at the parent's object directory, so
# the variant sees the same headers the parent does.
CFLAGS = \
	--sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-Wno-implicit-int -Wno-implicit-function-declaration \
	-Wno-int-conversion -Wno-incompatible-sysroot \
	-Wno-nullability-completeness -no-cpp-precomp -nostdlib \
	-fdollars-in-identifiers -fno-common -fno-stack-protector \
	-fno-stack-check -momit-leaf-frame-pointer \
	-D__DARWIN_VERS_1050 -DLIBSYSCALL_INTERFACE -DSYSCALL_PRE1050 \
	-DNO_SYSCALL_LEGACY -DCF_OPEN_SOURCE -DCF_EXCLUDE_CSTD_HEADERS \
	-DDEBUG -D_FORTIFY_SOURCE=0 -DDARWIN_C_SOURCE=DARWIN_C_FULL \
	-DPRIVATE -DTARGET_OS_BRIDGE=0 -D__DARWIN_UNIX03 \
	-I${XNU}/bsd -I${XNU}/libsyscall/mach -I${.CURDIR} \
	-I${XNU}/libsyscall/os \
	-I${XNU}/libsyscall/wrappers/spawn \
	-I${ROOT_SOURCE_DIR}/Frameworks \
	-I${XNU}/libsyscall/wrappers \
	-I${XNU}/libsyscall/wrappers/string \
	-I${XNU}/libsyscall/wrappers/libproc \
	-I${XNU}/libsyscall \
	-I${ROOT_BINARY_DIR}/${CpuArch} \
	-I${RAVYN_SDKROOT}/usr/local/include \
	-I${RAVYN_SDKROOT}/usr/local/include/kernel \
	-I${RAVYN_SDKROOT}${SLF}/${SYSPRIVHDR} \
	-I${PARENT_OBJDIR}/internal_hdr/include \
	-I${PARENT_OBJDIR}/internal_hdr/include/mach \
	-I${PARENT_OBJDIR}/${CpuArch} \
	-I${PARENT_OBJDIR}/mig_hdr/include/mach \
	-I${PARENT_OBJDIR}/mig_hdr/include \
	-I${PARENT_OBJDIR}/mig_hdr/include/servers

all: lib${LIB}.a

.include <bsd.lib.mk>
