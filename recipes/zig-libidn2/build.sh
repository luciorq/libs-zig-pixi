#!/usr/bin/env bash
# GNU libidn2's own autotools configure + make (D1), static only (D3), into
# the sub-prefix (D2), through `zig-toolchain configure` (slice2 D104), on
# zig-libunistring and zig-libiconv from the host env (slice3 D130). Only
# the library, idn2.h and libidn2.pc: not the idn2 program (src/), the
# examples, translations (po/) or docs.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libidn2: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libidn2: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

z="${ZIG_LIBS_PREFIX}"
# libunistring and iconv: configure's gl_LIBUNISTRING and AM_ICONV link
# -lunistring and -liconv themselves (no pkg-config lookup), so the
# sub-prefix goes in CPPFLAGS/LDFLAGS as plain flags (--with-*-prefix=<dir>
# would put the absolute build path into libidn2.pc). A libunistring that
# is not found is replaced by the copy in unistring/ (gnulib modules) with
# no error, so the check below fails the build instead: two copies of the
# same u8_* symbols would clash with zig-libunistring in one link.
# --disable-nls: no libintl in the sub-prefix; --disable-doc: no
# man/info pages.
# Two renames: with an external libunistring, unistring/ still compiles
# the gnulib modules an installed (shared) libunistring does not export,
# into libidn2.a. Two of them define names the static closure already
# has: _UC_CATEGORY_NONE (zig-libunistring's libunistring.a exports every
# public symbol, this one too) and locale_charset (zig-libiconv's
# libiconv.a), so pkgtest --unique-c-symbols (DESIGN 6.5) finds each
# twice. libidn2's copies take their own names; the others (c_isalnum,
# mem_iconveh, ...) are private, prefixed names in libunistring.a.
mkdir -p _build && cd _build
CFLAGS="-O2 ${CFLAGS}" zig-toolchain configure ../configure \
  --disable-nls --disable-doc \
  CPPFLAGS="-I${z}/include -D_UC_CATEGORY_NONE=libidn2__UC_CATEGORY_NONE -Dlocale_charset=libidn2_locale_charset" \
  LDFLAGS="-L${z}/lib"
grep -E '^HAVE_LIBUNISTRING = yes$' Makefile >/dev/null \
  && grep -E '^LTLIBUNISTRING = -lunistring( -liconv)? *$' Makefile >/dev/null \
  || { echo "zig-libidn2: libunistring not found, configure would use its own copy:" >&2; grep -E '^(LTLIBUNISTRING|HAVE_LIBUNISTRING)' Makefile >&2; exit 1; }
# gl/ (gnulib) and unistring/ (empty with an external libunistring) are
# lib/'s prerequisites
make -j"${CPU_COUNT:-2}" -C gl
make -j"${CPU_COUNT:-2}" -C unistring
make -j"${CPU_COUNT:-2}" -C lib
make -C lib install DESTDIR="${PREFIX}/Library"
make install-pkgconfigDATA DESTDIR="${PREFIX}/Library"
cd ..

# the renames above: no _UC_CATEGORY_NONE or locale_charset in libidn2.a
dup=$(llvm-nm -g --defined-only "$z/lib/libidn2.a" | awk '$NF == "_UC_CATEGORY_NONE" || $NF == "locale_charset" {print $NF}')
[ -z "$dup" ] || { echo "zig-libidn2: not renamed: ${dup}" >&2; exit 1; }

# lib<n>.a only: no libtool archive
rm -f "$z"/lib/*.la
[ ! -e "$z/bin" ] && [ ! -e "$z/share" ] \
  || { echo "zig-libidn2: unexpected bin/ or share/ in the sub-prefix" >&2; ls -R "$z/bin" "$z/share" >&2 || true; exit 1; }

# libidn2.pc: Libs.private is "@LTLIBICONV@ @LTLIBUNISTRING@" (-liconv
# -lunistring -liconv: configure links libunistring together with libiconv);
# it becomes Requires.private libunistring, whose .pc requires iconv, so
# the closure comes from the .pc files in dependency order. close-pc folds
# the private fields into the public ones.
pcf="$z/lib/pkgconfig/libidn2.pc"
grep -E '^Libs\.private:( +-l(iconv|unistring))+ *$' "$pcf" >/dev/null \
  || { echo "zig-libidn2: unexpected Libs.private in libidn2.pc:" >&2; cat "$pcf" >&2; exit 1; }
sed -i -E 's/^Libs\.private:.*$/Requires.private: libunistring/' "$pcf"
zig-toolchain close-pc "$pcf"
for f in COPYING.LESSERv3 COPYINGv2 COPYING.unicode; do
  install -Dm644 "$f" "$z/licenses/libidn2/$f"
done
