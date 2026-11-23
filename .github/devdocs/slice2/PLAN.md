# slice2: replace the Rtools45 aarch64 fallback (M6)

Brief written 2026-11-23 at the session split, on top of main 6b249e7
(M5 done: 19 zig-* build 0 on universe). Design: DESIGN.md (6.4, 7
"Retiring R_ZIG_FALLBACK_SOFT", 9.1, 9.2 M6). Interface:
CONTRACT.md. Previous record: m5/PLAN.md (D82-D101, M5-F1..F29).
Decisions here continue at D102; findings are S2-F1 onward.

Tags: **V** verified, **I** inferred, **A** assumption.

## Goal

r-zig-pixi builds R packages on win-arm64 against a CRAN Rtools45
aarch64 static tree (`R_ZIG_FALLBACK_SOFT`) for the libraries no
zig-* package has. Slice 2 makes zig-* packages of them, so r-zig-pixi
can move each stress row off the tree and finally delete
`R_ZIG_FALLBACK_SOFT` (DESIGN.md 7, a `refactor:` in r-zig-pixi).

## What the tree serves today

From r-zig-pixi stress 45219870330 (windows-11-arm, tree and conda),
`stress.R` `rtools_has`, `stress/packages.tsv` (origin/main 8e8bc72):

| Library | Stress rows | Upstream build | Deps | win-64 gains too? |
|---|---|---|---|---|
| gmp | Rmpfr, gmp, igraph | autotools | none | no (conda's works) |
| mpfr | Rmpfr | autotools | gmp | no |
| glpk | igraph (scran) | autotools | gmp | yes: conda's win-64 glpk has no glpk.pc (fail-sysdep) |
| gsl | gsl | autotools | own gslcblas | yes: MKL gslcblas.lib (fail-upstream) |
| nlopt | nloptr, lme4 | cmake | none (C++ inside, C API) | no |
| udunits2 | units (sf, lwgeom) | autotools; cmake on Windows | expat (zig-expat exists) | no |
| hdf5 | hdf5r | cmake | zlib; libaec optional | yes: hdf5r wants the 1_12_0 wrappers, conda has HDF5 2.2 (fail-package) |
| libnetcdf | ncdf4 | cmake | hdf5, zlib, curl | no |
| libpq | RPostgres | meson on Windows | openssl (exists); icu, krb5, ldap to turn off (not checked) | no |
| harfbuzz | textshaping (ragg) | meson | freetype, fribidi | no |

Hidden scope (the same rows also take these from the tree on
win-arm64): freetype, fribidi, libpng, libtiff, libjpeg, libwebp
(textshaping, ragg), libxml2 (igraph), libcurl (ncdf4; conda-forge's
win-arm64 libcurl.pc names a `D:/bld/.../z.lib`). A row leaves the tree
only when all of its libraries are zig-* packages (the r-zig-pixi
stress column shows it per row).

Not in scope: imagemagick (the tree has none; magick downloads its own
aarch64 bundle). protolite (r-zig-pixi D5, 2026-11-23): on win-arm64 it
fails because the tree's protobuf headers win over conda-forge's protoc;
a zig-protobuf on zig-abseil, with its own protoc, would fix it: a
candidate, not in the first batches.

## Open decisions for this session

| # | Question | Options |
|---|---|---|
| D102 | Verifying unpublished builds now that r-zig-pixi consumes only published ones | **A ★** first add DESIGN.md 9.1 item 4, the `r-consumer` job: r-zig-slim from universe plus this run's channels (`pixi exec`), R packages from source, `tests/r/smoke.R` extended per library; B rely on pkgtest only and let r-zig-pixi find breakage after publishing; C a staging channel on prefix.dev |
| D103 | Order | **A ★** leaves first: {gmp, mpfr, glpk}, {nlopt, udunits2}, gsl, libpq, then the text stack {freetype, fribidi, harfbuzz, libpng, libtiff, libjpeg, libwebp}, libxml2, then the data stack {libaec?, hdf5 1.12.x, curl, netcdf} last; B by rows unblocked per library; C data stack first (largest win-64 gain) |
| D104 | Autotools cross builds (gmp, mpfr, glpk, gsl, udunits2): no toolchain path for them yet (slice 1 had cmake and meson only) | **A ★** a toolchain `configure` helper (cache presets, host-tool hygiene as D78/D97) proved on gmp first; B the libraries' cmake ports where they exist; C zig build.zig ports (AYCB) where they exist |
| D105 | GPL redistribution: gsl and glpk are GPL-3, gmp and mpfr LGPL-3+ (the fallback never redistributed them) | **A ★** ship them with licences in `licenses/<pkg>/` as conda-forge does, record it in DESIGN.md; B leave GPL ones on the tree |
| D106 | Release cadence | **A ★** publish per batch (each batch is a PR, a publish and a handover to r-zig-pixi); B one publish at the end |
| D107 | D77 leftovers (`proj.db` shipped twice; json-c prefixing, due when a second json-c arrives) | **A ★** proj.db in the first batch PR with a zig-proj bump; json-c when netcdf or libxml2 brings one; B a separate PR first |

Before the first recipe: re-run the non-AYCB zig port search
(DESIGN.md 6.4, it stopped at a rate limit) and record it here.

## Known risks (from slice 1 and M5)

- Host-tool leaks on the hosted runner (swig D78, pkg-config and bison
  D97); configure scripts probe more host tools than CMake does. The
  build script sees only the fixed system directories on PATH (M5-F27).
- HDF5 under zig hit `_Float16` / `FLT16_MAX` in Rhdf5lib's vendored copy
  (r-zig-pixi packages.tsv); pin 1.12.x as Rtools does.
- harfbuzz/freetype dependency cycle (MXE `build.sh`); libpq's UCRT
  setjmp patch (MXE).
- Every new archive must keep CONTRACT.md 2-3 true (closed `.pc`,
  `lib<n>.a` only, no collisions), and duplicate-symbol checks across the
  closure (pkgtest) get larger.

## Handover to r-zig-pixi (per batch, CONTRACT.md 8)

After each publish: names, subdirs and build strings; contract changes;
then r-zig-pixi adds the packages to its Windows stress env, updates
`packages.tsv` sysdeps and expects (`windows-aarch64=` keys), relocks,
runs stress on both Windows arches, and removes a library from
`rtools_has` once no row resolves into the tree for it.
