MK_WERROR = no
PROG = sh
SRCS =  bltin/echo.c \
	alias.c \
	arith_yacc.c \
	arith_yylex.c \
	cd.c \
	error.c \
	eval.c \
	exec.c \
	expand.c \
	histedit.c \
	input.c \
	jobs.c \
	mail.c \
	main.c \
	memalloc.c \
	miscbltin.c \
	mystring.c \
	options.c \
	output.c \
	parser.c \
	redir.c \
	show.c \
	trap.c \
	var.c \
	builtins.c \
	nodes.c \
	syntax.c \
	shims.c

CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-DSHELL -I${.CURDIR} -I${.OBJDIR} -I${.CURDIR}/../../lib/libedit/src \
        -Wno-nullability-completeness

LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-L${RAVYN_SDKROOT}/usr/lib -lncursesw \
	-L${ROOT_BINARY_DIR}${.CURDIR:H}/../lib/libedit -ledit

builtins.c builtins.h: ${.CURDIR}/mkbuiltins ${SRCS:N*builtins.*}
	${.CURDIR}/mkbuiltins ${.CURDIR}

syntax.c syntax.h: mksyntax
	${.OBJDIR}/mksyntax

nodes.c nodes.h: mknodes
	${.OBJDIR}/mknodes ${.CURDIR}/nodetypes ${.CURDIR}/nodes.c.pat

token.h:
	${.CURDIR}/mktokens

parser.o: token.h

mksyntax: ${.CURDIR}/mksyntax.c
	${HOST_CC} \
	  -include${ROOT_SOURCE_DIR}/Libraries/Libsystem/libsystem_c/fbsdcompat/_fbsd_compat_.h \
	  "-D__unused=" -o ${.OBJDIR}/mksyntax ${.CURDIR}/mksyntax.c

mknodes: ${.CURDIR}/mknodes.c
	${HOST_CC} \
	  -include${ROOT_SOURCE_DIR}/Libraries/Libsystem/libsystem_c/fbsdcompat/_fbsd_compat_.h \
	  "-D__unused=" -o ${.OBJDIR}/mknodes ${.CURDIR}/mknodes.c


.include <bsd.prog.mk>
