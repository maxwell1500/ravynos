FRAMEWORK=QuartzCore
MK_WERROR = no
.include "../framework.common.mk"

SRCS= \
	CAAnimation.m \
	CAAnimationGroup.m \
	CABase.m \
	CABasicAnimation.m \
	CALayer.m \
	CALayerContext.m \
	CAMediaTimingFunction.m \
	CAPropertyAnimation.m \
	CATransaction.m \
	CATransactionGroup.m \
	CATransform3D.m \
	CATransition.m \
	CAValueFunction.m \
	CIAffineTransform.m \
	CIBloom.m \
	CIBoxBlur.m \
	CIColor.m \
	CIContext.m \
	CIFilter.m \
	CIImage.m \
	CILinearGradient.m \
	CIVector.m

HEADERS= \
	CAAction.h \
	CAAnimation.h \
	CAAnimationGroup.h \
	CABase.h \
	CABasicAnimation.h \
	CALayer.h \
	CALayerContext.h \
	CAMediaTiming.h \
	CAMediaTimingFunction.h \
	CAPropertyAnimation.h \
	CIBloom.h \
	CARenderer.h \
	CATransaction.h \
	CATransactionGroup.h \
	CATransform3D.h \
	CATransition.h \
	CAValueFunction.h \
	CAWindowOpenGLContext.h \
	CIAffineTransform.h \
	CIBoxBlur.h \
	CIColor.h \
	CIContext.h \
	CIFilter.h \
	CIImage.h \
	CILinearGradient.h \
	CIVector.h \
	CoreAnimation.h \
	CoreImage.h \
	CoreVideo.h \
	QuartzCore.h
RESOURCES=Info.plist English.lproj
CFLAGS+= ${FMWK_CFLAGS} -I${.CURDIR:H} \
	-I${OBJTOP}/Frameworks/Foundation/Headers \
        -I${OBJTOP}/Frameworks/AppKit/Headers \
	-I${RAVYN_SDKROOT}/usr/local/include/kernel \
	-I${RAVYN_SDKROOT}/usr/include/machine \
	-I${RAVYN_SDKROOT}/usr/include \
	-I${ROOT_SOURCE_DIR}/Kernel/xnu/bsd \
	-Wno-error=deprecated-objc-isa-usage





LDFLAGS+= ${FMWK_LDFLAGS} \



.include <rvn.framework.mk>

installresources: std_install_hook
