#!/usr/bin/env bash
# GLPK's own autotools configure + make (D1), static only (D3), into the
# sub-prefix (D2), through `zig-toolchain configure` (slice2 D104), on
# zig-gmp from the host env.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-glpk: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-glpk: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# -D__WOE__: GLPK's own switch for its MS Windows code (env/stdc.c
# strerror_s/strtok_s/gmtime_s, env/time.c GetSystemTime, env/dlsup.c
# LoadLibrary, env/tls.c DllMain). Without it the autotools build takes
# the POSIX code: gmtime_r and strerror_r, which MinGW-w64 does not
# declare, and glp_time passes timeval's 32-bit tv_sec as a time_t*
# (slice2 S2-F12). CRAN's Rtools45 libglpk.a is the same Windows code
# (DllMain, GetSystemTime, MessageBoxA, strerror_s).
# --with-gmp: GLPK's exact arithmetic on GMP, as MXE/Rtools build it.
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure --with-gmp \
  CPPFLAGS="-D__WOE__ -I${ZIG_LIBS_PREFIX}/include" LDFLAGS="-L${ZIG_LIBS_PREFIX}/lib"
make -j"${CPU_COUNT:-2}"
make install DESTDIR="${PREFIX}/Library"
cd ..

# lib<n>.a only: no libtool archive, no glpsol program
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.la
rm -rf "${ZIG_LIBS_PREFIX}/bin"

# Upstream installs no .pc (conda-forge's win-64 glpk has none either,
# r-zig-pixi stress igraph fail-sysdep). Neutral prefix, then close-pc
# makes it relocatable (DESIGN 5.5). user32: MessageBoxA (env/tls.c).
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
mkdir -p "${pc}"
cat > "${pc}/glpk.pc" <<PC
prefix=/zig-libs/$(basename "${ZIG_LIBS_PREFIX}")
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: glpk
Description: GNU Linear Programming Kit
URL: https://www.gnu.org/software/glpk/
Version: ${PKG_VERSION}
Requires: gmp
Libs: -L\${libdir} -lglpk -luser32
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${pc}/glpk.pc"
# GLPK (GPL-3.0-or-later) and the notices of the code it bundles (DESIGN
# 5.8): AMD and COLAMD (LGPL-2.1-or-later), MiniSat (MIT), zlib
lic="${ZIG_LIBS_PREFIX}/licenses/glpk"
install -Dm644 COPYING "${lic}/COPYING"
for d in amd colamd minisat zlib; do
  install -Dm644 "src/${d}/README" "${lic}/${d}-README"
done
install -Dm644 src/minisat/LICENSE "${lic}/minisat-LICENSE"
