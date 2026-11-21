# m0: repo skeleton, zig-toolchain, zig-zlib

Branch `m0`, the first branch of libs-zig-pixi. Started 2026-11-20. Design: `.github/devdocs/DESIGN.md` (accepted 2026-11-20). Rules: `.github/devdocs/CONVENTIONS.md`.

Tags: **V** verified, **I** inferred, **A** assumption.

## Goal

Stand up the repo and prove the whole path on the smallest library: a Zig multi-call cross toolchain packaged as `zig-toolchain`, and `zig-zlib` cross-built on linux for win-64 and win-arm64, installed into the private sub-prefix, and tested on real Windows runners, with both zigs.

## Scope

M0 exit criteria (DESIGN §9.2):

1. Repo skeleton: `pixi.toml`/`pixi.lock` (envs `default`, `upstream-zig`), `variants.yaml`, `recipes/`, `toolchain/`, `tests/smoke/`, `.github/devdocs/`, README, LICENSE.
2. `zig-toolchain` (linux-64): one Zig program with triple-named roles for `x86_64-w64-mingw32` and `aarch64-w64-mingw32` (`-cc`, `-c++`, `-ar`, `-ranlib`, `-dlltool`, `-windres`, `-rc`, `-strip`, `-objcopy`), subcommands `close-pc` and `check-alignment`, generated CMake toolchain files, an activation script; honours `ZIG_BIN`.
3. `zig-zlib` 1.3.1 cross-built for win-64 and win-arm64 on linux, installing only `<envdir>/zig-libs/<triple>/{include,lib/libz.a,lib/pkgconfig/zlib.pc,licenses/zlib/}`.
4. Recipe test on linux: files present; no `*.lib`, `*.dll`, `*.dll.a`; `pkgconf --libs zlib` resolves.
5. Package tests pass on `windows-latest` and `windows-11-arm` (`rattler-build test --package-file`): a plain smoke executable compresses and uncompresses; every `-L` and archive path printed by `pkgconf --libs zlib` exists (relocatable `.pc`).
6. Both zigs: `ZIG_BIN` reaches the build script through `build.script.env: ZIG_BIN: ${{ env.get("ZIG_BIN", default="") }}`, and upstream ziglang 0.17.1 builds zig-zlib for both subdirs.
7. Archive and `.conda` sizes recorded below.

Local builds put big scratch under `/data/gamma/luciorq/workspaces/temp/r-zig-pixi/libs-m0/` with `RATTLER_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` there (`/` has ~90 GB free).

## Decisions

All dated 2026-11-20. "user" = the user's "Yes, continue with recommended", which accepts every ★ option of the draft design's menus. "default" = picked for a decision the review found silent; the user may revisit. Full table with alternatives' consequences: DESIGN §10.

