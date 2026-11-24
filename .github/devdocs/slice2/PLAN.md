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

## Decisions

All dated 2026-11-23. The user accepted every ★ option of the brief
(D102A, D103A, D105A, D106A, D107A) and changed D104 (A with an early
per-library fallback, text below).

| # | Question | Options | Choice | Reason | Who |
|---|---|---|---|---|---|
| D102 | Verifying unpublished builds now that r-zig-pixi consumes only published ones | A first add DESIGN.md 9.1 item 4, the `r-consumer` job: r-zig-slim from universe plus this run's channels (`pixi exec`), R packages from source, `tests/r/smoke.R` extended per library; B pkgtest only, r-zig-pixi finds breakage after publishing; C a staging channel on prefix.dev | A | breakage is found before a publish, inside this repo (CONTRACT.md 7) | user |
| D103 | Order | A leaves first: {gmp, mpfr, glpk}, {nlopt, udunits2}, gsl, libpq, the text stack {freetype, fribidi, harfbuzz, libpng, libtiff, libjpeg, libwebp}, libxml2, then the data stack {libaec?, hdf5 1.12.x, curl, netcdf}; B by rows unblocked; C data stack first | A | each batch only needs packages that exist; the riskiest stack comes last, on a proven path | user |
| D104 | Autotools cross builds (gmp, mpfr, glpk, gsl, udunits2) | A a toolchain `configure` helper, proved on gmp first; B the library's cmake port; C a zig build.zig port | A with an early per-library fallback to C (a zig build.zig port, Codeberg only) or B (a cmake port), whichever is maintained and closer to upstream. The helper stays for the libraries where it works cleanly. Each fallback is its own decision here, with its trigger and evidence | simplicity-first: stop before workarounds pile up | user |
| D105 | GPL redistribution (gsl, glpk GPL-3; gmp, mpfr LGPL-3+) | A ship with licences in `licenses/<pkg>/` as conda-forge does, record it in DESIGN.md; B leave the GPL ones on the tree | A | conda-forge ships the same libraries the same way; the consumer R packages that link them (gsl, igraph, Rmpfr) are GPL themselves | user |
| D106 | Release cadence | A publish per batch (PR, publish, handover each); B one publish at the end | A | r-zig-pixi moves stress rows off the tree batch by batch | user |
| D107 | D77 leftovers (`proj.db` shipped twice; json-c prefixing) | A proj.db in the first batch PR with a zig-proj bump; json-c when netcdf or libxml2 brings one; B a separate PR first | A | no extra publish for a small fix | user |
| D108 | Where the D104 helper lives, and what its toolchain change costs | A a `zig-toolchain configure` subcommand (configure.zig), so `zig_toolchain` goes 0.1.0 -> 0.2.0 and every published library is rebuilt as build number 1 in the batch-1 publish (D100, D87: same number under a new build string is an alignment problem); B a shell function in each recipe's build.sh (no toolchain bump, the fence copied per recipe); C a separate package for the helper | A | prefer Zig, one place for the fence (simplicity-first); the rebuild costs one CI run and changes no archive content (I) | default, user may revisit |
| D109 | How libtool learns the linker is GNU-compatible (S2-F8) | A the helper sets `lt_cv_prog_gnu_ld=yes` for every library (one fixed answer, true for zig/lld) and keeps the failing LD stub; B a `<triple>-ld` stub that prints a GNU-compatible `-v` line and still refuses to link; C leave LD unfenced (the build machine's `/usr/bin/ld` answers; a host without binutils gets libtool's MSVC branch) | A | B fakes a tool's identity; C is the host leak D104 forbids. The answer is the same for every library, so it does not "grow" per library (D104) | default, user may revisit; no r-zig conflict (S2-F10) |
| D110 | glpk on MinGW: the autotools build takes GLPK's POSIX code (`gmtime_r`, `strerror_r`, a 32-bit `tv_sec` passed as `time_t*`) | A `CPPFLAGS=-D__WOE__`, GLPK's own switch for its Windows code, plus `--with-gmp`: CRAN's Rtools45 archive is this code (S2-F12); B MSYS2's source patches (`__WOE__` -> `_WIN32` in stdc.c, the timeval fix); C a D104 fallback (no zig port of glpk exists, S2-F7, and a cmake port would need the same choice) | A | no patch and no cache answer, so not a D104 trigger; CRAN parity, `DllMain` included | default, user may revisit |
| D111 | Which zig ports count for the D104 fallback C, after S2-F4/F5 (the brief's premise "GitHub AYCB unmaintained, moved to Codeberg" did not hold) | A a maintained port on any host (GitHub, AYCB included, or Codeberg), pinned to a commit; B Codeberg only (as briefed); C no ports, fallback B or our own build.zig only | A | the facts: Codeberg's AYCB org has none of these libraries, GitHub's AYCB repos get commits; any port needs our `.pc` anyway (S2-F6) | user ("continue with recommended") |
| D112 | `proj.db` shipped twice (D77, S1-F11; D107 put it in this batch) | A keep both, close D77's item; B embed off, `share/proj` only (PROJ then needs PROJ_DATA: a contract change); C embedded only (sf, terra, gdalraster copy `share/proj`) | A | CONTRACT.md 2 promises both (`share/proj` and no PROJ_DATA needed); zig-proj changes only by the D108 rebuild | user ("continue with recommended") |
| D113 | How the r-consumer job (D102) tests R packages | A own harness: a pixi env of this run's channel, universe, conda-forge with r-zig-slim, r-zig-toolchain, the zig-* libraries and conda-forge sysdeps; `tests/r/install.R` (source installs) then `tests/r/smoke.R`; per-arch package lists (sf skips win-arm64 until zig-udunits2, batch 2); default leg first; B r-zig-pixi's stress.R pinned to a commit; C no r-consumer for batch 1 | A | no CI dependency on the consumer repo; the stress suite stays r-zig-pixi's (CONTRACT.md 7) | user ("continue with recommended") |
| D114 | r-consumer while universe's r-zig (build 11) predates the zig-libs search (S2-F13; r-zig build 12 unpublished, no date: the r-zig-pixi user batches the release) | A report-only (`continue-on-error`) plus the r-zig-pixi session's emulation of build 12 in the job (PKG_CONFIG_PATH, R_MAKEVARS_USER -I/-L, R_TOOLS_SOFT); flip to required and drop the emulation when build 12 is on universe; B report-only, no emulation (no signal until build 12); C hold the batch-1 publish until build 12 | A | signal now (S2-F14: it works on kappa); nothing blocks on the other repo's release; the r-zig-pixi session's first preference is report-only, emulation its option 2; it asked not to build r-zig from its main | default, user may revisit |
| D115 | CI build time (S2-F23): reuse what has not changed | A a shared zig global cache per job, kept between runs (activation honours `LIBS_ZIG_CACHE`, passed by each recipe's `env.get`; pkgtest and the test command use zig's per-user cache), in this PR while zig-toolchain 0.2.0 and the build-1 bumps are unpublished; then, in its own PR, build only what universe lacks (`--skip-existing=all`, the D96 recipe check moved to the start); B the skip only; C the cache only; D prototype both first | A | the cache needs a toolchain and test-file change that is free before the batch-1 publish; archives stay byte-identical (S2-F23) | user ("Apply the recommended", 2026-11-24) |
| D116 | r-consumer once r-zig build 12 is on universe (D114's exit condition; r-zig-pixi session message 2026-11-24: build 12 published, release run 45381914199, pre-merge stress 45305358893 ok for sf, terra, gdalraster, lwgeom, s2 on both Windows arches) | A drop the D114 emulation (the appended Rcmd_environ lines, the user Makevars) and `continue-on-error`, pin r-zig-slim and r-zig-toolchain to `4.6.2 *_12`; B keep it report-only one more batch | A, dated 2026-11-24, in the batch-2 PR (#8) so its run is the first with the job required | D114 said to drop both with build 12; the pin keeps an older r-zig from being picked, where the job would fail for a reason not in this repo | mine (D114 exit), on the r-zig-pixi session's request |
| D117 | Fence the host gfortran that udunits' `AC_PROG_FC` finds on the GitHub runner (S2-F24) | A `FC=no F77=no` on zig-udunits2's configure line only, the helper fence later; B the same two fences in `zig-toolchain configure` now; C helper fence after a batch-1 publish (12 libraries to build 2) | B, dated 2026-11-24 (first A; B once D118 removed the batch-1 publish: zig-toolchain 0.2.0 is unpublished, so the fence changes no version and no build string) | one fence for every autotools library (hdf5 and netcdf come with optional Fortran parts); UDUNITS-2 has no Fortran API ("No Fortran or Perl API", udunits2.texi; lib/ builds C only), so the fence drops nothing; gmp, mpfr, glpk, gsl probe no Fortran | mine, after the user's D118 |
| D118 | Release cadence for the rest of slice 2 (replaces D106A) | A publish per batch (D106); B one PR for all remaining slice-2 work, one publish at the end | B, dated 2026-11-24 | user: "We don't need to publish anything now. Let's fold all ongoing work on a single PR with all builds we have in our ongoing list." Batch 1 (merged, PR #7) stays unpublished; PR #8 (branch feat-slice2-batch2) carries batch 2 and the D103 rest (gsl, libpq, the text stack, libxml2, the data stack); one handover to r-zig-pixi after that publish | user |

D104 in the user's words: "As soon as cross-compiling a library with
autotools gets tricky, stop and switch that library to another path
instead of piling on workarounds." Tricky is any of:

- upstream configure or Makefile files need patching;
- cache answers keep growing from one attempt to the next;
- host tools leak in that cannot be cleanly fenced off;
- the build-machine helper programs (CC_FOR_BUILD) need special handling;
- for gmp, the assembly needs workarounds beyond `--disable-assembly`.

Port search (user, with D104): the AYCB GitHub repositories are
unmaintained and moved to Codeberg; search the AYCB Codeberg org's full
repo list and all of Codeberg per library, then GitHub outside AYCB
(authenticated), for the slice 2 libraries plus DESIGN.md 6.4's; per hit:
last commit date, zig version targeted, upstream version wrapped, `.pc`
or CMake files installed. Results are S2-F findings; DESIGN.md 6.4 says
ports are pinned to Codeberg commits.

## Findings

**S2-F1 V. Rtools45 build 6768 aarch64 versions** (the tree's `.pc`
files, `next/probe-rtools/closedpc/` in the r-zig-pixi scratch,
`rtools45-toolchain-libs-full-aarch64-6768`): gmp 6.3.0, mpfr 4.2.2, glpk
5.0, gsl 2.7.1, nlopt 2.10.0, hdf5 1.12.1, netcdf 4.9.2, libpq 16.10,
harfbuzz 12.3.0, freetype2 26.4.20 (freetype 2.14.x), fribidi 1.0.16,
libpng 1.6.54, libtiff 4.7.1, libjpeg 9.6.0 (IJG jpeg 9f, not
libjpeg-turbo), libwebp 1.6.0, libxml2 2.12.10, libcurl 8.18.0. No
udunits2 or libaec `.pc` in the tree. These are the D9-style version
targets (CRAN parity).

**S2-F2 V. gmp 6.3.0 cross-configures with autotools, no patch, no cache
answer (2026-11-23, manual run on gamma).** Script
`/data/gamma/luciorq/workspaces/temp/libs-zig-pixi/slice2/try-gmp.sh`,
PATH = zig-toolchain wrappers + zig + `/usr/bin:/bin`; source sha256
`a3c2b802...538898` (ftpmirror.gnu.org; gmplib.org answered a 158-byte
error page to curl). `--build=x86_64-pc-linux-gnu --host=<triple>
--disable-shared --enable-static --disable-assembly`, `CC_FOR_BUILD="zig
cc"`:
- aarch64-w64-mingw32: configure and `make -j16` pass (24 s); 516
  objects, `pe-machine` aarch64; the gen-* programs ran through `zig cc`
  (make.log).
- x86_64-w64-mingw32: configure needs `m4` even with
  `--disable-assembly` ("No usable m4"; gamma has none on the host), and
  then runs GMP's x86 assembler probes, which read an object with `nm`
  ("cannot determine how to define a 32-bit word" with the toolchain's
  nm stub). With conda-forge m4 1.4.21 and `NM=llvm-nm` (llvm-tools
  23.1.6): configure and make pass, objects x86_64. Neither is a patch
  or a cache answer, so not a D104 trigger: m4 and llvm-tools are pinned
  build tools (variants.yaml), NM is set by the helper for every
  library.
- `--enable-cxx` (Rtools45 ships libgmpxx and gmpxx.pc, S2-F1's tree):
  both arches build and install `libgmp{,xx}.a`, `gmp{,xx}.h`,
  `gmp{,xx}.pc` (no `-lstdc++`; gmpxx.pc `Requires: gmp`), plus `.la`
  files and `share/info` (removed by build.sh).
- libtool's host probes: `as` -> `/usr/bin/as`, linker `/usr/bin/ld`, `mt`
  -> `/usr/bin/mt`. None ran in the static build (make.log has no `as`
  or `ld` call); the helper still points AS/LD at failing stubs and
  MANIFEST_TOOL at `false`, so a later use fails loudly.
- The manual run left 4 objects (`doprnt`, `doscan`, `pprime_p`,
  `randlc2x`) with the absolute source path from `ASSERT_ALWAYS`'s
  `__FILE__`; the activation's `-ffile-prefix-map=$SRC_DIR=.` (absent in
  the manual run) maps it; pkgtest check 3 verifies it in the recipe.

**S2-F3 V. Build-tool versions conda-forge resolved 2026-11-23** (`pixi
exec --spec m4 --spec make --spec llvm-tools`): m4 1.4.21, make 4.4.1
(= variants.yaml), llvm-tools 23.1.6. Pinned in variants.yaml as `m4`,
`llvm_tools`.

**Port search (2026-11-23).** Full table, queries and per-hit columns
(last commit, zig version, upstream version, `.pc`/CMake) in
[PORTS.md](PORTS.md); raw API data in
`/data/gamma/luciorq/workspaces/temp/libs-zig-pixi/slice2/ports-raw/`.

**S2-F4 V. The AYCB Codeberg org holds none of the slice-2 libraries.**
`GET codeberg.org/api/v1/orgs/allyourcodebase/repos?limit=50` page 1: 15
repos (bubblewrap, gnumake, libFLAC, libcap, libevdev, libinput, libogg,
libsamplerate, libseat, libudev-zero, libvorbis, miniaudio, nanomodbus,
spirv-cross, uncrustify); page 2 empty (re-checked by hand). Codeberg-wide
search: `/api/v1/repos/search` answered HTTP 429 to every query for about
2 minutes, so the search used the website's explore pages (865 repos
with language Zig, plus one query per library, all HTTP 200); a Codeberg
port with no Zig file would be missed.

**S2-F5 V. The GitHub AYCB repositories are maintained, not frozen.** Not
archived; latest default-branch commits: boringssl 2026-11-09, libpng
2026-11-06, harfbuzz 2026-10-28, curl 2026-10-12 ("upgrade to zig
0.17.0") (`gh api repos/allyourcodebase/<r>/commits`). Neither the org
description nor the boringssl, libpng or curl READMEs mention a move to
Codeberg. This contradicts the brief's premise ("unmaintained, moved to
Codeberg"); DESIGN.md 6.4 is left as it was until D109.

**S2-F6 V. No port installs a `.pc` file or CMake package files.** grep of
all 101 fetched `build.zig` files: `cmake` appears only as
`addConfigHeader(.style = .cmake)`, `pkg_config` only as
`linkSystemLibrary(.use_pkg_config)`. A port fallback (D104 C) has to add
the `.pc` (and CMake files where the contract lists them) itself.

**S2-F7 V. Best port per batch-1/2 library** (PORTS.md; none built for
windows-gnu yet): gmp: github shreyassanthu77/zig-gmp (2026-11-13, zig
min 0.17.0, gmp 6.3.0); mpfr, glpk, udunits2: no port anywhere; nlopt:
no standalone port (only a vendored copy in lab-key/phyzx, zig 0.15.1);
gsl: codeberg rwolters/gsl (2026-11-04, README zig 0.17.1, GSL 2.8, not
Rtools' 2.7.1). Later batches: hdf5 codeberg rwolters/hdf5 (HDF5 2.2.0,
not the 1.12.x the risks need); libpq shreyassanthu77/zig-libpq (PostgreSQL
18.7, Rtools 16.10); curl jiacai2050/zig-curl (8.19.0, mbedtls); netcdf-c
and libaec (standalone) none. So for mpfr and glpk a D104 fallback can
only be B (cmake port) or a new port of our own.

**S2-F8 V. The helper's LD stub sent libtool into its MSVC branch
(2026-11-23, rattler-build, both subdirs).** First recipe build of
zig-gmp: configure passed, then `libtool: link: lib -OUT:.libs/libmpn.lib
...` and `../libtool: line 1744: lib: command not found` (Error 127).
The generated libtool had `old_archive_cmds="lib -OUT:$oldlib..."`:
libtool's "is the linker GNU ld" test ran `x86_64-w64-mingw32-ld -v`,
which is the failing stub, so it assumed MSVC. In the manual run (S2-F2)
the build machine's `/usr/bin/ld` had answered "GNU ld... yes", which
is a leak. `zig ld.lld -m i386pep|arm64pe` gives "unknown emulation"
(zig 0.17.1's ld.lld is the ELF driver only), so LD cannot be a real
PE linker. Fixed by D109.
With D109 the configure logs show `checking if the linker
(<triple>-ld) is GNU ld... (cached) yes` for C. libtool's C++ tag checks
again under its own variable (`lt_cv_prog_gnu_ldcxx`) and says `no`; the
generated libtool (scratch re-run, `b/helper-x64`) still has
`old_archive_cmds="$AR $AR_FLAGS ..."` in the CXX section, and its
`with_gnu_ld="no"` only changes shared-library commands, which a static
build never runs. Left unset (no second answer).

**S2-F9 V. zig-gmp 6.3.0 builds and passes its package test on linux for
both subdirs (2026-11-23, local rattler-build, zig-toolchain 0.2.0 from
this branch).** win-arm64 `zig-gmp-6.3.0-zig_9f4afec_0.conda` (416,540
B), win-64 `zig_f2af8c6_0` (462,750 B). pkgtest: `pkgconf --cflags --libs
gmpxx` = `-lgmpxx -lc++ -lgmp` from the sub-prefix, no `-lstdc++`, 2
archives without build paths, llvm-nm 131 `std::__1` / 0 `__cxx11`, 0
duplicate C symbols, 0 `-export:` directives; gmp.c and gmp.cpp link as
PE images of the right machine (not run: linux host; they run in CI's
Windows test jobs). Logs: `CC_FOR_BUILD='zig cc'`, `NM=$BUILD_PREFIX/bin/llvm-nm`,
no `/usr/bin/{ld,as,nm,pkg-config}` in either configure. No upstream
patch, and no cache answer beyond D109's.

**S2-F10 V. r-zig-pixi already decided part of this (user, 2026-11-23:
consult r-zig-pixi before any toolchain decision).** rzig ships GNU-style
binutils personalities: nm, objdump, strip, dlltool, windres, and `as`
(one `.s` through zig cc's integrated assembler)
(`zigbuild/tools/rzig/main.zig:156-182`). r-zig-pixi
feat-win-zig-binutils/PLAN.md decision 1 chose them over conda-forge's
llvm-tools ("a second toolchain", libLLVM over 100 MB, LLVM output
formats). rzig has no `ld`. r-zig-pixi's winch/libbacktrace configure hit
the same libtool gap ("no acceptable ld found in $PATH",
feat-standalone-toolchain/phase7/AMENDMENTS.md) and left it as an
expected failure. So D109 (lt_cv_prog_gnu_ld) and the `NM=llvm-nm` part
of S2-F2/S2-F3 are on hold: S2-F2, S2-F8 and the questions were sent to
the r-zig-pixi session (r-zig-pixi-ed) on 2026-11-23; its reply decides
whether zig-toolchain ports rzig's nm and as personalities (as
binutils.zig already copies dlltool/windres) instead of requiring
llvm-tools.

Reply from the r-zig-pixi session (2026-11-23), per item: (1) rzig has
no ld personality and no decision on `lt_cv_prog_gnu_ld`; the only record
is the winch/libbacktrace casualty, so D109 contradicts nothing. If
libs-zig-pixi ever wants an ld personality, the two repos pick one answer
together (winch would want it too). (2) feat-win-zig-binutils decision 1
is about what r-zig ships to users (libLLVM size, GNU output for
sotools.R, no second toolchain in the install). A pinned build-time
llvm-nm in a recipe's build env is fine; rzig's nm (binutils.zig:599)
would probably answer gmp's probe too (not verified); port it only to get
zero LLVM tools in the build env. (3) port rzig's `as` (binutils.zig
asArgv) when a library actually assembles (gmp with assembly, OpenSSL
asm); not needed with `--disable-assembly`. (4) CC_FOR_BUILD and (5) m4:
no r-zig impact. Consumer side: rebuilding all nine libraries as build 1
is fine; r-zig-pixi relocks after the handover and runs stress on both
Windows arches; a CONTRACT.md 5 note on zig_toolchain 0.2.0 in the
handover is enough. Result: D109 and the llvm-nm pin stand as they are.

**S2-F11 V. mpfr 4.2.2 cross-builds through the helper, no patch, no
cache answer (2026-11-23).** sha256 `b67ba038...6ce01` from
ftpmirror.gnu.org and www.mpfr.org (identical). Configure: "for TLS
support... cannot test, assume no" when cross; with MPFR's own
`--enable-thread-safe` it prints "cannot test, assume yes" and defines
`MPFR_USE_THREAD_SAFE=1` (`__thread`), as a native build detects
(acinclude.m4: the cross branch of AC_RUN_IFELSE honours the option).
Also skipped when cross: "GMP_NUMB_BITS and sizeof(mp_limb_t)
consistency" and "gmp.h version and libgmp version" (both "cannot test";
one channel with exact pins). mpfr.pc names `-lgmp` in Libs; build.sh
replaces it with `Requires: gmp`. Recipe build, both subdirs: win-arm64
`zig-mpfr-4.2.2-zig_032ea3f_0`, win-64 `zig_8976154_0`; pkgtest: `-lmpfr
-lgmp`, 0 duplicate C symbols with libgmp.a, 0 `-export:`, smoke links
(it asserts `mpfr_buildopt_tls_p()` where it runs, on Windows).

**S2-F12 V. glpk 5.0 needs GLPK's Windows code on MinGW; CRAN builds it
that way (2026-11-23).** sha256 `4a1013ee...ec6f15` (ftp.gnu.org,
ftpmirror; MXE's glpk.mk has the same). Plain configure + make fails:
`env/stdc.c:79: call to undeclared function 'gmtime_r'` and `:85
'strerror_r'`. GLPK picks its Windows code on `__WOE__` (set by its own
w32/w64 MSVC files), which the autotools build never sets. MinGW-w64
declares `gmtime_r` only under `_POSIX_THREAD_SAFE_FUNCTIONS` and has no
`strerror_r`. The POSIX `glp_time` also passes `&tv.tv_sec` (32-bit
`long` on MinGW) as `time_t*` (MSYS2's timeval-64bit.patch fixes it).
MSYS2 carries 5 source patches (fix-platform-check.patch: `__WOE__` ->
`_WIN32` in stdc.c); MXE's glpk.mk uses `--with-gmp CFLAGS=-std=c99` and
writes `glpk.pc` with only `-lglpk`. CRAN's Rtools45 aarch64 libglpk.a
(r-zig-pixi scratch `next/fix-winarm/rt/a/...`) defines `DllMain` and
uses `GetSystemTime`, `MessageBoxA`, `strerror_s` and 34 `__gmp*`
symbols, so it was built with GLPK's Windows code and GMP. With
`CPPFLAGS=-D__WOE__ --with-gmp` (D110) both arches build; libglpk.a
defines `DllMain` (env/tls.c: an error box on Windows before Vista, else
TRUE), its internal zlib is prefixed `_glp_zlib_*`, and it imports
`MessageBoxA` (user32; `-luser32` in the written glpk.pc). Upstream
installs no `.pc`; build.sh writes one (Requires: gmp). Recipe build:
win-arm64 `zig-glpk-5.0-zig_668bbc6_0`, win-64 `zig_59e4d1f_0`; pkgtest
all passed (0 duplicate C symbols, 0 `-export:`, smoke links: simplex and
exact simplex). Open: `DllMain` inside a static archive becomes the
entry point of a DLL that links it (an R package with its own `DllMain`
would get a duplicate symbol). CRAN has the same; igraph in the
r-consumer job (D102) checks it.

**S2-F13 V. The published r-zig-slim does not look in zig-libs yet
(kappa, 2026-11-23).** A pixi env on kappa (win-64) from these channels
in order: local batch-1 channel, universe, conda-forge; r-zig-slim 4.6.2
`hc365614_11` and r-zig-toolchain `h7cdf2a3_11` from universe (the only
win-64 r-zig-slim build there), zig-gmp/mpfr/glpk from the local
channel (`pixi list --json`: `source` = the local channel URL).
`Library/zig-libs/x86_64-windows-gnu/` holds the archives and `.pc`
files. `tests/r/install.R gmp Rmpfr igraph` (6.2 min): all three FAILED,
`Rgmp.h:9:10: fatal error: 'gmp.h' file not found` (gmp, Rmpfr) and
igraph's "Package glpk was not found in the pkg-config search path", then
`'glpk.h' file not found`. That build's `etc/Rcmd_environ` has no
`R_ZIG_LIBS`; its pkg-config path is only `lib/pkgconfig;share/pkgconfig`
(lines 57-58). So the CONTRACT.md 6 consumer side is not in a published
r-zig yet, and the r-consumer job (D113) cannot pass with universe's
r-zig-slim. Asked the r-zig-pixi session (2026-11-23) which build has it
and when it will be published.
Reply: the integration is in r-zig build 12 only (main since PR #51,
merged 2026-11-22), unpublished, no date (user decision there: one
batched release). Build 11 was published 2026-11-18 (run 44336177906).
Every r-zig-pixi stress run that passed sf/terra/gdalraster/s2 on
Windows used an r-zig built in the same CI run, never universe's.
CONTRACT.md 6 now says so (their request).
Update (r-zig-pixi session, later 2026-11-23): the r-zig-pixi user
decided to publish r-zig build 12 right after r-zig-pixi's current wave 2
passes CI and stress (no date; the rest of its backlog moves to build
13). That session will send the published r-zig-slim/r-zig-toolchain `_12`
build strings; then D114's emulation and `continue-on-error` go, and
r-consumer becomes required.

**S2-F14 V. With build 12 emulated, gmp, Rmpfr and igraph build from
source on Windows against the batch-1 packages and pass smoke.R (kappa
win-64, 2026-11-23).** Same env as S2-F13, plus `PKG_CONFIG_PATH=<zig-libs>/lib/pkgconfig;<env>/Library/lib/pkgconfig`,
`R_MAKEVARS_USER` (`CPPFLAGS += -I<zig-libs>/include`, `LDFLAGS +=
-L<zig-libs>/lib`) and `R_TOOLS_SOFT=<zig-libs>`: gmp 0.7.5.1, Rmpfr
1.1.3, igraph 2.3.4 installed; smoke.R 8/8 PASS (factorialZ, isprime,
bigq; pi to 200 bits, mpfr/3; ring, cluster_optimal through GLPK,
GraphML through libxml2). Link lines: igraph `-L<zig-libs>/lib ... -lxml2
-lglpk -luser32 -lgmp` (from our glpk.pc), Rmpfr `-lmpfr -lgmp`, gmp
`-lgmp`. The env has no conda-forge gmp or glpk, so the archives are
zig-libs'. igraph's DLL loads with GLPK's `DllMain` in it (S2-F12's open
point, for igraph). Not run: win-arm64 (CI), mpfr's thread-local
storage under threads.

**S2-F15 V. All 12 recipes build and pass their tests for win-64 with
zig-toolchain 0.2.0 (gamma, `pixi run build-libs win-64`, 2026-11-23).**
12 "all tests passed". Build strings: zig-zlib `zig_00866d4_1`,
zig-sqlite `zig_0558645_1`, zig-expat `zig_082a123_1`, zig-openssl
`zig_e9f36c6_1`, zig-abseil `zig_1ed8917_1`, zig-onetbb `zig_67e80fb_1`,
zig-geos `zig_51e08d0_1`, zig-proj `zig_fb84dec_1`, zig-gdal
`zig_f2af728_1`, zig-gmp `zig_f2af8c6_0`, zig-mpfr `zig_8976154_0`,
zig-glpk `zig_59e4d1f_0`. `zig-toolchain check-alignment --expect win-64
--published=https://prefix.dev/universe`: "published comparison OK: 16
new, 0 already published" (the nine rebuilt libraries are `_1` beside the
published `_0`). llvm-nm over the 106 archives of these packages: only
`libglpk.a` defines `DllMain` (CONTRACT.md 2's line holds).

**S2-F16 V. The consumer env's pkg-config activation puts conda-forge's
openssl.pc first; build 12's Rcmd_environ lines fix it, exported
variables do not (kappa win-64, 2026-11-23).** Full win-64 list on kappa
(S2-F15's 12 packages + r-zig `_11` + libxml2-devel, cmake, udunits2;
emulation by exported PKG_CONFIG_PATH, R_MAKEVARS_USER, R_TOOLS_SOFT):
terra 1.9.60, gdalraster 2.7.0, gmp, Rmpfr, igraph ok; s2 FAILED
("Package absl_base was not found", then `lld-link: error: undefined
symbol: absl::lts_20250127::...`), and sf (needs s2) was never tried.
Cause 1 (DESIGN R11): s2's Makevars.win sets
`PKG_CONFIG_PATH=$(CURDIR)/../tools/pkgconfig` for absl_s2, which hides
ours. Adding `PKG_CONFIG_LIBDIR` (zig-libs, env lib, env share; build
12's own default order, r-zig-pixi build.zig:2862-2870) gives s2 1.1.13
and sf 1.1.3 installed and smoke.R 30/30 PASS for sf, terra, gdalraster,
s2, gmp, Rmpfr and igraph. Cause 2: s2 then linked `-L<env>/Library/lib
-llibssl -llibcrypto`, conda-forge openssl 3.6.5's MSVC import
libraries (the env has it as a dependency). pixi's activation runs
`etc/conda/activate.d/pkg-config_activate.bat`, which prepends
`<env>\Library\lib\pkgconfig` to PKG_CONFIG_PATH, so the job's
exported value comes after it. With build 12's lines appended to the
env's `Rcmd_environ` instead (`PKG_CONFIG_PATH="${R_ZIG_LIBS}/lib/pkgconfig;${PKG_CONFIG_PATH}"`,
read by R after the activation): s2 links `-L<zig-libs>/lib -lssl
-lcrypto -lws2_32 -lgdi32 -lcrypt32 -luser32 -ladvapi32 -lz` (zig-openssl
and zig-zlib), and smoke s2 5/5 and sf 7/7 PASS. The r-consumer job now
uses the Rcmd_environ form (D114). Side finding: the env's
`Rcmd_environ` is a hardlink to pixi's package cache
(`fsutil hardlink list`: `AppData\Local\rattler\cache\pkgs\r-zig-slim-4.6.2-hc365614_11\...`).
The append changed kappa's cached copy; it was restored in place from a
copy taken before the append (`fc /b`: no differences). The CI job
copies the file before appending.

**S2-F17 V. All 12 recipes build and pass their tests for win-arm64
(gamma, `pixi run build-libs win-arm64`, 2026-11-23).** Build strings:
zig-zlib `zig_1ed7dd2_1`, zig-sqlite `zig_0740526_1`, zig-expat
`zig_87c6c29_1`, zig-openssl `zig_d514311_1`, zig-abseil `zig_944986a_1`,
zig-onetbb `zig_46eba61_1`, zig-geos `zig_41337d2_1`, zig-proj
`zig_74ae35b_1`, zig-gdal `zig_8e71cba_1`, zig-gmp `zig_9f4afec_0`,
zig-mpfr `zig_032ea3f_0`, zig-glpk `zig_668bbc6_0`. check-alignment
`--expect win-64,win-arm64` against universe: "published comparison OK:
25 new, 0 already published". Not run on win-arm64 hardware: the smoke
programs and R packages (CI's test and r-consumer jobs).

**S2-F18 V. PR #7 CI, run 45285470540 (head 4d4a5f4, pull_request,
default leg), 2026-11-24.** plan, toolchain (the new configure tests
included), cross win-64 and win-arm64, alignment: success. Build strings
are the same as the local builds (S2-F15, S2-F17). test win-64 and test
win-arm64: "12 package(s) tested, 1 failed: zig-mpfr". The 11 others ran
their smoke programs on the runner ("ran: OK", "all checks passed"),
gmp's C and C++ and glpk's included. zig-mpfr failed in its smoke
program only: `FAIL: pi = 3.14159265358979323846264338327950288419716939937511
(want ...937510)`. The test was wrong: pi = ...937510 58209..., so the
correctly rounded 50-decimal value ends in 1, and MPFR's output is right.
tests/smoke/mpfr.c now expects ...937511; checked on linux against
conda-forge mpfr 4.2.2 ("OK"). Its TLS assertion has not run on Windows
yet (the program stopped at pi). r-consumer (report-only, D114): win-64
installed sf, terra, gdalraster, s2, gmp, Rmpfr, igraph (21.2 min),
smoke 30/30 PASS; win-arm64 installed terra, gdalraster, s2, gmp, Rmpfr,
igraph (16.1 min), smoke 23/23 PASS, the first R evidence on win-arm64
for gmp, Rmpfr, igraph (GLPK, libxml2) against zig-* packages. Every
zig-* came from the run's channel (`pixi list` source column).

**S2-F23 V. Where CI time goes, and the shared zig cache (2026-11-24).**
Run 45285470540: cross win-64 51 min (gdal 15.8, geos 5.9, openssl 5.4,
proj 4.4, gmp 3.9, abseil 3.5, onetbb 3.4, zlib 2.4, mpfr 2.0, glpk 2.0,
expat 1.7, sqlite 1.1), win-arm64 33; test win-64 36 min, 2.2-4.1 min
per package even for zlib: test env 43 s, `zig run pkgtest.zig` 11 s,
one smoke link 66 s (zig builds the MinGW C runtime, and libc++ for the
C++ packages, in the test's empty `.zig-global-cache`); the checks
themselves take seconds. Builds also start from an empty cache per
recipe (activation: `ZIG_GLOBAL_CACHE_DIR=$SRC_DIR/.zig-global-cache`).
rattler-build passes the caller's environment to neither: a build sees a
variable only through `env.get` in `build.script.env` (it is exported in
build_env.sh before the activation scripts run), and a test sees none
(probe package: PROBE_PLAIN, ZIG_GLOBAL_CACHE_DIR empty), but keeps HOME
(linux) and LOCALAPPDATA, APPDATA, TEMP (kappa; USERPROFILE is set to
SRC_DIR), so zig's per-user cache works in tests. D115 changes:
activation `ZIG_GLOBAL_CACHE_DIR="${LIBS_ZIG_CACHE:-${SRC_DIR}/.zig-global-cache}"`
(local cache unchanged), `LIBS_ZIG_CACHE: ${{ env.get(...) }}` in the
12 recipes, the test command `zig run --cache-dir .zig-local-cache`
(no `--global-cache-dir`), pkgtest no longer sets the child's
ZIG_GLOBAL_CACHE_DIR; build.yml keeps `zig-cache` (cross) and
`~/AppData/Local/zig` (test) with actions/cache 6.1.0, written on main
only. Local check (gamma, win-64, LIBS_ZIG_CACHE shared): libz.a,
libglpk.a, libgeos.a, libgeos_c.a byte-identical to the per-recipe-cache
builds (sha256 diff empty); the cache holds 66 MB after zlib, glpk, geos;
zig-zlib build+test 91 s with a fresh cache, 32 s with the shared one
warm. Local gotcha: rebuilding zig-toolchain under the same file name
left rattler's package cache with the old extraction and the channel's
repodata with the old sha256 ("hash mismatch when extracting"); fixed by
deleting the cache entry and `rattler-index fs --force`. CI starts empty,
so it is unaffected. Not measured: CI times with the cache (next run
fills it; PR runs read main's).

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

## Handover to r-zig-pixi (CONTRACT.md 8)

One handover for all of slice 2, after its single publish (D118; the
per-batch drafts below are merged into it then). After the publish: names, subdirs and build strings; contract changes;
then r-zig-pixi adds the packages to its Windows stress env, updates
`packages.tsv` sysdeps and expects (`windows-aarch64=` keys), relocks,
runs stress on both Windows arches, and removes a library from
`rtools_has` once no row resolves into the tree for it.

### Batch 1 handover (draft; confirmed after the publish run)

Packages (both subdirs unless noted; build strings from the local builds,
S2-F9, S2-F11, S2-F12, S2-F15; the variant hash makes them the same in CI):

| Package | Version | win-64 | win-arm64 |
|---|---|---|---|
| zig-gmp (new; gmp + gmpxx) | 6.3.0 | `zig_f2af8c6_0` | `zig_9f4afec_0` |
| zig-mpfr (new) | 4.2.2 | `zig_8976154_0` | `zig_032ea3f_0` |
| zig-glpk (new) | 5.0 | `zig_59e4d1f_0` | `zig_668bbc6_0` |
| zig-zlib, -sqlite, -expat, -openssl, -abseil, -onetbb, -geos, -proj, -gdal | unchanged | build 1 (S2-F15) | build 1 (S2-F17) |

Contract changes (CONTRACT.md, this PR):
- section 1: zig-gmp, zig-mpfr, zig-glpk;
- section 2: libglpk.a defines `DllMain` (GLPK's Windows code, as CRAN);
  recipe-written `.pc` files (glpk.pc);
- section 5 (no text change): zig_toolchain 0.1.0 -> 0.2.0 (the
  `configure` helper, D108) rebuilt the nine slice-1 libraries as build
  1; archive content is expected unchanged (I);
- section 6: describes r-zig build 12 (unpublished); build 11 predates it;
- section 7: the r-consumer job, report-only until r-zig build 12 (D114).

What r-zig-pixi does (CONTRACT.md 8 step 3): relock (its specs are `*`,
so the nine take build 1); add zig-gmp, zig-mpfr, zig-glpk to the
Windows stress env; `packages.tsv`: gmp, Rmpfr, igraph rows get
`zig-gmp@windows`, `zig-mpfr@windows`, `zig-glpk@windows` sysdeps in
place of conda-forge's gmp/mpfr/glpk on Windows (igraph's win-64
`fail-sysdep`, no glpk.pc, should become ok); run stress on both Windows
arches with an r-zig that has the zig-libs search (build 12 or a same-run
build); drop gmp, mpfr, glpk from `rtools_has` once no win-arm64 row
resolves them from the tree.

## Batch 2: nlopt, udunits2 (branch feat-slice2-batch2)

Started 2026-11-24 while PR #7 (batch 1) waits for CI, in its own worktree
(`/data/gamma/luciorq/workspaces/temp/r-zig-pixi/wt/libs-slice2-b2`,
branched from feat-slice2 f616781). Versions as the Rtools45 tree
(S2-F1: nlopt 2.10.0) and r-windows/rtools-packages (udunits 2.2.28).

**S2-F19 V. nlopt 2.10.0 cross-builds with its own CMake, no patch
(2026-11-24).** Source: GitHub's tag archive (the v2.10.0 release has no
asset), sha256 `506f83a9...237be1`. Rtools45 builds it with CMake and
`-DNLOPT_CXX=ON` (r-windows/rtools-packages mingw-w64-nlopt PKGBUILD);
MXE's nlopt.mk has the same options. With the toolchain file: configure,
build and install pass on both arches ("Looking for isinf/qsort_r/syscall
- not found" only). libnlopt.a carries the C++ algorithms: llvm-nm -u
gives 70 `std::__1` references (pkgtest: 227 std::__1, 0 __cxx11), while
upstream's nlopt.pc names only `-lm` in Libs.private, so build.sh adds
`-lc++` (close-pc --libs); the C smoke program (Nelder-Mead and StoGO)
links with the .pc's flags alone. NLoptConfig.cmake set
NLOPT_INCLUDE_DIRS/NLOPT_LIBRARY_DIRS to the absolute host prefix (the
imported target file is relative); build.sh rewrites them to
`${CMAKE_CURRENT_LIST_DIR}/../../..` and fails if the prefix remains. The
slice-1 packages' lib/cmake and lib/pkgconfig files name no host prefix
(grep over the 12 extracted win-64 packages: 0 files). Licence
`LGPL-2.1-or-later AND MIT` (COPYING: MIT core, luksan LGPL-2.1+).
Recipe build: win-arm64 `zig-nlopt-2.10.0-zig_7d742f2_0`, win-64
`zig_b870d38_0`; pkgtest all passed.

**S2-F20 V. udunits 2.2.28 cross-builds through the helper, no patch, no
cache answer (2026-11-24).** The URL Rtools and conda-forge name
(`artifacts.unidata.ucar.edu/.../udunits-2.2.28.tar.gz`) answers 404;
`downloads.unidata.ucar.edu/udunits/2.2.28/udunits-2.2.28.tar.gz` has the
same sha256 (`590baec8...d579e`, the PKGBUILD's and conda-forge's).
Rtools builds it with plain configure. With `zig-toolchain configure`,
zig-expat (`-DXML_STATIC`, as its expat.pc) both arches configure, build
and install (lib, include, share/udunits XML, a udunits2 program removed).
The compiled-in default database path is the relative Windows
`share\udunits\udunits2.xml`, not a prefix. Upstream installs no .pc and
Rtools has none; R's units on Windows links `-ludunits2 -lexpat` directly
(Makevars.ucrt, units 1.0-1) and ships its own XML; build.sh writes a
udunits2.pc (Requires: expat). Licence `UCAR`. Recipe build: pkgtest all
passed on both subdirs (smoke: an XML unit system read through expat,
2.5 km = 2500 m).

**S2-F22 V. nloptr, units and sf build from source on Windows against
batch 2 (kappa win-64, 2026-11-24).** Env: local channel with this
branch's 14 win-64 packages (zig-nlopt, zig-udunits2 and S2-F15's 12),
then universe (r-zig `_11`), then conda-forge (libxml2-devel, cmake; no
conda-forge udunits2); build 12's Rcmd_environ lines (D114), the file
copied first (`fsutil hardlink list`: one link, so the cache was not
touched). install.R: nloptr 2.2.1, units 1.0.1, sf 1.1.3 ok. smoke.R
nloptr, units, sf, s2: 18/18 PASS (StoGO included). Link lines: nloptr
`-L<zig-libs>/lib -lnlopt`, units `-L<zig-libs>/lib -ludunits2 -lexpat`.
nloptr names no `-lc++` and links anyway (its DLL is linked as C++).
kappa scratch removed.

### Batch 2 handover (draft; confirmed after the publish run)

| Package | Version | win-64 | win-arm64 |
|---|---|---|---|
| zig-nlopt (new) | 2.10.0 | `zig_b870d38_0` | `zig_7d742f2_0` |
| zig-udunits2 (new) | 2.2.28 | `zig_88de710_0` | `zig_53d4c50_0` |

check-alignment `--expect win-64,win-arm64` against universe: "build
alignment OK", "published comparison OK: 29 new" (batch 1 and 2,
unpublished). Contract changes (CONTRACT.md): section 1 names them;
section 2: udunits2.pc written by the recipe, `share/udunits/` and the
relative default database path; section 7: r-consumer runs sf on both
arches. No other package changes (no toolchain change, so no rebuilds).

What r-zig-pixi does: add zig-nlopt and zig-udunits2 to the Windows
stress env; `packages.tsv`: nloptr's `nlopt@windows` becomes
`zig-nlopt@windows`, units (and sf, lwgeom through it) take
`zig-udunits2@windows`; lme4 follows nloptr; drop nlopt and udunits2 from
`rtools_has` once no win-arm64 row resolves them from the tree.

**S2-F24 V. udunits' configure finds the runner's gfortran; libtool
then names the archive `.lib` (2026-11-24).** PR #8 run 45382544600:
cross win-64 and win-arm64 fail in zig-udunits2's package content test
(`lib/libudunits2.a` missing, `lib/libudunits2.lib` present). Its log:
`checking for gfortran... gfortran`, `WARNING: using cross tools not
prefixed with host triplet`, `whether we are using the GNU Fortran
compiler... no`. configure.ac line 95 is `AC_PROG_FC`; the GitHub
ubuntu image has `/usr/bin/gfortran` (gamma has none, so the local
builds of S2-F20 gave `.a`), and the build script's PATH keeps
`/usr/bin` (M5-F27). libtool configures an FC tag for it, takes the
non-GNU (MSVC) branch and sets `libext=lib`. Reproduced on gamma with a
stand-in `gfortran` (`exec /bin/false`) on PATH: `libext=lib`.
`FC=false F77=false` still gives `lib` (libtool skips the tag only for
an empty FC or `no`); `FC=no F77=no` gives `libext=a`, a libtool
config block and config.h identical to the no-gfortran build, and
`libudunits2.a`. The recipe build with the fence (win-64, gamma) passes
its tests. gmp, mpfr, glpk and gsl 2.7.1 configure scripts have no
FC/F77 probe. Fix D117.

**S2-F21 V. gsl 2.7.1 prototype for batch 3 (manual, 2026-11-24, not in
this batch).** sha256 `dcb0fbd4...eeb34b` (ftpmirror.gnu.org and
ftp.gnu.org identical). r-windows/rtools-packages builds gsl with plain
configure (its PKGBUILD says 2.7; the tree has 2.7.1, S2-F1). Through
`zig-toolchain configure`, both arches configure, build and install with
no patch and no cache answer: libgsl.a, libgslcblas.a (GSL's own CBLAS,
not MKL: the win-64 fail-upstream row in r-zig-pixi is conda-forge's
MKL gslcblas.lib), 266 headers, gsl.pc (`-lgsl -lgslcblas -lm`, neutral
prefix for close-pc); also gsl-config, two programs, man/info pages (to
remove). Configure: "IEEE arithmetic interface type... unknown", so
`gsl_ieee_env_setup` has no FP-mode support on MinGW (I: as a native
MinGW build; R's gsl package does not call it).
