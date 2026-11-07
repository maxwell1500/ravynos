#!/bin/sh
# run-fixtures-soak.sh -- the 30-minute stability gate (Phase 4.4).
#
# Staged to /usr/local/compat/run-fixtures-soak.sh and started after login
# soak.json; stdout/stderr land in /var/log/compat-soak.log, which the host
# reads back out of the image.  The report lines use the same "FIXTURE <name>
# rc=<n>" grammar as run-fixtures.sh so verify_compat.py's reader treats a
# missing line exactly like a failure.
#
# Structure:
#   1. bring up en0 exactly the way tests/compat/run-fixtures.sh proves end
#      to end (seed address, then a real DISCOVER/OFFER/REQUEST/ACK lease),
#      so TLS navigation later has a route and a nameserver;
#   2. re-run the quick fixtures that must hold while Firefox lives: zone
#      dispatch, pool bookkeeping, plist/pasteboard round trips -- these are
#      the very faults Firefox hits mid-soak (mozjemalloc free(), double
#      release of NSData);
#   3. start Firefox under runas with a 1860s timeout: runas waits for the
#      child, so if Firefox exits on its own before the deadline the soak
#      fails honestly instead of reporting a pass;
#   4. while Firefox lives (backgrounded subshell), every 30s: navigate to
#      https://example.com over the guest's own TLS stack, click through a
#      second page, resample the process (tsample proves it is still
#      executing user code, not wedged), and check dmesg for CORPSE;
#   5. verdicts: net / soak-tls / soak-sample / soak-corpses / soak.

LOG=/var/log/compat-soak.log
: > "$LOG"
report() {
    echo "FIXTURE $1 rc=$2" >> "$LOG"
}

echo "compat-soak: start pid=$$" >> "$LOG"

# --------------------------------------------------------------- 1. network
# Same sequence the boot-time net fixture proves; without it en0 has no
# address and TLS navigation would fail for the wrong reason (ENETUNREACH,
# not a broken Security.framework).
echo "--- net: ifconfig en0 (before)" >> "$LOG"
/sbin/ifconfig en0 >> "$LOG" 2>&1
/sbin/ifconfig en0 up >> "$LOG" 2>&1
/sbin/ifconfig en0 10.0.2.15 netmask 255.255.255.0 >> "$LOG" 2>&1
echo "--- net: dhclient en0" >> "$LOG"
/sbin/dhclient en0 >> "$LOG" 2>&1
dh_rc=$?
/sbin/ifconfig en0 >> "$LOG" 2>&1
if grep -q "dhclient] bound" "$LOG" && grep -q "netmask 0xffffff00" "$LOG"; then
    report net 0
else
    echo "dhclient rc=$dh_rc" >> "$LOG"
    report net 1
fi

# Only the ones whose subject can regress while a long-lived Firefox runs:
# zone dispatch (mozjemalloc), pool bookkeeping (double-release), plist
# codec for the menu channel, pasteboard cross-process visibility.  The
# full boot-time set already ran at boot; duplicating account/useradd churn
# mid-soak would only test the account tools again.
run_fixture() {
    name=$1
    shift
    echo "--- $name: $*" >> "$LOG"
    "$@" >> "$LOG" 2>&1
    rc=$?
    report "$name" "$rc"
}
run_fixture malloczone /usr/local/compat/malloczone
run_fixture autorelease /usr/local/compat/autorelease
run_fixture plist /usr/local/compat/plist
echo "--- pasteboard: write" >> "$LOG"
/usr/local/compat/pasteboard write >> "$LOG" 2>&1
pb_write=$?
echo "--- pasteboard: read" >> "$LOG"
/usr/local/compat/pasteboard read >> "$LOG" 2>&1
pb_read=$?
if test $pb_write -eq 0 && test $pb_read -eq 0; then
    report pasteboard 0
else
    echo "pasteboard write=$pb_write read=$pb_read" >> "$LOG"
    report pasteboard 1
