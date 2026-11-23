//! zig-toolchain: the cross toolchain of libs-zig-pixi, one multi-call
//! binary (decision D8). It dispatches on its own name, like busybox and
//! rzig:
//!
//!   <triple>-cc, <triple>-c++   zig cc|c++ -target <zig triple> -mcpu=baseline
//!                               -fno-sanitize=undefined -Wno-date-time <args>
//!                               (-march/-mcpu values in zig's spelling, flags.zig)
//!   <triple>-ar, <triple>-ranlib  zig ar|ranlib <args>
//!   <triple>-dlltool            zig dlltool, GNU's options translated (binutils.zig)
//!   <triple>-windres            zig rc, GNU windres' options translated (binutils.zig)
//!   <triple>-rc                 zig rc /:target <arch> <args> (rc.exe's options)
//!   <triple>-strip              a no-op, exit 0 (objects are built with -g0;
//!                               `cmake --install --strip` stays harmless)
//!   <triple>-{nm,objdump,objcopy,readelf,addr2line,ld,as}
//!                               an error, exit 1: zig has none of these for
//!                               COFF. They exist so that the CMake toolchain
//!                               files can name them and CMake never falls
//!                               back to the build machine's ELF binutils.
//!
//! <triple> is x86_64-w64-mingw32 or aarch64-w64-mingw32 (zig's
//! x86_64-windows-gnu and aarch64-windows-gnu, target.zig). For a real nm,
//! a build env adds llvm-tools (llvm-nm).
//!
//! Called as zig-toolchain:
//!   zig-toolchain close-pc [--libs "<words>"] <file.pc>...   (closepc.zig)
//!   zig-toolchain configure <configure script> [args...]     an autotools cross
//!                                                             configure for the
//!                                                             activation's target,
//!                                                             host tools fenced off
//!                                                             (configure.zig)
//!   zig-toolchain check-alignment [--expect <subdir>,...] [--published <channel>] <dir>...
//!                                                             one build number per package
//!                                                             across subdirs, compared with
//!                                                             a published channel (alignment.zig)
//!   zig-toolchain <triple>-<tool> <args>...                   the tool, by name
//!   zig-toolchain pe-machine <file>...                        a PE/COFF file's machine
//!   zig-toolchain version | --version
//!   zig-toolchain tools                                       the <tool> names, one per line
//!                                                             (the recipe links <triple>-<tool>)
//!
//! zig is $ZIG_BIN when set and not empty (both zigs, decision D11: the
//! upstream-zig leg points it at PyPI ziglang's zig), else `zig` on PATH.
//! ZIG_TOOLCHAIN_TRACE=1 prints `zig-toolchain: using <zig>` and the
//! command to stderr before running it. On posix the wrapper replaces
//! itself with zig (execve); elsewhere it runs zig and passes on its exit
//! code.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const target = @import("target.zig");
const flags = @import("flags.zig");
const binutils = @import("binutils.zig");
const closepc = @import("closepc.zig");
const alignment = @import("alignment.zig");
const configure = @import("configure.zig");

pub const version = "0.2.0";

const Tool = enum {
    cc,
    cxx,
    ar,
    ranlib,
    dlltool,
    windres,
    rc,
    strip,
    unsupported,

    fn fromName(name: []const u8) ?Tool {
        const map = std.StaticStringMap(Tool).initComptime(.{
            .{ "cc", .cc },               .{ "gcc", .cc },              .{ "c++", .cxx },
            .{ "g++", .cxx },             .{ "ar", .ar },               .{ "ranlib", .ranlib },
            .{ "dlltool", .dlltool },     .{ "windres", .windres },     .{ "rc", .rc },
            .{ "strip", .strip },         .{ "nm", .unsupported },      .{ "objdump", .unsupported },
            .{ "objcopy", .unsupported }, .{ "readelf", .unsupported }, .{ "addr2line", .unsupported },
            .{ "ld", .unsupported },      .{ "as", .unsupported },
        });
        return map.get(name);
    }
};

/// The names this binary is installed under (recipes/zig-toolchain).
pub const tool_names = [_][]const u8{ "cc", "c++", "ar", "ranlib", "dlltool", "windres", "rc", "strip", "nm", "objdump", "objcopy", "readelf", "addr2line", "ld", "as" };

const Call = struct { target: target.Target, tool: Tool, name: []const u8 };

/// `<triple>-<tool>`, the name without directory or .exe.
fn parseName(name: []const u8) ?Call {
    const dash = mem.lastIndexOfScalar(u8, name, '-') orelse return null;
    const t = target.fromGnu(name[0..dash]) orelse return null;
    const tool = Tool.fromName(name[dash + 1 ..]) orelse return null;
    return .{ .target = t, .tool = tool, .name = name };
}

fn baseName(arg: []const u8) []const u8 {
    const base = std.fs.path.basename(arg);
    if (base.len > 4 and std.ascii.eqlIgnoreCase(base[base.len - 4 ..], ".exe")) return base[0 .. base.len - 4];
    return base;
}

