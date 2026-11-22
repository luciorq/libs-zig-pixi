//! `zig-toolchain close-pc [--libs "<words>"] <file.pc>...`: makes an
//! installed pkg-config file closed and relocatable, in place.
//!
//!   relocatable  `prefix=${pcfiledir}/../..` (the .pc sits in
//!                <sub-prefix>/lib/pkgconfig or share/pkgconfig); every
//!                other occurrence of the old prefix as a whole path (at a
//!                word or option start, followed by a slash, a space or the
//!                line's end) becomes ${prefix}, and exec_prefix is
//!                ${prefix}. No absolute path may remain: any is an error
//!                (exit 1), naming the line.
//!   closed       Libs.private is appended to Libs, Cflags.private to
//!                Cflags and Requires.private to Requires (a missing Libs,
//!                Cflags or Requires line is added), and the private
//!                lines are dropped: r-zig's pkgconf prints the .private
//!                fields only with --static, which the R packages never
//!                pass (a static define such as expat's -DXML_STATIC sits in
//!                Cflags.private). --libs appends more words (the Windows
//!                system libraries the archive needs) to Libs.
//!   libc++       one spelling of the C++ runtime in Libs: -lstdc++ (as
//!                GEOS's .pc writes it; zig links its libc++ for it too)
//!                becomes -lc++, and only the first -lc++ is kept.
//!   comments     `#` lines (licence headers with URLs) are kept as they
//!                are: no prefix replacement, no absolute-path check.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;

pub const Error = error{ BadPc, OutOfMemory };

fn fail(comptime fmt: []const u8, args: anytype) Error {
    std.debug.print("zig-toolchain close-pc: " ++ fmt ++ "\n", args);
    return error.BadPc;
}

