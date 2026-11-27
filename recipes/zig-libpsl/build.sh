#!/usr/bin/env bash
# libpsl's own meson build (D1), cross through zig-toolchain's meson cross
# file (slice2 D119), static only (D3), into the sub-prefix (D2), on
# zig-libidn2, zig-libunistring and zig-libiconv from the host env (slice3
# D130): the release's built-in list and run-time IDNA through libidn2.
# meson over the autotools build: on a static-only Windows build meson's
# src/meson.build compiles with -DPSL_STATIC and writes it into
# libpsl.pc's Cflags; autotools does neither, so libpsl.h would
# dllexport (build) and dllimport (consumer) every function.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
: "${ZIG_TOOLCHAIN_MESON_CROSS:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libpsl: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libpsl: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

z="${ZIG_LIBS_PREFIX}"
# -Druntime=libidn2: an error when libidn2 is missing ('auto' would fall
# back to no IDNA). libidn2 comes through pkg-config; libunistring and
# iconv through meson's cc.find_library and dependency('iconv'), which
# search the compiler's paths only, so the sub-prefix goes in c_args and
# c_link_args (the build's command lines; meson writes neither into
# libpsl.pc). Setting c_args replaces the CFLAGS meson would take from the
# environment, so the activation's CFLAGS (-ffile-prefix-map=$SRC_DIR=.,
# ...) go in first: without them libpsl.a holds the build path (pkgtest).
# -Dpsl_file: the list the built-in data is made from, as a path relative
# to src/ (meson resolves custom_target inputs there). psl-make-dafsa
# writes the path it is given into libpsl.a (psl_builtin_filename(), and
# psl_builtin_outdated() stats it); the default is the absolute path in
# the source tree, a build path (pkgtest), so it is relative here and names
# no file on the user's machine (psl_builtin_outdated() then says 0).
# No docs, no tests (they need the build machine to run them).
meson setup _build . \
  --cross-file "${ZIG_TOOLCHAIN_MESON_CROSS}" \
  --prefix="${ZIG_LIBS_PREFIX}" --libdir=lib \
  --buildtype=release \
  -Ddefault_library=static \
  -Druntime=libidn2 -Dbuiltin=true \
  -Dpsl_file=../list/public_suffix_list.dat \
  -Ddocs=false -Dtests=false \
  -Dc_args="${CFLAGS} -I${z}/include" -Dc_link_args="${LDFLAGS:-} -L${z}/lib"
grep -E '^#define WITH_LIBIDN2( 1)?$' _build/config.h >/dev/null \
  && grep -E '^#define ENABLE_BUILTIN( 1)?$' _build/config.h >/dev/null \
  || { echo "zig-libpsl: libidn2 or the built-in list not enabled:" >&2; cat _build/config.h >&2; exit 1; }
# the library only: tools/ builds the psl program, whose install (tag
# runtime) and man pages (tag man) the devel tag leaves out, with
# psl-make-dafsa (install_data, untagged)
ninja -C _build -j"${CPU_COUNT:-2}" src/libpsl.a
meson install -C _build --no-rebuild --tags devel
[ ! -e "$z/bin" ] && [ ! -e "$z/share" ] \
  || { echo "zig-libpsl: unexpected bin/ or share/ in the sub-prefix" >&2; ls -R "$z/bin" "$z/share" >&2 || true; exit 1; }

# libpsl.pc: on a static-only build meson writes Requires libidn2 (found
# through pkg-config) and the find_library results into Libs (-lunistring
# -lws2_32 -liconv). libunistring goes into Requires instead (its .pc
# requires iconv), so the closure comes from the .pc files in dependency
# order; -lws2_32 (a system library) stays. close-pc folds any private
# field into the public ones.
pcf="$z/lib/pkgconfig/libpsl.pc"
grep -E '^Requires: +libidn2 *$' "$pcf" >/dev/null \
  && grep -E '^Libs: +-L\$\{libdir\} -lpsl -lunistring -lws2_32 -liconv *$' "$pcf" >/dev/null \
  || { echo "zig-libpsl: unexpected Requires or Libs in libpsl.pc:" >&2; cat "$pcf" >&2; exit 1; }
sed -i -E -e 's/^Requires: +libidn2 *$/Requires: libidn2 libunistring/' \
  -e 's/^Libs: .*$/Libs: -L${libdir} -lpsl -lws2_32/' "$pcf"
zig-toolchain close-pc "$pcf"
grep -E '^Cflags:.* -DPSL_STATIC( |$)' "$pcf" >/dev/null \
  || { echo "zig-libpsl: -DPSL_STATIC missing from libpsl.pc:" >&2; cat "$pcf" >&2; exit 1; }
install -Dm644 LICENSE "$z/licenses/libpsl/LICENSE"
install -Dm644 src/LICENSE.chromium "$z/licenses/libpsl/LICENSE.chromium"
