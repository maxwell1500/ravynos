#!/bin/sh -xe
#
# Copyright (c) 2010 Apple Inc. All rights reserved.
#
# @APPLE_OSREFERENCE_LICENSE_HEADER_START@
# 
# This file contains Original Code and/or Modifications of Original Code
# as defined in and that are subject to the Apple Public Source License
# Version 2.0 (the 'License'). You may not use this file except in
# compliance with the License. The rights granted to you under the License
# may not be used to create, or enable the creation or redistribution of,
# unlawful or unlicensed copies of an Apple operating system, or to
# circumvent, violate, or enable the circumvention or violation of, any
# terms of an Apple operating system software license agreement.
# 
# Please obtain a copy of the License at
# http://www.opensource.apple.com/apsl/ and read it before using this file.
# 
# The Original Code and all software distributed under the License are
# distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
# EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
# INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
# Please see the License for the specific language governing rights and
# limitations under the License.
# 
# @APPLE_OSREFERENCE_LICENSE_HEADER_END@
#

# build inside OBJROOT
cd $OBJROOT

MIG=`xcrun -sdk "$SDKROOT" -find mig`
# Honour CC from the environment if the caller set one, for the same reason as
# compile-syscalls.pl: hardcoding `xcrun -find cc` made these the only TUs in
# the Libsystem build that bypassed tools/bootlab/isysroot-cc. The generated
# *User.c files are compiled by the Makefile with ${CC}, but mig itself is
# invoked with -cc ${MIGCC}, and MIGCC is exported below, so an unwrapped
# value here silently reintroduces the same asymmetry.
MIGCC=${CC:-`xcrun -sdk "$SDKROOT" -find cc`}
export MIGCC
[ -n "$DRIVERKITROOT" ] && MIG_DRIVERKIT_DEFINES="-DDRIVERKIT"
MIG_DEFINES="-DLIBSYSCALL_INTERFACE $MIG_DRIVERKIT_DEFINES"
MIG_PRIVATE_DEFINES="-DPRIVATE"

# ---------------------------------------------------------------------------
# Per-defs override of LIBSYSCALL_INTERFACE.
#
# Two of the MIGS carry their own defs-level selection for the routines
# libsyscall implements BY HAND, and $MIG_DEFINES was picking the wrong side of
# it for both files. Measured with the real mig, same flags, only the define
# differing (symbol sets of the generated *User.c, `awk '/^mig_external/'):
#
#   defs             with -DLIBSYSCALL_INTERFACE   with ...=0
#   mach_host.defs   27 stubs                     24 stubs
#     lost:  host_get_atm_diagnostic_flag, host_get_multiuser_config_flags,
#            host_check_multiuser_mode, host_create_mach_voucher
#     gained: _kernelrpc_host_create_mach_voucher
#   mach_voucher.defs  5 stubs                    5 stubs
#     lost:  mach_voucher_extract_attr_recipe
#     gained: _kernelrpc_mach_voucher_extract_attr_recipe
#
# This is the defs files' own mechanism, not an exclusion invented here.
# osfmk/mach/mach_host.defs:319-357 guards those three comm-page readers with
# `#if !KERNEL && LIBSYSCALL_INTERFACE / routine ... / #else / skip;`, and
# mach_host.defs:283-289 plus mach_voucher.defs:45-51 offer either the public
# routine or its `_kernelrpc_` twin. They are written for exactly the two
# implementations this library ships:
#
#   - the three comm-page readers are `skip;`ped because mach/host.c:37,45,58
#     answer from the comm page with no kernel round trip;
#   - host_create_mach_voucher and mach_voucher_extract_attr_recipe are
#     hand-written trap wrappers (host.c:84, mach_port.c:736) that fall back to
#     the _kernelrpc_ MIG stub on MACH_SEND_INVALID_DEST, so those two
#     `_kernelrpc_` stubs MUST be generated or the wrappers dangle.
#
# With the define set, mig generated the public name for all five, so ld64 saw
# two strong definitions of each; and it generated NO `_kernelrpc_` variant, so
# `_kernelrpc_host_create_mach_voucher` and
# `_kernelrpc_mach_voucher_extract_attr_recipe` were undefined in every archive
# (verified with `nm -A` over libmach.a, libsystem_kernel.a and libsyscalls.a:
# 0 definitions, 1 undefined reference each from host.o and mach_port.o).
#
# The override is per-file on purpose. Flipping it globally is wrong and was
# measured, not assumed: mach_port.defs:71-73 does `UserPrefix _kernelrpc_` when
# !LIBSYSCALL_INTERFACE, so a global flip renames 43 of mach_port.defs' stubs
# (mach_port_allocate, mach_port_deallocate, ...), 3 of task.defs', 3 of
# thread_act.defs' and 5 of vm_map.defs', and changes the on-the-wire type of
# mach_port_get_context/construct/destruct/guard from mach_port_context_t to
# mach_vm_address_t (mach_port.defs:523-620).
# ---------------------------------------------------------------------------
mig_defines_for() {
	case "$1" in
	mach_host.defs|mach_voucher.defs)
		echo "-DLIBSYSCALL_INTERFACE=0 $MIG_DRIVERKIT_DEFINES"
		;;
	*)
		echo "$MIG_DEFINES"
		;;
	esac
}

