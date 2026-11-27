# slice3: libcurl with Rtools45's features, protobuf, libgnurx

Brief written 2026-11-26 on top of main eee907d (slice 2 published
2026-11-25, zig-libcurl build 1 on 2026-11-26, selective CI D129).
Interface: CONTRACT.md. Previous record: slice2/PLAN.md (D102-D129,
S2-F1..F38). Decisions here continue at D130; findings are S3-F1 onward.

Tags: **V** verified, **I** inferred, **A** assumption.

## Goal

1. zig-libcurl with Rtools45's features: SFTP/SCP (libssh2), HTTP/2
   (nghttp2), IDN through libidn2 and the public suffix list (libpsl),
   so R packages written against Rtools45's curl get the same behaviour
   and the link names their Makevars.win hard-code resolve.
2. zig-protobuf with its own protoc, so protolite and RProtoBuf build on
   both Windows arches against one protobuf (r-zig-pixi D5: on win-arm64
   protolite failed with the tree's protobuf headers and conda-forge's
   protoc).
3. zig-libgnurx (regex.h, libregex.a), r-zig-pixi's request for its
   build 14 (Rhtslib; r-zig-pixi build14 .github/devdocs/b14-rhtslib/
   PLAN.md F1-F12), so Windows no longer needs the Rtools tree.
4. r-consumer on r-zig build 13 without the D124 LOCAL_SOFT workaround.

One branch (feat-curl-parity), one PR, one publish (user, 2026-11-26).

## What Rtools45 has (build 6768)

