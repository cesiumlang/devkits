#!/usr/bin/env bash
# Assemble the devkit of a host triple from what the other scripts built, and
# archive it.
#
# usage: package.sh <host triple>
# needs: $WORK/llvm-<host>  (build-llvm.sh)   $WORK/qbe-<host>  (build-qbe.sh)
#        $WORK/compression-<host>  (build-compression.sh)
# output: $DIST/cesium-devkit-<host>-<version>.tar.xz (.zip for Windows hosts)
#         $DIST/cesium-devkit-<host>-<version>.json   (its manifest)
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST=${1:?usage: package.sh <host triple>}
NAME=$(devkit_name "$HOST")
EXT=$(archive_ext "$HOST")
STAGE=$WORK/stage/$NAME

[ -d "$WORK/llvm-$HOST/lib" ] || { echo "no LLVM for $HOST: run build-llvm.sh" >&2; exit 1; }
[ -d "$WORK/qbe-$HOST/lib" ] || { echo "no QBE for $HOST: run build-qbe.sh" >&2; exit 1; }
[ -f "$WORK/compression-$HOST/lib/libzstd.a" ] || { echo "no zlib and zstd for $HOST: run build-compression.sh" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"

# zig/: the official release for the host, unmodified
bash "$ROOT/scripts/fetch-zig.sh" "$HOST" "$STAGE/zig"

# llvm/: headers and static libraries; no programs are built, and the CMake
# package files are dropped because nothing here runs CMake
mkdir -p "$STAGE/llvm"
cp -R "$WORK/llvm-$HOST/include" "$STAGE/llvm/include"
mkdir -p "$STAGE/llvm/lib"
cp "$WORK/llvm-$HOST"/lib/*.a "$STAGE/llvm/lib/"
cp "$ROOT/llvm-project/llvm/LICENSE.TXT" "$STAGE/llvm/LICENSE.TXT"
# zlib and zstd, which the LLVM libraries need, beside them
cp "$WORK/compression-$HOST"/lib/*.a "$STAGE/llvm/lib/"
cp "$WORK/compression-$HOST"/LICENSE-* "$STAGE/llvm/"

# qbe/: the program, libqbe.a with its header, and the pinned source
cp -R "$WORK/qbe-$HOST" "$STAGE/qbe"

cp "$ROOT/LICENSE" "$STAGE/LICENSE"

jq -n \
  --arg version "$DEVKIT_VERSION" \
  --arg host "$HOST" \
  --arg commit "$(git -C "$ROOT" rev-parse HEAD)" \
  --arg zig "$ZIG_VERSION" \
  --arg zig_file "$(pin ".zig.archives[\"$HOST\"].file")" \
  --arg zig_sha "$(pin ".zig.archives[\"$HOST\"].sha256")" \
  --arg qbe_target "$(pin ".qbe.default_target[\"$HOST\"]")" \
  --slurpfile pins "$PINS" \
  '{
    version: $version,
    host: $host,
    devkits_commit: $commit,
    zig: { version: $zig, archive: $zig_file, sha256: $zig_sha, path: "zig" },
    llvm: ($pins[0].llvm + { path: "llvm" }),
    qbe: { commit: $pins[0].qbe.commit, default_target: $qbe_target, path: "qbe" }
  }' > "$STAGE/manifest.json"
cp "$STAGE/manifest.json" "$DIST/$NAME.json"

rm -f "$DIST/$NAME.$EXT"
case $EXT in
  zip) (cd "$WORK/stage" && zip -qr -9 "$DIST/$NAME.zip" "$NAME") ;;
  *) tar -C "$WORK/stage" -cf - "$NAME" | xz -T0 -9 > "$DIST/$NAME.tar.xz" ;;
esac
ls -l "$DIST/$NAME.$EXT"
