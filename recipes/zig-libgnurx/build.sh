#!/usr/bin/env bash
# libgnurx (the MinGW project's port of glibc's POSIX regex) compiled
# directly (DESIGN 6.1), as MXE's libgnurx.mk builds it for Rtools45: one
# object, regex.o (regex.c includes regcomp.c, regexec.c and
# regex_internal.c), with -std=gnu99, archived as libgnurx.a and installed
# as libregex.a too; regex.h as shipped. Static only (D3), into the
# sub-prefix (D2). zig-toolchain's activation script set CC, AR, RANLIB,
# CFLAGS, ZIG_LIBS_PREFIX.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libgnurx: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libgnurx: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# The tarball's configure + Makefile only add a DLL and its import
# library (MXE replaces its rules with Makefile.mxe for a static build);
# the object is the same `$CC -std=gnu99 <CFLAGS> -I. -c regex.c` either
# way. -O2 as Rtools; CFLAGS: -g0, sections, -ffile-prefix-map
# (activation).
$CC -std=gnu99 -O2 ${CFLAGS} -I. -c regex.c -o regex.o
z="${ZIG_LIBS_PREFIX}"
mkdir -p "$z/lib/pkgconfig" "$z/include"
$AR rcs "$z/lib/libregex.a" regex.o
$RANLIB "$z/lib/libregex.a"
# Rtools45 (MXE's install-static) has lib/libgnurx.a and libregex.a as
# the same archive (a symlink in MXE, a hard link in the tarball); a
# second copy here, since a package's links are not kept on every
# filesystem it is installed to, and the archive is small.
cp -p "$z/lib/libregex.a" "$z/lib/libgnurx.a"
install -m644 regex.h "$z/include/"

# Upstream and Rtools45 ship no .pc; regex.pc (the -lregex name packages
# link, e.g. htslib's Makevars.win) so the package has one like every
# zig-* library. No system library beyond zig's defaults.
cat > "$z/lib/pkgconfig/regex.pc" <<PC
prefix=${z}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: regex
Description: libgnurx, POSIX regex functions from glibc for MinGW (static, zig-built)
URL: https://github.com/TimothyGu/libgnurx
Version: ${PKG_VERSION}
Libs: -L\${libdir} -lregex
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "$z/lib/pkgconfig/regex.pc"
cat "$z/lib/pkgconfig/regex.pc"
install -Dm644 COPYING.LIB "$z/licenses/libgnurx/COPYING.LIB"
