#!/usr/bin/env bash
# FriBidi's own meson build (D1), cross through zig-toolchain's meson cross
# file (slice2 D119), static only (D3), into the sub-prefix (D2): the
# library only (no fribidi program, tests or docs).
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
: "${ZIG_TOOLCHAIN_MESON_CROSS:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-fribidi: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-fribidi: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# gen.tab/ builds the Unicode table generators for the build machine
# (native: true) and runs them. A native file names `zig cc` as the build
# machine's C compiler, as `zig-toolchain configure` sets CC_FOR_BUILD:
# never a compiler of the build machine itself (D97).
cat > _native.ini <<INI
[binaries]
c = ['${zig_bin:-zig}', 'cc']
INI
CFLAGS="-O2 ${CFLAGS}" \
meson setup _build . \
  --cross-file "${ZIG_TOOLCHAIN_MESON_CROSS}" \
  --native-file _native.ini \
  --prefix="/zig-libs/${ZIG_TOOLCHAIN_TARGET}" --libdir=lib \
  --buildtype=release \
  -Ddefault_library=static \
  -Ddocs=false -Dbin=false -Dtests=false
ninja -C _build -j"${CPU_COUNT:-2}"
meson install -C _build --destdir "${PREFIX}/Library"

# meson's fribidi.pc: Cflags -I${includedir}/fribidi -DFRIBIDI_LIB_STATIC
# (meson.build's extra_cflags for a static Windows build: without it
# fribidi-common.h declares the API dllimport); closed and relocatable
# (DESIGN 5.5).
grep -q -- '-DFRIBIDI_LIB_STATIC' "${ZIG_LIBS_PREFIX}/lib/pkgconfig/fribidi.pc"
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/fribidi.pc"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/fribidi/COPYING"
