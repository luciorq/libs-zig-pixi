# Zig build-system ports survey (2026-11-23, slice2 PLAN.md S2-F4..F7)

Scope: 32 C/C++ libraries used by libs-zig-pixi. Target zig: 0.17.1.
All raw data is in this directory (see "Files" at the end).

## Headline findings

1. **Codeberg AYCB org** is `allyourcodebase` (`GET /api/v1/orgs/allyourcodebase` -> 200).
   It holds **15 repos**, none of them in our library list:
   bubblewrap, gnumake, libcap, libevdev, libFLAC, libinput, libogg, libsamplerate, libseat,
   libudev-zero, libvorbis, miniaudio, nanomodbus, spirv-cross, uncrustify
   (`cb_org_names.tsv`, `raw/cb_org_p1.json`; page 2 empty).
2. **GitHub AYCB org is not frozen.** `github.com/allyourcodebase` has 130 public repos
   (`raw/gh_aycb_repos.json`). Repos in our list have default-branch commits as recent as
   boringssl 2026-11-09, libpng 2026-11-06, freetype/harfbuzz 2026-10-28, curl 2026-10-12.
   The "unmaintained mirror" premise does not hold for these repos as of today. They are listed
   below as AYCB rows for reference only.
3. **No surveyed port installs a `.pc` file or CMake config files.** Grep of all 101 fetched
   `build.zig` files for `pkgconfig|\.pc"|\.pc\.in|[Cc]onfig\.cmake|lib/cmake` returned no
   match. `cmake` hits in `build.zig` are only `addConfigHeader(.{ .style = .{ .cmake = ... } })`
   (config.h generation), and `pkg_config` hits are only `linkSystemLibrary(..., .use_pkg_config)`.
   So the `.pc` and `cmake` columns are "no" everywhere.
4. **No port found anywhere** for: mpfr, glpk, udunits2, netcdf-c, libaec (standalone).
   c-blosc2, win-iconv and GNU libiconv exist only as AYCB repos. fribidi and hdf5 exist only inside other projects or one
   Codeberg repo (see tables).
5. Ports that state zig 0.17.x: rwolters/gsl and rwolters/hdf5 (Codeberg, README tables list
   0.17.1), GabeRealB/pe2-editor `packages/ports/*` (min 0.17.1), ghostty `pkg/*` (min 0.17.1),
   shreyassanthu77/zig-gmp and zig-libpq (min 0.17.0), jiacai2050/zig-curl (min 0.17.0),
   LukasKastern/json-c (min 0.17.0), Xevion/ffmpeg-hermetic (min 0.17.0),
   AYCB curl/boringssl (min 0.17.0).

## Column meanings

- **last commit**: committer date of the newest commit on the default branch (for sub-directory
  ports: newest commit touching that path).
- **zig**: `minimum_zig_version` from `build.zig.zon` ("min"); CI versions from workflow files
  ("CI"); README statements ("README"). "unknown" when none of these exist.
- **upstream**: from the `build.zig.zon` dependency URL/ref, else "vendored" (source in repo).
- **.pc / cmake**: does `build.zig` install a pkg-config file / CMake package config. "no" for
  every row (finding 3).
- **stars / archived** from the host API.

## Results per library

### gmp
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/shreyassanthu77/zig-gmp | github | 2026-11-13 | min 0.17.0 | gmp 6.3.0 tarball | no | no | 0 | no | freshest; has a `.windows` branch for PIC |
| https://github.com/Rexicon226/zig-gmp | github | 2026-06-02 | min 0.15.0, CI 0.16.0 | gmp 6.3.0 tarball | no | no | 4 | no | most referenced by other zon files (2 hits) |
| https://github.com/nDimensional/zig-gmp | github | 2026-06-28 | min 0.16.0 | gmp 6.3.0 tarball | no | no | 0 | no | description says "bindings"; zon pulls the gmp tarball |

### mpfr
None. GitHub repo search (`mpfr` lang:zig, `mpfr zig`), GitHub code search
(`mpfr` in build.zig.zon: 0 hits) and Codeberg explore (only lch361/lcalc, a calculator app) found no port.

### glpk
None (all queries 0 relevant hits).

