//! `zig-toolchain check-alignment [--expect <subdir>,...] <dir>...`: one
//! build number per package across subdirs (CONVENTIONS.md "Versions and
//! build numbers", DESIGN 5.2) over channels built locally or in one CI run.
//! It covers part of flang-pixi's scripts/check-build-alignment.py: that
//! script also compares with the published universe channel and with
//! declared release numbers, which is what catches --skip-existing keeping
//! stale subdirs (DESIGN R15). That comparison is not here yet (M0-F22;
//! planned before M5: a channel-URL input).
//!
//! Each <dir> is a conda subdir (it holds repodata.json) or a channel root
//! (its child directories that hold a repodata.json are the subdirs). The
//! same subdir may come from several dirs (one artifact per CI job); their
//! records are merged. The records come from repodata.json, which
//! rattler-build writes into every subdir it builds for, so no .conda is
//! opened. Every .conda/.tar.bz2 in a subdir must be listed in its
//! repodata.json and every listed file must exist: a stale index would
//! hide a package from the check.
//!
//! Rules, per package name and version (the newest build number of each
//! subdir counts, as in flang-pixi's script):
//!   1. the subdirs that have it all have the same build number;
//!   2. with --expect, a package present in any expected subdir is present
//!      in every expected subdir, and every expected subdir exists. A
//!      package found only outside the expected subdirs (zig-toolchain in
//!      linux-64) is checked by rule 1 alone.
//! Prints one table row per package and version, then the problems.
//! Exit 0 when aligned, 1 on any problem or unreadable input, 2 on usage.
const std = @import("std");
const mem = std.mem;
const Io = std.Io;

pub const Record = struct {
    subdir: []const u8,
    name: []const u8,
    version: []const u8,
    build_number: u64,
    file: []const u8,
};

pub const LoadError = error{ BadRepodata, OutOfMemory };

fn fail(comptime fmt: []const u8, args: anytype) LoadError {
    std.debug.print("zig-toolchain check-alignment: " ++ fmt ++ "\n", args);
    return error.BadRepodata;
}

