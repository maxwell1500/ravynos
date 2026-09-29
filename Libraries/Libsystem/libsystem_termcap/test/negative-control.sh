#!/bin/bash
# The negative control for libsystem_termcap's test suite.
#
# A suite where every test passes on a broken implementation is worth nothing:
# it cannot tell a working termcap from a wrong one. This script proves the
# suite can, by breaking the implementation in six specific ways and requiring
# the suite to go RED on each.
#
# Each mutation is a real defect this component could plausibly ship:
#
#   1. `ce' points at the wrong control function (ED instead of EL)
#   2. `ch' loses its %i, so a 1-based column becomes 0-based
#   3. `RI' gains an %i it must not have, so a distance becomes off-by-one
#   4. tgetflag() answers "yes" to everything
#   5. tgetnum() answers 0 instead of -1 for a capability that is not there
#   6. tgoto() silently drops an unknown conversion instead of refusing
#
# and one structural mutation that is the failure this project has actually
# produced before:
#
#   7. the VT100 entry's `am' capability is dropped, which is invisible to
#      every single tgetstr check and must be caught by the boolean checks
#
# Every mutation is applied to a COPY of termcap.c in a scratch directory. The
# tree is never modified.
#
# The positive control is the same script's first step: the pristine source
# must exit 0. Without that, "the mutant failed" could just mean "the harness
# is broken", which is the failure mode a negative control exists to rule out.
#
# Exit 0 means: the pristine build passed AND every mutant was caught.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$HERE/.." && pwd)"
WORK=${WORK:-/tmp/ravyn-termcap-negctl}
CC=${HOST_CC:-xcrun clang}
CFLAGS="-std=gnu11 -g -O0 -Wall -I$TOP -I$HERE"

unset DEVELOPER_DIR || true
rm -rf "$WORK"; mkdir -p "$WORK"

rc=0
caught=0
total=0

run_suite() {   # run_suite <label> <termcap.c>
	local label=$1 src=$2
	local bin="$WORK/t-$label"

	# shellcheck disable=SC2086
	$CC $CFLAGS -o "$bin" "$HERE/test-termcap.c" "$src" 2>"$WORK/$label.buildlog"
	if [ $? -ne 0 ]; then
		echo "  $label: did not even COMPILE -- counts as caught"
		sed 's/^/      /' "$WORK/$label.buildlog" | head -5
		return 1
	fi
	"$bin" >"$WORK/$label.out" 2>&1
	return $?
}

expect_red() {  # expect_red <label> <must-mention regexp>
	local label=$1 mention=$2
	total=$((total + 1))
	if run_suite "$label" "$WORK/$label.c"; then
		echo "  MISSED  $label: the suite still passed on a broken build"
		rc=1
		return
	fi
	caught=$((caught + 1))
	echo "  caught  $label  ($(grep -c '^  FAIL' "$WORK/$label.out") failing checks)"
	if [ -n "$mention" ] && ! grep -qE "$mention" "$WORK/$label.out"; then
		echo "          ...but for an unexpected reason; no check mentioned /$mention/"
		rc=1
	fi
}

echo "== positive control: the pristine source must pass"
if run_suite pristine "$TOP/termcap.c"; then
	echo "  ok      pristine: $(grep -c '^  PASS' "$WORK/pristine.out") checks pass, exit 0"
else
	echo "  BROKEN  the pristine suite does not pass; every result below is void"
	grep '^  FAIL' "$WORK/pristine.out" | sed 's/^/      /'
	exit 1
fi
if [ "$(grep -c '^  FAIL' "$WORK/pristine.out")" -ne 0 ]; then
	echo "  BROKEN  the pristine suite printed FAIL lines but exited 0"
	exit 1
fi

echo
echo "== mutations: each of these must turn the suite red"

# 1. `ce' pointed at ED instead of EL.
sed 's|"ce=\\\\E\[K:"|"ce=\\\\E[J:"|' "$TOP/termcap.c" > "$WORK/m1.c"
expect_red m1 'libedit cap ce +value'

# 2. `ch' loses its %i: CHA is 1-based, so column 5 is ESC [ 6 G, not ESC [ 5 G.
sed 's|"ch=\\\\E\[%i%dG:"|"ch=\\\\E[%dG:"|' "$TOP/termcap.c" > "$WORK/m2.c"
expect_red m2 'tgoto\("ch"'

# 3. `RI' gains the %i it must not have.
sed 's|"RI=\\\\E\[%dC:"|"RI=\\\\E[%i%dC:"|' "$TOP/termcap.c" > "$WORK/m3.c"
expect_red m3 'tgoto\("RI"'

# 4. tgetflag says yes to everything.
sed 's|\treturn (tc_find(tc_cur->caps, id, \&f) != NULL);|\treturn (1);|' \
    "$TOP/termcap.c" > "$WORK/m4.c"
expect_red m4 'libedit cap xn|libedit cap xt'

# 5. tgetnum says 0 instead of -1 for an absent capability.
python3 - "$TOP/termcap.c" "$WORK/m5.c" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
old = """	if (tc_cur == NULL || tc_find(tc_cur->caps, id, &f) == NULL || !f.isnum)
		return (-1);"""
new = """	if (tc_cur == NULL || tc_find(tc_cur->caps, id, &f) == NULL || !f.isnum)
		return (0);"""
assert old in src, "mutation 5 anchor not found -- termcap.c has moved on"
open(sys.argv[2], "w").write(src.replace(old, new))
PYEOF
expect_red m5 'tgetnum of an absent cap is -1'

# 6. tgoto drops an unknown conversion instead of refusing it.
python3 - "$TOP/termcap.c" "$WORK/m6.c" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
old = """			if (!tc_isdigit(*p)) {
				/*
				 * A conversion this component does not
				 * implement. Say so; do not approximate it.
				 */
				return (NULL);
			}"""
new = """			if (!tc_isdigit(*p)) {
				p++;	/* pretend we understood it */
				break;
			}"""
assert old in src, "mutation 6 anchor not found -- termcap.c has moved on"
open(sys.argv[2], "w").write(src.replace(old, new))
PYEOF
expect_red m6 'is refused'

# 7. The `am' capability is dropped. Nothing that reads a STRING can see this.
sed 's|^\t"am:"\t\t\t/\* boolean: DECAWM, wraps at the right margin \*/$||' \
    "$TOP/termcap.c" > "$WORK/m7.c"
expect_red m7 'libedit cap am'

echo
echo "negative control: $caught of $total mutations caught"
if [ "$caught" -ne "$total" ]; then
	echo "negative control: FAIL -- the suite does not discriminate"
	rc=1
else
	echo "negative control: PASS -- the suite fails on every deliberate break"
fi
exit "$rc"
