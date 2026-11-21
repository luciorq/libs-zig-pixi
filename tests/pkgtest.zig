//! The package test every zig-* library recipe runs, on linux right after
//! the cross build and on Windows through `rattler-build test
//! --package-file` (M0 exit criterion 5). One Zig program instead of a
//! shell script: rattler-build runs a test's script with bash on linux and
//! cmd.exe on Windows, and finds `interpreter: bash` on Windows only in the
//! test's build env (m2-bash, which linux cannot install), so the script
//! line is the same plain command for both shells:
//!
//!   zig run --global-cache-dir .zig-global-cache --cache-dir .zig-local-cache
//!     zig-libs-tests/pkgtest.zig -- <zig triple> <pc module> [<smoke.c>]
//!
//! with `zig` and `pkgconf` in the test's build requirements and $PREFIX
//! the installed (relocated) test prefix. It checks, in the sub-prefix
//! <envdir>/zig-libs/<triple> (<envdir> is $PREFIX/Library for a Windows
//! triple, DESIGN 5.4):
//!   1. `pkgconf --cflags --libs <module>` with PKG_CONFIG_LIBDIR set to
//!      its lib/pkgconfig: every -I/-L directory and every archive path
//!      exists, and at least one -l<n> is a lib<n>.a of the sub-prefix
//!      (the relocatable .pc, DESIGN 5.5, risk R1);
//!   2. no .pc file names $PREFIX (with either slash) and each uses
//!      ${pcfiledir};
//!   3. no archive holds a build path (rattler-build_, /bld/,
//!      zig-*-cache; decision D22);
//!   4. with <smoke.c>: `zig cc -target <triple> -O2 <smoke.c> <pkgconf
//!      flags>` links a PE image of the triple's machine, and where the host
//!      can run it (Windows on the same arch) it runs, exits 0 and prints a
//!      line `OK`. Elsewhere it is linked and checked only.
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

/// $PREFIX in both slash spellings, for the .pc check.
fn prefixSpellings(a: mem.Allocator, prefix: []const u8) ![2][]const u8 {
    const fwd = try a.dupe(u8, prefix);
    mem.replaceScalar(u8, fwd, '\\', '/');
    const back = try a.dupe(u8, prefix);
    mem.replaceScalar(u8, back, '/', '\\');
    return .{ fwd, back };
}

pub fn main(init: std.process.Init) !u8 {
    const a = init.arena.allocator();
    const io = init.io;
    const env = init.environ_map;
    const args: []const []const u8 = try init.minimal.args.toSlice(a);
    if (args.len < 3 or args.len > 4) {
        std.debug.print("usage: pkgtest <zig triple> <pc module> [<smoke.c>]\n", .{});
        return 2;
    }
    const triple = args[1];
    const module = args[2];
    const smoke: ?[]const u8 = if (args.len == 4) args[3] else null;
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
    const pc = try std.process.run(a, io, .{ .argv = &.{ "pkgconf", "--cflags", "--libs", module }, .environ_map = &child_env });
    if (pc.stderr.len > 0) std.debug.print("{s}", .{pc.stderr});
    if (!pc.term.success()) {
        failed("pkgconf --cflags --libs {s}: {f}", .{ module, pc.term });
        return 1;
    }
    const flags_text = mem.trim(u8, pc.stdout, " \t\r\n");
    note("pkgconf --cflags --libs {s}: {s}", .{ module, flags_text });
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
    var own: usize = 0;
    for (flags.items) |w| {
        if (!mem.startsWith(u8, w, "-l")) continue;
        const name = try std.fmt.allocPrint(a, "lib{s}.a", .{w[2..]});
        for (dirs.items) |d| {
            if (isFile(io, try std.fs.path.join(a, &.{ d, name }))) {
                note("{s} -> {s}", .{ w, try std.fs.path.join(a, &.{ d, name }) });
                own += 1;
                break;
            }
        } else note("{s}: not in a -L directory (a system library)", .{w});
    }
    if (own == 0) failed("no -l of `pkgconf --libs {s}` names an archive of the sub-prefix", .{module});

    // 2. .pc files: relocatable
    const spell = try prefixSpellings(a, prefix);
    {
        var d = try Io.Dir.cwd().openDir(io, pcdir, .{ .iterate = true });
        defer d.close(io);
        var it = d.iterate();
        while (try it.next(io)) |e| {
            if (!mem.endsWith(u8, e.name, ".pc")) continue;
            const text = try d.readFileAlloc(io, e.name, a, .limited(1 << 20));
            for (spell) |p| if (mem.indexOf(u8, text, p) != null) failed("{s} names the absolute prefix {s}", .{ e.name, p });
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

    // 4. smoke executable
    if (smoke) |src| {
        const exe = try std.fmt.allocPrint(a, "{s}-smoke-{t}.exe", .{ module, arch });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ "zig", "cc", "-target", triple, "-O2", src });
        try argv.appendSlice(a, flags.items);
        try argv.appendSlice(a, &.{ "-o", exe });
        note("link: {s}", .{try mem.join(a, " ", argv.items)});
        var child = try std.process.spawn(io, .{ .argv = argv.items, .environ_map = &child_env });
        const term = try child.wait(io);
        if (!term.success()) {
            failed("zig cc: {f}", .{term});
            return 1;
        }
        const image = try Io.Dir.cwd().readFileAlloc(io, exe, a, .limited(1 << 30));
        const want: u16 = if (arch == .x86_64) 0x8664 else 0xaa64;
        const got = peMachine(image);
        if (got != want) failed("{s}: PE machine {?x}, want {x}", .{ exe, got, want }) else note("{s}: PE machine 0x{x}", .{ exe, want });

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

test "buildPathIn" {
    try std.testing.expectEqualStrings("/bld/", buildPathIn("x /bld/rattler y").?);
    try std.testing.expectEqualStrings("zig-*-cache", buildPathIn("a zig-global-cache/o b").?);
    try std.testing.expectEqualStrings("zig-*-cache", buildPathIn("zig--cache").?);
    try std.testing.expect(buildPathIn("zig-libs.obj zig-toolchain zig-") == null);
}

test "peMachine" {
    var pe: [0x90]u8 = @splat(0);
    pe[0] = 'M';
    pe[1] = 'Z';
    pe[0x3c] = 0x80;
    @memcpy(pe[0x80..0x84], "PE\x00\x00");
    pe[0x84] = 0x64;
    pe[0x85] = 0x86;
    try std.testing.expectEqual(@as(?u16, 0x8664), peMachine(&pe));
    pe[0x3c] = 0xfe;
    pe[0x3d] = 0xff;
    pe[0x3e] = 0xff;
    pe[0x3f] = 0xff;
    try std.testing.expectEqual(@as(?u16, null), peMachine(&pe));
}