### gsl
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://codeberg.org/rwolters/gsl | codeberg | 2026-11-04 | min 0.15.2; README: pkg 2.8.0-zig2.0.0 = zig 0.17.1, zig1.0.0 = 0.16 | gsl 2.8 (ftp.gnu.org) | no | no | 2 | no | build.zig has an explicit Windows branch (links gslcblas). Best candidate |
| https://github.com/tatjam/zgsl | github | 2024-09-03 | unknown | gsl 2.8 | no | no | 2 | no | stale; also a wrapper |

### nlopt
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/lab-key/phyzx/tree/main/libs/znlopt-mit/libs/nlopt-mit | github | 2025-11-06 (path) | min 0.15.1 | vendored (`src/`), version unknown | no | no | 3 (repo) | no | sub-package inside an app; "nlopt-mit" = MIT-licensed subset (name-based guess) |
| https://github.com/Beyley/zig-nlopt | github | 2026-09-19 | min 0.16.0 | none | no | no | 1 | no | NOT a C port: build.zig has no C sources, only `src/main.zig` |

### udunits2
None (GitHub repos, GitHub code search 0 hits, Codeberg 0 hits).

### hdf5
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://codeberg.org/rwolters/hdf5 | codeberg | 2026-11-04 | min 0.15.0; README: v2.2.0-rev1 = zig 0.17.1; tested Fedora x86_64 only | HDF5 2.2.0 + libaec 1.1.8 + zlib 1.3.2 (tarballs) | no | no | 1 | no | builds libaec (`aec`) in the same build.zig; H5pubconf has `H5_HAVE_WINDOWS`/`WIN32_API`/`WIN_THREADS` keyed on target. Best candidate |
| https://github.com/exp4-age/metro2hdf | github | 2026-11-03 | min 0.17.0 | HDF5 2.1.1 tarball | no | no | 0 | no | in-app `buildHdf5()` in a 711-line build.zig; reference only |
| https://github.com/burakssen/zhdf5 | github | 2026-09-10 | min 0.16.0 | none | - | - | 0 | no | NOT a port: pure-Zig HDF5 reader (no C sources) |
| github.com/vaibhav-venkat/soft-material-research `packages/hdf5` | github | 2026-07-22 | min 0.17.0-dev.387 | none | - | - | 0 | no | NOT a port: links system hdf5 via `CONDA_PREFIX` |

### netcdf-c (libnetcdf)
None.

### libpq (PostgreSQL client)
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/shreyassanthu77/zig-libpq | github | 2026-11-13 | min 0.17.0 | postgresql-18.7 tarball + shreyassanthu77/zig-openssl | no | no | 0 | no | freshest |
| https://github.com/seemsindie/libpq | github | 2026-03-19 | min 0.14.0, CI 0.14.1/0.15.2/master | postgres REL_18_1 | no | no | 0 | no | GitHub fork of allyourcodebase/libpq (API `parent`) |
| https://github.com/zadockmaloba/libpq-zig | github | 2025-11-28 | min 0.15.2 | AYCB libpq 5.16.4+4 | no | no | 0 | no | wrapper over AYCB, not a port |
| https://github.com/allyourcodebase/libpq | github (AYCB) | 2026-06-22 | min 0.14.0, CI 0.14.1/0.15.2/0.16.0/master | postgres REL_18_4 | no | no | 16 | no | AYCB reference |
| https://codeberg.org/Swindlers-Inc/postgrez | codeberg | 2026-05-08 | min 0.16.0 | none | - | - | 2 | no | NOT a port: `linkSystemLibrary("libpq")` |

### harfbuzz
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| github.com/GabeRealB/pe2-editor `packages/ports/harfbuzz` | github | 2026-11-13 (path) | min 0.17.1 | harfbuzz 15.1.0 | no | no | 0 | no | sub-package of an app |
| github.com/ghostty-org/ghostty `pkg/harfbuzz` | github | 2026-11-23 (repo) | min 0.17.1 (root zon) | harfbuzz 11.0.0 (ghostty mirror) | no | no | - | no | in-tree, well maintained |
| https://github.com/akunaakwei/zig-harfbuzz | github | 2026-04-19 | min 0.16.0 | harfbuzz 12.1.0 (+ zig-icu, zig-freetype2) | no | no | 0 | no | |
| https://codeberg.org/Bergasms/FTandHB | codeberg | 2026-07-26 | min 0.15.2 | harfbuzz 14.1.0 + hexops freetype fork | no | no | 0 | no | freetype+harfbuzz combined, from mach-freetype |
| https://github.com/allyourcodebase/harfbuzz | github (AYCB) | 2026-10-28 | min 0.15.2, CI 0.15.2/master | harfbuzz 14.4.0 | no | no | 21 | no | AYCB reference |
| https://github.com/flying-swallow/harfbuzz-zig | github | 2026-08-24 | min 0.17.0-dev | - | - | - | 0 | no | NOT a port: pure-Zig shaper rewrite |

