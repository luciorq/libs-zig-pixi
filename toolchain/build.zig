//! zig-toolchain: one binary (src/main.zig) plus its data files.
//!
//!   zig build -Doptimize=safe [--prefix <p>]
//!     <p>/bin/zig-toolchain
//!     <p>/share/zig-toolchain/<triple>.cmake, <triple>.ini   (CMake toolchain, meson cross files)
//!     <p>/etc/conda/activate.d/zig-toolchain_activate.sh     (rattler-build build env)
//!   zig build test
//!
//! The triple-named links (<p>/bin/<triple>-<tool> -> zig-toolchain) are made
//! by recipes/zig-toolchain/build.sh.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // no debug info in a release binary (4.3 MB -> about 1 MB)
        .strip = optimize != .debug,
    });
    const exe = b.addExecutable(.{ .name = "zig-toolchain", .root_module = mod });
    b.installArtifact(exe);

    for ([_][]const u8{ "x86_64-w64-mingw32", "aarch64-w64-mingw32" }) |t| {
        const cmake = b.fmt("{s}.cmake", .{t});
        const ini = b.fmt("{s}.ini", .{t});
        b.getInstallStep().dependOn(&b.addInstallFile(b.path(b.fmt("share/{s}", .{cmake})), b.fmt("share/zig-toolchain/{s}", .{cmake})).step);
        b.getInstallStep().dependOn(&b.addInstallFile(b.path(b.fmt("share/{s}", .{ini})), b.fmt("share/zig-toolchain/{s}", .{ini})).step);
    }
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("share/activate.sh"), "etc/conda/activate.d/zig-toolchain_activate.sh").step);

    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the unit tests").dependOn(&run_tests.step);
}
