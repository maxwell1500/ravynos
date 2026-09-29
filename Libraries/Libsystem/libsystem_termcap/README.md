# libsystem_termcap — the termcap interface

An original, 4-clause BSD implementation of the classic termcap interface
(`tgetent`, `tgetnum`, `tgetflag`, `tgetstr`, `tgoto`, `tputs`) with a small
built-in entry table.

## Why it exists

`BSD/lib/libedit/src/terminal.c` calls all six entry points unconditionally
from `terminal_set()` (`terminal.c:864`, `:882-897`, `:895`). It has no
non-termcap path. ravynOS had no termcap at all: no `<termcap.h>` anywhere in
the SDK, no `tget*` in any Libsystem archive, and no termcap database in the
SDK tree — and no network to fetch one.

So the consequences were concrete, not theoretical:

* the target `libedit.a` could not be built, and
* `BSD/bin/sh` had to be compiled with `SHELL_TARGET_NO_HISTORY=1`, which is a
  complete shell that does not do arrow keys or history.

The two alternatives were both rejected before this was written: the GPL-3
termcap in the bash source tree (28 KB, working, but it contaminates
`Libsystem`), and extracting from ncurses (drags in a ~188 KB terminfo
closure for an interface that needs none of it).

## Provenance

Written from the specification — `termcap(3)`, the capability names and
meanings in `termcap(5)`, and the ECMA-48 / ISO 6429 / DEC VT-series control
functions the capability strings are drawn from. **Not** derived from any
existing termcap implementation: not the historical BSD one, not GNU, not
ncurses, not musl. No line was copied, transliterated or paraphrased from one.

Two things in `termcap.c` are necessarily not original, and both are facts
rather than code: the **capability names** (`ce`, `co`, `xn`, … are the
vocabulary every termcap consumer already speaks), and the **escape sequences**
(`\E[K` is the EL control function because that is what an EL-capable terminal
interprets it as). Everything else — the entry table layout, the field scanner,
the unescaper, `tgoto`'s conversion machine, `tputs`' padding accounting and
every error return — is this component's own.

## The header name

`termcap.h` is installed into the SDK as `<termcap.h>`, which is the name a
program includes. That is deliberate and it is the only sensible spelling:
`BSD/lib/libedit/src/terminal.c:58` does `#include <termcap.h>`.

### Why the header is not optional

`libedit`'s `src/sys.h` includes `config.h` into every translation unit, and
`config.h` has `HAVE_TERMCAP_H 1`, so `terminal.c` really does reach that
`#include`. `terminal.c` declares the six prototypes **itself only** under
`#if defined(__sun)` (`terminal.c:71-78`). Without the header there, the
ravynOS build compiles with an implicit

    int tgetent(); int tgetflag(); int tgetnum(); int tputs(); char *tgoto();

`int tgetstr()` in particular truncates a returned pointer to 32 bits on
x86_64. That is not a warning; it is a wrong library.

`config.h` also had `HAVE_CURSES_H` and `HAVE_NCURSES_H` set to 1, recorded
by `configure` on a host that had curses. ravynOS has neither, so the same
translation unit died on

    BSD/lib/libedit/src/terminal.c:61:10: fatal error: 'curses.h' file not found

Both are now `#undef` in `BSD/lib/libedit/config.h`, with the reasoning in a
comment there. `HAVE_TERM_H` is left alone: `terminal.c:67` already skips
`<term.h>` whenever `HAVE_TERMCAP_H` is defined.

## There is no file database, and `tgetent` never returns −1

The entries are compiled in. `tgetent` does not read `/etc/termcap`,
`$TERMCAP` or `$HOME/.termcap`, because none of those exist on this system.

Consequently:

| return | meaning | can this implementation produce it? |
|---|---|---|
| `1` | the entry was loaded into `*bp` | yes |
| `0` | no entry for that terminal name | yes |
| `−1` | a termcap database file exists and could not be read | **never** |

`−1` is not a stub value. It means "I looked for a database file and could not
use it", and there is no file to look for. A caller that tests `i <= 0` for "no
editing available" is still correct; one that tests `i == -1` specifically to
detect a broken database will never see it, and that is the honest answer.

**Not determined:** whether `$TERMCAP`-as-a-file support should be added. It
is a real feature and about forty lines given the field scanner that already
exists, but it was not needed by any consumer here and was not written.

## What the entries contain

