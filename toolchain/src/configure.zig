//! `zig-toolchain configure <configure script> [args...]`: runs an
//! autotools configure script as a cross build for the activation's target
//! (slice2 PLAN.md D104). It adds the cross arguments in front of the
//! caller's:
//!
//!   --build=<this machine> --host=<GNU triple of ZIG_TOOLCHAIN_TARGET>
//!   --prefix=/zig-libs/<zig triple> --libdir=/zig-libs/<zig triple>/lib
//!   --disable-shared --enable-static
//!
//! The prefix is neutral, so no build path is compiled into an archive
//! (CONTRACT.md 2); the recipe installs with
//! `make install DESTDIR="$PREFIX/Library"`, which puts the files at
//! $ZIG_LIBS_PREFIX. close-pc then makes the .pc files relocatable.
//!
//! It also fences the configure script off from the build machine's tools.
//! Each variable is set only when the caller left it unset or empty:
//!
//!   CC_FOR_BUILD   "<zig> cc": programs that configure or make build and
//!                  run on the build machine (gmp's gen-*). <zig> is
//!                  $ZIG_BIN when set (both zigs, D11), else zig.
//!   NM             llvm-nm from the build env (llvm-tools), else
//!                  <triple>-nm, which fails with a message
//!   LD AS          <triple>-ld, <triple>-as: they fail with a message, so
//!                  libtool never runs the build machine's ELF ld or as
//!   MANIFEST_TOOL  false (libtool's probe then finds none; /usr/bin/mt is
//!                  a tape tool)
//!   PKG_CONFIG     pkg-config from the build env, else false (no
//!                  pkg-config; never the build machine's, D97)
//!   CONFIG_SITE    /dev/null (no site defaults from the build machine)
//!   FC F77         no: none of these libraries builds Fortran, but a
//!                  configure that probes for it (udunits' AC_PROG_FC)
//!                  finds the build machine's gfortran; libtool then sets
//!                  up a Fortran tag on its MSVC branch and names the
//!                  archive lib<n>.lib. libtool skips the tag only for an
//!                  empty FC/F77 or "no" (not "false"; slice2 PLAN.md S2-F24)
//!   lt_cv_prog_gnu_ld  yes: the toolchain links through zig (lld, "compatible
//!                  with GNU linkers"). libtool asks whether $LD is GNU ld;
//!                  with the failing LD stub it answers no and takes its MSVC
//!                  branch (`lib -OUT:` as the archiver, slice2 PLAN.md
//!                  S2-F8). zig's own `ld.lld` is ELF-only (no i386pep or
//!                  arm64pe), so LD cannot be a real PE linker. The one
//!                  cache answer the helper gives, the same for every library.
//!
//! "The build env" is $BUILD_PREFIX/bin when BUILD_PREFIX is set
//! (rattler-build), else PATH. Apart from lt_cv_prog_gnu_ld it passes no
//! cache answers (ac_cv_*): a library that needs them is a D104 fallback
//! trigger, so the caller has to add them in its own build.sh, where they
//! are seen.
//!
//! The command and the variables it set are printed to stderr first. On
//! posix it replaces itself with the script; elsewhere it runs it and
//! passes on the exit code.
const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Io = std.Io;
const target = @import("target.zig");

/// The GNU triple of the machine zig-toolchain runs on (autoconf's
/// --build). zig-toolchain is built for linux-64 (later osx-*).
pub fn buildTriple(arch: std.Target.Cpu.Arch, os: std.Target.Os.Tag) ?[]const u8 {
    return switch (os) {
        .linux => switch (arch) {
            .x86_64 => "x86_64-pc-linux-gnu",
            .aarch64 => "aarch64-unknown-linux-gnu",
            else => null,
        },
        .macos => switch (arch) {
            .x86_64 => "x86_64-apple-darwin",
            .aarch64 => "aarch64-apple-darwin",
            else => null,
        },
        else => null,
    };
}

/// The target named by the activation's ZIG_TOOLCHAIN_TARGET (zig triple).
pub fn fromZig(zig: []const u8) ?target.Target {
    for (target.all) |t| if (mem.eql(u8, t.zig, zig)) return t;
    return null;
}

