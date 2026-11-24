# zig-toolchain activation (etc/conda/activate.d): the cross compiler
# variables for rattler-build's target_platform. It does nothing for any
# other target (a linux-64 build of zig-toolchain itself, a plain env).
#
#   CC CXX AR RANLIB RC WINDRES DLLTOOL   the <triple>-* wrappers
#   CFLAGS CXXFLAGS     -g0 -ffunction-sections -fdata-sections, and
#                       -ffile-prefix-map=$SRC_DIR=. when SRC_DIR is set
#   ZIG_LIBS_PREFIX     <host prefix>/Library/zig-libs/<zig triple>: where
#                       zig-* packages install and find each other (D2)
#   PKG_CONFIG_LIBDIR   its lib/pkgconfig only (never the build machine's)
#   CMAKE_ARGS          the toolchain file, Ninja, Release, static, the
#                       sub-prefix as install prefix, IPO off. No
#                       CMAKE_PREFIX_PATH: the toolchain file's
#                       CMAKE_FIND_ROOT_PATH already finds libraries,
#                       headers and packages in the sub-prefix, and a
#                       prefix path would let find_program pick up
#                       <sub-prefix>/bin scripts (foo-config) on the host
#   ZIG_TOOLCHAIN_MESON_CROSS   the meson cross file (first used by zig-libpq)
#   ZIG_GLOBAL_CACHE_DIR  $LIBS_ZIG_CACHE when the recipe passes it (CI: one
#                       cache per job, kept between runs; slice2 D115),
#                       else under $SRC_DIR. Zig's cache is content
#                       addressed: it holds the target's C runtime and
#                       libc++, built once per cache instead of per recipe
#   ZIG_LOCAL_CACHE_DIR   under $SRC_DIR when set, so the recipe's own
#                       objects never come from or go to a shared cache
case "${target_platform:-}" in
  win-64) _zt_gnu=x86_64-w64-mingw32; _zt_zig=x86_64-windows-gnu ;;
  win-arm64) _zt_gnu=aarch64-w64-mingw32; _zt_zig=aarch64-windows-gnu ;;
  *) _zt_gnu= ; _zt_zig= ;;
esac
if [ -n "${_zt_gnu}" ]; then
  _zt_root="${BUILD_PREFIX:-${CONDA_PREFIX}}"
  _zt_host="${PREFIX:-${CONDA_PREFIX}}"
  export ZIG_TOOLCHAIN_TARGET="${_zt_zig}"
  export ZIG_LIBS_PREFIX="${_zt_host}/Library/zig-libs/${_zt_zig}"
  export CC="${_zt_gnu}-cc" CXX="${_zt_gnu}-c++" AR="${_zt_gnu}-ar" RANLIB="${_zt_gnu}-ranlib"
  export RC="${_zt_gnu}-windres" WINDRES="${_zt_gnu}-windres" DLLTOOL="${_zt_gnu}-dlltool"
  _zt_flags="-g0 -ffunction-sections -fdata-sections"
  if [ -n "${SRC_DIR:-}" ]; then
    _zt_flags="${_zt_flags} -ffile-prefix-map=${SRC_DIR}=."
    export ZIG_GLOBAL_CACHE_DIR="${LIBS_ZIG_CACHE:-${SRC_DIR}/.zig-global-cache}"
    export ZIG_LOCAL_CACHE_DIR="${SRC_DIR}/.zig-local-cache"
  fi
  export CFLAGS="${_zt_flags}" CXXFLAGS="${_zt_flags}"
  export PKG_CONFIG_LIBDIR="${ZIG_LIBS_PREFIX}/lib/pkgconfig"
  export ZIG_TOOLCHAIN_MESON_CROSS="${_zt_root}/share/zig-toolchain/${_zt_gnu}.ini"
  export CMAKE_ARGS="-G Ninja -DCMAKE_TOOLCHAIN_FILE=${_zt_root}/share/zig-toolchain/${_zt_gnu}.cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${ZIG_LIBS_PREFIX} -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF"
fi
unset _zt_gnu _zt_zig _zt_root _zt_host _zt_flags
