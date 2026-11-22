#!/usr/bin/env bash
# Cross-link smoke sources on linux against the built zig-* packages and
# keep the executables (to run them on a Windows host by hand). The newest
# .conda of every zig-* package for <subdir> in $LIBS_ZIG_OUT is extracted
# into one fresh prefix, so a .pc's Requires (gdal, proj, openssl) resolve,
# and tests/pkgtest.zig runs there with $PREFIX set: the package test's
# checks and its link (`zig cc` for .c, `zig c++` for .cpp/.cc/.cxx), the
# executables written to $LIBS_ZIG_SMOKE (default $LIBS_ZIG_OUT/smoke) as
# <source stem>[-<ext>]-smoke-<arch>.exe. The archive checks that need
# llvm-tools (--libcxx, ...) are the package test's, not repeated here.
#   usage: link.sh <subdir> <pc module>[,<pc module>...] <source>[,<source>...]
#   pixi run smoke <pc modules> <sources> [<subdir>]
#     e.g. pixi run smoke sqlite3 sqlite.c win-arm64
#          pixi run smoke geos geos.c,geos.cpp
# A source without a slash is a file in tests/smoke/.
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: link.sh <subdir> <pc modules> <sources>" >&2; exit 2; }
subdir=$1 modules=$2 sources=$3
: "${LIBS_ZIG_OUT:?run through pixi (pixi run smoke ...)}"
smoke="${LIBS_ZIG_SMOKE:-${LIBS_ZIG_OUT}/smoke}"
case "$subdir" in
  win-64) zt=x86_64-windows-gnu ;;
  win-arm64) zt=aarch64-windows-gnu ;;
  *) echo "subdir: win-64 or win-arm64" >&2; exit 2 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)
srcs=()
IFS=, read -ra list <<< "$sources"
for s in "${list[@]}"; do
  case "$s" in */*) srcs+=("$(realpath "$s")") ;; *) srcs+=("$here/$s") ;; esac
done
mkdir -p "$smoke"
work=$(mktemp -d "${smoke}/work.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
# the newest .conda of each package
declare -A pick
for f in "${LIBS_ZIG_OUT}/${subdir}"/zig-*.conda; do
  n=$(basename "$f" .conda); n=${n%-*-*}
  if [ -z "${pick[$n]:-}" ] || [ "$f" -nt "${pick[$n]}" ]; then pick[$n]=$f; fi
done
for f in "${pick[@]}"; do
  echo "package: $f"
  rattler-build package extract -q "$f" -d "$work/prefix" > /dev/null
done
touch "$work/start"
cd "$smoke"
PREFIX="$work/prefix" zig run \
  --global-cache-dir "${ZIG_GLOBAL_CACHE_DIR:-${smoke}/zig-cache}" --cache-dir "$work/zig-local-cache" \
  "$here/../pkgtest.zig" -- "$zt" "$modules" "${srcs[@]}"
echo "wrote:"; find "$smoke" -maxdepth 1 -name '*-smoke-*.exe' -newer "$work/start"
