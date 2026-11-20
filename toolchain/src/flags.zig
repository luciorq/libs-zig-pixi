//! zig cc / zig c++ arguments for a wrapper: the target, the defaults every
//! compile gets, and the caller's arguments with -march/-mcpu values that
//! clang takes but zig does not rewritten into zig's spelling.
//!
//! armMcpu, armExts, arm_ext_names and clangCpu are copied from r-zig-pixi
//! zigbuild/tools/rzig/compiler.zig (origin/main f951022), with rzig's Ctx
//! replaced by an allocator and the target arch.
const std = @import("std");
const mem = std.mem;
const target = @import("target.zig");

/// Added before the caller's arguments (the caller's own flags come later
/// and win where clang lets the last one win):
///   -mcpu=baseline          never the build machine's CPU (zig's default
///                           for a native target; rzig's fix-rzig-baseline-cpu)
///   -fno-sanitize=undefined zig cc enables UBSan traps in Debug-like builds
///   -Wno-date-time          __DATE__/__TIME__ users (reproducibility
///                           warning, an error under -Werror)
/// -g0, -ffunction-sections and -fdata-sections come from the activation
/// script's CFLAGS/CXXFLAGS, so a build system can still override them.
pub const defaults = [_][]const u8{ "-mcpu=baseline", "-fno-sanitize=undefined", "-Wno-date-time" };

/// After the defaults, unless an input is a plain `.s` file (clang warns
/// "argument unused" there, an error under -Werror): a constant CodeView
/// S_OBJNAME. Without it every COFF object's .debug$S names its absolute
/// build path (the build dir, or zig's cache tmp path), even with -g0 and
/// -ffile-prefix-map; published archives would carry the build machine's
/// paths and differ between build dirs.
pub const objname = [_][]const u8{ "-Xclang", "-object-file-name=zig-libs.obj" };

/// -march, -mcpu and -mtune `=native` are dropped: in a cross compile zig
/// would still target the build machine's CPU (AVX2 in a Windows library),
/// which the -mcpu=baseline default exists to prevent.
fn isNative(x: []const u8) bool {
    const names = [_][]const u8{ "-march=native", "-mcpu=native", "-mtune=native" };
    for (names) |n| if (mem.eql(u8, x, n)) return true;
    return false;
}

/// A plain assembler input (`.s`, not the preprocessed `.S`).
fn hasPlainAsm(caller: []const []const u8) bool {
    for (caller) |x| if (x.len > 2 and mem.endsWith(u8, x, ".s")) return true;
    return false;
}

/// The value of `x` after `prefix`, or null.
fn flagValue(x: []const u8, prefix: []const u8) ?[]const u8 {
    if (x.len > prefix.len and mem.startsWith(u8, x, prefix)) return x[prefix.len..];
    return null;
}

/// Flags whose next argument is passed through to another tool and must
/// not be rewritten.
fn takesRawValue(x: []const u8) bool {
    const raw = [_][]const u8{ "-Xclang", "-Xlinker", "-Xpreprocessor", "-Xassembler", "-Xarch_host", "-Xarch_device" };
    for (raw) |r| if (mem.eql(u8, x, r)) return true;
    return false;
}

/// `zig cc|c++ -target <t> <defaults> <caller's, rewritten>` after zig's path.
pub fn compilerArgs(a: mem.Allocator, lang: []const u8, t: target.Target, caller: []const []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    try out.appendSlice(a, &.{ lang, "-target", t.zig });
    try out.appendSlice(a, &defaults);
    if (!hasPlainAsm(caller)) try out.appendSlice(a, &objname);
    var i: usize = 0;
    while (i < caller.len) : (i += 1) {
        const x = caller[i];
        if (takesRawValue(x) and i + 1 < caller.len) {
            try out.appendSlice(a, &.{ x, caller[i + 1] });
            i += 1;
            continue;
        }
        if (isNative(x)) continue;
        if (flagValue(x, "-march=")) |v| {
            if (try armMcpu(a, v)) |m| {
                try out.append(a, m);
                continue;
            }
            try out.append(a, (try clangCpu(a, t.arch, "-march=", v)) orelse x);
        } else if (flagValue(x, "-mcpu=")) |v| {
            try out.append(a, (try clangCpu(a, t.arch, "-mcpu=", v)) orelse x);
        } else try out.append(a, x);
    }
    return out.items;
}

