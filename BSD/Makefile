.if "${.MAKE.OS}" == "Darwin"
SUBDIR = lib
.else
SUBDIR = lib
SUBDIR += bin
SUBDIR += sbin
SUBDIR += usr.bin
SUBDIR += usr.sbin
.endif
.include <bsd.subdir.mk>
