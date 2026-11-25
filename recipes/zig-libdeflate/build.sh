#!/usr/bin/env bash
# libdeflate's own CMake build (D1), static only (D3), into the sub-prefix
# (D2). zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX,
# CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libdeflate: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libdeflate: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

cmake -S . -B _build ${CMAKE_ARGS} \
  -DLIBDEFLATE_BUILD_STATIC_LIB=ON \
  -DLIBDEFLATE_BUILD_SHARED_LIB=OFF \
  -DLIBDEFLATE_BUILD_GZIP=OFF \
  -DLIBDEFLATE_BUILD_TESTS=OFF
cmake --build _build
cmake --install _build

# lib<n>.a only: with a MinGW compiler libdeflate's CMake names the static
# archive libdeflate.a (deflatestatic only for MSVC and clang-cl), which
# libdeflate.pc's -ldeflate finds.
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share"

zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/libdeflate.pc"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/libdeflate/COPYING"