MIG_HEADER_OBJ="$OBJROOT/mig_hdr/include/mach"
MIG_HEADER_DST="$BUILT_PRODUCTS_DIR/mig_hdr/include/mach"
MIG_PRIVATE_HEADER_DST="$BUILT_PRODUCTS_DIR/mig_hdr/local/include/mach"
SERVER_HEADER_DST="$BUILT_PRODUCTS_DIR/mig_hdr/include/servers"
MACH_HEADER_DST="$BUILT_PRODUCTS_DIR/mig_hdr/include/mach"
MACH_PRIVATE_HEADER_DST="$BUILT_PRODUCTS_DIR/mig_hdr/local/include/mach"
MIG_INTERNAL_HEADER_DST="$BUILT_PRODUCTS_DIR/internal_hdr/include/mach"
MIG_INCFLAGS="-I${SRCROOT}/../osfmk"
SRC="$SRCROOT/mach"
FILTER_MIG="$SRCROOT/xcodescripts/filter_mig.awk"

# MACHINE_ARCH *really* needs to be a 32-bit arch to generate vm_map_internal.h correctly, even if there are no 32-bit targets.
# thread_state_t *really* needs to pick up arm64 over intel because it has a larger struct type.
case "$ARCHS" in
*arm64*)
    MACHINE_ARCH=armv7
    ;;
*x86_64*)
    MACHINE_ARCH=i386
    ;;
*)
    MACHINE_ARCH=`echo $ARCHS | cut -d' ' -f 1`
    ;;
esac

ASROOT=""
if [ `whoami` = "root" ]; then
	ASROOT="-o 0"
fi

# These are covered by ../../osfmk/mach/mach.modulemap.
MIGS="clock.defs
	clock_priv.defs
	clock_reply.defs
	exc.defs
	host_priv.defs
	host_security.defs
	mach_eventlink.defs
	mach_host.defs
	mach_port.defs
	mach_voucher.defs
	memory_entry.defs
	processor.defs
	processor_set.defs
	task.defs
	thread_act.defs
	vm_map.defs"

# These are covered by ../../osfmk/mach/mach_private.modulemap.
MIGS_PRIVATE=""

MIGS_DUAL_PUBLIC_PRIVATE=""

MIGS_PRIVATE_PLATFORMS="iphoneos iphonesimulator tvos tvsimulator appletvos appletvsimulator watchos watchsimulator bridgeos bridgesimulator iphoneosnano iphonenanosimulator"

if ( echo $MIGS_PRIVATE_PLATFORMS | grep -wFq "${PLATFORM_NAME}" )
then
	MIGS_PRIVATE="mach_vm.defs"
else
	MIGS="$MIGS mach_vm.defs"
fi

MIGS_INTERNAL="mach_port.defs
	mach_vm.defs
	task.defs
	thread_act.defs
	vm_map.defs"

SERVER_HDRS="key_defs.h
	ls_defs.h
	netname_defs.h
	nm_defs.h"

# These are covered by ../../osfmk/mach/mach.modulemap.
MACH_HDRS="mach.h
	mach_error.h
	mach_init.h
	mach_interface.h
	mach_right.h
	port_obj.h
	sync.h
	vm_task.h
	vm_page_size.h
	thread_state.h"

# These are covered by ../../osfmk/mach/mach_private.modulemap.
MACH_PRIVATE_HDRS="port_descriptions.h
	mach_right_private.h
	mach_sync_ipc.h"

MIG_FILTER_TEMPLATE="add_attributes_to_mig.txt"

# install /usr/include/server headers 
mkdir -p $SERVER_HEADER_DST
for hdr in $SERVER_HDRS; do
	install $ASROOT -c -m 444 $SRC/servers/$hdr $SERVER_HEADER_DST
done

# install /usr/include/mach headers
mkdir -p $MACH_HEADER_DST
for hdr in $MACH_HDRS; do
	install $ASROOT -c -m 444 $SRC/mach/$hdr $MACH_HEADER_DST
done

# install /usr/local/include/mach headers
mkdir -p $MACH_PRIVATE_HEADER_DST
for hdr in $MACH_PRIVATE_HDRS; do
	install $ASROOT -c -m 444 $SRC/mach/$hdr $MACH_PRIVATE_HEADER_DST
done

# special case because we only have one to do here
$MIG -novouchers -arch $MACHINE_ARCH -cc $MIGCC -header "$SERVER_HEADER_DST/netname.h" $MIG_INCFLAGS $SRC/servers/netname.defs

# install /usr/include/mach mig headers