### freetype
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/ipc-packages/freetype | github | 2026-11-21 | min 0.15.2, CI 0.15.2/0.16.0/master | freetype git 0a0221a (zon version 2.14.3) + AYCB libpng | no | no | 0 | no | not a GitHub fork; reuses AYCB libpng pin |
| github.com/GabeRealB/pe2-editor `packages/ports/freetype` | github | 2026-11-13 (path) | min 0.17.1 | freetype 2.14.3 | no | no | 0 | no | sub-package |
| https://github.com/akunaakwei/zig-freetype2 | github | 2026-04-19 | min 0.16.0 | freetype 2.14.1 (+brotli, minised) | no | no | 0 | no | |
| https://codeberg.org/Bergasms/FTandHB | codeberg | 2026-07-26 | min 0.15.2 | hexops freetype fork 1d0f0f1 | no | no | 0 | no | see harfbuzz |
| https://codeberg.org/elijah-immer/mach-freetype | codeberg | 2025-02-25 | unknown | pkg.machengine.org freetype | no | no | - | no | mirror of hexops/mach-freetype (stale) |
| https://github.com/allyourcodebase/freetype | github (AYCB) | 2026-10-28 | min 0.15.2, CI 0.15.2/0.16.0/master | freetype 2.14.3 | no | no | 21 | no | AYCB reference |
| ghostty `pkg/freetype`, Xevion/ffmpeg-hermetic `build/freetype.zig` | github | 2026-11-23 / 2026-11-18 | min 0.17.1 / 0.17.0 | ghostty mirror tarball / freetype 2.15.0 | no | no | - | no | in-tree references |

### fribidi
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| github.com/GabeRealB/pe2-editor `packages/ports/fribidi` | github | 2026-11-13 (path) | min 0.17.1 | fribidi 1.0.18 | no | no | 0 | no | only standalone-shaped build found; sub-package of an app |
| github.com/Xevion/ffmpeg-hermetic `build/fribidi.zig` | github | 2026-11-18 | min 0.17.0 | fribidi 1.0.18 | no | no | 0 | no | in-tree build file |
| https://github.com/allyourcodebase/SDL | github (AYCB) | 2026-11-20 | min 0.16.0 | fribidi 1.0.16 (zon dep) | no | no | 82 | no | built inside SDL's build (SDL_ttf); reference |

No standalone fribidi port repo exists on GitHub or Codeberg.

### libpng
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/se4ny/libpng | github | 2026-08-30 | min 0.16.0 | pnggroup/libpng git (unpinned in zon url) | no | no | 0 | no | |
| https://github.com/akunaakwei/zig-png | github | 2026-04-18 | min 0.16.0 | libpng v1.6.58 (+zlib-ng) | no | no | 0 | no | |
| https://github.com/EdvardPedersen/libpng | github | 2025-10-31 | min 0.16.0-dev.747 | libpng 1.6.50 | no | no | 0 | no | |
| https://github.com/allyourcodebase/libpng | github (AYCB) | 2026-11-06 | min 0.15.1 | libpng 1.6.59 | no | no | 13 | no | AYCB reference; also ghostty `pkg/libpng` (min 0.17.1) |
| https://codeberg.org/cn-cn-cn/spng | codeberg | 2026-10-24 (explore) | not fetched | libspng (not libpng) | - | - | - | - | noted only |

### libtiff
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/thuvasooriya/libtiff | github | 2026-04-06 | min 0.15.2 | libtiff git 61b5551 (zon 4.7.1) + AYCB zlib | no | no | 0 | no | same author has libjpeg-turbo, libwebp |
| https://github.com/shreyassanthu77/libtiff-zig | github | 2025-09-10 | min 0.15.1 | libtiff git 57dd777 | no | no | 0 | no | |
| https://github.com/JacobCrabill/libtiff | github | 2025-08-31 | unknown | 4.7.0 (zon version; source vendored/fork) | no | no | 0 | no | GitHub fork of leroycep/libtiff (API `parent`; leroycep last commit 2024-09-19) |

