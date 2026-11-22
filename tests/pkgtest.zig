//! The package test every zig-* library recipe runs, on linux right after
//! the cross build and on Windows through `rattler-build test
//! --package-file` (M0 exit criterion 5). One Zig program instead of a
//! shell script: rattler-build runs a test's script with bash on linux and
//! cmd.exe on Windows, and finds `interpreter: bash` on Windows only in the
//! test's build env (m2-bash, which linux cannot install), so the script
//! line is the same plain command for both shells:
//!
//!   zig run --global-cache-dir .zig-global-cache --cache-dir .zig-local-cache
//!     zig-libs-tests/pkgtest.zig -- [<options>] <zig triple> <pc modules>
//!     [<smoke source>...]
//!
//! with `zig` and `pkgconf` in the test's build requirements (and
//! `llvm-tools` for the archive checks below) and $PREFIX the installed
//! (relocated) test prefix. <pc modules> is one module or a comma-separated
//! list, passed to one pkgconf call. It checks, in the sub-prefix
//! <envdir>/zig-libs/<triple> (<envdir> is $PREFIX/Library for a Windows
//! triple, DESIGN 5.4):
//!   1. `pkgconf --cflags --libs <modules>` with PKG_CONFIG_LIBDIR set to
//!      its lib/pkgconfig: every -I/-L directory and every archive path
//!      exists, and at least one -l<n> is a lib<n>.a of the sub-prefix
//!      (the relocatable .pc, DESIGN 5.5, risk R1); the archives found are
//!      "the closure" below;
//!   2. no .pc file names $PREFIX (with either slash) and each uses
//!      ${pcfiledir};
//!   3. no archive holds a build path (rattler-build_, /bld/,
//!      zig-*-cache; decision D22);
//!   4. each <smoke source> (.c with `zig cc`; .cpp, .cc or .cxx with
//!      `zig c++`, which links zig's libc++) built as `zig cc|c++ -target
//!      <triple> -O2 <source> <pkgconf flags>` links a PE image of the
//!      triple's machine, and where the host can run it (Windows on the
//!      same arch) it runs, exits 0 and prints a line `OK`. Elsewhere it
//!      is linked and checked only.
//! Options, each switched on by the recipes that need it:
//!   --require <word>     the pkgconf output has this word (repeatable);
//!   --forbid <word>      the pkgconf output lacks this word (repeatable);
//!   --libcxx             `llvm-nm` over the closure: C++ symbols are
//!                        libc++ (std::__1, what zig links), none
//!                        libstdc++ (std::__cxx11, [abi:cxx11]; DESIGN 5.10);
//!   --unique-c-symbols   no global C-linkage symbol is defined in two
//!                        archives of the closure (an internal copy of
//!                        zlib, SQLite, ... in one archive would clash with
//!                        the zig-* package's, DESIGN 6.5); Itanium C++
//!                        names (_Z...) and __clang_call_terminate are
//!                        COMDAT copies the linker merges and are left out;
//!   --no-dllexport       `llvm-readobj --coff-directives` over the
//!                        closure: no object carries an -export: directive
//!                        (a consumer DLL would re-export it, and MinGW
//!                        auto-export of the DLL's own symbols stops).
//! Exit 0 when everything passes, 1 otherwise, 2 on usage.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;

var failures: usize = 0;

fn failed(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("pkgtest: FAIL " ++ fmt ++ "\n", args);
    failures += 1;
}

fn note(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("pkgtest: " ++ fmt ++ "\n", args);
}

fn usage() u8 {
    std.debug.print(
        \\usage: pkgtest [--libcxx] [--unique-c-symbols] [--no-dllexport]
        \\               [--require <word>]... [--forbid <word>]...
        \\               <zig triple> <pc module>[,<pc module>...] [<smoke source>...]
        \\
    , .{});
    return 2;
}

fn isDir(io: Io, path: []const u8) bool {
    var d = Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    d.close(io);
    return true;
}

fn isFile(io: Io, path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch return false;
    return !isDir(io, path);
}

