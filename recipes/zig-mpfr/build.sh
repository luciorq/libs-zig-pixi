#!/usr/bin/env bash
# MPFR's own autotools configure + make (D1), static only (D3), into the
# sub-prefix (D2), through `zig-toolchain configure` (slice2 D104), on
# zig-gmp from the host env.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-mpfr: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-mpfr: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# --with-gmp: zig-gmp's headers and archive (the path is used for -I/-L
# only; mpfr.pc names gmp through Requires below).
# --enable-thread-safe: configure cannot run its TLS test when cross
# compiling and would assume no; with the option it assumes yes and uses
# __thread (MPFR's acinclude.m4), as a native build detects. The smoke
# test checks mpfr_buildopt_tls_p() where it runs (slice2 S2-F11).
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure \
  --with-gmp="${ZIG_LIBS_PREFIX}" --enable-thread-safe
grep -q 'MPFR_USE_THREAD_SAFE=1' Makefile
make -j"${CPU_COUNT:-2}"
make install DESTDIR="${PREFIX}/Library"
cd ..

# lib<n>.a only: no libtool archive, no docs or info pages
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.la
rm -rf "${ZIG_LIBS_PREFIX}/share/doc/mpfr" "${ZIG_LIBS_PREFIX}/share/info"
rmdir "${ZIG_LIBS_PREFIX}/share/doc" "${ZIG_LIBS_PREFIX}/share" 2>/dev/null || true

# Libs names -lgmp next to -lmpfr: zig-gmp's module gmp replaces it,
# through Requires (as zig-openssl does for zlib); closed and relocatable
# (DESIGN 5.5).
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig/mpfr.pc"
sed -i -e '/^Libs:/s| -lgmp\b||' -e '/^Libs:/a Requires: gmp' "${pc}"
zig-toolchain close-pc "${pc}"
for f in COPYING COPYING.LESSER; do
  install -Dm644 "$f" "${ZIG_LIBS_PREFIX}/licenses/mpfr/$f"
done