From the extracted trees in the r-zig-pixi scratch
(next/probe-rtools-x64/tree, next/probe-rtools/e2e; headers and
closedpc/*.pc), the same on x64 and aarch64:

| Library | Version | Rtools45's build |
|---|---|---|
| libcurl | 8.18.0 | OpenSSL and Schannel, libssh2, nghttp2, libidn2, libpsl, zstd, zlib, brotli |
| libssh2 | 1.11.1 | libgcrypt + libgpg-error, zlib |
| nghttp2 | 1.68.0 | library only, -DNGHTTP2_STATICLIB |
| libidn2 | 2.3.8 | libunistring, libiconv |
| libunistring | 1.4.1 | no .pc |
| libpsl | 0.21.5 | libidn2, libunistring, -DPSL_STATIC |
| protobuf | 29.5 | abseil 20250127, utf8_range, upb, libprotoc, protoc.exe |
| libgnurx | 2.6.1 | MXE; include/regex.h (22162 bytes), libregex.a, libgnurx.a (hard link), no .pc |

Hard-coded link lists in CRAN/Bioconductor sources (read 2026-11-26):
Rhtslib's Makevars.win `-lcurl -lsecur32 [-lnghttp2] [-lpsl] -lbcrypt
-lidn2 -lunistring -liconv -lssl -lcrypto -lz -lcrypt32 -lwsock32
-lwldap32 -lssh2 -lgcrypt -lgpg-error -lws2_32 -lzstd -lregex`; the
rwinlib fallbacks of curl, gert and sf link `-lssh2 -lssl -lcrypto`.
protolite 2.4.0 uses `pkg-config --libs protobuf` and a bare `protoc`
(else it downloads r-windows' protobuf 21.12); RProtoBuf 0.4.28's
Makevars.ucrt uses `pkg-config --libs protobuf` or `-lprotobuf`.

## Decisions

| # | Question | Options | Choice | Reason | Who |
|---|---|---|---|---|---|
| D130 | libcurl parity: libssh2's crypto backend and IDN | libssh2: A zig-openssl; B WinCNG; C libgcrypt + libgpg-error (Rtools45). IDN/PSL: A libpsl, IDN stays WinIDN; B libidn2 + libunistring + libpsl (Rtools45) | libssh2 A, IDN B; new zig-nghttp2, zig-libssh2, zig-libunistring, zig-libidn2, zig-libpsl; zig-libcurl build 2 on them, still Schannel TLS (D126 B); no zig-libgcrypt or zig-libgpg-error. Dated 2026-11-26 | libssh2 on OpenSSL is what Linux, macOS, conda-forge and the rwinlib lists use; libgcrypt is MXE's choice only. libidn2 gives the same IDNA2008 behaviour as Linux and Rtools45 and resolves Rhtslib's -lidn2 -lunistring. Rhtslib's -lgcrypt -lgpg-error are dropped by rzig when they do not resolve (r-zig-pixi H2 a); curl on OpenSSL never calls them | user, after r-zig-pixi's answer (2026-11-26: "go with your plan") |
| D131 | zig-libgnurx (r-zig-pixi build 14 request, H1 a) | A Rtools45's layout: regex.h, libregex.a and the same archive as libgnurx.a, regex.pc; B a POSIX regex from another library (TRE, PCRE2-posix) | A, dated 2026-11-26 | the request; htslib includes <regex.h> and Rtools45 ships MXE's libgnurx | r-zig-pixi request, my default |
| D132 | zig-protobuf | A 29.5 (Rtools45) with protoc.exe; B 29.5 libraries only; C the newest (36.x) | A, dated 2026-11-26. protoc.exe in the sub-prefix's bin/ (native per arch, not Library/bin); protobuf.pc brings the absl_* and utf8_range closure; GNU Cflags only; no PROTOBUF_USE_DLLS | 29.x is the last series before v30 changed C++ descriptor APIs to return absl::string_view; Rtools45's version is what CRAN's Windows checks use; zig-abseil 20250127 is its abseil. r-zig-pixi puts zig-libs/bin on R CMD's PATH in its build 14 | user (asked to follow r-zig-pixi), r-zig-pixi |
| D133 | r-consumer after r-zig build 13 (2026-11-26, LOCAL_SOFT defaults to zig-libs) | A pin *_13, drop the D124 LOCAL_SOFT export; B keep *_12 | A, dated 2026-11-26. Until r-zig build 14, r-consumer puts zig-libs/bin on PATH for protolite's protoc | the workaround's own exit condition (slice2 D124) | my default (D124 said so) |

## Findings

**S3-F1 V. zig-libcurl build 1 fixes Rhtslib on win-arm64 (slice2
D128, S2-F35; 2026-11-26, r-zig-pixi stress).** Run 45858117550
(r-zig-pixi 55ce1db, build 13's code, lock cf4b3220532c, Rtools45 tree
still on), windows-11-arm: tree leg 168 ok, conda leg 168 ok; Rhtslib
and Rsamtools ok on both legs (before: `undefined symbol:
if_nametoindex`). Not ok and expected: protolite (a duplicate
`std::__1::bad_function_call` between the r-windows protobuf bundle and
zig's libc++, which zig-protobuf with protoc on PATH replaces, D132),
arrow, rstan's smoke. libs smoke 21/21. Without the tree (r-zig build
14) Rhtslib also needs regex.h: zig-libgnurx (D131).

**S3-F2 V. nghttp2 and libssh2 (2026-11-26, gamma; evidence and logs in
the scratch s3/notes-a.md, a-*.log).** nghttp2 1.68.0 (CMake,
ENABLE_LIB_ONLY, static): its libnghttp2.pc has no -DNGHTTP2_STATICLIB
(the CMake target sets it only as a usage requirement), and nghttp2.h
dllimports every function without it; build.sh appends it to Cflags (as
Rtools45's .pc has it). libssh2 1.11.1 (CMake, CRYPTO_BACKEND=OpenSSL,
ENABLE_ZLIB_COMPRESSION=ON): needs libcrypto only (Requires libcrypto,
zlib); its static .pc kept the .private lines next to the folded public
ones, so close-pc doubled every word: build.sh drops the .private lines
first, as zig-libcurl's does. libssh2.h dllimports only for a DLL build.
The smoke checks the OpenSSL engine, zlib compression, ssh-ed25519,
curve25519-sha256 and aes256-gcm (WinCNG has neither ed25519 nor
curve25519).

**S3-F3 V. libunistring, libidn2, libpsl (2026-11-26, gamma;
s3/notes-b.md).** libunistring 1.4.1 and libidn2 2.3.8 through
`zig-toolchain configure`, libpsl 0.21.5 through meson (only meson
compiles with -DPSL_STATIC and writes it into libpsl.pc; autotools would
dllimport). Duplicate symbols the closure check found and their fixes,
in the new packages only (zig-libiconv, published, unchanged):
`locale_charset` in libunistring.a and libiconv.a (renamed in
libunistring with -Dlocale_charset=libunistring_locale_charset);
libidn2.a's bundled gnulib copies of `_UC_CATEGORY_NONE` and
`locale_charset` (renamed the same way); build.sh checks each with
llvm-nm. libunistring's DLL VERSIONINFO resource breaks zig rc as
libiconv's did (`WOE32_LIBADD=`). libpsl's built-in list embeds the
list's path: `-Dpsl_file=../list/public_suffix_list.dat` keeps the build
path out. Meson's `-Dc_args` replaces the environment's CFLAGS (the
activation's -ffile-prefix-map was lost): build.sh passes ${CFLAGS}
first; any meson recipe that sets c_args needs the same. The DAFSA
generator runs on an unpinned python, as zig-harfbuzz's generators do
(its output depends on the list file only). GPG signatures of all three
tarballs verified.

**S3-F4 V. libgnurx (2026-11-26, gamma; s3/notes-c.md).** regex.c
compiled directly (`$CC -std=gnu99`, one object, as MXE's build gives);
libgnurx.a is a copy of libregex.a (links do not survive extraction
everywhere). regex.h byte-identical to Rtools45's on both arches; the
15 global symbols are exactly Rtools45's libregex.a's; undefined
symbols are C runtime only, so regex.pc has no Requires. htslib 1.18's
hts_expr.c compiles against it for both arches (without it: `'regex.h'
file not found`).

**S3-F5 V. protobuf 29.5 (2026-11-26, gamma; s3/notes-d.md).**
- Patch 0001: port_def.inc enables weak descriptor messages for any
  non-MSVC clang, MinGW included; protoc.exe then failed with `lld-link:
  error: undefined symbol: __start_pb_defaults`. Backport of upstream's
  v31.0 fix (5769732ec0, #20025: `&& !defined(_WIN32)`); 29.6 and 30.0
  lack it. The header is installed, so consumers' generated code sees
  the same guard.
- Patch 0002: utf8_range.c is compiled into both libutf8_range.a and
  libutf8_validity.a (`utf8_range_IsValid` defined twice); utf8_validity
  now links utf8_range. utf8_range.pc gives `-lutf8_validity
  -lutf8_range`, as Rtools45's protobuf.pc; a hard-coded
  `-lutf8_validity` alone would no longer link (none seen).
- CMake on linux installs each .exe as a versioned file plus a symlink
  (protoc.exe -> protoc.exe-29.5.0); build.sh moves the file to the
  plain name and rewrites the exported CMake targets.
- `protoc --version`: "libprotoc 29.5" (PROTOBUF_OSS_VERSION 5029005,
  empty suffix; checked in build.sh).
- protobuf.pc and protobuf-lite.pc: Requires 38 absl_* modules and
  utf8_range, Cflags -I only (no PROTOBUF_USE_DLLS, no MSVC flags;
  pkgtest forbids them); the closure is 84 archives with -ladvapi32
  -ldbghelp -lbcrypt.
- Rtools45 parity: no zlib (its protobuf.pc has none), libprotoc and
  upb built; the three protoc-gen-upb* plugins stay because protobuf's
  CMake config imports them.
- The smoke's .pb.h/.pb.cc are committed, generated by upstream's
  protoc-29.5-linux-x86_64.zip (conda-forge has no 5.29.5); the
  generated `PROTOBUF_VERSION != 5029005` check pins them to the
  package's headers. On Windows the smoke also runs the package's
  protoc.exe: its version line and a byte-identical `--cpp_out`.


**S3-F6 V. zig-libcurl build 2 (2026-11-26, gamma; s3/e-curl-*.log).**
curl's CMake finds the four libraries with find_path/find_library in the
sub-prefix (pkg-config stays off when cross compiling, so no unpinned
pkgconf shapes the build): `Found NGHTTP2 ... 1.68.0`, `Libidn2 2.3.8`,
`Libpsl 0.21.5`, `Libssh2 1.11.1`; protocols gain scp and sftp, SSL
backends Schannel only. No .pc -D reaches curl's sources that way, so
build.sh adds -DNGHTTP2_STATICLIB -DPSL_STATIC to CFLAGS and fails on any
`__imp_` reference to a zig-* library in libcurl.a (llvm-nm), and on a
missing USE_LIBSSH2, USE_NGHTTP2, HAVE_LIBIDN2, USE_LIBPSL or a set
USE_WIN32_IDN in curl_config.h (nghttp2 and libidn2 are optional to
curl). libcurl.pc: `Requires: libssh2,libidn2,zlib,libbrotlidec,
libbrotlicommon,libzstd,libnghttp2,libpsl`, `Libs: -L${libdir} -lcurl
-lssh2 -lidn2 -lz -lbrotlidec -lbrotlicommon -lzstd -lnghttp2 -lwldap32
-lpsl -lbcrypt -ladvapi32 -lcrypt32 -lsecur32 -lws2_32` (-lnormaliz went
with WinIDN); features alt-svc AsynchDNS brotli HSTS HTTP2 HTTPS-proxy
IDN IPv6 Kerberos Largefile libz NTLM PSL SPNEGO SSL SSPI threadsafe
UnixSockets zstd. pkgtest over the closure (libcrypto, libunistring,
iconv through Requires; NGHTTP2_STATICLIB, PSL_STATIC in Cflags) passes
with no duplicate C symbol; the smoke links on both arches (win-64
`zig_f8676a9_2`, win-arm64 `zig_078318b_2`).

**S3-F7 V. Review of the branch (2026-11-26, an independent read of
the diff; fixed on the branch).** (1) curl calls `idn2_lookup_ul`
(ENABLE_UNICODE off, curl's default), which reads the host name in the
locale's charset; in the "C" locale on Windows that is the ANSI code page
(CP1252 on the runners), so a UTF-8 host would be misread: the libcurl
smoke sets `setlocale(LC_CTYPE, ".UTF-8")`, as R (UTF-8 since 4.2) runs.
A non-UTF-8 C consumer must pass punycode or set a UTF-8 locale, as with
Rtools45's curl. (2) zig-protobuf's licence is BSD-3-Clause AND MIT
(utf8_range). (3) zig-libgnurx's test forbids .exe, .la and share/ like
the others. (4) libpsl's python (the DAFSA generator) and meson's
pkgconf are unpinned, as in zig-harfbuzz, zig-libpq, zig-fribidi and
zig-freetype: a known gap of variants.yaml's rule, left for a separate
decision. (5) libcurl's llvm-nm check captures the listing first, so a
failing llvm-nm stops the build. (6) the libpsl smoke's header no longer
claims to run libidn2 (the built-in context needs no IDNA). (7)
r-consumer checks protolite's install log for `using protobuf and
libprotoc 29.5`, so a fallback to r-windows' bundle cannot pass. (8) doc
fixes (libssh2 test comment; CONTRACT: protoc-gen-upb plugins).


**S3-F8 V. First Windows run: PR #11 CI run 45941523863 (2026-11-27).**
Every check except one passed on both arches:
- Alignment: 9/9 ok.
- r-consumer: 24/24 INSTALL ok, and the protolite log grep matched.
- SMOKE: 68/68 PASS on win-64 and 66/66 on win-arm64 (+2 each:
  protolite round trip, and RProtoBuf libprotobuf 29.5 with a message
  round trip).
- test: 8 packages per arch, 7 passed. zig-libcurl's IDN check
  (punycode both ways) passed. zig-protobuf's checks passed: `protoc
  --version`, the byte-identical regeneration and the link test.

The one failure was the zig-libssh2 smoke on both arches: "method 6:
1 algorithms, zlib MISSING". The cause is in the test, not the package.
libssh2 lists zlib among the COMP methods only once the session has
LIBSSH2_FLAG_COMPRESS set (src/comp.c `_libssh2_comp_methods`), and the
smoke set the flag after it checked the list. The smoke now sets the
flag first. The local tests did not catch this because no .exe runs on
linux-64.

protolite's "from Rtools" in its install log is fixed text
(Makevars.win:9). It means only that `pkg-config --libs protobuf` and
`protoc` both answered, here with zig-protobuf's. Rtools45 also has
protobuf 29.5, so the grep alone cannot tell the two apart. What does
tell them apart: Rtools' gcc-built libprotobuf.a cannot link with zig's
libc++, and the RProtoBuf smoke checks libprotobuf 29.5.
