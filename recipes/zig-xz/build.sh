#!/usr/bin/env bash
# XZ Utils' own CMake build (D1), liblzma only, static only (D3), into the
# sub-prefix (D2). zig-toolchain's activation script set CMAKE_ARGS,
# ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-xz: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-xz: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# XZ_THREADS=yes picks Windows (Vista) threads on a 64-bit Windows target,
# so liblzma.pc gets no -pthread. XZ_NLS off: no libintl in the
# sub-prefix, and only the tools have translations. XZ_TOOL_SCRIPTS is a
# UNIX-only option.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DXZ_TOOL_XZ=OFF \
  -DXZ_TOOL_XZDEC=OFF \
  -DXZ_TOOL_LZMADEC=OFF \
  -DXZ_TOOL_LZMAINFO=OFF \
  -DXZ_DOC=OFF \
  -DXZ_NLS=OFF \
  -DXZ_THREADS=yes \
  -DBUILD_TESTING=OFF
cmake --build _build
cmake --install _build

# lib<n>.a only: with a MinGW compiler XZ Utils' CMake names the static
# archive liblzma.a (its .pc says -llzma).
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share"

# liblzma.pc carries -DLZMA_API_STATIC in Cflags.private; close-pc merges
# it into Cflags, which static consumers need (lzma.h dllimports
# otherwise, for compilers that are not GNU-like).
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/liblzma.pc"
# liblzma is 0BSD; COPYING says which licence covers which part
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/xz/COPYING"
install -Dm644 COPYING.0BSD "${ZIG_LIBS_PREFIX}/licenses/xz/COPYING.0BSD"