/// A build path in an archive (decision D22): rattler-build_<pkg>, /bld/,
/// or zig-<word>-cache.
pub fn buildPathIn(data: []const u8) ?[]const u8 {
    for ([_][]const u8{ "rattler-build_", "/bld/" }) |m| if (mem.indexOf(u8, data, m) != null) return m;
    var i: usize = 0;
    while (mem.indexOfPos(u8, data, i, "zig-")) |at| {
        var j = at + 4;
        while (j < data.len and std.ascii.isLower(data[j])) j += 1;
        if (mem.startsWith(u8, data[j..], "-cache")) return "zig-*-cache";
        i = at + 4;
    }
    return null;
}

/// The PE image's machine (MZ, e_lfanew, "PE\0\0", machine).
pub fn peMachine(d: []const u8) ?u16 {
    if (d.len < 0x40 or d[0] != 'M' or d[1] != 'Z') return null;
    const off: usize = mem.readInt(u32, d[0x3c..][0..4], .little);
    if (off > d.len or d.len - off < 6 or !mem.eql(u8, d[off..][0..4], "PE\x00\x00")) return null;
    return mem.readInt(u16, d[off + 4 ..][0..2], .little);
}

/// A C++ source (zig c++) rather than C (zig cc).
pub fn isCxx(src: []const u8) bool {
    for ([_][]const u8{ ".cpp", ".cc", ".cxx" }) |e| if (mem.endsWith(u8, src, e)) return true;
    return false;
}

/// The smoke executable's name: geos.c -> geos-smoke-x86_64.exe,
/// geos.cpp -> geos-cpp-smoke-x86_64.exe (both may be built in one run).
pub fn smokeExeName(a: mem.Allocator, src: []const u8, arch: std.Target.Cpu.Arch) ![]const u8 {
    // either slash, whatever the host (cmd.exe passes a/b, a\b alike)
    const base = if (mem.lastIndexOfAny(u8, src, "/\\")) |k| src[k + 1 ..] else src;
    const dot = mem.lastIndexOfScalar(u8, base, '.') orelse base.len;
    const stem = base[0..dot];
    const ext = if (dot < base.len) base[dot + 1 ..] else "";
    if (mem.eql(u8, ext, "c") or ext.len == 0) return std.fmt.allocPrint(a, "{s}-smoke-{t}.exe", .{ stem, arch });
    return std.fmt.allocPrint(a, "{s}-{s}-smoke-{t}.exe", .{ stem, ext, arch });
}

/// libc++ (St3__1, mangled std::__1) and libstdc++ (__cxx11 in
/// std::__cxx11, B5cxx11 in [abi:cxx11]) occurrences in `llvm-nm` output.
pub fn cxxRuntimeCounts(nm: []const u8) struct { libcxx: usize, libstdcxx: usize } {
    return .{
        .libcxx = mem.count(u8, nm, "St3__1"),
        .libstdcxx = mem.count(u8, nm, "__cxx11") + mem.count(u8, nm, "B5cxx11"),
    };
}

/// The global C-linkage symbol a `llvm-nm` line defines, or null: an
/// upper-case type other than U (undefined), W/V (weak), C (common) and
/// I (indirect); no Itanium C++ name, no `.refptr.*`-like or MSVC name, no
/// __clang_call_terminate (a COMDAT helper clang emits in many objects).
pub fn cSymbolDefined(line: []const u8) ?[]const u8 {
    var f = mem.tokenizeScalar(u8, mem.trimEnd(u8, line, "\r"), ' ');
    // `<addr> <type> <name>`; undefined symbols have no address
    const first = f.next() orelse return null;
    const t = f.next() orelse return null;
    const sym = mem.trim(u8, f.rest(), " ");
    if (first.len == 1) return null; // `U name`
    if (t.len != 1 or sym.len == 0 or !std.ascii.isUpper(t[0])) return null;
    if (mem.indexOfScalar(u8, "UWVCI", t[0]) != null) return null;
    if (mem.eql(u8, sym, "__clang_call_terminate")) return null;
    if (mem.startsWith(u8, sym, "_Z") or mem.startsWith(u8, sym, "__Z") or sym[0] == '.' or sym[0] == '?') return null;
    return sym;
}

/// Objects of `llvm-readobj --coff-directives` output whose directives
/// export a symbol (-export: as lld/MinGW writes it, /EXPORT: as MSVC).
pub fn exportingObjects(readobj: []const u8) usize {
    var n: usize = 0;
    var blocks = mem.splitSequence(u8, readobj, "\nFile: ");
    while (blocks.next()) |b| {
        if (mem.indexOf(u8, b, "-export:") != null or mem.indexOf(u8, b, "/EXPORT:") != null) n += 1;
    }
    return n;
}