/// The script's argv: the script, the cross arguments, then the caller's.
pub fn configureArgv(a: mem.Allocator, build: []const u8, t: target.Target, script: []const u8, rest: []const []const u8) ![]const []const u8 {
    const prefix = try std.fmt.allocPrint(a, "/zig-libs/{s}", .{t.zig});
    const head = [_][]const u8{
        script,
        try std.fmt.allocPrint(a, "--build={s}", .{build}),
        try std.fmt.allocPrint(a, "--host={s}", .{t.gnu}),
        try std.fmt.allocPrint(a, "--prefix={s}", .{prefix}),
        try std.fmt.allocPrint(a, "--libdir={s}/lib", .{prefix}),
        "--disable-shared",
        "--enable-static",
    };
    return mem.concat(a, []const u8, &.{ &head, rest });
}

pub const Fence = struct { name: []const u8, value: []const u8 };

/// The fence variables (header) for target t. `found` maps a program name
/// to its path in the build env, or null. Only variables the environment
/// leaves unset or empty are returned.
pub fn fences(
    a: mem.Allocator,
    t: target.Target,
    zig: []const u8,
    env: *const std.process.Environ.Map,
    ctx: anytype,
    comptime found: fn (@TypeOf(ctx), []const u8) ?[]const u8,
) ![]const Fence {
    var list: std.ArrayList(Fence) = .empty;
    const nm = found(ctx, "llvm-nm") orelse try std.fmt.allocPrint(a, "{s}-nm", .{t.gnu});
    const pkg_config = found(ctx, "pkg-config") orelse "false";
    const all = [_]Fence{
        .{ .name = "CC_FOR_BUILD", .value = try std.fmt.allocPrint(a, "{s} cc", .{zig}) },
        .{ .name = "NM", .value = nm },
        .{ .name = "LD", .value = try std.fmt.allocPrint(a, "{s}-ld", .{t.gnu}) },
        .{ .name = "AS", .value = try std.fmt.allocPrint(a, "{s}-as", .{t.gnu}) },
        .{ .name = "MANIFEST_TOOL", .value = "false" },
        .{ .name = "PKG_CONFIG", .value = pkg_config },
        .{ .name = "CONFIG_SITE", .value = "/dev/null" },
        .{ .name = "FC", .value = "no" },
        .{ .name = "F77", .value = "no" },
        .{ .name = "lt_cv_prog_gnu_ld", .value = "yes" },
    };
    for (all) |f| {
        if (env.get(f.name)) |v| if (v.len > 0) continue;
        try list.append(a, f);
    }
    return list.toOwnedSlice(a);
}

const Finder = struct {
    io: Io,
    a: mem.Allocator,
    /// $BUILD_PREFIX/bin, or PATH's directories
    dirs: []const []const u8,

    fn find(self: Finder, name: []const u8) ?[]const u8 {
        for (self.dirs) |dir| {
            const p = std.fs.path.join(self.a, &.{ dir, name }) catch return null;
            Io.Dir.cwd().access(self.io, p, .{ .execute = true }) catch continue;
            return p;
        }
        return null;
    }
};

const usage = "usage: zig-toolchain configure <configure script> [args...]\n";

