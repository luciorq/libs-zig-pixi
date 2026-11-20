//! GNU dlltool and windres arguments as `zig dlltool` (llvm-dlltool) and
//! `zig rc` take them. Copied from r-zig-pixi
//! zigbuild/tools/rzig/binutils.zig (origin/main f951022: optValue, isOpt,
//! dlltoolArgv, windresArgv), with rzig's Ctx replaced by an allocator and
//! the machine taken from the wrapper's triple instead of rzig's own arch.
const std = @import("std");
const mem = std.mem;
const target = @import("target.zig");

pub const Error = error{ Usage, OutOfMemory };

fn usage(comptime fmt: []const u8, args: anytype) Error {
    std.debug.print("zig-toolchain: " ++ fmt ++ "\n", args);
    return error.Usage;
}

/// The value of `-x v`, `-xv`, `--long v` or `--long=v` at args[i.*].
fn optValue(args: []const []const u8, i: *usize, short: ?[]const u8, long: ?[]const u8) ?[]const u8 {
    const x = args[i.*];
    if (long) |l| {
        if (mem.eql(u8, x, l)) {
            if (i.* + 1 >= args.len) return null;
            i.* += 1;
            return args[i.*];
        }
        if (mem.startsWith(u8, x, l) and x.len > l.len and x[l.len] == '=') return x[l.len + 1 ..];
    }
    if (short) |s| {
        if (mem.eql(u8, x, s)) {
            if (i.* + 1 >= args.len) return null;
            i.* += 1;
            return args[i.*];
        }
        if (mem.startsWith(u8, x, s) and x.len > s.len and x[1] != '-') return x[s.len..];
    }
    return null;
}

fn isOpt(x: []const u8, short: ?[]const u8, long: ?[]const u8) bool {
    if (long) |l| if (mem.eql(u8, x, l) or (mem.startsWith(u8, x, l) and x.len > l.len and x[l.len] == '=')) return true;
    if (short) |s| if (mem.startsWith(u8, x, s) and (x.len == s.len or x[1] != '-')) return true;
    return false;
}

/// `zig dlltool` (llvm-dlltool) for GNU dlltool's arguments.
pub fn dlltoolArgv(a: mem.Allocator, arch: target.Arch, args: []const []const u8) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    try out.append(a, "dlltool");
    var machine: []const u8 = arch.dlltool();
    var have_lib = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (isOpt(x, "-d", "--input-def") or isOpt(x, null, "--def")) {
            const long = if (isOpt(x, null, "--def")) "--def" else "--input-def";
            try out.appendSlice(a, &.{ "-d", optValue(args, &i, "-d", long) orelse return usage("--input-def needs a file", .{}) });
        } else if (isOpt(x, "-l", "--output-lib")) {
            try out.appendSlice(a, &.{ "-l", optValue(args, &i, "-l", "--output-lib") orelse return usage("--output-lib needs a file", .{}) });
            have_lib = true;
        } else if (isOpt(x, "-D", "--dllname")) {
            try out.appendSlice(a, &.{ "-D", optValue(args, &i, "-D", "--dllname") orelse return usage("--dllname needs a name", .{}) });
        } else if (isOpt(x, "-m", "--machine")) {
            const m = optValue(args, &i, "-m", "--machine") orelse return usage("--machine needs a value", .{});
            machine = if (mem.eql(u8, m, "i386:x86-64") or mem.eql(u8, m, "x86_64") or mem.eql(u8, m, "x64")) "i386:x86-64" else if (mem.eql(u8, m, "arm64") or mem.eql(u8, m, "aarch64")) "arm64" else m;
        } else if (mem.eql(u8, x, "-k") or mem.eql(u8, x, "--kill-at")) {
            try out.append(a, "-k");
        } else if (isOpt(x, "-S", "--as") or isOpt(x, "-f", "--as-flags") or isOpt(x, "-t", "--temp-prefix")) {
            // the assembler and its flags: llvm-dlltool writes the library itself
            const takes_value = mem.eql(u8, x, "-S") or mem.eql(u8, x, "--as") or mem.eql(u8, x, "-f") or mem.eql(u8, x, "--as-flags") or mem.eql(u8, x, "-t") or mem.eql(u8, x, "--temp-prefix");
            if (takes_value) i += 1;
        } else if (mem.eql(u8, x, "--no-leading-underscore") or mem.eql(u8, x, "-U") or mem.eql(u8, x, "--add-underscore") or
            mem.eql(u8, x, "-A") or mem.eql(u8, x, "--add-stdcall-alias") or mem.eql(u8, x, "-v") or mem.eql(u8, x, "--verbose") or
            mem.eql(u8, x, "--no-delete") or mem.eql(u8, x, "-n"))
        {
            // leading underscores are i386's, which is not a target here
        } else {
            return usage("unsupported dlltool argument {s} (--input-def, --output-lib, --dllname, -k, -m; --as and its flags are ignored)", .{x});
        }
    }
    if (!have_lib) return usage("dlltool: no --output-lib (import libraries only)", .{});
    try out.appendSlice(a, &.{ "-m", machine });
    return out.items;
}

