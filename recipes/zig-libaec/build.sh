#!/usr/bin/env bash
# libaec's own CMake build (D1), static only (D3), into the sub-prefix
# (D2). zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX,
# CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libaec: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libaec: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# src/CMakeLists.txt always builds a static and a shared copy of each
# library (BUILD_SHARED_LIBS is not read) and installs the DLLs, the aec
# tool and its man page with them. Only the two static targets are built
# (MXE patches the CMakeLists to the same effect, aec-1-fixes.patch):
# libaec.a (aec_*) and libsz.a (the SZ_* szip API in sz_compat.c plus the
# aec_* objects again, so -lsz alone links, as Rtools45's hdf5.pc uses it).
cmake -S . -B _build ${CMAKE_ARGS} -DBUILD_TESTING=OFF
cmake --build _build --target aec_static sz_static

# By hand instead of `cmake --install`: install(TARGETS) names the shared
# targets and aec_client too, and the headers are the shared targets'
# PUBLIC_HEADER. Nothing else is installed: no bin/ (aec.exe, the DLLs),
# no man page, no cmake/ config dir (libaec-config.cmake describes the
# shared library).
z="${ZIG_LIBS_PREFIX}"
install -Dm644 _build/src/libaec.a "$z/lib/libaec.a"
install -Dm644 _build/src/libsz.a "$z/lib/libsz.a"
install -Dm644 -t "$z/include" include/libaec.h include/szlib.h

# Upstream ships no .pc file. libaec.pc for the aec_* API; szip.pc for
# szlib.h's SZ_* API (the name HDF5's and netCDF's builds look for): -lsz
# only, since libsz.a carries the aec_* objects itself and -lsz -laec
# would put each aec_* symbol in two archives of one link. Neither needs a
# define: LIBAEC_DLL_EXPORTED is empty on Windows (no dllimport).
pc="$z/lib/pkgconfig"
mkdir -p "$pc"
cat > "$pc/libaec.pc" <<PC
prefix=/zig-libs/$(basename "$z")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libaec
Description: Adaptive Entropy Coding library (CCSDS 121.0-B)
URL: https://gitlab.dkrz.de/k202009/libaec
Version: ${PKG_VERSION}
Libs: -L\${libdir} -laec
Cflags: -I\${includedir}
PC
cat > "$pc/szip.pc" <<PC
prefix=/zig-libs/$(basename "$z")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: szip
Description: libaec's szip-compatible SZ_* API (szlib.h)
URL: https://gitlab.dkrz.de/k202009/libaec
Version: ${PKG_VERSION}
Libs: -L\${libdir} -lsz
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "$pc/libaec.pc" "$pc/szip.pc"
install -Dm644 LICENSE.txt "$z/licenses/libaec/LICENSE.txt"
