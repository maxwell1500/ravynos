/* rcvtimeo.c -- prove SO_RCVTIMEO is honoured by the socket receive wait:
 * a blocking recvfrom on a socket that never receives must return
 * EWOULDBLOCK after roughly the requested timeout, not block forever.
 * Measured because the DHCP work had to fall back to O_NONBLOCK+poll.
 */
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(void)
{
    struct timeval tv = {0, 500000}; /* 500 ms */
    struct sockaddr_in sin;
    struct timespec t0, t1;
    char buf[64];
    double ms;
    int fd, rc;

    alarm(8); /* hard bound: a hang still ends the fixture */

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { printf("RCVTIMEO-FAIL socket: %s\n", strerror(errno)); return 1; }

    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons(18456);
    sin.sin_addr.s_addr = inet_addr("127.0.0.1");
    if (bind(fd, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
        printf("RCVTIMEO-FAIL bind: %s\n", strerror(errno));
        return 1;
    }
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
        printf("RCVTIMEO-FAIL setsockopt: %s\n", strerror(errno));
        return 1;
    }

    clock_gettime(CLOCK_MONOTONIC, &t0);
    rc = recvfrom(fd, buf, sizeof(buf), 0, NULL, NULL);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;

    if (rc >= 0) { printf("RCVTIMEO-FAIL unexpected data\n"); return 1; }
    if (errno != EWOULDBLOCK && errno != EAGAIN) {
        printf("RCVTIMEO-FAIL errno=%d (%s) after %.0f ms\n", errno, strerror(errno), ms);
        return 1;
    }
    if (ms < 350 || ms > 2000) {
        printf("RCVTIMEO-FAIL timeout %.0f ms (want ~500)\n", ms);
        return 1;
    }
    printf("RCVTIMEO-OK %.0f ms\n", ms);
    return 0;
}
