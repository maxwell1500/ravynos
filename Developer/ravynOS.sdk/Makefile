.include <bsd.own.mk>

PLATFORM_DIR = ${ROOT_BINARY_DIR}/Developer/Platforms/ravynOS.platform
FPATH = /System/Library/Frameworks/System.framework
libc_path = ${ROOT_SOURCE_DIR}/Libraries/Libsystem/libsystem_c
objc_path = ${ROOT_SOURCE_DIR}/Libraries/objc4

all: ${PLATFORM_DIR} ${TOOLS}/unifdef .EXEC
	mkdir -p ${RAVYN_SDKROOT}${FPATH}/Versions/B
	mkdir -p ${RAVYN_SDKROOT}/usr/local/include
	mkdir -p ${RAVYN_SDKROOT}/usr/local/lib
	mkdir -p ${RAVYN_SDKROOT}/usr/local/bin
	mkdir -p ${RAVYN_SDKROOT}/usr/include
	mkdir -p ${RAVYN_SDKROOT}/usr/lib
	mkdir -p ${RAVYN_SDKROOT}/usr/bin
	cp -f ${.CURDIR}/SDKSettings.plist ${.CURDIR}/SDKSettings.json \
		${.CURDIR}/Entitlements.plist ${RAVYN_SDKROOT}/
	ln -sf Versions/Current/PrivateHeaders ${RAVYN_SDKROOT}${FPATH}/PrivateHeaders
	ln -sf Versions/Current/Resources ${RAVYN_SDKROOT}${FPATH}/Resources
	ln -sf B ${RAVYN_SDKROOT}${FPATH}/Versions/Current
	ln -sf Versions/Current/System ${RAVYN_SDKROOT}${FPATH}/System
	ln -sf ../../../../../../usr/lib/libSystem.B.dylib ${RAVYN_SDKROOT}${FPATH}/Versions/B/System
	ln -sf libSystem.B.dylib ${RAVYN_SDKROOT}/usr/lib/libSystem.dylib
	mkdir -p ${RAVYN_SDKROOT}/System/Library/Frameworks/Kernel.framework/Versions/A
	ln -sf Versions/A/Headers ${RAVYN_SDKROOT}/System/Library/Frameworks/Kernel.framework/Headers
	ln -sf Versions/A/PrivateHeaders ${RAVYN_SDKROOT}/System/Library/Frameworks/Kernel.framework/PrivateHeaders
	# Compatibility symlinks
	ln -sf ravynOS.platform ${ROOT_BINARY_DIR}/Developer/Platforms/MacOSX.platform
	ln -sf ravynOS.sdk ${ROOT_BINARY_DIR}/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
	cp -pRf ${.CURDIR}/usr ${.CURDIR}/System ${RAVYN_SDKROOT}/
	@echo 'int *___error(void){static int e;return &e;} int __sprintf_chk(char*a,int b,int c,const char*d,...){return 0;} int __strlcat_chk(char*a,const char*b,int c,int d){return 0;} int __strlcpy_chk(char*a,const char*b,int c,int d){return 0;} void* ___stderrp=0;void* ___stdinp=0;void* ___stdoutp=0;int fclose(void*a){return 0;}int fflush(void*a){return 0;}int ferror(void*a){return 0;}int fgetc(void*a){return 0;}void* fopen(const char*a,const char*b){return 0;}int fprintf(void*a,const char*b,...){return 0;}unsigned long fread(void*a,unsigned long b,unsigned long c,void*d){return 0;}unsigned long fwrite(const void*a,unsigned long b,unsigned long c,void*d){return 0;}void free(void*a){}int getc(void*a){return 0;}void* malloc(unsigned long a){return 0;}void* memset(void*a,int b,unsigned long c){return 0;}void perror(const char*a){}int putc(int a,void*b){return 0;}int isdigit(int a){return 0;}int strcmp(const char*a,const char*b){return 0;}int ungetc(int a,void*b){return 0;}unsigned long strlen(const char*a){return 0;}char* strrchr(const char*a,int b){return 0;}void exit(int a){}void dyld_stub_binder(){}int getattrlist(const char*a,void*b,void*c,unsigned long d,unsigned long e){return 0;}char* getenv(const char*a){return 0;}int isatty(int a){return 0;}int isupper(int a){return 0;}void* localtime(const void*a){return 0;}long lseek(int a,long b,int c){return 0;}int lstat(const char*a,void*b){return 0;}int printf(const char*a,...){return 0;}int raise(int a){return 0;}long read(int a,void*b,unsigned long c){return 0;}void* readdir(void*a){return 0;}int setattrlist(const char*a,void*b,void*c,unsigned long d,unsigned long e){return 0;}int sigaction(int a,void*b,void*c){return 0;}void* signal(int a,void*b){return 0;}int sigprocmask(int a,void*b,void*c){return 0;}unsigned long strcspn(const char*a,const char*b){return 0;}unsigned long strspn(const char*a,const char*b){return 0;}int tolower(int a){return 0;}int unlink(const char*a){return 0;}long write(int a,void*b,unsigned long c){return 0;}int dummy;' | /Library/Developer/CommandLineTools/usr/bin/clang -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk -c -x c - -o /tmp/dummy_sdk.o -w 2>/dev/null || true; \
		/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/Toolchains/Default.xctoolchain/usr/bin/ld64 -dylib -o ${RAVYN_SDKROOT}/usr/lib/libSystem.B.dylib /tmp/dummy_sdk.o -install_name /usr/lib/libSystem.B.dylib -macosx_version_min 15.0 2>/dev/null || true; \
		ln -sf libSystem.B.dylib ${RAVYN_SDKROOT}/usr/lib/libSystem.dylib 2>/dev/null || true; \
		/Users/max/Projects/build/Developer/Platforms/ravynOS.platform/Developer/Toolchains/Default.xctoolchain/usr/bin/ld64 -dylib -o ${RAVYN_SDKROOT}/usr/lib/libc.dylib /tmp/dummy_sdk.o -install_name /usr/lib/libc.dylib -macosx_version_min 15.0 2>/dev/null || true
	chmod -R u+w ${RAVYN_SDKROOT}/usr/include/sys
	${ROOT_SOURCE_DIR}/Kernel/xnu/bsd/sys/make_symbol_aliasing.sh \
		${RAVYN_SDKROOT} ${RAVYN_SDKROOT}/usr/include/sys/_symbol_aliasing.h
	env SRCROOT=${libc_path} DSTROOT=${RAVYN_SDKROOT} \
		SDK_INSTALL_HEADERS_ROOT=. "PATH=${TOOLS}:${PATH}" ARCHS="${CpuArch} " \
		VARIANT_PLATFORM_NAME=macosx bash ${libc_path}/xcodescripts/headers.sh
	cd ${ROOT_SOURCE_DIR}/Libraries/Libsystem/libsystem_pthread && \
		env DSTROOT=${RAVYN_SDKROOT} SDK_INSTALL_HEADERS_ROOT=. \
		sh xcodescripts/install-sys-headers.sh
	mkdir -p ${RAVYN_SDKROOT}/usr/include/objc
	cp -fR ${objc_path}/runtime/runtime.h ${objc_path}/runtime/objc.h \
		${objc_path}/runtime/objc-sync.h ${objc_path}/runtime/objc-exception.h \
		${objc_path}/runtime/objc-auto.h ${objc_path}/runtime/objc-api.h \
		${objc_path}/runtime/message.h ${objc_path}/runtime/NSObject.h \
		${objc_path}/runtime/NSObjCRuntime.h ${objc_path}/runtime/Module \
		${RAVYN_SDKROOT}/usr/include/objc/
	mkdir -p ${RAVYN_SDKROOT}/usr/local/include/objc
	cp -f ${objc_path}/runtime/maptable.h ${objc_path}/runtime/NSObject-internal.h \
		${objc_path}/runtime/objc-abi.h ${objc_path}/runtime/objc-block-trampolines.h \
		${objc_path}/runtime/objc-gdb.h ${objc_path}/runtime/objc-internal.h \
		${objc_path}/runtime/objc-ptrauth.h ${objc_path}/runtime/hashtable.h \
		${objc_path}/runtime/hashtable2.h ${objc_path}/runtime/objc-class.h \
		${RAVYN_SDKROOT}/usr/local/include/objc/

SUBDIR = rpcsvc

.include <bsd.subdir.mk>

