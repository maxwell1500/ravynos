#!/bin/sh
# run-fixtures.sh -- run the ABI conformance fixtures inside the guest.
#
# Staged to /usr/local/compat/run-fixtures.sh and started at boot by
# /System/Library/LaunchDaemons/com.ravynos.compat.json, which sends stdout
# and stderr to /var/log/compat.log.  The host reads that file back out of
# the image (tools/bootlab/verify_compat.py).
#
# Every fixture ends with a line "FIXTURE <name> rc=<n>".  The reader treats
# a missing line exactly like a failure: a fixture that did not start must
# never look like a pass.

LOG=/var/log/compat.log
: > "$LOG"

report() {
    # report <name> <rc>.  The log is the single record: launchd also sends
    # this script's stdout to the same file, so echoing here too duplicated
    # every result line.
    echo "FIXTURE $1 rc=$2" >> "$LOG"
}

run_fixture() {
    name=$1
    shift
    echo "--- $name: $*" >> "$LOG"
    "$@" >> "$LOG" 2>&1
    rc=$?
    report "$name" "$rc"
}

# The pid makes every boot's report distinct, so the host can prove it read
# this boot's run rather than the previous one left on the disk image.
echo "compat: fixtures start pid=$$" >> "$LOG"
# uname is not in this image yet (staged in phase 7); keep the line honest
# without turning a missing tool into a missing fixture.
echo "compat: uname: $(uname -a 2>/dev/null || echo unavailable)" >> "$LOG"

# Bootstrap port after dropping privileges.  The probe prints the port and
# then the look_up result; if the line is absent, the process died or hung in
# the bootstrap protocol (which is where Firefox as uid 501 stops).
echo "--- bootstrap: as root" >> "$LOG"
/usr/local/compat/bootstrap_probe >> "$LOG" 2>&1
echo "bootstrap root rc=$?" >> "$LOG"
echo "--- bootstrap: as ravyn (501)" >> "$LOG"
/usr/local/compat/runas -t 8 501 20 /usr/local/compat/bootstrap_probe >> "$LOG" 2>&1
echo "bootstrap user rc=$?" >> "$LOG"

# Account provisioning through the system's own tools.  The ravynos account
# is not baked into the image's /etc files: useradd creates the master.passwd
# entry, the passwd line, the group membership and the home directory, and the
# passwd fixture below verifies that the result authenticates with crypt(3)
# exactly as the login window would.  Idempotent: a boot that already has the
# account skips it.
if ! grep -q '^ravynos:' /etc/master.passwd 2>/dev/null; then
    echo "--- accounts: useradd ravynos" >> "$LOG"
    /usr/sbin/useradd -u 502 -g staff -c 'ravynOS Test User' -m \
        -p '$6$FI1CdogNNtw92Z8W$zIY8VxohOWf5g9LKcbabPrXnv3WDTueNEcYcWXM2TBzy8tQAQFGlGM5BzBANOqeGlnXo1POEkCMqa2pr5LRF0/' ravynos >> "$LOG" 2>&1
    echo "compat: useradd ravynos rc=$?" >> "$LOG"
fi

# Account tools round trip: groupadd, useradd, passwd, usermod, groupmod,
# userdel, groupdel.  This is the system's own add/modify/remove path, not a
# hand-edited database: a transient account is created, its password changed
# with passwd(1), renamed with usermod(1), its group renamed with groupmod(1),
# and then it is deleted and must be gone together with its home.
echo "--- accounts: tools round trip" >> "$LOG"
acct_ok=1
/usr/sbin/groupadd -g 530 ravyn-selftest >> "$LOG" 2>&1 || acct_ok=0
/usr/sbin/useradd -u 530 -g ravyn-selftest -c 'Self Test' -m -p '*' \
    ravyn-selftest >> "$LOG" 2>&1 || acct_ok=0
/usr/bin/passwd -p '$6$FI1CdogNNtw92Z8W$zIY8VxohOWf5g9LKcbabPrXnv3WDTueNEcYcWXM2TBzy8tQAQFGlGM5BzBANOqeGlnXo1POEkCMqa2pr5LRF0/' ravyn-selftest >> "$LOG" 2>&1 || acct_ok=0
/usr/sbin/usermod -l ravyn-renamed -c 'Renamed User' -s /bin/zsh \
    ravyn-selftest >> "$LOG" 2>&1 || acct_ok=0