fn str(v: std.json.Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

/// The records of one repodata.json. The subdir is its info.subdir, else
/// `fallback_subdir` (the directory's name). `files` gets every file name
/// the index lists.
pub fn parseRepodata(
    a: mem.Allocator,
    text: []const u8,
    fallback_subdir: []const u8,
    records: *std.ArrayList(Record),
    files: *std.ArrayList([]const u8),
) LoadError![]const u8 {
    const root = std.json.parseFromSliceLeaky(std.json.Value, a, text, .{}) catch |err|
        return fail("repodata.json is not JSON: {t}", .{err});
    if (root != .object) return fail("repodata.json is not a JSON object", .{});
    var subdir = fallback_subdir;
    if (root.object.get("info")) |info| if (info == .object) if (info.object.get("subdir")) |s| if (str(s)) |v| {
        subdir = v;
    };
    for ([_][]const u8{ "packages", "packages.conda" }) |section| {
        const pkgs = root.object.get(section) orelse continue;
        if (pkgs != .object) return fail("{s}: \"{s}\" is not an object", .{ subdir, section });
        var it = pkgs.object.iterator();
        while (it.next()) |e| {
            const file = e.key_ptr.*;
            const obj = e.value_ptr.*;
            if (obj != .object) return fail("{s}/{s}: record is not an object", .{ subdir, file });
            const name = str(obj.object.get("name") orelse .null) orelse return fail("{s}/{s}: no name", .{ subdir, file });
            const version = str(obj.object.get("version") orelse .null) orelse return fail("{s}/{s}: no version", .{ subdir, file });
            const bn: u64 = switch (obj.object.get("build_number") orelse .null) {
                .integer => |n| if (n >= 0) @intCast(n) else return fail("{s}/{s}: negative build_number", .{ subdir, file }),
                else => return fail("{s}/{s}: no build_number", .{ subdir, file }),
            };
            try records.append(a, .{ .subdir = subdir, .name = name, .version = version, .build_number = bn, .file = file });
            try files.append(a, file);
        }
    }
    return subdir;
}

fn isPackageFile(name: []const u8) bool {
    return mem.endsWith(u8, name, ".conda") or mem.endsWith(u8, name, ".tar.bz2");
}

fn contains(list: []const []const u8, x: []const u8) bool {
    for (list) |y| if (mem.eql(u8, x, y)) return true;
    return false;
}

/// One subdir directory: its repodata.json, checked against its files.
fn loadSubdir(io: Io, a: mem.Allocator, path: []const u8, records: *std.ArrayList(Record), subdirs: *std.ArrayList([]const u8)) LoadError!void {
    const rd = std.fs.path.join(a, &.{ path, "repodata.json" }) catch return error.OutOfMemory;
    const text = Io.Dir.cwd().readFileAlloc(io, rd, a, .limited(1 << 30)) catch |err|
        return fail("cannot read {s}: {t}", .{ rd, err });
    var listed: std.ArrayList([]const u8) = .empty;
    const subdir = parseRepodata(a, text, std.fs.path.basename(path), records, &listed) catch |err| {
        std.debug.print("zig-toolchain check-alignment: in {s}\n", .{rd});
        return err;
    };
    if (!contains(subdirs.items, subdir)) try subdirs.append(a, subdir);

    var dir = Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err|
        return fail("cannot open {s}: {t}", .{ path, err });
    defer dir.close(io);
    var present: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch |err| return fail("cannot list {s}: {t}", .{ path, err })) |e| {
        if (e.kind == .directory or !isPackageFile(e.name)) continue;
        try present.append(a, try a.dupe(u8, e.name));
    }
    var stale = false;
    for (present.items) |f| if (!contains(listed.items, f)) {
        std.debug.print("zig-toolchain check-alignment: {s}/{s} is not in its repodata.json (stale index)\n", .{ path, f });
        stale = true;
    };
    for (listed.items) |f| if (!contains(present.items, f)) {
        std.debug.print("zig-toolchain check-alignment: {s}/repodata.json lists {s}, which is missing\n", .{ path, f });
        stale = true;
    };
    if (stale) return error.BadRepodata;
}

fn hasRepodata(io: Io, a: mem.Allocator, path: []const u8) bool {
    const rd = std.fs.path.join(a, &.{ path, "repodata.json" }) catch return false;
    Io.Dir.cwd().access(io, rd, .{}) catch return false;
    return true;
}

/// A subdir directory, or a channel root whose child directories are.
pub fn load(io: Io, a: mem.Allocator, path: []const u8, records: *std.ArrayList(Record), subdirs: *std.ArrayList([]const u8)) LoadError!void {
    if (hasRepodata(io, a, path)) return loadSubdir(io, a, path, records, subdirs);
    var dir = Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch |err|
        return fail("cannot open {s}: {t}", .{ path, err });
    defer dir.close(io);
    var children: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch |err| return fail("cannot list {s}: {t}", .{ path, err })) |e| {
        // a subdir may be a link (an unpacked artifact, a shared cache);
        // hasRepodata below drops every child that is not a subdir
        if (e.kind != .directory and e.kind != .sym_link) continue;
        const child = std.fs.path.join(a, &.{ path, e.name }) catch return error.OutOfMemory;
        if (hasRepodata(io, a, child)) try children.append(a, child);
    }
    if (children.items.len == 0) return fail("{s}: no repodata.json in it or in its subdirectories", .{path});
    mem.sort([]const u8, children.items, {}, lessStr);
    for (children.items) |c| try loadSubdir(io, a, c, records, subdirs);
}

fn lessStr(_: void, x: []const u8, y: []const u8) bool {
    return mem.order(u8, x, y) == .lt;
}

