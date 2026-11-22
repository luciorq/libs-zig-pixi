#!/usr/bin/env bash
# GDAL's own CMake build (D1), static only (D3), into the sub-prefix (D2),
# options as DESIGN 6.3 (D6, D14). zig-toolchain's activation script set
# CMAKE_ARGS, ZIG_LIBS_PREFIX, CC, ...
set -euo pipefail
: "${ZIG_LIBS_PREFIX:?zig-toolchain activation did not run}"
# both zigs (D11): $ZIG_BIN when the upstream-zig leg sets it; either way
# the zig the wrappers run must be the variant's version
zig_bin="${ZIG_BIN:-}"; v=$("${zig_bin:-zig}" version)
echo "zig-gdal: ZIG_BIN='${zig_bin}' zig version: $v ($(command -v "${zig_bin:-zig}"))"
[ "$v" = "${ZIG_VERSION}" ] || { echo "zig-gdal: zig is $v, variants.yaml says ${ZIG_VERSION}" >&2; exit 1; }

# External: PROJ (always required: GDAL has no GDAL_USE_PROJ option),
# GEOS, SQLite3, expat, zlib (zig-* host packages, found
# in the sub-prefix through the toolchain file's root path; one copy of
# each in the link closure). Everything else GDAL can use is its internal
# copy (GDAL_USE_*_INTERNAL) or off (GDAL_USE_EXTERNAL_LIBS=OFF), iconv
# included (DESIGN 6.3). All built-in drivers (D14). No try_run runs in
# this configuration (the only one, the iconv charset check, is behind
# GDAL_USE_ICONV), so no preset cache entries are needed.
cmake -S . -B _build ${CMAKE_ARGS} \
  -DBUILD_APPS=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_PYTHON_BINDINGS=OFF \
  -DBUILD_JAVA_BINDINGS=OFF \
  -DBUILD_CSHARP_BINDINGS=OFF \
  -DGDAL_USE_EXTERNAL_LIBS=OFF \
  -DGDAL_USE_INTERNAL_LIBS=ON \
  -DGDAL_USE_GEOS=ON \
  -DGDAL_USE_SQLITE3=ON \
  -DGDAL_USE_EXPAT=ON \
  -DGDAL_USE_ZLIB=ON \
  -DGDAL_USE_ZLIB_INTERNAL=OFF \
  -DGDAL_USE_ICONV=OFF \
  -DGDAL_USE_TIFF_INTERNAL=ON \
  -DGDAL_USE_GEOTIFF_INTERNAL=ON \
  -DGDAL_USE_JPEG_INTERNAL=ON \
  -DGDAL_USE_PNG_INTERNAL=ON \
  -DGDAL_USE_GIF_INTERNAL=ON \
  -DGDAL_USE_JSONC_INTERNAL=ON \
  -DGDAL_USE_LERC_INTERNAL=ON \
  -DGDAL_USE_QHULL_INTERNAL=ON \
  -DGDAL_USE_SHAPELIB_INTERNAL=ON \
  -DEMBED_RESOURCE_FILES=ON
c=_build/CMakeCache.txt
grep -E '^(GDAL_USE_[A-Z0-9_]*|EMBED_RESOURCE_FILES|IS_SHARP_EMBED_AVAILABLE_RES|(PROJ|GEOS|SQLite3|EXPAT|ZLIB)_(DIR|INCLUDE_DIRS?|LIBRARY[A-Z_]*)):' "$c" || true
for k in GDAL_USE_GEOS GDAL_USE_SQLITE3 GDAL_USE_EXPAT GDAL_USE_ZLIB EMBED_RESOURCE_FILES; do
  grep -q "^${k}:BOOL=ON$" "$c" || { echo "zig-gdal: ${k} is not ON" >&2; exit 1; }
