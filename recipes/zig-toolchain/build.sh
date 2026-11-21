#!/usr/bin/env bash
# zig-toolchain: the Zig multi-call binary, its data files, and the
# triple-named links to it. A baseline-CPU static linux binary (no libc).
set -euo pipefail
export ZIG_GLOBAL_CACHE_DIR="${SRC_DIR}/.zig-global-cache" ZIG_LOCAL_CACHE_DIR="${SRC_DIR}/.zig-local-cache"
case "${target_platform}" in
  linux-64) zt=x86_64-linux ;;
  linux-aarch64) zt=aarch64-linux ;;
  *) echo "zig-toolchain: no build for ${target_platform} yet" >&2; exit 1 ;;
esac
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig must be the variant's version
zig="${ZIG_BIN:-zig}"
v=$("$zig" version)
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-toolchain: $zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }
# the same line as every library build.sh: CI lists which zig ran (build.yml)
echo "zig-toolchain: ZIG_BIN='${ZIG_BIN:-}' zig version: $v ($(command -v "$zig"))"
"$zig" build test
"$zig" build -Doptimize=safe -Dtarget="${zt}" -Dcpu=baseline --prefix "${PREFIX}"
for t in x86_64-w64-mingw32 aarch64-w64-mingw32; do
  for tool in $("${PREFIX}/bin/zig-toolchain" tools); do
    ln -sf zig-toolchain "${PREFIX}/bin/${t}-${tool}"
  done
done
