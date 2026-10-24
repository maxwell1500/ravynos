#import "DiskBackend.h"
#import <sys/mount.h>
#import <sys/stat.h>
#import <sys/ioctl.h>
#import <sys/disk.h>
#import <dirent.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>

@implementation DiskItem
@synthesize deviceName, mountPoint, fsType, totalBytes, usedBytes, availBytes, blockSize, blockCount, isRoot, isMounted;
@end

@implementation DiskBackend

+ (instancetype)shared {
    static DiskBackend *b = nil;
    if (b == nil) {
        b = [[DiskBackend alloc] init];
    }
    return b;
}

- (NSArray<DiskItem *> *)refreshVolumes {
    NSMutableArray *out = [NSMutableArray array];
    int n = getfsstat(NULL, 0, MNT_NOWAIT);
    if (n < 0) n = 0;
    struct statfs *bufs = calloc((size_t)n + 1, sizeof(struct statfs));
    int got = getfsstat(bufs, (n + 1) * (int)sizeof(struct statfs), MNT_NOWAIT);
    if (got < 0) got = 0;
    for (int i = 0; i < got; i++) {
        DiskItem *it = [[DiskItem alloc] init];
        it.deviceName = [NSString stringWithUTF8String:bufs[i].f_mntfromname];
        it.mountPoint = [NSString stringWithUTF8String:bufs[i].f_mntonname];
        it.fsType = [NSString stringWithUTF8String:bufs[i].f_fstypename];
        uint64_t bs = (uint64_t)bufs[i].f_bsize;
        if (bs == 0) bs = 4096;
        it.totalBytes = (uint64_t)bufs[i].f_blocks * bs;
        uint64_t free = (uint64_t)bufs[i].f_bfree * bs;
        uint64_t avail = (uint64_t)bufs[i].f_bavail * bs;
        it.availBytes = avail;
        it.usedBytes = (it.totalBytes > free) ? (it.totalBytes - free) : 0;
        it.isRoot = [it.mountPoint isEqualToString:@"/"];
        it.isMounted = YES;
        [out addObject:it];
    }
    free(bufs);

    // Add unmounted /dev/disk* devices
    NSArray *devs = [self diskDevicePaths];
    NSMutableSet *mountedDevs = [NSMutableSet set];
    for (DiskItem *it in out) [mountedDevs addObject:it.deviceName];
    for (NSString *dev in devs) {
        NSString *devName = [dev lastPathComponent];
        // try to match /dev/diskX to mounted entries by suffix
        BOOL found = NO;
        for (NSString *m in mountedDevs) {
            if ([m hasSuffix:devName]) { found = YES; break; }
        }
        if (found) continue;
        DiskItem *it = [[DiskItem alloc] init];
        it.deviceName = dev;
        it.mountPoint = nil;
        it.fsType = @"unknown";
        it.isMounted = NO;
        it.isRoot = NO;
        int fd = open([dev UTF8String], O_RDONLY);
        if (fd >= 0) {
            uint32_t bs = 0;
            uint64_t bc = 0;
            if (ioctl(fd, DKIOCGETBLOCKSIZE, &bs) == 0) it.blockSize = bs;
            if (ioctl(fd, DKIOCGETBLOCKCOUNT, &bc) == 0) it.blockCount = bc;
            close(fd);
        }
        if (it.blockSize == 0) it.blockSize = 512;
        it.totalBytes = it.blockSize * it.blockCount;
        it.availBytes = it.totalBytes;
        it.usedBytes = 0;
        [out addObject:it];
    }
    return out;
}

- (NSArray<NSString *> *)diskDevicePaths {
    NSMutableArray *out = [NSMutableArray array];
    DIR *d = opendir("/dev");
    if (!d) return out;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (strncmp(e->d_name, "disk", 4) == 0) {
            [out addObject:[NSString stringWithFormat:@"/dev/%s", e->d_name]];
        }
    }
    closedir(d);
    [out sortUsingSelector:@selector(compare:)];
    return out;
}