### libjpeg / libjpeg-turbo
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/chearon/libjpeg-turbo | github | 2026-07-13 | min 0.16.0 | libjpeg-turbo 3.1.1 (zon `3.1.1-1`, fork of upstream repo) + AYCB nasm | no | no | 0 | no | SIMD via nasm |
| https://github.com/thuvasooriya/libjpeg-turbo | github | 2026-04-06 | min 0.15.2, CI setup-zig@v2 | libjpeg-turbo git 20ade4d (zon 3.1.0) | no | no | 0 | no | most referenced by others (3 zon hits) |
| https://github.com/timsurber/libjpeg | github | 2025-09-20 | min 0.14.1 | IJG libjpeg 9f | no | no | 1 | no | IJG libjpeg, not turbo |
| https://github.com/zig-pkgs/libjpeg | github | 2024-11-16 | min 0.11.0 | winlibs/libjpeg | no | no | 0 | no | stale |

### libwebp
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| github.com/GabeRealB/pe2-editor `packages/ports/webp` | github | 2026-11-13 (path) | min 0.17.1 | libwebp v1.6.0 | no | no | 0 | no | sub-package |
| https://github.com/thuvasooriya/libwebp | github | 2026-04-06 | min 0.15.2 | libwebp git 4510224 (zon 1.6.0) | no | no | 0 | no | |
| https://github.com/meshy-dev/zig-libwebp | github | 2026-01-07 | min 0.15.1 | libwebp 4fa2191 (zon 1.6.0) + AYCB zlib/libpng | no | no | 0 | no | |

### libxml2
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/ianprime0509/zig-libxml2 | github | 2026-06-20 | min 0.16.0, CI 0.16.0 | libxml2 v2.12.6 + libxslt 1.1.39 | no | no | 3 | no | old upstream |
| https://github.com/Tomcat-42/libxml2 | github | 2026-03-04 | unknown (CI master) | libxml2 v2.15.1 | no | no | 0 | no | |
| https://github.com/allyourcodebase/libxml2 | github (AYCB) | 2026-10-01 | min 0.16.0 | libxml2 2.15.4 (+AYCB zlib, libiconv) | no | no | 8 | no | AYCB reference; Xevion/ffmpeg-hermetic `build/libxml2.zig` also 2.15.4, min 0.17.0 |
| https://github.com/mitchellh/zig-libxml2 | github | 2023-08-02 | unknown | git submodule | no | no | 87 | no | stale |

### curl
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/jiacai2050/zig-curl | github | 2026-11-02 | min 0.17.0 | curl 8.19.0 + zlib 1.3.1 + mbedtls 3.6.0 | no | no | 159 | no | bindings + from-source libcurl build; Codeberg copy https://codeberg.org/jiacai2050/zig-curl (2026-11-01, same zon) |
| https://github.com/allyourcodebase/curl | github (AYCB) | 2026-10-12 | min 0.17.0 | curl 8.18.0 (+AYCB zlib, zstd, ...) | no | no | 16 | no | AYCB reference |
| https://github.com/iCodeIN/zig-libcurl | github | 2022-02-08 | unknown | git submodule | no | no | 0 | no | stale (gyro era) |

### libaec
No standalone port. Built inside https://codeberg.org/rwolters/hdf5 (libaec 1.1.8, target name `aec`).

### mbedtls
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/vak0160/zig_mbedtls | github | 2025-09-23 | min 0.14.1 | mbedtls v3.6.4 | no | no | 0 | no | |
| https://github.com/solenopsys/zig-mbedtls | github | 2026-08-19 | unknown | vendored submodule | no | no | 0 | no | |
| https://github.com/EricTianC/zig-mbedtls | github | 2025-06-11 | unknown | mbedtls 2.27.0 submodule | no | no | 0 | no | old 2.x |
| https://github.com/allyourcodebase/mbedtls | github (AYCB) | 2026-06-25 | min 0.15.1 | mbedtls v3.6.6 | no | no | 5 | no | AYCB reference; jiacai2050/zig-curl also builds mbedtls 3.6.0 |

### libressl
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/binarycraft007/libressl | github | 2024-06-21 | min 0.11.0 | libressl 3.9.2 | no | no | 0 | no | stale |
| https://github.com/allyourcodebase/libressl | github (AYCB) | 2026-06-06 | min 0.14.0, CI 0.14.1/0.15.2/0.16.0/master | libressl 4.0.0 | no | no | 9 | no | AYCB reference; most referenced (9+ zon hits) |

