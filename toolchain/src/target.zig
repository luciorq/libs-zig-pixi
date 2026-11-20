//! The targets zig-toolchain compiles for, named by their GNU triple (the
//! prefix of each wrapper's name, `x86_64-w64-mingw32-cc`) and by zig's
//! -target. The zig spelling `<arch>-windows-gnu` is the one rzig uses for
//! Windows (r-zig-pixi zigbuild/tools/rzig/target.zig, `zig(.windows, a)`),
//! and it names the private sub-prefix: <envdir>/zig-libs/<zig triple>.
const std = @import("std");
const mem = std.mem;

pub const Arch = enum {
    x86_64,
    aarch64,

    /// llvm-dlltool's -m (rzig binutils.zig, Machine.dlltool).
    pub fn dlltool(a: Arch) []const u8 {
        return switch (a) {
            .x86_64 => "i386:x86-64",
            .aarch64 => "arm64",
        };
    }

    /// zig rc's /:target (rzig binutils.zig, Machine.rc).
    pub fn rc(a: Arch) []const u8 {
        return switch (a) {
            .x86_64 => "x64",
            .aarch64 => "arm64",
        };
    }

    pub fn std_arch(a: Arch) std.Target.Cpu.Arch {
        return switch (a) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
        };
    }
};

pub const Target = struct {
    arch: Arch,
    /// GNU triple, the wrappers' prefix.
    gnu: []const u8,
    /// zig's -target, and the sub-prefix directory name.
    zig: []const u8,
};

pub const all = [_]Target{
    .{ .arch = .x86_64, .gnu = "x86_64-w64-mingw32", .zig = "x86_64-windows-gnu" },
    .{ .arch = .aarch64, .gnu = "aarch64-w64-mingw32", .zig = "aarch64-windows-gnu" },
};

pub fn fromGnu(triple: []const u8) ?Target {
    for (all) |t| if (mem.eql(u8, t.gnu, triple)) return t;
    return null;
}

/// conda's subdir for a target (rattler-build's target_platform).
pub fn fromSubdir(subdir: []const u8) ?Target {
    if (mem.eql(u8, subdir, "win-64")) return all[0];
    if (mem.eql(u8, subdir, "win-arm64")) return all[1];
    return null;
}

test "triples" {
    try std.testing.expectEqualStrings("x86_64-windows-gnu", fromGnu("x86_64-w64-mingw32").?.zig);
    try std.testing.expectEqualStrings("aarch64-windows-gnu", fromGnu("aarch64-w64-mingw32").?.zig);
    try std.testing.expect(fromGnu("i686-w64-mingw32") == null);
    try std.testing.expectEqual(Arch.aarch64, fromSubdir("win-arm64").?.arch);
}