Two entries. `tc_vt100_caps` is a VT100/ECMA-48 entry, listed under every name
that speaks it (`xterm`, `xterm-256color`, `screen`, `screen.xterm-256color`,
`tmux-256color`, `vt100`…`vt420`, `ansi`, `linux`, `alacritty`, `foot`,
`kitty`, `wezterm`, … — 40 names). `tc_dumb_caps` is `dumb`: a bell and a
size, and nothing else.

Every capability string names the control function it is, in a comment, so it
can be checked against the terminal's manual rather than against this file's
memory.

### Deliberately absent, and why

These are the interesting ones. An absent capability is reported as absent.
It is never filled in with a substitute.

**`UP` and `LE`** — real VT100 capabilities, omitted because of how their only
consumer calls them:

    terminal.c:516   tgoto(Str(T_UP), -del, -del)
    terminal.c:597   tgoto(Str(T_LE), -del, -del)

Both pass a **negated** count, so the ordinary spelling `\E[%dA` renders
`\E[-7A` — a negative repeat count, which a VT100 treats as a parameter error.
Classic `tgoto` has no negation operator, and inventing one would be inventing
syntax no other termcap implementation has. `libedit` tests `GoodStr(T_UP)` /
`GoodStr(T_LE)` before calling `tgoto` on them and has a correct fallback when
they are absent, so omitting them produces *right behaviour* rather than a
wrong escape sequence.

`RI`, `DC`, `IC` and `ch` **are** provided: `libedit` passes those the same
value to both parameters, positively, which is what the ordinary `%d` form
expects. `RI`/`DC`/`IC` deliberately carry **no** `%i` — they take a zero-based
repeat count — while `ch` does carry `%i`, because CHA takes a 1-based column
number rather than a distance.

**`xn`** (magic margins / magic erase) and **`xt`** (destructive tabs) are not
set: a VT100 has neither. Setting them would make `libedit` believe the
terminal erases overstrikes and that tab stops eat characters.

**`vb`** (visible bell) is not set: it is `CSI ?5h CSI ?5l` (DECTCEM), which a
plain VT100 ignores.

**`@7`** is absent because it is not a termcap capability — no terminal sends
it. `terminal.c` uses that index for the End key, which
`terminal_reset_arrow` binds unconditionally anyway.

**`kD`** *is* provided, as `\E[3~`. It is not a standard termcap name, but
`libedit` uses it for ED_DELETE_NEXT_CHAR and `\E[3~` is what a VT100-family
terminal actually sends for the Delete key, so this is a real key bound to a
real action rather than an invented capability.

**No ravynOS-specific terminal name.** ravynOS's console is BSDFramebuffer-
backed with no VT emulation this component can verify. Claiming it would be a
claim about hardware and firmware that nothing in this tree establishes, so
`TERM=<anything unknown>` gets `tgetent() == 0` — the honest answer, and one
`libedit` already handles by falling back to its own dumb path.

**Termcap has no prompt capability.** `PS1` and friends are the shell's own
business; nothing here provides, reads or interferes with them.

## `tgoto`

