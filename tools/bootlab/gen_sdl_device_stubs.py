#!/usr/bin/env python3
"""Generate Frameworks/SDL2/src/SDL_ravynos_devices_stubs.c.

ravynOS has no joystick, game controller, sensor or haptic hardware.  Every
entry point of those SDL 2.32 subsystems still has to exist with its exact
declared signature, or ports that merely *reference* the API fail to link.
Rather than retype 130-odd prototypes by hand (and drift from the headers on
every SDL update), this reads them out of the public headers and emits
zero-result implementations.

Usage: python3 tools/bootlab/gen_sdl_device_stubs.py [--check]
       --check exits 1 if the committed file is out of date.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
FMWK = os.path.join(REPO, "Frameworks", "SDL2")
HEADERS = [
    "SDL_joystick.h",
    "SDL_gamecontroller.h",
    "SDL_sensor.h",
    "SDL_haptic.h",
]
OUT = os.path.join(FMWK, "src", "SDL_ravynos_devices_stubs.c")

HEADER = """/* Generated device-subsystem stubs: ravynOS has no joystick, game controller,
 * sensor or haptic hardware, so every entry point in those subsystems is
 * present with the exact SDL 2.32 signature and a no-device result.
 *
 * Do not edit by hand. Regenerate with:
 *     python3 tools/bootlab/gen_sdl_device_stubs.py
 */

#include "SDL_ravynos_internal.h"

"""


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def split_statements(text):
    """Split on ';' but keep the text, because prototypes never contain one."""
    return [s.strip() for s in text.split(";") if s.strip()]


def parse_decl(stmt):
    """Return (ret_type, name, params) for one 'extern DECLSPEC ...;' stmt."""
    # Trailing availability attributes (`SDL_ACQUIRE()`, `SDL_RELEASE()`)
    # follow the parameter list; they belong to the declaration only.
    stmt = re.sub(r"\s+SDL_[A-Z_0-9]+\((?:[^()]*)\)\s*$", "", stmt)
    m = re.match(
        r"^extern\s+DECLSPEC\s+(.+?)\s+SDLCALL\s+(\w+)\s*\((.*)\)\s*$",
        stmt,
        re.S,
    )
    if not m:
        return None
    ret = " ".join(m.group(1).split())
    name = m.group(2)
    raw_args = " ".join(m.group(3).split())
    # A trailing attribute can also end up inside the argument list when the
    # declaration keeps it after the closing paren.
    raw_args = re.sub(r"\s+SDL_[A-Z_0-9]+\((?:[^()]*)\)\s*$", "", raw_args)
    if raw_args in ("", "void"):
        return ret, name, []

    params = []
    for arg in raw_args.split(","):
        arg = arg.strip()
        if not arg:
            continue
        # Drop a trailing identifier (the parameter name) if there is a type
        # in front of it; keep pointer parameters verbatim.
        m2 = re.match(r"^(.*?)([A-Za-z_]\w*)$", arg)
        if m2 and m2.group(1).strip() and not arg.rstrip().endswith("*"):
            params.append(m2.group(1).strip())
        else:
            params.append(arg)
    return ret, name, params


def is_struct_return(ret):
    """A struct-by-value return cannot be spelled '(Type)0'."""
    return "(" not in ret and " " not in ret and "*" not in ret and \
        ret not in ("int", "char", "short", "long", "float", "double",
                    "unsigned", "signed", "void")


def emit(ret, name, params):
    sig = ", ".join(params) if params else "void"
    lines = []
    # The prototype is not re-emitted: SDL_ravynos_internal.h includes SDL.h,
    # so the compiler checks this definition against the real declaration.
    lines.append("%s SDLCALL %s(%s) {" % (ret, name, sig))
    for i, p in enumerate(params):
        # Silence unused parameters without naming them.
        lines.append("    (void)0;")
        break
    if ret == "void":
        pass
    elif "*" in ret:
        lines.append("    return NULL;")
    elif is_struct_return(ret):
        lines.append("    %s zero;" % ret)
        lines.append("    SDL_memset(&zero, 0, sizeof(zero));")
        lines.append("    return zero;")
    else:
        lines.append("    return (%s)0;" % ret)
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def generate():
    body = []
    for hdr in HEADERS:
        path = os.path.join(FMWK, "Headers", hdr)
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = strip_comments(f.read())
        seen = set()
        for stmt in split_statements(text):
            if not stmt.startswith("extern DECLSPEC"):
                continue
            parsed = parse_decl(stmt)
            if not parsed:
                continue
            ret, name, params = parsed
            if name in seen:
                continue
            seen.add(name)
            body.append(emit(ret, name, params))
    return HEADER + "".join(body)


def main():
    content = generate()
    if "--check" in sys.argv:
        if not os.path.isfile(OUT):
            print("missing %s" % OUT, file=sys.stderr)
            return 1
        with open(OUT, "r", encoding="utf-8") as f:
            if f.read() != content:
                print("%s is stale; regenerate it" % OUT, file=sys.stderr)
                return 1
        return 0
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(content)
    print("wrote %s (%d bytes)" % (OUT, len(content)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
