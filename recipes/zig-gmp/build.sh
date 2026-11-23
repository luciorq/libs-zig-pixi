#!/usr/bin/env bash
# GMP's own autotools configure + make (D1), static only (D3), into the
# sub-prefix (D2), through `zig-toolchain configure` (slice2 D104): it adds
# --build/--host, the neutral prefix /zig-libs/<zig triple> and
# --disable-shared --enable-static, and fences off the build machine's
# tools (CC_FOR_BUILD is zig cc for GMP's gen-* programs; NM is llvm-nm).
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-gmp: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-gmp: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# --disable-assembly: generic C mpn (D104: assembly is a fallback trigger,
# not a workaround). --enable-cxx: libgmpxx, as Rtools45 ships it.
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" CXXFLAGS="-O2 ${CXXFLAGS}" \
  zig-toolchain configure ../configure --disable-assembly --enable-cxx
make -j"${CPU_COUNT:-2}"
make install DESTDIR="${PREFIX}/Library"
cd ..

# lib<n>.a only: no libtool archives (they name the neutral prefix), no
# info pages
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.la
rm -rf "${ZIG_LIBS_PREFIX}/share/info"
rmdir "${ZIG_LIBS_PREFIX}/share" 2>/dev/null || true

# closed and relocatable (DESIGN 5.5); gmpxx is C++: one -lc++
pc="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
zig-toolchain close-pc "${pc}/gmp.pc"
zig-toolchain close-pc --libs "-lc++" "${pc}/gmpxx.pc"
for f in COPYING.LESSERv3 COPYINGv2 COPYINGv3; do
  install -Dm644 "$f" "${ZIG_LIBS_PREFIX}/licenses/gmp/$f"
done
