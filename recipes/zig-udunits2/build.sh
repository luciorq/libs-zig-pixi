#!/usr/bin/env bash
# UDUNITS-2's own autotools configure + make (D1), static only (D3), into
# the sub-prefix (D2), through `zig-toolchain configure` (slice2 D104), on
# zig-expat from the host env. As Rtools45 builds it
# (r-windows/rtools-packages mingw-w64-udunits: plain configure).
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-udunits2: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-udunits2: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# zig-expat's headers and archive; -DXML_STATIC as its expat.pc says.
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure \
  CPPFLAGS="-I${ZIG_LIBS_PREFIX}/include -DXML_STATIC" LDFLAGS="-L${ZIG_LIBS_PREFIX}/lib"
make -j"${CPU_COUNT:-2}"
make install DESTDIR="${PREFIX}/Library"
cd ..

# lib<n>.a only: no libtool archive, no udunits2 program, no docs or info
# pages. share/udunits (the XML database) stays: the library's Windows
# default is the relative share\udunits\udunits2.xml (no prefix compiled
# in, slice2 S2-F20); R's units ships and passes its own copy.
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.la
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share/doc" "${ZIG_LIBS_PREFIX}/share/info"

# Upstream installs no .pc (neither does Rtools45); written here, closed
# and relocatable through close-pc (DESIGN 5.5). expat through Requires.
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
mkdir -p "${pc}"
cat > "${pc}/udunits2.pc" <<PC
prefix=/zig-libs/$(basename "${ZIG_LIBS_PREFIX}")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: udunits2
Description: UDUNITS-2 units of physical quantities
URL: https://www.unidata.ucar.edu/software/udunits/
Version: ${PKG_VERSION}
Requires: expat
Libs: -L\${libdir} -ludunits2
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${pc}/udunits2.pc"
install -Dm644 COPYRIGHT "${ZIG_LIBS_PREFIX}/licenses/udunits2/COPYRIGHT"