/// `zig rc` for GNU windres' arguments.
pub fn windresArgv(a: mem.Allocator, arch: target.Arch, args: []const []const u8) Error![]const []const u8 {
    var opts: std.ArrayList([]const u8) = .empty;
    var input: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var out_format: ?[]const u8 = null;
    var in_format: ?[]const u8 = null;
    var tgt: []const u8 = arch.rc();
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (x.len < 2 or x[0] != '-') {
            if (input == null) input = x else if (output == null) output = x else return usage("windres: one input and one output, not also {s}", .{x});
        } else if (isOpt(x, "-i", "--input")) {
            input = optValue(args, &i, "-i", "--input") orelse return usage("--input needs a file", .{});
        } else if (isOpt(x, "-o", "--output")) {
            output = optValue(args, &i, "-o", "--output") orelse return usage("--output needs a file", .{});
        } else if (isOpt(x, "-O", "--output-format")) {
            out_format = optValue(args, &i, "-O", "--output-format") orelse return usage("--output-format needs a value", .{});
        } else if (isOpt(x, "-J", "--input-format")) {
            in_format = optValue(args, &i, "-J", "--input-format") orelse return usage("--input-format needs a value", .{});
        } else if (isOpt(x, "-F", "--target")) {
            const t = optValue(args, &i, "-F", "--target") orelse return usage("--target needs a value", .{});
            if (mem.find(u8, t, "x86-64") != null or mem.find(u8, t, "x86_64") != null) tgt = "x64" else if (mem.find(u8, t, "aarch64") != null or mem.find(u8, t, "arm64") != null) tgt = "arm64";
        } else if (isOpt(x, "-I", "--include-dir")) {
            try opts.appendSlice(a, &.{ "/i", optValue(args, &i, "-I", "--include-dir") orelse return usage("--include-dir needs a directory", .{}) });
        } else if (isOpt(x, "-D", "--define")) {
            try opts.appendSlice(a, &.{ "/d", optValue(args, &i, "-D", "--define") orelse return usage("--define needs a symbol", .{}) });
        } else if (isOpt(x, "-U", "--undefine")) {
            try opts.appendSlice(a, &.{ "/u", optValue(args, &i, "-U", "--undefine") orelse return usage("--undefine needs a symbol", .{}) });
        } else if (isOpt(x, "-l", "--language")) {
            const l = optValue(args, &i, "-l", "--language") orelse return usage("--language needs a value", .{});
            try opts.appendSlice(a, &.{ "/l", if (mem.startsWith(u8, l, "0x")) l[2..] else l });
        } else if (isOpt(x, "-c", "--codepage")) {
            const cp = optValue(args, &i, "-c", "--codepage") orelse return usage("--codepage needs a value", .{});
            try opts.appendSlice(a, &.{ "/c", cp });
        } else if (mem.eql(u8, x, "--preprocessor") or mem.eql(u8, x, "--preprocessor-arg")) {
            // zig rc preprocesses itself, with RC_INVOKED defined
            i += 1;
        } else if (mem.startsWith(u8, x, "--preprocessor=") or mem.startsWith(u8, x, "--preprocessor-arg=") or
            mem.eql(u8, x, "--use-temp-file") or mem.eql(u8, x, "--no-use-temp-file") or mem.eql(u8, x, "-v") or mem.eql(u8, x, "--verbose"))
        {} else {
            return usage("unsupported windres argument {s} (-i, -o, -O, -J, -F, -I, -D, -U, -l, -c)", .{x});
        }
    }
    const in = input orelse return usage("windres: no input file (a .rc file, not stdin)", .{});
    const out = output orelse return usage("windres: no output file", .{});
    const fmt_name = out_format orelse if (std.ascii.endsWithIgnoreCase(out, ".res")) "res" else "coff";
    const zig_format = if (std.ascii.eqlIgnoreCase(fmt_name, "coff")) "coff" else if (std.ascii.eqlIgnoreCase(fmt_name, "res")) "res" else return usage("windres: output format {s}: coff or res only", .{fmt_name});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "rc", "/:output-format", zig_format, "/:target", tgt, "/:auto-includes", "gnu" });
    if (in_format) |f| {
        if (std.ascii.eqlIgnoreCase(f, "res")) try argv.appendSlice(a, &.{ "/:input-format", "res" }) else if (!std.ascii.eqlIgnoreCase(f, "rc")) return usage("windres: input format {s}: rc or res only", .{f});
    }
    try argv.appendSlice(a, opts.items);
    try argv.appendSlice(a, &.{ "/fo", out, "--", in });
    return argv.items;
}

const testing = std.testing;

fn expectArgs(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

test "dlltool: GNU's options as zig dlltool's, the machine the triple's" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectArgs(&.{ "dlltool", "-k", "-D", "R.dll", "-d", "R.def", "-l", "libR.dll.a", "-m", "arm64" }, try dlltoolArgv(a, .aarch64, &.{ "--as", "as.exe", "-k", "--dllname", "R.dll", "--input-def", "R.def", "--output-lib", "libR.dll.a" }));
    try expectArgs(&.{ "dlltool", "-d", "y.def", "-l", "liby.dll.a", "-m", "i386:x86-64" }, try dlltoolArgv(a, .x86_64, &.{ "--def", "y.def", "-l", "liby.dll.a" }));
    try testing.expectError(error.Usage, dlltoolArgv(a, .x86_64, &.{ "--input-def", "x.def" }));
}

test "windres: GNU's options as zig rc's" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectArgs(&.{ "rc", "/:output-format", "coff", "/:target", "arm64", "/:auto-includes", "gnu", "/d", "X=1", "/i", "inc", "/fo", "r.obj", "--", "r.rc" }, try windresArgv(a, .aarch64, &.{ "-O", "coff", "-DX=1", "-I", "inc", "r.rc", "r.obj" }));
    try expectArgs(&.{ "rc", "/:output-format", "res", "/:target", "x64", "/:auto-includes", "gnu", "/fo", "r.res", "--", "r.rc" }, try windresArgv(a, .x86_64, &.{ "--preprocessor=gcc", "-i", "r.rc", "-o", "r.res" }));
    try testing.expectError(error.Usage, windresArgv(a, .x86_64, &.{"r.rc"}));
}