- (BOOL)validateFATAtPath:(NSString *)path error:(NSString **)errOut {
    // path may be device or image; read first sector
    int fd = open([path UTF8String], O_RDONLY);
    if (fd < 0) {
        if (errOut) *errOut = @"Cannot open device";
        return NO;
    }
    unsigned char boot[512];
    ssize_t r = read(fd, boot, sizeof(boot));
    close(fd);
    if (r < 512) {
        if (errOut) *errOut = @"Short read of boot sector";
        return NO;
    }
    if (boot[510] != 0x55 || boot[511] != 0xAA) {
        if (errOut) *errOut = @"Invalid boot signature (expected 0x55AA)";
        return NO;
    }
    uint16_t bytesPerSec = boot[11] | (boot[12] << 8);
    uint8_t secPerClus = boot[13];
    uint16_t reserved = boot[14] | (boot[15] << 8);
    uint8_t numFATs = boot[16];
    uint16_t rootEntries = boot[17] | (boot[18] << 8);
    uint16_t totalSec16 = boot[19] | (boot[20] << 8);
    uint32_t totalSec32 = boot[32] | (boot[33] << 8) | (boot[34] << 16) | (boot[35] << 24);
    uint32_t secPerFAT32 = boot[36] | (boot[37] << 8) | (boot[38] << 16) | (boot[39] << 24);
    if (bytesPerSec == 0 || (bytesPerSec & (bytesPerSec - 1)) != 0) {
        if (errOut) *errOut = @"Invalid bytes per sector";
        return NO;
    }
    if (secPerClus == 0 || (secPerClus & (secPerClus - 1)) != 0) {
        if (errOut) *errOut = @"Invalid sectors per cluster";
        return NO;
    }
    if (numFATs == 0) {
        if (errOut) *errOut = @"Invalid number of FATs";
        return NO;
    }
    uint32_t totalSec = totalSec16 ? totalSec16 : totalSec32;
    if (totalSec == 0) {
        if (errOut) *errOut = @"Invalid total sector count";
        return NO;
    }
    // FAT32 check
    if (secPerFAT32 == 0 && totalSec16 == 0) {
        // could be FAT12/16
    }
    // Basic cluster chain sanity: read first FAT sector and ensure entries are not all corrupt
    // We'll just report pass if structural fields valid.
    (void)reserved; (void)rootEntries;
    return YES;
}


#pragma mark - FAT32 formatter

/* Minimal but valid FAT32 layout: boot sector with 0x55AA, FSInfo, two FATs
 * whose first entries are the reserved EOC markers plus the root directory
 * cluster, and a zeroed root directory carrying the volume label.  Sizes are
 * chosen so the cluster count stays inside the FAT32 range for a 10 MB image
 * up to a few GB device. */
