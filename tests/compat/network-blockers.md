# Network conformance state

Measured on the desktop image with `tools/bootlab/verify_compat.py`.

| fixture        | status | notes |
|----------------|--------|-------|
| net            | PASS   | interface enumeration + configuration |
| icmp           | PASS   | raw socket round trip |
| tcp            | PASS   | connect + read against the host harness |
| dns            | PASS   | `fixture.test` served from `/etc/hosts` by `file_module` |
| dns_external   | PASS   | `example.com` via the SLIRP nameserver, see below |
| download       | PASS   | http fetch |
| openurl        | PASS   | `NSWorkspace openURL:` finds the http handler |

## Why name resolution used to stop at `/etc/hosts`

`getaddrinfo` walked `cache -> file -> mdns`.  The `mdns` module needs
`DNSServiceQueryRecord`, which is answered by `mDNSResponder`; that daemon is
not part of this image, so the lookup returned `HOST_NOT_FOUND` for every name
that `/etc/hosts` did not contain.  There was no plain resolver path at all,
which is why no application could open a URL.

`Libsystem/libsystem_info/lookup.subproj/dns_module.c` adds one:

* `si_module_static_dns` resolves `libresolv.9.dylib` with `dlopen` (no link
  time dependency, so the library still loads when the dylib is absent) and
  uses `res_9_init` / `res_9_query`, i.e. the same resolver configuration that
  `/etc/resolv.conf` and the `res_9_*` calls already describe.
* `si_module.c` exports the module and `search_module.c` places `dns` between
  `file` and `mdns`, so hosts files still win, and the daemon-dependent path
  is only a fallback.

The resolver lives in its own module rather than inside `search_module` so that
a failing resolver can never take the whole lookup down with it: a module that
returns NULL just means "no answer from this source".
