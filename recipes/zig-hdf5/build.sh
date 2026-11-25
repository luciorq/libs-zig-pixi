#!/usr/bin/env bash
# HDF5's own CMake build (D1), static only (D3), into the sub-prefix (D2):
# the C library and the high-level library (hdf5_hl), on zig-zlib (the
# deflate filter) and zig-libaec (the szip filter, encoder included; slice2
# D127 C) from the host env. No
# tools, utils, examples, tests, C++, Fortran or Java; thread-safety off,
# as in Rtools45's build (its H5lib_settings.c: "Threadsafety: OFF").
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
: "${ZIG_TOOLCHAIN_TARGET:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-hdf5: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-hdf5: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

z="${ZIG_LIBS_PREFIX}"
zt="${ZIG_TOOLCHAIN_TARGET}"

# H5Tinit.c: HDF5 1.12 builds H5detect and runs it at build time to write
# the native type layout (sizes, float formats, alignments) as C. A cross
# build on linux cannot run a Windows program, and a linux H5detect
# describes linux types (8-byte long, other long double), so the build uses
# H5detect's output from the target itself (HDF5_USE_PREGEN):
# pregen/<triple>/H5Tinit.c are byte for byte the H5Tinit.c.mingw64 and
# H5Tinit.c.aarch64 of Rtools45's MXE hdf5-2-platform-detection.patch
# (R-dev-web trunk WindowsBuilds/winutf8/ucrt3/toolchain_libs/mxe/src,
# r6263, Tomas Kalibera), H5detect of HDF5 1.12.1 run natively on Windows
# (x86_64: gcc 13.2.0, 2024-08-07; aarch64: LLVM 17.0.6, 2024-08-08, per
# the patch's H5lib_settings.c.*). The x86_64 file's data equals MXE's
# H5Tinit.c.mingw64 for 1.12.0 (mxe-octave, 2020); the two differ only
# in long double (x86_64: 80-bit x87 in 16 bytes; aarch64: IEEE double).
# The check after configure below holds every value of the file against
# zig's own target layout.
mkdir -p _pregen
cp "${RECIPE_DIR}/pregen/${zt}/H5Tinit.c" _pregen/H5Tinit.c

# The other build-time programs: H5make_libsettings is replaced for a cross
# build by a CMake script (the recipe's patch). HDF5_ENABLE_EMBEDDED_LIBINFO
# off: libhdf5.settings names the compiler wrapper and the CFLAGS with
# their build paths, which would end up in libhdf5.a (pkgtest, D22).
#
# TRY_RUN checks: in a cross build CMake cannot run them and needs each
# result as a cache value (<VAR>, and <VAR>__TRYRUN_OUTPUT where the
# output is read). The values are what each test program returns on
# Windows, from its source (config/cmake/ConversionTests.c,
# config/cmake_ext_mod/HDFTests.c), the same on both arches; MXE's and
# Rtools45's hdf5.mk set the same ConversionTests, LFS and IOEO values
# (for the last two items they differ, below):
#   *_LDOUBLE_TO_LONG_SPECIAL, *_LONG_TO_LDOUBLE_SPECIAL: 1 (no): IBM
#     Power6 only; both tests need an 8-byte long (Windows: 4).
#   *_LDOUBLE_TO_LLONG_ACCURATE, *_LLONG_TO_LDOUBLE_CORRECT: 0 (yes): the
#     tests fail only for a 16-byte big-endian double-double long double.
#   *_DISABLE_SOME_LDOUBLE_CONV: 1 (no): ppc64le only.
#   *_NO_ALIGNMENT_RESTRICTIONS: 0 (yes): x86_64 and Windows on ARM64
#     load and store unaligned (the native H5detect in H5Tinit.c finds
#     every ALIGN_g 1 on both).
#   TEST_LFS_WORKS_RUN: set, as MXE does, only so that CMake skips the
#     Linux large-file block, which cannot run its test (defined, the
#     block adds no -D_FILE_OFFSET_BITS=64). HDF5's Windows I/O is 64-bit
#     without it (H5win32defs.h: HDoff_t __int64, _lseeki64, _fstati64).
#   HAVE_IOEO: 0: InitOnceExecuteOnce (Vista and later).
#   H5_PRINTF_LL_WIDTH: "I64", the first width the HDFTests.c program
#     tries that prints a 64-bit integer right; UCRT and MinGW-w64's own
#     printf both take it (it fills PRIdHSIZE etc. in H5public.h).
#     Rtools45 passes the test's run with no output, which leaves the
#     width empty ("%d" for 64-bit values); MXE fails it ("unknown").
#   RUN_RESULT_VAR + pac_Cconftest.out: the C_RUN "maximum decimal
#     precision for C" program writes "<DECIMAL_DIG>;<FLT128_DIG>;" to
#     the build dir; DECIMAL_DIG is read from zig's float.h for the
#     target (x86_64 21, aarch64 17), FLT128_DIG is 0: zig ships no
#     quadmath.h (H5_HAVE_QUADMATH_H). Only the Fortran interface uses it
#     (Rtools45 patches in "21;33;", its gcc's, for both arches).
mkdir -p _build
dig=$(printf '#include <float.h>\nzig_hdf5_dig=DECIMAL_DIG\n' | "${CC}" -E -P -x c - \
  | sed -n 's/^zig_hdf5_dig=\([0-9]*\)$/\1/p')
