#import <Foundation/Foundation.h>

/* Progress is reported through a plain C function pointer: the Objective-C
 * blocks runtime is not usable on this image (see libsystem_blocks/data.c). */
typedef void (*ArchiveProgressCallback)(void *context,
                                        NSString *entryName,
                                        long long bytesDone,
                                        long long totalBytes);

@interface ArchiveEngine : NSObject

// Extracts the archive at `archivePath` into an auto-determined directory.
// Returns YES on success; on failure `errorOut` receives a message.
+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                    progress:(ArchiveProgressCallback)progress
                     context:(void *)context
                       error:(NSString **)errorOut;

// Compresses the given paths into the zip at `destZipPath`.
+ (BOOL)compressPaths:(NSArray<NSString *> *)sourcePaths
          destination:(NSString *)destZipPath
             progress:(ArchiveProgressCallback)progress
              context:(void *)context
                error:(NSString **)errorOut;

@end
