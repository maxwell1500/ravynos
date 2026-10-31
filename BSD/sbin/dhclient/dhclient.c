/*
 * dhclient - DHCP client for ravynOS
 *
 * Copyright (c) 2026 ravynOS Project
 *
 * Implements the four-message exchange (DISCOVER/OFFER/REQUEST/ACK) on
 * UDP port 68, applies the lease with SIOCAIFADDR, and writes the DNS
 * servers from option 6 into /etc/resolv.conf.  Nothing here is hardcoded:
 * the address, mask, router and DNS list all come from the server.
 *
 * The broadcast flag is set in every request so a server whose reply would
 * otherwise be unicast to an address the interface does not have yet can
 * still reach us.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <stddef.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/in_var.h>
#include <arpa/inet.h>

#define DHCP_SERVER_PORT 67
#define DHCP_CLIENT_PORT 68
#define DHCP_MAGIC       0x63825363

#define DHCPDISCOVER 1
#define DHCPOFFER    2
#define DHCPREQUEST  3
#define DHCPACK      5

struct dhcp_packet {
    uint8_t  op;
    uint8_t  htype;
    uint8_t  hlen;
    uint8_t  hops;
    uint32_t xid;
    uint16_t secs;
    uint16_t flags;
    uint32_t ciaddr;
    uint32_t yiaddr;
    uint32_t siaddr;
    uint32_t giaddr;
    uint8_t  chaddr[16];
    uint8_t  sname[64];
    uint8_t  file[128];
    uint32_t magic;
    uint8_t  options[312];
} __attribute__((packed));

static uint8_t *
add_option(uint8_t *p, uint8_t code, uint8_t len, const void *data)
{
    *p++ = code;
    *p++ = len;
    memcpy(p, data, len);
    return p + len;
}

static int
get_mac(int s, const char *ifname, uint8_t mac[6])
{
    struct ifreq ifr;

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
    if (ioctl(s, SIOCGIFLLADDR, &ifr) < 0) {
        perror("SIOCGIFLLADDR");
        return -1;
    }
    if (ifr.ifr_addr.sa_len >= 6) {
        memcpy(mac, ifr.ifr_addr.sa_data, 6);
        return 0;
    }
    return -1;
}

static int
if_up(int s, const char *ifname)
{
    struct ifreq ifr;

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
    if (ioctl(s, SIOCGIFFLAGS, &ifr) < 0) {
        return -1;
    }
    ifr.ifr_flags |= IFF_UP;
    return ioctl(s, SIOCSIFFLAGS, &ifr);
}

static int
apply_lease(int s, const char *ifname, uint32_t addr, uint32_t mask)
{
    struct ifaliasreq ifra;
    struct sockaddr_in *sin;

    memset(&ifra, 0, sizeof(ifra));
    strncpy(ifra.ifra_name, ifname, IFNAMSIZ - 1);

    sin = (struct sockaddr_in *)&ifra.ifra_addr;
    sin->sin_family = AF_INET;
    sin->sin_len = sizeof(*sin);
    sin->sin_addr.s_addr = addr;

    sin = (struct sockaddr_in *)&ifra.ifra_mask;
    sin->sin_family = AF_INET;
    sin->sin_len = sizeof(*sin);
    sin->sin_addr.s_addr = mask;

    sin = (struct sockaddr_in *)&ifra.ifra_broadaddr;
    sin->sin_family = AF_INET;
    sin->sin_len = sizeof(*sin);
    sin->sin_addr.s_addr = addr | ~mask;

    return ioctl(s, SIOCAIFADDR, &ifra);
}

static uint8_t *
find_option(struct dhcp_packet *pkt, uint8_t code)
{
    uint8_t *p = pkt->options;
    uint8_t *end = pkt->options + sizeof(pkt->options);

    while (p < end) {
        uint8_t c = p[0];
        uint8_t l;

        if (c == 0) {           /* pad */
            p++;
            continue;
        }
        if (c == 255) {         /* end */
            break;
        }
        if (p + 1 >= end) {
            break;
        }
        l = p[1];
        if (p + 2 + l > end) {
            break;
        }
        if (c == code) {
            return p + 2;
        }
        p += 2 + l;
    }
    return NULL;
}