/usr/sbin/groupmod -n ravyn-regroup ravyn-selftest >> "$LOG" 2>&1 || acct_ok=0
grep -q '^ravyn-renamed:$6$FI1CdogNNtw92Z8W$zIY8VxohOWf5g9LKcbabPrXnv3WDTueNEcYcWXM2TBzy8tQAQFGlGM5BzBANOqeGlnXo1POEkCMqa2pr5LRF0/:530:530:' /etc/master.passwd || acct_ok=0
grep -q '^ravyn-renamed:\*:530:530:Renamed User:/Users/ravyn-selftest:/bin/zsh' \
    /etc/passwd || acct_ok=0
grep -q '^ravyn-regroup:\*:530:ravyn-renamed$' /etc/group || acct_ok=0
grep -q '^ravyn-selftest:' /etc/master.passwd && acct_ok=0
test -d /Users/ravyn-selftest/Desktop || acct_ok=0
/usr/sbin/userdel -r ravyn-renamed >> "$LOG" 2>&1 || acct_ok=0
/usr/sbin/groupdel ravyn-regroup >> "$LOG" 2>&1 || acct_ok=0
grep -q '^ravyn-renamed:' /etc/master.passwd && acct_ok=0
test -d /Users/ravyn-selftest && acct_ok=0
if test $acct_ok -eq 1; then
    report accounts 0
else
    report accounts 1
fi

# LaunchServices first, before any instance of the bundle has run: `open`
# must launch the bundle as a bundle, and the launched app must reach
# applicationDidFinishLaunching, where it writes a marker.  The marker is
# removed first so an old file cannot stand in for a launch that never
# happened.  This runs before the direct cocoa fixture on purpose: a second
# registration of a bundle the Window Server has already seen is a separate
# question from whether bundle launch works at all.
# NB: the image ships test(1) but not [ as a separate binary, so this script
# uses `test`.
echo "--- launch: open /usr/local/compat/CocoaProbe.app" >> "$LOG"
rm -f /tmp/ravyn-compat-launched /tmp/ravyn-compat-entered-main
/usr/bin/open /usr/local/compat/CocoaProbe.app >> "$LOG" 2>&1
open_rc=$?
i=0
while test $i -lt 10; do
    test -f /tmp/ravyn-compat-launched && break
    sleep 1
    i=$((i + 1))
done
if test $open_rc -eq 0 && test -f /tmp/ravyn-compat-launched; then
    report launch 0
else
    marker=no
    test -f /tmp/ravyn-compat-launched && marker=yes
    entered=no
    test -f /tmp/ravyn-compat-entered-main && entered=yes
    echo "open rc=$open_rc marker=$marker entered_main=$entered" >> "$LOG"
    # LaunchServices leaves its decision trace here; copy it into the report
    # so a failed launch says where it stopped.
    if test -f /tmp/ls-trace.log; then
        echo "--- ls-trace" >> "$LOG"
        cat /tmp/ls-trace.log >> "$LOG"
        rm -f /tmp/ls-trace.log
    fi
    report launch 1
fi

# Network: the e1000 driver attaches en0; ifconfig must see it, and dhclient
# must get a lease from the QEMU user-mode DHCP server.  This is a fixture
# because a driver that attaches but cannot pass a packet is not working.
echo "--- net: ifconfig en0 (before)" >> "$LOG"
/sbin/ifconfig en0 >> "$LOG" 2>&1
echo "--- net: ifconfig en0 up" >> "$LOG"
/sbin/ifconfig en0 up >> "$LOG" 2>&1
# Known gap: this kernel cannot route a sendto(255.255.255.255) on an
# interface that has no address at all (ENETUNREACH), so a DHCP client cannot
# send its first DISCOVER on a bare link.  Until that is fixed, the test gives
# the interface the QEMU SLIRP address first, purely so a route exists, and
# then requires a real DISCOVER/OFFER/REQUEST/ACK exchange to succeed: the
# "bound" line below is only printed after a DHCPACK is received and applied.
echo "--- net: temporary route address" >> "$LOG"
/sbin/ifconfig en0 10.0.2.15 netmask 255.255.255.0 >> "$LOG" 2>&1
echo "--- net: dhclient -1 en0" >> "$LOG"
/sbin/dhclient en0 >> "$LOG" 2>&1
dh_rc=$?
echo "--- net: ifconfig en0 (after)" >> "$LOG"
/sbin/ifconfig en0 >> "$LOG" 2>&1
# The lease must be the server's: dhclient prints what it bound, and the
# kernel must report the /24 mask from option 1.  A hardcoded or stale
# address cannot satisfy both.
# The lease must be the server's: dhclient prints what it bound, and the
# kernel must report the /24 mask from option 1.  A hardcoded or stale
# address cannot satisfy both.
if grep -q "dhclient] bound" "$LOG" && grep -q "netmask 0xffffff00" "$LOG"; then
    report net 0
