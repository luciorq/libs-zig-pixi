#!/usr/bin/env bash
# bzip2's own Makefile, library target only (D1), static only (D3), into
# the sub-prefix (D2). zig-toolchain's activation script set
# ZIG_LIBS_PREFIX, CC, AR, RANLIB, CFLAGS, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-bzip2: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-bzip2: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# The Makefile's own CFLAGS without -g (the activation's -g0 and
# -ffile-prefix-map follow). Only the libbz2.a target:
# `all` also builds the bzip2 programs and runs them (`test`), and
# `install` copies programs, scripts and man pages; libbz2.a and bzlib.h
# are installed by hand below.
# The Makefile compiles with a bare `$(CC) $(CFLAGS) -c x.c` and archives
# x.o: zig-toolchain's cc names that output x.o, as gcc does (zig alone
# says x.obj; slice2 PLAN.md S2-F29).
make -j"${CPU_COUNT:-2}" libbz2.a CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
  CFLAGS="-Wall -Winline -O2 -D_FILE_OFFSET_BITS=64 ${CFLAGS}"
install -Dm644 libbz2.a "${ZIG_LIBS_PREFIX}/lib/libbz2.a"
install -Dm644 bzlib.h "${ZIG_LIBS_PREFIX}/include/bzlib.h"

# Upstream installs no .pc (1.0.8 predates bzip2.pc); bzip2.pc / -lbz2 is
# the name conda-forge and MXE use. Neutral prefix, then close-pc makes it
# relocatable (DESIGN 5.5). bzlib.h has no dllimport for _WIN32 (only
# WINAPI, which is nothing on x86_64 and aarch64), so no static define.
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
mkdir -p "${pc}"
cat > "${pc}/bzip2.pc" <<PC
prefix=/zig-libs/$(basename "${ZIG_LIBS_PREFIX}")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: bzip2
Description: Lossless, block-sorting data compression library
URL: https://sourceware.org/bzip2/
Version: ${PKG_VERSION}
Libs: -L\${libdir} -lbz2
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${pc}/bzip2.pc"
install -Dm644 LICENSE "${ZIG_LIBS_PREFIX}/licenses/bzip2/LICENSE"