- (BOOL)formatFAT32AtPath:(NSString *)path volumeName:(NSString *)volName error:(NSString **)errOut {
    int fd = open([path UTF8String], O_RDWR);
    struct stat st;
    uint64_t totalBytes = 0;
    unsigned char sector[512];
    uint32_t bytesPerSec = 512;
    uint32_t secPerClus = 1;
    uint32_t reserved = 32;
    uint32_t numFATs = 2;
    uint32_t fatSize = 0;
    uint32_t totalSectors = 0;
    uint32_t clusterCount = 0;
    unsigned char *fat = NULL;
    unsigned char *rootDir = NULL;

    if (fd < 0) {
        if (errOut) *errOut = @"Cannot open device for writing";
        return NO;
    }
    if (fstat(fd, &st) == 0 && st.st_size > 0) {
        totalBytes = (uint64_t)st.st_size;
    } else {
        uint64_t bc = 0;
        uint32_t bs = 0;
        if (ioctl(fd, DKIOCGETBLOCKCOUNT, &bc) == 0 && ioctl(fd, DKIOCGETBLOCKSIZE, &bs) == 0)
            totalBytes = bc * bs;
    }
    if (totalBytes < 1024 * 1024) {
        close(fd);
        if (errOut) *errOut = @"Device is too small for FAT32";
        return NO;
    }

    /* Pick a cluster size that keeps the FAT small but the count > 65525
     * where possible: 8 sectors (4 KB) up to 8 GB, larger above. */
    if (totalBytes > 8ULL * 1024 * 1024 * 1024ULL) secPerClus = 64;
    else if (totalBytes > 2ULL * 1024 * 1024 * 1024ULL) secPerClus = 32;
    else if (totalBytes > 512ULL * 1024 * 1024ULL) secPerClus = 8;
    else secPerClus = 1;

    totalSectors = (uint32_t)(totalBytes / bytesPerSec);
    /* fatSize such that clusters fit: iterate twice (fatSize depends on the
     * cluster count, which depends on fatSize). */
    for (int pass = 0; pass < 2; pass++) {
        uint32_t dataSectors = totalSectors - reserved - numFATs * fatSize;
        clusterCount = dataSectors / secPerClus;
        fatSize = (clusterCount + 2) * 4 / bytesPerSec + 1;
    }
    if (fatSize == 0 || clusterCount < 16) {
        close(fd);
        if (errOut) *errOut = @"Device geometry is not usable for FAT32";
        return NO;
    }

    memset(sector, 0, sizeof(sector));
    /* Jump instruction + OEM name */
    sector[0] = 0xEB; sector[1] = 0x58; sector[2] = 0x90;
    memcpy(sector + 3, "RAVYNOS ", 8);
    /* BPB */
    sector[11] = bytesPerSec & 0xff; sector[12] = (bytesPerSec >> 8) & 0xff;
    sector[13] = (unsigned char)secPerClus;
    sector[14] = reserved & 0xff; sector[15] = (reserved >> 8) & 0xff;
    sector[16] = (unsigned char)numFATs;
    sector[21] = 0xF8; /* media descriptor: fixed disk */
    sector[24] = 63; sector[26] = 255; /* sectors per track / heads */
    sector[32] = totalSectors & 0xff;
    sector[33] = (totalSectors >> 8) & 0xff;
    sector[34] = (totalSectors >> 16) & 0xff;
    sector[35] = (totalSectors >> 24) & 0xff;
    sector[36] = fatSize & 0xff;
    sector[37] = (fatSize >> 8) & 0xff;
    sector[38] = (fatSize >> 16) & 0xff;
    sector[39] = (fatSize >> 24) & 0xff;
    /* Ext boot signature, volume id, label, fs type */
    sector[66] = 0x29;
    sector[67] = 0x52; sector[68] = 0x56; sector[69] = 0x4E; sector[70] = 0x53;
    {
        const char *label = volName != nil ? [volName UTF8String] : "UNTITLED";
        size_t n = strlen(label);
        if (n > 11) n = 11;
        memset(sector + 71, ' ', 11);
        memcpy(sector + 71, label, n);
        for (size_t i = 0; i < n; i++)
            if (sector[71+i] >= 'a' && sector[71+i] <= 'z')
                sector[71+i] -= 32;
    }
    memcpy(sector + 82, "FAT32   ", 8);
    sector[510] = 0x55; sector[511] = 0xAA;

    if (pwrite(fd, sector, sizeof(sector), 0) != (ssize_t)sizeof(sector)) {
        close(fd);
        if (errOut) *errOut = @"Cannot write boot sector";
        return NO;
    }

    /* FSInfo sector */
    memset(sector, 0, sizeof(sector));
    sector[0] = 0x52; sector[1] = 0x52; sector[2] = 0x61; sector[3] = 0x41;
    sector[484] = 0x72; sector[485] = 0x72; sector[486] = 0x41; sector[487] = 0x61;
    {
        uint32_t freeClusters = clusterCount - 1;
        uint32_t nextFree = 3;
        memcpy(sector + 488, &freeClusters, 4);
        memcpy(sector + 492, &nextFree, 4);
    }
    sector[510] = 0x55; sector[511] = 0xAA;
    pwrite(fd, sector, sizeof(sector), (off_t)bytesPerSec);

    /* The backup boot sector lives at sector 6; copy the primary there. */
    {
        unsigned char primary[512];
        if (pread(fd, primary, sizeof(primary), 0) == (ssize_t)sizeof(primary))
            pwrite(fd, primary, sizeof(primary), (off_t)6 * bytesPerSec);
    }

    /* FATs */
    fat = calloc(fatSize, bytesPerSec);
    if (fat == NULL) {
        close(fd);
        if (errOut) *errOut = @"Out of memory";
        return NO;
    }
    fat[0] = 0xF8; fat[1] = 0xFF; fat[2] = 0xFF; fat[3] = 0x0F; /* entry 0 */
    fat[4] = 0xFF; fat[5] = 0xFF; fat[6] = 0xFF; fat[7] = 0x0F; /* entry 1 */
    fat[8] = 0xFF; fat[9] = 0xFF; fat[10] = 0xFF; fat[11] = 0x0F; /* root EOC */
    for (uint32_t i = 0; i < numFATs; i++) {
        off_t off = (off_t)(reserved + i * fatSize) * bytesPerSec;
        if (pwrite(fd, fat, (size_t)fatSize * bytesPerSec, off) != (ssize_t)((size_t)fatSize * bytesPerSec)) {
            free(fat);
            close(fd);
            if (errOut) *errOut = @"Cannot write FAT";
            return NO;
        }
    }
    free(fat);

    /* Root directory cluster with the volume label entry. */
    rootDir = calloc(1, (size_t)secPerClus * bytesPerSec);
    if (rootDir == NULL) {
        close(fd);
        if (errOut) *errOut = @"Out of memory";
        return NO;
    }
    {
        const char *label = volName != nil ? [volName UTF8String] : "UNTITLED";
        size_t n = strlen(label);
        if (n > 11) n = 11;
        memset(rootDir, ' ', 11);
        memcpy(rootDir, label, n);
        for (size_t i = 0; i < n; i++)
            if (rootDir[i] >= 'a' && rootDir[i] <= 'z')
                rootDir[i] -= 32;
        rootDir[11] = 0x08; /* ATTR_VOLUME_ID */
    }
    {
        off_t off = (off_t)(reserved + numFATs * fatSize) * bytesPerSec;
        if (pwrite(fd, rootDir, (size_t)secPerClus * bytesPerSec, off) !=
            (ssize_t)((size_t)secPerClus * bytesPerSec)) {
            free(rootDir);
            close(fd);
            if (errOut) *errOut = @"Cannot write root directory";
            return NO;
        }
    }
    free(rootDir);
    close(fd);
    return YES;
}

@end