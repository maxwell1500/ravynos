/* filemmap.c -- check that file-backed mmap returns the file's real bytes.
 *
 * The Firefox content process renders its own glyphs from font data.  If
 * file mmap serves zero or stale pages, read()-based paths (CoreText/
 * FreeType inside the frameworks) still work while an mmap consumer gets
 * garbage, so the two observation channels disagree exactly the way the
 * text-bars symptom does.  This probe compares an mmap of a staged font
 * against pread() of the same file and prints the result to the serial
 * console as well as stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

int main(void) {
    FILE *con = fopen("/dev/console", "w");
    const char *path = "/System/Library/Fonts/TTF/NimbusRoman-Regular.ttf";
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(con ? con : stderr, "FILEMMAP open failed %s\n", path);
        return 1;
    }
    off_t len = lseek(fd, 0, SEEK_END);
    lseek(fd, 0, SEEK_SET);
    if (len <= 0) {
        fprintf(con ? con : stderr, "FILEMMAP size failed len=%lld\n", (long long)len);
        return 1;
    }

    char *mm = mmap(NULL, (size_t)len, PROT_READ, MAP_FILE | MAP_PRIVATE, fd, 0);
    if (mm == MAP_FAILED) {
        fprintf(con ? con : stderr, "FILEMMAP mmap failed len=%lld\n", (long long)len);
        return 1;
    }

    char *buf = malloc((size_t)len);
    if (buf == NULL || pread(fd, buf, (size_t)len, 0) != (ssize_t)len) {
        fprintf(con ? con : stderr, "FILEMMAP pread failed len=%lld\n", (long long)len);
        return 1;
    }

    long long bad = 0;
    long long first = -1;
    for (off_t i = 0; i < len; i++) {
        if (mm[i] != buf[i]) {
            bad++;
            if (first < 0)
                first = i;
        }
    }

    int headOK = mm[0] == 0 && mm[1] == 1 && mm[2] == 0 && mm[3] == 0;

    fprintf(con ? con : stdout,
        "FILEMMAP len=%lld mismatches=%lld first=%lld head=%02x%02x%02x%02x headOK=%d\n",
        (long long)len, bad, first,
        (unsigned char)mm[0], (unsigned char)mm[1],
        (unsigned char)mm[2], (unsigned char)mm[3], headOK);

    int rc = (bad == 0 && headOK) ? 0 : 1;
    fprintf(con ? con : stdout, "FILEMMAP verdict rc=%d\n", rc);
    return rc;
}
