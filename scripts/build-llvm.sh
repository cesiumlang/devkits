#!/usr/bin/env bash
#cSpell:enableCompoundWords
# Cross-compile LLVM and LLD as static libraries for a host triple, with the
# pinned official Zig as the C/C++ compiler. No Clang and no LLVM tools: the
# Cesium compiler links the libraries and drives them through LLVM's C API.
# Adapted from randyos-org/zig-build's build-llvm-cross.sh. Re-running resumes:
# ninja skips finished work, and CCACHE=ccache lets a fresh build directory
# reuse objects.
#
# usage: build-llvm.sh <host triple>      e.g. x86_64-windows-gnu
# output: $WORK/llvm-<host triple>        (install prefix: include/, lib/)
# Needs cmake, ninja and a POSIX shell; runs in CI on Linux.
# shellcheck source=scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST=${1:?usage: build-llvm.sh <host triple>}
MCPU=baseline

for tool in cmake ninja; do
  command -v $tool >/dev/null || { echo "$tool not found on PATH" >&2; exit 1; }
done
[ -f "$ROOT/llvm-project/llvm/CMakeLists.txt" ] \
  || { echo "llvm-project is not checked out: git submodule update --init --depth 1 llvm-project" >&2; exit 1; }
require_builder_zig

ZIG=$(builder_zig)
BUILDER=$(builder_triple)
SRC=$ROOT/llvm-project
BUILD=$WORK/build-llvm-$HOST
PREFIX=$WORK/llvm-$HOST
SYSTEM_NAME=$(cmake_system_name "$HOST")
TARGETS=$(pin '.llvm.targets | join(";")')
PROJECTS=$(pin '.llvm.projects | join(";")')
mkdir -p "$BUILD" "$PREFIX"

# ar, ranlib and rc through Zig itself, so no host binutils are needed
TOOLS=$WORK/tools
mkdir -p "$TOOLS"
for tool in ar ranlib rc; do
  printf '#!/bin/sh\nexec "%s" %s "$@"\n' "$ZIG" "$tool" > "$TOOLS/$tool"
  chmod +x "$TOOLS/$tool"
done

LAUNCHER=()
if [ -n "${CCACHE:-}" ]; then
  # ccache cannot identify `zig cc` on its own
  export CCACHE_COMPILERTYPE=clang
  LAUNCHER=(-DCMAKE_C_COMPILER_LAUNCHER="$CCACHE" -DCMAKE_CXX_COMPILER_LAUNCHER="$CCACHE")
fi

cross_cc () { echo "$ZIG;$1;-fno-sanitize=all;-s;-target;$HOST;-mcpu=$MCPU"; }

# CMake says only that a check failed; why is at the end of its configure log
configure () { # <build dir> <cmake argument>...
  local dir=$1
  shift
  if ! cmake -B "$dir" "$@"; then
    echo "::group::tail of $dir/CMakeFiles/CMakeConfigureLog.yaml"
    tail -n 150 "$dir/CMakeFiles/CMakeConfigureLog.yaml" || true
    echo "::endgroup::"
    exit 1
  fi
}

# 1. llvm-tblgen for the machine this runs on (the only native piece)
TBLGEN=$WORK/build-tblgen-$BUILDER
configure "$TBLGEN" -S "$SRC/llvm" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$ZIG;cc;-target;$BUILDER;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-target;$BUILDER;-mcpu=$MCPU" \
  -DCMAKE_ASM_COMPILER="$ZIG;cc;-target;$BUILDER;-mcpu=$MCPU" \
  -DCMAKE_AR="$TOOLS/ar" \
  -DCMAKE_RANLIB="$TOOLS/ranlib" \
  ${LAUNCHER[@]+"${LAUNCHER[@]}"} \
  -DLLVM_TARGETS_TO_BUILD="$TARGETS" \
  -DLLVM_APPEND_VC_REV=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_PLUGINS=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF
cmake --build "$TBLGEN" --target llvm-tblgen

# 2. LLVM core, the targets of devkit.json, and LLD, as static libraries
# (LLVM_BUILD_STATIC is not set: it only adds -static to the link of LLVM's
# own programs, none of which are built, and CMake's compiler checks then
# fail for macOS, where nothing links statically. The libraries are static
# because BUILD_SHARED_LIBS is off by default.)
configure "$BUILD" -S "$SRC/llvm" -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CROSSCOMPILING=True \
  -DCMAKE_SYSTEM_NAME="$SYSTEM_NAME" \
  -DCMAKE_C_COMPILER="$(cross_cc cc)" \
  -DCMAKE_CXX_COMPILER="$(cross_cc c++)" \
  -DCMAKE_ASM_COMPILER="$(cross_cc cc)" \
  -DCMAKE_RC_COMPILER="$TOOLS/rc" \
  -DCMAKE_LINK_DEPENDS_USE_LINKER=OFF \
  -DCMAKE_AR="$TOOLS/ar" \
  -DCMAKE_RANLIB="$TOOLS/ranlib" \
  ${LAUNCHER[@]+"${LAUNCHER[@]}"} \
  -DLLVM_TARGETS_TO_BUILD="$TARGETS" \
  -DLLVM_ENABLE_PROJECTS="$PROJECTS" \
  -DLLVM_APPEND_VC_REV=OFF \
  -DLLVM_ENABLE_BACKTRACES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_CRASH_OVERRIDES=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_PLUGINS=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_ENABLE_ZLIB=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_TABLEGEN="$TBLGEN/bin/llvm-tblgen" \
  -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_BUILD_TOOLS=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$HOST" \
  -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
  -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
  -DLLVM_TOOL_LTO_BUILD=OFF \
  -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
  -DLLD_BUILD_TOOLS=OFF
cmake --build "$BUILD" --target install

echo "LLVM $LLVM_VERSION for $HOST: $PREFIX"
