#!/usr/bin/env bash
# libssh2's own CMake build (D1), static only (D3), into the sub-prefix
# (D2), on zig-openssl's libcrypto (slice3 D130: OpenSSL, as Linux, macOS
# and conda-forge build it; Rtools45's MXE build uses libgcrypt) and
# zig-zlib (compression) from the host env. zig-toolchain's activation
# script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libssh2: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libssh2: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# CRYPTO_BACKEND=OpenSSL makes a missing OpenSSL a configure error instead
# of a quiet fall back to WinCNG. OpenSSL and zlib are found with
# find_path/find_library in the sub-prefix (the toolchain file's
# CMAKE_FIND_ROOT_PATH). No examples, tests or man pages.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DBUILD_STATIC_LIBS=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF \
  -DCRYPTO_BACKEND=OpenSSL \
  -DENABLE_ZLIB_COMPRESSION=ON
cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
# share/ holds the docs (COPYING, NEWS, README, RELEASE-NOTES) and man
# pages; lib/cmake/libssh2 goes: consumers (libcurl's CMake included) read
# libssh2.pc, and libssh2-targets.cmake names the build's absolute paths
# of libcrypto.a and libz.a.
rm -rf "$z/bin" "$z/share" "$z/lib/cmake/libssh2"
rmdir "$z/lib/cmake" 2>/dev/null || true

# libssh2.pc: a static-only build already folds the private fields into
# the public ones (Requires: libcrypto,zlib; Libs: -lssh2 -lws2_32
# -lcrypto -lcrypt32 -lbcrypt -lz) and keeps the same words in the
# .private fields too, which close-pc would append a second time, so those
# lines go first; the check below makes sure the public fields have what a
# static link needs.
pcf="$z/lib/pkgconfig/libssh2.pc"
sed -i -E '/^(Requires|Libs|Cflags)\.private:/d' "$pcf"
for w in -lssh2 -lws2_32 -lcrypto -lcrypt32 -lbcrypt -lz; do
  grep -E "^Libs:.* ${w}( |$)" "$pcf" >/dev/null \
    || { echo "zig-libssh2: '${w}' missing from libssh2.pc:" >&2; cat "$pcf" >&2; exit 1; }
done
grep -E '^Requires: +libcrypto,zlib *$' "$pcf" >/dev/null \
  || { echo "zig-libssh2: unexpected Requires in libssh2.pc:" >&2; cat "$pcf" >&2; exit 1; }
zig-toolchain close-pc "$pcf"
install -Dm644 COPYING "$z/licenses/libssh2/COPYING"
