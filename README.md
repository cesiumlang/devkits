# Cesium devkits

Prebuilt toolchain packages for building the [Cesium](https://github.com/cesiumlang/cesium) compiler. A devkit is one archive per host that holds everything the compiler's build needs, so nobody builds LLVM locally:

| Directory | Holds |
| --- | --- |
| `zig/` | The pinned official [Zig](https://ziglang.org) release for the host, unmodified. It is the C/C++ compiler (`zig cc`) and runs `build.zig`. |
| `llvm/` | LLVM and LLD as static libraries with their headers (`include/`, `lib/`), and the zlib and zstd they use for compressed debug sections (`lib/libz.a`, `lib/libzstd.a`). No Clang and no LLVM tools. |
| `qbe/` | [QBE](https://c9x.me/compile/) at a pinned commit: the `qbe` program (`bin/`), `libqbe.a` with `qbe.h` for running QBE in-process (`lib/`, `include/`), and its source (`src/`). |
| `manifest.json` | What the devkit was built from: the Zig version and checksum, the LLVM tag and target list, the zlib and zstd versions, the QBE commit, and this repository's commit. |

The design comes from the compiler's decision records: [ADR 0001](https://github.com/cesiumlang/cesium/issues/4) (LLVM packaging and toolchain), [ADR 0002](https://github.com/cesiumlang/cesium/issues/5) (bootstrap) and [ADR 0004](https://github.com/cesiumlang/cesium/issues/7) (QBE first, LLVM as the release backend). The pipeline is adapted from [randyos-org/zig-devkits](https://github.com/randyos-org/zig-devkits) and [randyos-org/zig-build](https://github.com/randyos-org/zig-build).

## What is pinned: `devkit.json`

`devkit.json` is the single list of pins:

- `version`: the devkit version. It names the release.
- `zig`: the official Zig release, with the sha256 of its archive for each host.
- `llvm`: the LLVM tag and commit, the targets (`X86`, `AArch64`, `ARM`, `PowerPC`, `SPIRV`, `WebAssembly`) and the projects (`lld`); `zlib` and `zstd`: the version, release archive and sha256 of each.
- `qbe`: the QBE commit, and the target `qbe` emits by default on each host.
- `hosts`: the hosts a devkit is built for, each with the GitHub runner that tests it.

LLVM and QBE are git submodules (`llvm-project`, `qbe`) at the commits `devkit.json` names; CI fails if they differ.

QBE comes from [`cesiumlang/qbe`](https://github.com/cesiumlang/qbe), a mirror of upstream's `git://c9x.me/qbe.git` (its `master` and tags, unchanged, synced nightly), so that a build does not depend on one server. The devkit follows upstream as a dependency bot would: every Monday the **Follow QBE** workflow (`.github/workflows/follow-qbe.yml`) looks whether the mirror's `master` has commits the released devkit lacks, and if so opens a pull request into `main` from a branch named `qbe-updates-<commit>`, which moves the submodule and its pin and takes the next patch version. That pull request is a release of its own: CI builds and tests every host for it, merging it publishes the release, and CI merges `main` back into `dev`. An older update pull request that a newer one replaces is closed. The workflow acts as the Cesium Agent app, because what a workflow's own token pushes or opens starts no CI; it needs the secret `CESIUM_AGENT_PRIVATE_KEY`, a private key of that app.

The LLVM version follows LLVM's releases, independent of the version of the pinned Zig's own Clang, and it is compiled with that Zig. ADR 0001 asks only that: everything linked with these libraries must be compiled with the same Zig, so that the C++ standard library matches. When Zig is bumped, LLVM is rebuilt; a new LLVM release is a deliberate bump with a devkit release.

## Hosts

| Host triple | Tested on |
| --- | --- |
| `x86_64-linux-musl` | `ubuntu-24.04` |
| `aarch64-linux-musl` | `ubuntu-24.04-arm` |
| `x86_64-windows-gnu` | `windows-2025` |
| `aarch64-windows-gnu` | `windows-11-arm` |
| `x86_64-macos-none` | `macos-15-intel` |
| `aarch64-macos-none` | `macos-15` |

These are the hosts the compiler runs on. The targets it can emit code for are the same in every devkit.

QBE has no arm64 Windows target, so on `aarch64-windows-gnu` the `qbe` program defaults to `amd64_win`.

## Releases

A release `v<version>` holds, for every host:

- `cesium-devkit-<host triple>-<version>.tar.xz` (`.zip` for Windows hosts)
- `cesium-devkit-<host triple>-<version>.json`, a copy of the archive's `manifest.json`

and two files for the whole release:

- `devkits.json`: for each host, the archive's name, sha256 and URL
- `SHA256SUMS`

Releases are never changed once published. A new build takes a new version in `devkit.json`.

To use a devkit, read `devkits.json` of the release you pin, download the archive for your host, check its sha256, and unpack it.

## How a devkit is built

The **CI** workflow (`.github/workflows/ci.yml`) cross-compiles every host's devkit on Linux runners, then tests each one on the host's own runner:

1. **Zig:** `scripts/fetch-zig.sh` downloads the pinned official release and checks its sha256.
2. **QBE:** `scripts/build-qbe.sh <host>` compiles QBE with `zig cc`, once as the program and once with `-Dmain=qbe_main` as `libqbe.a`.
3. **zlib and zstd:** `scripts/build-compression.sh <host>` downloads their pinned release archives, checks their sha256, and compiles their library sources with `zig cc` into `libz.a` and `libzstd.a`.
4. **LLVM:** `scripts/build-llvm.sh <host>` builds a native `llvm-tblgen`, then LLVM and LLD for the host with `zig cc` and `zig c++` through CMake and Ninja. It builds with zlib and zstd. CMake runs only here.
5. **Package:** `scripts/package.sh <host>` assembles the archive and its manifest.
6. **Smoke test:** `scripts/smoke.sh <devkit>` runs on the host. Using only the devkit's own Zig, it compiles a C program, links a program against the LLVM and LLD libraries that emits objects for several targets and links ELF, COFF and Wasm outputs in-process, round-trips data through zlib and zstd, and runs QBE both as a program and through `libqbe.a`.
7. **Publish:** a push to `main` whose `devkit.json` version has no release yet publishes `v<version>`.

The LLVM build is long. Its objects are cached with ccache, and a build that reaches the time limit can be re-run to resume.

To build one locally on Linux (needs `cmake`, `ninja`, `jq`, `xz` and `zip`):

```sh
git submodule update --init --depth 1 llvm-project
git submodule update --init qbe
bash scripts/build-qbe.sh x86_64-linux-musl
bash scripts/build-compression.sh x86_64-linux-musl
bash scripts/build-llvm.sh x86_64-linux-musl
bash scripts/package.sh x86_64-linux-musl
```

Build output goes to `work/` and archives to `dist/`.

## What is not in a devkit

- **Clang and the LLVM tools.** The pinned Zig is the C and C++ compiler (`zig cc`), and Cesium links the LLVM libraries.
- **clangd.** `zig cc` is Clang, so clangd is the language server for the C that Zig compiles, but it is an editor tool and not needed to build. The [clangd extension for VS Code](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.vscode-clangd) offers to download clangd when none is on `PATH`; other editors use the clangd of the system's package manager.

## Branches

Changes are collected on `dev` through pull requests and released by merging `dev` into `main`, through the standing pull request from `dev` to `main`. CI runs for pull requests into `main` and pushes to `main`, not for `dev`: the standing pull request checks `dev` as a whole, and each merge into `dev` restarts its run; `gh workflow run ci.yml --ref BRANCH` checks one branch alone.

`devkit.json` holds the version the next release will have. A pull request into `main` that changes a devkit must carry a version that has no release yet. A push to `main` with such a version publishes it; CI then merges `main` back into `dev` and begins the next patch version there. For a minor or major release, set the version on `dev` by hand. Besides `dev`, pull requests into `main` come from the branches of automated updates (`qbe-updates-<commit>`), each a patch release of its own.

A push or pull request that changes only files listed in `no-ci.txt` (documentation, editor, workspace and lint configuration, workflows that build nothing) skips the host builds, and the required `CI` check passes at once. A pull request counts only its own changes, from where it branched off. Changes to the build scripts, `devkit.json`, `.gitmodules`, `.gitattributes`, `no-ci.txt`, the submodules and `ci.yml` always build (`ALWAYS` in `.github/scripts/changes.sh`).

## Licenses

This repository's own files are MIT (`LICENSE`). The devkits carry Zig (MIT), LLVM and LLD (Apache-2.0 WITH LLVM-exception), zlib (zlib License; `llvm/LICENSE-zlib`), zstd (BSD-3-Clause; `llvm/LICENSE-zstd`) and QBE (MIT), each under its own license.
