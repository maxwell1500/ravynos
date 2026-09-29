#!/bin/bash
# Differential + behavioural test for the fresh wc and tr.
#
# Every case is run through BOTH the ravynOS build and the host's
# /usr/bin/<prog>, and the two outputs compared byte for byte. A divergence
# is printed as a DIVERGENCE line and counted separately: the host is the
# more trustworthy oracle, so a disagreement is a finding to be reported,
# not something to be quietly reconciled.
#
# Usage:  BSD/usr/bin/verify-ravyn-wc-tr.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$HERE/../.." && pwd)
# The programs under test: prefer the --host-only build, which is the one
# that can actually be executed on this machine.
BIN=${BIN:-/tmp/ravyn-utils-host/bin}
SYSHELPER=/usr/bin:/bin

[ -x "$BIN/wc" ] || { echo "need $BIN/wc -- run build-ravynos-utils.sh --host-only"; exit 1; }
[ -x "$BIN/tr" ] || { echo "need $BIN/tr -- run build-ravynos-utils.sh --host-only"; exit 1; }

PASS=0; FAIL=0; DIVERGE=0
DLINES=""
W=$(PATH=$SYSHELPER mktemp -d)
trap 'PATH=$SYSHELPER rm -rf "$W"' EXIT

hex() { PATH=$SYSHELPER od -An -tx1 | PATH=$SYSHELPER tr -d ' \n'; }

# cmp_case <label> <stdin-file> <args...>
# Runs both, compares stdout bytes and exit status.
cmp_case() {
	local label=$1 input=$2; shift 2
	local ours theirs ourrc theirrc

	ours=$("$BIN/$PROG" "$@" < "$input" 2>/dev/null | hex)
	ourrc=$?
	theirs=$(PATH=$SYSHELPER "/usr/bin/$PROG" "$@" < "$input" 2>/dev/null | hex)
	theirrc=$?
	# Rebuild exit status properly (the pipe masked it).
	"$BIN/$PROG" "$@" < "$input" >/dev/null 2>&1; ourrc=$?
	PATH=$SYSHELPER "/usr/bin/$PROG" "$@" < "$input" >/dev/null 2>&1; theirrc=$?

	if [ "$ours" = "$theirs" ] && [ "$ourrc" = "$theirrc" ]; then
		PASS=$((PASS+1)); printf '  MATCH  %-46s rc=%s out=%s\n' "$label" "$ourrc" "${ours:0:40}"
	else
		DIVERGE=$((DIVERGE+1))
		printf '  DIVERGE %-46s ours(rc=%s)=[%s] host(rc=%s)=[%s]\n' \
		    "$label" "$ourrc" "${ours:0:60}" "$theirrc" "${theirs:0:60}"
		DLINES="$DLINES$label"$'\n'
	fi
}

# expect <label> <expected> <actual>  -- our behaviour only, no host involved
expect() {
	if [ "$2" = "$3" ]; then
		PASS=$((PASS+1)); printf '  OK     %-46s [%s]\n' "$1" "$2"
	else
		FAIL=$((FAIL+1)); printf '  FAIL   %-46s want=[%s] got=[%s]\n' "$1" "$2" "$3"
	fi
}

# ---------------------------------------------------------------- wc -----
PROG=wc
echo "== wc: differential against /usr/bin/wc =="

printf 'a b c\nde f\n'            > "$W/basic"
printf 'abc\ndef'                 > "$W/unterm"      # final line, no newline
: > "$W/empty"                                    # zero bytes
printf '\n'                       > "$W/nl"
printf '   \t \n \n'              > "$W/blank"
printf 'x\r\ny\r\n'               > "$W/crlf"
printf '\xc3\xa9\xc3\xa8x\n'      > "$W/utf8"

cmp_case "default, 2 lines 5 words"  "$W/basic"
cmp_case "default, unterminated last" "$W/unterm"
cmp_case "default, empty file"        "$W/empty"
cmp_case "default, single newline"    "$W/nl"
cmp_case "default, blank runs"        "$W/blank"
cmp_case "default, CRLF"              "$W/crlf"
cmp_case "-l newlines"                "$W/basic" -l
cmp_case "-w words"                   "$W/basic" -w
cmp_case "-c bytes"                   "$W/basic" -c
cmp_case "-lw"                        "$W/basic" -lw
cmp_case "-lcw"                       "$W/basic" -lcw
cmp_case "--lines"                    "$W/basic" --lines
cmp_case "--words"                    "$W/basic" --words
cmp_case "--bytes"                    "$W/basic" --bytes
cmp_case "clustered -clw on unterm"   "$W/unterm" -clw
cmp_case "repeated -ll"               "$W/basic" -ll
cmp_case "no operands (stdin)"        "$W/basic"
cmp_case "-- terminator then nothing" "$W/basic" --
cmp_case "utf8 counted as bytes"      "$W/utf8" -c

