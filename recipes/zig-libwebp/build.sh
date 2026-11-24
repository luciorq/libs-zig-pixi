#!/usr/bin/env bash
# libwebp's own CMake build (D1), static only (D3), into the sub-prefix
# (D2): the libraries only, none of the tools. zig-toolchain's activation
# script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libwebp: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libwebp: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# WEBP_ENABLE_SIMD (the default): cmake/cpu.cmake builds the SSE2 code
# (x86_64 baseline), the SSE4.1 and AVX2 files with per-file -msse4.1 and
# -mavx2, and the NEON code (aarch64 baseline). libwebp picks the SSE4.1
# and AVX2 paths at run time (VP8GetCPUInfo, cpuid), so a baseline CPU still
# runs the archive.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DWEBP_ENABLE_SIMD=ON \
  -DWEBP_BUILD_ANIM_UTILS=OFF \
  -DWEBP_BUILD_CWEBP=OFF \
  -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF \
  -DWEBP_BUILD_IMG2WEBP=OFF \
  -DWEBP_BUILD_VWEBP=OFF \
  -DWEBP_BUILD_WEBPINFO=OFF \
  -DWEBP_BUILD_WEBPMUX=OFF \
  -DWEBP_BUILD_EXTRAS=OFF \
  -DWEBP_BUILD_LIBWEBPMUX=ON
cmake --build _build
cmake --install _build

rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share/man"
# share/WebP/cmake stays: install(EXPORT) and configure_package_config_file
# locate the prefix from the file's own directory, so it is relocatable
# (WebP::webp, WebP::sharpyuv, ...). Its targets also name shlwapi, ole32
# and windowscodecs (deps.cmake adds them whenever wincodec.h exists, for
# the tools' WIC image readers); the archives import only kernel32 and CRT
# functions, and the .pc files do not name them.

# upstream's .pc files: Requires.private libsharpyuv (libwebp), libwebp
# (demux, mux); Libs.private is empty here (CMake drops -lm, Threads adds no
# library on MinGW). close-pc merges them into Requires and makes them
# relocatable (DESIGN 5.5).
for pc in "${ZIG_LIBS_PREFIX}"/lib/pkgconfig/lib{webp,sharpyuv,webpdecoder,webpdemux,webpmux}.pc; do
  zig-toolchain close-pc "${pc}"
done
for f in COPYING PATENTS; do
  install -Dm644 "$f" "${ZIG_LIBS_PREFIX}/licenses/libwebp/$f"
done