const Key = struct { name: []const u8, version: []const u8 };

fn lessKey(_: void, x: Key, y: Key) bool {
    return switch (mem.order(u8, x.name, y.name)) {
        .lt => true,
        .gt => false,
        .eq => mem.order(u8, x.version, y.version) == .lt,
    };
}

/// The newest build number of `key` in `subdir`, or null.
fn newest(records: []const Record, key: Key, subdir: []const u8) ?u64 {
    var best: ?u64 = null;
    for (records) |r| {
        if (!mem.eql(u8, r.name, key.name) or !mem.eql(u8, r.version, key.version) or !mem.eql(u8, r.subdir, subdir)) continue;
        if (best == null or r.build_number > best.?) best = r.build_number;
    }
    return best;
}

/// The table and the problems, into `out`. Returns the number of problems.
pub fn check(
    a: mem.Allocator,
    records: []const Record,
    found_subdirs: []const []const u8,
    expect: []const []const u8,
    out: *std.ArrayList(u8),
) error{OutOfMemory}!usize {
    var problems: std.ArrayList([]const u8) = .empty;

    // the table's columns: the subdirs with packages, and the expected ones
    var subdirs: std.ArrayList([]const u8) = .empty;
    for (records) |r| if (!contains(subdirs.items, r.subdir)) try subdirs.append(a, r.subdir);
    for (expect) |s| if (!contains(found_subdirs, s))
        try problems.append(a, try std.fmt.allocPrint(a, "expected subdir {s} is not among the inputs", .{s}));
    for (expect) |s| if (!contains(subdirs.items, s)) try subdirs.append(a, s);
    mem.sort([]const u8, subdirs.items, {}, lessStr);

    var keys: std.ArrayList(Key) = .empty;
    for (records) |r| {
        const k: Key = .{ .name = r.name, .version = r.version };
        for (keys.items) |x| {
            if (mem.eql(u8, x.name, k.name) and mem.eql(u8, x.version, k.version)) break;
        } else try keys.append(a, k);
    }
    mem.sort(Key, keys.items, {}, lessKey);

    var name_w: usize = "package".len;
    var ver_w: usize = "version".len;
    for (keys.items) |k| {
        name_w = @max(name_w, k.name.len);
        ver_w = @max(ver_w, k.version.len);
    }
    const w = 11;
    try pad(a, out, "package", name_w + 2);
    try pad(a, out, "version", ver_w + 2);
    for (subdirs.items) |s| try pad(a, out, s, @max(w, s.len + 2));
    try out.appendSlice(a, "status\n");

    for (keys.items) |k| {
        try pad(a, out, k.name, name_w + 2);
        try pad(a, out, k.version, ver_w + 2);
        var first: ?u64 = null;
        var differ = false;
        var in_expected = false;
        for (subdirs.items) |s| {
            const bn = newest(records, k, s);
            const cell = if (bn) |n| try std.fmt.allocPrint(a, "_{d}", .{n}) else "-";
            try pad(a, out, cell, @max(w, s.len + 2));
            if (bn) |n| {
                if (first) |f| {
                    if (f != n) differ = true;
                } else first = n;
                if (contains(expect, s)) in_expected = true;
            }
        }
        var row_ok = true;
        if (differ) {
            row_ok = false;
            var msg: std.ArrayList(u8) = .empty;
            try msg.print(a, "{s} {s}: build numbers differ across subdirs (", .{ k.name, k.version });
            var sep = false;
            for (subdirs.items) |s| if (newest(records, k, s)) |n| {
                if (sep) try msg.appendSlice(a, ", ");
                try msg.print(a, "{s} _{d}", .{ s, n });
                sep = true;
            };
            try msg.appendSlice(a, ")");
            try problems.append(a, msg.items);
        }
        if (in_expected) for (expect) |s| if (newest(records, k, s) == null) {
            row_ok = false;
            try problems.append(a, try std.fmt.allocPrint(a, "{s} {s}: missing from expected subdir {s}", .{ k.name, k.version, s }));
        };
        try out.appendSlice(a, if (row_ok) "ok\n" else "FAIL\n");
    }
    if (keys.items.len == 0) try problems.append(a, "no packages in the inputs");

    for (problems.items) |p| try out.print(a, "problem: {s}\n", .{p});
    if (problems.items.len == 0)
        try out.print(a, "build alignment OK: {d} package version(s) over {d} subdir(s)\n", .{ keys.items.len, subdirs.items.len })
    else
        try out.print(a, "build alignment FAILED: {d} problem(s) (one build number per package across subdirs, CONVENTIONS.md)\n", .{problems.items.len});
    return problems.items.len;
}

