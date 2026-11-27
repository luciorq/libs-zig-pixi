#!/usr/bin/env bash
# curl's own CMake build (D1), the library only, static only (D3), into the
# sub-prefix (D2), with Schannel TLS and Windows' CA store, on zig-zlib,
# zig-zstd and zig-brotli (slice2 D126 B) and, since build 2, zig-libssh2,
# zig-nghttp2, zig-libidn2 and zig-libpsl (slice3 D130) from the host env.
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
# Rtools45's other features (slice3 D130): SFTP/SCP through libssh2 (on
# zig-openssl's libcrypto; curl's TLS stays Schannel), HTTP/2 through
# nghttp2, IDN through libidn2 (USE_WIN32_IDN off: curl looks for libidn2
# only then) and cookie domain checks through libpsl.
# LDAP: Windows' wldap32 (USE_WIN32_LDAP, the default with LDAP on), one
# more system library, as in Rtools45's build. CURL_ZLIB, CURL_BROTLI and
# CURL_ZSTD ON make a missing library a configure error instead of a quiet
# build without it; libpsl and libssh2 are REQUIRED when on, nghttp2 and
# libidn2 are not, so the curl_config.h check below covers them. Each is
# found with find_path/find_library in the sub-prefix (the toolchain file's
# CMAKE_FIND_ROOT_PATH; curl leaves pkg-config off when cross compiling,
# and it stays off: no unpinned pkgconf shaping the build, R15). Without
# pkg-config no -D from the .pc files reaches curl's sources:
# NGHTTP2_STATICLIB and PSL_STATIC go in CFLAGS, or nghttp2.h and
# libpsl.h declare every function dllimport (`__imp_nghttp2_*`,
# `__imp_psl_*` undefined at a static link; checked after the build).
# libcurl.pc still names the modules (INTERFACE_LIBCURL_PC_MODULES).
# No curl tool, docs, man pages, tests or examples.
CFLAGS="${CFLAGS} -DNGHTTP2_STATICLIB -DPSL_STATIC"
export CFLAGS
# if_nametoindex (slice2 D128, S2-F35): off, so curl loads it from
# iphlpapi.dll at run time (Curl_if_nametoindex, its pre-Vista path) and
# libcurl.a needs no -liphlpapi, as Rtools45's libcurl; R packages that
# hard-code Rtools' link list (Rhtslib) link it. curl's Windows prefill
# sets HAVE_IF_NAMETOINDEX=1 for MinGW over any -D, so _CURL_PREFILL is
# off too and CMake runs the checks; curl_config.h differs from the
# prefilled one in HAVE_IF_NAMETOINDEX only (checked on win-arm64).
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
  -DUSE_WIN32_IDN=OFF \
  -DUSE_LIBIDN2=ON \
  -DCURL_USE_LIBPSL=ON \
  -DCURL_USE_LIBSSH2=ON \
  -DCURL_USE_LIBSSH=OFF \
  -DUSE_NGHTTP2=ON \
  -DUSE_NGTCP2=OFF \
  -DUSE_QUICHE=OFF \
  -DUSE_LIBRTMP=OFF \
  -DCURL_USE_GSSAPI=OFF \
  -DCURL_DISABLE_LDAP=OFF \
  -DUSE_WIN32_LDAP=ON \
  -DCURL_ZLIB=ON \
  -DCURL_BROTLI=ON \
  -DCURL_ZSTD=ON \
  -D_CURL_PREFILL=OFF \
  -DHAVE_IF_NAMETOINDEX=0
grep -q '^/\* #undef HAVE_IF_NAMETOINDEX \*/$' _build/lib/curl_config.h \
  || { echo "zig-libcurl: HAVE_IF_NAMETOINDEX is set (D128)" >&2; exit 1; }
# the D130 features, each found (nghttp2 and libidn2 are optional to curl)
for d in USE_LIBSSH2 USE_NGHTTP2 HAVE_LIBIDN2 HAVE_IDN2_H USE_LIBPSL; do
  grep -q "^#define $d 1\$" _build/lib/curl_config.h \
    || { echo "zig-libcurl: $d not set in curl_config.h (D130)" >&2; exit 1; }
done
! grep -q '^#define USE_WIN32_IDN 1$' _build/lib/curl_config.h \
  || { echo "zig-libcurl: USE_WIN32_IDN is set (D130: libidn2)" >&2; exit 1; }
cmake --build _build
# no dllimport reference to a static zig-* library (NGHTTP2_STATICLIB,
# PSL_STATIC above; libssh2.h and idn2.h import only for a DLL build)
# (the listing first, so a failing llvm-nm stops the build under set -e)
undef=$(llvm-nm -u _build/lib/libcurl.a)
[ -n "$undef" ] || { echo "zig-libcurl: llvm-nm listed nothing" >&2; exit 1; }
if grep -E '__imp_(nghttp2|psl|idn2|libssh2|inflate|deflate|ZSTD|Brotli)' <<< "$undef"; then
  echo "zig-libcurl: dllimport references to static libraries in libcurl.a" >&2; exit 1
fi
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
# public ones: Requires names zlib, libbrotlidec, libbrotlicommon, libzstd,
# libssh2, libnghttp2, libidn2 and libpsl (whose .pc files bring libcrypto,
# libunistring, iconv and their Cflags -DNGHTTP2_STATICLIB, -DPSL_STATIC),
# Libs the same libraries and the Windows system libraries, Cflags
# -DCURL_STATICLIB (curl.h dllimports every function without it). It
# keeps the same words in the .private fields too, which close-pc would
# append a second time, so those lines go first; the check below makes
# sure the public fields have what a static link needs.
pcf="$z/lib/pkgconfig/libcurl.pc"
sed -i -E '/^(Requires|Libs|Cflags)\.private:/d' "$pcf"
# -liphlpapi goes too: curl's CMake lists it on every Windows build, but
# nothing in libcurl.a imports from it any more (D128); pkgtest's smoke
# links through this .pc, so it proves the link without iphlpapi.
sed -i -E '/^Libs:/s/ -liphlpapi( |$)/\1/' "$pcf"
! grep -q -- '-liphlpapi' "$pcf" \
  || { echo "zig-libcurl: -liphlpapi left in libcurl.pc:" >&2; cat "$pcf" >&2; exit 1; }
for w in -DCURL_STATICLIB -lz -lzstd -lbrotlidec -lbrotlicommon -lssh2 -lnghttp2 -lidn2 -lpsl -lbcrypt -ladvapi32 -lcrypt32 -lsecur32 -lwldap32 -lws2_32; do
  grep -E "^(Cflags|Libs):.* ${w}( |$)" "$pcf" >/dev/null \
    || { echo "zig-libcurl: '${w}' missing from libcurl.pc:" >&2; cat "$pcf" >&2; exit 1; }
done
req=$(sed -n -E 's/^Requires: *//p' "$pcf" | tr ', ' '\n\n' | sed '/^$/d' | sort | tr '\n' ' ')
[ "$req" = "libbrotlicommon libbrotlidec libidn2 libnghttp2 libpsl libssh2 libzstd zlib " ] \
  || { echo "zig-libcurl: unexpected Requires in libcurl.pc ($req):" >&2; cat "$pcf" >&2; exit 1; }
zig-toolchain close-pc "$pcf"
install -Dm644 COPYING "$z/licenses/libcurl/COPYING"
