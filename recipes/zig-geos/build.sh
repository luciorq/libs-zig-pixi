#!/usr/bin/env bash
# GEOS's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-geos: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-geos: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

cmake -S . -B _build ${CMAKE_ARGS} \
  -DBUILD_GEOSOP=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_BENCHMARKS=OFF \
  -DBUILD_DOCUMENTATION=OFF
cmake --build _build
cmake --install _build

# lib<n>.a only, no shell scripts: GEOS installs geos-config into bin/
# (R packages read geos.pc on Windows).
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin"

# geos.pc: Libs -lgeos_c, Libs.private -lgeos -lstdc++ -lm; close-pc moves
# them into Libs and spells the C++ runtime -lc++, as proj.pc and gdal.pc
# (zig links its libc++ for either spelling).
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/geos.pc"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/geos/COPYING"