mkdir -p $MIG_HEADER_DST
mkdir -p $MIG_HEADER_OBJ

for mig in $MIGS $MIGS_DUAL_PUBLIC_PRIVATE; do
	MIG_NAME=`basename $mig .defs`
	MIG_DEFS=`mig_defines_for $mig`
	$MIG -novouchers -arch $MACHINE_ARCH -cc $MIGCC -header "$MIG_HEADER_OBJ/$MIG_NAME.h" $MIG_DEFS $MIG_INCFLAGS $SRC/$mig
        $FILTER_MIG $SRC/$MIG_FILTER_TEMPLATE $MIG_HEADER_OBJ/$MIG_NAME.h > $MIG_HEADER_OBJ/$MIG_NAME.tmp.h
        mv $MIG_HEADER_OBJ/$MIG_NAME.tmp.h $MIG_HEADER_OBJ/$MIG_NAME.h
	install $ASROOT -c -m 444 $MIG_HEADER_OBJ/$MIG_NAME.h $MIG_HEADER_DST/$MIG_NAME.h
done

mkdir -p $MIG_PRIVATE_HEADER_DST

for mig in $MIGS_PRIVATE $MIGS_DUAL_PUBLIC_PRIVATE; do
	MIG_NAME=`basename $mig .defs`
	MIG_DEFS=`mig_defines_for $mig`
	$MIG -novouchers -arch $MACHINE_ARCH -cc $MIGCC -header "$MIG_PRIVATE_HEADER_DST/$MIG_NAME.h" $MIG_DEFS $MIG_PRIVATE_DEFINES $MIG_INCFLAGS $SRC/$mig
	if [ ! -e "$MIG_HEADER_DST/$MIG_NAME.h" ]; then
		echo "#error $MIG_NAME.h unsupported." > "$MIG_HEADER_DST/$MIG_NAME.h"
	fi
done


# special headers used just for building Libsyscall
# Note: not including -DLIBSYSCALL_INTERFACE to mig so we'll get the proper
#  'internal' version of the headers being built
#
# ...and, unlike the public pass above, its generated .c files are kept rather
# than discarded: the `_kernelrpc_*` stubs in them are what libsyscall's own
# trap wrappers call (mach/mach_port.c, mach/host.c).
#
# mig names its *User.c and *Server.c after the .defs FILE, NOT after the
# -header path. Verified directly: `mig -header .../mach_port_internal.h
# .../mach_port.defs` writes mach_portUser.c, not mach_port_internalUser.c.
# So before this pass was given its own OBJROOT it overwrote the public
# mach_portUser.c, taskUser.c, thread_actUser.c, vm_mapUser.c and
# mach_vmUser.c in place, and won because the public pass runs first. That was
# the right answer reached by directory order, which is not an answer.
mkdir -p $MIG_INTERNAL_HEADER_DST

# The public pass above also emitted *User.c/*Server.c for the five interfaces
# in MIGS_INTERNAL. Those five are exactly the ones libsyscall implements by
# hand -- mach_port.c, mach_vm.c, thread_act.c, port_descriptions.c -- so
# linking the public stubs for them is a collision, not a duplicate: 187 of
# them, measured on the real link, and every one falls into exactly two
# classes, both of which disappear when the public .c for these five is not
# linked:
#
#   168  public vs internal, same member basename -- taskUser.c.o,
#        mach_portUser.c.o, thread_actUser.c.o, vm_mapUser.c.o and
#        mach_vmUser.c.o each appear TWICE in libkernel.a (archive indices
#        147/152, 140/150, 148/153, 149/154, 141/151), because `ar rcs`
#        keys members by name and both passes use the .defs basename.
#    19  public generated vs hand-written: mach_vm.o against the public
#        vm_mapUser.c.o and mach_vmUser.c.o (_vm_read, _vm_map,
#        _vm_deallocate, 8 each) and thread_act.o against the public
#        thread_actUser.c.o (3).
#
# The public .c for these five is therefore not wanted at all, which is what
# the section header below already says ("special headers used just for
# building Libsyscall"). Before the internal pass was given its own OBJROOT
# the answer was correct by accident: it wrote the same filenames into the
# same directory and won. This makes it explicit instead of positional.
for mig in $MIGS_INTERNAL; do
	MIG_NAME=`basename $mig .defs`
	rm -f "$OBJROOT/${MIG_NAME}User.c" "$OBJROOT/${MIG_NAME}Server.c"
done
MIG_INTERNAL_OBJROOT="$OBJROOT/internal"
mkdir -p "$MIG_INTERNAL_OBJROOT"
for mig in $MIGS_INTERNAL; do
	MIG_NAME=`basename $mig .defs`
	( cd "$MIG_INTERNAL_OBJROOT" && \
	  $MIG -novouchers -arch $MACHINE_ARCH -cc $MIGCC -header "$MIG_INTERNAL_HEADER_DST/${MIG_NAME}_internal.h" $MIG_INCFLAGS $SRC/$mig )
done
 
