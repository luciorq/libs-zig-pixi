#!/usr/bin/env bash
# nghttp2's own CMake build (D1), the library only, static only (D3), into
# the sub-prefix (D2). zig-toolchain's activation script set CMAKE_ARGS,
# ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-nghttp2: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-nghttp2: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# ENABLE_LIB_ONLY turns off the programs, HPACK tools and examples (and
# with them every optional dependency: OpenSSL, libev, c-ares, jansson,
# libxml2, ...). BUILD_SHARED_LIBS defaults ON; BUILD_TESTING follows
# BUILD_STATIC_LIBS, so it is set off; ENABLE_DOC defaults ON.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DENABLE_LIB_ONLY=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_STATIC_LIBS=ON \
  -DBUILD_TESTING=OFF \
  -DENABLE_DOC=OFF \
  -DENABLE_FAILMALLOC=OFF
cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
# lib<n>.a only. lib/cmake/nghttp2 goes: consumers (libcurl's CMake
# included) read libnghttp2.pc. share/ holds nghttp2's docs (README,
# fetch-ocsp-response) and man pages.
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
rm -rf "$z/bin" "$z/share" "$z/lib/cmake/nghttp2"
rmdir "$z/lib/cmake" 2>/dev/null || true

# libnghttp2.pc has no -DNGHTTP2_STATICLIB (the CMake target carries it as
# a usage requirement only): without it nghttp2.h declares every function
# __declspec(dllimport) on _WIN32, and a static link fails with undefined
# __imp_nghttp2_* symbols. It goes into Cflags, as Rtools45's .pc has it.
pcf="$z/lib/pkgconfig/libnghttp2.pc"
sed -i -E 's|^Cflags: (.*)$|Cflags: \1 -DNGHTTP2_STATICLIB|' "$pcf"
grep -E '^Cflags:.* -DNGHTTP2_STATICLIB$' "$pcf" >/dev/null \
  || { echo "zig-nghttp2: no -DNGHTTP2_STATICLIB in libnghttp2.pc:" >&2; cat "$pcf" >&2; exit 1; }
zig-toolchain close-pc "$pcf"
install -Dm644 COPYING "$z/licenses/nghttp2/COPYING"