fn pad(a: mem.Allocator, out: *std.ArrayList(u8), s: []const u8, width: usize) !void {
    try out.appendSlice(a, s);
    var n = s.len;
    while (n < width) : (n += 1) try out.append(a, ' ');
    if (s.len >= width) try out.append(a, ' ');
}

const usage = "usage: zig-toolchain check-alignment [--expect <subdir>[,<subdir>...]] <channel-or-subdir-dir>...\n";

pub fn run(io: Io, a: mem.Allocator, args: []const []const u8) u8 {
    var expect: std.ArrayList([]const u8) = .empty;
    var dirs: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        var list: ?[]const u8 = null;
        if (mem.eql(u8, x, "--expect")) {
            if (i + 1 >= args.len) {
                std.debug.print("zig-toolchain check-alignment: --expect needs a value\n{s}", .{usage});
                return 2;
            }
            i += 1;
            list = args[i];
        } else if (mem.startsWith(u8, x, "--expect=")) {
            list = x["--expect=".len..];
        } else if (mem.startsWith(u8, x, "-")) {
            std.debug.print("zig-toolchain check-alignment: unknown option {s}\n{s}", .{ x, usage });
            return 2;
        } else dirs.append(a, x) catch return 1;
        if (list) |l| {
            var it = mem.tokenizeAny(u8, l, ", ");
            while (it.next()) |s| expect.append(a, s) catch return 1;
        }
    }
    if (dirs.items.len == 0) {
        std.debug.print("{s}", .{usage});
        return 2;
    }
    var records: std.ArrayList(Record) = .empty;
    var subdirs: std.ArrayList([]const u8) = .empty;
    for (dirs.items) |d| load(io, a, d, &records, &subdirs) catch return 1;
    var out: std.ArrayList(u8) = .empty;
    const n = check(a, records.items, subdirs.items, expect.items, &out) catch return 1;
    Io.File.stdout().writeStreamingAll(io, out.items) catch return 1;
    return if (n == 0) 0 else 1;
}

const testing = std.testing;

fn rec(subdir: []const u8, name: []const u8, version: []const u8, bn: u64) Record {
    return .{ .subdir = subdir, .name = name, .version = version, .build_number = bn, .file = "" };
}

fn runCheck(a: mem.Allocator, records: []const Record, subdirs: []const []const u8, expect: []const []const u8) !struct { n: usize, text: []const u8 } {
    var out: std.ArrayList(u8) = .empty;
    const n = try check(a, records, subdirs, expect, &out);
    return .{ .n = n, .text = out.items };
}

test "aligned: zig-toolchain only in linux-64, zig-zlib in both win subdirs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const recs = [_]Record{
        rec("linux-64", "zig-toolchain", "0.1.0", 0),
        rec("win-64", "zig-zlib", "1.3.1", 0),
        rec("win-arm64", "zig-zlib", "1.3.1", 0),
    };
    const r = try runCheck(a, &recs, &.{ "linux-64", "win-64", "win-arm64" }, &.{ "win-64", "win-arm64" });
    try testing.expectEqual(@as(usize, 0), r.n);
    try testing.expect(mem.indexOf(u8, r.text, "build alignment OK: 2 package version(s) over 3 subdir(s)") != null);
}