const Options = struct {
    libcxx: bool = false,
    unique_c_symbols: bool = false,
    no_dllexport: bool = false,
    require: std.ArrayList([]const u8) = .empty,
    forbid: std.ArrayList([]const u8) = .empty,
    positional: std.ArrayList([]const u8) = .empty,
};

pub fn main(init: std.process.Init) !u8 {
    const a = init.arena.allocator();
    const io = init.io;
    const env = init.environ_map;
    const args: []const []const u8 = try init.minimal.args.toSlice(a);

    var o: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (mem.eql(u8, x, "--libcxx")) {
            o.libcxx = true;
        } else if (mem.eql(u8, x, "--unique-c-symbols")) {
            o.unique_c_symbols = true;
        } else if (mem.eql(u8, x, "--no-dllexport")) {
            o.no_dllexport = true;
        } else if (mem.eql(u8, x, "--require") or mem.eql(u8, x, "--forbid")) {
            if (i + 1 >= args.len) return usage();
            i += 1;
            try (if (x[2] == 'r') &o.require else &o.forbid).append(a, args[i]);
        } else if (mem.startsWith(u8, x, "--")) {
            std.debug.print("pkgtest: unknown option {s}\n", .{x});
            return usage();
        } else try o.positional.append(a, x);
    }
    if (o.positional.items.len < 2) return usage();
    const triple = o.positional.items[0];
    var modules: std.ArrayList([]const u8) = .empty;
    var mit = mem.tokenizeScalar(u8, o.positional.items[1], ',');
    while (mit.next()) |m| try modules.append(a, m);
    if (modules.items.len == 0) return usage();
    const smokes = o.positional.items[2..];
    const arch: std.Target.Cpu.Arch = if (mem.startsWith(u8, triple, "x86_64-"))
        .x86_64
    else if (mem.startsWith(u8, triple, "aarch64-"))
        .aarch64
    else {
        std.debug.print("pkgtest: unknown triple {s}\n", .{triple});
        return 2;
    };
    const windows = mem.indexOf(u8, triple, "-windows") != null;

    const prefix = env.get("PREFIX") orelse {
        std.debug.print("pkgtest: PREFIX is not set (run under rattler-build test)\n", .{});
        return 2;
    };
    const sub = try std.fs.path.join(a, if (windows) &.{ prefix, "Library", "zig-libs", triple } else &.{ prefix, "zig-libs", triple });
    const libdir = try std.fs.path.join(a, &.{ sub, "lib" });
    const pcdir = try std.fs.path.join(a, &.{ libdir, "pkgconfig" });
    note("host {t}-{t}, sub-prefix {s}", .{ builtin.os.tag, builtin.cpu.arch, sub });
    if (!isDir(io, pcdir)) {
        failed("no {s}", .{pcdir});
        return 1;
    }

    // zig cc below: its caches in the test directory, as the zig run above
    var child_env = try env.clone(a);
    const cwd_path = try std.process.currentPathAlloc(io, a);
    try child_env.put("PKG_CONFIG_LIBDIR", pcdir);
    try child_env.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(a, &.{ cwd_path, ".zig-global-cache" }));
    try child_env.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ cwd_path, ".zig-local-cache" }));

    // 1. pkgconf
    const module_list = try mem.join(a, " ", modules.items);
    var pc_argv: std.ArrayList([]const u8) = .empty;
    try pc_argv.appendSlice(a, &.{ "pkgconf", "--cflags", "--libs" });
    try pc_argv.appendSlice(a, modules.items);
    const pc = try std.process.run(a, io, .{ .argv = pc_argv.items, .environ_map = &child_env });
    if (pc.stderr.len > 0) std.debug.print("{s}", .{pc.stderr});
    if (!pc.term.success()) {
        failed("pkgconf --cflags --libs {s}: {f}", .{ module_list, pc.term });
        return 1;
    }
    const flags_text = mem.trim(u8, pc.stdout, " \t\r\n");
    note("pkgconf --cflags --libs {s}: {s}", .{ module_list, flags_text });
    var flags: std.ArrayList([]const u8) = .empty;
    var dirs: std.ArrayList([]const u8) = .empty;
    var words = mem.tokenizeAny(u8, flags_text, " \t\r\n");
    while (words.next()) |w| {
        try flags.append(a, w);
        if (mem.startsWith(u8, w, "-I") or mem.startsWith(u8, w, "-L")) {
            const d = w[2..];
            if (isDir(io, d)) {
                note("exists: {s}", .{d});
                if (w[1] == 'L') try dirs.append(a, d);
            } else failed("{s}: no such directory {s}", .{ w[0..2], d });
        } else if (mem.endsWith(u8, w, ".a") and !mem.startsWith(u8, w, "-")) {
            if (!isFile(io, w)) failed("no such archive {s}", .{w});
        }
    }
    // the closure: the archives of the sub-prefix that the -l words name
    var closure: std.ArrayList([]const u8) = .empty;
    for (flags.items) |w| {
        if (!mem.startsWith(u8, w, "-l")) continue;
        const name = try std.fmt.allocPrint(a, "lib{s}.a", .{w[2..]});
        for (dirs.items) |d| {
            const path = try std.fs.path.join(a, &.{ d, name });
            if (isFile(io, path)) {
                note("{s} -> {s}", .{ w, path });
                for (closure.items) |c| {
                    if (mem.eql(u8, c, path)) break;
                } else try closure.append(a, path);
                break;
            }
        } else note("{s}: not in a -L directory (a system library)", .{w});
    }
    if (closure.items.len == 0) failed("no -l of `pkgconf --libs {s}` names an archive of the sub-prefix", .{module_list});
    for (o.require.items) |r| {
        for (flags.items) |w| {
            if (mem.eql(u8, w, r)) {
                note("has {s}", .{r});
                break;
            }
        } else failed("pkgconf output lacks {s}", .{r});
    }
    for (o.forbid.items) |r| {
        for (flags.items) |w| {
            if (mem.eql(u8, w, r)) {
                failed("pkgconf output has {s}", .{r});
                break;
            }
        } else note("has no {s}", .{r});
    }

    // 2. .pc files: relocatable
    {
        const fwd = try a.dupe(u8, prefix);
        mem.replaceScalar(u8, fwd, '\\', '/');
        const back = try a.dupe(u8, prefix);
        mem.replaceScalar(u8, back, '/', '\\');
        var d = try Io.Dir.cwd().openDir(io, pcdir, .{ .iterate = true });
        defer d.close(io);
        var it = d.iterate();
        while (try it.next(io)) |e| {
            if (!mem.endsWith(u8, e.name, ".pc")) continue;
            const text = try d.readFileAlloc(io, e.name, a, .limited(1 << 20));
            for ([_][]const u8{ fwd, back }) |p| if (mem.indexOf(u8, text, p) != null) failed("{s} names the absolute prefix {s}", .{ e.name, p });
            if (mem.indexOf(u8, text, "${pcfiledir}") == null) failed("{s} does not use ${{pcfiledir}}", .{e.name});
        }
    }

    // 3. archives: no build paths
    {
        var d = try Io.Dir.cwd().openDir(io, libdir, .{ .iterate = true });
        defer d.close(io);
        var it = d.iterate();
        var n: usize = 0;
        while (try it.next(io)) |e| {
            if (!mem.endsWith(u8, e.name, ".a")) continue;
            n += 1;
            const data = try d.readFileAlloc(io, e.name, a, .limited(1 << 31));
            if (buildPathIn(data)) |m| failed("{s} holds a build path ({s})", .{ e.name, m });
        }
        note("{d} archive(s) checked for build paths", .{n});
    }

    // archive checks over the closure (llvm-tools)
    if (o.libcxx or o.unique_c_symbols) {
        var libcxx: usize = 0;
        var libstdcxx: usize = 0;
        // symbol -> index of the first archive that defines it; closure.len
        // once reported
        var owner: std.StringHashMapUnmanaged(usize) = .empty;
        var dups: usize = 0;
        for (closure.items, 0..) |archive, ai| {
            const r = try std.process.run(a, io, .{
                .argv = &.{ "llvm-nm", archive },
                .environ_map = &child_env,
                .stdout_limit = .limited(1 << 31),
            });
            if (!r.term.success()) {
                std.debug.print("{s}", .{r.stderr});
                failed("llvm-nm {s}: {f}", .{ archive, r.term });
                continue;
            }
            const c = cxxRuntimeCounts(r.stdout);
            libcxx += c.libcxx;
            libstdcxx += c.libstdcxx;
            if (!o.unique_c_symbols) continue;
            var lines = mem.splitScalar(u8, r.stdout, '\n');
            while (lines.next()) |line| {
                const sym = cSymbolDefined(line) orelse continue;
                const gop = try owner.getOrPut(a, sym);
                if (!gop.found_existing) {
                    gop.value_ptr.* = ai;
                } else if (gop.value_ptr.* != ai and gop.value_ptr.* != closure.items.len) {
                    if (dups < 20) note("{s} defined in {s} and {s}", .{ sym, std.fs.path.basename(closure.items[gop.value_ptr.*]), std.fs.path.basename(archive) });
                    dups += 1;
                    gop.value_ptr.* = closure.items.len;
                }
            }
        }
        if (o.libcxx) {
            note("llvm-nm over {d} archive(s): {d} std::__1 (libc++), {d} __cxx11 (libstdc++)", .{ closure.items.len, libcxx, libstdcxx });
            if (libcxx == 0) failed("no std::__1 symbol: not built against libc++", .{});
            if (libstdcxx != 0) failed("{d} __cxx11 symbol(s): libstdc++ ABI", .{libstdcxx});
        }
        if (o.unique_c_symbols) {
            note("{d} global C-linkage symbol(s) defined in two archives of the closure", .{dups});
            if (dups != 0) failed("duplicate C-linkage symbols in the closure", .{});
        }
    }
    if (o.no_dllexport) {
        var n: usize = 0;
        for (closure.items) |archive| {
            const r = try std.process.run(a, io, .{
                .argv = &.{ "llvm-readobj", "--coff-directives", archive },
                .environ_map = &child_env,
                .stdout_limit = .limited(1 << 31),
            });
            if (!r.term.success()) {
                std.debug.print("{s}", .{r.stderr});
                failed("llvm-readobj --coff-directives {s}: {f}", .{ archive, r.term });
                continue;
            }
            const e = exportingObjects(r.stdout);
            if (e != 0) note("{s}: {d} object(s) with -export:", .{ std.fs.path.basename(archive), e });
            n += e;
        }
        note("llvm-readobj over {d} archive(s): {d} object(s) with -export: directives", .{ closure.items.len, n });
        if (n != 0) failed("the closure carries dllexport directives", .{});
    }

    // 4. smoke executables
    for (smokes) |src| {
        const exe = try smokeExeName(a, src, arch);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ "zig", if (isCxx(src)) "c++" else "cc", "-target", triple, "-O2", src });
        try argv.appendSlice(a, flags.items);
        try argv.appendSlice(a, &.{ "-o", exe });
        note("link: {s}", .{try mem.join(a, " ", argv.items)});
        var child = try std.process.spawn(io, .{ .argv = argv.items, .environ_map = &child_env });
        const term = try child.wait(io);
        if (!term.success()) {
            failed("zig {s} {s}: {f}", .{ argv.items[1], src, term });
            continue;
        }
        const image = try Io.Dir.cwd().readFileAlloc(io, exe, a, .limited(1 << 30));
        const want: u16 = if (arch == .x86_64) 0x8664 else 0xaa64;
        const got = peMachine(image);
        if (got != want) failed("{s}: PE machine {?x}, want {x}", .{ exe, got, want }) else note("{s}: PE machine 0x{x}, {d} bytes", .{ exe, want, image.len });

        if (windows and builtin.os.tag == .windows and builtin.cpu.arch == arch) {
            const exe_path = try std.fs.path.join(a, &.{ cwd_path, exe });
            const r = try std.process.run(a, io, .{ .argv = &.{exe_path} });
            std.debug.print("{s}{s}", .{ r.stdout, r.stderr });
            var ok_line = false;
            var lines = mem.tokenizeAny(u8, r.stdout, "\r\n");
            while (lines.next()) |l| if (mem.eql(u8, l, "OK")) {
                ok_line = true;
            };
            if (!r.term.success()) failed("{s}: {f}", .{ exe, r.term });
            if (!ok_line) failed("{s} printed no line OK", .{exe});
            if (r.term.success() and ok_line) note("{s} ran: OK", .{exe});
        } else note("{s} not run: host is {t}-{t}", .{ exe, builtin.os.tag, builtin.cpu.arch });
    }

    if (failures > 0) {
        note("{d} failure(s)", .{failures});
        return 1;
    }
    note("all checks passed", .{});
    return 0;
}

