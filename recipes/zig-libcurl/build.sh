#!/usr/bin/env bash
# curl's own CMake build (D1), the library only, static only (D3), into the
# sub-prefix (D2), with Schannel TLS and Windows' CA store, on zig-zlib,
# zig-zstd and zig-brotli from the host env (slice2 D126 B).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libcurl: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libcurl: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# TLS: Schannel only (CURL_USE_OPENSSL defaults ON otherwise); it verifies
# against Windows' certificate store, so there is no CA bundle or CA path to
# set (CMake offers neither for Schannel). SSPI (secur32) comes with it.
# IDN: Windows' own (USE_WIN32_IDN, -lnormaliz); libidn2, libpsl, libssh2
# and nghttp2 default ON when found and are switched off: no zig-* package.
# LDAP: Windows' wldap32 (USE_WIN32_LDAP, the default with LDAP on), one
# more system library, as in Rtools45's build. CURL_ZLIB, CURL_BROTLI and
# CURL_ZSTD ON make a missing library a configure error instead of a quiet
# build without it. Each is found with find_path/find_library in the
# sub-prefix (the toolchain file's CMAKE_FIND_ROOT_PATH; curl leaves
# pkg-config off when cross compiling). No curl tool, docs, man pages,
# tests or examples.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DBUILD_STATIC_LIBS=ON \
  -DBUILD_CURL_EXE=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_LIBCURL_DOCS=OFF \
  -DBUILD_MISC_DOCS=OFF \
  -DENABLE_CURL_MANUAL=OFF \
  -DCURL_ENABLE_SSL=ON \
  -DCURL_USE_SCHANNEL=ON \
  -DCURL_USE_OPENSSL=OFF \
  -DCURL_WINDOWS_SSPI=ON \
  -DUSE_WIN32_IDN=ON \
  -DUSE_LIBIDN2=OFF \
  -DCURL_USE_LIBPSL=OFF \
  -DCURL_USE_LIBSSH2=OFF \
  -DUSE_NGHTTP2=OFF \
  -DCURL_DISABLE_LDAP=OFF \
  -DUSE_WIN32_LDAP=ON \
  -DCURL_ZLIB=ON \
  -DCURL_BROTLI=ON \
  -DCURL_ZSTD=ON
cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
# bin/ holds curl-config and wcurl (shell scripts for the build machine,
# curl-config with the build's absolute paths); consumers read libcurl.pc.
# lib/cmake/CURL goes: CURLConfig.cmake sets CURL_LIBRARIES_PRIVATE to the
# build's absolute paths of libz.a, libbrotlidec.a, libbrotlicommon.a and
# libzstd.a (LIBCURL_PC_LIBS_PRIVATE_LIST), so it is not relocatable.
# CMake's own FindCURL module reads libcurl.pc.
rm -rf "$z/bin" "$z/share" "$z/lib/cmake/CURL"
rmdir "$z/lib/cmake" 2>/dev/null || true

# libcurl.pc: a static-only build already folds the private fields into the
# public ones: Requires names zlib, libbrotlidec, libbrotlicommon and
# libzstd, Libs the same libraries and the Windows system libraries, Cflags
# -DCURL_STATICLIB (curl.h dllimports every function without it). It
# keeps the same words in the .private fields too, which close-pc would
# append a second time, so those lines go first; the check below makes
# sure the public fields have what a static link needs.
pcf="$z/lib/pkgconfig/libcurl.pc"
sed -i -E '/^(Requires|Libs|Cflags)\.private:/d' "$pcf"
for w in -DCURL_STATICLIB -lz -lzstd -lbrotlidec -lbrotlicommon -lbcrypt -ladvapi32 -lcrypt32 -lsecur32 -lnormaliz -lwldap32 -lws2_32 -liphlpapi; do
  grep -E "^(Cflags|Libs):.* ${w}( |$)" "$pcf" >/dev/null \
    || { echo "zig-libcurl: '${w}' missing from libcurl.pc:" >&2; cat "$pcf" >&2; exit 1; }
done
grep -E '^Requires: +zlib,libbrotlidec,libbrotlicommon,libzstd *$' "$pcf" >/dev/null \
  || { echo "zig-libcurl: unexpected Requires in libcurl.pc:" >&2; cat "$pcf" >&2; exit 1; }
zig-toolchain close-pc "$pcf"
install -Dm644 COPYING "$z/licenses/libcurl/COPYING"