| # | Question | Options | Choice | Reason | Who |
|---|---|---|---|---|---|
| D1 | Build method | A ★ own build system under rattler-build + zig-toolchain, ports as references/fallbacks; B build.zig ports; C own build.zig per library | A | verified cross path; upstream `.pc`/CMake configs; no port zig churn | user |
| D2 | Install layout | A ★ `<envdir>/zig-libs/<zig-triple>` found by rzig; B conda-forge paths; C `LOCAL_SOFT` only. Name: `zig-libs/<triple>` ★, `zig/<triple>`, `<triple>.static` | A, `zig-libs/<triple>` (was draft D11) | no clash with conda-forge; arches side by side | user |
| D3 | Static vs shared | A ★ static `lib<n>.a` only; B + DLL/`.dll.a`; C shared | A | Rtools parity; zig `-l` order; no libc++ across DLLs | user |
| D4 | Zig pin | A ★ `==0.17.1`, bump = rebuild all + bump all; B `0.17.*`; C 0.18-dev | A | matches r-zig; no silent zig change | user |
| D5 | linux/macOS builds | A ★ later; B now | A | conda-forge covers them today | user |
| D6 | GDAL deps | A ★ minimal (internal tiff/png/jpeg/json-c…; iconv off; no OpenMP/armadillo); B + codecs; C + curl/netCDF | A | covers the test drivers; review M6 evidence | user |
| D7 | OpenSSL | A ★ own static zig-openssl; B conda-forge MSVC; C s2 download | A | static, consistent closure | user |
| D8 | Toolchain shims | A ★ one Zig multi-call program, copying rzig `binutils.zig`/`target.zig` with a source note; B bash; C depend on rzig | A | simplicity-first, prefer-Zig | user |
| D9 | Versions | A ★ Rtools45 build 6768 (zlib 1.3.1, sqlite 3.51.2, expat 2.7.3, geos 3.14.1, proj 9.7.1, gdal 3.12.1, abseil 20250127.0, onetbb 2022.2.0, openssl 3.6.0); B latest | A | CRAN parity | user |
| D10 | pkg-config path | A ★ `Rcmd_environ` line now, rzig mode later; B rzig mode now | A | least rzig work before M4 | user |
| D11 | Zig for published packages | A upstream repackaged on universe (review's ★); B ★ conda-forge zig 0.17.1, upstream ziglang in a gated leg via `ZIG_BIN` + `env.get`; C one zig, both tested only at consumer link | B | as r-zig's own packages; upstream stays the reference, conda-forge quirks only as removable workarounds | user (accepted the recommendation) |
| D12 | Non-conda users | A ★ conda only, recorded; B zip of the sub-prefix | A | scope | user |
| D13 | Slice-1 scope | include oneTBB and OpenSSL ★; leave terra/s2 broken | include | the four R packages are the done criterion | user |
| D14 | GDAL drivers | all built-in ★; `GDAL_BUILD_OPTIONAL_DRIVERS=OFF` + list | all | CRAN-like behaviour | user |
| D15 | Repo visibility | public ★; private | public | free `windows-11-arm` runners need a public repo (I) | user |
| D16 | Resource files | PROJ default + GDAL `EMBED_RESOURCE_FILES=ON` and ship `share/{proj,gdal}`; embed only; ship only | both | sf/terra/gdalraster copy `share/` from `R_TOOLS_SOFT` | default (user may revisit) |
| D17 | Tooling language | Zig subcommands of zig-toolchain; Python script | Zig; `llvm-nm` in build/test env only | prefer-Zig; zig has no nm | default (user may revisit) |
| D18 | Rules file | `.github/devdocs/CONVENTIONS.md`; `devdocs/RULES.md` | CONVENTIONS.md | same as r-zig-pixi | default (user may revisit) |
| D19 | Repo licence | A MIT; B BSD-3-Clause (first default, conda-forge recipe convention); C Apache-2.0 | A MIT | matches zig and its port ecosystem; the reusable part is a Zig program; r-zig-pixi (no LICENSE yet) should use the same | user, 2026-11-20 |
| D20 | Windows smoke tests | M0/M1 executables, from M2 `R CMD SHLIB` DLLs; executables only | staged | rzig link flags/cfguard/`tmp.def` only tested by DLL links | default (user may revisit) |

| D21 | Toolchain change → rebuild of dependents | A `zig_toolchain` key in `variants.yaml`, recipes require `zig-toolchain ==${{ zig_toolchain }}` (in the hash); B rule "toolchain change bumps all build numbers" in CONVENTIONS.md only | A | `--skip-existing` would keep stale builds otherwise (M0-F9) | default (user may revisit) |
| D22 | Build paths in `.debug$S` S_OBJNAME | A wrapper appends `-Xclang -object-file-name=zig-libs.obj` (not for plain `.s` inputs); B same flag in activation CFLAGS only; C leave paths | A | covers callers that override CFLAGS; no user path ships (M0-F6) | default (user may revisit) |
| D23 | `-strip`/`nm`/`objdump` roles | A `<triple>-strip` no-op exit 0, `-{nm,objdump,objcopy,readelf,addr2line,ld}` exit 1 "add llvm-tools", all set as CMake CACHE FILEPATH; B `zig objcopy`; C leave to host discovery | A | B fails on PE (M0-F7); C runs host ELF binutils on COFF | default (user may revisit) |
| D24 | Output dirs and `ZIG_BIN` per env | A default env `ZIG_BIN=""`, `LIBS_ZIG_OUT=${LIBS_ZIG_OUT:-$PIXI_PROJECT_ROOT/output}`; upstream env `${LIBS_ZIG_OUT_UPSTREAM:-$PIXI_PROJECT_ROOT/output-upstream}`; per-machine paths exported locally; B one shared dir; C machine path as default | A | same filename/build string in both legs (M0-F8); public repo must not default to `/data/gamma` | default (user may revisit) |
| D25 | Zig version guard | A every `build.sh` fails when `"${ZIG_BIN:-zig}" version` ≠ `${{ zig }}` (passed as `ZIG_VERSION`); B no check | A | `ZIG_BIN` from a caller's shell could pick another zig (M0-F8) | default (user may revisit) |
| D26 | zlib install fixups | A post-install in `build.sh`: rename `libzlibstatic.a`→`libz.a`, remove DLL/`.dll.a`/`bin/`/man, `close-pc`; B patch zlib's CMake | A | smallest change; F7 mismatch | default (user may revisit) |
| D27 | `-march/-mcpu/-mtune=native` | A dropped by the wrapper (keeps `-mcpu=baseline`); B pass through | A | native leaked AVX2 into a cross build (M0-F10) | default (user may revisit) |
| D28 | `CMAKE_PREFIX_PATH` in activation `CMAKE_ARGS` | A removed (root path does libs/headers/packages); B keep | A | it made `find_program` run sub-prefix scripts (M0-F11) | default (user may revisit) |
| D29 | Pre-upload guard against upstream-leg packages | A deferred to the publish step (M5); B now | A | M0 has no upload task | default (user may revisit) |
| D30 | Publish job in the M0 workflow | A none now, publishing is M5 (with D29's guard, OIDC, `vars.CONDA_PUBLISH`); B a gated publish job now | A | nothing may be published before M5; no secrets or `id-token` needed, `permissions: contents: read` | default (user may revisit), 2026-11-21 |
| D31 | How a library's package tests run on Windows | A one Zig program `tests/pkgtest.zig` run by one plain line `zig run … pkgtest.zig -- <triple> <module> [<smoke.c>]` that bash (linux) and cmd.exe (Windows) both run; shipped through a `path: ../../tests` source and `tests.files.source`; zig and pkgconf as test build requirements; B keep `interpreter: bash` and add `m2-bash` to the test's build requirements; C split the tests per platform with selectors; D the smoke as a workflow-only step with `pixi exec` | A | B cannot solve on linux-64 (M0-F14); C: tests are rendered at build time on linux, where `target_platform` is always win-*, so no selector tells the test host apart; D leaves the package tests without the smoke, which criterion 5 asks for. A is one test path for both hosts, in Zig (prefer-Zig) | default (user may revisit), 2026-11-21 |
| D32 | Static-only check (no `*.dll`, `*.dll.a`, `*.lib`) | A `package_contents.files.not_exists` globs; B inside pkgtest.zig | A | declarative; the archive content is the same on every host, and rattler-build keeps `package_contents` out of the stored tests anyway (M0-F16) | default (user may revisit), 2026-11-21 |
| D33 | Where the recipe list and its order live | A pixi task `build-libs <subdir>`: one `depends-on` line per recipe, run in the order listed; B `rattler-build --recipe-dir recipes` (topological); C a list in build.yml | A | pixi.toml stays the one place that knows commands; B would also try the linux-only zig-toolchain for win-*; order verified (M0-F19) | default (user may revisit), 2026-11-21 |
| D34 | Shape of the gated upstream-zig leg | A the same jobs with an `env` matrix axis: `default` always, `upstream-zig` with PR label `upstream-zig` or `full-ci` or dispatch input `upstream_zig`; B a second workflow file as r-zig-pixi's `upstream-zig.yaml`; C separate jobs | A | one step list for both zigs; the toolchain job computes the axis once (`outputs.envs`) | default (user may revisit), 2026-11-21; toolchain job amended by D43 |
| D35 | Artifacts and output dirs in CI | A `LIBS_ZIG_OUT=$GITHUB_WORKSPACE/out/default`, `LIBS_ZIG_OUT_UPSTREAM=…/out/upstream-zig`; artifacts `channel-<subdir>-<env>` holding `<subdir>/` and `noarch/` with rattler-build's `repodata.json`, `bld/`, `src_cache/`, `test/` dropped; B one artifact per job with everything | A | the legs never mix packages with the same file names (M0-F8); flang-pixi's handoff without its stage action (pixi tasks build, so no composite build action is needed) | default (user may revisit), 2026-11-21 |
| D36 | check-alignment input and rules | A each subdir's `repodata.json` (rattler-build writes it), a stale-index check (every `.conda` listed, every listed file present), newest build number per subdir, `--expect win-64,win-arm64` from pixi.toml so a package in one expected subdir must be in all; B open each `.conda` (zip + zstd tar; zig 0.17 std has `std.zip` and `std.compress.zstd`, not tried); C parse file names | A | no archive code; the expected list is data in pixi.toml; zig-toolchain (linux-64 only) is checked by the build-number rule alone. CI checks the `default` leg only: the upstream leg builds the same recipes and is never published | default (user may revisit), 2026-11-21 |
| D37 | `zig_toolchain` version after adding check-alignment | A stays 0.1.0; B bump to 0.1.1 | A | 0.1.0 was never published, and the wrapper flags, activation script and CMake/meson files are unchanged, so no dependent build differs; build strings are unchanged (`zig_69dc1b3_0`, `zig_29ef852_0`, `zig_6e0c9c0_0`). The variants.yaml bump rule holds from the first publish (its comment says so since the review) | default (user may revisit), 2026-11-21 |
| D38 | Build numbers after the recipe test changes | A stay 0; B bump to 1 | A | nothing is published; CONVENTIONS' bump rule protects `--skip-existing` uploads, which start in M5 | default (user may revisit), 2026-11-21 |
| D39 | Action references | A the tags flang-pixi pins (`actions/checkout@v7.0.1`, `prefix-dev/setup-pixi@v0.11.3` with pixi v0.84.2, `actions/upload-artifact@v7.0.2`, `actions/download-artifact@v8.0.2`); B commit SHAs | A | as the reference repos; zizmor reports `unpinned-uses` for each (M0-F21), SHA pinning stays open | default (user may revisit), 2026-11-21 |
| D40 | rattler-build on the Windows runners | A `pixi exec --spec rattler-build==0.80.2` (the version pixi.lock has, `RATTLER_BUILD_VERSION` in build.yml, bumped with the lock); B a locked win-64/win-arm64 pixi env | A | DESIGN 3: no locked Windows env, no lock against a `file://` channel; `pixi exec` writes no lock | default (user may revisit), 2026-11-21 |
| D41 | Proof of which zig built a package | A every `build.sh` prints `<pkg>: ZIG_BIN='…' zig version: V (<path>)` and the composite action `.github/actions/which-zig` lists those lines in the step summary and fails unless they match the env (`ZIG_BIN=''` for default, `…/ziglang/zig` for upstream-zig); B `ZIG_TOOLCHAIN_TRACE=1` (34+ lines per build); C read `ZIG_BIN` from each package's rendered recipe | A | short, and it checks the log of the zig that ran, not only the env | default (user may revisit), 2026-11-21 |
| D42 | Which zig-toolchain binary runs check-alignment | A the sources, `zig build --build-file toolchain/build.zig run -- check-alignment` (pixi task); B the packaged binary through `pixi exec` from the artifact channel | A | the same command locally and in CI; the packaged subcommand is covered by the zig-toolchain recipe test | default (user may revisit), 2026-11-21; amended by D44 |
| D43 | The toolchain job with both legs (review: an upstream-zig failure skipped every default job, and the other way round) | A a `plan` job writes the env list (`outputs.envs`); `toolchain` gets the same `env` matrix with `fail-fast: false` as cross and test, one artifact `channel-linux-64-<env>` per leg; cross, test and alignment gate on `!cancelled() && needs.plan.result == 'success'`, so a failed leg fails only its own env's jobs at the artifact download; B keep one toolchain job and mark the upstream steps `continue-on-error`; C two toolchain jobs | A | one step list for both zigs (D34); a matrix job's `needs.<job>.result` is the worst of its legs, so gating on `toolchain` would still skip both envs; B hides a failed gated check as green | default (user may revisit), 2026-11-21 |
| D44 | How the check-alignment task runs the binary (review: `zig build run` turned exit 2 into 1 and appended build-runner lines) | A `zig build --build-file toolchain/build.zig --prefix toolchain/zig-out` (gitignored), then `toolchain/zig-out/bin/zig-toolchain check-alignment …`; B keep `zig build run` and document zero vs non-zero only | A | the documented exit codes (0, 1, 2) and a clean log reach CI; the `run` step D42 added to build.zig is dropped again, so build.zig is as at 59f7431 (M0-F23) | default (user may revisit), 2026-11-21 |
| D45 | What check-alignment covers before M5 (review: the claim that it replaces flang-pixi's script was overstated) | A M0: local channels only (one run's builds); before M5 add a channel-URL input (plain GET of `https://prefix.dev/universe/<subdir>/repodata.json`, no key, as M0-F10) and compare the new build numbers with the published ones or with a declared release number kept as data; B add the URL input now | A | nothing is published before M5, so there is nothing to compare with yet; R15 stays open until then (M0-F22) | default (user may revisit), 2026-11-21 |

Decisions taken during M0 are appended here as D21+.

## Findings

Dated 2026-11-20 unless noted. Scratch roots: `NEXT=/data/gamma/luciorq/workspaces/temp/r-zig-pixi/next`, `LD=$NEXT/libs-design`.

**F1 (X1) V. The Rtools45 x86_64 tree is GCC 14.3 with libstdc++.** Tarball `rtools45-toolchain-libs-full-6768.tar.zst`, sha256 `6b5cece3…4099`, MXE tree `x86_64-w64-mingw32.static.posix`. `strings` on `libgsl.a`/`libgdal.a` objects: `GCC: (GNU) 14.3.0`. It ships `lib/gcc/…/14.3.0/{libstdc++.a,libsupc++.a,libgcc.a,libgomp.a,…}`, no `libgcc_eh.a`, and a full MinGW-w64 import-library set, so a blanket `-L` collides (duplicate `pthread_*`, `DllMain`). Evidence: `$NEXT/probe-rtools-x64/FINDINGS.md` X1.

**F2 (X2) V. Its `.pc` files are static-only and partly broken.** `libgcrypt.pc` has `Libs` twice; `gdal.pc` defines `prefix` twice (pkg-config errors); udunits2 has no `.pc`. Evidence: FINDINGS.md X2.

**F3 (X3) V. Its C libraries link with zig and run.** gsl, gslcblas, hdf5, z, sz, aec: on kappa (win-64) `gsl_sf_bessel_J0(1)` and `H5get_libversion` ran. Evidence: FINDINGS.md X3.

**F4 (X4) V. The C API of its C++ libraries needs GCC's libstdc++.** geos_c/proj with zig's runtime only: 153 undefined libstdc++ symbols (`std::__cxx11::basic_string`, …); `geos.pc`'s `-lstdc++` means GCC's, which zig maps to libc++. With the tree's `libstdc++.a` and `libgcc.a` by path it links and runs on kappa (GEOS area 1, ParseException caught, proj 9). Evidence: FINDINGS.md X4.

**F5 (X5) V. Its C++ API cannot mix with zig's libc++.** GDAL `OGRSpatialReference::exportToWkt` compiled with libc++: 209 undefined libstdc++ symbols; adding `libstdc++.a`: duplicate `std::exception`/`std::bad_alloc` vtables (libc++abi vs libsupc++). Evidence: FINDINGS.md X5.

**F6 (X6) V. It works only by compiling the consumer against GCC's libstdc++ headers.** `-nostdinc++ -isystem <gcc>/include/c++ … -nostdlib++` plus `libstdc++.a libgcc.a libgomp.a`: 112 MB DLL; on kappa `importFromEPSG(4326)`/`exportToWkt` ok, exceptions across GCC- and zig-compiled code ok; adding the tree's `libwinpthread.a` breaks it (`_gnu_exception_handler` undefined). This contradicts r-zig's libc++-on-Windows decision, which is why the libraries are rebuilt (DESIGN §1). Evidence: FINDINGS.md X6.

**F7 V. rattler-build 0.80.1 + zig 0.17.1 cross-built zlib 1.3.1 for win-64 and win-arm64 on linux.** Triple-named wrappers (`$LD/rattler-cross/tc/`) and a CMake toolchain file. Evidence: `$LD/rattler-cross/probe2/win-64.2.log` and `win-arm64.2.log` (header `rattler-build 0.80.1`); outputs `$LD/rattler-cross/probe2/out/win-64/zig-zlib-probe-1.3.1-h9490d1a_0.conda` and `.../win-arm64/zig-zlib-probe-1.3.1-h5667933_0.conda`. zlib's CMake installs `lib/libzlibstatic.a` and `share/pkgconfig/zlib.pc` (`$LD/rattler-cross/inst-aarch64.log`): the archive name disagrees with the `.pc`'s `-lz`, and the `.pc` is under `share/`. Not run on Windows in that probe.

**F8 V. zig 0.17.1 `-l` resolution prefers `<n>.lib`, never `.dll.a`.** Link tests in `$LD/rattler-cross/linktest/` [cross §3]; the basis of D3.

**F9 V (partial). Zig ports survey.** Codeberg `allyourcodebase` has 15 repos, none in this stack; the GitHub org has 130 public repos including abseil, curl, zstd, libiconv, win-iconv, libpng, json-c, libxml2, libssh2, mbedtls, libressl, boringssl, bzip2, c-blosc2, fast-lzma2 (`$LD/review/aycb-github-repos.txt`). No xz, libdeflate or libwebp there. AYCB zlib `main` needs zig 0.18.0-dev.469 and names output `z.lib`; AYCB sqlite3 fails on 0.17 (`no field named 'args'`); AYCB abseil builds both arches in 37 s but has no `absl_*.pc`; CIC proj exports 286 `sqlite3_*` symbols [zigports §2-3]. **Search outside AYCB, completed 2026-11-20 (V):** the first run stopped with `HTTP 403: API rate limit exceeded … q="sqlite zig"` (`$LD/zig-ports/ghsearch.txt:48`). It was re-run, paced, for sqlite, expat, tbb, onetbb, openssl, zlib, curl, zstd, libiconv, libpng, json-c, libxml2, qhull, libgeotiff, libjpeg-turbo and libtiff (`gh search repos "<lib> zig"`, `$LD/zig-ports/ghsearch2.txt`). New candidates: `dzfrias/openssl-zig` (22 stars, updated 2026-07-24; a reference for zig-openssl next to AYCB openssl), `Midstall/expat.zig` and `Midstall/zlib.zig` (0 stars, 2024-2025), `shreyassanthu77/libtiff-zig` (0 stars, 2025-09). The other hits are bindings, native Zig rewrites (sqlite, zstd) or tutorials. No hits for tbb, onetbb, libiconv, libpng, json-c, libxml2, qhull, libgeotiff or libjpeg-turbo. The search matches words in names and descriptions only, so it misses repos named only after the library (for example AYCB `zlib`); those are covered by the AYCB org listing. Codeberg-wide search outside AYCB is still not verified (the `repos/search` endpoint returned non-JSON). Conclusion unchanged: no GDAL, GEOS, PROJ or oneTBB port fit for reuse.

**F10 V. No upstream-zig conda package exists on universe.** `curl -sL --compressed https://prefix.dev/universe/<subdir>/repodata.json` for linux-64, win-64, win-arm64 and noarch (2026-11-20): the only zig-named packages are r-zig's own (`flang-rt-zig`, `flang-zig`, `lld-zig`, `r-zig-*`). The earlier failure was a `303` redirect to `packages.prefix.dev` that curl did not follow. D11 option A would need a new package. Note: universe already has `r-zig-toolchain`, so the new `zig-toolchain` name is close to it; they are different packages.

**F11 V. Stress expectations for the four packages.** `windows=` covers win-arm64 unless a `windows-aarch64=` key exists (`stress/stress.R:757-762`, r-zig-pixi origin/main): sf `fail-dependency` both arches, s2 `fail-abi` both, terra and gdalraster `fail-*` on win-64 and `ok` on win-arm64 via the Rtools fallback. Command: `git show origin/main:stress/packages.tsv` in r-zig-pixi.

**F12 V (review). Corrections folded into the design.** sqlite `-DSQLITE_OMIT_LOAD_EXTENSION=0` would remove extension loading (`src/loadext.c:22` uses `#ifndef`); Rtools' sqlite options taken verbatim (DESIGN §6.2). OpenSSL 3.6.0 `mingw64`/`mingwarm64` install into `lib64`/`lib-arm64` without `--libdir=lib` (`Configurations/10-main.conf`, `unix-Makefile.tmpl:330`). GDAL 3.12.1 disables iconv with `GDAL_USE_EXTERNAL_LIBS=OFF` (`CheckDependentLibraries.cmake:31`) and uses no OpenMP. abseil's `-march=armv8-a+crypto` is skipped for `CMAKE_SYSTEM_PROCESSOR ARM64` (`AbseilConfigureCopts.cmake:61`). Evidence: `$LD/CRITIQUE.md` H2, M1, M6, L2.

## M0 results

Dated 2026-11-20. `M0=/data/gamma/luciorq/workspaces/temp/r-zig-pixi/libs-m0` (logs `$M0/*.log`, rerun after review `$M0/r2-*.log`). `pixi.lock` sha256 `8849a4ea327f483c4d9a20fb053f3653ccbd2d857194dbce1df976daa9132b1e`, `pixi lock --check` up to date, unchanged by the review fixes. No git repo yet (no `.git`).

**Exit criteria:** 1 met; 2 met (`check-alignment` added 2026-11-21, M0-F18); 3 met; 4 met; **5 partly met**: the package tests (smoke built and run natively, relocated `.pc` paths exist) pass on win-64 hardware (kappa, M0-F17, both zigs' packages, plus a negative test); GitHub `windows-latest` and `windows-11-arm` runs are still to come (build.yml). win-arm64 can be verified only by the `windows-11-arm` runner: no win-arm64 host here, only its PE header (`0xaa64`) is checked; 6 met; 7 met. Status 2026-11-21: verified locally (linux: toolchain, cross builds both subdirs and both zigs, linux recipe tests, check-alignment with negatives, which-zig on real logs, actionlint/zizmor; M0-F13, F18-F21, F23) and on kappa (win-64 test step, M0-F17); awaiting the first GitHub run: every job of build.yml, both Windows runners, win-arm64 runtime.

| Package | Subdir | conda-forge zig 0.17.1 | upstream ziglang 0.17.1 |
|---|---|---|---|
| zig-toolchain 0.1.0 | linux-64 | build + tests ok (V) | build + tests ok (V) |
| zig-zlib 1.3.1 | win-64 | build + linux tests + smoke link ok; kappa run OK; build.yml test step on kappa OK (V, M0-F17) | build + linux tests ok; build.yml test step on kappa OK (V, M0-F17) |
| zig-zlib 1.3.1 | win-arm64 | build + linux tests + smoke link ok; runtime only on `windows-11-arm` (V/–) | build + linux tests ok; runtime only on `windows-11-arm` (V/–) |

**kappa (win-64) V.** `scp` of `zlib-smoke-x86_64.exe` to `C:\Users\admin\rz-libs-m0`, run: `zlib 1.3.1: 111 -> 74 -> 111 bytes` / `OK`, exit 0; dir removed (`REMOVED`). Done for the first and the post-review exe.

**Final packages** (`$M0/`):

| File | sha256 | Bytes |
|---|---|---|
| `out/linux-64/zig-toolchain-0.1.0-zig_69dc1b3_0.conda` | `ddcc26c9a7a1a0ec1b4efb888831f0d8dc5dc8746aa84849eda05f8bb6661525` | 147646 |
| `out/win-64/zig-zlib-1.3.1-zig_29ef852_0.conda` | `d56a55d267556408b22f13ebda50ec21282999a524c82d081dae5836e9e69278` | 104538 |
| `out/win-arm64/zig-zlib-1.3.1-zig_6e0c9c0_0.conda` | `4a817e7ffbf9ce35cb12709913794f5a44105103424d10dd8fb19e90a378661c` | 95502 |
| `out-upstream/linux-64/zig-toolchain-0.1.0-zig_69dc1b3_0.conda` | `9d97c192a417b1a1792616afb6a290b59e57ddfa7221b6f9fd04715309b1d57f` | 147622 |
| `out-upstream/win-64/zig-zlib-1.3.1-zig_29ef852_0.conda` | `3de4b7945c9fcbcb3899af836dd39a96deaf2c6a2083d9450dc6a0fb256e19bf` | 104486 |
| `out-upstream/win-arm64/zig-zlib-1.3.1-zig_6e0c9c0_0.conda` | `7ae6e8664d44f570363817f4ac21d94973cc2d2bc31709de4bc32524c84699f2` | 95469 |
| `smoke/zlib-smoke-x86_64.exe` | `bb37b14aca2b2744f51382ffc5d2120c420c6106dd9c1fc8bf6a762e92b3c0b7` | 287744 |
| `smoke/zlib-smoke-aarch64.exe` | `0fbb624f683a7dd6e154613380ebf3cc9036513624c6ffc0fad8341040e54984` | 250368 |

**Sizes (first build, before the review fixes) V:** `zig-toolchain` binary 416 KB stripped; `libz.a` x86_64 160972 B (upstream zig 159728 B), aarch64 144660 B. Envs: `default` 1.4 GB, `upstream-zig` 1.9 GB (`du`); `bin/zig` link count 1 (copies, I).

### Findings

**M0-F1 V. The whole path works on linux for both subdirs and both zigs.** `pixi run toolchain-test` 12/12; `pixi run build-toolchain`, `pixi run build zig-zlib win-64|win-arm64`, the same with `-e upstream-zig`, `pixi run test <pkg>` and `pixi run smoke zlib win-64|win-arm64` all rc=0 (`$M0/r2-*.log`). Toolchain tests: C, C++ and windres outputs for both triples have the right PE machine (`hello-aarch64.exe: aarch64`, …). Smoke exes: x86_64 / aarch64 (0xAA64); x86_64 imports only `api-ms-win-crt-*` and `KERNEL32.dll`.

**M0-F2 V. zig-zlib content and relocatable `.pc`.** Only `libz.a`, `zlib.h`, `zconf.h`, `lib/pkgconfig/zlib.pc`, licence under `Library/zig-libs/<zig triple>/`; no `*.dll`, `*.dll.a`, `*.lib`. `zlib.pc`: `prefix=${pcfiledir}/../..`; pkgconf in rattler's test prefix: `-L$PREFIX/Library/zig-libs/aarch64-windows-gnu/lib -lz`, dirs exist. `paths.json` has no `prefix_placeholder` entries, so `build.prefix_detection.ignore` was not needed (key spelling still A). Run export: weak `zig-zlib >=1.3.1,<1.4.0a0`.

**M0-F3 V. No `ignore_run_exports` needed for zig-zlib.** `info/index.json` has `"depends": []` on both subdirs with zig as a build requirement only.

**M0-F4 V. `ZIG_BIN` reaches the script via `env.get`.** Log: `zig-zlib: ZIG_BIN='.../.pixi/envs/upstream-zig/lib/python3.13/site-packages/ziglang/zig' zig version: 0.17.1`; all 34 `ZIG_TOOLCHAIN_TRACE` lines per build say `using .../ziglang/zig`. The upstream rendered recipe records `ZIG_BIN`; the published one has none.

**M0-F5 V. Both zigs give the same code.** 15/15 `libz.a` members per arch: all sections except `.debug$S` byte-identical; `.debug$S` holds S_OBJNAME (identical after M0-F6) and S_COMPILE3, which differs only by the clang ident (`clang version 22.1.8 (https://github.com/conda-forge/clangdev-feedstock 3cdb735d…)` vs `clang version 22.1.8`); 0 differences with the ident masked. Raw bytes differ (length fields). Headers and `.pc` identical.

**M0-F6 V. Absolute build paths leaked into `.debug$S` despite `-g0 -ffile-prefix-map`.** First build: `grep -c -a /data/gamma libz.a` → 15 (`.../out/bld/rattler-build_zig-zlib/work/_build/CMakeFiles/zlibstatic.dir/adler32.c.obj`). `-fdebug-compilation-dir=.` did not help. Fix D22: after it, `/data/gamma` 0, `/bld/` 0, `zig-libs.obj` 15 on both arches; recipe test greps for `rattler-build_`, `/bld/`, `zig-*-cache` (catches the old archive: 15 hits). Residual: without `-g0`, CodeView LF_BUILDINFO still records cwd, source path and cc1 line (V by the toolchain test).

**M0-F7 V. `zig objcopy` cannot handle PE/COFF.** `zig objcopy --strip-all a.exe` → `error: invalid elf file: InvalidElfMagic`. Before D23 the CMake toolchain files left `CMAKE_STRIP/NM/OBJDUMP/LINKER` to host discovery (`/usr/bin/strip`, …). DESIGN §4.3/§4.5 corrected.

**M0-F8 V. Both legs produce identical filenames and build strings** (`zig_29ef852_0`; `ZIG_BIN` is not a variant), and the default env inherited a caller's `ZIG_BIN` (`ZIG_BIN=/nonexistent/zig pixi run … → /nonexistent/zig`). Fixed by D24/D25; negative test with a fake zig printing 0.16.0: `zig-zlib: zig is 0.16.0, variants.yaml says 0.17.1`, rc=1. Upload guard deferred (D29).

**M0-F9 V. zig-toolchain was not in dependents' hash.** `info/hash_input.json` = `{"target_platform": "win-64", "zig": "0.17.1", "zlib_version": "1.3.1"}`. After D21 the build strings changed (toolchain `zig_f4184d7`→`zig_69dc1b3`; zlib `b13c51a`→`29ef852`, `e8243f5`→`6e0c9c0`).

**M0-F10 V. `-march=native` leaked host CPU features into cross builds.** `x86_64-w64-mingw32-cc -march=native -E -dM m.c | grep -c '__AVX2__ 1'` → 1. Fixed by D27 (unit + recipe test). The `-march=armv8-a+crc+crypto` → `-mcpu=generic+v8a+crc+crypto` rewrite works together with the default `-mcpu=baseline`.

**M0-F11 V. `-DCMAKE_PREFIX_PATH=<sub-prefix>` made `find_program` pick `<sub-prefix>/bin/perl`.** Probe with a fake sub-prefix: `PERL=.../fake/bin/perl`; without it `PERL=.../.pixi/envs/default/bin/perl` and still `ZLIB_FOUND=TRUE ZL=.../fake/lib/libz.a`. Fixed by D28 (build log line 105 has no PREFIX_PATH).

**M0-F12 V. Smaller defects found and fixed.** `pe-machine` u32 overflow on `e_lfanew=0xFFFFFFFE` → panic, now null (unit test); `tests/smoke/link.sh` failed on a missing smoke dir and leaked `work.*` dirs (now `mkdir -p` + EXIT trap); `! cmd` lines in `bash -e` test scripts never fail unless last, now `if …; then exit 1; fi`; the upstream leg had not built zig-toolchain itself (now does, into `output-upstream`). Not done: `check-alignment` subcommand (needed by M5, DESIGN §5.2); the zig-zlib sha256 is hard-coded, so a `zlib_version` change needs a sha256 edit; `<triple>-rc` always adds `/:target` (a duplicate is accepted by `zig rc`, exit 0).

### CI and check-alignment (2026-11-21)

Scratch `CI=/data/gamma/luciorq/workspaces/temp/r-zig-pixi/libs-ci` (logs `$CI/logs/`). Files: `.github/workflows/build.yml`, `.github/actions/which-zig/action.yml`, `toolchain/src/alignment.zig`, `tests/pkgtest.zig`; pixi tasks `build-libs`, `check-alignment`. `pixi.lock` unchanged (sha256 `8849a4ea…132b1e`, `pixi lock --check` up to date). Job graph: `toolchain` → `cross` (win-64, win-arm64 × env) → `test` (windows-latest win-64, windows-11-arm win-arm64 × env) and `alignment`.

**M0-F13 V. The linux part of build.yml runs locally, both zigs.** CI-like dirs (a fresh `LIBS_ZIG_OUT` holding only the toolchain's `linux-64/` and `noarch/`, as the artifact hands over): `pixi run build-toolchain` rc=0 (3m40s), `pixi run build-libs win-64|win-arm64` rc=0, the same with `-e upstream-zig` rc=0. In every zig-zlib test: `pkgtest: … all checks passed`, `zlib-smoke-x86_64.exe: PE machine 0x8664` / `zlib-smoke-aarch64.exe: PE machine 0xaa64`, `not run: host is linux-x86_64`. Build strings unchanged by this work: `zig_69dc1b3_0`, `zig_29ef852_0`, `zig_6e0c9c0_0`. Sizes: zig-toolchain `.conda` 217097 B (binary 557376 B; was 147646 B before check-alignment's JSON code), zig-zlib win-64 108985 B, win-arm64 107389 B (they now carry the two test files, M0-F16). `zig build test` 17/17 (5 new in alignment.zig); `zig test tests/pkgtest.zig` 2/2.

**M0-F14 V. `interpreter: bash` cannot serve a Windows test.** rattler-build v0.80.2 `crates/rattler_build_script/src/interpreter/bash.rs`: `search_scope` is `build_and_host_with_system_fallback()` only when the build platform is unix, else `build_only()`, so on Windows bash must be in the test's build env; `run_test.rs:1052-1066` resolves those requirements for `config.current_platform`. `m2-bash` (noarch) depends on `m2-conda-epoch`, which exists only in the win-64 and win-arm64 subdirs of conda-forge (repodata, 2026-11-21), so the linux test after the build could not solve it. Hence D31.

**M0-F15 V. conda-forge has what the Windows legs need.** Repodata 2026-11-21: `zig 0.17.1` win-64 `bd21d8f_0`, win-arm64 `d7e684b_0`; `pkgconf 3.0.11` both; `rattler-build 0.80.2` win-64 `he94b42d_0`, win-arm64 `hbd70cef_0`.

**M0-F16 V. What rattler-build stores of the tests.** The package holds `info/tests/tests.yaml` with only the script test (`cwd: etc/conda/test-files/zig-zlib/0`, requirements `zig ==0.17.1`, `pkgconf`) and the files `etc/conda/test-files/zig-zlib/0/zig-libs-tests/{pkgtest.zig,smoke/zlib.c}`; `package_contents` runs at build time only (`serialize_test.rs:123` drops it). Those two files are installed into every env that installs the package (outside the sub-prefix, under rattler-build's per-package test-files path).

**M0-F17 V. The win-64 Windows test step passes on kappa, and a failing test fails it.** build.yml's step run verbatim with Git bash (`"C:\Program Files\Git\bin\bash.exe" --noprofile --norc -eo pipefail`), pixi 0.84.2, `pixi exec --spec rattler-build==0.80.2`, caches and TEMP inside `C:\Users\admin\rz-libs-ci` (removed afterwards: `REMOVED`). The test env took conda-forge `zig 0.17.1 bd21d8f_0` and `pkgconf 3.0.11`; rattler-build ran the line through cmd.exe; output `pkgconf --cflags --libs zlib: -I%PREFIX%/Library/zig-libs/x86_64-windows-gnu/include -L%PREFIX%/Library/zig-libs/x86_64-windows-gnu/lib -lz`, both dirs exist, `zlib 1.3.1: 111 -> 74 -> 111 bytes`, `OK`, `all tests passed!`, ssh exit 0 — for the default package (sha256 `7a57f927…ecc0`) and the upstream-zig one (`23cf08bf…ed7a`). Negative: a scratch copy of the recipe asking for module `nosuchmodule` (`zig_29ef852_9`): `pkgtest: FAIL pkgconf --cflags --libs nosuchmodule: exited with code 1`, `failed to run test`, ssh exit 1. (cmd's `& echo %ERRORLEVEL%` printed 0 in both cases: parse-time expansion; the ssh exit code is the real one.) Criterion 5 is therefore met on win-64 hardware but not yet on GitHub's runners, and not at all on win-arm64.

**M0-F18 V. check-alignment on real channels.** CI-like artifact dirs `channels/channel-{linux-64,win-64,win-arm64}-default`: `build alignment OK: 2 package version(s) over 3 subdir(s)`, rc=0. Negatives, rc=1 each: a scratch build of zig-zlib win-arm64 with `number: 1` (`zig_6e0c9c0_1`): `problem: zig-zlib 1.3.1: build numbers differ across subdirs (win-64 _0, win-arm64 _1)`; the win-arm64 artifact left out: `problem: expected subdir win-arm64 is not among the inputs` and `zig-zlib 1.3.1: missing from expected subdir win-arm64`; an extra `.conda` copied into `win-64/`: `… is not in its repodata.json (stale index)`. The zig-toolchain recipe test runs the same three cases on hand-written repodata.

**M0-F19 V. pixi 0.84.2 runs `depends-on` entries with templated args in the order listed.** Scratch manifest with four `{ task = "build", args = ["<r>", "{{ subdir }}"] }` entries: `pixi run build-libs win-arm64` printed them in that order.

**M0-F20 V. rattler-build wraps log lines at about 160 columns unless `CI` is set** (`--wrap-log-lines` help: "automatically disabled on CI"). A local upstream log split the `ZIG_BIN=…` line; rebuilt with `CI=true` it did not, and the which-zig script then listed `zig-zlib: ZIG_BIN='…/.pixi/envs/upstream-zig/lib/python3.13/site-packages/ziglang/zig' zig version: 0.17.1 (…)` (rc=0 for env upstream-zig, rc=1 when told default), and `ZIG_BIN='' zig version: 0.17.1 ($BUILD_PREFIX/bin/zig)` for the default logs (rc=1 when told upstream-zig).

**M0-F21 V. Workflow linters.** `pixi exec --spec actionlint --spec shellcheck -- actionlint -verbose .github/workflows/build.yml` (actionlint 1.7.12, shellcheck 0.11.0): `Found total 0 errors`. `pixi exec --spec zizmor -- zizmor --offline` (1.32.0): 14 `unpinned-uses` (tags, D39) and 3 `self-repository` help notes on `uses: ./.github/actions/which-zig`; no template-injection, cache-poisoning or artipacked finding. `zig fmt --check` flags `toolchain/src/main.zig`, as it already did at 59f7431 (`git show HEAD:toolchain/src/main.zig | zig fmt --stdin --check` exit 1); not changed here.

**M0-F22 V (read). check-alignment does not mitigate R15 yet.** flang-pixi `scripts/check-build-alignment.py` reads the published universe channel (`from_universe()`, prefix.dev GraphQL) or a channel dir and compares it with `build-alignment.json` (`release`, `hotfixes`, `legacy`); that is what catches `--skip-existing` keeping a stale or partial set of subdirs. `zig-toolchain check-alignment` reads only the `repodata.json` of channels built in the same run; every subdir is built from the same recipe.yaml there, so rule 1 fires only for a per-platform `build.number` selector, and rule 2 reports what a failed cross leg already reports. The alignment.zig header now says so; the comparison with universe is D45 (before M5).

**M0-F23 V. Review fixes to check-alignment.** (a) A channel root whose subdir is a symlink was skipped (`if (e.kind != .directory) continue;`), giving `expected subdir win-64 is not among the inputs`; now `.sym_link` children are kept and `hasRepodata` still drops non-subdirs. Unit test `load: a channel root whose subdir is a symlink` (also a symlink to a file, skipped); `zig build test` 18/18. The crafted `c2` (`win-64 -> ../c2real/win-64`) now gives `build alignment OK: 1 package version(s) over 2 subdir(s)`, rc=0. (b) The task installs and runs the binary (D44): `--bogus` gives `unknown option --bogus` and rc=2; c1 (a version only in win-64) and c3 (`_0` vs `_1`) give rc=1 with no `failed command`/`Build Summary` lines; the CI-like `channels/channel-*-default` give `build alignment OK: 2 package version(s) over 3 subdir(s)`, rc=0. (c) Rebuilt after the fixes from a fresh `LIBS_ZIG_OUT` (`CI=true`, default env): `build-toolchain` rc=0 in 13m14s with a cold cache, recipe test `all tests passed!`, `zig-toolchain-0.1.0-zig_69dc1b3_0.conda` (build string unchanged); `build-libs win-64|win-arm64` rc=0, `pkgtest: all checks passed`, PE `0x8664`/`0xaa64`, `zig_29ef852_0`/`zig_6e0c9c0_0`; `pixi run check-alignment` on that dir rc=0. The upstream-zig leg was not rebuilt (alignment.zig and the task are not in its build path). actionlint 1.7.12 on the D43 workflow: `Found total 0 errors`; zizmor 1.32.0: 13 `unpinned-uses` (one upload fewer), 2 `self-repository`.

**Left for CONVENTIONS.md (not edited in M0):** per-machine env (`LIBS_ZIG_OUT`, `LIBS_ZIG_OUT_UPSTREAM`, `RATTLER_CACHE_DIR`, `ZIG_GLOBAL_CACHE_DIR`) and the D21 bump rule.

## Not verified

Resolved by M0: `env.get("ZIG_BIN")` (M0-F4); upstream ziglang building packages (M0-F1); `-march` rewrite with `-mcpu=baseline` (M0-F10).

- win-arm64 runtime of anything (only the PE header of `zlib-smoke-aarch64.exe` was checked); no win-arm64 host here, only `windows-11-arm` in build.yml will run the win-arm64 package tests.
- `rattler-build test --package-file` on GitHub `windows-latest` and `windows-11-arm` runners (M0 criterion 5). kappa (win-64) passed (M0-F17), so R1 is verified for win-64 under rattler-build 0.80.2 only.
- build.yml has not run on GitHub yet: every job, the `plan` job and the per-env toolchain matrix (D43; a failing leg leaving the other env's jobs running is inferred from GitHub's documented `needs` semantics, I), the `labeled` concurrency group, `cache-write`, the artifact layout of `pattern` downloads (`channels/<artifact>/`), Defender exclusions, `pixi exec` rattler-build on windows-11-arm, the upstream-zig legs (M0-F13 and M0-F17 are local and kappa runs of the same commands).
- The upstream-zig Windows legs link the smoke with conda-forge zig of the subdir, not upstream zig: the archives are upstream-built, the consumer link is not (R3 stays open).
- check-alignment against `.conda` files without a `repodata.json` (not supported, D36).
- check-alignment against the published universe channel (not implemented, D45): R15 has no automatic check until then.
- `build.prefix_detection.ignore` key spelling for `**/*.a` (A; not needed for zlib, M0-F2).
- No-op `strip` being enough for `cmake --install --strip` in a real project (A); no slice-1 library needing a real nm/objdump/objcopy through CMake (I).
- Build path still embedded when a build system drops `-g0` (I, M0-F6 residual).
- windres → `zig rc` inside a CMake RC build: zlib's DLL target built it, the DLL was deleted uninspected; `dlltool` covered by unit tests only.
- Meson cross files and autotools `--host` with the wrappers.
- `pixi run smoke` with the default `LIBS_ZIG_SMOKE`; `toolchain-test` without a `ZIG_GLOBAL_CACHE_DIR` override; whether rattler-build's path source copies `toolchain/.zig-cache` (40 MB) in a non-git dir.
- Pre-upload `ZIG_BIN` guard (D29); packages downloaded from universe.
- Any MinGW system import lib being present in both zigs (R10).
- Zig ports outside AYCB (F9 caveat); Codeberg-wide search.
- That free `windows-11-arm` runners require a public repo (I, GitHub policy not checked).
- Every CI time estimate (A); GDAL archive size (~100 MB guess, I).
- Licence IDs in DESIGN §5.8 (I until each recipe's files are read).

## Next steps

- **First CI run:** push a branch and open a PR (no label: default leg), then add the `upstream-zig` label for the gated leg; read every job (plan, toolchain × env, cross, test on `windows-latest` and `windows-11-arm`, alignment) and the which-zig summaries; record results, times and any fixes as M0-F24+ and close exit criterion 5 (win-arm64 runtime included).
- **M1:** zig-sqlite (Rtools option set, `PRAGMA compile_options` test), zig-expat, zig-openssl (`--libdir=lib`); plain smoke executables on both arches.
- **M2:** zig-geos, zig-proj, zig-abseil, zig-onetbb; smoke tests as `R CMD SHLIB` DLLs via r-zig-slim (D20); `llvm-nm` libc++ check; no `sqlite3_*` exported from `libproj.a`; multi-threaded `parallel_for`.
- **M3:** zig-gdal, all built-in drivers; closed `gdal.pc`; duplicate-symbol scan; licence inventory.
- **M4:** r-zig-pixi consumer branch (DESIGN §7): rzig sub-prefix lookup, `Rcmd_environ` pkg-config line, stress sysdeps and the zig-* build column, CXX-STDLIB.md amendment; sf/terra/gdalraster/s2 on both arches with both zigs.
- **Before M5:** check-alignment channel-URL input (D45, M0-F22).
- **M5:** publish preflight; Trusted Publisher registration (user); publish build 0 to universe; r-zig-pixi consumes from universe.
