#!/usr/bin/env bash
# GSL's own autotools configure + make (D1), static only (D3), into the
# sub-prefix (D2), through `zig-toolchain configure` (slice2 D104). As
# Rtools45 builds it (r-windows/rtools-packages mingw-w64-gsl: plain
# configure, GSL's own CBLAS; slice2 S2-F21).
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-gsl: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-gsl: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure
make -j"${CPU_COUNT:-2}"
make install DESTDIR="${PREFIX}/Library"
cd ..

# lib<n>.a only: no libtool archive; no programs (gsl-histogram,
# gsl-randist) and no gsl-config (a script with the prefix compiled in;
# gsl.pc carries the same flags); no man, info pages or aclocal macro.
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.la
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share"

# upstream's gsl.pc: -lgsl -lgslcblas and -lm (zig's MinGW libc carries
# the math functions; -lm resolves to it). Closed and relocatable
# (DESIGN 5.5).
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/gsl.pc"
install -Dm644 COPYING "${ZIG_LIBS_PREFIX}/licenses/gsl/COPYING"
