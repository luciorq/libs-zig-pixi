#!/usr/bin/env bash
# NLopt's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-nlopt: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-nlopt: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# NLOPT_CXX=ON: the C++ algorithms (StoGO, AGS), as Rtools45 builds it
# (r-windows/rtools-packages mingw-w64-nlopt); no language bindings, no
# tests.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DNLOPT_CXX=ON \
  -DNLOPT_PYTHON=OFF \
  -DNLOPT_OCTAVE=OFF \
  -DNLOPT_MATLAB=OFF \
  -DNLOPT_GUILE=OFF \
  -DNLOPT_JAVA=OFF \
  -DNLOPT_SWIG=OFF \
  -DNLOPT_TESTS=OFF
cmake --build _build
cmake --install _build
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib

# NLoptConfig.cmake sets NLOPT_INCLUDE_DIRS and NLOPT_LIBRARY_DIRS to the
# absolute install prefix (the host env path, which conda rewrites at
# install, DESIGN R1); the imported target (NLoptLibraryDepends.cmake) is
# already relative. Same as that file: the prefix is three directories up
# from lib/cmake/nlopt. Nothing under lib/cmake may name the prefix after.
cm="${ZIG_LIBS_PREFIX}/lib/cmake/nlopt"
sed -i "s|${ZIG_LIBS_PREFIX}|\${CMAKE_CURRENT_LIST_DIR}/../../..|g" "${cm}/NLoptConfig.cmake"
if grep -rn -F "${PREFIX}" "${cm}"; then echo "zig-nlopt: absolute prefix left in ${cm}" >&2; exit 1; fi

# nlopt.pc: Libs -lnlopt, Libs.private -lm, but libnlopt.a holds C++
# (StoGO, AGS: 70 std::__1 references, slice2 S2-F19), so a C consumer
# links libc++ too: -lc++ (DESIGN 5.5).
zig-toolchain close-pc --libs "-lc++" "${ZIG_LIBS_PREFIX}/lib/pkgconfig/nlopt.pc"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/nlopt/COPYING"
install -Dm644 COPYRIGHT "${ZIG_LIBS_PREFIX}/licenses/nlopt/COPYRIGHT"
