#!/usr/bin/env bash
# zlib's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-zlib: ZIG_BIN='${zig_bin}' zig version: $v"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-zlib: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

cmake -S . -B _build ${CMAKE_ARGS} \
  -DZLIB_BUILD_EXAMPLES=OFF \
  -DINSTALL_PKGCONFIG_DIR="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
cmake --build _build
cmake --install _build

# lib<n>.a only: zlib's CMake names the archive libzlibstatic.a (its .pc
# says -lz) and always builds the DLL too.
mv "${ZIG_LIBS_PREFIX}/lib/libzlibstatic.a" "${ZIG_LIBS_PREFIX}/lib/libz.a"
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin" "${ZIG_LIBS_PREFIX}/share/man"
rmdir "${ZIG_LIBS_PREFIX}/share" 2>/dev/null || true

zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/zlib.pc"
install -Dm644 LICENSE "${ZIG_LIBS_PREFIX}/licenses/zlib/LICENSE"
