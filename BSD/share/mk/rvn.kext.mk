.include <bsd.suffixes.mk>

.iig.cpp .iig.h .iig.o:
	@echo '[WARNING] NOT processing IIG file ${.IMPSRC} -> ${.TARGET}'

_KEXT_FOLDER = ${.OBJDIR}/${KEXT}.kext
_KEXT_LIB = ${_KEXT_FOLDER}/Contents/MacOS/${KEXT}

.if defined(RAVYN_SDKROOT)
SDKROOT = ${RAVYN_SDKROOT}
.endif

.PATH: ${.OBJDIR}
SRCS += kmod_info.c
OBJS = ${SRCS:C/\..*$/.o/}

# Kernel headers first.  A kext compiles against the kernel's own mach/,
# osfmk/ and vm/ headers (published in the Kernel.framework inside the SDK),
# not against the userspace copies in usr/include.  With the userspace headers
# ahead of these, mach/port.h defines ipc_port_t differently and
# vm/vm_memtag.h is not found at all -- which is what every kext produced
# before this ordering was fixed.
_KEXT_KERNEL_INCLUDES = \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/osfmk \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/libkern \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/bsd \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/iokit \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/security \
	-I${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/Kernel/xnu/EXPORT_HDRS/san \
	-I${SDKROOT}/usr/local/include/kernel

# := (immediate expansion) on purpose: `CFLAGS = ... ${CFLAGS}` is a
# self-reference, which bmake rejects ("Variable CFLAGS is recursive") and
# then treats as empty -- silently dropping every include the kext Makefile
# set.  Expanding once here keeps the kext's flags and puts the kernel headers
# in front of them.
# -include mach/task_info.h: kern/task.h declares task_get_suspend_stats()
# with task_suspend_stats_t under KERNEL_PRIVATE but only includes
# mach/task_info.h under MACH_KERNEL_PRIVATE, which kexts must not define.
# __builtin_xnu_type_summary() is an Apple-clang builtin (the kernel signature
# type system).  The ravynOS toolchain's clang does not implement it, and the
# only use in the exported headers is a static_assert that classifies a type
# as data-only.  Defining it to 0 keeps that assertion true, which is the
# permissive answer: it disables a diagnostic, not a runtime check.
CFLAGS := ${_KEXT_KERNEL_INCLUDES} -DKERNEL -DPRIVATE \
	"-D__builtin_xnu_type_summary(x)=0" -include mach/task_info.h \
	--sysroot=${SDKROOT} ${CFLAGS} \
	-I${SDKROOT}/usr/include -I${SDKROOT}/usr/local/include
# The CFLAGS capture above happens before the KERNEL_PRIVATE block
# below, so C++ files would compile without -DKERNEL_PRIVATE and headers
# such as i386/machine_routines.h would hide ipi_handler_t.
CXXFLAGS := -fapple-kext ${CFLAGS} ${CXXFLAGS} ${KERNEL_PRIVATE:?-DKERNEL_PRIVATE:}
LDFLAGS += -nostdlib -Wl,-bundle -Wl,-undefined,dynamic_lookup \
	-Wl,-kext -Wl,-segalign,0x1000 \
	-L${SDKROOT}/usr/lib -L${SDKROOT}/usr/lib/system

.if defined(RPATHS)
.for rpath in ${RPATHS}
LDFLAGS += -Wl,-rpath,${rpath}
.endfor
.endif

.if "${INSTALL_NAME_DIR}" != ""
LDFLAGS += -Wl,-install_name,${INSTALL_NAME_DIR}/${KEXT}
.elsif "${INSTALL_NAME}" != ""
LDFLAGS += -Wl,-install_name,${INSTALL_NAME}
.endif

.if defined(KERNEL_PRIVATE)
CFLAGS += -DKERNEL_PRIVATE
LDFLAGS += -L${SDKROOT}/usr/local/lib/kernel -lkmod
.endif

# XNU's kext headers use C++11 templates; an empty CXXSTD makes bsd.lib.mk
# pass -std= and the compiler defaults to gnu++98, where "T does not refer to
# a value" in OSData.h/IOLib.h.
CXXSTD ?= gnu++17
CSTD ?= gnu17

.if defined(MACOS_VERSION_MIN)
CFLAGS += -mmacos-version-min=${MACOS_VERSION_MIN}
LDFLAGS += -mmacos-version-min=${MACOS_VERSION_MIN}
.endif

.if defined(MAIN_FUNCTION)
MAIN_FUNCTION_DECL = extern kern_return_t ${MAIN_FUNCTION}(kmod_info_t *ki, void *data);
.else
MAIN_FUNCTION = 0
.endif

.if defined(ANTIMAIN_FUNCTION)
ANTIMAIN_FUNCTION_DECL = extern kern_return_t ${ANTIMAIN_FUNCTION}(kmod_info_t *ki, void *data);
.else
ANTIMAIN_FUNCTION = 0
.endif

all: ${_KEXT_LIB}

${_KEXT_FOLDER}:
	mkdir -p ${.TARGET}/Contents/MacOS

${_KEXT_FOLDER}/Contents/Info.plist: ${.CURDIR}/${INFO_PLIST}
	sed -e 's/@BUNDLE_IDENTIFIER@/${BUNDLE_IDENTIFIER}/' \
	    -e 's/@BUNDLE_VERSION@/${BUNDLE_VERSION}/' \
	    ${.CURDIR}/${INFO_PLIST} >${.TARGET}

${_KEXT_LIB}: ${_KEXT_FOLDER} ${_KEXT_FOLDER}/Contents/Info.plist ${OBJS} \
		${.OBJDIR}/kmod_info.c 
	${CXX} -o ${.TARGET} ${OBJS} ${LDFLAGS}

.if defined(KERNEL_PRIVATE)
${_KEXT_LIB}: ${SDKROOT}/usr/local/lib/kernel/libkmod.a
.endif

kmod_info.c: ${.OBJDIR}/kmod_info.c
${.OBJDIR}/kmod_info.c:
	(echo '#include <mach/kmod.h>'; \
	 echo 'extern kern_return_t _start(kmod_info_t *ki, void *data);'; \
	 echo 'extern kern_return_t _stop(kmod_info_t *ki, void *data);'; \
	 echo '${MAIN_FUNCTION_DECL}'; \
	 echo '${ANTIMAIN_FUNCTION_DECL}'; \
	 echo '__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(${BUNDLE_IDENTIFIER}, "${BUNDLE_VERSION}", _start, _stop)'; \
	 echo '__private_extern__ kmod_start_func_t *_realmain = ${MAIN_FUNCTION};'; \
	 echo '__private_extern__ kmod_stop_func_t *_antimain = ${ANTIMAIN_FUNCTION};'; \
	 echo '__private_extern__ int _kext_apple_cc = __APPLE_CC__;') >${.TARGET}

.include <bsd.lib.mk>

# bsd.lib.mk pulls in bsd.sys.mk, which appends -fuse-ld=<path> (from the kext
# Makefile) and, on Darwin hosts, -lSystem.  Neither belongs on a kext link:
# the selected linker does not apply the sysroot's library search path, and a
# kext resolves kernel symbols through -undefined dynamic_lookup rather than
# against libSystem.  Strip both after the mk files have had their say.
LDFLAGS := ${LDFLAGS:C/-fuse-ld=[^ ]*//g}
LDFLAGS := ${LDFLAGS:C/-lSystem//g}
