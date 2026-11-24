#!/usr/bin/env bash
# GNU libiconv's own autotools configure + make (D1), static only (D3),
# into the sub-prefix (D2), through `zig-toolchain configure` (slice2
# D104). Only libiconv, libcharset and their headers: not the iconv
# program (src/, srclib/), its translations (po/) or man pages.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libiconv: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libiconv: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# --disable-nls: no libintl in the sub-prefix, and only the iconv program
# has translations. With --disable-shared configure sets DLL_VARIABLE
# empty, so the installed iconv.h declares _libiconv_version without
# __declspec(dllimport).
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure --disable-nls
# The top-level `all` also builds srclib/ and src/ (the iconv program), po/
# and man/; lib/localcharset.h is the target that builds libcharset first
# (lib/ includes its header).
make -j"${CPU_COUNT:-2}" lib/localcharset.h
# OBJECTS_RES_yes= (here and at install, whose `all` would build it
# again): no libiconv.res.o. It is iconv.dll's VERSIONINFO
# resource, and an archive member without symbols is never linked from a
# static library. Building it also fails: windres-options --escape
# backslash-escapes the quotes in -DPACKAGE_VERSION_STRING=\"1.17\" for
# GNU windres, which hands -D to its preprocessor through a shell; zig rc
# (the toolchain's windres) takes the argument as is and sees \"1.17\"
# ("expected '<'}' or END>', got '\'", libiconv.rc:25).
make -j"${CPU_COUNT:-2}" -C lib OBJECTS_RES_yes=
# the libraries' own install targets, then iconv.h as the top-level
# `install` copies it (include/iconv.h.inst: the installed variant)
make -C libcharset install DESTDIR="${PREFIX}/Library"
make -C lib install OBJECTS_RES_yes= DESTDIR="${PREFIX}/Library"
install -Dm644 include/iconv.h.inst "${ZIG_LIBS_PREFIX}/include/iconv.h"
cd ..

z="${ZIG_LIBS_PREFIX}"
# lib<n>.a only: no libtool archive
rm -f "$z"/lib/*.la
[ ! -e "$z/bin" ] && [ ! -e "$z/share" ] \
  || { echo "zig-libiconv: unexpected bin/ or share/ in the sub-prefix" >&2; exit 1; }

# Upstream installs no .pc. iconv.pc / -liconv is the name Rtools45's tree
# (MXE) and MSYS2 ship; libxml2 2.12's configure links -liconv itself
# (no pkg-config lookup) and writes it into libxml-2.0.pc's Libs.
# libcharset gets no .pc of its own (Rtools45 ships none): libiconv.a
# carries its own copy of locale_charset (lib/localcharset.c is compiled
# into it), so -liconv alone links.
pc="$z/lib/pkgconfig"
mkdir -p "${pc}"
cat > "${pc}/iconv.pc" <<PC
prefix=/zig-libs/$(basename "$z")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: iconv
Description: GNU libiconv, character set conversion library
URL: https://www.gnu.org/software/libiconv/
Version: ${PKG_VERSION}
Libs: -L\${libdir} -liconv
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${pc}/iconv.pc"
# the libraries are LGPL-2.1-or-later (COPYING.LIB); COPYING (GPL-3.0)
# covers the iconv program, not in this package
install -Dm644 COPYING.LIB "$z/licenses/libiconv/COPYING.LIB"
