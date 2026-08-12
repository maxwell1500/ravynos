.include <src.opts.mk>

SUBDIR =
PROG=	head
CFLAGS += -I${ROOT_SOURCE_DIR}/BSD/lib/libutil
LDFLAGS += -L${ROOT_BINARY_DIR}${ROOT_SOURCE_DIR}/BSD/lib/libutil -lutil

.include <bsd.prog.mk>
