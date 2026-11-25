#!/usr/bin/env bash
# libpng's own CMake build (D1), static only (D3), into the sub-prefix (D2),
# on zig-zlib from the host env. zig-toolchain's activation script set
# CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libpng: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libpng: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

cmake -S . -B _build ${CMAKE_ARGS} \
  -DPNG_SHARED=OFF \
  -DPNG_STATIC=ON \
  -DPNG_TESTS=OFF \
  -DPNG_TOOLS=OFF
cmake --build _build
cmake --install _build

# On a linux build host libpng's CMake installs lib/libpng.a and
# lib/pkgconfig/libpng.pc as symlinks to libpng16.a and libpng16.pc. A
# Windows install cannot rely on symlinks: one real file per name (-lpng
# and libpng.pc are what configure scripts and Makevars.win name).
z="${ZIG_LIBS_PREFIX}"
for f in lib/libpng.a lib/pkgconfig/libpng.pc; do
  if [ -L "$z/$f" ]; then cp --remove-destination "$(readlink -f "$z/$f")" "$z/$f"; fi
done
# No libpng-config scripts (bin/, absolute build prefix in them; the .pc
# files say the same), no man pages. lib/cmake/PNG stays: PNGTargets.cmake
# finds the prefix from its own location (_IMPORT_PREFIX) and names zlib as
# the ZLIB::ZLIB target. lib/libpng/libpng16.cmake goes: a second export
# of the same target without the PNG:: namespace, for include() by path
# (find_package(PNG CONFIG) reads lib/cmake/PNG).
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
rm -rf "$z/bin" "$z/share/man" "$z/lib/libpng"
rmdir "$z/share" 2>/dev/null || true

# libpng16.pc: Requires.private zlib, Libs.private -lz -lm; close-pc moves
# them into Requires and Libs (a static -lpng16 needs zlib).
zig-toolchain close-pc "$z/lib/pkgconfig/libpng16.pc" "$z/lib/pkgconfig/libpng.pc"
install -Dm644 LICENSE "$z/licenses/libpng/LICENSE"
