#import <QuartzCore/CATransform3D.h>

const CATransform3D CATransform3DIdentity = {1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1};

CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz) {
    CATransform3D t = CATransform3DIdentity;
    t.m11 = sx;
    t.m22 = sy;
    t.m33 = sz;
    return t;
}