pub fn run(io: Io, a: mem.Allocator, env: *std.process.Environ.Map, zig: []const u8, args: []const []const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("{s}", .{usage});
        return 2;
    }
    const zt = env.get("ZIG_TOOLCHAIN_TARGET") orelse "";
    const t = fromZig(zt) orelse {
        std.debug.print("zig-toolchain configure: ZIG_TOOLCHAIN_TARGET is '{s}' (the zig-toolchain activation sets it for win-64 and win-arm64)\n", .{zt});
        return 2;
    };
    const build = buildTriple(builtin.cpu.arch, builtin.os.tag) orelse {
        std.debug.print("zig-toolchain configure: no --build triple for this machine\n", .{});
        return 2;
    };

    var dirs: std.ArrayList([]const u8) = .empty;
    if (env.get("BUILD_PREFIX")) |bp| if (bp.len > 0) try dirs.append(a, try std.fs.path.join(a, &.{ bp, "bin" }));
    if (dirs.items.len == 0) if (env.get("PATH")) |path| {
        var it = mem.tokenizeScalar(u8, path, ':');
        while (it.next()) |d| try dirs.append(a, d);
    };
    const finder: Finder = .{ .io = io, .a = a, .dirs = dirs.items };

    const set = try fences(a, t, zig, env, finder, Finder.find);
    for (set) |f| try env.put(f.name, f.value);
    const argv = try configureArgv(a, build, t, args[0], args[1..]);

    var line: std.ArrayList(u8) = .empty;
    try line.appendSlice(a, "zig-toolchain configure:");
    for (set) |f| try line.print(a, " {s}='{s}'", .{ f.name, f.value });
    for (argv) |x| try line.print(a, " {s}", .{x});
    std.debug.print("{s}\n", .{line.items});

    if (builtin.os.tag == .windows) {
        var child = std.process.spawn(io, .{ .argv = argv, .environ_map = env }) catch |err| return cannotRun(args[0], err);
        const term = child.wait(io) catch return 1;
        return switch (term) {
            .exited => |code| code,
            else => 1,
        };
    }
    const err = std.process.replace(io, .{ .argv = argv, .environ_map = env });
    return cannotRun(args[0], err);
}

fn cannotRun(script: []const u8, err: anyerror) u8 {
    std.debug.print("zig-toolchain configure: cannot run {s}: {t}\n", .{ script, err });
    return if (err == error.FileNotFound) 127 else 126;
}

test "argv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = fromZig("aarch64-windows-gnu").?;
    const argv = try configureArgv(a, "x86_64-pc-linux-gnu", t, "../configure", &.{"--enable-cxx"});
    const want = [_][]const u8{
        "../configure",                               "--build=x86_64-pc-linux-gnu",
        "--host=aarch64-w64-mingw32",                 "--prefix=/zig-libs/aarch64-windows-gnu",
        "--libdir=/zig-libs/aarch64-windows-gnu/lib", "--disable-shared",
        "--enable-static",                            "--enable-cxx",
    };
    try std.testing.expectEqual(want.len, argv.len);
    for (want, argv) |w, g| try std.testing.expectEqualStrings(w, g);
    try std.testing.expect(fromZig("x86_64-linux-gnu") == null);
    try std.testing.expectEqualStrings("x86_64-pc-linux-gnu", buildTriple(.x86_64, .linux).?);
}

test "fences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const t = fromZig("x86_64-windows-gnu").?;
    var env = std.process.Environ.Map.init(a);
    try env.put("PKG_CONFIG", "/bp/bin/pkgconf");
    try env.put("NM", "");
    const Ctx = struct {
        fn none(_: void, _: []const u8) ?[]const u8 {
            return null;
        }
        fn nm(_: void, name: []const u8) ?[]const u8 {
            return if (mem.eql(u8, name, "llvm-nm")) "/bp/bin/llvm-nm" else null;
        }
    };
    const f1 = try fences(a, t, "/z/zig", &env, {}, Ctx.none);
    // PKG_CONFIG is the caller's; an empty NM is replaced
    for (f1) |f| try std.testing.expect(!mem.eql(u8, f.name, "PKG_CONFIG"));
    try std.testing.expectEqualStrings("CC_FOR_BUILD", f1[0].name);
    try std.testing.expectEqualStrings("/z/zig cc", f1[0].value);
    try std.testing.expectEqualStrings("x86_64-w64-mingw32-nm", f1[1].value);
    try std.testing.expectEqualStrings("x86_64-w64-mingw32-as", f1[3].value);
    var fc = false;
    for (f1) |f| if (mem.eql(u8, f.name, "FC")) {
        try std.testing.expectEqualStrings("no", f.value);
        fc = true;
    };
    try std.testing.expect(fc);
    const f2 = try fences(a, t, "zig", &env, {}, Ctx.nm);
    try std.testing.expectEqualStrings("/bp/bin/llvm-nm", f2[1].value);
}