### boringssl
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/cryptodeal/boringssl | github | 2026-07-02 | min 0.16.0 | boringssl main 3adc3d1 (zon 0.20260616.0) | no | no | 0 | no | |
| https://github.com/akunaakwei/zig-boringssl | github | 2026-04-19 | min 0.16.0 | boringssl 1ad43d6 (+zig-nasm, zig-patch) | no | no | 0 | no | |
| https://github.com/nullstyle/boringssl-zig | github | 2026-09-21 | min 0.17.0-dev.813 | boringssl aef0e2d | no | no | 0 | no | also has a CMake-prebuilt mode; description "vibe-coded" |
| https://github.com/allyourcodebase/boringssl | github (AYCB) | 2026-11-09 | min 0.17.0 | boringssl 190fa71 (zon 0.20260526.0) | no | no | 3 | no | AYCB reference |

### libssh2
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/dasimmet/libssh2 | github | 2026-06-14 | min 0.16.0, CI 0.16.0/master | libssh2 1.11.1 + AYCB zlib | no | no | 0 | no | GitHub fork of allyourcodebase/libssh2 (API `parent`), same head date and zlib pin |
| https://github.com/bytesofpie/zig-libssh2 | github | 2025-09-09 | min 0.15.1, CI 0.15.1/master | libssh2 1.11.1 | no | no | 0 | no | |
| https://github.com/EricTianC/zig-libssh2 | github | 2025-06-11 | unknown | 1.11.1 (zon version) + EricTianC/zig-mbedtls | no | no | 0 | no | |
| https://github.com/allyourcodebase/libssh2 | github (AYCB) | 2026-06-14 | min 0.16.0, CI 0.16.0/master | libssh2 1.11.1 | no | no | 10 | no | AYCB reference |

### zstd
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/akunaakwei/zig-zstd | github | 2026-04-18 | min 0.16.0 | zstd v1.5.7 | no | no | 0 | no | |
| https://github.com/meshy-dev/zig-zstd | github | 2026-03-14 | min 0.15.0 | zstd v1.5.7 | no | no | 0 | no | |
| https://github.com/JacobCrabill/zig-zstd | github | 2025-08-31 | min 0.15.1 | zstd v1.5.7 | no | no | 0 | no | |
| https://github.com/allyourcodebase/zstd | github (AYCB) | 2026-06-03 | min 0.14.0, CI 0.14.1/0.15.2/0.16.0/master | zstd v1.5.7 | no | no | 18 | no | AYCB reference; also Xevion/ffmpeg-hermetic (1.5.7, min 0.17.0) |

### bzip2
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/akunaakwei/zig-bzip2 | github | 2026-04-18 | min 0.16.0 | bzip2 1.0.8 (gitlab) | no | no | 0 | no | |
| https://github.com/silver-signal/zig-bzip2 | github | 2025-07-08 | min 0.14.0 | bzip2 1.0.8 (sourceware) | no | no | 0 | no | |
| https://github.com/allyourcodebase/bzip2 | github (AYCB) | 2025-07-17 | min 0.14.1, CI 0.14.0 | libarchive/bzip2 1.0.8 | no | no | 0 | no | AYCB reference; also ffmpeg-hermetic `build/bzip2.zig` (min 0.17.0) |

### json-c
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/LukasKastern/json-c | github | 2026-11-16 | min 0.17.0 | json-c git f2b558c | no | no | 0 | no | best non-AYCB |
| https://github.com/allyourcodebase/json-c | github (AYCB) | 2026-05-30 | min 0.14.0, CI 0.15.2 | json-c 0.18-20240915 | no | no | 3 | no | AYCB reference |
| https://github.com/Orolia2s/json-c | github | 2024-09-13 | unknown | json-c 0.17 | no | no | 0 | **yes** | archived |

### libiconv
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/allyourcodebase/libiconv | github (AYCB) | 2026-08-31 | min 0.16.0, CI master | GNU libiconv 1.19 | no | no | 1 | no | only GNU libiconv port; most referenced (12 zon hits) |
| https://github.com/Beyley/iconv-zig | github | 2024-03-06 | unknown | win-iconv submodule | no | no | 0 | no | actually win-iconv; stale |

### win-iconv
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/allyourcodebase/win-iconv | github (AYCB) | 2026-03-02 | min 0.15.2, CI master | win-iconv 82f00fb (0.0.10) | no | no | 0 | no | only port besides Beyley/iconv-zig (2024) |