/// `<flag><cpu>[+ext...]` with clang's CPU name in zig's spelling (the
/// extensions as armMcpu names them), or null when nothing changes.
fn clangCpu(a: mem.Allocator, arch_: target.Arch, flag: []const u8, v: []const u8) !?[]const u8 {
    var it = mem.splitScalar(u8, v, '+');
    const name = it.first();
    if (mem.indexOfScalar(u8, name, '-') == null) return null;
    const arch = arch_.std_arch();
    if (arch.parseCpuModel(name) != null) return null;
    const zname = try a.dupe(u8, name);
    mem.replaceScalar(u8, zname, '-', '_');
    if (arch.parseCpuModel(zname) == null) return null;
    var s: std.ArrayList(u8) = .empty;
    try s.appendSlice(a, flag);
    try s.appendSlice(a, zname);
    try armExts(a, &s, &it);
    return s.items;
}

const arm_ext_names = std.StaticStringMap([]const u8).initComptime(.{
    .{ "simd", "neon" },    .{ "fp", "fp_armv8" },   .{ "fp16", "fullfp16" },     .{ "rdma", "rdm" },
    .{ "rng", "rand" },     .{ "memtag", "mte" },    .{ "profile", "spe" },       .{ "fcma", "complxnum" },
    .{ "jscvt", "jsconv" }, .{ "pmuv3", "perfmon" }, .{ "predres2", "specres2" },
});

/// `armv<N>[.<M>]-a[+ext...]` as zig's -mcpu, or null for any other value:
/// `-march=armv8-a+crc+crypto` is `-mcpu=generic+v8a+crc+crypto`.
fn armMcpu(a: mem.Allocator, v: []const u8) !?[]const u8 {
    var it = mem.splitScalar(u8, v, '+');
    const arch = it.first();
    if (!mem.startsWith(u8, arch, "armv") or !mem.endsWith(u8, arch, "-a")) return null;
    const ver = arch["armv".len .. arch.len - "-a".len];
    if (ver.len == 0) return null;
    for (ver) |c| if (!std.ascii.isDigit(c) and c != '.') return null;
    var s: std.ArrayList(u8) = .empty;
    try s.appendSlice(a, "-mcpu=generic+v");
    for (ver) |c| try s.append(a, if (c == '.') '_' else c);
    try s.append(a, 'a');
    try armExts(a, &s, &it);
    return s.items;
}

/// clang's `+<ext>` list, the rest of `it`, in zig's words onto `s`.
fn armExts(a: mem.Allocator, s: *std.ArrayList(u8), it: *mem.SplitIterator(u8, .scalar)) !void {
    while (it.next()) |e| {
        if (e.len == 0) continue;
        const off = e.len > 2 and mem.startsWith(u8, e, "no");
        const name = if (off) e[2..] else e;
        try s.append(a, if (off) '-' else '+');
        for (arm_ext_names.get(name) orelse name) |c| try s.append(a, if (c == '-') '_' else c);
    }
}

const testing = std.testing;

fn expectArgs(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "cc: target and defaults first, the caller's after" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = target.fromGnu("x86_64-w64-mingw32").?;
    try expectArgs(&.{ "cc", "-target", "x86_64-windows-gnu", "-mcpu=baseline", "-fno-sanitize=undefined", "-Wno-date-time", "-Xclang", "-object-file-name=zig-libs.obj", "-O2", "-c", "a.c" }, try compilerArgs(arena.allocator(), "cc", t, &.{ "-O2", "-c", "a.c" }));
}

test "aarch64: -march=armv8-a+<any features> is -mcpu=generic+v8a+<features>" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = target.fromGnu("aarch64-w64-mingw32").?;
    const got = try compilerArgs(arena.allocator(), "c++", t, &.{ "-march=armv8-a+crypto", "-march=armv8-a+crc", "-march=armv8.2-a+fp16+nosve", "-Xclang", "-march=armv8-a" });
    try testing.expectEqualStrings("-mcpu=generic+v8a+crypto", got[8]);
    try testing.expectEqualStrings("-mcpu=generic+v8a+crc", got[9]);
    try testing.expectEqualStrings("-mcpu=generic+v8_2a+fullfp16-sve", got[10]);
    // a value passed through to clang itself is not touched
    try testing.expectEqualStrings("-march=armv8-a", got[12]);
}

test "x86_64: clang's CPU names in zig's spelling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = target.fromGnu("x86_64-w64-mingw32").?;
    const got = try compilerArgs(arena.allocator(), "cc", t, &.{ "-march=x86-64-v2", "-march=haswell" });
    try testing.expectEqualStrings("-march=x86_64_v2", got[8]);
    try testing.expectEqualStrings("-march=haswell", got[9]);
}

test "-march/-mcpu/-mtune=native are dropped; .s inputs get no -object-file-name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = target.fromGnu("x86_64-w64-mingw32").?;
    try expectArgs(&.{ "cc", "-target", "x86_64-windows-gnu", "-mcpu=baseline", "-fno-sanitize=undefined", "-Wno-date-time", "-c", "a.s" }, try compilerArgs(arena.allocator(), "cc", t, &.{ "-march=native", "-mcpu=native", "-mtune=native", "-c", "a.s" }));
}
