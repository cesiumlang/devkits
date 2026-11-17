#!/usr/bin/env bash
# Cross-compile the pinned QBE for a host triple with the pinned official Zig:
# the `qbe` program, and libqbe.a, the same code with its entry point renamed
# to qbe_main so a compiler can run QBE in-process (include/qbe.h).
# QBE's sources are used unmodified.
#
# usage: build-qbe.sh <host triple>
# output: $WORK/qbe-<host triple>   (bin/, lib/, include/, src/)
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST=${1:?usage: build-qbe.sh <host triple>}
SRC=$ROOT/qbe
[ -f "$SRC/main.c" ] || { echo "qbe is not checked out: git submodule update --init qbe" >&2; exit 1; }
[ "$(git -C "$SRC" rev-parse HEAD)" = "$QBE_COMMIT" ] \
  || { echo "qbe is at $(git -C "$SRC" rev-parse HEAD), devkit.json pins $QBE_COMMIT" >&2; exit 1; }
require_builder_zig

ZIG=$(builder_zig)
OUT=$WORK/qbe-$HOST
OBJ=$WORK/build-qbe-$HOST
DEFTGT=$(pin ".qbe.default_target[\"$HOST\"]")
rm -rf "$OUT" "$OBJ"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/include" "$OBJ/prog" "$OBJ/lib"

# QBE's Makefile writes config.h from uname; here the host decides
echo "#define Deftgt T_$DEFTGT" > "$OBJ/config.h"

# the Makefile's source list: main.c and the rest of the top level, then
# every target directory
SOURCES=()
for f in "$SRC"/*.c "$SRC"/amd64/*.c "$SRC"/arm64/*.c "$SRC"/rv64/*.c; do
  SOURCES+=("$f")
done

CFLAGS=(-target "$HOST" -mcpu=baseline -std=c99 -O2 -fno-sanitize=all -I"$OBJ" -I"$SRC")

compile () { # <object dir> <extra flag>...
  local dir=$1 f o
  shift
  for f in "${SOURCES[@]}"; do
    o=$dir/$(echo "${f#"$SRC"/}" | tr / _).o
    "$ZIG" cc "${CFLAGS[@]}" "$@" -c "$f" -o "${o%.c.o}.o"
  done
}

compile "$OBJ/prog"
"$ZIG" cc -target "$HOST" -mcpu=baseline -s "$OBJ"/prog/*.o -o "$OUT/bin/qbe$(exe_ext "$HOST")"

# only main.c differs, but one flag set for the whole archive is simpler
compile "$OBJ/lib" -Dmain=qbe_main
"$ZIG" ar rcs "$OUT/lib/libqbe.a" "$OBJ"/lib/*.o

cp "$ROOT/scripts/qbe.h" "$OUT/include/qbe.h"
git -C "$SRC" archive --format=tar --prefix=src/ HEAD | tar -xf - -C "$OUT"

echo "QBE ${QBE_COMMIT:0:7} for $HOST: $OUT (default target $DEFTGT)"
