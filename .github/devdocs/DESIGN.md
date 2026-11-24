# libs-zig-pixi: design and first slice

Date: 2026-11-20. **Status: accepted 2026-11-20** (the user: "Yes, continue with recommended", which accepts every ★ option of the draft's menus; see section 10). Milestone M0 is in progress on branch `m0` (`.github/devdocs/m0/PLAN.md`).

**Sources.** The research reports are cited by area name: **[infra]**, **[mxe]**, **[cross]**, **[consumer]**, **[zigports]** and **[review]** (the adversarial review of the draft). Their scratch evidence is under `/data/gamma/luciorq/workspaces/temp/r-zig-pixi/next/libs-design/` (`precedent-infra/`, `mxe-blueprint/`, `rattler-cross/`, `consumer/`, `zig-ports/`, `review/`, plus `CRITIQUE.md`). The Rtools x86_64 probe is `/data/gamma/luciorq/workspaces/temp/r-zig-pixi/next/probe-rtools-x64/FINDINGS.md` (X1-X6). r-zig-pixi line numbers refer to origin/main f951022.

**Tags.** **V** verified (by a report, the review, or while writing this). **I** inferred. **A** an assumption the slice must test.

**Where the R packages stand today.** r-zig-pixi `stress/packages.tsv` (origin/main) gives these Windows expectations (V). The most specific key wins, so `windows=` covers win-arm64 too when no `windows-aarch64=` key exists (`stress/stress.R:757-762`, V):

| package | win-64 | win-arm64 |
|---|---|---|
| sf | `fail-dependency` | `fail-dependency` (from `windows=`; it waits on s2) |
| terra | `fail-sysdep` | `ok` (Rtools aarch64 tree via `R_ZIG_FALLBACK_SOFT`) |
| gdalraster | `fail-abi` | `ok` (same fallback) |
| s2 | `fail-abi` | `fail-abi` (from `windows=`; absl_* not found, stress 44450918935) |

So slice 1 fixes all four packages on win-64 and sf and s2 on win-arm64, and it moves terra and gdalraster off the fallback tree on win-arm64.

---

## 1. Goal and scope

**Goal.** A repo, `libs-zig-pixi`, that rebuilds third-party C and C++ libraries with `zig cc` / `zig c++` and publishes them as conda packages named `zig-<upstream>` on the prefix.dev `universe` channel.

- Platform-general: any library worth rebuilding, any platform. Windows is the first slice.
- On Windows it replaces what the zig toolchain cannot use:
  - conda-forge's MSVC-ABI C++ libraries [infra §5];
  - Rtools45's x86_64 GCC 14.3 / libstdc++ tree, since r-zig uses libc++ on Windows (CXX-STDLIB decision 1) [consumer §2]. The probe shows the C API of its C++ libraries links only with GCC's `libstdc++.a` by path, and GDAL's C++ API needs the whole GCC C++ stack (X4-X6, V);
  - the Rtools aarch64 LLVM tree, reached today through `R_ZIG_FALLBACK_SOFT` [consumer §2].

**First slice.**
- **Libraries:** zlib, sqlite, expat, geos, proj, gdal (a minimal GDAL stack), abseil, plus oneTBB (terra links `-ltbb12`) and OpenSSL (s2) (D13).
- **Targets:** win-64 and win-arm64.
- **Done when:** sf, terra, gdalraster and s2 install from source and pass a smoke test natively on `windows-latest` and `windows-11-arm`, with archives built by conda-forge zig and in the gated leg rebuilt with upstream zig (D11).

**Out of slice 1:** linux/macOS builds (D5); GDAL network drivers, netCDF, HDF5, Arrow/Parquet, PDF and most of CRAN's ~60-library GDAL closure (D6, section 6.3).

**Relation to r-zig-pixi's CXX-STDLIB record.** r-zig-pixi `.github/devdocs/CXX-STDLIB.md` (origin/main, ~:150-158) lists "Rebuild the C++ libraries with zig and libc++" under *Ruled out* (upkeep per upstream release, "4-6 days to set up", "GDAL loses drivers") [review M3] V. That entry stays right **for linux**, where libstdc++ for all C++ is the chosen path (feat-linux-libstdcxx). **For Windows it is chosen, 2026-11-20**, because there is no usable alternative: conda-forge's libraries are MSVC C++ and Rtools' x86_64 tree is GCC/libstdc++ (X5). The upkeep cost is handled by section 8 (Maintenance). The consumer branch in r-zig-pixi updates CXX-STDLIB.md's entry to say this. The earlier evidence there (a native linux shared build of abseil and GDAL 3.13.2 in about 2 and 5 minutes) does not measure a static Windows cross build, so every CI time estimate here is **A**.

---

## 2. Standing decisions

| # | Decision |
|---|---|
| U1 | Repo `libs-zig-pixi`, separate from r-zig-pixi, which becomes a consumer (section 7). |
| U2 | Names `zig-<upstream>`: `zig-zlib`, `zig-sqlite`, `zig-expat`, `zig-geos`, `zig-proj`, `zig-gdal`, `zig-abseil`, `zig-onetbb`, `zig-openssl`; the toolchain is `zig-toolchain`. The prefix avoids shadowing conda-forge names on universe (as r-zig-packages' `rz-`) [infra §5]. Upstream names win over conda-forge splits (`zig-gdal`, not `zig-libgdal-core`). |
| U3 | Publish to `universe`. Consumers list universe before conda-forge; it has no base relation [infra §5]. |
| U4 | rattler-build plus zig around each library's own build system (D1). |
| U5 | No MXE, no MSYS2, no wine. Windows binaries are cross-built on linux and executed only on real Windows runners. |
| U6 | Platform-general. |

The repo rules (git, commit types, decision records, both zigs, build numbers, static-only, `.pc`, publish preflight) are in `.github/devdocs/CONVENTIONS.md` (D18).

---

## 3. Repo layout

```
libs-zig-pixi/
  pixi.toml  pixi.lock     # envs (below) and tasks; task names are defined there
  variants.yaml            # global pins: zig, triples, every zig-* version
  recipes/
    zig-toolchain/         # built first, linux-64 (later osx-*)
    zig-zlib/  recipe.yaml build.sh patches/
    zig-sqlite/ ... zig-gdal/ zig-abseil/ zig-onetbb/ zig-openssl/
  toolchain/               # zig-toolchain sources: one Zig multi-call program
    build.zig build.zig.zon src/*.zig
    cmake/zig-cross.cmake.in  meson/cross.ini.in
  zigbuild/                # build.zig ports, only where a build system cannot cross (empty in slice 1)
  tests/pkgtest.zig        # the package test every library recipe runs (linux and Windows, m0 D31)
  tests/smoke/             # C/C++ smoke sources per library
  tests/r/                 # sf/terra/gdalraster/s2 smoke scripts
  .github/
    actions/which-zig/action.yml  # which zig each build ran (m0 D41); the build steps are pixi tasks, so no stage action (m0 D35)
    workflows/build.yml
    devdocs/DESIGN.md  devdocs/CONVENTIONS.md  devdocs/<branch>/PLAN.md
  README.md  LICENSE      # MIT (D19)
```

No Python and no `scripts/` directory: build-number alignment and `.pc` closing are subcommands of the `zig-toolchain` program (D17).

**pixi environments** (kept small; `/` has little space, big scratch goes to `/data/gamma/luciorq/workspaces/temp/r-zig-pixi/libs-m0/` locally with `RATTLER_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` under it):
- `default`: `rattler-build`, `zig ==0.17.1` (conda-forge), `cmake`, `ninja`, `perl` (OpenSSL Configure), `sqlite` (host `sqlite3` for `proj.db`), `pkgconf`, `llvm-tools` (`llvm-nm`, build/test only; zig has no `nm`).
- `upstream-zig`: adds PyPI `ziglang ==0.17.1`; it only supplies the `ZIG_BIN` path for the gated leg (D11).
- No locked Windows test env. Windows tests use `rattler-build test --package-file` and `pixi exec -c file://… -c conda-forge`, so CI never writes a lock against a `file://` channel [review M7].

**Building.** `rattler-build build --recipe recipes/<pkg> --target-platform <subdir> -m variants.yaml -c file://$OUT -c conda-forge --test skip`. No pixi-build backend: it cannot express a split build/target platform [infra §2]. Recipes are v1 (`recipe.yaml`) without v3-only features [infra §4].

---

## 4. Toolchain

### 4.1 Zig and its pin (D4, D11)
- Recipes take plain conda-forge `zig ==0.17.1` in `requirements.build` through `variants.yaml`, not `${{ compiler('zig') }}`: no linux-64-hosted `zig_win-*` wrapper exists, and the wrapper drops `-march`, `-stdlib`, `-fstack-protector` and defaults Windows to `-windows-msvc` [infra §1, §2, §5] V.
- **A zig bump rebuilds every package and bumps every build number.** `zig-toolchain` pins zig exactly again.
- Ports need differing zig versions (AYCB zlib `main` needs 0.18.0-dev.469; AYCB sqlite3 fails on 0.17) [zigports §3] V, another reason the default path does not depend on them (D1).

### 4.2 Both zigs (D11)
- **Published packages are built with conda-forge zig 0.17.1**, like r-zig's own packages. One artifact and one build number per subdir.
- **Upstream zig is the reference.** PyPI `ziglang 0.17.1` is byte-identical to the ziglang.org build (both-zigs record, 2026-10-04) V. A failure under upstream zig is fixed in the design; a conda-forge quirk gets only a small, isolated, removable workaround inside `zig-toolchain` (for example `ignore_run_exports` for the libstdcxx/libgcc run-exports of conda-forge zig ≥0.17.0 build 6 on Windows [infra §5] V).
- **Mechanism.** rattler-build build envs come from conda channels only, so PyPI ziglang cannot be a build requirement [review H1] (I). Instead the `zig-toolchain` program honours `ZIG_BIN`, as rzig does (`zigbuild/tools/rzig/check.zig:528ff`) [review H1] V, and every recipe passes it through:
  ```yaml
  build:
    script:
      env:
        ZIG_BIN: ${{ env.get("ZIG_BIN", default="") }}
  ```
  Empty means the build env's conda zig. **Whether `env.get` reaches the script this way is A, to verify in M0.**
- **Gated leg** (`full-ci` label or dispatch, as r-zig-pixi's CI tiers): set `ZIG_BIN` to the `upstream-zig` env's zig, rebuild the packages into a separate output dir, run the same Windows package tests, and link the R packages against them. These artifacts carry the same build string and are **never uploaded**.
- **Risk:** libc++ ABI drift between archives built by one zig and linked by the other. zig builds libc++ from source per link, so archives see the headers of the zig that compiled them (I). The gated leg tests it (R3).

### 4.3 Cross toolchain: package `zig-toolchain` (D8)
The cross probe built zlib for win-64 and win-arm64 under rattler-build 0.80.1 with zig 0.17.1, using triple-named wrappers plus a CMake toolchain file [cross §1, §2, §4] V (`rattler-cross/probe2/out/win-64/zig-zlib-probe-1.3.1-h9490d1a_0.conda`, `.../win-arm64/zig-zlib-probe-1.3.1-h5667933_0.conda`).

**Form.** One Zig multi-call program (simplicity-first, prefer-Zig). argv[0] selects the role and the target:

| Name | Runs |
|---|---|
| `<triple>-cc`, `<triple>-c++` | `zig cc` / `zig c++ -target <arch>-windows-gnu` plus the default flags (4.4) |
| `<triple>-ar`, `-ranlib` | `zig ar`, `zig ranlib` |
| `<triple>-dlltool` | `zig dlltool -m …` |
| `<triple>-windres`, `-rc` | `zig rc /:auto-includes gnu /:target <arch> /:output-format coff`, with GNU→rc flag translation (CMake and zlib pass GNU flags) [cross §2] V |
| `<triple>-strip` | no-op, exit 0; `zig objcopy` rejects PE/COFF (`InvalidElfMagic`, m0 PLAN M0-F7, D23) |
| `<triple>-{nm,objdump,objcopy,readelf,addr2line,ld}` | exit 1 "not available … add llvm-tools"; set in the CMake toolchain files so host ELF binutils are never found (M0-F7) |
| `zig-toolchain close-pc`, `check-alignment` | tooling subcommands (5.4, 5.2) |

Triples: `x86_64-w64-mingw32`, `aarch64-w64-mingw32`. The zig executable is `ZIG_BIN` when set, else `zig` from the build env.

**Code reused, copied with a source note** (no dependency on r-zig-pixi):
- r-zig-pixi `zigbuild/tools/rzig/binutils.zig` and `target.zig`: the windres→`zig rc` and dlltool translation. rzig fixes the target to the host; here it comes from argv[0] (I).
- blast `recipe/build.sh:122-347` [infra §3] V: the `-march` rewrite (generalised, 4.4), `ZIG_GLOBAL_CACHE_DIR`/`ZIG_LOCAL_CACHE_DIR` under `SRC_DIR`, a hermetic PATH. Dropped: the emulation watchdog, the `x86_64-w64-mingw32-zig` lookup, the wcstold shim (fixed in zig 0.17).

**CMake toolchain file** `share/zig-toolchain/<triple>.cmake` (as the probe's `tc/x86_64-windows.cmake`) [cross §2] V:
- `CMAKE_SYSTEM_NAME Windows`; `CMAKE_SYSTEM_PROCESSOR AMD64|ARM64`; wrappers as C, CXX, AR, RANLIB, RC.
- `CMAKE_FIND_ROOT_PATH` = **only** `<envdir>/zig-libs/<triple>`, so nothing under `$PREFIX/Library` can win over the sub-prefix [review L3].
- Root-path mode ONLY for libraries, includes and packages; NEVER for programs (the build-env `sqlite3` and `perl` must be found).
- `CMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF` (rzig drops `-flto` on Windows links) [review M2].
- Preset cache entries for any `try_run` as they appear (no emulator), each recorded in PLAN.md (I).
- CMake identifies the compiler as Clang and still sets `MINGW` [cross §2] V.

**Meson cross file** `<triple>.ini`: generated, untested (A); no slice-1 recipe uses meson.
**Autotools:** `--host=<triple>` finds `<triple>-cc` etc. by name (A); `CC_FOR_BUILD=zig cc`.
**Activation script:** sets `CC`, `CXX`, `AR`, `RANLIB`, `RC`, `CMAKE_ARGS` (toolchain file, `-G Ninja`, `CMAKE_BUILD_TYPE=Release`, install prefix) and `ZIG_LIBS_PREFIX`. rattler-build sets none of these itself [cross §1] V.
**Scripts:** on a linux build machine rattler-build runs `build.sh` even for win-* targets [cross §1] V, so each recipe has one bash `build.sh`.
**Future osx-64 host:** the toolchain must not let `zig ar` create archives there (known osx-64 failure, r-zig gotchas) [review L11]; use the platform `ar` or `llvm-ar` on that host.

### 4.4 Flags every archive is compiled with
The wrappers add these defaults, so the archives match what rzig links [review M2, L2, L4]:

| Flag | Why |
|---|---|
| `-mcpu=baseline` | never `native`, also if a recipe ever builds on a Windows runner (fix-rzig-baseline-cpu lesson) |
| `-g0` | small archives |
| `-ffunction-sections -fdata-sections` | lets the consumer link drop unused code |
| `-fno-sanitize=undefined` | as rzig (`compiler.zig:31`) |
| `-Wno-date-time` | as blast and rzig |
| `-ffile-prefix-map=$SRC_DIR=.` | no build paths from `__FILE__` in the archives |

**`-march` rewrite, generalised.** blast rewrites only `-march=armv8-a+crc`. Any `-march=<arch>+<f1>+<f2>…` becomes `-mcpu=generic+<f1>+<f2>…` (blast's verified spelling; the interaction with the default `-mcpu=baseline` is A). abseil matches `"arm.*|aarch64"` case-sensitively (`AbseilConfigureCopts.cmake:61`), so `CMAKE_SYSTEM_PROCESSOR ARM64` adds no `-march=armv8-a+crypto` and randen uses its portable path [review L2] V. Keep the `ARM64` spelling; the rewrite covers the other case.

### 4.5 Binutils
No GNU binutils: `zig ar`, `ranlib`, `dlltool`, `rc`. `zig objcopy` does not handle PE/COFF (m0 PLAN M0-F7), so `-strip` is a no-op. zig has no `nm`, so symbol checks use `llvm-nm` from `llvm-tools` in the build/test env only, never in run requirements (D17). The zigports report already used `llvm-nm` on zig-built Windows archives [zigports §3] V.

---

## 5. Package conventions

### 5.1 Versions and build strings
Upstream version; build string `zig_${{ hash }}_${{ build_number }}` as flang-rt-zig [infra §3]. Consumers can pin `zig_*` or `*_N`.

### 5.2 Build numbers
- Bump on any change to the recipe, the zig pin or a dependency version. rattler-build hashes spec strings, not resolved packages, so `--skip-existing` silently keeps stale builds [infra §5] V (r-zig's build 1→2 episode).
- One build number per package across all subdirs, checked by `zig-toolchain check-alignment` (D17).

### 5.3 Static only (D3)
Ship `lib<n>.a` only: no DLL, no `lib<n>.dll.a`, never `<n>.lib`.
- zig 0.17.1's `-l` looks for `<n>.dll`, `<n>.lib`, `lib<n>.a`, never `.dll.a`; any `<n>.lib` wins even with `-static` [cross §3] V.
- CMake's MinGW search prefers `.dll.a` over `.a` [cross §3] (I).
- Rtools is static-only and the R packages assume it [mxe §A] [consumer §1].
- No libc++ object crosses a DLL boundary; no PATH or rpath at run time (I).
- Upstream names vary: zlib 1.3.1 installs `libzlibstatic.a` while its `.pc` says `-lz` (`rattler-cross/inst-aarch64.log`) V; zig's own build.zig names Windows static libs `<n>.lib` [zigports §3] V. Every recipe normalises to `lib<n>.a`; the recipe test asserts no `*.lib`, `*.dll`, `*.dll.a`.

### 5.4 Install layout (D2)
```
<envdir>/zig-libs/<zig-triple>/{include, lib/*.a, lib/pkgconfig/*.pc, lib/cmake/*, share/gdal, share/proj, licenses/<pkg>/}
```
`<envdir>` is `$PREFIX/Library` on Windows and `$PREFIX` on unix (rzig's `Env.dir`).
- `lib/cmake/*` only where the upstream config is relocatable and links with zig: slice 1 ships absl, expat, GEOS and TBB, and removes OpenSSL's (static deps not closed), PROJ's and GDAL's (`shell32.lib`/`ole32.lib` spellings the zig MinGW link cannot find); the `.pc` is the interface (slice1 PLAN D51, D67, S1-F15) V. The triple is `x86_64-windows-gnu` or `aarch64-windows-gnu`.
- No file in common with any conda-forge package, so zig-* packages coexist with `libgdal-core` and friends [consumer §3]. Installing at conda-forge's paths would overwrite `Library/include/{gdal,ogr,cpl,proj,geos,absl,tbb}*`, conflict on zlib/sqlite (r-zig-slim needs `zlib`) and abseil/libprotobuf, and block conda-forge GDAL on linux/macOS.
- Both arches can sit side by side; noarch "sysroot-like" packages for linking from linux become possible later (I).
- No header name zig itself ships (no MinGW sysroot headers, no `c++/`, no `omp.h`; W15 rule) [consumer §3].

### 5.5 `.pc` rules
Written by `zig-toolchain close-pc` after install [consumer §1, §3]:
1. **Closed.** The full static closure is in `Libs:`. r-zig's pkgconf prints `Libs.private` only with `--static`, which the R packages never pass [consumer §1] V. Windows system libs are included (`-lws2_32 -lbcrypt -lcrypt32 -ldbghelp …`), limited to MinGW import libs both zigs ship (A; R10).
2. **Relocatable.** `prefix=${pcfiledir}/../..`, no absolute path, so placeholder slash rewriting on Windows does not matter (R1).
3. `Requires:` only names zig-libs modules.
4. **Cflags carry static defines** where a header would otherwise emit `__imp_` references (`-DCURL_STATICLIB` when curl arrives; oneTBB's export header checked in M2) [review L5]. lld in MinGW mode tolerates locally defined imports (I).
5. **Abseil:** abseil's own CMake writes one `absl_<component>.pc` per module with `Version:` = LTS date; close-pc closes in `dbghelp` etc. [mxe §B] [infra §6]. No post-step for `-Wnon-virtual-dtor`: abseil 20250127's `.pc` Cflags never contain it (only `-Wno-*`, `-D`, `-I`), and the package test forbids it (slice1 PLAN D54) V.

### 5.6 Data (D16, default)
- `share/proj/proj.db` and `share/gdal/*` from the same build, because sf, terra and gdalraster copy `$(R_TOOLS_SOFT)/share/{gdal,proj}` into the installed package [consumer §1] V.
- `EMBED_RESOURCE_FILES`: PROJ keeps its own default (ON for static builds, `CMakeLists.txt:392-396`, 9.7.1) [review M8] V; GDAL sets it ON. The duplication (~10+ MB per DLL, I) is accepted so the packages behave as on CRAN.

### 5.7 Build paths and prefix detection
`-ffile-prefix-map` removes source paths. Install paths are kept out of the archives at the source, not handled by prefix detection: PROJ with `EMBED_PROJ_DATA_PATH=OFF`, GDAL with a recipe patch removing `INST_DATA`, `SYSCONFDIR`, `INSTALL_PLUGIN_FULL_DIR` and `GDAL_PREFIX`, OpenSSL configured for the neutral prefix `/zig-libs/<triple>` with `-DOSSL_WINCTX` (slice1 PLAN D50, D57, D59). No slice-1 package has a `prefix_placeholder` entry, so no recipe uses `build.prefix_detection.ignore`, and pkgtest refuses any archive holding a build path (slice1 PLAN S1-F9) V. Data come from `PROJ_DATA`/`GDAL_DATA` (R packages set them to their copied `share/`) or the embedded resources.

### 5.8 Licences
- `about.license` (SPDX) and `about.license_file` per recipe; a copy under `zig-libs/<triple>/licenses/<pkg>/`, since the archives end up inside R package DLLs.
- **Inventory** (licence IDs I, checked per recipe in M1-M3) [review L6]:

| Package | Licence | Bundled code needing its own notice |
|---|---|---|
| zig-zlib | Zlib | |
| zig-sqlite | blessing (public domain) | |
| zig-expat | MIT | |
| zig-geos | **LGPL-2.1-or-later** | static linking into a redistributed binary carries the relink obligation (matters for r-zig-packages binaries, Phase 3) |
| zig-proj | MIT | |
| zig-gdal | MIT | internal libtiff (libtiff), libgeotiff, libjpeg (**IJG notice**), libpng, giflib, json-c, LERC (Apache-2.0), **qhull** (own licence), shapelib |
| zig-abseil | Apache-2.0 | |
| zig-onetbb | Apache-2.0 | |
| zig-openssl | Apache-2.0 | |
| zig-gmp (slice 2) | **LGPL-3.0-or-later OR GPL-2.0-or-later** | relink obligation as GEOS |
| zig-mpfr (slice 2) | **LGPL-3.0-or-later** | relink obligation as GEOS |
| zig-nlopt (slice 2) | **LGPL-2.1-or-later AND MIT** | luksan (LGPL-2.1-or-later) in NLopt's COPYING; relink obligation as GEOS |
| zig-udunits2 (slice 2) | UCAR | |
| zig-glpk (slice 2) | **GPL-3.0-or-later** | internal zlib (Zlib), AMD and COLAMD (SuiteSparse, LGPL-2.1-or-later), MiniSat (MIT); their READMEs/LICENSE in `licenses/glpk/` |

  Slice 2 (slice2 PLAN.md D105, user 2026-11-23): the GPL and LGPL
  libraries the Rtools45 tree served without redistributing them (gsl and
  glpk GPL-3.0-or-later; gmp, mpfr LGPL-3.0-or-later) are shipped like any
  other zig-* package, with their licence files in `licenses/<pkg>/`, as
  conda-forge ships them. A static archive inside an R package DLL makes
  that DLL a combined work: the R packages that link gsl or glpk (gsl,
  igraph) are GPL themselves; for binary redistribution (Phase 3) the
  LGPL relink obligation applies as for GEOS. Rows are added per recipe.

  `about` links the recipe repo, which holds the exact source URLs, hashes and patches.

### 5.9 run_exports and dependencies
- `run_exports: weak: pin_subpackage(<name>, upper_bound="x.x")` (exact x.x for proj, geos, gdal, abseil). A host dependency becomes a run dependency: `zig-gdal` runs with `zig-proj 9.7.*`, `zig-geos 3.14.*`, `zig-sqlite`, `zig-expat`, `zig-zlib`.
- `ignore_run_exports`: `libstdcxx`, `libgcc`, `vc`, `vc14_runtime`, `ucrt`, `vs2022_runtime` (conda-forge zig quirk, 4.2).
- Host requirements contain only zig-* packages, never conda-forge Windows libraries [cross §1] V.

### 5.10 Tests per recipe
- **linux, after the build:** `package_contents.files` globs for `zig-libs/<triple>/lib/lib<n>.a`, headers, `.pc` (not `package_contents.lib`, which checks MSVC names [cross §1] V); absence of `*.lib`, `*.dll`, `*.dll.a`; `pkgconf --libs <n>` with `PKG_CONFIG_LIBDIR` set; for C++ packages `llvm-nm` shows `std::__1` (libc++), not `__cxx11`.
- **Windows runners:** `rattler-build test --package-file …`. M0 and M1 link plain smoke executables; **from M2 every smoke test links as R packages do**: a DLL built with `R CMD SHLIB` from `r-zig-slim`, loaded with `dyn.load()` and called with `.Call` (D20). R package links go through rzig, which adds `-mcpu=baseline -fno-sanitize=undefined -Wno-error=date-time`, `/OPT:NOICF` via `_LINK_` (finding 35, "invalid symbol index in addrsig section"), the `cfguard.o` stub and R's `tmp.def`; an executable link tests none of that [review M2] V.

| Library | Smoke |
|---|---|
| zlib | compress / uncompress |
| sqlite | RTREE table; `PRAGMA compile_options` equals the list kept in the recipe |
| expat | parse a small document |
| openssl | SHA-256 |
| proj | 4326→3857 with `proj.db` and with no `PROJ_DATA` (embedded) |
| geos | buffer |
| abseil | `absl::StrCat` |
| onetbb | `parallel_for` on more than one thread |
| gdal | in-memory GPKG plus GTiff, GeoJSON, Shapefile |

---

## 6. First slice

Versions are Rtools45 build 6768 [mxe §B] (D9). Build order follows the dependency graph [mxe §D]. Every recipe uses the section 4 toolchain and its own build system (D1); zig ports are references or fallbacks only.

### 6.1 Recipes

| # | Package | Version | Build system | Key options | Patches | Zig port; reused? |
|---|---|---|---|---|---|---|
| 0 | zig-toolchain | 0.1.0 | build.zig (own code) | | | |
| 1 | zig-zlib | 1.3.1 | CMake (cross verified, both arches [cross §4] V) | `-DBUILD_SHARED_LIBS=OFF`; `.pc` into the sub-prefix; `libzlibstatic.a`→`libz.a` | none | AYCB/zlib: fallback only; `main` needs zig 0.18-dev and names output `z.lib` [zigports §3] V |
| 2 | zig-sqlite | 3.51.2 (3510200) | amalgamation compiled directly (`$CC -c`, `$AR rcs`) plus a written `sqlite3.pc` | the Rtools option set (6.2) | none | AYCB/sqlite3 fails on zig 0.17; CIC/sqlite has no RTREE [zigports §2-3] V |
| 3 | zig-expat | 2.7.3 | CMake | static; `EXPAT_BUILD_TOOLS/EXAMPLES/TESTS=OFF` | none expected (A) | AYCB/libexpat 2.9.0: reference (x86_64 Windows CI only) [zigports §2] |
| 4 | zig-geos | 3.14.1 | CMake (C++) | `-DBUILD_SHARED_LIBS=OFF -DBUILD_GEOSOP=OFF -DBUILD_TESTING=OFF` | none; our closed `geos.pc` replaces CRAN's `geos-config` patch | none usable (stale) |
| 5 | zig-proj | 9.7.1 | CMake | `-DBUILD_SHARED_LIBS=OFF -DENABLE_TIFF=OFF -DENABLE_CURL=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF`; build-env `sqlite3` as `EXE_SQLITE3` | none expected | CIC/proj 9.9.0: not reused (exports 286 `sqlite3_*` symbols from a private SQLite, one maintainer, not rechecked on 0.17) [zigports §3] V; its `proj-db-gen` is a reference |
| 6 | zig-gdal | 3.12.1 | CMake (C++) | 6.3 | `0001-no-install-paths-compiled-in.patch` (slice1 PLAN D59) V; CRAN's `gdal-1..3` concern apps, 3.12.0 or poppler [mxe §B] V | none exists [mxe §E] |
| 7 | zig-abseil | 20250127.0 | CMake | `-DCMAKE_CXX_STANDARD=17 -DABSL_PROPAGATE_CXX_STD=ON -DBUILD_SHARED_LIBS=OFF -DABSL_BUILD_TESTING=OFF`; `.pc` post-step | `0001-cctz-mingw-without-windows-globalization-h.patch` (zig's MinGW headers lack `windows.globalization.h`, slice1 PLAN D53, S1-F13) V; `ABSL_FORCE_WAITER_MODE` not set | AYCB/abseil 20260526.0: fallback (builds both arches in 37 s, but one `abseil.lib`, no `absl_*.pc`; s2 needs 25 `absl_*` modules) [zigports §3] [consumer §1] V |
| 8 | zig-onetbb | 2022.2.0 | CMake | `-DTBB_TEST=OFF -DTBB_STRICT=OFF -DBUILD_SHARED_LIBS=OFF`; archive named `libtbb12.a` (terra hard-codes `-ltbb12`) | CRAN's `intel-tbb-1-msys2-fixes.patch` [mxe §B]; `0002-static-build-exports-nothing.patch` (no `-export:` in the static archive, slice1 PLAN D68, S1-F5) V | RichieSams/zig-oneTBB: reference |
| 9 | zig-openssl | 3.6.0 | Perl `Configure mingw64` / `mingwarm64` | `--prefix=/zig-libs/<triple> --openssldir=/zig-libs/<triple>/ssl` installed with `DESTDIR=$PREFIX/Library`, `-DOSSL_WINCTX=zig_libs` (slice1 PLAN D50), `--libdir=lib no-shared no-module no-capieng no-tests zlib`, `CC/AR/RANLIB` = wrappers | none expected | AYCB/openssl 3.3.2: not reused (old, no CI) [zigports §2] |

**OpenSSL `--libdir=lib` is required.** 3.6.0's `mingw64` target has `multilib => "64"` and `mingwarm64` `multilib => "-arm64"`, and `unix-Makefile.tmpl:330` sets `$libdir = "lib$target{multilib}"`, so without it the archives land in `lib64/` or `lib-arm64/` [review M1] V. MXE passes `--libdir` too. `no-asm` is a documented fallback if aarch64 perlasm fails (I; llvm-mingw builds it with asm).

**Static oneTBB.** Upstream discourages static oneTBB (no `DllMain` thread cleanup) (I); CRAN ships it anyway. The M2 smoke runs `parallel_for` on several threads and M4 adds a multi-threaded terra call [review L8].

### 6.2 sqlite options
The Rtools `libsqlite3.a` compile options (`strings`, V [review H2]):
```
-DSQLITE_ATOMIC_INTRINSICS=1 -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_MATH_FUNCTIONS
-DSQLITE_ENABLE_PERCENTILE -DSQLITE_ENABLE_RTREE -DSQLITE_SYSTEM_MALLOC
-DSQLITE_TEMP_STORE=1 -DSQLITE_THREADSAFE=1
```
- No `SQLITE_OMIT_LOAD_EXTENSION` in any form: SQLite tests it with `#ifndef` (`src/loadext.c:22`, 3.51.2), so `=0` would **remove** extension loading; MXE passes `--enable-load-extension` (`mxe-blueprint/r6768/sqlite.mk`) V.
- The autosetup configure adds `ENABLE_MATH_FUNCTIONS`, `ENABLE_PERCENTILE`, `TEMP_STORE=1` by itself; the direct amalgamation compile must pass them explicitly.
- The recipe keeps this list and the smoke test compares it with `PRAGMA compile_options`.

### 6.3 GDAL (D6, D14)
```
-DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF -DBUILD_PYTHON_BINDINGS=OFF
-DGDAL_USE_EXTERNAL_LIBS=OFF -DGDAL_USE_INTERNAL_LIBS=ON
-DGDAL_USE_PROJ=ON -DGDAL_USE_GEOS=ON -DGDAL_USE_SQLITE3=ON -DGDAL_USE_EXPAT=ON -DGDAL_USE_ZLIB=ON
-DGDAL_USE_TIFF_INTERNAL=ON -DGDAL_USE_GEOTIFF_INTERNAL=ON -DGDAL_USE_JPEG_INTERNAL=ON -DGDAL_USE_PNG_INTERNAL=ON
-DGDAL_USE_GIF_INTERNAL=ON -DGDAL_USE_JSONC_INTERNAL=ON -DGDAL_USE_LERC_INTERNAL=ON
-DGDAL_USE_QHULL_INTERNAL=ON -DGDAL_USE_SHAPELIB_INTERNAL=ON -DEMBED_RESOURCE_FILES=ON
```
- **All built-in drivers** (no `GDAL_BUILD_OPTIONAL_DRIVERS=OFF` list) (D14). This covers the four packages' test drivers: GTiff, MEM, VRT, Shapefile, GeoJSON, CSV, AAIGrid, HFA, RRASTER, OpenFileGDB, `/vsizip`, GPKG/SQLite, GML/KML/GPX/OSM [mxe §C].
- **iconv off** (recorded). With `GDAL_USE_EXTERNAL_LIBS=OFF`, `gdal_check_package(Iconv … CAN_DISABLE)` is off (`cmake/helpers/CheckDependentLibraries.cmake:31`, 3.12.1) V, while CRAN's `gdal.pc` links `-liconv` V. GDAL then uses its recode stub (I), so shapefile/DBF encodings other than UTF-8 and code pages may behave differently from CRAN. Turning it on later: AYCB `libiconv` or `win-iconv` ports exist; its CMake test is a `check_cxx_source_runs` (line 70) that needs a preset cache entry when cross [review M6].
- **OpenMP and armadillo are not needed.** GDAL's CMake has no OpenMP use (grep, V). CRAN's `-lgomp -fopenmp` in the sf/terra/gdalraster fallback `PKG_LIBS` come from armadillo/openblas, which GDAL uses only for TPS; the pkg-config branches (`sf.Makevars.ucrt`, `terra.Makevars.ucrt`, `gdalraster.Makevars.win`) add no `-fopenmp` V. Without armadillo, TPS uses GDAL's fallback solver [review M6].
- No external libtiff anywhere, so nothing clashes with the renamed internal libtiff [mxe §D].
- **Missing network features** (no curl): `/vsicurl` and other `/vsi*` network handlers, `sf_proj_network(TRUE)` / PROJ CDN grids, gdalraster's vsicurl tests, WMS/WMTS/WFS/OGC API drivers. Tests touching them fail or skip (R13) [review L10].

### 6.4 Slice 2 candidates and existing zig ports
The AYCB GitHub org (130 public repos, V) has ports of libraries slice 2 needs; the Codeberg org has 15 repos, none in this stack [review §0] V. They are references or fallbacks under D1, each pinned to a commit. Re-checked 2026-11-23 (slice2 PLAN.md S2-F4..F7, PORTS.md): the Codeberg org still has the same 15 repos; the GitHub AYCB repos are not archived and get commits (boringssl 2026-11-09, libpng 2026-11-06, curl 2026-10-12, "upgrade to zig 0.17.0"), with no move notice. A fallback port (slice2 D104 C) may come from any host, maintained and pinned to a commit (slice2 D111). No surveyed port installs a `.pc` or CMake package files, so a recipe that uses one writes them.

| Library | Use in slice 2 | Zig port (AYCB) |
|---|---|---|
| curl | `/vsicurl`, PROJ network | curl |
| mbedtls / libressl / boringssl | TLS for curl (or schannel) | mbedtls, libressl, boringssl |
| libssh2 | curl sftp (optional) | libssh2 |
| zstd | GTiff/GPKG codec | zstd |
| bzip2 | `/vsibz2`, netCDF filters | bzip2 |
| libpng | external libpng (now internal) | libpng |
| json-c | external json-c (now internal) | json-c |
| libxml2 | some drivers, netCDF | libxml2 |
| libiconv / win-iconv | GDAL recode (6.3) | libiconv, win-iconv |
| c-blosc2 | Zarr | c-blosc2 |
| xz (liblzma) | GTiff LZMA | no xz port; fast-lzma2 (an LZMA2 encoder, not liblzma) |
| libdeflate, libwebp | GTiff codecs | not in the AYCB list (`review/aycb-github-repos.txt`); other orgs unsearched (below) |

The non-AYCB port search stopped at `HTTP 403: API rate limit exceeded` on the `sqlite` query (`zig-ports/ghsearch.txt:48`) V, so later queries never ran; Codeberg-wide search returned non-JSON. Re-run 2026-11-23 (authenticated GitHub, 82 repo and 34 code searches; Codeberg through its explore pages, its search API answered 429): slice2/PORTS.md.

### 6.5 Slice-wide risks
PROJ's static CMake config and SQLite (R5); GDAL finding host copies (mitigated by 4.3's root path); oneTBB on aarch64 MinGW (R8); duplicate symbols between internal copies and the rest (M3 check).

---

## 7. Consumer integration in r-zig-pixi

A branch in r-zig-pixi after M3 [consumer §3(b)]; lines are origin/main f951022.

1. **`zigbuild/tools/rzig/environment.zig` `list()` (:126-141):** for R's env and `R_ZIG_EXTRA_ENV`, when `<dir>/zig-libs/<triple>` exists, insert it as an `Env` before its parent (`.conda=false`, new `.zig_libs` flag; `openmp()` skips it). Tests next to :262-345. Order alone makes zig-libs win, which also fixes the conda-abseil header/archive skew (W15) [consumer §2] V.
2. **`build.zig` `rcmdEnviron` (:2813-2841)** (D10): prepend `${R_HOME}/../../zig-libs/<triple>/lib/pkgconfig` to `PKG_CONFIG_PATH`; `PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR-<zig-libs pc>;…}"` (the s2 fix: `Makevars.win:11` replaces `PKG_CONFIG_PATH`) [consumer §1] V; `R_TOOLS_SOFT="${R_TOOLS_SOFT-${R_HOME}/../../zig-libs/<triple>}"` (`Makeconf.win:57` uses `?=`). Later an rzig `pkg-config` mode.
3. **`build.zig` `cmakeToolchain` (:4268):** zig-libs first on `CMAKE_PREFIX_PATH` (D80). Not `CMAKE_SYSTEM_PREFIX_PATH`: CMake searches the prefixes it derives from PATH before that one, so a conda-forge copy under the env's `Library` won (r-zig-pixi feat-zig-libs ZL11, V on gamma).
4. **`stress/stress.R`:** `:416` `R_TOOLS_SOFT` to zig-libs when present; `:719-721` `.pc` order zig-libs, tree, env. The Rtools tree stays behind zig-libs for the libraries no zig-* package has yet (nlopt, gsl, gmp, mpfr, glpk, hdf5, netcdf, udunits2, harfbuzz, libpq); only GDAL/GEOS/PROJ precedence changes (r-zig-pixi feat-zig-libs ZL14).
5. **`stress/packages.tsv` sysdeps:** sf, gdalraster `libgdal-core@linux libgdal-core@macos zig-gdal@windows zig-geos@windows zig-proj@windows`; terra the same plus `zig-onetbb@windows`; s2 `zig-abseil@windows zig-openssl@windows`. Expectations become `windows=ok`, with an explicit `windows-aarch64=` key where the arches differ [review L9].
6. **`pixi.toml`:** universe is already before conda-forge. Until M5, tests used a `file://` channel from the libs-zig-pixi CI artifact through `stress.R --libs-channel`; since M5 the stress env takes the published zig-* packages and `--libs-channel` is gone (r-zig-pixi PR #52; CONTRACT.md).
7. **`CXX-STDLIB.md`:** amend the "Ruled out" entry (section 1).
8. **Stress report column:** per row, the zig-* builds that were linked (name and build number), and whether any `-l` resolved into the fallback tree (section 8).

**Retiring `R_ZIG_FALLBACK_SOFT`** (win-arm64 only; searched last, never the OpenMP provider, its import libs skipped, `environment.zig:103-124` V): zig-libs comes first, so rebuilt libraries stop coming from the fallback; each later slice moves rows off it, tracked by the column above; when no row resolves into it, delete the variable, code and tests (`environment.zig:297-327`) as a `refactor:`. win-64 never had the fallback (wrong ABI), so it gains directly.

---

## 8. Maintenance

Static archives are linked into every sf, terra, gdalraster and s2 DLL, so an upstream fix reaches users only after a zig-* rebuild, a build-number bump **and** a source reinstall of the R packages [review M4]. This is the upkeep CXX-STDLIB.md named.

- **Cadence:** follow Rtools45 updates (each new Rtools build is the version reference, D9), and review all pins at every zig bump (which rebuilds everything anyway, D4).
- **Security watch list:** OpenSSL, expat, SQLite, zlib, libtiff (internal to GDAL); curl when it arrives. A security release triggers a rebuild of that package with a bumped build number. Dependent zig-* archives hold no copy of it (the code is joined only at the consumer's link, I), so they need a rebuild only when the fix changes headers or the version pin.
- **Consumers learn to reinstall** through the stress-report column (section 7, item 8) that shows the zig-* builds each R package was linked with; a mismatch with the newest build means reinstall from source.
- **Sizes:** record each archive's size and each `.conda` size per build in PLAN.md (a static all-driver GDAL is guessed at ~100 MB uncompressed, I); check prefix.dev upload limits before M5 [review L7].

---

## 9. CI, publishing and milestones

### 9.1 CI (`.github/workflows/build.yml`)
CI tiers as r-zig-pixi: a core set on every push; the full matrix and the upstream-zig leg via the `full-ci` label or dispatch.

1. **toolchain** (ubuntu-latest): `pixi run build-toolchain` into a local channel (`-c file://$LIBS_ZIG_OUT -c conda-forge`), `bld/`, `src_cache/`, `test/` deleted before the upload, as flang-pixi's stage action [infra §3]. As built in M0: m0 PLAN D33-D35; a `plan` job writes the env list (`default`, plus the gated `upstream-zig`) and toolchain runs once per env with `fail-fast: false`, so a failing leg does not skip the other leg's jobs (m0 D43, from the M0 review).
2. **cross (win-64), cross (win-arm64)** (ubuntu-latest): the chain in order (zlib → sqlite → expat → geos → proj → gdal; abseil, onetbb, openssl) as `pixi run build-libs <subdir>` (one `depends-on` line per recipe in pixi.toml), with each recipe's tests run on linux after its build; upload `channel-<subdir>-<env>`. Time: A.
3. **test** on `windows-latest` and `windows-11-arm`: Defender exclusions, short timeouts (MSYS spawn flake) [infra §5]; native conda-forge zig; `rattler-build test --package-file` per package through `pixi exec`, whose stored test is `tests/pkgtest.zig` (m0 D31).
4. **r-consumer** (win-64, win-arm64) × (conda-zig | upstream-zig, gated): `pixi exec` with `r-zig-slim` from universe plus the artifact channel; install sf, terra, gdalraster, s2 from source; run `tests/r/smoke.R`. No lock writes in CI.
5. **publish** (ubuntu-latest; not in the workflow until M5, m0 D30): push/dispatch on main **and** `vars.CONDA_PUBLISH == 'true'`; `permissions: id-token: write`; `rattler-build -v upload prefix --channel universe --skip-existing dist/<subdir>/*.conda`; then flang-pixi's GraphQL verify (`build.yml:298-319`) [infra §3, §4]. **User action:** register `luciorq/libs-zig-pixi` / `build.yml` as a Trusted Publisher on universe (Base/Overrides empty). Before any local publish the preflight (CONVENTIONS.md) is required.
6. **alignment** (ubuntu-latest): `zig-toolchain check-alignment` over the built packages. As built in M0: the locally built default-leg channels only (each subdir's `repodata.json`, `--expect win-64,win-arm64`, m0 D36, D44); the comparison with the published universe channel comes before M5 (m0 M0-F22, D45).

The repo is public: free `windows-11-arm` runners need a public repo (D15, I).

A native fallback (building a recipe on a Windows runner) stays possible if cross hits a blocker (A).

### 9.2 Milestones

| M | Content | Exit criteria |
|---|---|---|
| M0 | Repo skeleton, DESIGN/CONVENTIONS/PLAN, pixi envs, `zig-toolchain`, `zig-zlib` | Both subdirs cross-built on linux. Package tests pass on windows-latest and windows-11-arm with a plain smoke executable. `pkgconf --libs zlib` gives existing paths on Windows (relocatable `.pc`). No `*.lib`/`*.dll`/`*.dll.a`. `ZIG_BIN` reaches the build script via `env.get` and upstream ziglang 0.17.1 builds it too. Sizes recorded. |
| M1 | zig-sqlite, zig-expat, zig-openssl | Smoke executables run on both arches; RTREE works; `PRAGMA compile_options` matches; OpenSSL archives in `lib/`. |
| M2 | zig-geos, zig-proj, zig-abseil, zig-onetbb | Smoke tests as `R CMD SHLIB` DLLs (D20) run on both arches. `proj.db` present and the embedded copy works without `PROJ_DATA`. `llvm-nm`: libc++ only; no exported `sqlite3_*` in `libproj.a`. Multi-threaded `parallel_for`. |
| M3 | zig-gdal | GDAL smoke (DLL) opens GPKG, GTiff, GeoJSON, Shapefile on both arches. `gdal.pc` closed (link works without `--static`). No duplicate defined symbols over the closure. Licence inventory complete. |
| M4 | r-zig-pixi consumer branch (section 7) against the artifact channel | sf, terra, gdalraster, s2 install and pass `tests/r/smoke.R` (D81) on both arches with conda zig, and in the gated leg with upstream ziglang; a multi-threaded terra call; stress rows ok; link logs show `lib<n>.a`. |
| M5 | Publish build 0 to universe (OIDC); r-zig-pixi consumes from universe | GraphQL verify lists every package in win-64 and win-arm64; r-zig-pixi CI green from universe; the stress zig-* build/fallback column exists. |
| M6 (later) | Slice 2 (6.4), linux/macOS if wanted (D5), retiring `R_ZIG_FALLBACK_SOFT` | Defined in the slice-2 PLAN.md. |

---

## 10. Decisions

All accepted 2026-11-20. "user" = accepted by the user's "Yes, continue with recommended" (every ★ option). "default" = chosen for a decision the review found silent; the user may revisit.

| # | Question | Accepted | Alternatives considered | Reason | Who |
|---|---|---|---|---|---|
| D1 | Build method | Each library's own build system (CMake, Perl Configure, direct amalgamation compile) under rattler-build with zig-toolchain; zig ports are references/fallbacks | B reuse build.zig ports; C write our own build.zig per library | verified cross path; upstream `.pc`/CMake configs (s2 needs `absl_*.pc`); no port zig-version churn; matches CRAN recipes [cross §4] [zigports §3] | user |
| D2 | Install layout and name | Private sub-prefix `<envdir>/zig-libs/<zig-triple>`, found automatically by rzig | B conda-forge paths + `run_constrained`; C sub-prefix via `LOCAL_SOFT` only; names `zig/<triple>`, `<triple>.static` | no clash with conda-forge; arches side by side; works on any OS [consumer §3] | user |
| D3 | Static vs shared | Static `lib<n>.a` only | B static + DLL + `.dll.a`; C shared only | Rtools parity; no PATH/rpath; no libc++ across DLLs; zig `-l` order [cross §3] | user |
| D4 | Zig pin | Exactly `==0.17.1`; a bump rebuilds everything and bumps every build number | B `0.17.*`; C track 0.18-dev | matches r-zig; no silent zig change behind one build string [infra §5] | user |
| D5 | linux/macOS builds | Later; conda-forge covers them today | B now | smaller slice; layout already allows it | user |
| D6 | GDAL deps in slice 1 | Minimal: external proj/geos/sqlite/expat/zlib, GDAL-internal tiff/geotiff/jpeg/png/gif/json-c/lerc/qhull/shapelib; iconv off (recorded; AYCB libiconv/win-iconv for later); OpenMP and armadillo not needed | B + zstd/libdeflate/libwebp/xz; C + curl, netCDF/HDF5 | covers every test driver except netCDF/Parquet; evidence in 6.3 [review M6] | user |
| D7 | OpenSSL for s2 | Build our own static zig-openssl 3.6.0 | B conda-forge MSVC openssl; C s2's download | static, consistent closure; B breaks static-only and is MSVC | user |
| D8 | Toolchain shims | One Zig multi-call program in zig-toolchain (triple-named), copying rzig's `binutils.zig`/`target.zig` translation with a source note | B bash wrappers; C depend on rzig | simplicity-first, prefer-Zig; one place for workarounds | user |
| D9 | Versions | Rtools45 build 6768: zlib 1.3.1, sqlite 3.51.2, expat 2.7.3, geos 3.14.1, proj 9.7.1, gdal 3.12.1, abseil 20250127.0, onetbb 2022.2.0, openssl 3.6.0 | B latest upstream | CRAN parity, known patches | user |
| D10 | pkg-config search path | A line in `Rcmd_environ` now; an rzig `pkg-config` mode later | B the rzig mode now | least rzig work before M4 | user |
| D11 | Zig for published packages | conda-forge zig 0.17.1 (as r-zig's packages); upstream ziglang 0.17.1 is the reference, in a gated CI leg that rebuilds the packages via `ZIG_BIN` (`build.script.env: ZIG_BIN: ${{ env.get("ZIG_BIN", default="") }}`, verify in M0) and checks R packages link | A upstream zig repackaged on universe for publishing (the review's ★); C rebuild with one zig only, test both at the consumer link | consistent with r-zig's own packages; upstream failures fixed in the design, conda-forge quirks only as removable workarounds [review H1] | user (accepted the recommendation over the review's) |
| D12 | Non-conda users (wheel, standalone R) | conda only for now, recorded | B also publish the sub-prefix as a zip (`R_TOOLS_SOFT`-like tree) | scope; the zip is a later option [review M5] | user |
| D13 | Slice-1 scope | includes oneTBB (terra `-ltbb12`) and OpenSSL (s2) | leave terra/s2 partly broken on Windows | the four packages are the done criterion [review M8.2] | user |
| D14 | GDAL drivers | All built-in drivers | `GDAL_BUILD_OPTIONAL_DRIVERS=OFF` plus a list | package behaviour as CRAN; size recorded (section 8) [review M8.4] | user |
| D15 | Repo visibility | Public | private | free `windows-11-arm` runners need a public repo (I, GitHub policy not checked) [review M8.7] | user |
| D16 | Resource files | PROJ's own `EMBED_RESOURCE_FILES` default (ON for static), GDAL ON, and ship `share/{proj,gdal}` | embed only; ship only | sf/terra/gdalraster copy `share/` from `R_TOOLS_SOFT`; behaviour as on CRAN [review M8.3] | default (user may revisit) |
| D17 | Tooling language | Zig: build-number alignment and `.pc` closing are `zig-toolchain` subcommands; no Python; `llvm-nm` (llvm-tools) in build/test env only, since zig has no nm | Python `check-build-alignment.py` (flang-pixi) | prefer-Zig, simplicity-first [review M8.5] | default (user may revisit) |
| D18 | Rules file | `.github/devdocs/CONVENTIONS.md` | `devdocs/RULES.md` | same name as r-zig-pixi [review M8.6] | default (user may revisit) |
| D19 | Repo licence | MIT | BSD-3-Clause (first default), Apache-2.0 | matches zig and its port ecosystem; the reusable part is a Zig program; r-zig-pixi should use the same | user, 2026-11-20 |
| D20 | Windows smoke tests | From M2, link as R packages do (`R CMD SHLIB` DLL via r-zig-slim, `dyn.load`, `.Call`); M0/M1 plain executables | executables only; reuse rzig link logic in zig-toolchain | rzig adds flags, `/OPT:NOICF`, cfguard, `tmp.def` that an executable never tests [review M2] | default (user may revisit) |
| D80 | CMake prefix variable for zig-libs in r-zig.cmake (section 7.3) | `CMAKE_PREFIX_PATH` | `CMAKE_SYSTEM_PREFIX_PATH` (first design), plus a docs note | PATH-derived prefixes are searched before the system prefix path, so conda-forge's copy won (r-zig-pixi feat-zig-libs ZL11) | user, 2026-11-22 |
| D81 | R smoke script | `tests/r/smoke.R` here, from the kappa M4 run, one `SMOKE` line per check, exit 1 on any failure | in r-zig-pixi `stress/`; only packages.tsv one-liners | one script both repos can run against the same packages | user, 2026-11-22 |

---

## 11. Risks and unknowns

| # | Risk | Status | How the slice tests it |
|---|---|---|---|
| R1 | Prefix placeholder in text files rewritten with wrong slashes on Windows [cross §1] | unverified | `.pc` uses `${pcfiledir}`; M0 checks every `-L`/archive path from `pkgconf --libs zlib` exists; M3 `cmake --find-package` for GDAL |
| R2 | zig `-l` picks `<n>.lib` / `.dll.a` [cross §3] | verified behaviour; mitigated | no `*.lib`/`*.dll`/`*.dll.a` assertion; M4 link logs show `lib<n>.a` |
| R3 | libc++ ABI drift between the archive-building zig and the linking zig | unknown | gated upstream-zig leg (4.2, 9.1 job 4) |
| R4 | Host env pulls conda-forge MSVC runtime packages [cross §1] | verified behaviour | host lists only zig-*; `ignore_run_exports`; linkage check shows only system DLLs |
| R5 | PROJ static + GDAL CMake: SQLite twice or missing static deps | inferred; PROJ's static config calls `find_dependency(SQLite3)` (`project-config.cmake.in:30`) V | M3 duplicate-symbol scan; GDAL smoke linked with only `pkgconf --libs gdal` |
| R6 | `proj.db` generation needs build-env `sqlite3` | inferred | toolchain file: NEVER for programs; M2 checks `proj.db` and embedded use |
| R7 | `try_run` in cross mode | GDAL skips them when cross [mxe §B] V; others unknown | builds fail loudly; preset cache entries recorded in PLAN.md |
| R8 | oneTBB on aarch64-windows-gnu with clang | inferred (CRAN builds it with llvm-mingw) | M2 multi-thread smoke on windows-11-arm; M4 terra |
| R9 | abseil ABI options vs s2 | inferred | M4 s2 smoke (`s2_area`, a union); undefined `absl::lts_2025…` symbols resolve |
| R10 | Windows import libs in closed `.pc` missing in one zig | assumption | smoke links in both zig legs |
| R11 | s2's `PKG_CONFIG_PATH` replacement hides `absl_*` | verified failure today [consumer §1] | M4 s2 with only the `PKG_CONFIG_LIBDIR` default |
| R12 | `R_TOOLS_SOFT` unset → `cp "/share/gdal"` fails | inferred | M4 plain `R CMD INSTALL` without stress.R's override |
| R13 | netCDF/Parquet/network tests fail instead of skipping | assumption | M4 runs package tests once, non-gating; failures listed against 6.3's missing-features list; feed slice 2 |
| R14 | Hosted-runner hazards (MSYS spawn hang, Defender, arm queue) | verified elsewhere [infra §5] | timeouts, exclusions, re-runs; job times in PLAN.md |
| R15 | `--skip-existing` keeps stale builds | verified pitfall | `check-alignment` (M0: local channels only; the comparison with universe comes before M5, m0/PLAN.md D45); every change bumps; publish logs (`-v`) checked for "skipped" |
| R16 | `zig-*` name collisions on universe | unknown | query universe repodata for every name before M5 |
| R17 | A library-specific cross blocker | inferred low | per recipe: native Windows build or a build.zig port, recorded |
| R18 | Licence compliance of archives inside R package DLLs | inferred | `licenses/<pkg>/` present; M3 inventory (5.8); GEOS LGPL noted for Phase 3 binaries |
| R19 | `env.get("ZIG_BIN")` does not reach the build script | assumption | M0 exit criterion; fallback recorded in m0 PLAN.md if it fails |
| R20 | Upstream ziglang has no conda package on universe | unresolved (repodata check not finished) | only matters for the review's alternative A (D11); not needed by the accepted mechanism |
