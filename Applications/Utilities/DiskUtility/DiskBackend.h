#import <Foundation/Foundation.h>

@interface DiskItem : NSObject
@property (copy) NSString *deviceName;
@property (copy) NSString *mountPoint;
@property (copy) NSString *fsType;
@property (assign) uint64_t totalBytes;
@property (assign) uint64_t usedBytes;
@property (assign) uint64_t availBytes;
@property (assign) uint64_t blockSize;
@property (assign) uint64_t blockCount;
@property (assign) BOOL isRoot;
@property (assign) BOOL isMounted;
@end

@interface DiskBackend : NSObject
+ (instancetype)shared;
- (NSArray<DiskItem *> *)refreshVolumes;
- (NSArray<NSString *> *)diskDevicePaths;
- (BOOL)validateFATAtPath:(NSString *)path error:(NSString **)errOut;
/* Write a FAT32 filesystem onto an image file or block device.  No external
 * newfs_msdos exists in the image, so Disk Utility formats in process. */
- (BOOL)formatFAT32AtPath:(NSString *)path volumeName:(NSString *)volName error:(NSString **)errOut;
@end