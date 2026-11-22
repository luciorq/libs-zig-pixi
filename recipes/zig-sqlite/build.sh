#!/usr/bin/env bash
# The amalgamation compiled directly (DESIGN 6.1): sqlite3.c -> libsqlite3.a
# with the Rtools option set (compile-options.h, DESIGN 6.2), a written
# sqlite3.pc, static only (D3), into the sub-prefix (D2).
# zig-toolchain's activation script set CC, AR, RANLIB, CFLAGS,
# ZIG_LIBS_PREFIX.
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-sqlite: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-sqlite: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# -DSQLITE_<o> for every SQLITE_OPTION_SET("<o>") line, and nothing else
defs=$(sed -n 's/^SQLITE_OPTION_SET("\(.*\)")$/-DSQLITE_\1/p' "${RECIPE_DIR}/compile-options.h")
[ "$(printf '%s\n' $defs | wc -l)" -eq 8 ] || { echo "zig-sqlite: expected 8 options, got: $defs" >&2; exit 1; }
echo "zig-sqlite: defines: $defs"

# -O2 as Rtools; CFLAGS: -g0, sections, -ffile-prefix-map (activation)
$CC -O2 ${CFLAGS} $defs -c sqlite3.c -o sqlite3.o
mkdir -p "${ZIG_LIBS_PREFIX}/lib/pkgconfig" "${ZIG_LIBS_PREFIX}/include"
$AR rcs "${ZIG_LIBS_PREFIX}/lib/libsqlite3.a" sqlite3.o
$RANLIB "${ZIG_LIBS_PREFIX}/lib/libsqlite3.a"
install -m644 sqlite3.h sqlite3ext.h "${ZIG_LIBS_PREFIX}/include/"

# Windows needs no system library beyond zig's defaults (kernel32), so the
# closed Libs is -lsqlite3 alone and there is no Requires.
cat > "${ZIG_LIBS_PREFIX}/lib/pkgconfig/sqlite3.pc" <<PC
prefix=${ZIG_LIBS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: SQLite
Description: SQL database engine (static, zig-built)
Version: ${PKG_VERSION}
Libs: -L\${libdir} -lsqlite3
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "${ZIG_LIBS_PREFIX}/lib/pkgconfig/sqlite3.pc"
cat "${ZIG_LIBS_PREFIX}/lib/pkgconfig/sqlite3.pc"
install -Dm644 "${RECIPE_DIR}/LICENSE" "${ZIG_LIBS_PREFIX}/licenses/sqlite/LICENSE"
