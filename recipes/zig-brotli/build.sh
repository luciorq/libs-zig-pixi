#!/usr/bin/env bash
# brotli's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-brotli: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-brotli: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# BUILD_SHARED_LIBS=OFF (CMAKE_ARGS) without BROTLI_BUILD_FOR_PACKAGE: the
# static targets keep their plain names (libbrotlicommon.a, ..., what the
# .pc files' -l words say), no -static suffixed copies. No brotli program;
# its round-trip tests need the program.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DBROTLI_BUILD_TOOLS=OFF \
  -DBROTLI_DISABLE_TESTS=ON
cmake --build _build
cmake --install _build

# lib<n>.a only; no man pages (brotli installs its API man3 pages always).
# brotli installs no CMake package config.
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share/man"
rmdir "${ZIG_LIBS_PREFIX}/share" 2>/dev/null || true

# libbrotlidec.pc and libbrotlienc.pc: Requires.private libbrotlicommon;
# close-pc moves it into Requires (consumers need -lbrotlicommon with a
# static -lbrotlidec).
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
zig-toolchain close-pc "${pc}/libbrotlicommon.pc" "${pc}/libbrotlidec.pc" "${pc}/libbrotlienc.pc"
install -Dm644 LICENSE "${ZIG_LIBS_PREFIX}/licenses/brotli/LICENSE"
