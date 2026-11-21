#!/usr/bin/env bash
# Cross-compile the pinned zlib and zstd for a host triple with the pinned
# official Zig, as static libraries: LLVM and LLD use them for compressed
# debug sections. Their release archives are used unmodified; only the
# library sources are compiled, as their own makefiles do, without running
# their build systems.
#
# usage: build-compression.sh <host triple>
# output: $WORK/compression-<host triple>   (include/, lib/libz.a, lib/libzstd.a)
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST=${1:?usage: build-compression.sh <host triple>}
require_builder_zig

ZIG=$(builder_zig)
OUT=$WORK/compression-$HOST
OBJ=$WORK/build-compression-$HOST
rm -rf "$OUT" "$OBJ"
mkdir -p "$OUT/include" "$OUT/lib" "$OBJ"

# unpack <name> (zlib or zstd) from its pinned archive into $OBJ/<name>
unpack () {
  local url sum file
  url=$(pin ".llvm.$1.url")
  sum=$(pin ".llvm.$1.sha256")
  file=$WORK/downloads/$(basename "$url")
  fetch_pinned "$url" "$sum" "$file"
  mkdir -p "$OBJ/$1"
  # zstd's tests hold symbolic links, which Windows builders cannot make
  tar -xzf "$file" -C "$OBJ/$1" --strip-components=1 --exclude="*/tests"
}

# compile <archive> <C flag>... -- <source>...
compile () {
  local lib=$1 flags=() f o
  shift
  while [ "$1" != -- ]; do flags+=("$1"); shift; done
  shift
  mkdir -p "$OBJ/obj-$lib"
  for f in "$@"; do
    o=$OBJ/obj-$lib/$(basename "${f%.*}").o
    "$ZIG" cc -target "$HOST" -mcpu=baseline -O2 -fno-sanitize=all "${flags[@]}" -c "$f" -o "$o"
  done
  "$ZIG" ar rcs "$OUT/lib/$lib" "$OBJ/obj-$lib"/*.o
}

# zlib: the top-level sources; ./configure would find unistd.h and stdarg.h
unpack zlib
ZLIB=$OBJ/zlib
ZLIB_FLAGS=(-DHAVE_STDARG_H=1)
case $HOST in
  *-windows-*) ;;
  *) ZLIB_FLAGS+=(-DHAVE_UNISTD_H=1) ;;
esac
compile libz.a "${ZLIB_FLAGS[@]}" -- "$ZLIB"/*.c
cp "$ZLIB/zlib.h" "$ZLIB/zconf.h" "$OUT/include/"
cp "$ZLIB/LICENSE" "$OUT/LICENSE-zlib"

# zstd: lib/common, compress and decompress (no dictionary builder, legacy
# formats or threads), with the flags of its lib/libzstd.mk
unpack zstd
ZSTD=$OBJ/zstd
ZSTD_SRC=("$ZSTD"/lib/common/*.c "$ZSTD"/lib/compress/*.c "$ZSTD"/lib/decompress/*.c)
# the x86-64 assembly decoder; it compiles to nothing where it does not apply
ZSTD_SRC+=("$ZSTD/lib/decompress/huf_decompress_amd64.S")
compile libzstd.a -DXXH_NAMESPACE=ZSTD_ -DDEBUGLEVEL=0 -DZSTD_LEGACY_SUPPORT=0 -- "${ZSTD_SRC[@]}"
cp "$ZSTD/lib/zstd.h" "$ZSTD/lib/zstd_errors.h" "$OUT/include/"
cp "$ZSTD/LICENSE" "$OUT/LICENSE-zstd"

echo "zlib $(pin .llvm.zlib.version) and zstd $(pin .llvm.zstd.version) for $HOST: $OUT"
