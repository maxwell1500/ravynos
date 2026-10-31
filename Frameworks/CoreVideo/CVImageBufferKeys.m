/*
 * CoreVideo image buffer keys and values a stock application binds at load.
 *
 * XUL records kCVImageBuffer* as non-lazy strings; a missing one stops the
 * load.  Each constant is a real NSString with the documented value, so
 * attachment dictionaries behave as CoreVideo callers expect.
 */
#import <Foundation/Foundation.h>

NSString * const kCVImageBufferChromaLocationTopFieldKey = @"ChromaLocationTopField";
NSString * const kCVImageBufferChromaLocationBottomFieldKey = @"ChromaLocationBottomField";
NSString * const kCVImageBufferChromaLocation_Left = @"Left";
NSString * const kCVImageBufferColorPrimaries_ITU_R_2020 = @"ITU_R_2020";
NSString * const kCVImageBufferColorPrimaries_ITU_R_709_2 = @"ITU_R_709_2";
NSString * const kCVImageBufferTransferFunction_ITU_R_709_2 = @"ITU_R_709_2";
NSString * const kCVImageBufferYCbCrMatrix_ITU_R_2020 = @"ITU_R_2020";
NSString * const kCVImageBufferYCbCrMatrix_ITU_R_601_4 = @"ITU_R_601_4";
NSString * const kCVImageBufferYCbCrMatrix_ITU_R_709_2 = @"ITU_R_709_2";