/// `Key: value` (a field) or null. The key's case is ignored, as pkgconf
/// does (`CFlags:` is `Cflags:`).
fn field(line: []const u8, key: []const u8) ?[]const u8 {
    if (line.len > key.len and std.ascii.startsWithIgnoreCase(line, key) and line[key.len] == ':')
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

/// Libs words with the C++ runtime spelled -lc++ once (-lstdc++ is the
/// same libc++ under zig).
fn oneCxxRuntime(a: mem.Allocator, libs: []const u8) ![]const u8 {
    var s: std.ArrayList(u8) = .empty;
    var seen = false;
    var words = mem.tokenizeAny(u8, libs, " \t");
    while (words.next()) |w0| {
        const w = if (mem.eql(u8, w0, "-lstdc++")) "-lc++" else w0;
        if (mem.eql(u8, w, "-lc++")) {
            if (seen) continue;
            seen = true;
        }
        if (s.items.len > 0) try s.append(a, ' ');
        try s.appendSlice(a, w);
    }
    return s.items;
}

fn isComment(line: []const u8) bool {
    return mem.startsWith(u8, mem.trimStart(u8, line, " \t"), "#");
}

/// Whether the prefix found at line[i..end] is a whole path: it starts a
/// word, a variable value or an option's argument, and ends at a slash, a
/// space or the line's end. So prefix /p is not replaced inside /proj,
/// /x/p/lib or http://example.org/p.
fn atPathBoundary(line: []const u8, i: usize, end: usize) bool {
    if (end < line.len and mem.indexOfScalar(u8, "/\\ \t\"'", line[end]) == null) return false;
    if (i == 0) return true;
    if (mem.indexOfScalar(u8, " \t=\"':", line[i - 1]) != null) return true;
    for ([_][]const u8{ "-L", "-I", "-isystem", "-idirafter", "-Wl,-rpath,", "-Wl,-rpath=" }) |opt| {
        if (i >= opt.len and mem.eql(u8, line[i - opt.len .. i], opt) and
            (i == opt.len or mem.indexOfScalar(u8, " \t=:", line[i - opt.len - 1]) != null)) return true;
    }
    return false;
}

/// `line` with every whole-path occurrence of `prefix` replaced by ${prefix}.
fn replacePrefix(a: mem.Allocator, line: []const u8, prefix: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (mem.indexOfPos(u8, line, i, prefix)) |at| {
        const end = at + prefix.len;
        if (atPathBoundary(line, at, end)) {
            try out.appendSlice(a, line[i..at]);
            try out.appendSlice(a, "${prefix}");
        } else {
            try out.appendSlice(a, line[i..end]);
        }
        i = end;
    }
    try out.appendSlice(a, line[i..]);
    return out.items;
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
    var cflags: []const u8 = "";
    var cflags_private: []const u8 = "";
    var requires: []const u8 = "";
    var requires_private: []const u8 = "";
    var lines: std.ArrayList([]const u8) = .empty;
    it = mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        var line: []const u8 = mem.trimEnd(u8, raw, "\r");
        if (isComment(line)) {
            try lines.append(a, line);
            continue;
        }
        if (variable(line, "prefix") != null) {
            try lines.append(a, "prefix=${pcfiledir}/../..");
            continue;
        }
        if (variable(line, "exec_prefix") != null) {
            try lines.append(a, "exec_prefix=${prefix}");
            continue;
        }
        if (prefix.len > 0 and prefix[0] != '$')
            line = try replacePrefix(a, line, prefix);
        if (field(line, "Libs.private")) |v| {
            libs_private = v;
            continue;
        }
        if (field(line, "Cflags.private")) |v| {
            cflags_private = v;
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
        if (field(line, "Cflags")) |v| {
            cflags = v;
            try lines.append(a, "\x00cflags");
            continue;
        }
        if (field(line, "Requires")) |v| {
            requires = v;
            try lines.append(a, "\x00requires");
            continue;
        }
        try lines.append(a, line);
    }
    // a missing Libs, Requires or Cflags line gets one only when there is
    // something to put there
    var have_libs = false;
    var have_requires = false;
    var have_cflags = false;
    for (lines.items) |l| {
        if (mem.eql(u8, l, "\x00libs")) have_libs = true;
        if (mem.eql(u8, l, "\x00requires")) have_requires = true;
        if (mem.eql(u8, l, "\x00cflags")) have_cflags = true;
    }

    var out: std.ArrayList(u8) = .empty;
    for (lines.items, 0..) |l, n| {
        if (mem.eql(u8, l, "\x00libs")) {
            try out.print(a, "Libs: {s}\n", .{try oneCxxRuntime(a, try join(a, &.{ libs, libs_private, extra_libs }))});
        } else if (mem.eql(u8, l, "\x00cflags")) {
            try out.print(a, "Cflags: {s}\n", .{try join(a, &.{ cflags, cflags_private })});
        } else if (mem.eql(u8, l, "\x00requires")) {
            const r = try join(a, &.{ requires, requires_private });
            try out.print(a, "Requires:{s}{s}\n", .{ if (r.len > 0) " " else "", r });
        } else {
            // the text's trailing newline gives one empty last item
            if (n == lines.items.len - 1 and l.len == 0) break;
            try out.print(a, "{s}\n", .{l});
        }
    }
    if (!have_libs) {
        const l = try oneCxxRuntime(a, try join(a, &.{ libs_private, extra_libs }));
        if (l.len > 0) try out.print(a, "Libs: {s}\n", .{l});
    }
    if (!have_requires and requires_private.len > 0) try out.print(a, "Requires: {s}\n", .{requires_private});
    if (!have_cflags and cflags_private.len > 0) try out.print(a, "Cflags: {s}\n", .{cflags_private});

    // nothing absolute may remain (comment lines aside)
    var check = mem.splitScalar(u8, out.items, '\n');
    var line_no: usize = 0;
    while (check.next()) |line| {
        line_no += 1;
        if (isComment(line)) continue;
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

test "Cflags.private merged into Cflags (expat 2.7.3's -DXML_STATIC)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const in =
        \\prefix=/b/h_env/Library/zig-libs/x86_64-windows-gnu
        \\exec_prefix=${prefix}
        \\libdir=${exec_prefix}/lib
        \\includedir=${prefix}/include
        \\
        \\Name: expat
        \\Version: 2.7.3
        \\Libs: -L${libdir} -lexpat
        \\Libs.private: -lm
        \\Cflags: -I${includedir}
        \\Cflags.private: -DXML_STATIC
        \\
    ;
    const want =
        \\prefix=${pcfiledir}/../..
        \\exec_prefix=${prefix}
        \\libdir=${exec_prefix}/lib
        \\includedir=${prefix}/include
        \\
        \\Name: expat
        \\Version: 2.7.3
        \\Libs: -L${libdir} -lexpat -lm
        \\Cflags: -I${includedir} -DXML_STATIC
        \\
    ;
    try testing.expectEqualStrings(want, try close(a, in, ""));
    // only Cflags.private: a Cflags line is written
    try testing.expectEqualStrings("prefix=${pcfiledir}/../..\nLibs: -lx\nCflags: -DX_STATIC\n", try close(a, "prefix=/p\nLibs: -lx\nCflags.private: -DX_STATIC\n", ""));
}

test "comment lines kept as they are (oneTBB 2022.2.0's licence header)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const in =
        \\# Copyright (c) 2021-2023 Intel Corporation
        \\#
        \\# you may not use this file except in compliance with the License.
        \\#     http://www.apache.org/licenses/LICENSE-2.0
        \\  # /b/h_env stays in an indented comment too
        \\
        \\prefix=/b/h_env
        \\libdir=/b/h_env/lib
        \\Libs: -L${libdir} -ltbb12
        \\
    ;
    const want =
        \\# Copyright (c) 2021-2023 Intel Corporation
        \\#
        \\# you may not use this file except in compliance with the License.
        \\#     http://www.apache.org/licenses/LICENSE-2.0
        \\  # /b/h_env stays in an indented comment too
        \\
        \\prefix=${pcfiledir}/../..
        \\libdir=${prefix}/lib
        \\Libs: -L${libdir} -ltbb12
        \\
    ;
    try testing.expectEqualStrings(want, try close(arena.allocator(), in, ""));
}

test "prefix replaced only as a whole path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // /p inside /proj, after another directory, or in a URL stays; at a
    // value's or an option's start, before / or the end, it is replaced
    try testing.expectEqualStrings(
        "prefix=${pcfiledir}/../..\nlibdir=${prefix}/lib\nURL: http://example.org/p\nName: proj\nCflags: -I${prefix}/include -I${prefix} -isystem${prefix}/x\n",
        try close(a, "prefix=/p\nlibdir=/p/lib\nURL: http://example.org/p\nName: proj\nCflags: -I/p/include -I/p -isystem/p/x\n", ""),
    );
    // the old substring replacement turned /x/p/lib into /x${prefix}/lib;
    // now it is left as it is, and refused as an absolute path
    try testing.expectError(error.BadPc, close(a, "prefix=/p\nLibs: -L/x/p/lib -lz\n", ""));
    try testing.expectEqualStrings("a ${prefix}/b ${prefix}", try replacePrefix(a, "a /p/b /p", "/p"));
    try testing.expectEqualStrings("/proj /pp:/p", try replacePrefix(a, "/proj /pp:/p", "/pp/x"));
    try testing.expectEqualStrings("x=${prefix}\\lib", try replacePrefix(a, "x=C:\\p\\lib", "C:\\p"));
}

