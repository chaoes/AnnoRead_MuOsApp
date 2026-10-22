#!/usr/bin/env python3
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "legado_js_bundle.h"
s = open(path).read()

# Append a trailing 0x00 byte to the array so QuickJS lookahead reads NUL,
# but LEAVE `legado_js_len` unchanged so JS_Eval parses the real script length.
needle = "0x0a\n};\nunsigned int legado_js_len"
replacement = "0x0a,\n  0x00\n};\nunsigned int legado_js_len"
if needle in s:
    s = s.replace(needle, replacement, 1)
    open(path, "w").write(s)
    print(f"Patched {path}: appended terminating 0x00 byte")
else:
    print("WARNING: needle not found in", path, file=sys.stderr)
