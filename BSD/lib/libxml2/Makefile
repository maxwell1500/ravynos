# libxml2 for ravynOS: /usr/lib/libxml2.2.dylib.
#
# LibreOffice links libxml2.2 (compatibility 10.0.0) and the SDK needs the
# headers for ports.  The full 2.x source tree is in this directory; the build
# uses the same CMake toolchain file the source-port track uses, so the
# library is built by ravynos-cc against the ravynOS SDK rather than by the
# host toolchain.
#
# Python bindings are off (no Python in the image), lzma/ICU are off (neither
# is a build dependency of this library here), and iconv/zlib are on: both are
# now real libraries in this tree.
MK_WERROR=	no
BUILD=		${.OBJDIR}/cmake-build
STAGE=		${.OBJDIR}/cmake-stage

all: ${.OBJDIR}/libxml2.2.dylib

${.OBJDIR}/libxml2.2.dylib:
	mkdir -p ${BUILD} ${STAGE}
	cmake -G "Unix Makefiles" -S ${.CURDIR} -B ${BUILD} \
		-DCMAKE_TOOLCHAIN_FILE=${ROOT_SOURCE_DIR}/Developer/cmake/ravynos.toolchain.cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_NAME_DIR=/usr/lib \
		-DCMAKE_MACOSX_RPATH=OFF \
		-DCMAKE_DL_LIBS= \
		-DBUILD_SHARED_LIBS=ON \
		-DLIBXML2_WITH_PYTHON=OFF \
		-DLIBXML2_WITH_LZMA=OFF \
		-DLIBXML2_WITH_ICU=OFF \
		-DLIBXML2_WITH_ICONV=ON \
		-DLIBXML2_WITH_ZLIB=ON \
		-DLIBXML2_WITH_MODULES=OFF \
		-DLIBXML2_WITH_TESTS=OFF \
		-DLIBXML2_WITH_PROGRAMS=OFF
	${MAKE} -C ${BUILD}
	# libxml2's CMake stamps -compatibility_version 2.0.0 (its own version
	# major), but macOS clients record 10.0.0 for /usr/lib/libxml2.2.dylib
	# and dyld2 rejects a library that reports less than the client
	# recorded.  Re-link the same objects with Apple's ABI versions and
	# install name; the objects are untouched, only the identity changes.
	sed -e 's/-compatibility_version [0-9.]*/-compatibility_version 10.0.0/' \
	    -e 's/-current_version [0-9.]*/-current_version 10.9.0/' \
	    -e 's#-install_name [^ ]*#-install_name /usr/lib/libxml2.2.dylib#' \
	    ${BUILD}/CMakeFiles/LibXml2.dir/link.txt > ${BUILD}/link.ravyn.txt
	(cd ${BUILD} && sh link.ravyn.txt)
	${MAKE} -C ${BUILD} DESTDIR=${STAGE} install
	@for sdk in "${RAVYN_SDKROOT}" "${SYSROOT_DIR}" "${RAVYN_REPO_SDKROOT}"; do \
	  [ -n "$$sdk" ] && [ -d "$$sdk" ] || continue; \
	  mkdir -p "$$sdk/usr/lib" "$$sdk/usr/include/libxml2"; \
	  cp -f ${BUILD}/libxml2.2.12.4.dylib "$$sdk/usr/lib/libxml2.2.dylib"; \
	  ln -sf libxml2.2.dylib "$$sdk/usr/lib/libxml2.dylib"; \
	  cp -Rf ${STAGE}/usr/include/libxml2/* "$$sdk/usr/include/libxml2/"; \
	done
	touch ${.TARGET}