case "$dig" in ''|*[!0-9]*) echo "zig-hdf5: DECIMAL_DIG for ${zt} is '${dig}'" >&2; exit 1 ;; esac
printf '%s;0;' "$dig" > _build/pac_Cconftest.out

cmake -S . -B _build ${CMAKE_ARGS} \
  -DONLY_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DHDF5_BUILD_TOOLS=OFF \
  -DHDF5_BUILD_UTILS=OFF \
  -DHDF5_BUILD_EXAMPLES=OFF \
  -DHDF5_BUILD_HL_LIB=ON \
  -DHDF5_BUILD_CPP_LIB=OFF \
  -DHDF5_BUILD_FORTRAN=OFF \
  -DHDF5_BUILD_JAVA=OFF \
  -DHDF5_BUILD_DOC=OFF \
  -DHDF5_ENABLE_THREADSAFE=OFF \
  -DHDF5_ENABLE_PARALLEL=OFF \
  -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
  -DHDF5_ENABLE_SZIP_SUPPORT=ON \
  -DHDF5_ENABLE_SZIP_ENCODING=ON \
  -DSZIP_LIBRARY="${ZIG_LIBS_PREFIX}/lib/libsz.a" \
  -DSZIP_INCLUDE_DIR="${ZIG_LIBS_PREFIX}/include" \
  -DHDF5_ALLOW_EXTERNAL_SUPPORT=NO \
  -DHDF5_ENABLE_EMBEDDED_LIBINFO=OFF \
  -DHDF5_USE_PREGEN=ON \
  -DHDF5_USE_PREGEN_DIR="${SRC_DIR}/_pregen" \
  -DH5_LDOUBLE_TO_LONG_SPECIAL_RUN=1 \
  -DH5_LDOUBLE_TO_LONG_SPECIAL_RUN__TRYRUN_OUTPUT= \
  -DH5_LONG_TO_LDOUBLE_SPECIAL_RUN=1 \
  -DH5_LONG_TO_LDOUBLE_SPECIAL_RUN__TRYRUN_OUTPUT= \
  -DH5_LDOUBLE_TO_LLONG_ACCURATE_RUN=0 \
  -DH5_LDOUBLE_TO_LLONG_ACCURATE_RUN__TRYRUN_OUTPUT= \
  -DH5_LLONG_TO_LDOUBLE_CORRECT_RUN=0 \
  -DH5_LLONG_TO_LDOUBLE_CORRECT_RUN__TRYRUN_OUTPUT= \
  -DH5_DISABLE_SOME_LDOUBLE_CONV_RUN=1 \
  -DH5_DISABLE_SOME_LDOUBLE_CONV_RUN__TRYRUN_OUTPUT= \
  -DH5_NO_ALIGNMENT_RESTRICTIONS_RUN=0 \
  -DH5_NO_ALIGNMENT_RESTRICTIONS_RUN__TRYRUN_OUTPUT= \
  -DTEST_LFS_WORKS_RUN=0 \
  -DHAVE_IOEO_EXITCODE=0 \
  -DH5_PRINTF_LL_WIDTH='"I64"' \
  -DRUN_RESULT_VAR=0 \
  -DRUN_RESULT_VAR__TRYRUN_OUTPUT= | tee _configure.log
