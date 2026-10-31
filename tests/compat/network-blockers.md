# Network blockers

One line per open defect, with the measurement that proves it. Remove the line
when its fixture goes green.

# Network status and gate notes

All conformance fixtures are green: `posix`, `cocoa`, `launch`, `pasteboard`,
`net` (DHCP lease), `icmp` (ping 10.0.2.2, 3/3 replies), `tcp` (HTTP GET to the
host over the leased address, marker verified). The defects below are recorded
because both were invisible until measured, and both will be reintroduced by
anyone who "simplifies" the receive path or rewrites ping.

## Phase 3.4 deviation: curl and scp cannot be built from this tree

The plan assumed the sources were present. They are not:

- `BSD/usr.bin/curl/` contains one Makefile that invokes
  `${OBJTOP}/tmp/usr/bin/cmake -S${SRCTOP}/contrib/curl`, and `contrib/curl`
  does not exist.
- `BSD/usr.bin/ssh/` contains only `Makefile`, `Makefile.depend` and
  `_PROVENANCE`; there are no `.c` files and no OpenSSL sources anywhere in
  `contrib/` (only expat, jansson, sqlite3).

So `curl https://…` and `scp` are not available to gate Phase 3 in this tree.
The gate is instead met with `tests/compat/tcp.c`: a stock Mach-O client built by
Apple's toolchain that completes a TCP handshake to 10.0.2.2 and verifies
application bytes (195-byte HTTP response containing `RAVYN-TCP-OK`), with the
host peer started by `verify_compat.py`. TLS is proven in Phase 4 by unmodified
Firefox, which is the project's stated TLS oracle; importing curl plus a TLS
library is a separate workstream and is not required for binary compatibility.

## Resolved: ICMP echo replies were freed as promiscuous

Symptom: `ping` sent a valid request, SLIRP returned a valid reply, the driver
received it (`rx len=118 ethertype=0x0800`), and no socket ever saw it.

Cause, proven with a probe in `ether_demux()`:

```
[edemux] data=00000000 dlen=0 dhost=00:00:00:00:00:00 ll=52:54:00:12:34:56 len=104 type=0000
[dlil] promisc drop len=104 fam=0 flags=2002
```

`mbuf_allocpacket()` returns a **zero-length packet-header mbuf with the frame
bytes chained after it**. The demux therefore read the link header from an empty
head, saw destination `00:00:00:00:00:00`, marked the packet `M_PROMISC`, and
`dlil_input_packet_list_common()` freed it before any protocol input. Broadcast
frames (DHCP) are exempt from that comparison, which is why `net` was green
while `icmp` was red.

Fix: the driver now builds RX packets as a header mbuf plus a cluster
(`mbuf_gethdr()` + `mbuf_getcluster()`), so the link header really is in the
packet head where `m_pkthdr.pkt_hdr` points. `mbuf_adj(14)` then leaves the IP
header at `m_data` and the header bytes intact behind it.

What does not work, and why: `mbuf_setdata()` after the copy leaves `m_len` at
0; restoring the header bytes by hand panicked at `ether_demux+0x39`
(`CR2 = 0xc`) because `mbuf_data()` was NULL; `mbuf_pullup()` in the driver
broke RX entirely.

## Resolved: ping rejected every valid reply

With delivery fixed, `ping` received `n=104` bytes beginning `45 00 54 00` and
still reported 100% loss. The payload check compared the reply at
`sizeof(struct icmp)`, which includes padding after `icmp_data[1]`, against a
send buffer whose payload begins at `offsetof(struct icmp, icmp_data)`. The four
byte skew failed every comparison. Both the length test and the `memcmp` now use
`offsetof`.

Result: `56 bytes from 10.0.2.2: icmp_seq=0 ttl=255 time=1.3 ms`, 3/3 replies,
`FIXTURE icmp rc=0`.

## Resolved: DHCP acquire (`net`)

DISCOVER/OFFER/REQUEST/ACK over the e1000, lease applied with `SIOCAIFADDR`.
Needed: `IFF_RUNNING` on link up, an Ethernet framer, the link header stripped
before `ip_input`, `rcvif` recorded on received packets, a broadcast source of
0.0.0.0 preserved until after the UDP checksum, and `in_selectsrc` accepting a
broadcast destination on an interface that has no address yet.