done
grep -q '^GDAL_USE_ZLIB_INTERNAL:BOOL=OFF$' "$c"
grep -Eq '^GDAL_USE_ICONV:[A-Z]+=OFF$' "$c"
# every library and include dir CMake found is in the sub-prefix (the
# toolchain file looks only there; this guards against a host copy)
while IFS= read -r l; do
  p=${l#*=}
  case "$p" in
    "${ZIG_LIBS_PREFIX}"/*) ;;
    *) echo "zig-gdal: ${l} is not in ${ZIG_LIBS_PREFIX}" >&2; exit 1 ;;
  esac
done < <(grep -E "^[A-Za-z0-9_]*_(LIBRARY|LIBRARY_RELEASE|INCLUDE_DIR|DIR):(FILE)?PATH=/" "$c" || true)

cmake --build _build
cmake --install _build

z="${ZIG_LIBS_PREFIX}"
# lib<n>.a only; no gdal-config (bin/), plugins dir, man pages or bash
# completions (installed even with BUILD_APPS=OFF)
rm -f "$z"/lib/*.dll.a "$z"/lib/*.lib
rm -rf "$z/bin" "$z/lib/gdalplugins" "$z/share/man" "$z/share/doc" "$z/share/bash-completion"
ls -l "$z/lib/libgdal.a"

# gdal.pc as GDAL writes it is not usable here: prefix comes through
# CONFIG_INST_PREFIX and Libs (static build) lists the dependencies as
# absolute archive paths of the host prefix. It is written anew from the
# link interface CMake computed (the words of CONFIG_INST_LIBS): the
# zig-libs dependencies become Requires (their own closed .pc files), the
# remaining -l words are the Windows system libraries libgdal.a needs;
# GDAL writes ole32 and shell32 as -lole32.lib -lshell32.lib (MSVC
# names, as MXE also fixes), normalised to -lole32 -lshell32;
# -lc++ lets a C program link through `pkgconf --libs gdal` alone (zig
# links its own libc++ for it).
pc="$z/lib/pkgconfig/gdal.pc"
echo "zig-gdal: gdal.pc as installed:"; cat "$pc"
inst_libs=$(sed -n 's/^CONFIG_INST_LIBS=//p' "$pc")
syslibs=""
for w in $inst_libs; do
  case "$w" in
    -L*|-lgdal|"") ;;
    */libproj.a|*/libgeos_c.a|*/libgeos.a|*/libsqlite3.a|*/libexpat.a|*/libz.a) ;;
    -lproj|-lgeos_c|-lgeos|-lsqlite3|-lexpat|-lz) ;;
    -l*.lib) w=${w%.lib} ;&
    -l*) case " $syslibs " in *" $w "*) ;; *) syslibs="$syslibs $w" ;; esac ;;
    *) echo "zig-gdal: unexpected word in CONFIG_INST_LIBS: $w" >&2; exit 1 ;;
  esac
done
echo "zig-gdal: system libraries from the link interface:${syslibs}"
cat > "$pc" <<PC
prefix=${z}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
datadir=\${prefix}/share/gdal

Name: libgdal
Description: Geospatial Data Abstraction Library
Version: ${PKG_VERSION}
Requires: proj geos sqlite3 expat zlib
Libs: -L\${libdir} -lgdal -lc++${syslibs}
Cflags: -I\${includedir}
PC
zig-toolchain close-pc "$pc"
echo "zig-gdal: gdal.pc closed:"; cat "$pc"

# No CMake package config (lib/cmake/gdal): gdal.pc is the interface
# (DESIGN 5.5), and the config would find_dependency(PROJ) through a CMake
# config or FindPROJ module that zig-proj does not ship.
rm -rf "$z/lib/cmake/gdal"
rmdir "$z/lib/cmake" 2>/dev/null || true
# no build path in the generated header (cpl_config.h: GDAL_PREFIX is gone
# with the patch)
if grep -l -e "${PREFIX}" -e "${BUILD_PREFIX}" -e "${SRC_DIR}" "$z/include/cpl_config.h"; then
  echo "zig-gdal: installed headers name build paths" >&2; exit 1
fi
install -Dm644 LICENSE.TXT "$z/licenses/gdal/LICENSE.TXT"
