#!/usr/bin/env bash
# FreeType's own CMake build (D1), static only (D3), into the sub-prefix
# (D2), on zig-zlib, zig-libpng, zig-bzip2 and zig-brotli from the host env;
# no HarfBuzz (slice2 D122: zig-harfbuzz builds on this package, not the
# other way round). zig-toolchain's activation script set CMAKE_ARGS,
# ZIG_LIBS_PREFIX, PKG_CONFIG_LIBDIR, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-freetype: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-freetype: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# FT_REQUIRE_*: a missing dependency fails the configure step instead of
# quietly building without it.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DFT_REQUIRE_ZLIB=ON \
  -DFT_REQUIRE_PNG=ON \
  -DFT_REQUIRE_BZIP2=ON \
  -DFT_REQUIRE_BROTLI=ON \
  -DFT_DISABLE_HARFBUZZ=ON
cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
# lib/cmake/freetype goes: freetype-config.cmake links the dependencies as
# ZLIB::ZLIB, BZip2::BZip2 and PNG::PNG without finding them
# (no find_dependency) and Brotli as the build's absolute path to
# libbrotlidec.a, so it is neither usable nor relocatable; consumers read
# freetype2.pc (CMake's own FindFreetype does too).
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
rm -rf "$z/bin" "$z/lib/cmake/freetype"
rmdir "$z/lib/cmake" 2>/dev/null || true

# freetype2.pc: a static build already writes the dependencies into
# Requires (zlib, bzip2, libpng, libbrotlidec); close-pc makes it
# relocatable and checks no absolute path is left.
zig-toolchain close-pc "$z/lib/pkgconfig/freetype2.pc"
install -Dm644 -t "$z/licenses/freetype" LICENSE.TXT docs/FTL.TXT docs/GPLv2.TXT
