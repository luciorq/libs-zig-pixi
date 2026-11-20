#!/usr/bin/env bash
# Cross-link tests/smoke/<lib>.c on linux against a built zig-<lib> package:
# extract the newest zig-<lib> .conda for <subdir> and zig-toolchain
# (linux-64) from $LIBS_ZIG_OUT into fresh prefixes, then compile with the
# triple's cc wrapper and `pkgconf --libs <lib>` (the closed, relocatable
# .pc at its extracted place). Writes $LIBS_ZIG_SMOKE (default
# $LIBS_ZIG_OUT/smoke)/<lib>-smoke-<arch>.exe
# and checks its PE machine. M0/M1 smoke tests are plain executables (D20).
#   usage: link.sh <lib> <subdir>     (pixi run smoke <lib> <subdir>)
set -euo pipefail
lib=$1 subdir=$2
: "${LIBS_ZIG_OUT:?run through pixi (pixi run smoke ...)}"
smoke="${LIBS_ZIG_SMOKE:-${LIBS_ZIG_OUT}/smoke}"
case "$subdir" in
  win-64) gnu=x86_64-w64-mingw32 zt=x86_64-windows-gnu arch=x86_64 ;;
  win-arm64) gnu=aarch64-w64-mingw32 zt=aarch64-windows-gnu arch=aarch64 ;;
  *) echo "subdir: win-64 or win-arm64" >&2; exit 2 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)
pkg=$(ls -t "${LIBS_ZIG_OUT}/${subdir}/zig-${lib}"-*.conda | head -1)
tc=$(ls -t "${LIBS_ZIG_OUT}/linux-64/zig-toolchain"-*.conda | head -1)
mkdir -p "$smoke"
work=$(mktemp -d "${smoke}/work.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
rattler-build package extract -q "$tc" -d "$work/tc"
rattler-build package extract -q "$pkg" -d "$work/pkg"
export PKG_CONFIG_LIBDIR="$work/pkg/Library/zig-libs/${zt}/lib/pkgconfig"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-${smoke}/zig-cache}"
flags="$(pkgconf --cflags "$lib") $(pkgconf --libs "$lib")"
out="${smoke}/${lib}-smoke-${arch}.exe"
echo "package: $pkg"
echo "flags: $flags"
"$work/tc/bin/${gnu}-cc" -O2 "$here/${lib}.c" $flags -o "$out"
"$work/tc/bin/zig-toolchain" pe-machine "$out"
echo "wrote $out"
