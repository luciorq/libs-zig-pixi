#!/usr/bin/env bash
# OpenSSL's own Perl Configure + make (D1), static only (D3), into the
# sub-prefix (D2). zig-toolchain's activation script set ZIG_LIBS_PREFIX,
# CC, AR, RANLIB, RC, CFLAGS for the target.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-openssl: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-openssl: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

case "${target_platform}" in
  win-64) target=mingw64 ;;
  win-arm64) target=mingwarm64 ;;
  *) echo "zig-openssl: target_platform ${target_platform} not supported" >&2; exit 1 ;;
esac
# ZIG_LIBS_PREFIX = $PREFIX/Library/zig-libs/<zig triple>
triple=$(basename "${ZIG_LIBS_PREFIX}")

# Configure bakes the prefix into libcrypto (OPENSSLDIR, ENGINESDIR,
# MODULESDIR) and its CFLAGS into the version text (crypto/buildinf.h).
# The host prefix is a build path (bld/rattler-build_*, the archives are
# not prefix-replaced), so OpenSSL is configured for the neutral prefix
# /zig-libs/<triple> and installed with DESTDIR=$PREFIX/Library, which puts
# it at $ZIG_LIBS_PREFIX. -DOSSL_WINCTX makes libcrypto take those three
# directories from the registry key
# HKLM\SOFTWARE\WOW6432Node\OpenSSL-3.6-zig_libs, and when that key is
# absent (the normal case) load no default openssl.cnf and no module from
# a compiled-in path (NOTES-WINDOWS.md): a drive-relative compiled-in
# directory would be writable by any user (CVE-2019-1552).
vprefix="/zig-libs/${triple}"
# -ffile-prefix-map=$SRC_DIR=. (activation) would put the build path into
# the version text; OpenSSL compiles in-tree with relative source paths and
# -g0, so it is not needed here.
cflags="-O3"
for f in ${CFLAGS}; do
  case "$f" in -ffile-prefix-map=*) ;; *) cflags="${cflags} $f" ;; esac
done
# zig-zlib through a relative link: the -I of --with-zlib-include goes into
# the version text too (make runs every compile from the source root).
ln -sfn "${ZIG_LIBS_PREFIX}" _zig-libs

# CROSS_COMPILE empty: CC/AR/RANLIB/RC are already the triple's wrappers.
CROSS_COMPILE= perl ./Configure "${target}" \
  no-shared no-module no-capieng no-tests no-docs zlib \
  --with-zlib-include=_zig-libs/include --with-zlib-lib=_zig-libs/lib \
  "--prefix=${vprefix}" --libdir=lib "--openssldir=${vprefix}/ssl" \
  "CC=${CC}" "AR=${AR}" "RANLIB=${RANLIB}" "RC=${RC}" \
  "CFLAGS=${cflags}" CXXFLAGS= CPPFLAGS=-DOSSL_WINCTX=zig_libs LDFLAGS=
perl configdata.pm --command-line
make -j"${CPU_COUNT:-2}"
make install_sw DESTDIR="${PREFIX}/Library"

# lib<n>.a only, no programs (openssl.exe, c_rehash), no engines/modules.
# No lib/cmake/OpenSSL either: its static dependency list (-lz -lws2_32
# -lgdi32 -lcrypt32) is not closed and names zlib by -l only; the .pc files
# are the interface (DESIGN 5.5) and CMake's FindOpenSSL uses them.
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/lib/engines-3" \
  "${ZIG_LIBS_PREFIX}/lib/ossl-modules" "${ZIG_LIBS_PREFIX}/lib/cmake/OpenSSL"
rmdir "${ZIG_LIBS_PREFIX}/lib/cmake" 2>/dev/null || true
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib

# Libs.private of libcrypto.pc names zlib as -L_zig-libs/lib -lz: the
# zig-libs module zlib (zig-zlib) replaces both, through Requires.
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
sed -i -e "/^Libs.private:/{s| -L_zig-libs/lib||;s| -lz\b||}" \
  -e '/^Libs.private:/a Requires.private: zlib' "${pc}/libcrypto.pc"
# closed (DESIGN 5.5): Libs.private (ws2_32 gdi32 crypt32 from the mingw
# target) into Libs, plus user32 (cryptlib.c: MessageBox, window station)
# and advapi32 (registry, event log, CryptoAPI).
zig-toolchain close-pc --libs "-luser32 -ladvapi32" "${pc}/libcrypto.pc"
zig-toolchain close-pc "${pc}/libssl.pc" "${pc}/openssl.pc"
install -Dm644 LICENSE.txt "${ZIG_LIBS_PREFIX}/licenses/openssl/LICENSE.txt"
