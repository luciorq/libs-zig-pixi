#!/usr/bin/env bash
# abseil's own CMake build (D1), static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CMAKE_ARGS, ZIG_LIBS_PREFIX, CXX, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-abseil: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-abseil: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# The toolchain file says CMAKE_SYSTEM_PROCESSOR ARM64 on win-arm64, which
# abseil's `arm.*|aarch64` match (AbseilConfigureCopts.cmake) does not take:
# no -march=armv8-a+crypto, randen uses its portable path (DESIGN 4.4).
cmake -S . -B _build ${CMAKE_ARGS} \
  -DCMAKE_CXX_STANDARD=17 \
  -DABSL_PROPAGATE_CXX_STD=ON \
  -DABSL_BUILD_TESTING=OFF \
  -DBUILD_TESTING=OFF \
  -DABSL_ENABLE_INSTALL=ON
cmake --build _build
cmake --install _build

# static only: abseil builds no DLL with BUILD_SHARED_LIBS=OFF; make sure
rm -f "${ZIG_LIBS_PREFIX}"/lib/*.dll.a "${ZIG_LIBS_PREFIX}"/lib/*.lib
rm -rf "${ZIG_LIBS_PREFIX}/bin"

# abseil writes one absl_<module>.pc per module (Requires: the absl_*
# modules it uses, Libs: its archive and the Windows system libraries,
# -ladvapi32 / -ldbghelp / -lbcrypt under MINGW). Its Cflags keep only
# -Wno-*, -D and -I words (CMake/AbseilHelpers.cmake drops every other -W),
# so CRAN's removal of -Wnon-virtual-dtor has nothing to do here; the
# package test checks it. Make every one relocatable.
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}"/lib/pkgconfig/absl_*.pc
install -Dm644 LICENSE "${ZIG_LIBS_PREFIX}/licenses/abseil/LICENSE"
