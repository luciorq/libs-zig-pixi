#!/usr/bin/env bash
# oneTBB's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-onetbb: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-onetbb: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# tbb only: terra needs -ltbb12; tbbmalloc(_proxy) would only replace the
# allocator, which a static library cannot do for R anyway.
# TBB_ENABLE_IPO=OFF as the toolchain's CMAKE_INTERPROCEDURAL_OPTIMIZATION
# (oneTBB has its own switch, default ON, though it only acts on shared
# builds). The hwloc search is off already when cross-compiling.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DTBB_TEST=OFF \
  -DTBB_STRICT=OFF \
  -DTBB_EXAMPLES=OFF \
  -DTBBMALLOC_BUILD=OFF \
  -DTBBMALLOC_PROXY_BUILD=OFF \
  -DTBB_ENABLE_IPO=OFF \
  -DTBB_DISABLE_HWLOC_AUTOMATIC_SEARCH=ON \
  -DTBB_FILE_TRIM=ON
cmake --build _build
cmake --install _build

# lib<n>.a only. On Windows oneTBB already names the archive tbb12
# (OUTPUT_NAME tbb${TBB_BINARY_VERSION}); fail loudly if that ever changes.
test -f "${ZIG_LIBS_PREFIX}/lib/libtbb12.a"
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share/doc"
rmdir "${ZIG_LIBS_PREFIX}/share" 2>/dev/null || true

# tbb.pc: Libs -ltbb12 plus the Windows system libraries static libtbb12.a
# needs beyond zig's MinGW defaults (none found: see the recipe's smoke).
# (close-pc keeps tbb.pc's licence header comment as it is.)
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/tbb.pc"
install -Dm644 LICENSE.txt "${ZIG_LIBS_PREFIX}/licenses/onetbb/LICENSE.txt"
install -Dm644 third-party-programs.txt "${ZIG_LIBS_PREFIX}/licenses/onetbb/third-party-programs.txt"
