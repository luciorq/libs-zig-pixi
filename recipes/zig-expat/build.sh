#!/usr/bin/env bash
# expat's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-expat: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-expat: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

cmake -S . -B _build ${CMAKE_ARGS} \
  -DEXPAT_SHARED_LIBS=OFF \
  -DEXPAT_BUILD_TOOLS=OFF \
  -DEXPAT_BUILD_EXAMPLES=OFF \
  -DEXPAT_BUILD_TESTS=OFF \
  -DEXPAT_BUILD_DOCS=OFF \
  -DEXPAT_BUILD_FUZZERS=OFF \
  -DEXPAT_BUILD_PKGCONFIG=ON
cmake --build _build
cmake --install _build

# lib<n>.a only: with a GNU-style (non-MSVC) compiler expat's CMake names
# the static archive libexpat.a (no MD/MT postfix) and its .pc says -lexpat;
# the test below checks both.
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share/doc" "${ZIG_LIBS_PREFIX}/share/man"
rmdir "${ZIG_LIBS_PREFIX}/share" 2>/dev/null || true

# expat.pc carries -DXML_STATIC in Cflags.private; close-pc merges it into
# Cflags, which static consumers need (expat_external.h dllimports
# otherwise under -fms-extensions), and -lm from Libs.private into Libs.
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/expat.pc"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/expat/COPYING"
