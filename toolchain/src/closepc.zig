//! `zig-toolchain close-pc [--libs "<words>"] <file.pc>...`: makes an
//! installed pkg-config file closed and relocatable, in place.
//!
//!   relocatable  `prefix=${pcfiledir}/../..` (the .pc sits in
//!                <sub-prefix>/lib/pkgconfig or share/pkgconfig); every
//!                other occurrence of the old prefix becomes ${prefix}, and
//!                exec_prefix is ${prefix}. No absolute path may remain:
//!                any is an error (exit 1), naming the line.
//!   closed       Libs.private is appended to Libs and Requires.private to
//!                Requires, and both private lines are dropped: r-zig's
//!                pkgconf prints Libs.private only with --static, which the
//!                R packages never pass. --libs appends more words (the
//!                Windows system libraries the archive needs) to Libs.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;

pub const Error = error{ BadPc, OutOfMemory };

fn fail(comptime fmt: []const u8, args: anytype) Error {
    std.debug.print("zig-toolchain close-pc: " ++ fmt ++ "\n", args);
    return error.BadPc;
}

/// `Key: value` (a field) or null.
fn field(line: []const u8, key: []const u8) ?[]const u8 {
    if (line.len > key.len and mem.startsWith(u8, line, key) and line[key.len] == ':')
        return mem.trim(u8, line[key.len + 1 ..], " \t");
    return null;
}

/// `name=value` (a variable) or null.
fn variable(line: []const u8, name: []const u8) ?[]const u8 {
    if (line.len > name.len and mem.startsWith(u8, line, name) and line[name.len] == '=')
        return mem.trim(u8, line[name.len + 1 ..], " \t");
    return null;
}

fn isAbsolute(word: []const u8) bool {
    var w = word;
    for ([_][]const u8{ "-L", "-I", "-isystem", "-idirafter", "-Wl,-rpath,", "-Wl,-rpath=" }) |p| {
        if (mem.startsWith(u8, w, p)) {
            w = w[p.len..];
            break;
        }
    }
    if (w.len > 0 and (w[0] == '/' or w[0] == '\\')) return true;
    if (w.len > 2 and std.ascii.isAlphabetic(w[0]) and w[1] == ':' and (w[2] == '/' or w[2] == '\\')) return true;
    return false;
}

fn join(a: mem.Allocator, parts: []const []const u8) ![]const u8 {
    var s: std.ArrayList(u8) = .empty;
    for (parts) |p| {
        const t = mem.trim(u8, p, " \t");
        if (t.len == 0) continue;
        if (s.items.len > 0) try s.append(a, ' ');
        try s.appendSlice(a, t);
    }
    return s.items;
}

/// The closed, relocatable text of a .pc file.
pub fn close(a: mem.Allocator, text: []const u8, extra_libs: []const u8) Error![]const u8 {
    var old_prefix: ?[]const u8 = null;
    var it = mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = mem.trimEnd(u8, raw, "\r");
        if (variable(line, "prefix")) |v| {
            old_prefix = v;
            break;
        }
    }
    const prefix = old_prefix orelse return fail("no prefix= line", .{});

    var libs: []const u8 = "";
    var libs_private: []const u8 = "";
    var requires: []const u8 = "";
    var requires_private: []const u8 = "";
    var lines: std.ArrayList([]const u8) = .empty;
    it = mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        var line: []const u8 = mem.trimEnd(u8, raw, "\r");
        if (variable(line, "prefix") != null) {
            try lines.append(a, "prefix=${pcfiledir}/../..");
            continue;
        }
        if (variable(line, "exec_prefix") != null) {
            try lines.append(a, "exec_prefix=${prefix}");
            continue;
        }
        if (prefix.len > 0 and prefix[0] != '$')
            line = try mem.replaceOwned(u8, a, line, prefix, "${prefix}");
        if (field(line, "Libs.private")) |v| {
            libs_private = v;
            continue;
        }
        if (field(line, "Requires.private")) |v| {
            requires_private = v;
            continue;
        }
        if (field(line, "Libs")) |v| {
            libs = v;
            try lines.append(a, "\x00libs");
            continue;
        }
        if (field(line, "Requires")) |v| {
            requires = v;
            try lines.append(a, "\x00requires");
            continue;
        }
        try lines.append(a, line);
    }
    // a missing Requires line gets one only when there is something to put there
    var have_requires = false;
    for (lines.items) |l| if (mem.eql(u8, l, "\x00requires")) {
        have_requires = true;
    };

    var out: std.ArrayList(u8) = .empty;
    for (lines.items, 0..) |l, n| {
        if (mem.eql(u8, l, "\x00libs")) {
            try out.print(a, "Libs: {s}\n", .{try join(a, &.{ libs, libs_private, extra_libs })});
        } else if (mem.eql(u8, l, "\x00requires")) {
            const r = try join(a, &.{ requires, requires_private });
            try out.print(a, "Requires:{s}{s}\n", .{ if (r.len > 0) " " else "", r });
        } else {
            // the text's trailing newline gives one empty last item
            if (n == lines.items.len - 1 and l.len == 0) break;
            try out.print(a, "{s}\n", .{l});
        }
    }
    if (!have_requires and requires_private.len > 0) try out.print(a, "Requires: {s}\n", .{requires_private});

    // nothing absolute may remain
    var check = mem.splitScalar(u8, out.items, '\n');
    var line_no: usize = 0;
    while (check.next()) |line| {
        line_no += 1;
        const value = if (mem.indexOfAny(u8, line, ":=")) |k| line[k + 1 ..] else line;
        var words = mem.tokenizeAny(u8, value, " \t");
        while (words.next()) |w| if (isAbsolute(w)) return fail("line {d} keeps an absolute path: {s}", .{ line_no, line });
    }
    return out.items;
}

