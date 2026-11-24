#!/usr/bin/env bash
# PostgreSQL's own meson build (D1), cross through zig-toolchain's meson
# cross file, only the client library's targets (slice2 D119, S2-F26):
# libpq.a and the two archives it needs, libpgcommon.a and libpgport.a, not
# the server. Static only (D3), into the sub-prefix (D2). OpenSSL from
# zig-openssl (pkg-config), LDAP from Windows' wldap32, as Rtools45's build;
# with Rtools45's c.h patch (recipe.yaml).
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
: "${ZIG_TOOLCHAIN_MESON_CROSS:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-libpq: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-libpq: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# -Dsystem_tzdata: no time zone files to compile (a native zic otherwise);
# the client never reads them.
# Without the activation's -ffile-prefix-map=<build dir>=...: src/common's
# config_info.c compiles the configure-time CFLAGS in as strings (pg_config's
# report), so the flag would put the build path into libpgcommon.a
# (pkgtest). meson compiles with relative paths (../src/...), so there is
# nothing for the flag to rewrite.
cflags=()
for f in ${CFLAGS}; do case "$f" in -ffile-prefix-map=*) ;; *) cflags+=("$f") ;; esac; done
CFLAGS="-O2 ${cflags[*]}" \
meson setup _build . \
  --cross-file "${ZIG_TOOLCHAIN_MESON_CROSS}" \
  --prefix="/zig-libs/${ZIG_TOOLCHAIN_TARGET}" --libdir=lib \
  --buildtype=release \
  -Dsystem_tzdata=/dev/null \
  -Dssl=openssl -Dldap=enabled \
  -Dicu=disabled -Dreadline=disabled -Dzlib=disabled -Dnls=disabled \
  -Dgssapi=disabled -Dlz4=disabled -Dzstd=disabled -Dlibxml=disabled \
  -Dlibxslt=disabled -Dplperl=disabled -Dplpython=disabled -Dpltcl=disabled \
  -Dsystemd=disabled -Duuid=none -Dtap_tests=disabled
ninja -C _build -j"${CPU_COUNT:-2}" \
  src/interfaces/libpq/libpq.a src/common/libpgcommon.a src/port/libpgport.a

# The client part of what `meson install` puts in include/ and lib/
# (src/include/meson.build, src/interfaces/libpq/meson.build): a full
# install would build the server first.
p="${ZIG_LIBS_PREFIX}"
install -Dm644 -t "$p/lib" _build/src/interfaces/libpq/libpq.a \
  _build/src/common/libpgcommon.a _build/src/port/libpgport.a
install -Dm644 -t "$p/include" src/interfaces/libpq/libpq-fe.h \
  src/interfaces/libpq/libpq-events.h src/include/postgres_ext.h \
  src/include/pg_config_manual.h _build/src/include/pg_config_ext.h \
  _build/src/include/pg_config.h _build/src/include/pg_config_os.h
install -Dm644 -t "$p/include/libpq" src/include/libpq/libpq-fs.h
install -Dm644 -t "$p/include/postgresql/internal" src/include/c.h \
  src/include/port.h src/include/postgres_fe.h \
  src/interfaces/libpq/libpq-int.h src/interfaces/libpq/fe-auth-sasl.h \
  src/interfaces/libpq/pqexpbuffer.h
install -Dm644 -t "$p/include/postgresql/internal/libpq" src/include/libpq/pqcomm.h

# meson's libpq.pc: Libs -lpq; Libs.private the Windows libraries
# (-lsecur32 -lwldap32 -lws2_32), -lpgport -lpgcommon; Requires.private
# openssl. close-pc moves them into Libs and Requires (RPostgres reads
# `pkg-config --libs libpq` and looks for ldap32) and makes it relocatable.
install -Dm644 _build/meson-private/libpq.pc "$p/lib/pkgconfig/libpq.pc"
zig-toolchain close-pc "$p/lib/pkgconfig/libpq.pc"
install -Dm644 COPYRIGHT "$p/licenses/libpq/COPYRIGHT"
