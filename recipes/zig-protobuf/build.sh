#!/usr/bin/env bash
# protobuf's own CMake build (D1), static only (D3), into the sub-prefix
# (D2), on zig-abseil from the host env (protobuf_ABSL_PROVIDER=package,
# abseil's lib/cmake/absl in the sub-prefix). protoc.exe is built for the
# target (an arm64 protoc on win-arm64) and installed in <sub>/bin, where
# r-zig puts it on R CMD's PATH (slice3 D132).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CXX, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-protobuf: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-protobuf: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# protoc --version prints "libprotoc " ProtocVersionString(PROTOBUF_VERSION)
# PROTOBUF_VERSION_SUFFIX (compiler/command_line_interface.cc), and
# runtime_version.h's 5029005 and "" give "libprotoc 29.5"
rv=src/google/protobuf/runtime_version.h
grep -q '^#define PROTOBUF_OSS_VERSION 5029005$' "$rv" \
  && grep -q '^#define PROTOBUF_OSS_VERSION_SUFFIX ""$' "$rv" \
  || { echo "zig-protobuf: $rv is not protobuf 29.5" >&2; exit 1; }

# protobuf_BUILD_LIBPROTOC: libprotoc.a, as Rtools45 ships it.
# protobuf_BUILD_LIBUPB (the default): libupb.a and upb.pc, as Rtools45
# has upb's libraries; it also builds upb's three protoc-gen-upb* plugins
# (Rtools45 ships none), kept because protobuf's exported CMake targets
# name them.
# protobuf_WITH_ZLIB=OFF: Rtools45's protobuf.pc links no zlib (gzip
# streams off), so no zig-zlib dependency. No tests, conformance or
# examples. protobuf_BUILD_SHARED_LIBS=OFF keeps PROTOBUF_USE_DLLS out of
# protobuf.pc's Cflags (cmake/install.cmake sets it for shared builds).
cmake -S . -B _build ${CMAKE_ARGS} \
  -DCMAKE_CXX_STANDARD=17 \
  -Dprotobuf_BUILD_SHARED_LIBS=OFF \
  -Dprotobuf_ABSL_PROVIDER=package \
  -Dprotobuf_BUILD_TESTS=OFF \
  -Dprotobuf_BUILD_CONFORMANCE=OFF \
  -Dprotobuf_BUILD_EXAMPLES=OFF \
  -Dprotobuf_BUILD_PROTOBUF_BINARIES=ON \
  -Dprotobuf_BUILD_PROTOC_BINARIES=ON \
  -Dprotobuf_BUILD_LIBPROTOC=ON \
  -Dprotobuf_BUILD_LIBUPB=ON \
  -Dprotobuf_WITH_ZLIB=OFF \
  -Dprotobuf_INSTALL=ON
cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
# CMake on a linux host gives each executable with a VERSION property
# (protoc, the three protoc-gen-upb* plugins) a versioned file and a
# symlink to it (protoc.exe -> protoc.exe-29.5.0), even for a Windows
# target. A Windows package gets no symlinks: the real file takes the plain
# name, and protobuf's exported CMake targets name that file.
for exe in "$z"/bin/*.exe; do
  [ -L "$exe" ] || { echo "zig-protobuf: $exe is not the expected symlink" >&2; exit 1; }
  real="$exe-${PKG_VERSION}.0"
  [ "$(readlink "$exe")" = "$(basename "$real")" ] && [ -f "$real" ] && [ ! -L "$real" ] \
    || { echo "zig-protobuf: $exe does not point at $(basename "$real")" >&2; exit 1; }
  rm -f "$exe"
  mv "$real" "$exe"
done
sed -i -E 's#(/bin/[A-Za-z_-]+\.exe)-'"${PKG_VERSION}"'\.0"#\1"#g' "$z/lib/cmake/protobuf/protobuf-targets-release.cmake"
! grep -n -- "-${PKG_VERSION}" "$z/lib/cmake/protobuf/protobuf-targets-release.cmake" \
  || { echo "zig-protobuf: a versioned executable name is left in protobuf-targets-release.cmake" >&2; exit 1; }
[ -z "$(find "$z/bin" -mindepth 1 ! -name '*.exe')" ] \
  || { echo "zig-protobuf: unexpected files in bin/:" >&2; ls -la "$z/bin" >&2; exit 1; }

# The .pc files: protobuf.pc and protobuf-lite.pc require the absl_*.pc
# modules protobuf links (cmake/abseil-cpp.cmake, protobuf_ABSL_USED_TARGETS)
# and utf8_range.pc (which requires absl_strings), so pkg-config's own
# closure gives every archive in link order; Cflags are -I only (no
# PROTOBUF_USE_DLLS in a static build, no MSVC flag). upb.pc as installed.
# abseil's Windows system libraries come with its .pc files.
pcd="$z/lib/pkgconfig"
for f in protobuf protobuf-lite utf8_range upb; do
  grep -E '^Cflags: -I\$\{includedir\} *$' "$pcd/$f.pc" >/dev/null \
    || { echo "zig-protobuf: unexpected Cflags in $f.pc:" >&2; cat "$pcd/$f.pc" >&2; exit 1; }
done
for f in protobuf protobuf-lite; do
  grep -E '^Requires: .*absl_base .*utf8_range *$' "$pcd/$f.pc" >/dev/null \
    || { echo "zig-protobuf: $f.pc does not require abseil and utf8_range:" >&2; cat "$pcd/$f.pc" >&2; exit 1; }
done
zig-toolchain close-pc "$pcd/protobuf.pc" "$pcd/protobuf-lite.pc" "$pcd/utf8_range.pc" "$pcd/upb.pc"
install -Dm644 LICENSE "$z/licenses/protobuf/LICENSE"
# libutf8_range.a and libutf8_validity.a: utf8_range's own MIT licence
install -Dm644 third_party/utf8_range/LICENSE "$z/licenses/protobuf/utf8_range-LICENSE"
