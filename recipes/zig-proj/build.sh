#!/usr/bin/env bash
# PROJ's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-proj: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-proj: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# SQLite3 (find_package) comes from zig-sqlite in the sub-prefix through
# the toolchain file's root path; EXE_SQLITE3 is the build env's sqlite3,
# named explicitly so the cross find cannot pick anything else.
# EMBED_RESOURCE_FILES: PROJ's static default (ON), kept explicit (D16).
# EMBED_PROJ_DATA_PATH=OFF: no install path compiled into libproj.a (it
# would be the rattler-build host prefix, a build path, D22); the data
# are found through PROJ_DATA (R packages set it to their copied
# share/proj) or the embedded proj.db.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DENABLE_TIFF=OFF \
  -DENABLE_CURL=OFF \
  -DBUILD_APPS=OFF \
  -DBUILD_TESTING=OFF \
  -DEMBED_RESOURCE_FILES=ON \
  -DEMBED_PROJ_DATA_PATH=OFF \
  -DEXE_SQLITE3="${BUILD_PREFIX}/bin/sqlite3"
grep -E '^(SQLite3_(INCLUDE_DIR|LIBRARY)|EMBED_[A-Z_]*|IS_SHARP_EMBED_AVAILABLE[A-Z_]*):' _build/CMakeCache.txt || true
grep -q '^EMBED_RESOURCE_FILES:BOOL=ON$' _build/CMakeCache.txt
for k in SQLite3_INCLUDE_DIR SQLite3_LIBRARY; do
  p=$(sed -n "s/^${k}:[A-Z]*=//p" _build/CMakeCache.txt)
  case "$p" in
    "${ZIG_LIBS_PREFIX}"/*) ;;
    *) echo "zig-proj: ${k}=${p} is not in ${ZIG_LIBS_PREFIX}" >&2; exit 1 ;;
  esac
done
cmake --build _build
cmake --install _build

# lib<n>.a only. scripts/CMakeLists.txt installs the projinfo/cs2cs bash
# completions even with BUILD_APPS=OFF. No CMake package config
# (lib/cmake/proj, lib/cmake/proj4): its link interface names the system
# libraries as shell32.lib/ole32.lib, which no MinGW link resolves, and
# proj.pc is the interface (DESIGN 5.5); zig-gdal finds PROJ through its
# own FindPROJ module.
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share/man" "${ZIG_LIBS_PREFIX}/share/doc" \
  "${ZIG_LIBS_PREFIX}/share/bash-completion" "${ZIG_LIBS_PREFIX}/lib/cmake/proj" \
  "${ZIG_LIBS_PREFIX}/lib/cmake/proj4"
rmdir "${ZIG_LIBS_PREFIX}/lib/cmake" 2>/dev/null || true

# proj.pc as installed: Requires.private sqlite3 and an empty Libs.private
# (PROJ's MinGW branch of configure_proj_pc lists the C++ implicit link
# libraries, none for zig c++, and leaves out ole32/shell32). close-pc
# moves sqlite3 into Requires and appends what libproj.a needs: libc++
# (zig links its own libc++ for -lc++, so a C program links through
# `pkgconf --libs proj` alone) and the two system libraries
# src/lib_proj.cmake links on WIN32.
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig/proj.pc"
echo "zig-proj: proj.pc as installed:"; cat "$pc"
zig-toolchain close-pc --libs "-lc++ -lole32 -lshell32" "$pc"
echo "zig-proj: proj.pc closed:"; cat "$pc"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/proj/COPYING"
