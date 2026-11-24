#!/usr/bin/env bash
# HarfBuzz's own meson build (D1), cross through zig-toolchain's meson cross
# file (slice2 D119), static only (D3), into the sub-prefix (D2), on
# zig-freetype from the host env and nothing else (slice2 D122: no GLib,
# ICU, Graphite2 or Cairo; HarfBuzz's own Unicode data).
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
: "${ZIG_TOOLCHAIN_MESON_CROSS:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-harfbuzz: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-harfbuzz: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# Every optional dependency off by name ('auto' would pick up whatever the
# pkg-config path offers), freetype required. gdi and directwrite (Windows
# shapers, off by default) stay off: they would add Windows system
# libraries and, for DirectWrite, the C++ runtime.
meson setup _build . \
  --cross-file "${ZIG_TOOLCHAIN_MESON_CROSS}" \
  --prefix="${ZIG_LIBS_PREFIX}" --libdir=lib \
  --buildtype=release \
  -Ddefault_library=static \
  -Dfreetype=enabled \
  -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled \
  -Dicu=disabled -Dgraphite=disabled -Dgraphite2=disabled \
  -Dgdi=disabled -Ddirectwrite=disabled \
  -Ddocs=disabled -Dtests=disabled -Dintrospection=disabled \
  -Dutilities=disabled -Dbenchmark=disabled
ninja -C _build -j"${CPU_COUNT:-2}"
meson install -C _build

z="${ZIG_LIBS_PREFIX}"
# lib/cmake/harfbuzz goes: harfbuzz-config.cmake is relocatable, but its
# static harfbuzz::harfbuzz target links no FreeType (a consumer gets
# undefined FT_* symbols) and it declares harfbuzz::icu for a
# libharfbuzz-icu.a this build does not have; consumers read harfbuzz.pc.
# Only harfbuzz's own directory: lib/cmake/ also holds zig-libpng's PNG/
# from the host env.
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
rm -rf "$z/bin" "$z/lib/cmake/harfbuzz"

# harfbuzz.pc: Requires.private freetype2, Libs.private -lm; close-pc
# moves them into Requires and Libs and makes both files relocatable. No
# C++ runtime to name: HarfBuzz compiles without exceptions and RTTI and
# meson links it as C (with_libstdcxx=false), so libharfbuzz.a references
# no libc++ symbol (tests/smoke/harfbuzz.c links with `zig cc`).
zig-toolchain close-pc "$z/lib/pkgconfig/harfbuzz.pc" "$z/lib/pkgconfig/harfbuzz-subset.pc"
install -Dm644 COPYING "$z/licenses/harfbuzz/COPYING"