pub fn run(io: Io, a: mem.Allocator, args: []const []const u8) u8 {
    var extra: []const u8 = "";
    var files: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (mem.eql(u8, x, "--libs")) {
            if (i + 1 >= args.len) {
                std.debug.print("zig-toolchain close-pc: --libs needs a value\n", .{});
                return 2;
            }
            i += 1;
            extra = args[i];
        } else if (mem.startsWith(u8, x, "--libs=")) {
            extra = x["--libs=".len..];
        } else files.append(a, x) catch return 1;
    }
    if (files.items.len == 0) {
        std.debug.print("usage: zig-toolchain close-pc [--libs \"-lws2_32 ...\"] <file.pc>...\n", .{});
        return 2;
    }
    const cwd = Io.Dir.cwd();
    for (files.items) |f| {
        const text = cwd.readFileAlloc(io, f, a, .limited(1 << 20)) catch |err| {
            std.debug.print("zig-toolchain close-pc: cannot read {s}: {t}\n", .{ f, err });
            return 1;
        };
        const closed = close(a, text, extra) catch {
            std.debug.print("zig-toolchain close-pc: in {s}\n", .{f});
            return 1;
        };
        cwd.writeFile(io, .{ .sub_path = f, .data = closed }) catch |err| {
            std.debug.print("zig-toolchain close-pc: cannot write {s}: {t}\n", .{ f, err });
            return 1;
        };
    }
    return 0;
}

const testing = std.testing;

test "zlib 1.3.1's CMake zlib.pc, closed and relocatable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const in =
        \\prefix=/b/h_env/Library/zig-libs/x86_64-windows-gnu
        \\exec_prefix=/b/h_env/Library/zig-libs/x86_64-windows-gnu
        \\libdir=/b/h_env/Library/zig-libs/x86_64-windows-gnu/lib
        \\sharedlibdir=/b/h_env/Library/zig-libs/x86_64-windows-gnu/lib
        \\includedir=/b/h_env/Library/zig-libs/x86_64-windows-gnu/include
        \\
        \\Name: zlib
        \\Description: zlib compression library
        \\Version: 1.3.1
        \\
        \\Requires:
        \\Libs: -L${libdir} -L${sharedlibdir} -lz
        \\Cflags: -I${includedir}
        \\
    ;
    const want =
        \\prefix=${pcfiledir}/../..
        \\exec_prefix=${prefix}
        \\libdir=${prefix}/lib
        \\sharedlibdir=${prefix}/lib
        \\includedir=${prefix}/include
        \\
        \\Name: zlib
        \\Description: zlib compression library
        \\Version: 1.3.1
        \\
        \\Requires:
        \\Libs: -L${libdir} -L${sharedlibdir} -lz
        \\Cflags: -I${includedir}
        \\
    ;
    try testing.expectEqualStrings(want, try close(arena.allocator(), in, ""));
}

test "private fields merged, extra libs appended, absolute paths refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const in = "prefix=/p\r\nlibdir=${prefix}/lib\r\nLibs: -L${libdir} -lgdal\r\nLibs.private: -lproj -lz\r\nRequires.private: proj\r\n";
    try testing.expectEqualStrings("prefix=${pcfiledir}/../..\nlibdir=${prefix}/lib\nLibs: -L${libdir} -lgdal -lproj -lz -lws2_32\nRequires: proj\n", try close(a, in, "-lws2_32"));
    try testing.expectError(error.BadPc, close(a, "prefix=/p\nLibs: -L/usr/lib -lz\n", ""));
    try testing.expectError(error.BadPc, close(a, "prefix=/p\nCflags: -IC:/x/include\n", ""));
    try testing.expectError(error.BadPc, close(a, "Libs: -lz\n", ""));
}
