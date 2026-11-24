#!/usr/bin/env bash
# libxml2's own autotools configure + make (D1), static only (D3), into the
# sub-prefix (D2), through `zig-toolchain configure` (slice2 D104), on
# zig-zlib, zig-xz and zig-libiconv from the host env (slice2 D125 B).
# Only the library, its headers and libxml-2.0.pc: not xmllint,
# xmlcatalog, xml2-config, the CMake config, libxml.m4 or the docs.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libxml2: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libxml2: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

z="${ZIG_LIBS_PREFIX}"
# zlib and lzma: configure asks pkg-config (the build env's pkgconf,
# PKG_CONFIG_LIBDIR the sub-prefix) and so writes `Requires: zlib liblzma`
# into libxml-2.0.pc. iconv: configure has no pkg-config lookup and links
# -liconv itself, so the sub-prefix goes in CPPFLAGS/LDFLAGS (as plain
# flags; --with-iconv=<dir> would write the absolute build path into the
# .pc). Each missing library silently turns its option off, so the check
# below fails the build instead. --without-python: configure would find the
# build machine's python and build the bindings; --without-icu is the
# default, said explicitly (slice2 D125).
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure \
  --with-zlib --with-lzma --with-iconv --without-icu --without-python \
  CPPFLAGS="-I${z}/include" LDFLAGS="-L${z}/lib"
for opt in ZLIB LZMA ICONV; do
  grep -E "^WITH_${opt} = 1$" Makefile >/dev/null \
    || { echo "zig-libxml2: ${opt} support not enabled (see config.log)" >&2; exit 1; }
done
make -j"${CPU_COUNT:-2}" libxml2.la
# automake's per-part install targets: the archive, the headers (include/,
# xmlversion.h among them) and libxml-2.0.pc; `make install` would build
# xmllint and xmlcatalog and install xml2-config, the CMake config,
# libxml.m4, the docs and the example sources.
make install-libLTLIBRARIES install-pkgconfigDATA DESTDIR="${PREFIX}/Library"
make -C include install DESTDIR="${PREFIX}/Library"
cd ..

# lib<n>.a only: no libtool archive
rm -f "$z"/lib/*.la

# libxml-2.0.pc: a static-only configure already folds the private fields
# into Requires (zlib liblzma) and Libs (-liconv, -lws2_32 for nanohttp
# and nanoftp), and puts -DLIBXML_STATIC in Cflags (xmlexports.h
# dllimports every symbol without it). iconv goes into Requires too:
# libxml/encoding.h includes <iconv.h>, which sits in include/, not in
# include/libxml2/ (Cflags' only -I); iconv.pc's Cflags brings it.
pcf="$z/lib/pkgconfig/libxml-2.0.pc"
grep -E '^Requires: +zlib liblzma *$' "$pcf" >/dev/null \
  || { echo "zig-libxml2: unexpected Requires in libxml-2.0.pc:" >&2; cat "$pcf" >&2; exit 1; }
sed -i -E 's/^Requires: +zlib liblzma *$/Requires: zlib liblzma iconv/' "$pcf"
zig-toolchain close-pc "$pcf"
install -Dm644 Copyright "$z/licenses/libxml2/Copyright"