Supported conversions, in full:

    %%       a literal '%'
    %d       the first parameter (col)
    %2       the second parameter (row)
    %3       the first parameter again, spelled the terminfo way
    %i       col += 1, then continue
    %r       swap col and row
    %+n      col += n         for n a single digit
    %.n      col += n + 1     for n a single digit; a bare `%.' adds 1
    %>xy     pad what the next parameter prints out to width y with char x
    %<w>[.<p>][+-][ ]<c>   a padding specification: stripped, and
                            (w − length so far) copies of c emitted at the
                            end of the result

`%.' is *always* the increment and never a padding specification, which is what
keeps `%.' from being ambiguous: `%.%d` is "add one, then print col". Padding
must start with a digit or a `+`.

**Every other conversion returns NULL.** `%p1`, `%P`, `%n`, `%B`, `%D`, `%a`,
`%s`, the terminfo stack and arithmetic forms — all refused. `tgoto` does not
emit a substitute and does not approximate. No capability in any entry this
component ships needs one. `tputs` accepts NULL and writes nothing, so a caller
that does not check degrades instead of crashing.

## `tputs` and padding

`$<count>` (with an optional `<`, `*` or `+`) is padding. Each pad byte is
`PC`; when `PC` is `'\0'` — which is the case for both entries here, since
neither defines `pc` — **no bytes are emitted**, but the count is still added
into the return, because the caller asked how much padding the terminal was
told to swallow and that does not depend on whether `PC` happens to be set.

The return value, spelled out so a caller can predict it:

| condition | returns |
|---|---|
| no padding in `str` | `affcnt`, unchanged |
| `affcnt < 0` | `affcnt`, unchanged (the caller does not want to know) |
| `pad_total <= affcnt` | `affcnt`, unchanged |
| `pad_total > affcnt` | `pad_total` |

`outc` returning `EOF` aborts and returns `EOF`.

## `tgetstr` and the caller's area

When `area` is non-NULL and `*area` is non-NULL the value is copied there and
`*area` is advanced past it, so repeated calls fill one buffer. The caller is
responsible for the size; `TC_BUFSIZ` (1024) is enough for every entry shipped
here — the 40 capabilities `libedit` asks for decode to **149 bytes**, which
the suite measures rather than assumes, against the 2048-byte area
`terminal.c:840` provides.

When `area` is NULL or `*area` is NULL, the value goes into a static buffer
that the next `tgetstr` overwrites. There is no `malloc` in this component.

`tgetent`'s `bp` must have room for `TC_BUFSIZ` bytes. The interface has no way
to learn a caller's buffer size; that is what the constant is for. Writing past
it is undefined, exactly as it has always been, and the test suite asserts only
that this component never writes *more* than it promised.

## Global state

`PC`, `BC`, `UP`, `HO`, `BO`, `EE` are set only from the entry `tgetent`
matched. A `tgetent` that finds no entry **clears all six first**, so a failed
lookup can never leave the previous terminal's capabilities visible — which
matters, because `libedit` holds pointers into what `tgetstr` returned and
would otherwise compare a new entry against the old one's idea of itself.

## Building

    cd Libraries/Libsystem/libsystem_termcap/static
    bmake -m "$REPO/BSD/share/mk" all

builds `libsystem_termcap_static.a` and installs both the archive and
`termcap.h` into the ravynOS SDK. `Makefile` in this directory builds the
`libsystem_termcap.dylib` and installs it as
`/usr/lib/system/libsystem_termcap.dylib`.

The dylib's load commands are `libsystem_c.dylib` and `libsystem_platform.dylib`
and nothing else — in particular **not** `libSystem.dylib`, which in this SDK is
a symlink to the 4 KB `libSystem.B.dylib` re-export shim. That is why the
component's `LDFLAGS` carries `-nodefaultlibs` and does not carry
`-umbrella System`, both of which are the opposite of what the sibling
components next door do. Same reasoning as `libsystem_pwdgrp/Makefile`.

## Tests

`test/run-tests.sh [host|dylib|target|all]` runs three builds:

| build | what it proves |
|---|---|
| host | `termcap.c` compiled for the Darwin host and **executed** — 160 checks |
| dylib | the same source as a shared library, linked through a real two-level bind |
| target | compiled with the ravynOS SDK's headers, archived, and linked by `tools/bootlab/link-static.sh`, which fails unless the result has zero `LC_LOAD_DYLIB` and zero undefined symbols |

`test/probe.c` includes `<termcap.h>` with no `-I` of its own, so it only
compiles if the header really is installed where `libedit` will look for it.

`test/negative-control.sh` is not optional. It breaks `termcap.c` in seven
specific ways on a scratch copy and requires the suite to go red on each:

1. `ce` pointed at ED instead of EL
2. `ch` loses its `%i` (1-based column becomes 0-based)
3. `RI` gains an `%i` it must not have
4. `tgetflag` answers "yes" to everything
5. `tgetnum` answers 0 instead of −1 for an absent capability
6. `tgoto` silently drops an unknown conversion instead of refusing
7. the VT100 entry's `am` capability is dropped — invisible to every
   single `tgetstr` check, caught only by the boolean checks

It runs the **pristine** source first and refuses to report anything if that
does not pass, so "the mutant failed" can never just mean "the harness is
broken".

## What it unblocked

`BSD/bin/sh/build-ravynos.sh` now defaults to `SHELL_TARGET_NO_HISTORY=0` and
builds the target shell **with** line editing and history. The flag change is
`SHELL_TARGET_NO_HISTORY:-1` → `:0` plus `-lsystem_termcap_static` and
`-lcorecrypto` in `RAVYN_EXTRA_LIBS` (the latter because `libedit`'s history
writer saves through `mkstemp`, `readline.c:1304` / `vi.c:1020`, and libc's
`mktemp.o` reaches `_ccrng`, which only `libcorecrypto.a` defines).

See "Results" in the delivery report for the three verification levels —
host-executed, target-structural, target-runtime — kept strictly separate.
