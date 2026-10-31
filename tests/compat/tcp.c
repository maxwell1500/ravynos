/*
 * tcp fixture -- prove that TCP over the DHCP-assigned address reaches the
 * host and carries application bytes both ways.
 *
 *   tcp <host> <port> <marker>
 *
 * The host side is a plain HTTP server started by tools/bootlab/verify_compat.py
 * on 127.0.0.1; QEMU's SLIRP presents it to the guest as the gateway address.
 * A pass means: connect() completed a handshake, the GET reached the server, and
 * the response body contained the marker the server was told to serve. ICMP and
 * UDP tests cannot produce that.
 *
 * Deliberately no libcurl: the tree has no curl sources (BSD/usr.bin/curl is a
 * Makefile pointing at a nonexistent contrib/curl), so this speaks HTTP/1.0
 * directly.  It says nothing about TLS; Firefox is the TLS oracle in Phase 4.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
    struct sockaddr_in dst;
    struct timeval tv;
    char request[256];
    char response[8192];
    size_t used = 0;
    int s;

    if (argc != 4) {
        fprintf(stderr, "usage: tcp host port marker\n");
        return 2;
    }

    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons((unsigned short)atoi(argv[2]));
    if (inet_pton(AF_INET, argv[1], &dst.sin_addr) != 1) {
        fprintf(stderr, "tcp: bad address %s\n", argv[1]);
        return 2;
    }

    s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) {
        perror("tcp: socket");
        return 2;
    }
    if (connect(s, (struct sockaddr *)&dst, sizeof(dst)) < 0) {
        perror("tcp: connect");
        close(s);
        return 1;
    }

    snprintf(request, sizeof(request),
        "GET /marker.txt HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n",
        argv[1]);
    if (send(s, request, strlen(request), 0) != (ssize_t)strlen(request)) {
        perror("tcp: send");
        close(s);
        return 1;
    }

    for (;;) {
        ssize_t n;

        tv.tv_sec = 5;
        tv.tv_usec = 0;
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(s, &rfds);
        n = select(s + 1, &rfds, NULL, NULL, &tv);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("tcp: select");
            close(s);
            return 1;
        }
        if (n == 0) {
            break;              /* server closed or stalled: keep what we have */
        }
        n = recv(s, response + used, sizeof(response) - 1 - used, 0);
        if (n < 0) {
            perror("tcp: recv");
            close(s);
            return 1;
        }
        if (n == 0) {
            break;
        }
        used += (size_t)n;
        if (used >= sizeof(response) - 1) {
            break;
        }
    }
    close(s);

    response[used] = '\0';
    if (used == 0) {
        fprintf(stderr, "tcp: server closed without a response\n");
        return 1;
    }
    if (strstr(response, argv[3]) == NULL) {
        fprintf(stderr, "tcp: response did not contain %s\n", argv[3]);
        return 1;
    }
    printf("PASS tcp-connect to %s:%s, %zu bytes, marker present\n",
        argv[1], argv[2], used);
    return 0;
}
