# libs-zig-pixi

Third-party C and C++ libraries rebuilt with `zig cc` / `zig c++` and published as conda packages.

**Status: pre-release.** Nothing is published yet. The first slice targets win-64 and win-arm64 with zlib, sqlite, expat, geos, proj, gdal, abseil, oneTBB and OpenSSL, so that the R packages sf, terra, gdalraster and s2 build from source with [r-zig](https://github.com/luciorq/r-zig-pixi) on Windows.

## Why

On Windows the zig toolchain cannot use conda-forge's libraries (MSVC C++ ABI) or Rtools' x86_64 tree (GCC libstdc++). These packages are built by zig itself, with libc++, as static archives. The repo is platform-general: Windows is only the first slice.

## Packages

- Channel: [`universe`](https://prefix.dev/channels/universe) on prefix.dev. List it before conda-forge.
- Names: `zig-<upstream name>` (`zig-zlib`, `zig-gdal`, ...), so they never shadow conda-forge packages. The cross toolchain is `zig-toolchain`.
- Static archives only (`lib<n>.a`); no DLLs.
- Build strings `zig_<hash>_<build_number>`.

## Layout in an environment

Every package installs into a private sub-prefix that no conda-forge package touches:

```
<envdir>/zig-libs/<zig-triple>/
  include/
  lib/lib<n>.a
  lib/pkgconfig/<n>.pc      # closed and relocatable
  lib/cmake/
  share/{gdal,proj}/
  licenses/<pkg>/
```

`<envdir>` is `$PREFIX/Library` on Windows and `$PREFIX` on unix; the triple is `x86_64-windows-gnu` or `aarch64-windows-gnu`. r-zig finds this directory by itself.

## Building a recipe locally

Requires [pixi](https://pixi.sh) on linux-64. Windows packages are cross-built on linux.

```sh
pixi run build-toolchain          # zig-toolchain (linux-64), needed by every recipe
pixi run build <pkg> <subdir>     # for example: pixi run build zig-zlib win-64
pixi run build-libs <subdir>      # every library recipe, in dependency order (as CI)
pixi run check-alignment          # one build number per package across subdirs
pixi run smoke <modules> <sources> [<subdir>]   # keep smoke executables, e.g. pixi run smoke sqlite3 sqlite.c
```

CI (`.github/workflows/build.yml`) runs the same tasks on linux and tests every package on `windows-latest` and `windows-11-arm`.

The exact task names and arguments are defined in `pixi.toml`. `zig-toolchain` is built first, into the local output channel, and every other recipe uses it. Set `RATTLER_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` to a disk with room; a GDAL build is large.

To build with upstream zig instead of conda-forge's, set `ZIG_BIN` to an upstream `zig` (the `upstream-zig` pixi env provides PyPI `ziglang`). Such builds are for testing and are never uploaded.

## Documentation

- `.github/devdocs/DESIGN.md`: the design and its decisions.
- `.github/devdocs/CONVENTIONS.md`: repo rules.
- `.github/devdocs/<branch>/PLAN.md`: per-branch plan, decisions and findings.

## License

The recipes and tooling are MIT (see `LICENSE`). Each built package carries its upstream library's own licence.
