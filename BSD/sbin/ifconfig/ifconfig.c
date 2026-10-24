/*
 * ifconfig - configure network interface parameters
 *
 * Copyright (c) 2026 ravynOS Project
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <errno.h>

static void print_flags(short flags) {
    printf("flags=%x<", flags);
    int first = 1;
    if (flags & IFF_UP) { printf("%sUP", first ? "" : ","); first = 0; }
    if (flags & IFF_BROADCAST) { printf("%sBROADCAST", first ? "" : ","); first = 0; }
    if (flags & IFF_DEBUG) { printf("%sDEBUG", first ? "" : ","); first = 0; }
    if (flags & IFF_LOOPBACK) { printf("%sLOOPBACK", first ? "" : ","); first = 0; }
    if (flags & IFF_POINTOPOINT) { printf("%sPOINTOPOINT", first ? "" : ","); first = 0; }
    if (flags & IFF_RUNNING) { printf("%sRUNNING", first ? "" : ","); first = 0; }
    if (flags & IFF_MULTICAST) { printf("%sMULTICAST", first ? "" : ","); first = 0; }
    printf("> ");
}

static void show_interfaces(const char *target_if) {
    struct ifaddrs *ifap, *ifa;
    if (getifaddrs(&ifap) != 0) {
        perror("getifaddrs");
        return;
    }

    char last_name[IFNAMSIZ] = {0};

    for (ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
        if (target_if && strcmp(target_if, ifa->ifa_name) != 0)
            continue;

        if (strcmp(last_name, ifa->ifa_name) != 0) {
            if (last_name[0] != '\0')
                printf("\n");
            strncpy(last_name, ifa->ifa_name, IFNAMSIZ - 1);
            printf("%s: ", ifa->ifa_name);
            print_flags(ifa->ifa_flags);

            int s = socket(AF_INET, SOCK_DGRAM, 0);
            if (s >= 0) {
                struct ifreq ifr;
                memset(&ifr, 0, sizeof(ifr));
                strncpy(ifr.ifr_name, ifa->ifa_name, IFNAMSIZ - 1);
                if (ioctl(s, SIOCGIFMTU, &ifr) == 0) {
                    printf("mtu %d", ifr.ifr_mtu);
                }
                close(s);
            }
            printf("\n");
        }

        if (ifa->ifa_addr == NULL)
            continue;

        if (ifa->ifa_addr->sa_family == AF_INET) {
            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
            struct sockaddr_in *mask = (struct sockaddr_in *)ifa->ifa_netmask;
            struct sockaddr_in *broad = (struct sockaddr_in *)ifa->ifa_dstaddr;

            char ip_str[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &sin->sin_addr, ip_str, sizeof(ip_str));
            printf("\tinet %s", ip_str);

            if (mask) {
                printf(" netmask 0x%08x", ntohl(mask->sin_addr.s_addr));
            }
            if (broad && (ifa->ifa_flags & IFF_BROADCAST)) {
                char broad_str[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &broad->sin_addr, broad_str, sizeof(broad_str));
                printf(" broadcast %s", broad_str);
            }
            printf("\n");
        }
    }

    freeifaddrs(ifap);
}

int main(int argc, char *argv[]) {
    if (argc == 1 || (argc == 2 && strcmp(argv[1], "-a") == 0)) {
        show_interfaces(NULL);
        return 0;
    }
    const char *ifname = argv[1];

    if (argc == 2) {
        show_interfaces(ifname);
        return 0;
    }

    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) {
        perror("socket");
        return 1;
    }

    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);

    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "up") == 0) {
            if (ioctl(s, SIOCGIFFLAGS, &ifr) == 0) {
                ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
                if (ioctl(s, SIOCSIFFLAGS, &ifr) < 0)
                    perror("SIOCSIFFLAGS up");
            }
        } else if (strcmp(argv[i], "down") == 0) {
            if (ioctl(s, SIOCGIFFLAGS, &ifr) == 0) {
                ifr.ifr_flags &= ~IFF_UP;
                if (ioctl(s, SIOCSIFFLAGS, &ifr) < 0)
                    perror("SIOCSIFFLAGS down");
            }
        } else if (strcmp(argv[i], "netmask") == 0) {
            if (i + 1 < argc) {
                i++;
                struct sockaddr_in *sin = (struct sockaddr_in *)&ifr.ifr_addr;
                sin->sin_family = AF_INET;
                sin->sin_len = sizeof(struct sockaddr_in);
                inet_pton(AF_INET, argv[i], &sin->sin_addr);
                if (ioctl(s, SIOCSIFNETMASK, &ifr) < 0)
                    perror("SIOCSIFNETMASK");
            }
        } else {
            // Assume IP address
            struct sockaddr_in *sin = (struct sockaddr_in *)&ifr.ifr_addr;
            sin->sin_family = AF_INET;
            sin->sin_len = sizeof(struct sockaddr_in);
            if (inet_pton(AF_INET, argv[i], &sin->sin_addr) > 0) {
                if (ioctl(s, SIOCSIFADDR, &ifr) < 0)
                    perror("SIOCSIFADDR");
                // Auto bring up
                if (ioctl(s, SIOCGIFFLAGS, &ifr) == 0) {
                    ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
                    ioctl(s, SIOCSIFFLAGS, &ifr);
                }
            } else {
                fprintf(stderr, "Invalid parameter: %s\n", argv[i]);
            }
        }
    }

    close(s);
    return 0;
}
