/* mousetest.c -- does the PS/2 mouse device ever deliver bytes?
 *
 * The WindowServer's cursor does not move under QEMU's injected mouse
 * events while injected keys do arrive, so either the i8042 aux path
 * carries no packets or the consumer drops them.  This probe reads
 * /dev/mouse non-blocking for three minutes and reports a byte count
 * once per second to the serial console; host-side mouse_move commands
 * sent during the window show up as a rising count.
 */
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <string.h>

int main(void) {
    FILE *con = fopen("/dev/console", "w");
    FILE *out = con ? con : stdout;
    int fd = open("/dev/mouse", O_RDONLY | O_NONBLOCK);
    if (fd < 0) {
        fprintf(out, "MOUSETEST open failed\n");
        return 1;
    }
    fprintf(out, "MOUSETEST reading /dev/mouse for 180s\n");

    long long total = 0;
    int last = 0;
    unsigned char sample[8];
    memset(sample, 0, sizeof(sample));
    time_t start = time(NULL);
    for (;;) {
        unsigned char buf[64];
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n > 0) {
            if (total < (long long)sizeof(sample))
                memcpy(sample + total, buf, (size_t)n < sizeof(sample) - (size_t)total
                       ? (size_t)n : sizeof(sample) - (size_t)total);
            total += n;
        }
        int now = (int)(time(NULL) - start);
        if (now != last) {
            last = now;
            fprintf(out, "MOUSETEST t=%ds bytes=%lld first=%02x %02x %02x %02x\n",
                    now, total, sample[0], sample[1], sample[2], sample[3]);
            if (now >= 180)
                break;
        }
        usleep(20000);
    }
    fprintf(out, "MOUSETEST done bytes=%lld\n", total);
    return 0;
}
