#!/usr/bin/env bash
# libtiff's own CMake build (D1), static only (D3), into the sub-prefix
# (D2), on the codec libraries of the host env's zig-* packages (slice2
# D122 B). zig-toolchain's activation script set CMAKE_ARGS,
# ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libtiff: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libtiff: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# libtiff finds its codecs with its own Find modules (cmake/Find*.cmake)
# and CMake's FindZLIB/FindJPEG: find_path/find_library through the
# toolchain file's CMAKE_FIND_ROOT_PATH, that is the sub-prefix only. Each
# codec is switched ON explicitly; the check below fails the build when one
# was not found (the option alone does not). liblzma's CMake target here is
# Findliblzma's, which does not carry liblzma.pc's -DLZMA_API_STATIC, so it
# goes in CFLAGS: lzma.h dllimports without it for compilers that are not
# GNU-like (zig cc is, so this keeps the objects as the .pc describes them).
# tiff-cxx OFF: no libtiffxx (the R packages use the C API only).
CFLAGS="${CFLAGS} -DLZMA_API_STATIC" cmake -S . -B _build ${CMAKE_ARGS} \
  -Dtiff-tools=OFF \
  -Dtiff-tests=OFF \
  -Dtiff-contrib=OFF \
  -Dtiff-docs=OFF \
  -Dtiff-cxx=OFF \
  -Dtiff-opengl=OFF \
  -Dzlib=ON \
  -Dlibdeflate=ON \
  -Djpeg=ON \
  -Dold-jpeg=ON \
  -Djpeg12=OFF \
  -Dwebp=ON \
  -Dzstd=ON \
  -Dlzma=ON \
  -Dlerc=OFF \
  -Djbig=OFF \
  -Dsphinx=OFF | tee _configure.log
for codec in ZLIB libdeflate JPEG LZMA2 ZSTD WEBP; do
  grep -E "^-- +${codec} support: +Requested:ON .*Support:TRUE" _configure.log >/dev/null \
    || { echo "zig-libtiff: codec '${codec}' not enabled (see the summary above)" >&2; exit 1; }
done
cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
rm -rf "$z/bin" "$z/share"
# lib/cmake/tiff goes: TiffTargets.cmake gives the static TIFF::tiff
# $<LINK_ONLY:ZLIB::ZLIB>, Deflate::Deflate, JPEG::JPEG, liblzma::liblzma,
# ZSTD::ZSTD and WebP::webp, and TiffConfig.cmake never defines those
# targets (upstream's "TODO: import dependencies"), so a consumer's
# find_package(Tiff CONFIG) fails at generate time. CMake's own FindTIFF
# module and libtiff-4.pc remain.
rm -rf "$z/lib/cmake/tiff"
rmdir "$z/lib/cmake" 2>/dev/null || true

# libtiff-4.pc: Requires.private names every codec module (zlib libdeflate
# libjpeg liblzma libzstd libwebp); close-pc moves them into Requires,
# which a static -ltiff needs.
zig-toolchain close-pc "$z/lib/pkgconfig/libtiff-4.pc"
install -Dm644 LICENSE.md "$z/licenses/libtiff/LICENSE.md"
