#!/usr/bin/env bash
# Download the pinned official Zig release for a host triple, check it against
# the sha256 in devkit.json, and unpack it so that <dir>/zig is the compiler.
# usage: fetch-zig.sh <host triple> <dir>
# The network fails now and then, so the download is retried (fetch_pinned).
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST=${1:?usage: fetch-zig.sh <host triple> <dir>}
DEST=${2:?usage: fetch-zig.sh <host triple> <dir>}

FILE=$(pin ".zig.archives[\"$HOST\"].file")
SUM=$(pin ".zig.archives[\"$HOST\"].sha256")
URL=$(pin .zig.base_url)/$FILE

ARCHIVE=$WORK/downloads/$FILE
fetch_pinned "$URL" "$SUM" "$ARCHIVE"

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