echo
echo "== wc: behaviour we assert directly =="
# 4 lines of 'in' concatenated = 8 lines, so an 8 is the correct answer and
# a 4 would be the bug.
printf 'a\nb\nc\nd\n' > "$W/f1"
cat "$W/f1" "$W/f1" > "$W/f2"
# wc pads each count to 8 columns, so compare the field, not the raw line.
r=$("$BIN/wc" -l < "$W/f2" | PATH=$SYSHELPER tr -d ' '); expect "two 4-line files -> 8 lines" "8" "$r"
r=$("$BIN/wc" -l "$W/f1" "$W/f1" | tail -1 | PATH=$SYSHELPER awk '{print $1}')
expect "total line present for 2 files" "8" "$r"
r=$("$BIN/wc" "$W/f1" | PATH=$SYSHELPER awk '{print NF}')
expect "1 file -> no total line" "4" "$r"
r=$("$BIN/wc" -m < "$W/utf8" 2>&1 >/dev/null | head -1)
case $r in
*"not supported"*) PASS=$((PASS+1)); printf '  OK     %-46s [%s]\n' "-m refused with a diagnostic" "$r";;
*) FAIL=$((FAIL+1)); printf '  FAIL   %-46s -m was NOT refused (got [%s])\n' "-m refusal" "$r";;
esac
r=$("$BIN/wc" --chars < "$W/utf8" 2>&1 >/dev/null | head -1)
case $r in
*"not supported"*) PASS=$((PASS+1)); printf '  OK     %-46s [%s]\n' "--chars refused with a diagnostic" "$r";;
*) FAIL=$((FAIL+1)); printf '  FAIL   %-46s --chars was NOT refused (got [%s])\n' "--chars" "$r";;
esac

# ---------------------------------------------------------------- tr -----
PROG=tr
echo
echo "== tr: differential against /usr/bin/tr =="

printf 'hello world\n'  > "$W/t_basic"
printf 'aabbbccd'       > "$W/t_runs"
printf 'abc123'         > "$W/t_digits"
printf '\xc3\xa9\xc3\xa8z\n' > "$W/t_utf8"

cmp_case "basic lowercase->upper"      "$W/t_basic" a-z A-Z
cmp_case "rot13-ish abc->xyz"          "$W/t_basic" abc xyz
cmp_case "-d delete vowels"            "$W/t_basic" -d aeiou
cmp_case "-s squeeze runs"             "$W/t_runs" -s ab
cmp_case "-s squeeze all"              "$W/t_runs" -s abc
cmp_case "-ds delete+squeeze"          "$W/t_runs" -ds b a
cmp_case "-c complement upper"         "$W/t_basic" -c a-z A-Z
cmp_case "-C synonym"                  "$W/t_basic" -C a-z A-Z
cmp_case "escapes \\n \\t"             "$W/t_basic" '\n' '@'
cmp_case "octal 3 digits"              "$W/t_digits" '\101\102\103' xyz
cmp_case "octal 1 digit"               "$W/t_digits" '\7' '@'
cmp_case "literal backslash"           "$W/t_basic" '\' '#'
cmp_case "class [:alpha:]"             "$W/t_basic" '[:lower:]' 'X'
cmp_case "class [:digit:]"              "$W/t_digits" '[:digit:]' 'N'
cmp_case "class negated [:^digit:]"    "$W/t_digits" '[:^digit:]' 'N'
cmp_case "class [:space:]"              "$W/t_basic" '[:space:]' '_'
cmp_case "class [:upper:]"              "$W/t_basic" '[:upper:]' 'L'
cmp_case "range from class a-[:digit:]" "$W/t_digits" 'a-[:digit:]' 'X'
cmp_case "utf8 bytes untouched"        "$W/t_utf8" a-z A-Z
cmp_case "utf8 delete ascii only"      "$W/t_utf8" -d a-z
cmp_case "-u is accepted"              "$W/t_basic" -u a-z A-Z
cmp_case "SET2 shorter (truncation)"   "$W/t_basic" abcdefgh xy
cmp_case "SET2 empty-ish via -d"       "$W/t_basic" -d abc
cmp_case "reversed range z-a"          "$W/t_basic" 'z-a' 'X'
cmp_case "trailing backslash in SET1"  "$W/t_basic" 'ab\' 'XY'
cmp_case "literal '-' at end"          "$W/t_basic" 'ab-' 'XYZ'
cmp_case "empty SET1 with -d"          "$W/t_basic" -d ''
cmp_case "empty SET1 translate"        "$W/t_basic" '' 'x'
cmp_case "delete nothing"              "$W/t_basic" -d 'ZZZ'
cmp_case "-t truncate"                 "$W/t_basic" -t abcd wxyz
cmp_case "-s single char"              "$W/t_runs" -s a
cmp_case "-cd complement delete"       "$W/t_basic" -cd aeiou

echo
echo "== tr: behaviour we assert directly =="
r=$("$BIN/tr" 'abc' 'xy' < "$W/t_digits"); expect "truncation pads with last char" "xyy123" "$r"
r=$("$BIN/tr" -s 'ab' < "$W/t_runs"); expect "-s squeezes runs of a and b" "abccd" "$r"
r=$("$BIN/tr" -d '' < "$W/t_basic" | head -c 3); expect "-d with empty SET1 is identity" "hel" "$r"
# \101 is 'A' (0x41), so the input has to be uppercase for it to match.
r=$(printf 'ABC' | "$BIN/tr" '\101' 'z'); expect "octal \\101 = 'A'" "zBC" "$r"
r=$(printf 'abc' | "$BIN/tr" 'a-c' 'XYZ'); expect "range a-c maps 3 chars" "XYZ" "$r"
r=$(printf 'abc' | "$BIN/tr" 'a-c' 'X'); expect "range a-c pads with X" "XXX" "$r"

echo
echo "=================================================="
printf 'matched: %d   diverged from host: %d   our-own failures: %d\n' \
    "$PASS" "$DIVERGE" "$FAIL"
if [ "$DIVERGE" -ne 0 ]; then
	echo
	echo "DIVERGENT CASES (investigate; the host is the oracle):"
	printf '%s' "$DLINES" | sed 's/^/  - /'
fi
[ "$FAIL" -eq 0 ] || exit 1
exit 0
