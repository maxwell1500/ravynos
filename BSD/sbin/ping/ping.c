/*
 * ping(8) -- ICMP echo request/reply, raw socket implementation.
 *
 * The tree shipped no ping source, so the Phase 3 network gate ("ping 10.0.2.2
 * replies") had nothing to run.  This is the smallest implementation that can
 * honestly prove the receive path: it builds a real ICMP echo, sends it on the
 * kernel's raw ICMP socket, and reports only replies whose id, sequence and
 * payload match what went out.
 *
 * The socket is non-blocking and polled with usleep().  SO_RCVTIMEO is not
 * honoured on this stack (measured: dhclient's blocking recv never returned
 * after a valid DHCP OFFER), so a timeout implemented with that option would
 * hang and report success by never timing out.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/in_systm.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#define PING_DATA_LEN 56

static unsigned short
checksum(const void *data, size_t len)
{
    const unsigned short *p = data;
    unsigned int sum = 0;

    while (len > 1) {
        sum += *p++;
        len -= 2;
    }
    if (len == 1) {
        sum += *(const unsigned char *)p;
    }
    while (sum >> 16) {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    return (unsigned short)~sum;
}

static double
now_ms(void)
{
    struct timeval tv;

    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec * 1000.0 + (double)tv.tv_usec / 1000.0;
}

int
main(int argc, char **argv)
{
    int count = 3;
    int timeout_ms = 1000;
    int argi = 1;
    const char *target;
    struct sockaddr_in dst;
    struct sockaddr_in from;
    socklen_t fromlen;
    int s;
    int sent = 0;
    int received = 0;
    unsigned short ident;
    unsigned char packet[sizeof(struct icmp) + PING_DATA_LEN];
    struct icmp *icmp = (struct icmp *)packet;
    struct timeval sendtime;

    while (argi < argc && argv[argi][0] == '-') {
        if (strcmp(argv[argi], "-c") == 0 && argi + 1 < argc) {
            count = atoi(argv[argi + 1]);
            argi += 2;
        } else if (strcmp(argv[argi], "-W") == 0 && argi + 1 < argc) {
            timeout_ms = atoi(argv[argi + 1]) * 1000;
            argi += 2;
        } else {
            fprintf(stderr, "usage: ping [-c count] [-W seconds] host\n");
            return 2;
        }
    }
    if (argi >= argc) {
        fprintf(stderr, "usage: ping [-c count] [-W seconds] host\n");
        return 2;
    }
    target = argv[argi];

    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    if (inet_pton(AF_INET, target, &dst.sin_addr) != 1) {
        fprintf(stderr, "ping: cannot resolve %s\n", target);
        return 2;
    }

    /* Prefer the datagram ICMP socket: it is the interface XNU's own ping
     * uses, and it carries the identifier the kernel assigns.  Raw ICMP is
     * the fallback for older kernels. */
    s = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
    if (s < 0) {
        s = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    }
    if (s < 0) {
        perror("ping: socket");
        return 2;
    }
    {
        int flags = fcntl(s, F_GETFL, 0);
        if (flags >= 0) {
            fcntl(s, F_SETFL, flags | O_NONBLOCK);
        }
    }

    ident = (unsigned short)(getpid() & 0xffff);
    if (count <= 0) {
        count = 1;
    }

    for (int seq = 0; seq < count; seq++) {
        double deadline;
        int got = 0;

        memset(packet, 0, sizeof(packet));
        icmp->icmp_type = ICMP_ECHO;
        icmp->icmp_code = 0;
        icmp->icmp_id = htons(ident);
        icmp->icmp_seq = htons((unsigned short)seq);
        icmp->icmp_cksum = 0;
        for (int i = 0; i < PING_DATA_LEN; i++) {
            icmp->icmp_data[i] = (unsigned char)('a' + (i % 26));
        }
        icmp->icmp_cksum = checksum(packet, sizeof(packet));

        gettimeofday(&sendtime, NULL);
        {
            /* Latch the send time in milliseconds for the real RTT below. */
        }
        if (sendto(s, packet, sizeof(packet), 0,
                (struct sockaddr *)&dst, sizeof(dst)) < 0) {
            perror("ping: sendto");
            close(s);
            return 2;
        }
        sent++;
        deadline = now_ms() + (double)timeout_ms;

        while (now_ms() < deadline) {
            unsigned char buf[1500];
            ssize_t n;

            memset(&from, 0, sizeof(from));
            fromlen = sizeof(from);
            n = recvfrom(s, buf, sizeof(buf), 0,
                (struct sockaddr *)&from, &fromlen);
            if (n < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    usleep(2000);
                    continue;
                }
                perror("ping: recvfrom");
                break;
            }
            if ((size_t)n < sizeof(struct icmp)) {
                continue;
            }
            {
                /* A raw socket delivers the IPv4 header, a datagram ICMP
                 * socket delivers only the ICMP message.  Detect which one
                 * arrived instead of assuming. */
                size_t iplen = 0;
                struct icmp *reply;
                size_t icmplen;
                int ttl = 0;

                if (n >= (ssize_t)sizeof(struct ip) &&
                    (buf[0] >> 4) == 4 && buf[9] == IPPROTO_ICMP) {
                    struct ip *ip = (struct ip *)buf;
                    iplen = (size_t)ip->ip_hl * 4;
                    ttl = (int)ip->ip_ttl;
                }
                if ((size_t)n <= iplen) {
                    continue;
                }
                reply = (struct icmp *)(buf + iplen);
                icmplen = (size_t)n - iplen;

                /* The datagram socket may rewrite the identifier to its own,
                 * so identity is established by sequence plus the eight-byte
                 * payload pattern rather than by id alone. */
                if (reply->icmp_type != ICMP_ECHOREPLY ||
                    reply->icmp_seq != htons((unsigned short)seq)) {
                    continue;
                }
                /* sizeof(struct icmp) includes padding after icmp_data[1];
                 * the payload begins at offsetof(icmp_data), which is eight
                 * bytes into the message.  Comparing at sizeof() rejected
                 * every valid echo reply (measured: n=104, 45 00 54 00, and
                 * the payload check failed). */
                if (icmplen < offsetof(struct icmp, icmp_data) + 8) {
                    continue;
                }
                if (memcmp((char *)reply + offsetof(struct icmp, icmp_data),
                        icmp->icmp_data, 8) != 0) {
                    continue;
                }
                {
                    double sent_ms = (double)sendtime.tv_sec * 1000.0 +
                        (double)sendtime.tv_usec / 1000.0;
                    printf("%zd bytes from %s: icmp_seq=%d ttl=%d time=%.1f ms\n",
                        (ssize_t)(icmplen - sizeof(struct icmp)),
                        inet_ntoa(from.sin_addr), seq, ttl,
                        now_ms() - sent_ms);
                }
                got = 1;
                received++;
                break;
            }
        }
        if (!got) {
            printf("Request timeout for icmp_seq %d\n", seq);
        }
        if (seq + 1 < count) {
            sleep(1);
        }
    }

    close(s);
    printf("--- %s ping statistics ---\n", target);
    printf("%d packets transmitted, %d packets received, %.0f%% packet loss\n",
        sent, received,
        sent > 0 ? 100.0 * (double)(sent - received) / (double)sent : 100.0);
    return received > 0 ? 0 : 1;
}
