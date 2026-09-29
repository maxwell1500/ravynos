SUBDIR =
MK_WERROR = no
LIB = edit

.PATH: ${.CURDIR}/src
SRCS =  chared.c \
	chartype.c \
	common.c \
	el.c \
	eln.c \
	emacs.c \
	filecomplete.c \
	hist.c \
	history.c \
	historyn.c \
	keymacro.c \
	literal.c \
	map.c \
	parse.c \
	prompt.c \
	read.c \
	readline.c \
	reallocarr.c \
	refresh.c \
	search.c \
	sig.c \
	terminal.c \
	tokenizer.c \
	tokenizern.c \
	tty.c \
	vi.c

# Upstream src/Makefile.am:38-52 adds strlcpy.c / strlcat.c / getline.c /
# vis.c / unvis.c / wcsdup.c only `if !HAVE_...`. This list named them
# unconditionally, which compiles a second definition of every one of them
# into libedit.a -- and all of them already exist on ravynOS:
#     _vis _unvis _getline _wcsdup  -> libsystem_c/libc_static/libc.a
#     _strlcpy _strlcat             -> libsystem_platform/static/libsystem_platform.a
# An archive member is only pulled when it resolves an undefined symbol, so
# this happened to link by luck of link order; it is still a second
# definition of a real libc function and must not be compiled here. Gate on
# config.h, which is what upstream does.
.if !defined(HAVE_VIS)
SRCS += vis.c
.endif
.if !defined(HAVE_STRUNVIS)
SRCS += unvis.c
.endif
.if !defined(HAVE_GETLINE)
SRCS += getline.c
.endif
.if !defined(HAVE_WCSDUP)
SRCS += wcsdup.c
.endif
.if !defined(HAVE_STRLCPY)
SRCS += strlcpy.c
.endif
.if !defined(HAVE_STRLCAT)
SRCS += strlcat.c
.endif

.include <bsd.lib.mk>

CFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
	-I${.CURDIR}/src -I${.CURDIR} -I${.OBJDIR}
LDFLAGS = --sysroot=${RAVYN_SDKROOT} -mmacos-version-min=${MACOS_VERSION_MIN} \
        -fuse-ld=${LD}

AHDR = vi.h emacs.h common.h 

# ---------------------------------------------------------------------------
# The Darwin branch used to `touch` a 0-byte libedit.a and a 0-byte
# ${RAVYN_SDKROOT}/usr/lib/libedit.dylib. It did that because the build
# genuinely could not run, not out of laziness, and the reason is not
# visible in the .c files:
#
#   src/{vi,emacs,common,fcns,help,func}.h are NOT in the tree. They are
#   BUILT_SOURCES -- src/Makefile.am:7-23 generates each one by running
#   src/makelist over the command tables in vi.c/emacs.c/common.c:
#
#       common.h: AWK=$(AWK) sh $(srcdir)/makelist -h $(srcdir)/common.c > $@
#
#   Twelve of the 32 sources (vi.c, emacs.c, common.c, map.c, read.c,
#   search.c, sig.c, terminal.c, tty.c, keymacro.c, readline.c) include
#   "common.h" or "fcns.h" unconditionally, so the archive could not be
#   assembled at all and `touch` was the only way to keep the tree
#   walking. It is the same defect class as the stale builtins.c in
#   BSD/bin/sh: a generated table that silently disagrees with (here, is
#   missing from) its generator's input.
#
# So the Darwin branch now GENERATES those six headers and then builds,
# exactly as the .else branch does. It must never touch.
#
# makelist is a /bin/sh script that dispatches on awk-vs-gawk; the tree
# ships src/makelist, and AWK is honoured the same way src/Makefile.am
# does. The six headers are written into ${.OBJDIR} rather than into
# src/ so a build never mutates the source tree, and -I${.OBJDIR} (already
# in CFLAGS below) is what finds them.
BUILT_SOURCES = vi.h emacs.h common.h fcns.h help.h func.h

AHDR = ${.OBJDIR}/vi.h ${.OBJDIR}/emacs.h ${.OBJDIR}/common.h
ASRC = ${.CURDIR}/src/vi.c ${.CURDIR}/src/emacs.c ${.CURDIR}/src/common.c

${.OBJDIR}/vi.h: ${.CURDIR}/src/vi.c
	@mkdir -p ${.OBJDIR}
	AWK=${AWK} sh ${.CURDIR}/src/makelist -h ${.CURDIR}/src/vi.c > ${.TARGET}

${.OBJDIR}/emacs.h: ${.CURDIR}/src/emacs.c
	@mkdir -p ${.OBJDIR}
	AWK=${AWK} sh ${.CURDIR}/src/makelist -h ${.CURDIR}/src/emacs.c > ${.TARGET}

${.OBJDIR}/common.h: ${.CURDIR}/src/common.c
	@mkdir -p ${.OBJDIR}
	AWK=${AWK} sh ${.CURDIR}/src/makelist -h ${.CURDIR}/src/common.c > ${.TARGET}

${.OBJDIR}/fcns.h: ${AHDR}
	AWK=${AWK} sh ${.CURDIR}/src/makelist -fh ${AHDR} > ${.TARGET}

${.OBJDIR}/help.h: ${ASRC}
	AWK=${AWK} sh ${.CURDIR}/src/makelist -bh ${ASRC} > ${.TARGET}

${.OBJDIR}/func.h: ${AHDR}
	AWK=${AWK} sh ${.CURDIR}/src/makelist -fc ${AHDR} > ${.TARGET}
all: ${.OBJDIR}/lib${LIB}.a ${.OBJDIR}/lib${LIB}.dylib

${.OBJDIR}/lib${LIB}.dylib: ${.OBJDIR}/lib${LIB}.a
	${CC} ${LDFLAGS} -shared -o ${.TARGET} \
	  -Wl,-install_name,/usr/lib/libedit.dylib \
	  -Wl,-current_version,3.1 -Wl,-compatibility_version,1.0 \
	  -nodefaultlibs -Wl,-not_for_dyld_shared_cache \
	  -Wl,-force_load,${.OBJDIR}/lib${LIB}.a -lncurses
	mkdir -p ${RAVYN_SDKROOT}/usr/lib ${SYSROOT_DIR}/usr/lib
	cp -f ${.TARGET} ${RAVYN_SDKROOT}/usr/lib/
	cp -f ${.TARGET} ${SYSROOT_DIR}/usr/lib/

