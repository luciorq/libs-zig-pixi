#!/usr/bin/env bash
# zstd's own CMake build (D1; build/cmake), static only (D3), into the
# sub-prefix (D2). zig-toolchain's activation script set CMAKE_ARGS,
# ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-zstd: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-zstd: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# ZSTD_MULTITHREAD_SUPPORT is ON by default (not Android): on _WIN32
# lib/common/threading.h uses Windows threads, so libzstd.pc gets no
# -pthread and nothing to link beyond libzstd.a.
cmake -S build/cmake -B _build ${CMAKE_ARGS} \
  -DZSTD_BUILD_STATIC=ON \
  -DZSTD_BUILD_SHARED=OFF \
  -DZSTD_BUILD_PROGRAMS=OFF \
  -DZSTD_BUILD_TESTS=OFF \
  -DZSTD_BUILD_CONTRIB=OFF \
  -DZSTD_MULTITHREAD_SUPPORT=ON
cmake --build _build
cmake --install _build

# lib<n>.a only: with a MinGW compiler zstd's CMake names the static
# archive libzstd.a (zstd_static only for MSVC and clang-cl).
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share"

zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/libzstd.pc"
# dual licence: BSD-3-Clause (LICENSE) or GPL-2.0-only (COPYING)
install -Dm644 LICENSE "${ZIG_LIBS_PREFIX}/licenses/zstd/LICENSE"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/zstd/COPYING"