const usage_text =
    \\usage: <triple>-{cc,c++,ar,ranlib,dlltool,windres,rc,strip} [args...]
    \\       zig-toolchain <triple>-<tool> [args...]
    \\       zig-toolchain close-pc [--libs "<words>"] <file.pc>...
    \\       zig-toolchain configure <configure script> [args...]
    \\       zig-toolchain check-alignment [--expect <subdir>,...] [--published <channel>] <dir>...
    \\       zig-toolchain pe-machine <file>...
    \\       zig-toolchain version
    \\       zig-toolchain tools
    \\triples: x86_64-w64-mingw32 aarch64-w64-mingw32
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const a = init.arena.allocator();
    const io = init.io;
    const args: []const []const u8 = try init.minimal.args.toSlice(a);
    if (args.len == 0) {
        std.debug.print("{s}", .{usage_text});
        return 2;
    }
    if (parseName(baseName(args[0]))) |c| return runTool(init, c, args[1..]);
    if (args.len < 2) {
        std.debug.print("{s}", .{usage_text});
        return 2;
    }
    const sub = args[1];
    if (mem.eql(u8, sub, "close-pc")) return closepc.run(io, a, args[2..]);
    if (mem.eql(u8, sub, "check-alignment")) return alignment.run(io, a, args[2..]);
    if (mem.eql(u8, sub, "configure")) return configure.run(io, a, init.environ_map, zigPath(init.environ_map), args[2..]);
    if (mem.eql(u8, sub, "pe-machine")) return peMachine(io, a, args[2..]);
    if (mem.eql(u8, sub, "tools")) {
        for (tool_names) |n| {
            const line = std.fmt.allocPrint(a, "{s}\n", .{n}) catch return 1;
            Io.File.stdout().writeStreamingAll(io, line) catch return 1;
        }
        return 0;
    }
    if (mem.eql(u8, sub, "version") or mem.eql(u8, sub, "--version")) {
        std.debug.print("zig-toolchain {s}\n", .{version});
        return 0;
    }
    if (parseName(sub)) |c| return runTool(init, c, args[2..]);
    std.debug.print("{s}", .{usage_text});
    return 2;
}

/// zig: $ZIG_BIN when set and not empty, else "zig" (found on PATH).
fn zigPath(env: *const std.process.Environ.Map) []const u8 {
    if (env.get("ZIG_BIN")) |z| if (z.len > 0) return z;
    return "zig";
}

/// For the trace line only: where PATH finds `name`.
fn which(io: Io, a: mem.Allocator, env: *const std.process.Environ.Map, name: []const u8) []const u8 {
    if (mem.indexOfScalar(u8, name, '/') != null) return name;
    const path = env.get("PATH") orelse return name;
    var it = mem.tokenizeScalar(u8, path, if (builtin.os.tag == .windows) ';' else ':');
    while (it.next()) |dir| {
        const p = std.fs.path.join(a, &.{ dir, name }) catch return name;
        Io.Dir.cwd().access(io, p, .{ .execute = true }) catch continue;
        return p;
    }
    return name;
}

fn runTool(init: std.process.Init, c: Call, rest: []const []const u8) !u8 {
    switch (c.tool) {
        .strip => return 0,
        .unsupported => {
            std.debug.print("zig-toolchain: {s} is not available (zig has no such tool for COFF; add llvm-tools to the build env)\n", .{c.name});
            return 1;
        },
        else => {},
    }
    const a = init.arena.allocator();
    const io = init.io;
    const env = init.environ_map;
    const zig = zigPath(env);
    const tail: []const []const u8 = switch (c.tool) {
        .cc => try flags.compilerArgs(a, "cc", c.target, rest),
        .cxx => try flags.compilerArgs(a, "c++", c.target, rest),
        .ar => try mem.concat(a, []const u8, &.{ &.{"ar"}, rest }),
        .ranlib => try mem.concat(a, []const u8, &.{ &.{"ranlib"}, rest }),
        .dlltool => binutils.dlltoolArgv(a, c.target.arch, rest) catch |err| return if (err == error.Usage) 2 else err,
        .windres => binutils.windresArgv(a, c.target.arch, rest) catch |err| return if (err == error.Usage) 2 else err,
        .rc => try mem.concat(a, []const u8, &.{ &.{ "rc", "/:target", c.target.arch.rc() }, rest }),
        .strip, .unsupported => unreachable,
    };
    const argv = try mem.concat(a, []const u8, &.{ &.{zig}, tail });

    if (env.get("ZIG_TOOLCHAIN_TRACE")) |v| if (v.len > 0 and !mem.eql(u8, v, "0")) {
        var line: std.ArrayList(u8) = .empty;
        for (argv, 0..) |x, i| {
            if (i > 0) try line.append(a, ' ');
            try line.appendSlice(a, x);
        }
        std.debug.print("zig-toolchain: using {s}\nzig-toolchain: {s}\n", .{ which(io, a, env, zig), line.items });
    };

    if (builtin.os.tag == .windows) {
        var child = std.process.spawn(io, .{ .argv = argv }) catch |err| return cannotRun(zig, err);
        const term = child.wait(io) catch return 1;
        return switch (term) {
            .exited => |code| code,
            else => 1,
        };
    }
    const err = std.process.replace(io, .{ .argv = argv });
    return cannotRun(zig, err);
}