### c-blosc2
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/allyourcodebase/c-blosc2 | github (AYCB) | 2025-10-23 | min 0.15.2 | c-blosc2 v2.21.3 (+AYCB lz4, zstd) | no | no | 0 | no | only port found |

### xz (liblzma)
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| github.com/GabeRealB/pe2-editor `packages/ports/xz` | github | 2026-11-13 (path) | min 0.17.1 | xz 5.8.4 | no | no | 0 | no | sub-package |
| github.com/Xevion/ffmpeg-hermetic `build/xz.zig` | github | 2026-11-18 | min 0.17.0 | xz 5.8.4 | no | no | 0 | no | in-tree |
| https://github.com/akunaakwei/zig-xz | github | 2026-04-18 | min 0.16.0 | xz v5.8.2 | no | no | 0 | no | best standalone |
| https://github.com/neelsani/liblzma | github | 2025-06-01 | min 0.14.0 | xz v5.6.4 | no | no | 0 | no | |

No AYCB xz repo on GitHub or Codeberg (AYCB has fast-lzma2 only).

### libdeflate
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/burakssen/libdeflate | github | 2026-06-06 | min 0.16.0 | libdeflate v1.25 | no | no | 0 | no | newest upstream |
| https://github.com/beef-wrap/libdeflate | github | 2026-07-24 | min 0.16.0, CI 0.16.0 | libdeflate git 24dd71e | no | no | 0 | no | |
| https://github.com/cryptodeal/libdeflate-zig | github | 2026-08-01 | min 0.16.0 | vendored fork (zon 1.18.0-1) | no | no | 0 | no | GitHub fork of neurocyte/libdeflate-zig (API `parent`; neurocyte last commit 2025-09-22) |

### protobuf
| URL | host | last commit | zig | upstream | .pc | cmake | stars | archived | notes |
|---|---|---|---|---|---|---|---|---|---|
| https://github.com/LukasKastern/protobuf | github | 2026-09-28 | min 0.16.0 | protobuf git 5ca1f22 (zon 36.1.0) + abseil | no | no | 1 | no | |
| https://github.com/allyourcodebase/protobuf | github (AYCB) | 2026-07-01 | unknown min, CI 0.16.0 | protobuf 35.1 + AYCB abseil | no | no | 1 | no | AYCB reference (also protobuf-c repo) |

Many other "protobuf" Zig hits (Arwalk/zig-protobuf, etc.) are pure-Zig implementations, not C++ ports.

## Libraries with no port anywhere

- **mpfr, glpk, udunits2, netcdf-c**: no hits on GitHub (repo + code search) or Codeberg.
- **libaec**: no standalone port; only inside rwolters/hdf5 (Codeberg).
- **fribidi**: no standalone port repo; only sub-packages (pe2-editor, ffmpeg-hermetic, AYCB SDL).
- Only-AYCB (no independent port): **c-blosc2, win-iconv, libiconv (GNU)**.

## Queries and commands run

Codeberg (Forgejo):
- `curl https://codeberg.org/api/v1/orgs/allyourcodebase` -> 200; `.../orgs/AllYourCodeBase` -> 200 (same org).
- `curl "https://codeberg.org/api/v1/orgs/allyourcodebase/repos?limit=50&page=N"` N=1 (15 repos), N=2 (0). Saved `raw/cb_org_p*.json`.
- `curl "https://codeberg.org/api/v1/users/search?q=allyourcode"` -> `{"data":[]}` (orgs are not returned by user search).
- **FAILED**: `curl "https://codeberg.org/api/v1/repos/search?q=<lib>&limit=50"` -> HTTP 429 with body
  "Search and filtering is seeing a high influx of requests for this repository, to preserve the
  availability of Codeberg, your search request will not be processed." Retried 3 times over ~2 min
  (`cb_queries.log`), always 429. Abandoned.
