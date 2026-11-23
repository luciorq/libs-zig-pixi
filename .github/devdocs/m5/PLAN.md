# m5: publish build 0 to universe (M5)

Started 2026-11-22 on top of main `4ef4e3c` (slice 1, PR #2). Design: `.github/devdocs/DESIGN.md` (9.1 item 5, 9.2 M5, R15, R16). Previous records: `m0/PLAN.md` (D1-D45; D29 pre-upload guard, D30 publish job, D45 check-alignment against the published channel), `slice1/PLAN.md` (D46-D78; D77 deferred items). DESIGN holds D79-D81. Decisions here continue at D82; findings are M5-F1 onward.

Tags: **V** verified, **I** inferred, **A** assumption.

Scratch: `S=/data/gamma/luciorq/workspaces/temp/r-zig-pixi/m5-scratch` (`$S/universe`, `$S/pins`, `$S/publish`, `$S/alignment`, and one `$S/review-*` per review). Input packages: CI run 44984149674 (slice 1, all green), artifacts `channel-<subdir>-<leg>`. `pixi.lock` unchanged, `pixi lock --check` up to date (V).

M4 (r-zig-pixi PR #51) is green with these packages on both Windows arches and both zigs: r-zig-pixi `feat-zig-libs` PLAN, findings 18-19.

## Goal

DESIGN 9.2 M5: publish build 0 of the ten packages (zig-toolchain for linux-64; nine libraries for win-64 and win-arm64) to universe from CI by trusted publishing (OIDC). Exit: the post-upload check lists every package in its subdir; r-zig-pixi CI is green when it takes them from universe; the stress zig-libs column shows the published builds.

## Scope

In:
- `.github/workflows/build.yml`: the `publish` job (D82-D85).
- `toolchain/src/alignment.zig`, `main.zig`, `pixi.toml` `[tasks.check-alignment]`: the comparison with universe (D86-D88).
- `variants.yaml`, `recipes/*/recipe.yaml`: exact build-tool pins (S1-F18, D89-D91).
- The pre-publish checks R16 (names) and upload size (D93, D94).

Out:
- The upload itself: a CI dispatch on main by the user after the Repository Access entry (Next steps).
- r-zig-pixi consuming from universe: after the upload, in r-zig-pixi.
- The other D77 items: one `proj.db` copy (S1-F11), json-c prefixing (S1-F10).

## Decisions

All dated 2026-11-22. "default" means the default, which the user may revisit. The user accepted every recommended option for D92 and D96-D98 ("All recommended").

| # | Question | Options | Choice | Reason | Who |
|---|---|---|---|---|---|
| D82 | Shape of the publish job | A one job on ubuntu-latest after `toolchain`, `cross`, `test`, `alignment`; downloads `channel-{linux-64,win-64,win-arm64}-default` from the same run by exact name; B upload in each cross leg (r-zig-pixi's form) | A | everything is cross-built on linux-64, so one job sees all three subdirs and uploads only after every test passed. An `if` with no status function makes every needed job count, including the upstream-zig leg on a gated dispatch | default |
| D83 | How the D29 guard tells the legs apart | A each `.conda`'s `info/recipe/rendered_recipe.yaml`: fail when `build.script.env.ZIG_BIN` is set, or when `build_prefix` is not under `$LIBS_ZIG_OUT/bld/`; B a new positive marker in the recipes; C the artifact names alone | A, behind C (download by exact name) | M5-F12: these are the only `info/` fields that differ between the legs; both markers fire on all 19 upstream-zig packages and on none of the 19 default ones. No recipe change needed | default |
| D84 | Post-upload check | A anonymous prefix.dev GraphQL: file name, platform, sha256, not hidden, not quarantined; 6 tries 20 s apart; fail on any mismatch; B flang-pixi's (file name only, API key); C GET `repodata.json` | A | M5-F13. OIDC leaves no stored key for B. The sha256 comparison turns a file kept by `--skip-existing` with other content into a failure | default |
| D85 | How publish runs rattler-build | A `pixi exec --spec rattler-build==$RATTLER_BUILD_VERSION`, as the `test` job; B a `publish` task in pixi.toml under `pixi run --locked` | A | the same pinned rattler-build as `test`; no locked env to install for one command | default |
| D86 | How check-alignment gets the published repodata | A `--published <channel-url-or-dir>`, fetched with zig 0.17.1 `std.http.Client` (TLS, redirects); a directory works too (tests, offline); B a local file only, fetched by curl | A | one tool and no extra shell. prefix.dev answers 303 to packages.prefix.dev and `fetch` follows it (V). The ReleaseSafe binary grows from 559,296 to 1,328,960 bytes, with no new dependencies | default |
| D87 | Rules against the published channel | per subdir, name and version, newest local build: below the published newest = problem; same number under another build string = problem; same file name = `published`, or `skip` when its sha256 differs; otherwise `new`. A URL must serve `noarch/repodata.json` (a typo gives 404, so exit 1); a missing subdir is empty; the v3 section (`v3.conda`) is read too | as stated | M5-F17, M5-F18. Universe keeps some records only under v3 | default |
| D88 | Where the channel URL lives | A default `published = https://prefix.dev/universe` in the pixi.toml task; B the CI step passes it | A | data in pixi.toml, as `--expect` (D36); CI's step is unchanged. Every alignment job now needs HTTPS to prefix.dev | default |
| D89 | How to pin build tools (S1-F18) | A one exact variants.yaml key per tool, required as `<tool> ==${{ <key> }}` in the recipes that run it; B bare-name auto-pinning; C leave unpinned | A | the pattern of `zig` and `zig_toolchain`; a key enters only the hashes of the recipes that use it (V: render) | default |
| D90 | Which versions | A those run 44984149674 resolved; B newest conda-forge | A: cmake 4.5.1, ninja 1.13.2, perl 5.44.0, make 4.4.1, sqlite 3.54.1 | the build M4 validated; the same in all four cross legs (M5-F19) | default |
| D91 | Test-only tools (pkgconf, llvm-tools) | A unpinned; B pinned | A | they do not touch the package files; a new version shows as a test result | default |
| D92 | Build number after the pins | A keep 0; B bump the changed recipes to 1 | A | the pins change 16 of 18 library build strings (M5-F20). Nothing is published, so no published build is shadowed; the bump rule (D4, D17) protects published packages | user, 2026-11-22 ("All recommended") |
| D93 | R16 name collisions | A closed by M5-F1/F2, with check-alignment's universe comparison at every run as the standing check; B a separate name check in the publish job | A | no zig-* name exists on universe or conda-forge; a later collision on universe shows in the alignment table | default |
| D94 | Upload size guard | A none; B a guard | A | the largest file is 16,903,152 bytes; universe already holds 205,764,157-byte files (M5-F3). The documented ceiling is 5 GiB, below it the plan's limit | default |
| D95 | `zig fmt` failure in `toolchain/src/main.zig` at HEAD | A fix here; B separate | A | formatting only (M5-F21) | default |
| D96 | A rebuilt package under an already published file name (`skip`), R15 | A before any upload, compare each already published file's recipe files with this run's: the same, leave it published (not uploaded, no failure); different, fail before uploading (recipe changed without a bump); upload and verify only the new file names; B fail on any already published file; C warn only | A, as a shell step in the publish job ("New or published with the same recipe"): `info/recipe/` without `rendered_recipe.yaml` and `variant_config.yaml`, plus the sha256 of the test files (`etc/conda/test-files/`, from `info/paths.json`) | M5-F22, M5-F24: catches R15 without byte-reproducible builds; check-alignment and the publish job then agree. Shell, not a zig subcommand: about 55 lines with the guard's tools (unzip, tar, curl, diff); in zig it would need zip, zstd and tar reading and the publish job would have to build the toolchain | user, 2026-11-22 ("All recommended") |
| D97 | zig-gdal finds the runner's `/usr/bin/pkg-config` and `/usr/bin/bison` | A disable both in `recipes/zig-gdal/build.sh` (as D78 did for SWIG); B pin pkgconf as a build requirement, leave bison; C record and defer | A, with an empty `PKG_CONFIG_EXECUTABLE` in place of `CMAKE_DISABLE_FIND_PACKAGE_PkgConfig` | M5-F23, M5-F26: GDAL calls `pkg_check_modules` without checking that pkg-config was found, so disabling PkgConfig breaks its configure | user, 2026-11-22 ("All recommended"); the variant is the default |
| D98 | Repository Access entry on universe | A owner luciorq, repo libs-zig-pixi, workflow `build.yml`, no Environment, Read/write; B the same plus a GitHub Environment `publish` with required reviewers | A | r-zig-pixi's entry (workflow `build.yaml`) does not cover this repo (M5-F15) | user, 2026-11-22 ("All recommended"); the entry was added by the user in the prefix.dev UI on 2026-11-22 (not readable without channel auth, A) |
| D100 | zig-toolchain's path source (`toolchain/`) is not in `info/recipe`, so D96 cannot see a change to it | A the rule of variants.yaml (from the first publish on, a change to `toolchain/` bumps `zig_toolchain`, a new file name, M0 D37); B also compare the payload sha256 of its text files | A | the version bump already gives a new file name; the binary is not byte-reproducible | default |
| D101 | Hardening of the D96 step from the review | A a 404 after a redirect is an error, not "new"; the test-file list is sorted; B leave | A | a published file answers 303 to packages.prefix.dev, so a 404 there is a CDN error (V: live `404/0` for an unpublished file, `200/1` for a published one) | default |
| D99 | Release switch | A `vars.CONDA_PUBLISH` as r-zig-pixi: set, dispatch on main, delete; B dispatch input; C every push to main | A | the same procedure as r-zig-pixi (M5-F16) | default |

## Findings

### Pre-publish checks

**M5-F1 V. No name collision on universe.** `curl -sSL --compressed https://prefix.dev/universe/<subdir>/repodata.json` for noarch, linux-64, win-64, win-arm64, osx-arm64, linux-aarch64, osx-64: 0 records named zig-toolchain or zig-{zlib,sqlite,expat,openssl,abseil,onetbb,geos,proj,gdal}, in `packages`, `packages.conda` and v3. Its zig-related names: flang-rt-zig, flang-zig, lld-zig, r-zig-*. Universe also holds other projects' packages (blast, polyglot, tradetracker).

**M5-F2 V. No name collision on conda-forge.** `channeldata.json` (35,148 packages, newest 2026-11-22 21:38 UTC) has none of the ten names; its zig names are zig, zig-compiler, zig_impl_<subdir>, zig_<subdir>.

**M5-F3 V. Upload size.** prefix.dev documents 1 GiB in the browser and, for CLI/API uploads, "the package-size and storage limits for the channel's plan, subject to the backend's 5 GiB absolute ceiling" (prefix.dev/docs/prefix/channels/publish-packages). Universe already holds win-64 flang-zig-23.1.1-zig_0ff6bf8_6.conda, 205,764,157 bytes. Who uploaded it and how is not shown in repodata.

**M5-F4 V. Package sizes, run 44984149674, default leg** (bytes). win-64, 32,544,313 in total: zig-gdal 16,903,152; zig-proj 5,397,780; zig-openssl 4,264,891; zig-geos 2,898,431; zig-abseil 1,389,522; zig-sqlite 962,239; zig-onetbb 462,975; zig-expat 153,055; zig-zlib 112,268. win-arm64, 31,209,230 in total (zig-gdal 15,902,793). linux-64: zig-toolchain 218,589. All build 0, `zig_<hash>_0`. Each artifact also carries `<subdir>/repodata.json` and `noarch/repodata.json`, which are not uploaded (the job takes `<subdir>/*.conda`).

**M5-F5 V. Trusted publishing.** prefix.dev now calls it Repository Access (prefix.dev/docs/prefix/channels/access): channel Settings, Repository Access, GitHub; owner, repository, workflow file name, an optional GitHub Environment (exact match), an access mode (Read/write or more to upload). There is no branch field. The workflow needs `permissions: {contents: read, id-token: write}`; `rattler-build upload prefix --channel universe` with no key uses OIDC (rattler-build 0.80.1 `--help`; r-zig-pixi publishes `_11` this way).

### Publish job

**M5-F12 V. The marker between the legs.** Run 44984149674, `channel-{win-64,linux-64}-{default,upstream-zig}`, `info-*.tar.zst` extracted and compared with `diff -r`: the upstream-zig leg's `rendered_recipe.yaml` has `ZIG_BIN: /home/runner/work/libs-zig-pixi/libs-zig-pixi/.pixi/envs/upstream-zig/lib/python3.13/site-packages/ziglang/zig` under `build.script.env`; the default leg has no `ZIG_BIN` (the empty `env.get` default is dropped). `build_prefix` is under `out/<leg>/bld/`. Otherwise `about.json` differs in the channel path, `index.json` in the timestamp, `paths.json` in sha256; file names and build strings are the same (M0-F8). The guard step, taken from the YAML and run under `bash -eo pipefail` with a real `unzip`: default leg exit 0, 19 files; upstream-zig leg exit 1, 19 `::error::` lines naming both markers (review re-run, `$S/review-publish`).

**M5-F13 V. The post-upload check.** prefix.dev GraphQL answers read queries on universe without a key; `PackageVariant` has filename, platform, sha256, hidden, activeQuarantines. The step on the 19 unpublished files: MISSING, exit 1. On the published `r-zig-slim-4.6.2-hc365614_11.conda` (win-64, downloaded from repo.prefix.dev): ok, exit 0. On a copy with one byte appended: OTHER CONTENT, exit 1.

**M5-F14 V. Validation.** `yaml.safe_load` ok; `publish` has `{contents: read, id-token: write}` and the workflow default stays `contents: read`; actionlint 1.7.7 with shellcheck 0.10.0: exit 0 apart from the existing `windows-11-arm` label (unknown to that actionlint version).

**M5-F15 I. r-zig-pixi's Repository Access entry does not cover this repo**: matching uses the repository and the workflow file, and this one is `build.yml`. Which entries exist cannot be read without channel auth (A).

**M5-F16 V. r-zig-pixi's release procedure** (its build.yaml, job conda-package): `permissions` contents read and id-token write, no `environment:`, step `if: github.ref == 'refs/heads/main' && (push || workflow_dispatch) && vars.CONDA_PUBLISH == 'true'`, then `rattler-build upload prefix --channel universe --skip-existing dist/conda/<subdir>/*.conda`; set the variable, dispatch on main, check, delete the variable.

Low items from the review, not changed (I): the guard reads only `<subdir>/*.conda`, so a future noarch package would be neither uploaded nor flagged (none exists); the check asks for at most 100 variants per package and does not page; a transient GraphQL error is not retried inside the loop (the job fails, and a rerun is safe); the `build_prefix` marker assumes the publish runner has the cross runners' workspace path (true on hosted ubuntu); the step greps "already exists", the wording in the rattler-build 0.80.1 binary, while CI uses 0.80.2.

### check-alignment against universe

**M5-F17 V.** `https://prefix.dev/universe/<subdir>/repodata.json` answers 303 to `packages.prefix.dev/.../repodata.json`; a missing subdir (win-32) and a missing channel both answer 404.

**M5-F18 V. Runs.** `zig build test`: 29/29 (23 before). Run 44984149674's default channels against live universe: 19 `new`, exit 0. A copy as the published channel: 19 `published`, exit 0. A simulated trap (one hash changed, one sha256 changed, one published build number 1): 2 problems and 1 `skip`, exit 1. A misspelled channel: exit 1. The review also ran a fake r-zig-toolchain channel against live universe and got the expected problem row, so `19 new` is not an empty read.

Low items from the review (I): a package with several variants per subdir at one build number would read as "two builds with one number" (none today); the fetch has no timeout, so a stalled prefix.dev blocks the alignment job until its timeout.

### Build-tool pins

**M5-F19 V. Tool versions.** Run 44984149674 resolved, in all four cross legs: cmake 4.5.1 hff7ac6b_0, ninja 1.13.2 h171cf75_1, perl 5.44.0 1_h7cc23a3_perl5, make 4.4.1 h1114479_4, sqlite 3.54.1 h9ffa6c4_0; test-only pkgconf 3.0.11, llvm-tools 23.1.6 (`gh run view --log`, `$S/pins/run.log`).

**M5-F20 V. Hash changes.** Renders of the original files give CI's build strings exactly, so the comparison is valid. After the pins (rattler-build 0.80.2 `--render-only`), win-64 / win-arm64: zig-zlib 29ef852→a5ccd49 / 6e0c9c0→5eb7c11; zig-expat 7fcb7fd→316815f / 2b3eccd→cc735f7; zig-openssl 436c1ea→8df055f / daa5ad0→e42cee8; zig-abseil 2e57825→c679942 / 90e5f06→185da94; zig-onetbb d03d386→d45494d / 2163197→fe476b5; zig-geos 573ba6a→dc362a3 / e4446d8→89cf0f7; zig-proj 4f71b06→81cc97b / 776cbfe→8278fcb; zig-gdal d646007→85e8ffa / e59a93e→8d757d0. Unchanged: zig-sqlite (no pinned tool), zig-toolchain. A real win-64 zig-zlib build resolved cmake ==4.5.1 and ninja ==1.13.2 and passed its tests (`$S/pins/out/win-64/zig-zlib-1.3.1-zig_a5ccd49_0.conda`). openssl (perl, make) and proj (sqlite) were only solve-rendered: CI is their first real build with the pins.

Side note (V, probe recipe): rattler-build exports a used variant key to the build script as a lower-case variable (`make=4.4.1`). OpenSSL's Makefile uses `$(MAKE)`, so it is harmless there (I).

**M5-F21 V.** `toolchain/src/main.zig` failed `zig fmt --check` at HEAD 4ef4e3c (a StaticStringMap table layout). Reformatted (D95); `zig fmt --check src` and `zig build test` pass.

### D96 and D97

**M5-F24 V. Which `info/` files differ between two builds of one recipe.** Run 44984149674, all 19 packages, default against upstream-zig leg: only `about.json` (channel path), `index.json` (timestamp), `paths.json` (sha256) and `info/recipe/rendered_recipe.yaml` (prefixes, timestamp, the runner's virtual packages). `recipe.yaml`, `build.sh`, patches, `variant_config.yaml`, `hash_input.json`, `run_exports.json`, `tests/tests.yaml` and `licenses/` are the same. `variant_config.yaml` holds the values of `hash_input.json`, already in the file name. The D96 step, taken from the YAML and run under `bash -eo pipefail` against a local HTTP server: empty channel, 19 new; the upstream-zig leg's 19 files as the published side, 19 "published, same recipe" and nothing to upload; published copies with `build.sh` changed (zig-zlib), the patch removed (zig-gdal) and one test-file sha256 changed (zig-proj), exit 1 with three `::error::` lines and one new file; no `noarch/repodata.json`, exit 1. Re-run after D101: the same results. Not seen: the build output, so a change that ships only as output needs the bump rule (D100). A change to the shared `tests/pkgtest.zig` changes every library's test files, so every published library then needs a bump (I).

**M5-F25 V. universe downloads need no login.** `repo.prefix.dev/universe/<subdir>/<file>` answers 303 to a signed `packages.prefix.dev/<n>/<sha256>` URL for a published file and 404 for an unpublished one or a missing subdir.

**M5-F26 V. D97 in `recipes/zig-gdal/build.sh`.** `-DCMAKE_DISABLE_FIND_PACKAGE_BISON=ON`: bison serves only the `generate_swq_parser` and `generate_ods_formula_parser` targets (not built by default; GDAL 3.12.1 ships the generated parsers); the `check_*_md5` targets only hash files. `-DPKG_CONFIG_EXECUTABLE=`: `FindEXPAT.cmake:40-42`, `FindZSTD.cmake:39-40` and `Findmuparser.cmake:22-23` call `pkg_check_modules` unconditionally, and cmake 4.5.1 with `CMAKE_DISABLE_FIND_PACKAGE_PkgConfig=ON` fails with `Unknown CMake command "pkg_check_modules"` (minimal project). gamma, win-64, with the pins: `zig-gdal-3.12.1-zig_85e8ffa_0`, "Could NOT find PkgConfig (missing: PKG_CONFIG_EXECUTABLE)", no BISON line, no search for `PKG_CONFIG_EXECUTABLE` or `BISON_EXECUTABLE` in `CMakeConfigureLog.yaml` (the unfixed recipe searched both, `/usr/bin` included), pkgtest "all checks passed", "all tests passed". The found/not-found lines and the feature summary differ from the unfixed build only by BISON, so no library or driver changed. The hosted runner's lines are I until CI.

**M5-F27 V. The build script does not get the caller's PATH.** CMake's `ENV{PATH}` in the cross build is `build_env/bin`, the host env directories, then `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`; the caller's `.pixi/envs/default/bin` is not in it. A fake tool on the caller's PATH is never seen, which explains the S1-F22 local result (the fake swig was never called); only tools in the fixed system directories leak, where the runner has swig, pkg-config and bison. GDAL also looks for other optional host programs (geos-config, curl-config, ccache, ...); none was seen found on the runner, recorded only.

**M5-F28 V. PR #4 CI, run 45090398767 (head 4e9b4e4, `upstream-zig` label), 13 jobs: 12 success, publish skipped (pull request).** All four cross legs built every recipe with the pins: cmake 4.5.1, ninja 1.13.2, perl 5.44.0, make 4.4.1, sqlite 3.54.1, so zig-openssl and zig-proj now built for real with them. zig-gdal in each of the four legs: "Could NOT find PkgConfig (missing: PKG_CONFIG_EXECUTABLE)", no "Found PkgConfig" and no "Found BISON" line (M5-F23 fixed on the runner). Each test job: "9 package(s) tested, 0 failed". check-alignment against `https://prefix.dev/universe`: 19 rows `new`, build strings as in M5-F20 (win-64 zig-gdal `zig_85e8ffa_0`, zig-sqlite unchanged `zig_1d5992e_0`, ...), "published comparison OK: 19 new, 0 already published". main push run 45090570843 (the PR #3 merge, default leg only): 7/7 success.

### Open

**M5-F22 V (settled by D96). `skip` was passed by check-alignment but failed by the publish check.** The build string is `zig_${{ hash }}_${{ build_number }}` and the hash covers the variant keys, not the recipe text or build.sh. A rebuild of an already published package keeps its file name; its sha256 differs unless the build is byte-reproducible (not measured, A). check-alignment reports that as `skip`, exit 0; the publish job uploads with `--skip-existing`, then its sha256 check fails for that file. A recipe change made without a bump looks the same, which is R15 itself. D96 settles it.

**M5-F23 V. zig-gdal finds host tools.** In all four cross legs GDAL's CMake found `/usr/bin/pkg-config (2.5.1)` and `/usr/bin/bison (3.8.2)` from the runner (run.log lines 11839, 25235, 38635, 51917, with the matching "Found BISON" lines). Neither is a build requirement. Same class as S1-F22 (swig, D78). pkg-config serves only optional dependencies that are not found, and the toolchain activation sets `PKG_CONFIG_LIBDIR` to the sub-prefix; bison only ran an md5 check, so the output is probably the same (I). A machine without them takes another path (A).

## Tests

gamma, 2026-11-22, worktree `wt/libs-m5`:

- `zig fmt --check src` (toolchain): ok. `zig build test --summary all`: "3/3 steps succeeded; 29/29 tests passed".
- `pixi lock --check`: ok; `pixi.lock` untouched.
- check-alignment, publish guard and verify steps, renders and the zig-zlib build: as in the findings above.

CI: run 45090398767 (M5-F28). Not run: OIDC, the upload, the D96 step against live universe with published files.

## Next steps

1. Done: D96, D97 (and D100, D101).
2. Done 2026-11-23: PR #4, CI 45090398767 green with the `upstream-zig` label (M5-F28).
3. Done 2026-11-22: the user added the Repository Access entry (D98). The first publish run proves it.
4. After merge: `gh variable set CONDA_PUBLISH --body true -R luciorq/libs-zig-pixi`, `gh workflow run build.yml -R luciorq/libs-zig-pixi --ref main`, read the publish job's table, `gh variable delete CONDA_PUBLISH -R luciorq/libs-zig-pixi`.
5. r-zig-pixi: the zig-* packages from universe (pixi.toml, lock), `--libs-channel` dropped from CI, the stress column shows the published builds.
