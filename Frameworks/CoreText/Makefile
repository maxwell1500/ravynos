FRAMEWORK=CoreText

SRCS= CTFont.m KTFont.m
HEADERS= CoreText.h CoreTextExport.h CTFont.h KTFont.h
RESOURCES=Info.plist 
LDFLAGS+= -F${OBJTOP}/Frameworks/Onyx2D -framework Onyx2D \
	-Wl,-rpath,/System/Library/Frameworks/Onyx2D.framework/Versions/A \
	-F${OBJTOP}/Frameworks/CoreGraphics -framework CoreGraphics \
	-Wl,-rpath,/System/Library/Frameworks/CoreGraphics.framework/Versions/A \
	-F${OBJTOP}/Frameworks/Foundation -framework Foundation \
	-Wl,-rpath,/System/Library/Frameworks/Foundation.framework/Versions/A \
	-lobjc
WARNS= 1
MK_WERROR= no


clean:
	rm -f ${MAKEOBJDIR}/*.o ${MAKEOBJDIR}/*.pico

.include <rvn.framework.mk>

CFLAGS+= -I${.CURDIR:H} -I${.CURDIR:H}/libobjc2 -I${.CURDIR:H}/Foundation/Headers \
	 -I${.CURDIR}/fontconfig/fontconfig \
	 -F${OBJTOP}/Frameworks/OpenGL

fontresources:
	cp -fv ${.CURDIR}/fontconfig/conf.d/*.conf ${FRAMEWORK_DIR}/Versions/A/Resources/
.for f in  \
	10-hinting-medium.conf \
	10-scale-bitmap-fonts.conf \
	10-sub-pixel-bgr.conf \
	10-yes-antialias.conf \
	11-lcdfilter-default.conf \
	20-unhint-small-vera.conf \
	25-unhint-nonlatin.conf \
	30-metric-aliases.conf \
	35-lang-normalize.conf \
	40-nonlatin.conf \
	45-generic.conf \
	45-latin.conf \
	48-spacing.conf \
	49-sansserif.conf \
	50-user.conf \
	51-local.conf \
	60-generic.conf \
	60-latin.conf \
	65-fonts-persian.conf \
	65-khmer.conf \
	65-nonlatin.conf \
	69-unifont.conf \
	70-yes-bitmaps.conf \
	80-delicious.conf \
	90-synthetic.conf 
	ln -sf /System/Library/Frameworks/CoreText.framework/Resources/${f} ${BUILDROOT}/etc/fonts/conf.d/
.endfor

installresources: fmwk-install-hook fontresources

fmwk-install-hook:
.for dir in ${RAVYN_SDKROOT}/System/Library/Frameworks/ ${SYSROOT_DIR}/System/Library/Frameworks/
	mkdir -p ${dir}
	cp -Rfp ${.OBJDIR}/${FRAMEWORK}.framework ${dir}
.endfor
