SUBDIR =
SLF = /System/Library/Frameworks
SYSPRIVHDR = System.framework/Versions/B/PrivateHeaders
XNU = ${ROOT_SOURCE_DIR}/Kernel/xnu
MACH_DEFS != echo ${XNU}/osfmk/mach/*.defs

.PATH: ${XNU}/libsyscall
.PATH: ${XNU}/libsyscall/wrappers
.PATH: ${XNU}/libsyscall/custom
.PATH: ${XNU}/libsyscall/os
.PATH: ${XNU}/libsyscall/mach

MK_WERROR = no

LIB = system_kernel

CFLAGS.os_packet.o = -fno-builtin
CFLAGS.os_channel.o = -fno-builtin
CFLAGS.os_nexus.o = -fno-builtin
# seems to be a version at Kernel/xnu/bsd/netinet/cpu_in_cksum_gen.c
CFLAGS.cpu_copy_in_cksum_gen.o = -fno-builtin
CFLAGS.cpu_in_cksum_gen.o = -fno-builtin
CFLAGS.os_channel_event.o = -fno-builtin

# DECISION: the SDK mach tree wins WHOLESALE. Do not put -I${XNU}/osfmk
# ahead of it. The two trees are different xnu generations and neither is a
# superset:
#   SDK    usr/include/mach  coherent, has mach/task.h (osfmk has none) and
#                               the suid_cred_* types; lacks mach_msg_aux_header_t
#   osfmk  partial mirror    has mach_msg_aux_header_t; lacks suid_cred_*;
#                               missing whole headers the SDK carries
# Mixing them per-header is the defect itself. Commit 064733a put osfmk first
# to fix mach_msg_aux_header_t; measurement later showed that only changed
# WHICH mix you get, and it broke suid_cred_*. That ordering is reverted here.
# mach_msg_aux_header_t is now SOURCED into the SDK tree from
# Kernel/xnu/osfmk/mach/message.h:626-629 -- see Libraries/check_sdk_stubs.sh
# and tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 4 and 11.
# ---------------------------------------------------------------------------
# TRIED AND INERT -- recorded so nobody repeats it. -I${.OBJDIR}/mig_hdr/
# include/mach was moved to the FRONT of CFLAGS, to let this build's own
# mig-generated mach_host.h (which declares host_get_io_main) outrank the SDK's
# Catalina one. It changed nothing, and the reason is not obvious:
#   -I.../mig_hdr/include/mach points AT the mach directory, so
# `#include <mach/mach_host.h>` looks for .../mig_hdr/include/mach/mach/
# mach_host.h, which does not exist. The -I that would work is the PARENT,
# ${.OBJDIR}/mig_hdr/include -- and isysroot-cc deliberately overlays exactly
# that one and strips its mach/ subdirectory (its case list has
# `*/libsystem_kernel/mig_hdr/include`), so the generated tree is unreachable
# from this Makefile as written. Confirmed with clang -H on the real captured
# invocation, which is the only evidence that settles it:
#   . <SDK>/usr/include/mach/mach_host.h
# Reversing the -I order changes nothing either; usr/include wins regardless.
#
# The fix that actually works is in the SDK instead, and it is bounded:
# host_get_io_main and host_get_io_master are the SAME Mach trap. Both headers
# put it at 205 ({ "host_get_io_master", 205 } against __DeclareSendRpc(205,
# "host_get_io_main")), both requests are an empty mach_msg_header_t, and both
# replies carry one mach_msg_port_descriptor_t. The two generations differ only
# in the spelling. See tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md sec. 22.

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
	-I${XNU}/bsd -I${XNU}/libsyscall/mach -I${.OBJDIR} \
	-I${XNU}/libsyscall/os \
	-I${XNU}/libsyscall/wrappers/spawn \
	-I${ROOT_SOURCE_DIR}/Frameworks \
	-I${XNU}/libsyscall/wrappers \
	-I${XNU}/libsyscall/wrappers/string \
	-I${XNU}/libsyscall/wrappers/libproc \
	-I${XNU}/libsyscall \
	-I${XNU}/libsyscall/mach \
	-I${ROOT_BINARY_DIR}/${CpuArch} \
	-I${RAVYN_SDKROOT}/usr/local/include \
	-I${RAVYN_SDKROOT}/usr/local/include/kernel \
	-I${RAVYN_SDKROOT}${SLF}/${SYSPRIVHDR} \
	-I${.OBJDIR}/internal_hdr/include \
	-I${.OBJDIR}/internal_hdr/include/mach \
	-I${.OBJDIR}/${CpuArch} \
	-I${.OBJDIR}/mig_hdr/include/mach \
	-I${.OBJDIR}/mig_hdr/include \
	-I${.OBJDIR}/mig_hdr/include/servers ${CFLAGS.${.TARGET:T}}

ACFLAGS = -x assembler-with-cpp ${CFLAGS}

# cancelable/open.c replaces legacy/open.c. legacy/open.c does not exist in
# this xnu snapshot: the 20 files in Kernel/xnu/libsyscall/wrappers/legacy/ do
# not include it, and the only open.c under libsyscall is wrappers/cancelable/
# open.c. bmake aborts the entire stage on a missing SRCS entry, so the stale
# name blocked everything downstream of it. Nothing is substituted -- if the
# legacy open(2) entry point is genuinely required, it must be written, not
# aliased. (Comment lives here, not inside the SRCS block: bmake cannot parse a
# comment on a backslash-continued line.)
#
# Full audit: all 130 SRCS entries resolve against .PATH. See
# tools/bootlab/LIBSYSTEM-KERNEL-BUILD-NOTES.md.
# legacy syscalls
SRCS = \
	legacy/accept.c \
	legacy/bind.c \
	legacy/getattrlist.c \
	legacy/getpeername.c \
	legacy/getsockname.c \
	legacy/lchown.c \
	legacy/listen.c \
	legacy/recvfrom.c \
	legacy/recvmsg.c \
	legacy/sendmsg.c \
	legacy/sendto.c \
	legacy/setattrlist.c \
	legacy/socketpair.c \
	legacy/connect.c \
	legacy/mprotect.c \
	legacy/msync.c \
	cancelable/open.c \
	legacy/select-pre1050.c \
	legacy/select.c \
	legacy/getaudit.c

# unix03 syscalls
SRCS += \
	unix03/chmod.c \
	unix03/fchmod.c \
	unix03/getrlimit.c \
	unix03/mmap.c \
	unix03/munmap.c \
	unix03/setrlimit.c

# cancelable syscalls
SRCS += \
	cancelable/pselect-darwinext-cancel.c \
	cancelable/pselect-darwinext.c \
	cancelable/fcntl.c \
	cancelable/fcntl-cancel.c \
	cancelable/select.c \
	cancelable/select-cancel.c \
	cancelable/sigsuspend.c \
	cancelable/sigsuspend-cancel.c

# custom syscall wrappers
SRCS += \
	custom/errno.c

# These Skywalk sources are all empty in the public xnu
SRCS += \
	skywalk/os_packet.c \
	skywalk/cpu_in_cksum.s \
	skywalk/os_channel.c \
	skywalk/os_nexus.c \
	skywalk/os_channel_event.c \
	skywalk/cpu_copy_in_cksum.s \
	skywalk/cpu_copy_in_cksum_gen.c \
	skywalk/cpu_in_cksum_gen.c

# General wrappers
# system-version-compat{,-support}.c define the two data pointers and the two
# functions behind _system_version_compat_{open_shim,check_path_suffix}.  Their
# consumers are already in this component -- open-base.c and _libkernel_init.c
# are both compiled here, and nm -u on libkernel.a shows their members
# (open.o, _libkernel_init.o) referencing all five of
#   __system_version_compat_{open_shim,check_path_suffix}   (the functions)
#   _system_version_compat_{open_shim,check_path_suffix}
#   _system_version_compat_mode                            (the pointers)
# while nothing in the tree defined any of them: these two files were in no
# SRCS list anywhere in the repo, and no .o for either existed on disk.  That
# is why the MH_DYLINKER link surfaced the two POINTERS as imports even though
# the DYLib could not have satisfied them either -- the providers were simply
# never compiled.  Same shape as the _libc_funcptr.o case: the code exists, it
# was just left out of the archive that should contain it.
#
# Both are needed together, and the set closes exactly.  Compiling just one
# would trade two resolved imports for two new ones: _libkernel_init.c assigns
# the functions into the pointers.  Measured with the component's own flags
# (-Wno-int-conversion, which this Makefile uses throughout), the two files
# compile clean and define 5 of the 5 referenced symbols, leaving 0 unresolved.
#
# They stay visibility("hidden") as upstream marks them, so packaging them into
# libkernel.a -- and therefore into libsystem_kernel.dylib -- exports nothing
# new; they are only resolvable inside a static link, which is what the
# dylinker's -Wl,-static link is.
SRCS += \
	mach_approximate_time.c \
	mach_continuous_time.c \
	mach_absolute_time.s \
	mach_timebase_info.c \
	mach_bridge_remote_time.c \
	mach_get_times.c \
	mach_boottime.c \
	libproc/libproc.c \
	libproc/proc_listpidspath.c \
	proc.c \
	spawn/posix_spawn.c \
	terminate_with_reason.c \
	kill.c \
	ioctl.c \
	rename.c \
	clonefile.c \
	unlinkat.c \
	renameat.c \
	renamex.c \
	unlink.c \
	rmdir.c \
	carbon_delete.c \
	utimensat.c \
	setpriority.c \
	guarded_open_dprotected_np.c \
	quota_obsolete.c \
	getiopolicy_np.c \
	gethostuuid.c \
	thread_register_state.c \
	stackshot.c \
	sfi.c \
	posix_sem_obsolete.c \
	pid_shutdown_networking.c \
	coalition.c \
	fs_snapshot.c \
	work_interval.c \
	remove-counter.c \
	open_dprotected_np.c \
	varargs_wrappers.s \
	persona.c \
	guarded_open_np.c \
	kdebug_trace.c \
	reboot.c \
	csr.c \
	init_cpu_capabilities.c \
	__commpage_gettimeofday.c \
	__get_cpu_capabilities.s \
	_libkernel_init.c \
	system-version-compat-support.c \
	system-version-compat.c \
	string/strlen.c \
	string/index.c \
	string/strcmp.c \
	string/memset.c \
	string/memcpy.c \
	string/strsep.c \
	string/strcpy.c \
	string/strlcpy.c \
	alloc_once.c \
	log_data.c

# mach traps
SRCS += \
	port_descriptions.c \
	clock_sleep.c \
	error_codes.c \
	exc_catcher_state_identity.c \
	exc_catcher_state.c \
	exc_catcher.c \
	fprintf_stderr.c \
	host.c \
	mach_error_string.c \
	mach_error.c \
	mach_init.c \
	mach_msg.c \
	mach_traps.s \
	mig_allocate.c \
	mig_deallocate.c \
	mig_reply_setup.c \
	mig_reply_port.c \
	mig_strncpy.c \
	ms_thread_switch.c \
	panic.c \
	port_obj.c \
	semaphore.c \
	slot_name.c \
	string.c \
	mach_legacy.c \
	mach_right.c \
	thread_act.c \
	mach_port.c \
	mach_vm.c
#OBJS = ${SRCS:S/.c$/.o/:S/.s$/.o/}

LDFLAGS = \
	-umbrella System -mmacos-version-min=${MACOS_VERSION_MIN} \
	-L${RAVYN_SDKROOT}/usr/lib/system \
	-Wl,-install_name,/usr/lib/system/libsystem_kernel.dylib \
	-Wl,-current_version,6153.0.168 -Wl,-compatibility_version,1.0.0

MIG_FLAGS = -novouchers -arch ${CpuArch} -cc ${MIGCC} \
	-I${RAVYN_SDKROOT}/usr/include -I${RAVYN_SDKROOT}/usr/local/include \
	-mmacos-version-min=${MACOS_VERSION_MIN} -fno-stack-check \
	-fno-stack-protector

all: lib${LIB}.dylib
lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.dylib

copy_defs: ${MACH_DEFS}
	mkdir -p ${RAVYN_SDKROOT}${SLF}/${SYSPRIVHDR}/mach
	cp -f ${MACH_DEFS} ${RAVYN_SDKROOT}${SLF}/${SYSPRIVHDR}/mach/

# Generate syscall stubs - 24614EF311E7C98600E78584 libsyscalls.a
${.OBJDIR}/libsyscalls.a: ${XNU}/bsd/kern/syscalls.master copy_defs
	mkdir -p ${.OBJDIR}/sys
	env SDKROOT=${RAVYN_SDKROOT} BUILT_PRODUCTS_DIR=${.OBJDIR} \
	DEVELOPER_DIR=${ROOT_BINARY_DIR}/Developer \
	PATH=${TOOLS}:${PATH} ARCHS=${CpuArch} SRCROOT=${XNU}/libsyscall \
	OBJROOT=${.OBJDIR} \
	${XNU}/libsyscall/xcodescripts/create-syscalls.pl \
	  ${XNU}/bsd/kern/syscalls.master ${XNU}/libsyscall/custom \
	  ${XNU}/libsyscall/Platforms MacOSX ${.OBJDIR}/sys
	env SDKROOT=${RAVYN_SDKROOT} SDK_INSTALL_HEADERS_ROOT=. \
	BUILT_PRODUCTS_DIR=${.OBJDIR} \
	DEVELOPER_DIR=${ROOT_BINARY_DIR}/Developer PATH=${TOOLS}:${PATH} \
	ARCHS=${CpuArch} SRCROOT=${XNU}/libsyscall OBJROOT=${.OBJDIR} \
	CC=${CC} LIBTOOL=${LIBTOOL} \
	${XNU}/libsyscall/xcodescripts/compile-syscalls.pl \
	  ${.OBJDIR}/sys/stubs.list ${.TARGET}

${.OBJDIR}/libmach.a: ${MACH_DEFS}
	mkdir -p ${.OBJDIR}/obj/mig_hdr/include/mach \
	  ${.OBJDIR}/obj/mig_hdr/include/servers \
	  ${.OBJDIR}/obj/internal_hdr/include/mach \
	  ${.OBJDIR}/${CpuArch}
	SDKROOT=${RAVYN_SDKROOT} PLATFORM_NAME=MacOSX ARCHS=${CpuArch} \
	SRCROOT=${XNU}/libsyscall OBJROOT=${.OBJDIR}/obj \
	BUILT_PRODUCTS_DIR=${.OBJDIR} \
	DEVELOPER_DIR=${ROOT_BINARY_DIR}/Developer PATH=${TOOLS}:${PATH} \
	CC=${CC} CFLAGS="${CFLAGS}" ${XNU}/libsyscall/xcodescripts/mach_install_mig.sh
	# Two sets of generated stubs, and which interfaces each one owns is
	# decided in mach_install_mig.sh, not here:
	#   obj/         the public pass (LIBSYSCALL_INTERFACE) for the twelve
	#                interfaces libsyscall does not implement by hand --
	#                mach_host, host_priv, host_security, clock, clock_priv,
	#                clock_reply, exc, processor, processor_set,
	#                memory_entry, mach_eventlink, netname, mach_voucher.
	#   obj/internal the internal pass for the five it does -- mach_port,
	#                mach_vm, task, thread_act, vm_map. Those carry the
	#                _kernelrpc_* stubs, which is what libsyscall's own trap
	#                wrappers in mach_port.c and host.c call.
	# The public .c for those same five is NOT linked. `ar rcs` keys archive
	# members by name, so with both sets present each of the five appears
	# twice in libkernel.a, and the public stubs also collide with the
	# hand-written mach_vm.c and thread_act.c. Measured on the real link:
	# 187 duplicate symbols, 168 same-name public-vs-internal and 19
	# generated-vs-hand-written.
	set -e; objs=""; \
	for d in ${.OBJDIR}/obj ${.OBJDIR}/obj/internal; do \
	    [ -d $$d ] || continue; \
	    for f in $$d/*User.c; do \
		${CC} ${CFLAGS} -o $$f.o -c $$f; \
		objs="$$objs $$f.o"; \
	    done; \
	done; \
	${AR} rcs ${.TARGET} $$objs

.for def in thread_act.defs mach_port.defs vm_map.defs mach_vm.defs
${.OBJDIR}/mach/${def:R}_internal.h: ${XNU}/libsyscall/mach/${def}
	mkdir -p ${.OBJDIR}/mach
	${MIG} ${MIG_FLAGS} -header ${.TARGET} ${.ALLSRC}

${.OBJDIR}/lib${LIB}.a: ${.OBJDIR}/mach/${def:R}_internal.h
.endfor

lib${LIB}.a: ${.OBJDIR}/libmach.a ${.OBJDIR}/libsyscalls.a

${.OBJDIR}/_libc_funcptr.o: ${XNU}/libsyscall/wrappers/_libc_funcptr.c
	${CC} -c ${.ALLSRC} -o ${.TARGET} ${CFLAGS}

${.OBJDIR}/lib${LIB}.dylib: ${.OBJDIR}/_libc_funcptr.o lib${LIB}.a
	mkdir -p ${RAVYN_SDKROOT}/usr/local/lib/kernel
	# _libc_funcptr.o must be INSIDE libkernel.a, not beside it.  It defines
	# the voucher dispatch shims (_voucher_mach_msg_fill_aux and
	# _voucher_mach_msg_fill_aux_supported) and it was force_loaded into
	# libsystem_kernel.dylib straight from the loose object, so the archive
	# never carried them.  Measured: the dylib exported both, libkernel.a
	# exported 0, and a whole-SDK census found those two symbols in exactly
	# one image -- libsystem_kernel.dylib -- and in no .a at all.  The
	# MH_DYLINKER tool link is -Wl,-static, so it can only take archives, and
	# it already links -L${RAVYN_SDKROOT}/usr/local/lib/kernel -lkernel: the
	# archive was present and on the line the whole time, just missing the
	# two members.  Packaging it here is a build change and invents no ABI.
	# llvm-libtool-darwin -static accepts a bare .o alongside the .a inputs
	# (verified), so one command still produces the whole archive.
	${TOOLS}/llvm-libtool-darwin -static -no_warning_for_no_symbols \
	  -o ${.OBJDIR}/libkernel.a ${.OBJDIR}/lib${LIB}.a \
		${.OBJDIR}/libmach.a ${.OBJDIR}/libsyscalls.a \
		${.OBJDIR}/_libc_funcptr.o
	${CC} -shared -dylib -fuse-ld=${LD} -nostdlib -o ${.TARGET} ${LDFLAGS} \
	  -Wl,-force_load,${.OBJDIR}/libkernel.a \
	  -Wl,-install_name,/usr/lib/system/libsystem_kernel.dylib \
	  -Wl,-current_version,6153.0.168 \
	  -Wl,-compatibility_version,1.0.0 \
	  -L${RAVYN_SDKROOT}/usr/lib/system -lsystem_c -ldyld
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/system/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/system/
	cp -f ${.OBJDIR}/libkernel.a \
	  ${RAVYN_SDKROOT}/usr/local/lib/kernel/libkernel.a

.include <bsd.lib.mk>
