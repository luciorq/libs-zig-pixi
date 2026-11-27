#!/usr/bin/env bash
# GNU libunistring's own autotools configure + make (D1), static only (D3),
# into the sub-prefix (D2), through `zig-toolchain configure` (slice2
# D104), on zig-libiconv from the host env (slice3 D130). Only the library
# and its headers (lib/): not the docs (doc/) or the tests.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libunistring: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libunistring: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

z="${ZIG_LIBS_PREFIX}"
# iconv: configure's AM_ICONV links -liconv itself (no pkg-config lookup),
# so the sub-prefix goes in CPPFLAGS/LDFLAGS as plain flags
# (--with-libiconv-prefix=<dir> would put the absolute build path into
# LTLIBICONV). Without it the uniconv functions fall back to no
# conversion at all, so the check below fails the build instead.
# --enable-threads=windows: Windows threads for the locale caches, as a
# MinGW build picks by default; said explicitly.
# -Dlocale_charset=libunistring_locale_charset: libunistring and GNU
# libiconv (zig-libiconv's libiconv.a, localcharset.o) each compile
# gnulib's localcharset.c and define the global locale_charset, so every
# closure with both (libunistring.pc requires iconv) has the symbol twice
# (pkgtest --unique-c-symbols, DESIGN 6.5; slice3 notes). libunistring
# keeps its own, newer copy (it also maps a "<lang>.UTF-8" locale name to
# UTF-8) under another name: renamed, the function is no longer one of the
# library's public names, and lib/Makefile's config.h step then prefixes
# it as it does every gnulib internal (libunistring_libunistring_...).
# locale_charset, declared in the installed unistring/localcharset.h,
# resolves to libiconv's for a caller.
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure \
  --enable-threads=windows \
  CPPFLAGS="-I${z}/include -Dlocale_charset=libunistring_locale_charset" LDFLAGS="-L${z}/lib"
grep -E '^#define HAVE_ICONV 1$' config.h >/dev/null \
  || { echo "zig-libunistring: iconv not found (see config.log)" >&2; exit 1; }
grep -E '^LTLIBICONV = -liconv *$' lib/Makefile >/dev/null \
  || { echo "zig-libunistring: unexpected LTLIBICONV:" >&2; grep -E '^LTLIBICONV' lib/Makefile >&2; exit 1; }
# WOE32_LIBADD= (here and at install, which would build it again): no
# libunistring.res.lo. It is the DLL's VERSIONINFO resource, never linked
# from a static library, and zig rc (the toolchain's windres) fails on it as
# on libiconv's (zig-libiconv build.sh: windres-options --escape quotes the
# version for GNU windres' shell; "expected '<'}' or END>', got '\'").
make -j"${CPU_COUNT:-2}" -C lib WOE32_LIBADD=
make -C lib install WOE32_LIBADD= DESTDIR="${PREFIX}/Library"
cd ..
# with --disable-shared configure sets DLL_VARIABLE empty, so the installed
# headers declare the exported variables (uninorm_nfc, ...) without
# __declspec(dllimport)
! grep -q dllimport "$z/include/unistring/woe32dll.h" \
  || { echo "zig-libunistring: woe32dll.h declares dllimport variables:" >&2; cat "$z/include/unistring/woe32dll.h" >&2; exit 1; }

# the rename above: libunistring.a defines its copy under a prefixed name
# and no locale_charset
lc=$(llvm-nm -g --defined-only "$z/lib/libunistring.a" | awk '$NF ~ /locale_charset$/ {print $NF}' | sort -u | tr '\n' ' ')
[ "$lc" = "libunistring_libunistring_locale_charset " ] \
  || { echo "zig-libunistring: locale_charset not renamed: '${lc}'" >&2; exit 1; }

# lib<n>.a only: no libtool archive
rm -f "$z"/lib/*.la
[ ! -e "$z/bin" ] && [ ! -e "$z/share" ] \
  || { echo "zig-libunistring: unexpected bin/ or share/ in the sub-prefix" >&2; exit 1; }

# Upstream installs no .pc. libunistring.pc / -lunistring is the name
# MSYS2 ships (and libidn2's and libpsl's configure link -lunistring
# themselves); Requires iconv: the static archive calls libiconv
# (uniconv/, LTLIBICONV above), and iconv.pc (zig-libiconv) adds -liconv.
pc="$z/lib/pkgconfig"
mkdir -p "${pc}"
cat > "${pc}/libunistring.pc" <<PC
prefix=/zig-libs/$(basename "$z")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libunistring
Description: GNU libunistring, Unicode string library
URL: https://www.gnu.org/software/libunistring/
Version: ${PKG_VERSION}
Requires: iconv
Libs: -L\${libdir} -lunistring
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${pc}/libunistring.pc"
# dual-licensed "LGPLv3+ or GPLv2+" (README): COPYING.LIB is the LGPL-3.0,
# which builds on the GPL-3.0 in COPYING
install -Dm644 COPYING "$z/licenses/libunistring/COPYING"
install -Dm644 COPYING.LIB "$z/licenses/libunistring/COPYING.LIB"