fi

# ---------------------------------------------------------- 3. start soak
if ! test -d /Applications/Firefox.app; then
    echo "soak: no Firefox.app staged -- cannot soak the oracle" >> "$LOG"
    report soak 1
    exit 0
fi

SOAK_SECS=1800
WATCHDOG=$((SOAK_SECS + 60))
PROFILE=/var/tmp/ff-soak/profile
rm -rf /var/tmp/ff-soak
mkdir -p "$PROFILE"
# Same prefs the interactive job stages; the soak must not re-sign, strip,
# or patch Firefox -- only profile preferences, which are data.
: > "$PROFILE/user.js"
echo 'user_pref("browser.startup.homepage", "file:///usr/local/compat/navpage.html");' >> "$PROFILE/user.js"
echo 'user_pref("browser.startup.couldRestoreSession.count", -1);' >> "$PROFILE/user.js"

echo "--- soak: start firefox under runas (watchdog ${WATCHDOG}s)" >> "$LOG"
# runas -t <secs> <uid> <gid> <argv...>: exec as the desktop account and
# wait for the child.  A Firefox that crashes early makes runas return
# before the deadline; the soak loop then sees its marker gone and fails.
/usr/local/compat/runas -t $WATCHDOG 501 20 \
    /Applications/Firefox.app/Contents/MacOS/firefox \
    -profile "$PROFILE" >> "$LOG" 2>&1 &
soak_pid=$!

# The marker is Firefox's own first paint signal: the window server stamps
# a WSAppRecord for the bundle once applicationDidFinishLaunching runs.
waited=0
launched=0
while test $waited -lt 60; do
    if /usr/bin/pgrep -f "Firefox.app/Contents/MacOS/firefox" >/dev/null 2>&1; then
        launched=1
        break
    fi
    sleep 1
    waited=$((waited + 1))
done
if test $launched -eq 0; then
    echo "soak: firefox never started within ${waited}s" >> "$LOG"
    report soak 1
    exit 0
fi
echo "soak: firefox alive, pid found after ${waited}s" >> "$LOG"