test "build numbers differ, the newest per subdir counts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const recs = [_]Record{
        rec("win-64", "zig-zlib", "1.3.1", 0),
        rec("win-64", "zig-zlib", "1.3.1", 1),
        rec("win-arm64", "zig-zlib", "1.3.1", 0),
        // another version is a separate row; its numbers agree
        rec("win-64", "zig-zlib", "1.3.2", 0),
        rec("win-arm64", "zig-zlib", "1.3.2", 0),
    };
    const r = try runCheck(a, &recs, &.{ "win-64", "win-arm64" }, &.{});
    try testing.expectEqual(@as(usize, 1), r.n);
    try testing.expect(mem.indexOf(u8, r.text, "zig-zlib 1.3.1: build numbers differ across subdirs (win-64 _1, win-arm64 _0)") != null);
    try testing.expect(mem.indexOf(u8, r.text, "build alignment FAILED: 1 problem(s)") != null);
}

test "missing from an expected subdir; without --expect only rule 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const recs = [_]Record{
        rec("linux-64", "zig-toolchain", "0.1.0", 0),
        rec("win-64", "zig-zlib", "1.3.1", 0),
        rec("win-64", "zig-sqlite", "3.51.2", 0),
        rec("win-arm64", "zig-sqlite", "3.51.2", 0),
    };
    const subdirs = [_][]const u8{ "linux-64", "win-64", "win-arm64" };
    const r = try runCheck(a, &recs, &subdirs, &.{ "win-64", "win-arm64" });
    try testing.expectEqual(@as(usize, 1), r.n);
    try testing.expect(mem.indexOf(u8, r.text, "zig-zlib 1.3.1: missing from expected subdir win-arm64") != null);
    try testing.expectEqual(@as(usize, 0), (try runCheck(a, &recs, &subdirs, &.{})).n);
    // an expected subdir that no input has
    const r2 = try runCheck(a, recs[2..], &.{ "win-64", "win-arm64" }, &.{ "win-64", "win-arm64", "osx-arm64" });
    try testing.expect(mem.indexOf(u8, r2.text, "expected subdir osx-arm64 is not among the inputs") != null);
    try testing.expect(r2.n >= 2);
    // nothing at all
    try testing.expectEqual(@as(usize, 1), (try runCheck(a, &.{}, &.{"win-64"}, &.{})).n);
}

test "parseRepodata: rattler-build's index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\{"info":{"subdir":"win-64"},"packages":{},"packages.conda":{"zig-zlib-1.3.1-zig_29ef852_0.conda":
        \\{"arch":"x86_64","build":"zig_29ef852_0","build_number":0,"depends":[],"name":"zig-zlib","subdir":"win-64","version":"1.3.1"}},
        \\"repodata_version":1,"v3":{}}
    ;
    var records: std.ArrayList(Record) = .empty;
    var files: std.ArrayList([]const u8) = .empty;
    const sd = try parseRepodata(a, text, "dirname", &records, &files);
    try testing.expectEqualStrings("win-64", sd);
    try testing.expectEqual(@as(usize, 1), records.items.len);
    try testing.expectEqualStrings("zig-zlib", records.items[0].name);
    try testing.expectEqual(@as(u64, 0), records.items[0].build_number);
    try testing.expectEqualStrings("zig-zlib-1.3.1-zig_29ef852_0.conda", files.items[0]);
    // no info.subdir: the directory's name
    records.clearRetainingCapacity();
    try testing.expectEqualStrings("noarch", try parseRepodata(a, "{\"packages\":{}}", "noarch", &records, &files));
    try testing.expectError(error.BadRepodata, parseRepodata(a, "{\"packages.conda\":{\"x.conda\":{\"name\":\"x\",\"version\":\"1\"}}}", "s", &records, &files));
    try testing.expectError(error.BadRepodata, parseRepodata(a, "not json", "s", &records, &files));
}