- Fallback (worked, 200): Codeberg web explore pages, parsed with `scripts/parse_explore.py`:
  - `https://codeberg.org/explore/repos?language=Zig&page=1..45` (all Zig-language repos on
    Codeberg, 865 repos, `cb_zig_all.tsv`), grepped for every library name.
  - `https://codeberg.org/explore/repos?q=<term>&language=Zig` and `...?q=<term>+zig` for terms:
    gmp mpfr glpk gsl nlopt udunits hdf5 netcdf libpq postgres harfbuzz freetype fribidi png tiff
    jpeg webp libxml2 curl aec mbedtls libressl boringssl libssh2 zstd bzip2 json-c iconv blosc xz
    lzma libdeflate protobuf (`cbx/`, `cb_q_hits.tsv`). The `+zig` keyword variant returned 0 hits
    for every term.
  - Caveat: explore `language=Zig` only covers repos whose language stats include Zig; a port
    repo with Zig detected as non-primary language is still included, one with no Zig file is not.
- `curl https://codeberg.org/api/v1/users/rwolters/repos` (non-search endpoint, OK).
- Per-candidate: `/api/v1/repos/<o>/<r>`, `/commits?sha=<branch>&limit=1`, raw `build.zig`,
  `build.zig.zon`, `README.md`, workflow dirs, git tree (`scripts/detail.sh`).

GitHub (`gh` authenticated as the user; no token printed):
- `gh search repos "<term>" --language=zig --limit 100` and `gh search repos "<term> zig" --limit 100`
  for terms: gmp mpfr glpk gsl nlopt udunits hdf5 netcdf libpq postgres harfbuzz freetype fribidi
  libpng libtiff libjpeg libjpeg-turbo turbojpeg libwebp libxml2 curl libcurl libaec mbedtls
  libressl boringssl libssh2 zstd bzip2 bzip json-c libiconv iconv win-iconv blosc c-blosc2 xz
  liblzma lzma libdeflate protobuf. 82 queries, all OK, no rate-limit error (`queries.log`, `gh/`).
- `gh search code "<term>" --filename build.zig.zon --limit 100` for 34 terms; all OK, 0 errors
  (`code_queries.log`, `ghcode/`). Hit counts: gmp 45, mpfr 0, glpk 0, gsl 33 (mostly wgsl noise),
  nlopt 4, udunits 0, hdf5 5, netcdf 0, libpq 18, fribidi 6, libtiff 11, libjpeg 16, libjpeg-turbo 15,
  libwebp 19, json-c 2, libaec 0, blosc 0, win-iconv 4, liblzma 4, libdeflate 23, libressl 13,
  libssh2 26, bzip2 17, libiconv 17, mbedtls 64, boringssl 60, curl 91, harfbuzz/freetype/libpng/
  libxml2/zstd/xz/protobuf 100 (capped).
- For sparse libraries, fetched each hit's zon via `gh api repos/<r>/contents/<path>` and tallied
  referenced URLs (`zon/`, `zon_urls.tsv`) to find ports that consumers depend on.
- `gh api --paginate orgs/allyourcodebase/repos` (130 repos, `gh_aycb_names.tsv`).
- `gh api users/akunaakwei/repos`, `users/thuvasooriya/repos`, `orgs/ipc-packages/repos`.
- Per-candidate: `gh api repos/<r>`, `repos/<r>/commits?sha=<branch>&per_page=1`,
  raw.githubusercontent.com `build.zig`, `build.zig.zon`, `README.md`, workflows, git tree.
- `gh api repos/ghostty-org/ghostty/contents/pkg`, `repos/GabeRealB/pe2-editor/contents/packages/ports`,
  Xevion/ffmpeg-hermetic tree and zon.

Not done: Windows (x86_64/aarch64-windows-gnu) buildability was not tested for any port; only
`build.zig` text was read.

## Files (this directory)

- `RESULTS.md` (this file)
- `cb_org_names.tsv`, `raw/cb_org_p1.json`, `raw/cb_org_p2.json`: Codeberg AYCB org (15 repos)
- `gh_aycb_names.tsv`, `raw/gh_aycb_repos.json`: GitHub AYCB org (130 repos)
- `cb_zig_all.tsv`, `cb_q_hits.tsv`, `cbx/`: Codeberg explore results
- `gh/`, `gh_merged.txt`: GitHub repo search JSON; `ghcode/`: code search JSON
- `zon/`, `zon_urls.tsv`: consumer zon files and referenced URLs
- `det/<host>__<owner>__<repo>/`, `sub/`: fetched meta, last commit, build.zig, build.zig.zon, README, workflows
- `gh_summary.tsv`, `gh_summary2.tsv`: per-candidate extracted fields
- `queries.log`, `code_queries.log`, `cb_queries.log`: query logs incl. errors
- `scripts/`: the scripts used
