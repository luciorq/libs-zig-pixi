#!/usr/bin/env bash
# IJG's own autotools configure + make (D1), static only (D3), into the
# sub-prefix (D2), through `zig-toolchain configure` (slice2 D104). Only
# the library, its headers and libjpeg.pc: not the cjpeg, djpeg, jpegtran,
# rdjpgcom and wrjpgcom programs or their man pages.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libjpeg: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libjpeg: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# configure's three run tests (char signed, right shift signed, fopen "b")
# cannot run when cross compiling and take their defaults, which are the
# Windows answers on both arches (char is signed, arithmetic right shift).
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure
make -j"${CPU_COUNT:-2}" libjpeg.la
# automake's per-part install targets: the archive, the headers, jconfig.h
# (install-data-local) and libjpeg.pc; `make install` would build the
# programs first.
make install-libLTLIBRARIES install-includeHEADERS install-data-local \
  install-nodist_pkgconfigDATA DESTDIR="${PREFIX}/Library"
cd ..

# lib<n>.a only: no libtool archive
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.la

# upstream's libjpeg.pc (Version 9.6.0, -ljpeg); closed and relocatable
# (DESIGN 5.5).
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/libjpeg.pc"
# the IJG licence is README's LEGAL ISSUES section
install -Dm644 README "${ZIG_LIBS_PREFIX}/licenses/libjpeg/README"
