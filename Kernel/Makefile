ROOT_SOURCE_DIR ?= ${.CURDIR}/..
ROOT_BINARY_DIR ?= ${.CURDIR}/../../build
# ------------------------------------------------------------------------
#  RAVYNOS BUILD SYSTEM - Kernel and Extensions
# ------------------------------------------------------------------------

AVAILABILITY_PL = ${RAVYN_SDKROOT}/usr/local/libexec/availability.pl
AVAILABILITY_PL_PATH = ${RAVYN_SDKROOT}/usr/local/libexec/availability.pl
SEED_DEFINES = -DRC_ENABLE_XNU_PRODUCT_INFO_FILTER
PATH := ${TOOLCHAIN}/usr/bin:${PATH}
GMAKE ?= /usr/local/bin/gmake
PATH := ${PATH:C/:[^:]*VMware[^:]*//g:C/^://:C/:$//:C/::/:/g}
ARCH_CONFIGS ?= X86_64
KERNEL_CONFIGS ?= DEVELOPMENT
.if "${KERNEL_CONFIGS}" == "DEBUG"
DEBUG = .debug
.else
DEBUG =
.endif

.if "${.MAKE.OS}" ==  "Linux"
HOST_CODESIGN = /bin/true
IIG = /bin/true
HOST_LD ?= /usr/bin/ld
DKPATH = ${.OBJDIR}/xnu/${KERNEL_CONFIGS}_${ARCH_CONFIGS}/iokit/DriverKit

${DKPATH}: .NOTMAIN
	mkdir -p ${DKPATH}
	cp -Rf ${.CURDIR}/xnu/iokit/DriverKit/*.h ${DKPATH}/
TARGETS = ${DKPATH}
.endif
TARGETS += xnu_all

MAKEFLAGS=
.MAKEFLAGS=

PLATFORM_DIR=${ROOT_BINARY_DIR}/Developer/Platforms/ravynOS.platform

all: ${TARGETS}
installhdrs: .PHONY
	touch ${ROOT_BINARY_DIR}${.CURDIR}/xnu/.mach_kernel.timestamp
	touch ${ROOT_BINARY_DIR}${.CURDIR}/xnu/.symbolset.timestamp
	PATH="/usr/bin:${PATH}" env -u DEVELOPER_DIR -u MACOSX_DEPLOYMENT_TARGET MAKEFLAGS="" .MAKEFLAGS="" DEVELOPER_DIR=/Library/Developer/CommandLineTools XCRUN=/usr/bin/xcrun MACOSX_DEPLOYMENT_TARGET="" HOST_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk ${GMAKE} -C ${.CURDIR}/xnu LOGCOLORS=y PLATFORM=MacOSX BUILD_LTO=0 \
		BUILD_PROFILE=0 BUILD_WERROR=0 DO_CTFMERGE=0 \
		SDKVERSION=${MACOS_VERSION_MIN} SRCROOT=${.CURDIR}/xnu \
		OBJROOT=${.OBJDIR}/xnu DSTROOT=${RAVYN_SDKROOT} \
		MIGCOM=${MIGCOM} MIG=${MIG} IIG=${IIG} MIGCC=${CC} \
		CC=${CC} CXX=${CXX} HOST_OS_VERSION=${MACOS_VERSION_MIN} \
		UNIFDEF=${UNIFDEF} CTFCONVERT=${CTFCONVERT} \
		CTFMERGE=${CTFMERGE} CTFINSERT=${CTFINSERT} \
		HOST_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk \
		AVAILABILITY_PL=${AVAILABILITY_PL} SDKROOT=macosx \
		KERNEL_CONFIGS=${KERNEL_CONFIGS} ARCH_CONFIGS=${ARCH_CONFIGS} \
		DEVELOPER_DIR=/Library/Developer/CommandLineTools HOST_FLEX=flex \
		SYMROOT=${ROOT_BINARY_DIR} HOST_CC=/Library/Developer/CommandLineTools/usr/bin/clang HOST_BISON=bison \
		HOST_CXX=/Library/Developer/CommandLineTools/usr/bin/clang++ HOST_LD=/usr/bin/ld \
		HOST_CODESIGN_ALLOCATE=/bin/true installhdrs

libfirehose_kernel: .PHONY
	${MAKE} -C ${ROOT_SOURCE_DIR}/Libraries/libfirehose_kernel all

compiler_rt: .PHONY
	${MAKE} -C ${ROOT_SOURCE_DIR}/Libraries all

xnu_all: installhdrs libfirehose_kernel compiler_rt
	PATH="/usr/bin:${PATH}" env -u DEVELOPER_DIR -u MACOSX_DEPLOYMENT_TARGET MAKEFLAGS="" .MAKEFLAGS="" DEVELOPER_DIR=/Library/Developer/CommandLineTools XCRUN=/usr/bin/xcrun MACOSX_DEPLOYMENT_TARGET="" HOST_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk ${GMAKE} -C ${.CURDIR}/xnu LOGCOLORS=y \
		PLATFORM=MacOSX BUILD_LTO=0 BUILD_WERROR=0 DO_CTFMERGE=0 \
		SDKVERSION=${MACOS_VERSION_MIN} SRCROOT=${.CURDIR}/xnu \
		SYMROOT=${.OBJDIR}/xnu/sym BUILD_STATIC_LINK=1 \
		MIGCOM=${MIGCOM} MIG=${MIG} IIG=${IIG} CC=/Library/Developer/CommandLineTools/usr/bin/clang CXX=/Library/Developer/CommandLineTools/usr/bin/clang++ \
		UNIFDEF=${UNIFDEF} CTFCONVERT=${CTFCONVERT} LD="/Library/Developer/CommandLineTools/usr/bin/clang --ld-path=/Library/Developer/CommandLineTools/usr/bin/ld" \
		CTFMERGE=${CTFMERGE} CTFINSERT=${CTFINSERT} AR=/usr/bin/ar \
		NM=/usr/bin/nm NMEDIT=/usr/bin/nmedit DSYMUTIL=/usr/bin/dsymutil LIPO=/usr/bin/lipo \
	       	STRIP=/usr/bin/strip AS=/Library/Developer/CommandLineTools/usr/bin/clang AVAILABILITY_PL=${AVAILABILITY_PL} \
		MACHINE=${MACHINE} XCRUN=/usr/bin/xcrun SDKROOT=macosx \
		HOST_OS_VERSION=${MACOS_VERSION_MIN} VERBOSE=yes \
		AVAILABILITY_PL_PATH=${AVAILABILITY_PL_PATH} \
		DEVELOPER_DIR=/Library/Developer/CommandLineTools \
		KERNEL_CONFIGS=${KERNEL_CONFIGS} ARCH_CONFIGS=${ARCH_CONFIGS} \
		HOST_CC=/Library/Developer/CommandLineTools/usr/bin/clang HOST_CXX=/Library/Developer/CommandLineTools/usr/bin/clang++ HOST_LD=/usr/bin/ld all install
.for target_dir in ${RAVYN_SDKROOT}/System/Library/Kernels \
  ${SYSROOT_DIR}/System/Library/Kernels
	mkdir -p ${target_dir} ${target_dir:H}/Extensions
	@if [ -d ${.OBJDIR}/xnu/sym/kernel${DEBUG}.dSYM ]; then \
		cp -Rf ${.OBJDIR}/xnu/sym/kernel${DEBUG}.dSYM ${target_dir}/; \
		cp -f ${.OBJDIR}/xnu/sym/kernel${DEBUG} ${target_dir}/; \
		cp -Rf ${.OBJDIR}/xnu/sym/System.kext ${target_dir:H}/Extensions/; \
	elif [ -f ${ROOT_BINARY_DIR}/DEVELOPMENT_X86_64/kernel.development ]; then \
		cp -Rf ${ROOT_BINARY_DIR}/DEVELOPMENT_X86_64/kernel.development.dSYM ${target_dir}/ 2>/dev/null || true; \
		cp -f ${ROOT_BINARY_DIR}/DEVELOPMENT_X86_64/kernel.development ${target_dir}/kernel 2>/dev/null || cp -f ${ROOT_BINARY_DIR}/DEVELOPMENT_X86_64/kernel.development ${target_dir}/; \
		cp -Rf ${ROOT_BINARY_DIR}/DEVELOPMENT_X86_64/System.kext ${target_dir:H}/Extensions/ 2>/dev/null || true; \
	elif [ -f ${ROOT_BINARY_DIR}/DEVELOPMENT_X86_64/kernel ]; then \
		cp -f ${ROOT_BINARY_DIR}/DEVELOPMENT_X86_64/kernel ${target_dir}/; \
	else \
		echo "kernel not found"; false; \
	fi
.endfor

# NOTE! This kxld build is for the host toolchain. The target kxld is built
# later in IOKitUser
.if "${.MAKE.OS}" != "Darwin"
SUBDIR = xnu/libkern/kmod xnu/libkern/kxld
SUBDIR += IOKitUser 
SUBDIR += Extensions
.else
SUBDIR =
.endif

.include <bsd.subdir.mk>