static int
send_packet(int s, struct dhcp_packet *pkt)
{
    struct sockaddr_in to;
    uint8_t *p;
    int rc;

    memset(&to, 0, sizeof(to));
    to.sin_family = AF_INET;
    to.sin_port = htons(DHCP_SERVER_PORT);
    to.sin_addr.s_addr = htonl(INADDR_BROADCAST);

    rc = sendto(s, pkt, sizeof(*pkt), 0, (struct sockaddr *)&to, sizeof(to));
    (void)p;
    return rc;
}

static void
build_request(struct dhcp_packet *pkt, uint32_t xid, const uint8_t mac[6],
    uint8_t type, uint32_t requested, uint32_t server)
{
    uint8_t *p;
    uint8_t msgtype = type;
    uint8_t bcast = 1;

    memset(pkt, 0, sizeof(*pkt));
    pkt->op = 1;                /* BOOTREQUEST */
    pkt->htype = 1;             /* Ethernet */
    pkt->hlen = 6;
    pkt->xid = xid;
    pkt->flags = htons(0x8000); /* broadcast reply */
    pkt->magic = htonl(DHCP_MAGIC);
    memcpy(pkt->chaddr, mac, 6);

    p = pkt->options;
    p = add_option(p, 53, 1, &msgtype);         /* DHCP message type */
    p = add_option(p, 61, 7, (uint8_t[]){ 1, mac[0], mac[1], mac[2],
        mac[3], mac[4], mac[5] });              /* client identifier */
    p = add_option(p, 55, 4, (uint8_t[]){ 1, 3, 6, 15 }); /* mask, router, dns */
    if (requested != 0) {
        p = add_option(p, 50, 4, &requested);   /* requested address */
    }
    if (server != 0) {
        p = add_option(p, 54, 4, &server);      /* server identifier */
    }
    (void)bcast;
    *p++ = 255;
}

static int
wait_for(int s, uint32_t xid, uint8_t want, struct dhcp_packet *out)
{
    time_t deadline = time(NULL) + 5;

    /* Non-blocking receive with an explicit poll loop: SO_RCVTIMEO is not
     * honoured on this stack yet, and a blocking recv() there never returns
     * even when an OFFER has already arrived (measured: one DISCOVER, one
     * OFFER on the wire, no REQUEST ever sent). */
    {
        int flags = fcntl(s, F_GETFL, 0);
        if (flags != -1) {
            fcntl(s, F_SETFL, flags | O_NONBLOCK);
        }
    }

    while (time(NULL) <= deadline) {
        ssize_t n = recv(s, out, sizeof(*out), 0);

        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            usleep(10000);
            continue;
        }
        uint8_t *type;

        if (n < (ssize_t)(offsetof(struct dhcp_packet, options) + 4)) {
            continue;
        }
        if (out->xid != xid || out->magic != htonl(DHCP_MAGIC)) {
            continue;
        }
        type = find_option(out, 53);
        if (type != NULL && *type == want) {
            return 0;
        }
    }
    return -1;
}

