# The interface between libs-zig-pixi and its consumers

A record that holds across branches, like CONVENTIONS.md. It states what
libs-zig-pixi (the producer) promises to anyone who installs its zig-*
packages, and what r-zig-pixi (the first consumer, luciorq/r-zig-pixi)
does with them. Each repository changes its own side freely as long as
this file stays true; a change to the file is a contract change (see
"Changing the contract"). Lines cited as of libs-zig-pixi 6b249e7 and
r-zig-pixi 8e8bc72 (2026-11-23); the cited files are the authority when
they differ from this summary.

## 1. Channel and names

- Channel: prefix.dev `universe` (`https://prefix.dev/universe`), public,
  no login for downloads (m5/PLAN.md M5-F25). universe has no base
  relation, so a consumer lists it before conda-forge (DESIGN.md 2).
- Names: `zig-<upstream name>` (CONVENTIONS.md). Built today for win-64
  and win-arm64: zig-zlib, zig-sqlite, zig-expat, zig-openssl,
  zig-abseil, zig-onetbb, zig-geos, zig-proj, zig-gdal; from slice 2
  batch 1 (slice2/PLAN.md) also zig-gmp (with gmpxx), zig-mpfr,
  zig-glpk; from batch 2 zig-nlopt, zig-udunits2; from batch 3 zig-gsl
  (libgsl.a and GSL's own CBLAS, libgslcblas.a); zig-libpq (libpq.a with
  libpgcommon.a and libpgport.a, LDAP and OpenSSL as Rtools45's).
  `zig-toolchain`
  (linux-64) is the build tool, not for consumers.
- Only published builds are part of the contract. A consumer never
  depends on a libs-zig-pixi CI artifact (r-zig-pixi PR #52 removed
  `--libs-channel`).
- After an upload, pixi's sharded index lists a file at once; the plain
  `<subdir>/repodata.json` can lag by some minutes (M5-F29; about 13 in
  r-zig-pixi feat-zig-libs-universe F3).

## 2. What a package installs

- Everything under `<envdir>/zig-libs/<triple>/`; `<envdir>` is
  `$PREFIX/Library` on Windows. Triples: `x86_64-windows-gnu` (win-64),
  `aarch64-windows-gnu` (win-arm64) (CONVENTIONS.md; recipes'
  `sub: Library/zig-libs/${{ zt }}`; toolchain/src/target.zig).
- `include/`; `lib/lib<n>.a` only: every recipe test asserts no `.dll`,
  `.dll.a` or `.lib`; build scripts remove `.exe`, `bin/` and GDAL's
  plugin directory, asserted in zig-gdal (all), zig-proj (`.exe`) and
  zig-openssl (`.exe`, `bin/`); `lib/pkgconfig/*.pc`;
  `lib/cmake/` where upstream installs one (abseil, expat, GEOS, oneTBB;
  not OpenSSL, PROJ, GDAL); `share/proj` (`proj.db`, `proj.ini` and
  PROJ's other resource files) and
  `share/gdal`; `licenses/<pkg>/`.
- No file is shared with a conda-forge package, and no header name
  collides with one zig ships (CONVENTIONS.md, DESIGN.md 5.4).
- PROJ and GDAL embed their resource files, so they work without
  `PROJ_DATA` or `GDAL_DATA`; `share/` is for consumers that copy it
  (r-zig-pixi's `R_TOOLS_SOFT`, section 6).
- No install prefix is compiled into the archives.
- `libglpk.a` defines `DllMain` (GLPK's Windows code, as CRAN's Rtools45
  archive; slice2/PLAN.md S2-F12, D110): a DLL that links zig-glpk gets
  GLPK's `DllMain` as its entry point, and one that defines its own gets
  a duplicate-symbol error. No other zig-* archive defines `DllMain`.
- `.pc` files the upstream build does not install are written by the
  recipe (zig-glpk's `glpk.pc`, zig-udunits2's `udunits2.pc`; upstream
  has neither).
- zig-udunits2 ships its XML database in `share/udunits/`; the library's
  default path is the relative `share\udunits\udunits2.xml` (no prefix);
  consumers pass a path or set `UDUNITS2_XML_PATH` (R's units ships its
  own copy).

## 3. pkg-config files

Written by `zig-toolchain close-pc` (toolchain/src/closepc.zig):

- Relocatable: `prefix=${pcfiledir}/../..`, no absolute path.
- Closed: `Libs.private`, `Cflags.private` and `Requires.private` are
  merged into the public fields, so a consumer never passes `--static`.
  The Windows system libraries an archive needs are in `Libs` (from
  upstream's `.pc`, from the recipe, or appended by `close-pc --libs`).
- One C++ runtime name: `-lc++` (never `-lstdc++`).
- `Requires:` names only zig-libs modules; static defines such as
  `-DXML_STATIC` are in `Cflags`. abseil has one `absl_<component>.pc`
  per module.

## 4. ABI and toolchain

- MinGW-w64 targets (`*-windows-gnu`), zig's clang and libc++
  (`std::__1`); never MSVC, never libstdc++. A consumer that links them
  compiles its own C++ with libc++ (r-zig-pixi does on Windows,
  CXX-STDLIB.md there).
- `-mcpu=baseline`, no `-march=native` (toolchain/src/flags.zig); no
  dllexport directive, checked by pkgtest `--no-dllexport` for the C++
  packages (abseil, onetbb, geos, proj, gdal).
- Built and published with conda-forge zig (exact pin in variants.yaml);
  every recipe also builds with upstream ziglang in the gated
  `upstream-zig` leg, which never publishes.

## 5. Versions, run_exports, build numbers

- Upstream versions live only in variants.yaml.
- Every library has `run_exports: weak: pin_subpackage(<name>,
  upper_bound="x.x")`; host dependencies are zig-* packages only.
- Build string `zig_<hash>_<number>`. The hash covers the variant keys
  that recipe uses (zig, zig_toolchain, its version key, the build tools
  it pins) and the target platform, not the recipe text or build.sh. A
  consumer may pin `zig_*` or a build number.
- A package's build number is bumped on any change to its recipe, the
  zig pin or a dependency's version; one number per package across
  subdirs (CONVENTIONS.md; R15). The publish job fails when a published
  file's `info/recipe` files or test files differ from the new build
  without a bump (m5/PLAN.md D96); a `toolchain/` change is caught by the
  `zig_toolchain` bump instead (D100).

## 6. What r-zig-pixi does with them (consumer side)

Owned by r-zig-pixi; listed so the producer knows what a change can
break. Windows only; unix never looks for zig-libs.

The first r-zig build that carries this section is 12, published on
universe 2026-11-24 (4.6.2; win-64 r-zig-slim `hb04b5bb_12`, win-arm64
`he73fba8_12`; r-zig-pixi release run 45381914199). Build 11 predates it
and never looks in zig-libs (slice2/PLAN.md S2-F13). Consumers pin
`r-zig-slim = { version = "4.6.2", build = "*_12" }` or later, with
universe listed before conda-forge.

- rzig (`zigbuild/tools/rzig/environment.zig`), environment order: R's
  own env's `zig-libs/<triple>` (when it exists), R's env, the
  toolchain's `openmp/` (when R's env has libomp), `R_ZIG_EXTRA_ENV`'s
  zig-libs and that env, and the Rtools45 fallback tree
  (`R_ZIG_FALLBACK_SOFT`, win-arm64 only) last. Headers as
  `-idirafter <dir>/include`, libraries as `-L<dir>/lib`, after the
  package's own arguments. Per `-L` directory in command-line order (the
  package's own first, then the environments'), rzig names
  `lib<n>.dll.a` or `lib<n>.lib` itself and leaves `<n>.dll`, `<n>.lib`
  and `lib<n>.a` to zig's search (windows.zig). So `-lz`, `-lssl`,
  `-lexpat`, `-lsqlite3` bind zig-libs' archives for every package of
  that env that does not bring its own copy. zig-libs never provides
  OpenMP.
- R's `etc/Rcmd_environ` (r-zig-pixi build.zig `rcmdEnviron`):
  `R_ZIG_LIBS=${R_HOME}/../../zig-libs/<triple>`; its `lib/pkgconfig`
  first on `PKG_CONFIG_PATH`, and in the default `PKG_CONFIG_LIBDIR`;
  `R_TOOLS_SOFT` defaults to it (sf, terra, gdalraster copy
  `$(R_TOOLS_SOFT)/share/gdal` and `share/proj`).
- `etc/r-zig.cmake`: zig-libs on `CMAKE_PREFIX_PATH`, before the
  prefixes PATH gives.
- The stress suite (`stress/`): the Windows stress env lists zig-abseil,
  zig-gdal, zig-geos, zig-onetbb, zig-openssl, zig-proj (`*`);
  `packages.tsv` rows name them as `zig-<lib>@windows` sysdeps (s2,
  lwgeom, sf, terra, gdalraster); the report's zig-libs column shows each
  zig-* sysdep's installed version and build (conda-meta), then the `-l`
  names that resolved into zig-libs and into the fallback tree (rzig
  trace).

Producer obligations that follow: the `.pc` module names and `-l` names
stay the upstream ones; `share/gdal` and `share/proj` stay; every archive
a `.pc` names is in `lib/`.

## 7. Testing responsibilities

- libs-zig-pixi verifies a build before it is published: recipe tests
  and `tests/pkgtest.zig` on linux and on Windows of both arches, and
  (from slice 2 on, DESIGN.md 9.1 item 4) R packages built from source
  against the new packages with r-zig from universe: the `r-consumer`
  job (build.yml; slice2/PLAN.md D113), `tests/r/install.R` then
  `tests/r/smoke.R` (sf, terra, gdalraster, s2, gmp, Rmpfr, igraph,
  nloptr, units, gsl, RPostgres, on both arches; RPostgres' queries
  against a throwaway PostgreSQL server on win-64), with r-zig-slim and r-zig-toolchain
  pinned to build 12 (D116). The publish job needs it, and it fails the
  run.
- r-zig-pixi verifies the published builds in its stress suite after it
  updates its lock, and reports anything that breaks this contract to
  libs-zig-pixi.

## 8. Changing the contract

1. The producer records the change and its reason in its branch
   PLAN.md, updates this file in the same PR, and bumps build numbers as
   section 5 requires.
2. After the publish, the branch PLAN.md's last section is a handover:
   package names, subdirs, build strings, contract changes, and what the
   consumer has to do (pixi.toml, lock, `packages.tsv`, rzig).
3. The consumer updates its side, runs its stress suite, and records the
   result in its own PLAN.md.
