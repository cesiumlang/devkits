#!/usr/bin/env bash
# Shared by the scripts in this directory: paths, the pins of devkit.json and
# small helpers. Source it; do not run it.
# shellcheck disable=SC2034 # the variables are for the scripts that source this
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PINS=$ROOT/devkit.json
# everything a build writes goes under here (ignored by git)
WORK=${DEVKIT_WORK:-$ROOT/work}
DIST=${DEVKIT_DIST:-$ROOT/dist}

command -v jq >/dev/null || { echo "jq not found on PATH" >&2; exit 1; }

pin () { jq -er "$1" "$PINS"; }

DEVKIT_VERSION=$(pin .version)
ZIG_VERSION=$(pin .zig.version)
LLVM_VERSION=$(pin .llvm.version)
QBE_COMMIT=$(pin .qbe.commit)

# the devkit's directory and archive base name for a host triple
devkit_name () { echo "cesium-devkit-$1-$DEVKIT_VERSION"; }

# the archive extension of a host triple's devkit (and of its official Zig)
archive_ext () {
  case $1 in
    *-windows-*) echo zip ;;
    *) echo tar.xz ;;
  esac
}

exe_ext () {
  case $1 in
    *-windows-*) echo .exe ;;
    *) echo "" ;;
  esac
}

# CMAKE_SYSTEM_NAME of a host triple
cmake_system_name () {
  case $1 in
    *-linux-*) echo Linux ;;
    *-windows-*) echo Windows ;;
    *-macos-*) echo Darwin ;;
    *) echo "no CMAKE_SYSTEM_NAME known for $1" >&2; return 1 ;;
  esac
}

# the triple of the machine the scripts run on, as devkit.json spells hosts
builder_triple () {
  local arch os
  case $(uname -m) in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) echo "unsupported builder architecture $(uname -m)" >&2; return 1 ;;
  esac
  case $(uname -s) in
    Linux) os=linux-musl ;;
    Darwin) os=macos-none ;;
    MINGW* | MSYS* | CYGWIN*) os=windows-gnu ;;
    *) echo "unsupported builder OS $(uname -s)" >&2; return 1 ;;
  esac
  echo "$arch-$os"
}

sha256_of () {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Download <url> to <file> unless it is there already, retrying, and check it
# against <sha256>.
fetch_pinned () { # <url> <sha256> <file>
  local url=$1 sum=$2 file=$3 got i
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ] || [ "$(sha256_of "$file")" != "$sum" ]; then
    for i in 1 2 3 4 5; do
      curl -fsSL --retry 3 -o "$file" "$url" && break
      [ "$i" = 5 ] && { echo "could not download $url" >&2; return 1; }
      sleep $((i * 15))
    done
  fi
  got=$(sha256_of "$file")
  [ "$got" = "$sum" ] || { echo "$(basename "$file"): sha256 $got, devkit.json pins $sum" >&2; return 1; }
}

# The Zig that compiles everything: the pinned official release for the
# machine the scripts run on, fetched by fetch-zig.sh.
builder_zig () {
  local triple
  triple=$(builder_triple)
  echo "$WORK/zig-$triple/zig$(exe_ext "$triple")"
}

require_builder_zig () {
  local zig
  zig=$(builder_zig)
  [ -x "$zig" ] || bash "$ROOT/scripts/fetch-zig.sh" "$(builder_triple)" "$WORK/zig-$(builder_triple)"
  [ "$("$zig" version)" = "$ZIG_VERSION" ] || { echo "$zig is not Zig $ZIG_VERSION" >&2; exit 1; }
}