const testing = std.testing;

test "buildPathIn" {
    try testing.expectEqualStrings("/bld/", buildPathIn("x /bld/rattler y").?);
    try testing.expectEqualStrings("zig-*-cache", buildPathIn("a zig-global-cache/o b").?);
    try testing.expectEqualStrings("zig-*-cache", buildPathIn("zig--cache").?);
    try testing.expect(buildPathIn("zig-libs.obj zig-toolchain zig-") == null);
}

test "peMachine" {
    var pe: [0x90]u8 = @splat(0);
    pe[0] = 'M';
    pe[1] = 'Z';
    pe[0x3c] = 0x80;
    @memcpy(pe[0x80..0x84], "PE\x00\x00");
    pe[0x84] = 0x64;
    pe[0x85] = 0x86;
    try testing.expectEqual(@as(?u16, 0x8664), peMachine(&pe));
    pe[0x3c] = 0xfe;
    pe[0x3d] = 0xff;
    pe[0x3e] = 0xff;
    pe[0x3f] = 0xff;
    try testing.expectEqual(@as(?u16, null), peMachine(&pe));
}

test "smoke sources: C or C++, executable names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expect(!isCxx("zig-libs-tests/smoke/geos.c"));
    try testing.expect(isCxx("zig-libs-tests/smoke/geos.cpp"));
    try testing.expect(isCxx("x.cc"));
    try testing.expectEqualStrings("geos-smoke-x86_64.exe", try smokeExeName(a, "zig-libs-tests/smoke/geos.c", .x86_64));
    try testing.expectEqualStrings("geos-cpp-smoke-aarch64.exe", try smokeExeName(a, "zig-libs-tests\\smoke\\geos.cpp", .aarch64));
}