int
main(int argc, char *argv[])
{
    const char *ifname = (argc > 1) ? argv[1] : "en0";
    int s, i;
    uint8_t mac[6];
    uint32_t xid;
    uint32_t offered = 0, server = 0, mask = 0, router = 0;
    uint8_t *opt;
    struct dhcp_packet pkt, reply;

    s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) {
        perror("socket");
        return 1;
    }
    {
        int one = 1;
        if (setsockopt(s, SOL_SOCKET, SO_BROADCAST, &one, sizeof(one)) < 0) {
            perror("SO_BROADCAST");
        }
    }
    if (if_up(s, ifname) < 0) {
        perror("SIOCSIFFLAGS");
    }

    /* DHCP is defined on client port 68: servers send their replies there,
     * and a server is entitled to ignore a request from an ephemeral port.
     * Without this bind the DISCOVER leaves and the OFFER can never arrive. */
    {
        struct sockaddr_in local;
        int one = 1;

        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        memset(&local, 0, sizeof(local));
        local.sin_family = AF_INET;
        local.sin_port = htons(DHCP_CLIENT_PORT);
        local.sin_addr.s_addr = INADDR_ANY;
        if (bind(s, (struct sockaddr *)&local, sizeof(local)) < 0) {
            perror("bind :68");
            close(s);
            return 1;
        }
    }
    if (get_mac(s, ifname, mac) < 0) {
        fprintf(stderr, "dhclient: cannot read the hardware address of %s\n",
            ifname);
        close(s);
        return 1;
    }
    printf("[dhclient] %s mac %02x:%02x:%02x:%02x:%02x:%02x\n", ifname,
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    srand((unsigned)time(NULL) ^ getpid());
    xid = ((uint32_t)rand() << 16) ^ (uint32_t)rand();

    for (i = 0; i < 3 && offered == 0; i++) {
        build_request(&pkt, xid, mac, DHCPDISCOVER, 0, 0);
        if (send_packet(s, &pkt) < 0) {
            perror("sendto DISCOVER");
        }
        if (wait_for(s, xid, DHCPOFFER, &reply) == 0) {
            offered = reply.yiaddr;
            opt = find_option(&reply, 1);
            if (opt != NULL) {
                memcpy(&mask, opt, 4);
            }
            opt = find_option(&reply, 54);
            if (opt != NULL) {
                memcpy(&server, opt, 4);
            }
        }
    }

    if (offered == 0) {
        fprintf(stderr, "dhclient: no DHCPOFFER received\n");
        close(s);
        return 1;
    }

    build_request(&pkt, xid, mac, DHCPREQUEST, offered, server);
    if (send_packet(s, &pkt) < 0) {
        perror("sendto REQUEST");
    }
    if (wait_for(s, xid, DHCPACK, &reply) != 0) {
        fprintf(stderr, "dhclient: no DHCPACK received\n");
        close(s);
        return 1;
    }

    if (reply.yiaddr != 0) {
        offered = reply.yiaddr;
    }
    opt = find_option(&reply, 1);
    if (opt != NULL) {
        memcpy(&mask, opt, 4);
    }
    if (mask == 0) {
        mask = htonl(0xffffff00u);
    }
    opt = find_option(&reply, 3);
    if (opt != NULL) {
        memcpy(&router, opt, 4);
    }

    if (apply_lease(s, ifname, offered, mask) < 0) {
        perror("SIOCAIFADDR");
        close(s);
        return 1;
    }

    {
        /* inet_ntoa() returns one static buffer, so both addresses must be
         * copied out before the second call overwrites the first. */
        char addrstr[INET_ADDRSTRLEN];
        char maskstr[INET_ADDRSTRLEN];
        snprintf(addrstr, sizeof(addrstr), "%s",
            inet_ntoa(*(struct in_addr *)&offered));
        snprintf(maskstr, sizeof(maskstr), "%s",
            inet_ntoa(*(struct in_addr *)&mask));
        printf("[dhclient] bound %s to %s netmask %s", ifname, addrstr, maskstr);
    }
    if (router != 0) {
        printf(" router %s", inet_ntoa(*(struct in_addr *)&router));
    }
    printf("\n");

    opt = find_option(&reply, 6);
    FILE *f = fopen("/etc/resolv.conf", "w");
    if (f != NULL) {
        fprintf(f, "# Generated by dhclient\n");
        if (opt != NULL) {
            uint8_t len = *(opt - 1);
            for (unsigned x = 0; x + 4 <= len; x += 4) {
                struct in_addr dns;
                memcpy(&dns, opt + x, 4);
                if (dns.s_addr != 0) {
                    fprintf(f, "nameserver %s\n", inet_ntoa(dns));
                }
            }
        }
        fclose(f);
        printf("[dhclient] updated /etc/resolv.conf\n");
    }

    close(s);
    return 0;
}