/// `zig-toolchain pe-machine <file>...`: each PE image's or COFF object's
/// machine (x86_64, aarch64, or the hex value), one line per file:
/// `<file>: <machine>`. Exit 1 when a file is neither.
fn peMachine(io: Io, a: mem.Allocator, files: []const []const u8) u8 {
    if (files.len == 0) {
        std.debug.print("usage: zig-toolchain pe-machine <file>...\n", .{});
        return 2;
    }
    var status: u8 = 0;
    for (files) |f| {
        const d = Io.Dir.cwd().readFileAlloc(io, f, a, .limited(1 << 30)) catch |err| {
            std.debug.print("{s}: cannot read: {t}\n", .{ f, err });
            status = 1;
            continue;
        };
        const m = machineOf(d) orelse {
            std.debug.print("{s}: not a PE image or COFF object\n", .{f});
            status = 1;
            continue;
        };
        const name = switch (m) {
            0x8664 => "x86_64",
            0xaa64 => "aarch64",
            else => std.fmt.allocPrint(a, "0x{x:0>4}", .{m}) catch "?",
        };
        const line = std.fmt.allocPrint(a, "{s}: {s}\n", .{ f, name }) catch return 1;
        Io.File.stdout().writeStreamingAll(io, line) catch return 1;
    }
    return status;
}

/// A PE image's machine (MZ, e_lfanew, "PE\0\0", machine), else a COFF
/// object's first u16 when it is a known machine.
fn machineOf(d: []const u8) ?u16 {
    if (d.len >= 0x40 and d[0] == 'M' and d[1] == 'Z') {
        const off: usize = mem.readInt(u32, d[0x3c..][0..4], .little);
        if (off > d.len or d.len - off < 6 or !mem.eql(u8, d[off..][0..4], "PE\x00\x00")) return null;
        return mem.readInt(u16, d[off + 4 ..][0..2], .little);
    }
    if (d.len >= 20) {
        const m = mem.readInt(u16, d[0..2], .little);
        if (m == 0x8664 or m == 0xaa64) return m;
    }
    return null;
}

fn cannotRun(zig: []const u8, err: anyerror) u8 {
    std.debug.print("zig-toolchain: cannot run {s}: {t} (set ZIG_BIN or put zig on PATH)\n", .{ zig, err });
    return if (err == error.FileNotFound) 127 else 126;
}

test {
    _ = target;
    _ = flags;
    _ = binutils;
    _ = closepc;
    _ = alignment;
    _ = configure;
}

test "names" {
    const c = parseName("aarch64-w64-mingw32-c++").?;
    try std.testing.expectEqual(Tool.cxx, c.tool);
    try std.testing.expectEqualStrings("aarch64-windows-gnu", c.target.zig);
    try std.testing.expectEqual(Tool.cc, parseName(baseName("/x/bin/x86_64-w64-mingw32-cc")).?.tool);
    try std.testing.expect(parseName("x86_64-linux-gnu-cc") == null);
    try std.testing.expect(parseName("zig-toolchain") == null);
    try std.testing.expectEqual(Tool.strip, parseName("x86_64-w64-mingw32-strip").?.tool);
    try std.testing.expectEqual(Tool.unsupported, parseName("aarch64-w64-mingw32-nm").?.tool);
    for (tool_names) |n| {
        const name = try std.fmt.allocPrint(std.testing.allocator, "x86_64-w64-mingw32-{s}", .{n});
        defer std.testing.allocator.free(name);
        try std.testing.expect(parseName(name) != null);
    }
}

test "machineOf" {
    var pe: [0x90]u8 = @splat(0);
    pe[0] = 'M';
    pe[1] = 'Z';
    pe[0x3c] = 0x80;
    @memcpy(pe[0x80..0x84], "PE\x00\x00");
    pe[0x84] = 0x64;
    pe[0x85] = 0xaa;
    try std.testing.expectEqual(@as(?u16, 0xaa64), machineOf(&pe));
    try std.testing.expectEqual(@as(?u16, null), machineOf("not a PE file at all, no"));
    // e_lfanew near 0xFFFFFFFF: "not a PE image", not an overflow panic
    pe[0x3c] = 0xfe;
    pe[0x3d] = 0xff;
    pe[0x3e] = 0xff;
    pe[0x3f] = 0xff;
    try std.testing.expectEqual(@as(?u16, null), machineOf(&pe));
}