test "C++ runtime counts in llvm-nm output" {
    const c = cxxRuntimeCounts(
        \\0000000000000000 T _ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE4findEPKcyy
        \\                 U _ZNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEE9_M_createERyy
        \\0000000000000010 T _ZN4absl12lts_2025012710StrCatB5cxx11ERKNS0_8AlphaNumE
        \\
    );
    try testing.expectEqual(@as(usize, 1), c.libcxx);
    try testing.expectEqual(@as(usize, 2), c.libstdcxx);
}

test "C-linkage definitions in llvm-nm output" {
    try testing.expectEqualStrings("deflate", cSymbolDefined("0000000000000000 T deflate").?);
    try testing.expectEqualStrings("z_errmsg", cSymbolDefined("0000000000000040 R z_errmsg\r").?);
    try testing.expect(cSymbolDefined("                 U inflate") == null);
    try testing.expect(cSymbolDefined("0000000000000000 t local_fn") == null);
    try testing.expect(cSymbolDefined("0000000000000000 W weak_fn") == null);
    try testing.expect(cSymbolDefined("0000000000000000 T _ZN4geos4geom8Geometry4areaEv") == null);
    try testing.expect(cSymbolDefined("0000000000000000 R .refptr.x") == null);
    try testing.expect(cSymbolDefined("0000000000000000 T __clang_call_terminate") == null);
    try testing.expect(cSymbolDefined("libz.a(adler32.c.obj):") == null);
}

test "objects with export directives in llvm-readobj output" {
    const out =
        \\
        \\File: libtbb12.a(address_waiter.cpp.obj)
        \\Format: COFF-x86-64
        \\Directive(s):  -exclude-symbols:_ZN3tbb6detail2r1a -export:_ZN3tbb6detail2r115wait_on_addressEPv
        \\
        \\File: libtbb12.a(allocator.cpp.obj)
        \\Format: COFF-x86-64
        \\Directive(s):  -exclude-symbols:__clang_call_terminate
        \\
        \\File: libx.a(x.obj)
        \\Directive(s):  /EXPORT:x
        \\
    ;
    try testing.expectEqual(@as(usize, 2), exportingObjects(out));
    try testing.expectEqual(@as(usize, 0), exportingObjects("\nFile: libz.a(adler32.c.obj)\nFormat: COFF-x86-64\n"));
}
