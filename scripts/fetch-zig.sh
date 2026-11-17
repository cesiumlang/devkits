#!/usr/bin/env bash
# Download the pinned official Zig release for a host triple, check it against
# the sha256 in devkit.json, and unpack it so that <dir>/zig is the compiler.
# usage: fetch-zig.sh <host triple> <dir>
# The network fails now and then, so the download is retried.
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST=${1:?usage: fetch-zig.sh <host triple> <dir>}
DEST=${2:?usage: fetch-zig.sh <host triple> <dir>}

FILE=$(pin ".zig.archives[\"$HOST\"].file")
SUM=$(pin ".zig.archives[\"$HOST\"].sha256")
URL=$(pin .zig.base_url)/$FILE

mkdir -p "$WORK/downloads"
ARCHIVE=$WORK/downloads/$FILE
if [ ! -f "$ARCHIVE" ] || [ "$(sha256_of "$ARCHIVE")" != "$SUM" ]; then
  for i in 1 2 3 4 5; do
    curl -fsSL --retry 3 -o "$ARCHIVE" "$URL" && break
    [ "$i" = 5 ] && { echo "could not download $URL" >&2; exit 1; }
    sleep $((i * 15))
  done
fi
GOT=$(sha256_of "$ARCHIVE")
[ "$GOT" = "$SUM" ] || { echo "$FILE: sha256 $GOT, devkit.json pins $SUM" >&2; exit 1; }

# the archive holds one top-level directory; its contents become <dir>
rm -rf "$DEST" "$DEST.unpack"
mkdir -p "$DEST.unpack"
case $FILE in
  *.zip) unzip -q "$ARCHIVE" -d "$DEST.unpack" ;;
  *) tar -xJf "$ARCHIVE" -C "$DEST.unpack" ;;
esac
mv "$DEST.unpack"/* "$DEST"
rmdir "$DEST.unpack"
echo "Zig $ZIG_VERSION for $HOST: $DEST"