test "one C++ runtime spelling: -lc++ (GEOS 3.14.1's geos.pc)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings(
        "prefix=${pcfiledir}/../..\nlibdir=${prefix}/lib\nLibs: -L${libdir} -lgeos_c -lgeos -lc++ -lm\n",
        try close(a, "prefix=/p\nlibdir=/p/lib\nLibs: -L${libdir} -lgeos_c\nLibs.private: -lgeos -lstdc++ -lm\n", ""),
    );
    // -lc++ from --libs after -lstdc++ in the file: one -lc++, first place
    try testing.expectEqualStrings(
        "prefix=${pcfiledir}/../..\nLibs: -lproj -lc++ -lole32\n",
        try close(a, "prefix=/p\nLibs: -lproj -lstdc++\n", "-lc++ -lole32"),
    );
    // a -lstdc++fs or -lc++abi stays as it is
    try testing.expectEqualStrings("-lc++ -lstdc++fs -lc++abi", try oneCxxRuntime(a, "-lstdc++ -lstdc++fs  -lc++abi -lc++"));
}

test "a missing Libs line gets Libs.private and --libs; CFlags is Cflags" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings(
        "prefix=${pcfiledir}/../..\nName: d\nCflags: -I${prefix}/include\nLibs: -ld -lws2_32\n",
        try close(a, "prefix=/p\nName: d\nLibs.private: -ld\nCflags: -I/p/include\n", "-lws2_32"),
    );
    try testing.expectEqualStrings("prefix=${pcfiledir}/../..\nLibs: -lws2_32\n", try close(a, "prefix=/p\n", "-lws2_32"));
    try testing.expectEqualStrings("prefix=${pcfiledir}/../..\n", try close(a, "prefix=/p\n", ""));
    // one Cflags line, whatever the key's case
    try testing.expectEqualStrings(
        "prefix=${pcfiledir}/../..\nCflags: -I${prefix}/include -DX_STATIC\n",
        try close(a, "prefix=/p\nCFlags: -I/p/include\nCflags.private: -DX_STATIC\n", ""),
    );
}
