#!/usr/bin/env bash
# Smoke-test an unpacked devkit on the host it was built for: the Zig runs and
# compiles C, the LLVM and LLD libraries link into a program that emits
# objects and links them, and QBE works as a program and as a library.
#
# usage: smoke.sh <unpacked devkit directory>
# Needs only bash, jq and the devkit: every compiler it uses is the devkit's.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KIT=$(cd "${1:?usage: smoke.sh <unpacked devkit directory>}" && pwd)

HOST=$(jq -er .host "$KIT/manifest.json")
WANT_ZIG=$(jq -er .zig.version "$KIT/manifest.json")
QBE_TARGET=$(jq -er .qbe.default_target "$KIT/manifest.json")
EXE=""
# expanded as ${SYSLIBS[@]+...}: the bash 3.2 of macOS calls an empty array unset
SYSLIBS=()
case $HOST in
  *-windows-*)
    EXE=.exe
    # what LLVM's Support library uses on Windows
    SYSLIBS=(-lole32 -luuid -lpsapi -lshell32 -ladvapi32 -lws2_32 -lntdll)
    ;;
esac
ZIG=$KIT/zig/zig$EXE
OUT=${SMOKE_OUT:-$HERE/work/smoke-$HOST}
rm -rf "$OUT"
mkdir -p "$OUT"

echo "== zig"
GOT_ZIG=$("$ZIG" version)
[ "$GOT_ZIG" = "$WANT_ZIG" ] || { echo "zig version $GOT_ZIG, manifest says $WANT_ZIG" >&2; exit 1; }
printf '#include <stdio.h>\nint main(void) { puts("hello from zig cc"); return 0; }\n' > "$OUT/hello.c"
"$ZIG" cc -target "$HOST" "$OUT/hello.c" -o "$OUT/hello$EXE"
[ "$("$OUT/hello$EXE" | tr -d '\r')" = "hello from zig cc" ]

echo "== llvm and lld"
"$ZIG" c++ -target "$HOST" -std=c++17 -fno-exceptions -fno-rtti -O1 \
  -I"$KIT/llvm/include" "$HERE/smoke/smoke.cpp" "$KIT"/llvm/lib/*.a ${SYSLIBS[@]+"${SYSLIBS[@]}"} \
  -o "$OUT/smoke$EXE"
"$OUT/smoke$EXE" "$OUT"
for f in answer-elf answer-coff.exe answer.wasm; do
  [ -s "$OUT/$f" ] || { echo "smoke did not write $f" >&2; exit 1; }
done

echo "== qbe"
run_hello () { # <assembly file>: assemble, link, run (only where the default target is the host's)
  case $HOST in
    aarch64-windows-*)
      echo "QBE has no arm64 Windows target: $1 is $QBE_TARGET assembly, not run"
      ;;
    *)
      "$ZIG" cc -target "$HOST" "$1" -o "${1%.s}$EXE"
      [ "$("${1%.s}$EXE" | tr -d '\r')" = "hello from qbe" ]
      ;;
  esac
}
"$KIT/qbe/bin/qbe$EXE" -o "$OUT/hello-qbe.s" "$HERE/smoke/hello.ssa"
run_hello "$OUT/hello-qbe.s"

"$ZIG" cc -target "$HOST" -I"$KIT/qbe/include" "$HERE/smoke/libqbe.c" "$KIT/qbe/lib/libqbe.a" -o "$OUT/libqbe$EXE"
"$OUT/libqbe$EXE" "$QBE_TARGET" "$HERE/smoke/hello.ssa" "$OUT/hello-libqbe.s"
run_hello "$OUT/hello-libqbe.s"

echo "devkit ok: $KIT"
