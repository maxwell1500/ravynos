PROG = syslogd
SRCS = syslogd.c \
       daemon.c \
       asl_action.c \
       bsd_in.c \
       bsd_out.c \
       dbserver.c \
       klog_in.c \
       remote.c \
       udp_in.c \
       ../../syslog/aslcommon/asl_common.c \
       ../../syslog/aslcommon/asl_memory.c \
       ../../../Libraries/Libsystem/libsystem_asl/asl_ipcServer.c

MAN =
MK_WERROR = no

CFLAGS += --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	  -Wno-nullability-completeness -D_DARWIN_C_SOURCE \
	  -I${.CURDIR} -I${.CURDIR}/../../syslog/aslcommon \
	  -I${.CURDIR}/../../../Libraries/Libsystem/libsystem_asl \
	  -I${.CURDIR}/../../../Libraries/Libsystem/libsystem_notify \
	  -I${.CURDIR}/../../../Developer/ravynOS.sdk/usr/include \
	  -I${.CURDIR}/../../../Libraries/openbsm

LDFLAGS += -Wl,-platform_version -Wl,macos \
	   -Wl,${MACOS_VERSION_MIN} -Wl,${MACOS_VERSION_MIN} \
	   -Wl,-syslibroot,${RAVYN_SDKROOT}/usr/lib -lSystem -lbsm

all: ${PROG}

${.OBJDIR}/${PROG}:
	mkdir -p ${.TARGET:H}

${PROG}: ${.OBJDIR}/${PROG}

install: ${PROG}

.include <bsd.prog.mk>
