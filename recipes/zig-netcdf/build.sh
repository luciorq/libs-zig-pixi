#!/usr/bin/env bash
# netCDF-C's own CMake build (D1), the library only, static only (D3), into
# the sub-prefix (D2), on zig-hdf5, zig-hdf4, zig-libcurl, zig-libxml2,
# zig-libaec, zig-zlib and zig-libjpeg from the host env (slice2 D126 B).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
: "${ZIG_TOOLCHAIN_TARGET:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-netcdf: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-netcdf: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

z="${ZIG_LIBS_PREFIX}"

# MXE's netcdf.mk options (Rtools45): netCDF-4 on HDF5, HDF4, DAP2/DAP4
# (ENABLE_DAP's default) and NCZarr (ENABLE_NCZARR's default; file store
# only, no zip), no utilities, tests, examples or docs. HDF5 given as the
# three paths, as MXE does: CMake's FindHDF5 runs h5cc or reads HDF5's
# CMake config, which zig-hdf5 does not ship.
# Off where MXE leaves the default on: ENABLE_BYTERANGE (HTTP range reads
# of remote files; Rtools45 has it, this package leaves it out). S3 is
# off in MXE too (no AWS SDK).
# ENABLE_PLUGINS: off as on every MinGW build (CMakeLists.txt forces it),
# said explicitly; no filter plugin DLLs, no plugin install dir.
# Zstd, Blosc, Bz2: not searched. Rtools45's build finds its libzstd,
# libblosc and libbz2, which only switches on nc_def_var_zstandard and
# nc_def_var_blosc, whose filters are HDF5 plugin DLLs netCDF does not
# build on MinGW, and puts the libraries in its link line. Without Bz2
# netCDF sets HAVE_BZ2 for its bundled copy, used by the plugins only.
# -DLIBXML_STATIC: as MXE; libncxml (DAP4) includes libxml2's headers,
# which dllimport every symbol without it. CMakeLists.txt itself adds
# -DCURL_STATICLIB.
# -Wno-error=incompatible-pointer-types: MXE passes
# -Wno-incompatible-pointer-types (GCC 14 made it an error; so has zig's
# clang), for two calls that stop the build: libhdf4/hdf4file.c passes an
# int * as HDF4's int32 * (long *; both 32 bits on Windows), and
# libdispatch/dpathmgr.c's NCstat passes its struct stat * to
# _wstat64/_stat64 (struct _stat64 *). With CMakeLists.txt's
# -D_FILE_OFFSET_BITS=64 (MinGW) and 64-bit time_t, MinGW-w64's struct
# stat has _stat64's members and layout, so the call is right; the check
# below holds that with the build's flags. Kept a warning, not silenced,
# so a new instance shows in the log.
cat > _stat_check.c <<'C'
#include <stddef.h>
#include <sys/stat.h>
#define SAME(m) _Static_assert(offsetof(struct stat, m) == offsetof(struct _stat64, m) && \
    sizeof(((struct stat *)0)->m) == sizeof(((struct _stat64 *)0)->m), #m)
SAME(st_dev); SAME(st_ino); SAME(st_mode); SAME(st_nlink); SAME(st_uid); SAME(st_gid);
SAME(st_rdev); SAME(st_size); SAME(st_atime); SAME(st_mtime); SAME(st_ctime);
_Static_assert(sizeof(struct stat) == sizeof(struct _stat64), "struct stat is struct _stat64");
C
"${CC}" ${CFLAGS} -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -std=c11 -c _stat_check.c -o _stat_check.o
# -DDLLEXPORT= (empty): include/ncjson.h defines DLLEXPORT as
# __declspec(dllexport) on _WIN32 unless it is already defined, so
# ncjson.c's NCJ* functions would carry -export: directives into
# libnetcdf.a, and a consumer DLL would re-export them (pkgtest
# --no-dllexport). Only the plugins' netcdf_filter_build.h uses the name
# otherwise, and no plugin is built.
CFLAGS="${CFLAGS} -DLIBXML_STATIC -DDLLEXPORT= -Wno-error=incompatible-pointer-types" cmake -S . -B _build ${CMAKE_ARGS} \
  -DBUILD_SHARED_LIBS=OFF \
  -DNC_FIND_SHARED_LIBS=OFF \
  -DENABLE_DLL=OFF \
  -DBUILD_UTILITIES=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_DOXYGEN=OFF \
  -DENABLE_NETCDF_4=ON \
  -DENABLE_HDF5=ON \
  -DHDF5_C_LIBRARY="$z/lib/libhdf5.a" \
  -DHDF5_HL_LIBRARY="$z/lib/libhdf5_hl.a" \
  -DHDF5_INCLUDE_DIR="$z/include" \
  -DENABLE_HDF4=ON \
  -DENABLE_HDF4_FILE_TESTS=OFF \
  -DENABLE_DAP=ON \
  -DENABLE_LIBXML2=ON \
  -DENABLE_NCZARR=ON \
  -DENABLE_NCZARR_ZIP=OFF \
  -DENABLE_BYTERANGE=OFF \
  -DENABLE_S3=OFF \
  -DENABLE_PLUGINS=OFF \
  -DPLUGIN_INSTALL_DIR=NO \
  -DENABLE_FILTER_TESTING=OFF \
  -DENABLE_PARALLEL4=OFF \
  -DENABLE_PNETCDF=OFF \
  -DCMAKE_DISABLE_FIND_PACKAGE_Zstd=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_Blosc=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_Bz2=ON | tee _configure.log

