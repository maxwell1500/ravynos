// dnstest.c -- resolve a hostname via getaddrinfo and print the first IPv4 hit.
// Proves /etc/hosts (fixture.test) resolves in-guest without involving Firefox.
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>

int main(int argc, char **argv) {
    const char *name = argc > 1 ? argv[1] : "fixture.test";
    struct addrinfo hints, *res = NULL, *p;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    int e = getaddrinfo(name, "8123", &hints, &res);
    if (e != 0) { printf("DNS-FAIL %s: %s\n", name, gai_strerror(e)); return 1; }
    for (p = res; p; p = p->ai_next) {
        char buf[64];
        struct sockaddr_in *a = (struct sockaddr_in *)p->ai_addr;
        if (p->ai_family != AF_INET) continue;
        inet_ntop(AF_INET, &a->sin_addr, buf, sizeof(buf));
        printf("DNS-OK %s -> %s\n", name, buf);
        freeaddrinfo(res);
        return 0;
    }
    printf("DNS-FAIL %s: no IPv4 result\n", name);
    freeaddrinfo(res);
    return 1;
}