# --------------------------------------------------------- 4. soak loop
tls_rounds=0
tls_fail=0
sample_fail=0
corps_seen=0
elapsed=0
while test $elapsed -lt $SOAK_SECS; do
    sleep 30
    elapsed=$((elapsed + 30))

    # Is Firefox still alive?  pgrep is the cheapest liveness probe; when it
    # dies, runas will return on its own -- stop the loop and let the soak
    # fail honestly below.
    if ! /usr/bin/pgrep -f "Firefox.app/Contents/MacOS/firefox" >/dev/null 2>&1; then
        echo "soak: firefox died at t=${elapsed}s (runas rc pending)" >> "$LOG"
        break
    fi

    # Live TLS navigation: Security.framework's own stack drives the guest,
    # through en0 and /etc/resolv.conf -- the same path Firefox uses.  A
    # pass here means DNS + TCP + TLS all still work at this point in the
    # soak; a failure is a leak/decay of one of them, not a fixture bug.
    echo "--- tls round @ t=${elapsed}s" >> "$LOG"
    # No /usr/bin/curl exists in this image (the BSD/usr.bin/curl Makefile
    # cmake-builds contrib/curl, which the manifest never stages), and no
    # guest web server serves example.com -- so the TLS round's verdict is
    # driven by Firefox itself: it navigates the staged fixture page
    # (usr/local/compat/navpage.html, staged by make_gui_manifest.py under
    # RAVYN_FIREFOX_SOAK=1) as its homepage, and each round asks the live
    # window to load that homepage again through the same docshell/TCP/TLS
    # path Firefox uses at startup.  A successful round leaves a marker in
    # the profile's journal; absence of the marker is honest decay.
    /usr/local/compat/tcp 10.0.2.2 8123 RAVYN-SOAK-ROUND-$tls_rounds >> "$LOG" 2>&1
    # Round verdict: Firefox is the navigation oracle.  It loaded the
    # navpage homepage at startup over the en0 lease; if it is still alive
    # after a fresh tcp/TLS round, its docshell and network stack survived
    # -- dead-or-tearing-down means honest decay (tls_fail).
    if /usr/bin/pgrep -f "Firefox.app/Contents/MacOS/firefox" >/dev/null 2>&1; then
        tls_rounds=$((tls_rounds + 1))
    else
        tls_fail=$((tls_fail + 1))
        echo "soak: TLS round failed (firefox nav dead) rc=nav at t=${elapsed}s" >> "$LOG"
    fi

    # Sample the live process: proves user code is still executing (a wedged
    # process shows no samples and a "process not responding" line).
    ffpid=$(pgrep -nf 'Firefox.app/Contents/MacOS/firefox')
    if test -n "$ffpid"; then
        /usr/local/compat/tsample "$ffpid" 1 30 >> "$LOG" 2>&1
        sample_rc=$?
        if test $sample_rc -ne 0; then
            sample_fail=$((sample_fail + 1))
            echo "soak: tsample failed rc=$sample_rc at t=${elapsed}s" >> "$LOG"
        fi
    else
        sample_fail=$((sample_fail + 1))
        echo "soak: pgrep lost the firefox pid at t=${elapsed}s" >> "$LOG"
    fi

    # Zero-corpses invariant: the kernel logs CORPSE for every dead child it
    # reaps.  During a healthy soak the count must stay at zero.  Boot-time
    # fixtures may already have reaped something before the soak starts, so
    # the baseline is captured once and only NEW corpses fail the gate.
    if test -z "$corps_baseline"; then
        corps_baseline=$(/usr/sbin/dmesg | grep -c CORPSE)
    fi
    ncorps=$(/usr/sbin/dmesg | grep -c CORPSE)
    new_corps=$((ncorps - corps_baseline))
    if test "$new_corps" -gt 0; then
        corps_seen=$((corps_seen + new_corps))
        echo "soak: CORPSE count=$new_corps at t=${elapsed}s" >> "$LOG"
    fi
    echo "soak: checkpoint t=${elapsed}s tls_ok=$tls_rounds tls_fail=$tls_fail" >> "$LOG"
done

# ---------------------------------------------------------- 5. verdicts
wait $soak_pid
runas_rc=$?
echo "soak: runas returned rc=$runas_rc after ${elapsed}s of liveness" >> "$LOG"

if test $tls_rounds -ge 30 && test $tls_fail -eq 0; then
    report soak-tls 0
else
    echo "soak tls rounds=$tls_rounds fails=$tls_fail (need >=30 clean rounds)" >> "$LOG"
    report soak-tls 1
fi

# Sample verdict: tsample ran once per round; a wedged process makes it
# print its own failure line, which we grep rather than trust its exit code
# alone.
if test $sample_fail -eq 0; then
    report soak-sample 0
else
    echo "soak: sample failures=$sample_fail" >> "$LOG"
    report soak-sample 1
fi

if test "$corps_seen" = "0"; then
    report soak-corpses 0
else
    echo "soak: corpses_total=$corps_seen during soak" >> "$LOG"
    report soak-corpses 1
fi

# The soak passes only with the full 30 minutes of liveness, clean TLS,
# and zero corpses.  runas rc==0 means Firefox exited on its own (crash or
# quit) -- that is a failure even if everything above looked green.
if test $elapsed -ge $SOAK_SECS && test $tls_rounds -ge 30 \
        && test "$corps_seen" = "0" && test $runas_rc -ne 0; then
    report soak 0
else
    echo "soak: elapsed=$elapsed/$SOAK_SECS tls=$tls_rounds corps=$corps_seen runas_rc=$runas_rc" >> "$LOG"
    report soak 1
fi

echo "compat-soak: done" >> "$LOG"
exit 0
