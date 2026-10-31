/*
 * NSProgress constants a stock application links at load time.
 *
 * Firefox's XUL records _NSProgressKindFile and dyld refuses to load it when
 * the symbol is absent ("Symbol not found: _NSProgressKindFile").  ravynOS's
 * Foundation has no NSProgress implementation, but the *constant* is part of
 * the ABI: applications pass it as a plain NSString and compare it by
 * contents.  Defining the documented string keeps that working without
 * pretending progress reporting exists.
 */
#import <Foundation/Foundation.h>

NSString * const NSProgressKindFile = @"NSProgressKindFile";
NSString * const NSProgressFileOperationKindKey = @"NSProgressFileOperationKindKey";
NSString * const NSProgressFileOperationKindCopying = @"NSProgressFileOperationKindCopying";
NSString * const NSProgressFileOperationKindDownloading = @"NSProgressFileOperationKindDownloading";
NSString * const NSProgressFileOperationKindDecompressingAfterDownloading = @"NSProgressFileOperationKindDecompressingAfterDownloading";
NSString * const NSProgressFileOperationKindReceiving = @"NSProgressFileOperationKindReceiving";
NSString * const NSProgressFileOperationKindUploading = @"NSProgressFileOperationKindUploading";
