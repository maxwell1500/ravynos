

libSystem_malloc:
	# We just need the headers for now
	mkdir -p ${BUILDROOT}/usr
	cp -R ${SRCTOP}/Libraries/libmalloc/include ${BUILDROOT}/usr/

copyfile.h: .PHONY
	mkdir -p ${BUILDROOT}/usr/include
	cp -fv ${CONTRIB}/copyfile/copyfile.h ${BUILDROOT}/usr/include/

architecture: .PHONY
	SRCROOT=${SRCTOP}/contrib/architecture DSTROOT=${BUILDROOT} \
		${GMAKE} -C contrib/architecture

libkmod: xnu_headers
	mkdir -pv ${OBJTOP}/Kernel/libkmod/include/pthread
	cp -fv ${SRCTOP}/Libraries/libpthread/private/{spinlock,tsd}_private.h \
		${OBJTOP}/Kernel/libkmod/include/pthread/
	cp -fv ${SRCTOP}/Libraries/Libc/locale/FreeBSD/{collate,lmessages,lmonetary,lnumeric,setlocale}.h \
		${OBJTOP}/Kernel/libkmod/include/
	cp -fv ${SRCTOP}/Libraries/Libc/stdtime/FreeBSD/timelocal.h \
		${OBJTOP}/Kernel/libkmod/include/
	ln -sfv B ${OBJTOP}/release/System/Library/Frameworks/System.framework/Versions/Current
	ln -sfv Versions/Current/Headers \
		${OBJTOP}/release/System/Library/Frameworks/System.framework/Headers
	ln -sfv Versions/Current/PrivateHeaders \
		${OBJTOP}/release/System/Library/Frameworks/System.framework/PrivateHeaders
	mkdir -pv ${BUILDROOT}/usr/include/os
	cp -fv ${CONTRIB}/os/availability.h ${BUILDROOT}/usr/include/os
	cd ${OBJTOP}/Kernel/libkmod; cmake -Wno-dev \
		-DCMAKE_INSTALL_PREFIX=/ -DCMAKE_BUILD_TYPE=Release \
		-DSRCTOP=${SRCTOP} -DOBJTOP=${OBJTOP} \
		-G"Unix Makefiles" ${SRCTOP}/Kernel/libkmod
	export PATH PLATFORM=MacOSX MAKEFLAGS="" MAKE=${GMAKE}; \
		${GMAKE} DESTDIR=${BUILDROOT} -C ${OBJTOP}/Kernel/libkmod

kext: libkmod
	mkdir -pv ${OBJTOP}/Kernel/Extensions/include/pthread
	mkdir -pv ${OBJTOP}/Kernel/Extensions/include/IOKit/{storage,ata}
	cp -fv ${SRCTOP}/Libraries/libpthread/private/qos_private.h \
		${OBJTOP}/Kernel/Extensions/include/pthread/
	cp -fv ${SRCTOP}/Kernel/Extensions/IOATAFamily/IOATARegI386.h \
		${OBJTOP}/Kernel/Extensions/include/IOKit/ata/
	cp -fv ${SRCTOP}/Kernel/Extensions/IOStorageFamily/*.h \
		${OBJTOP}/Kernel/Extensions/include/IOKit/storage/
	cd ${OBJTOP}/Kernel/Extensions;	cmake -Wno-dev \
		-DCMAKE_INSTALL_PREFIX=/System/Library/Extensions \
		-DCMAKE_BUILD_TYPE=Release -DSRCTOP=${SRCTOP} -DOBJTOP=${OBJTOP} \
		-G"Unix Makefiles" ${SRCTOP}/Kernel/Extensions
	export PATH PLATFORM=MacOSX MAKEFLAGS="" MAKE=${GMAKE}; \
		${GMAKE} DESTDIR=${BUILDROOT} -C ${OBJTOP}/Kernel/Extensions \
		install

KMUTIL?= /usr/bin/kmutil
prelink:
	${KMUTIL} create --allow-missing-kdk -n boot -z \
		--boot-path ${OBJTOP}/Kernel/kernelcache \
		-f 'OSBundleRequired == Local-Root'  \
		--kernel ${OBJTOP}/Kernel/xnu/RELEASE_${MACHINE:S/x/X/}/kernel \
		-r ${BUILDROOT}/System/Library/Extensions/ \
		-r ${SRCTOP}/Kernel/xnu/config/System.kext/PlugIns \
		--bundle-path ${SRCTOP}/Kernel/xnu/config/System.kext