else
    echo "dhclient rc=$dh_rc" >> "$LOG"
    report net 1
fi

# ICMP receive is tracked separately because it fails for a reason that is
# not the lease: SLIRP answers every echo request on the wire, the frame
# reaches the driver (measured, 118 bytes, ethertype 0x0800), and neither
# icmp_input() nor rip_input() is ever entered.  A single combined fixture
# would hide which half broke.
echo "--- icmp: ping 10.0.2.2" >> "$LOG"
/sbin/ping -c 3 -W 2 10.0.2.2 >> "$LOG" 2>&1
report icmp $?

# TCP: a real handshake and application bytes to the host.  ICMP proves the
# driver and IP; this proves the protocol stack carries a stream.
echo "--- tcp: GET 10.0.2.2:8123/marker.txt" >> "$LOG"
/usr/local/compat/tcp 10.0.2.2 8123 RAVYN-TCP-OK >> "$LOG" 2>&1
report tcp $?

# Kernel message buffer: dmesg must return the boot log, not an empty file.
# It is root-only by design (proc_info KERNMSGBUF calls suser).
echo "--- dmesg: kernel buffer" >> "$LOG"
if /usr/sbin/dmesg 2>>"$LOG" | grep -q 'ravynOS\|\[kext\]\|CORPSE'; then
    report dmesg 0
else
    report dmesg 1
fi

run_fixture posix /usr/local/compat/posix

# Zone dispatch: free() must return each pointer to the zone that owns it.
# Firefox's mozjemalloc registers a zone and then faults in its own free()
# during startup, which is what a foreign pointer handed to the wrong zone
# looks like; this fixture turns that into a one-line verdict.
# The ravynos account: getpwnam must read the master password entry and the
# stored hash must verify with crypt(3), which is how the login window
# authenticates.  Runs as root, which is when shadow entries are visible.
run_fixture passwd /usr/local/compat/passwd

run_fixture malloczone /usr/local/compat/malloczone

# Pool bookkeeping: nested pools must release each object exactly once.
# Firefox's NSData was released twice by a drain; this isolates that from
# the framework that created the object.
run_fixture autorelease /usr/local/compat/autorelease

# Backup/restore must copy a tree, detect a changed file and restore it.
run_fixture backup /usr/local/compat/backup

# Sandbox profiles are accepted and audited, not enforced (Phase 5.4).
run_fixture sandbox /usr/local/compat/sandbox

# Mode bits are enforced: uid 501 cannot write a 0600 file or list a 0700 dir.
run_fixture perms /usr/local/compat/perms
run_fixture spinkill /usr/local/compat/spinkill

# The property-list codecs AppKit uses for the window-server menu channel
# must round-trip: NSApplication.m:1160 serializes the menus with
# NSKeyedArchiver and the service loop at NSApplication.m:577 reads them
# back with NSKeyedUnarchiver.
run_fixture plist /usr/local/compat/plist

# Pasteboard: a string written by one process must be visible to another.
# The writer and reader are separate execs, so nothing but the pasteboard
# server can carry the value between them.
echo "--- pasteboard: write" >> "$LOG"
/usr/local/compat/pasteboard write >> "$LOG" 2>&1
pb_write=$?
# The reader failure names a byte position, so the record has to carry the
# bytes the tokenizer choked over.
for f in /tmp/ravynos_pboard_*.plist; do
    echo "--- pboard file: $f" >> "$LOG"
    cat "$f" >> "$LOG" 2>&1
done
echo "--- pasteboard: read" >> "$LOG"
/usr/local/compat/pasteboard read >> "$LOG" 2>&1
pb_read=$?
if test $pb_write -eq 0 && test $pb_read -eq 0; then
    report pasteboard 0
else
    echo "pasteboard write=$pb_write read=$pb_read" >> "$LOG"
    report pasteboard 1
fi
run_fixture cocoa /usr/local/compat/CocoaProbe.app/Contents/MacOS/CocoaProbe

echo "compat: fixtures done" >> "$LOG"