test "load: channel root, merged inputs, stale index refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try std.fs.path.join(a, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    const entry = "{{\"name\":\"zig-zlib\",\"version\":\"1.3.1\",\"build_number\":{d}}}";
    for ([_]struct { []const u8, []const u8, u64 }{ .{ "a/win-64", "z-0.conda", 0 }, .{ "b/win-arm64", "z-1.conda", 1 } }) |x| {
        try tmp.dir.createDirPath(io, x[0]);
        const body = try std.fmt.allocPrint(a, "{{\"info\":{{\"subdir\":\"{s}\"}},\"packages.conda\":{{\"{s}\":" ++ entry ++ "}}}}", .{ std.fs.path.basename(x[0]), x[1], x[2] });
        try tmp.dir.writeFile(io, .{ .sub_path = try std.fs.path.join(a, &.{ x[0], "repodata.json" }), .data = body });
        try tmp.dir.writeFile(io, .{ .sub_path = try std.fs.path.join(a, &.{ x[0], x[1] }), .data = "" });
    }
    var records: std.ArrayList(Record) = .empty;
    var subdirs: std.ArrayList([]const u8) = .empty;
    // a channel root, and a subdir dir given directly
    try load(io, a, try std.fs.path.join(a, &.{ base, "a" }), &records, &subdirs);
    try load(io, a, try std.fs.path.join(a, &.{ base, "b", "win-arm64" }), &records, &subdirs);
    try testing.expectEqual(@as(usize, 2), records.items.len);
    const r = try runCheck(a, records.items, subdirs.items, &.{ "win-64", "win-arm64" });
    try testing.expectEqual(@as(usize, 1), r.n);
    // a .conda the index does not list
    try tmp.dir.writeFile(io, .{ .sub_path = "a/win-64/extra-1-0.conda", .data = "" });
    try testing.expectError(error.BadRepodata, load(io, a, try std.fs.path.join(a, &.{ base, "a" }), &records, &subdirs));
    // no repodata anywhere
    try tmp.dir.createDirPath(io, "empty/x");
    try testing.expectError(error.BadRepodata, load(io, a, try std.fs.path.join(a, &.{ base, "empty" }), &records, &subdirs));
}

test "load: a channel root whose subdir is a symlink" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try std.fs.path.join(a, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    try tmp.dir.createDirPath(io, "real/win-64");
    try tmp.dir.createDirPath(io, "root/win-arm64");
    try tmp.dir.writeFile(io, .{ .sub_path = "real/win-64/repodata.json", .data = "{\"info\":{\"subdir\":\"win-64\"},\"packages.conda\":{\"z-0.conda\":{\"name\":\"zig-zlib\",\"version\":\"1.3.1\",\"build_number\":0}}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "real/win-64/z-0.conda", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "root/win-arm64/repodata.json", .data = "{\"info\":{\"subdir\":\"win-arm64\"},\"packages.conda\":{\"y-0.conda\":{\"name\":\"zig-zlib\",\"version\":\"1.3.1\",\"build_number\":0}}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "root/win-arm64/y-0.conda", .data = "" });
    try tmp.dir.symLink(io, "../real/win-64", "root/win-64", .{ .is_directory = true });
    // a symlink to a file is no subdir and is skipped
    try tmp.dir.symLink(io, "win-arm64/repodata.json", "root/notes", .{});
    var records: std.ArrayList(Record) = .empty;
    var subdirs: std.ArrayList([]const u8) = .empty;
    try load(io, a, try std.fs.path.join(a, &.{ base, "root" }), &records, &subdirs);
    try testing.expectEqual(@as(usize, 2), records.items.len);
    const r = try runCheck(a, records.items, subdirs.items, &.{ "win-64", "win-arm64" });
    try testing.expectEqual(@as(usize, 0), r.n);
}
