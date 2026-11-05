PROG = aslmanager
SRCS = aslmanager.c \
       daemon.c \
       ../../syslog/aslcommon/asl_common.c \
       ../../syslog/aslcommon/asl_memory.c

MAN =
MK_WERROR = no
CFLAGS += --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	  -Wno-nullability-completeness -D_DARWIN_C_SOURCE \
	  -I${.CURDIR} -I${.CURDIR}/../../syslog/aslcommon \
	  -I${.CURDIR}/../../../Libraries/Libsystem/liblaunch \
	  -I${.CURDIR}/../../../Libraries/Libsystem/libsystem_asl \
	  -I${.CURDIR}/../../../Developer/ravynOS.sdk/usr/include

LDFLAGS += -Wl,-platform_version -Wl,macos \
	   -Wl,${MACOS_VERSION_MIN} -Wl,${MACOS_VERSION_MIN} \
	   -Wl,-syslibroot,${RAVYN_SDKROOT}/usr/lib -lSystem -lz

all: ${PROG}

${.OBJDIR}/${PROG}:
	mkdir -p ${.TARGET:H}

${PROG}: ${.OBJDIR}/${PROG}

install: ${PROG}

.include <bsd.prog.mk>