# A missing optional library turns its feature off quietly: fail instead.
meta=_build/include/netcdf_meta.h
for f in NC2 NC4 HDF4 HDF5 SZIP SZIP_WRITE DAP2 DAP4 NCZARR CDF5 DISKLESS; do
  grep -E "^#define NC_HAS_${f} +1( |$)" "$meta" >/dev/null \
    || { echo "zig-netcdf: NC_HAS_${f} is not 1 in netcdf_meta.h:" >&2; grep NC_HAS_ "$meta" >&2; exit 1; }
done
for f in BYTERANGE S3 PARALLEL PARALLEL4 PNETCDF ZSTD BLOSC; do
  grep -E "^#define NC_HAS_${f} +0( |$)" "$meta" >/dev/null \
    || { echo "zig-netcdf: NC_HAS_${f} is not 0 in netcdf_meta.h:" >&2; grep NC_HAS_ "$meta" >&2; exit 1; }
done

cmake --build _build
cmake --install _build

rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
# bin/nc-config: a shell script for the build machine with the build's
# absolute paths; consumers read netcdf.pc. lib/cmake/netCDF goes:
# netCDFTargets.cmake links the build env's absolute archive paths (MXE
# seds them out) and finds no HDF5 CMake config in zig-hdf5.
rm -rf "$z/bin" "$z/share" "$z/lib/cmake/netCDF"
rmdir "$z/lib/cmake" 2>/dev/null || true
# libnetcdf.settings: the configure summary, with the build's absolute
# paths.
rm -f "$z/lib/libnetcdf.settings"

# netcdf.pc: upstream's has the build's absolute prefix and the
# dependencies as bare -l words in Libs.private (-lmfhdf -ldf -lhdf5_hl
# -lhdf5 -lz -lcurl -lxml2: no libjpeg, szip, libcurl's or libxml2's own
# dependencies, no defines); MXE patches in Requires.private for df, mfhdf,
# hdf5, hdf5_hl, libcurl and appends Requires: libxml-2.0. Written here
# instead, then closed: every library libnetcdf.a calls goes through
# Requires, whose .pc files bring their own dependencies (df: libjpeg)
# and their static defines (libcurl.pc -DCURL_STATICLIB, libxml-2.0.pc
# -DLIBXML_STATIC). netcdf.h itself needs no define: it dllimports only
# under DLL_NETCDF, which a static build never sets. No Windows library in
# Libs: libnetcdf.a's other imports are the CRT's and kernel32's
# (FindFirstFileA, MultiByteToWideChar, GetSystemInfo, ...), which every
# link has.
pc="$z/lib/pkgconfig"
cat > "${pc}/netcdf.pc" <<PC
prefix=/zig-libs/${ZIG_TOOLCHAIN_TARGET}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: netCDF
Description: NetCDF Client Library for C
URL: https://www.unidata.ucar.edu/netcdf
Version: ${PKG_VERSION}
Requires: hdf5_hl hdf5 mfhdf libcurl libxml-2.0 zlib szip
Libs: -L\${libdir} -lnetcdf
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${pc}/netcdf.pc"
install -Dm644 COPYRIGHT "$z/licenses/netcdf/COPYRIGHT"