grep -E '^#define H5_HAVE_FILTER_DEFLATE 1$' _build/src/H5pubconf.h >/dev/null \
  || { echo "zig-hdf5: deflate filter (zlib) not enabled (see _build/src/H5pubconf.h)" >&2; exit 1; }

# H5Tinit.c against zig's layout for the target: every size, precision,
# sign, float field, byte order and struct alignment (offsetof after a
# char, H5detect's COMP_ALIGNMENT) the file sets becomes a _Static_assert,
# compiled with the build's compiler and H5pubconf.h. ALIGN_g (unaligned
# access works) is a run-time fact; NO_ALIGNMENT_RESTRICTIONS above
# says the same.
awk -f "${RECIPE_DIR}/h5tinit-asserts.awk" _pregen/H5Tinit.c > _build/h5tinit_check.c
grep -c _Static_assert _build/h5tinit_check.c
"${CC}" ${CFLAGS} -std=c11 -Isrc -I_build/src -c _build/h5tinit_check.c -o _build/h5tinit_check.o

cmake --build _build
cmake --install _build

rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
rm -rf "$z/bin" "$z/share"
# lib/cmake goes: hdf5-targets.cmake gives hdf5-static the zlib archive's
# absolute build-env path (MXE seds it out); the .pc files below remain.
rm -rf "$z/cmake" "$z/lib/cmake"
# a missing szip turns the filter off quietly: fail instead (libsz.a is
# libaec's szip interface, zig-libaec's szip.pc)
grep -E '^#define H5_HAVE_FILTER_SZIP 1' "$z/include/H5pubconf.h" >/dev/null \
  || { echo "zig-hdf5: the szip filter is not enabled (H5pubconf.h)" >&2; exit 1; }
# libhdf5.settings is the configure summary with the build paths, not
# library data (the archive gets an empty one, above)
rm -f "$z/lib/libhdf5.settings"
# Upstream installs hdf5-1.12.1.pc and hdf5_hl-1.12.1.pc with -l<absolute
# path of libz.a> in Libs.private (MXE seds both); Rtools45 renames them
# hdf5.pc and hdf5_hl.pc. Written here instead, then closed: zlib and szip
# through Requires (zig-zlib's zlib.pc, zig-libaec's szip.pc: -lsz, as
# Rtools45's hdf5.pc). Windows libraries: libhdf5.a imports
# from kernel32 and, for GetUserNameA (H5system.c), advapi32; zig and
# MinGW gcc link both by default, -ladvapi32 says it anyway. Nothing from
# ws2_32/wsock32 (CMake's list in libhdf5.settings is for H5detect and
# the tests) nor shlwapi. No define in Cflags: H5api_adpt.h dllimports
# only under H5_BUILT_AS_DYNAMIC_LIB, which a static build never defines.
rm -f "$z"/lib/pkgconfig/hdf5*.pc
pc="$z/lib/pkgconfig"
cat > "${pc}/hdf5.pc" <<PC
prefix=/zig-libs/${zt}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: hdf5
Description: HDF5 (Hierarchical Data Format 5) Software Library
URL: https://www.hdfgroup.org/
Version: ${PKG_VERSION}
Requires: zlib szip
Libs: -L\${libdir} -lhdf5 -ladvapi32
Cflags: -I\${includedir}
PC
cat > "${pc}/hdf5_hl.pc" <<PC
prefix=/zig-libs/${zt}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: hdf5_hl
Description: HDF5 (Hierarchical Data Format 5) Software Library, high-level APIs
URL: https://www.hdfgroup.org/
Version: ${PKG_VERSION}
Requires: hdf5
Libs: -L\${libdir} -lhdf5_hl
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${pc}/hdf5.pc" "${pc}/hdf5_hl.pc"
install -Dm644 COPYING "$z/licenses/hdf5/COPYING"
