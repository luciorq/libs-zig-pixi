#!/usr/bin/env bash
# HDF4's own CMake build (D1), static only (D3), into the sub-prefix (D2),
# on zig-zlib, zig-libjpeg and zig-libaec (szip) from the host env (slice2
# D127 C). Only the two C libraries (libdf.a, libmfhdf.a), HDF4's own XDR
# (libxdr.a) and their headers: no Fortran, Java, tools, utilities,
# examples or tests. zig-toolchain's activation script set CMAKE_ARGS,
# ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-hdf4: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-hdf4: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# CMake rather than MXE's autotools: HDF4's configure knows no MinGW host
# (MXE patches configure.ac and reruns autoreconf), while its CMake build
# is the HDF Group's Windows build. On Windows it always builds HDF4's
# bundled XDR (mfhdf/xdr, HDF4_BUILD_XDR_LIB forced ON), so no separate
# portablexdr as in MXE.
# HDF4_ENABLE_NETCDF=OFF is MXE's --disable-netcdf: HDF4's netCDF-2 API
# (ncopen, ncvarget, ...) is renamed sd_* (hdf2netcdf.h) and the header is
# hdf4_netcdf.h, so libmfhdf.a and netcdf-c's libnetcdf.a link together.
# szip: the first find_package(SZIP) is config mode and finds nothing;
# HDF4's fallback FindSZIP.cmake (config/cmake_ext_mod) finds libsz.a and
# szlib.h through the toolchain file's CMAKE_FIND_ROOT_PATH (the
# sub-prefix). JPEG and ZLIB: CMake's own FindJPEG and FindZLIB likewise.
# Two try_run probes cannot run in a cross build and fail the configure
# step; their answers go in as cache variables. H4_PRINTF_LL_WIDTH: a
# printf width probe; "ll" is UCRT's, and no source or generated header
# reads the value. TEST_LFS_WORKS_RUN=1 ("no"): no -D_FILE_OFFSET_BITS=64
# -D_LARGEFILE64_SOURCE on the library, as MXE's autotools build; HDF4
# files are limited to 32-bit offsets anyway.
# -DH4_HAVE_WINSOCK2_H: as MXE's hdf4.mk. CMake detects winsock2.h, but
# config/cmake/h4config.h.in has no line for it, so the XDR's xdrstdio.c
# never includes it and calls htonl/ntohl undeclared (an error in clang).
# -Wno-implicit-int -Wno-incompatible-pointer-types: as MXE's hdf4.mk; the
# K&R-style XDR code (mfhdf/libsrc/xdrposix.c) puts long-returning
# functions in xdr_ops' u_int slots, an error in clang since 16. long and
# u_int are both 32 bits on Windows, so the calls are right.
CFLAGS="${CFLAGS} -DH4_HAVE_WINSOCK2_H -Wno-implicit-int -Wno-incompatible-pointer-types" cmake -S . -B _build ${CMAKE_ARGS} \
  -DH4_PRINTF_LL_WIDTH='"ll"' \
  -DTEST_LFS_WORKS_RUN=1 \
  -DBUILD_STATIC_LIBS=ON \
  -DONLY_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DHDF4_BUILD_FORTRAN=OFF \
  -DHDF4_BUILD_JAVA=OFF \
  -DHDF4_BUILD_TOOLS=OFF \
  -DHDF4_BUILD_UTILS=OFF \
  -DHDF4_BUILD_EXAMPLES=OFF \
  -DHDF4_NO_PACKAGES=ON \
  -DHDF4_ENABLE_NETCDF=OFF \
  -DHDF4_ENABLE_JPEG_LIB_SUPPORT=ON \
  -DHDF4_ENABLE_Z_LIB_SUPPORT=ON \
  -DHDF4_ENABLE_SZIP_SUPPORT=ON \
  -DHDF4_ENABLE_SZIP_ENCODING=ON | tee _configure.log
for f in "JPEGLIB is ON" "Filter ZLIB is ON" "Filter SZIP is ON"; do
  grep -F -- "-- ${f}" _configure.log >/dev/null \
    || { echo "zig-hdf4: '${f}' missing from the configure output" >&2; exit 1; }
done
for d in H4_HAVE_LIBJPEG H4_HAVE_LIBZ H4_HAVE_LIBSZ H4_HAVE_SZIP_ENCODER H4_NO_SYS_XDR_INC; do
  grep -E "^#define ${d} 1" _build/h4config.h >/dev/null \
    || { echo "zig-hdf4: ${d} not set in h4config.h" >&2; exit 1; }
done
if grep -E '^#define H4_HAVE_NETCDF' _build/h4config.h; then
  echo "zig-hdf4: H4_HAVE_NETCDF set (the netCDF-2 API would not be renamed)" >&2; exit 1
fi
cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
# CMake names the core library libhdf.a; Rtools45 (autotools) and every
# -ldf in configure scripts and Makevars.win use libdf.a.
mv "$z/lib/libhdf.a" "$z/lib/libdf.a"
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
# hdf-4.2.15.pc goes (-lhdf -lmfhdf, absolute prefix, no dependencies),
# replaced by Rtools45's df.pc and mfhdf.pc below; the CMake package
# config (cmake/ at the prefix root) and the share/ readme files go:
# hdf4-targets.cmake names libhdf.a and the build's absolute library paths.
rm -f "$z/lib/pkgconfig/hdf-${PKG_VERSION}.pc"
rm -rf "$z/bin" "$z/cmake" "$z/share" "$z/lib/cmake"
rm -f "$z"/COPYING "$z"/RELEASE.txt "$z"/README.txt "$z"/USING_HDF4_CMake.txt "$z"/USING_HDF4_VS.txt
# libhdf4.settings: a build summary with the build's absolute paths.
rm -f "$z/lib/libhdf4.settings"
# mfhdf/libsrc's private error.h and alloc.h: CMake installs them, the
# autotools build (Rtools45) does not, and no installed header includes
# them. In the shared include/ error.h would shadow MinGW's <error.h>
# (Windows error codes) for every consumer of the sub-prefix.
rm -f "$z/include/error.h" "$z/include/alloc.h"

# df.pc and mfhdf.pc as in Rtools45's tree (MXE's hdf4.mk writes them;
# Name hdf4 in both), with szip in df's Requires and HDF4's XDR (libxdr.a,
# htonl/ntohl from ws2_32) in mfhdf's Libs where Rtools45 has
# -lportablexdr. No define in Cflags: H4api_adpt.h declares plain extern
# unless H4_BUILT_AS_DYNAMIC_LIB (a DLL build) is defined.
pc="$z/lib/pkgconfig"
mkdir -p "$pc"
cat > "$pc/df.pc" <<PC
prefix=/zig-libs/$(basename "$z")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: hdf4
Description: HDF4
Version: ${PKG_VERSION}
Requires: libjpeg zlib szip
Libs: -L\${libdir} -ldf
Cflags: -I\${includedir}
PC
cat > "$pc/mfhdf.pc" <<PC
prefix=/zig-libs/$(basename "$z")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: hdf4
Description: HDF4
Version: ${PKG_VERSION}
Requires: df
Libs: -L\${libdir} -lmfhdf -lxdr -lws2_32
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "$pc/df.pc" "$pc/mfhdf.pc"
install -Dm644 COPYING "$z/licenses/hdf4/COPYING"
# the bundled XDR's licence: Sun's 2009 BSD-3-Clause notice, the header
# comment of each mfhdf/xdr source (xdr.c's first 27 lines)
sed -n '1,27p' mfhdf/xdr/xdr.c > "$z/licenses/hdf4/xdr-LICENSE"
