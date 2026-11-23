//! `zig-toolchain check-alignment [--expect <subdir>,...] [--published
//! <channel>] <dir>...`: one build number per package across subdirs
//! (CONVENTIONS.md "Versions and build numbers", DESIGN 5.2) over channels
//! built locally or in one CI run.
//! With --published it also compares them with a published channel: a
//! build number below the published one, and two builds under one number
//! (DESIGN R15, m0 D45, M0-F22). A rebuild under an already published file
//! name shows only as `skip`: the build string carries the variant hash,
//! not the recipe, so a recipe change without a bump looks the same (R15
//! stays partly open, m5 PLAN). flang-pixi's scripts/check-build-alignment.py also checks
//! declared release numbers; that part is not here.
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
//!
//! --published <channel>: a channel URL (http:// or https://; a plain GET
//! of <channel>/<subdir>/repodata.json, no key, redirects followed) or a
//! channel directory, read for every subdir that has packages in the
//! inputs. A subdir the channel does not have (HTTP 404, no file) counts as
//! empty; the channel itself must exist (a URL must serve noarch). Rules,
//! per subdir, package name and version, for the newest local build
//! number:
//!   3. it is not below the newest published build number;
//!   4. when that number is published, it is published as the same file
//!      (the same build string). Then the upload skips it: `published`, or
//!      `skip` when the published sha256 differs (a rebuild; the channel
//!      keeps the published file). The same number under another build
//!      string is a problem: two builds with one number.
//! Prints a second table, one row per subdir, package and version.
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
    /// the build string and sha256 when the index has them
    build: []const u8 = "",
    sha256: []const u8 = "",
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
/// the index lists. The v3 section (records with flags or extra_depends)
/// keys a record by its name without extension, under "conda" or
/// "tar.bz2".
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
        try parseSection(a, subdir, section, pkgs, "", records, files);
    }
    if (root.object.get("v3")) |v3| {
        if (v3 != .object) return fail("{s}: \"v3\" is not an object", .{subdir});
        for ([_][]const u8{ "conda", "tar.bz2" }) |ext| {
            const pkgs = v3.object.get(ext) orelse continue;
            try parseSection(a, subdir, "v3", pkgs, try std.fmt.allocPrint(a, ".{s}", .{ext}), records, files);
        }
    }
    return subdir;
}

fn parseSection(
    a: mem.Allocator,
    subdir: []const u8,
    section: []const u8,
    pkgs: std.json.Value,
    ext: []const u8,
    records: *std.ArrayList(Record),
    files: *std.ArrayList([]const u8),
) LoadError!void {
    if (pkgs != .object) return fail("{s}: \"{s}\" is not an object", .{ subdir, section });
    var it = pkgs.object.iterator();
    while (it.next()) |e| {
        const file = if (ext.len == 0) e.key_ptr.* else try mem.concat(a, u8, &.{ e.key_ptr.*, ext });
        const obj = e.value_ptr.*;
        if (obj != .object) return fail("{s}/{s}: record is not an object", .{ subdir, file });
        const name = str(obj.object.get("name") orelse .null) orelse return fail("{s}/{s}: no name", .{ subdir, file });
        const version = str(obj.object.get("version") orelse .null) orelse return fail("{s}/{s}: no version", .{ subdir, file });
        const bn: u64 = switch (obj.object.get("build_number") orelse .null) {
            .integer => |n| if (n >= 0) @intCast(n) else return fail("{s}/{s}: negative build_number", .{ subdir, file }),
            else => return fail("{s}/{s}: no build_number", .{ subdir, file }),
        };
        try records.append(a, .{
            .subdir = subdir,
            .name = name,
            .version = version,
            .build_number = bn,
            .file = file,
            .build = str(obj.object.get("build") orelse .null) orelse "",
            .sha256 = str(obj.object.get("sha256") orelse .null) orelse "",
        });
        try files.append(a, file);
    }
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

fn isUrl(channel: []const u8) bool {
    return mem.startsWith(u8, channel, "https://") or mem.startsWith(u8, channel, "http://");
}

/// The published records of `subdirs` in `channel` (a URL or a directory).
pub fn loadPublished(io: Io, a: mem.Allocator, channel: []const u8, subdirs: []const []const u8, records: *std.ArrayList(Record)) LoadError!void {
    const base = mem.trimEnd(u8, channel, "/");
    var client: std.http.Client = .{ .allocator = a, .io = io };
    defer client.deinit();
    // a misspelled channel must not read as an empty one: a directory must
    // exist, a URL must serve noarch (every channel has it)
    if (isUrl(base)) {
        const noarch = try mem.concat(a, u8, &.{ base, "/noarch/repodata.json" });
        if (try fetch(&client, a, noarch) == null) return fail("{s} is not a channel: {s} is not found", .{ base, noarch });
    } else {
        var dir = Io.Dir.cwd().openDir(io, base, .{}) catch |err|
            return fail("cannot open published channel {s}: {t}", .{ base, err });
        dir.close(io);
    }
    for (subdirs) |sd| {
        const loc = try mem.concat(a, u8, &.{ base, "/", sd, "/repodata.json" });
        const text = if (isUrl(base)) try fetch(&client, a, loc) else Io.Dir.cwd().readFileAlloc(io, loc, a, .limited(1 << 30)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return fail("cannot read {s}: {t}", .{ loc, err }),
        };
        const t = text orelse continue;
        var files: std.ArrayList([]const u8) = .empty;
        _ = parseRepodata(a, t, sd, records, &files) catch |err| {
            std.debug.print("zig-toolchain check-alignment: in {s}\n", .{loc});
            return err;
        };
    }
}

/// The body of a GET of `url`, or null on 404 (a subdir the channel does
/// not have).
fn fetch(client: *std.http.Client, a: mem.Allocator, url: []const u8) LoadError!?[]const u8 {
    var body: Io.Writer.Allocating = .init(a);
    const res = client.fetch(.{ .location = .{ .url = url }, .response_writer = &body.writer }) catch |err|
        return fail("cannot fetch {s}: {t}", .{ url, err });
    if (res.status == .not_found) return null;
    if (res.status != .ok) return fail("cannot fetch {s}: HTTP {d}", .{ url, @backingInt(res.status) });
    return body.written();
}

fn lessRecord(_: void, x: Record, y: Record) bool {
    return switch (mem.order(u8, x.subdir, y.subdir)) {
        .lt => true,
        .gt => false,
        .eq => switch (mem.order(u8, x.name, y.name)) {
            .lt => true,
            .gt => false,
            .eq => switch (mem.order(u8, x.version, y.version)) {
                .lt => true,
                .gt => false,
                .eq => mem.order(u8, x.file, y.file) == .lt,
            },
        },
    };
}

/// Rules 3 and 4: the local records against the published ones, into
/// `out`. Returns the number of problems.
pub fn compare(
    a: mem.Allocator,
    channel: []const u8,
    local: []const Record,
    published: []const Record,
    out: *std.ArrayList(u8),
) error{OutOfMemory}!usize {
    var problems: std.ArrayList([]const u8) = .empty;
    // the newest local build of each subdir, name and version
    var rows: std.ArrayList(Record) = .empty;
    for (local) |r| if (newest(local, .{ .name = r.name, .version = r.version }, r.subdir) == r.build_number)
        try rows.append(a, r);
    mem.sort(Record, rows.items, {}, lessRecord);

    var sub_w: usize = "subdir".len;
    var name_w: usize = "package".len;
    var ver_w: usize = "version".len;
    var build_w: usize = "build".len;
    for (rows.items) |r| {
        sub_w = @max(sub_w, r.subdir.len);
        name_w = @max(name_w, r.name.len);
        ver_w = @max(ver_w, r.version.len);
        build_w = @max(build_w, r.build.len);
    }
    try out.print(a, "published channel: {s}\n", .{channel});
    try pad(a, out, "subdir", sub_w + 2);
    try pad(a, out, "package", name_w + 2);
    try pad(a, out, "version", ver_w + 2);
    try pad(a, out, "build", build_w + 2);
    try pad(a, out, "published", 11);
    try out.appendSlice(a, "status\n");

    var n_new: usize = 0;
    var n_published: usize = 0;
    var n_skip: usize = 0;
    for (rows.items) |r| {
        const k: Key = .{ .name = r.name, .version = r.version };
        const top = newest(published, k, r.subdir);
        var same: ?Record = null;
        var other: ?Record = null;
        for (published) |p| {
            if (!mem.eql(u8, p.subdir, r.subdir) or !mem.eql(u8, p.name, r.name) or !mem.eql(u8, p.version, r.version)) continue;
            if (mem.eql(u8, p.file, r.file)) same = p else if (p.build_number == r.build_number) other = p;
        }
        var status: []const u8 = "new";
        if (top != null and r.build_number < top.?) {
            status = "FAIL";
            try problems.append(a, try std.fmt.allocPrint(a, "{s} {s} {s}: build number _{d} is below the published _{d}", .{ r.subdir, r.name, r.version, r.build_number, top.? }));
        } else if (same) |p| {
            if (p.sha256.len > 0 and r.sha256.len > 0 and !mem.eql(u8, p.sha256, r.sha256)) {
                status = "skip";
                n_skip += 1;
            } else status = "published";
            n_published += 1;
        } else if (other) |p| {
            status = "FAIL";
            try problems.append(a, try std.fmt.allocPrint(a, "{s} {s} {s}: build number _{d} is published as {s}, this build is {s}: bump build.number", .{ r.subdir, r.name, r.version, r.build_number, p.file, r.file }));
        } else n_new += 1;
        try pad(a, out, r.subdir, sub_w + 2);
        try pad(a, out, r.name, name_w + 2);
        try pad(a, out, r.version, ver_w + 2);
        try pad(a, out, if (r.build.len > 0) r.build else "?", build_w + 2);
        try pad(a, out, if (top) |n| try std.fmt.allocPrint(a, "_{d}", .{n}) else "-", 11);
        try out.print(a, "{s}\n", .{status});
    }

    for (problems.items) |p| try out.print(a, "problem: {s}\n", .{p});
    if (problems.items.len == 0)
        try out.print(a, "published comparison OK: {d} new, {d} already published ({d} rebuilt with other content, kept as published by --skip-existing)\n", .{ n_new, n_published, n_skip })
    else
        try out.print(a, "published comparison FAILED: {d} problem(s) (a build number not below the published one, one build string per number; DESIGN R15)\n", .{problems.items.len});
    return problems.items.len;
}

const usage = "usage: zig-toolchain check-alignment [--expect <subdir>[,<subdir>...]] [--published <channel-url-or-dir>] <channel-or-subdir-dir>...\n";

pub fn run(io: Io, a: mem.Allocator, args: []const []const u8) u8 {
    var expect: std.ArrayList([]const u8) = .empty;
    var dirs: std.ArrayList([]const u8) = .empty;
    var published: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        var list: ?[]const u8 = null;
        if (mem.eql(u8, x, "--expect") or mem.eql(u8, x, "--published")) {
            if (i + 1 >= args.len) {
                std.debug.print("zig-toolchain check-alignment: {s} needs a value\n{s}", .{ x, usage });
                return 2;
            }
            i += 1;
            if (mem.eql(u8, x, "--expect")) list = args[i] else published = args[i];
        } else if (mem.startsWith(u8, x, "--expect=")) {
            list = x["--expect=".len..];
        } else if (mem.startsWith(u8, x, "--published=")) {
            published = x["--published=".len..];
        } else if (mem.startsWith(u8, x, "-")) {
            std.debug.print("zig-toolchain check-alignment: unknown option {s}\n{s}", .{ x, usage });
            return 2;
        } else dirs.append(a, x) catch return 1;
        if (list) |l| {
            var it = mem.tokenizeAny(u8, l, ", ");
            while (it.next()) |s| expect.append(a, s) catch return 1;
        }
    }
    if (dirs.items.len == 0 or (published != null and published.?.len == 0)) {
        std.debug.print("{s}", .{usage});
        return 2;
    }
    var records: std.ArrayList(Record) = .empty;
    var subdirs: std.ArrayList([]const u8) = .empty;
    for (dirs.items) |d| load(io, a, d, &records, &subdirs) catch return 1;
    // the published side: only the subdirs that have packages here
    var pub_records: std.ArrayList(Record) = .empty;
    if (published) |ch| {
        var with: std.ArrayList([]const u8) = .empty;
        for (records.items) |r| if (!contains(with.items, r.subdir)) with.append(a, r.subdir) catch return 1;
        mem.sort([]const u8, with.items, {}, lessStr);
        loadPublished(io, a, ch, with.items, &pub_records) catch return 1;
    }
    var out: std.ArrayList(u8) = .empty;
    var n = check(a, records.items, subdirs.items, expect.items, &out) catch return 1;
    if (published) |ch| n += compare(a, ch, records.items, pub_records.items, &out) catch return 1;
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

/// A repodata.json of one subdir with `entries`: file, name, version,
/// build number, sha256.
fn fixture(a: mem.Allocator, subdir: []const u8, entries: []const struct { []const u8, []const u8, []const u8, u64, []const u8 }) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.print(a, "{{\"info\":{{\"subdir\":\"{s}\"}},\"packages\":{{}},\"packages.conda\":{{", .{subdir});
    for (entries, 0..) |e, i| {
        if (i > 0) try text.append(a, ',');
        const build = e[0][e[1].len + e[2].len + 2 .. e[0].len - ".conda".len];
        try text.print(a, "\"{s}\":{{\"name\":\"{s}\",\"version\":\"{s}\",\"build\":\"{s}\",\"build_number\":{d},\"sha256\":\"{s}\"}}", .{ e[0], e[1], e[2], build, e[3], e[4] });
    }
    try text.appendSlice(a, "},\"repodata_version\":1,\"v3\":{}}");
    return text.items;
}

fn parsed(a: mem.Allocator, texts: []const []const u8) ![]const Record {
    var records: std.ArrayList(Record) = .empty;
    var files: std.ArrayList([]const u8) = .empty;
    for (texts) |t| _ = try parseRepodata(a, t, "fallback", &records, &files);
    return records.items;
}

fn runCompare(a: mem.Allocator, local: []const Record, published: []const Record) !struct { n: usize, text: []const u8 } {
    var out: std.ArrayList(u8) = .empty;
    const n = try compare(a, "https://prefix.dev/universe", local, published, &out);
    return .{ .n = n, .text = out.items };
}

test "compare: nothing published, every build is new" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const local = try parsed(a, &.{
        try fixture(a, "win-64", &.{.{ "zig-zlib-1.3.1-zig_29ef852_0.conda", "zig-zlib", "1.3.1", 0, "aa" }}),
        try fixture(a, "win-arm64", &.{.{ "zig-zlib-1.3.1-zig_6e0c9c0_0.conda", "zig-zlib", "1.3.1", 0, "bb" }}),
    });
    // an empty subdir, and a published subdir with other packages only
    const published = try parsed(a, &.{
        try fixture(a, "win-64", &.{.{ "r-zig-slim-4.6.0-h1_11.conda", "r-zig-slim", "4.6.0", 11, "cc" }}),
        try fixture(a, "win-arm64", &.{}),
    });
    const r = try runCompare(a, local, published);
    try testing.expectEqual(@as(usize, 0), r.n);
    try testing.expect(mem.indexOf(u8, r.text, "win-64     zig-zlib  1.3.1    zig_29ef852_0  -          new\n") != null);
    try testing.expect(mem.indexOf(u8, r.text, "published comparison OK: 2 new, 0 already published") != null);
    try testing.expectEqual(@as(usize, 0), (try runCompare(a, local, &.{})).n);
}

test "compare: the same file is already published; a rebuild is a skip, not a problem" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const local = try parsed(a, &.{try fixture(a, "win-64", &.{
        .{ "zig-zlib-1.3.1-zig_29ef852_0.conda", "zig-zlib", "1.3.1", 0, "aa" },
        .{ "zig-sqlite-3.51.2-zig_1d5992e_0.conda", "zig-sqlite", "3.51.2", 0, "new" },
    })});
    const published = try parsed(a, &.{try fixture(a, "win-64", &.{
        .{ "zig-zlib-1.3.1-zig_29ef852_0.conda", "zig-zlib", "1.3.1", 0, "aa" },
        .{ "zig-sqlite-3.51.2-zig_1d5992e_0.conda", "zig-sqlite", "3.51.2", 0, "old" },
    })});
    const r = try runCompare(a, local, published);
    try testing.expectEqual(@as(usize, 0), r.n);
    try testing.expect(mem.indexOf(u8, r.text, "zig_29ef852_0  _0         published\n") != null);
    try testing.expect(mem.indexOf(u8, r.text, "zig_1d5992e_0  _0         skip\n") != null);
    try testing.expect(mem.indexOf(u8, r.text, "published comparison OK: 0 new, 2 already published (1 rebuilt") != null);
}

test "compare: same build number, other build string; below the published number, even as the same file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const local = try parsed(a, &.{try fixture(a, "win-64", &.{
        .{ "zig-zlib-1.3.1-zig_29ef852_0.conda", "zig-zlib", "1.3.1", 0, "aa" },
        .{ "zig-expat-2.7.3-zig_7fcb7fd_1.conda", "zig-expat", "2.7.3", 1, "bb" },
        // an older local build is not compared, only the newest
        .{ "zig-geos-3.14.1-zig_573ba6a_0.conda", "zig-geos", "3.14.1", 0, "cc" },
        .{ "zig-geos-3.14.1-zig_573ba6a_1.conda", "zig-geos", "3.14.1", 1, "dd" },
        // published, but a newer number is published too
        .{ "zig-proj-9.7.1-zig_4f71b06_0.conda", "zig-proj", "9.7.1", 0, "hh" },
    })});
    const published = try parsed(a, &.{try fixture(a, "win-64", &.{
        .{ "zig-zlib-1.3.1-zig_0000000_0.conda", "zig-zlib", "1.3.1", 0, "ee" },
        .{ "zig-expat-2.7.3-zig_7fcb7fd_2.conda", "zig-expat", "2.7.3", 2, "ff" },
        .{ "zig-geos-3.14.1-zig_573ba6a_0.conda", "zig-geos", "3.14.1", 0, "cc" },
        // another version does not count
        .{ "zig-zlib-1.3.2-zig_1111111_5.conda", "zig-zlib", "1.3.2", 5, "gg" },
        .{ "zig-proj-9.7.1-zig_4f71b06_0.conda", "zig-proj", "9.7.1", 0, "hh" },
        .{ "zig-proj-9.7.1-zig_4f71b06_1.conda", "zig-proj", "9.7.1", 1, "ii" },
    })});
    const r = try runCompare(a, local, published);
    try testing.expectEqual(@as(usize, 3), r.n);
    try testing.expect(mem.indexOf(u8, r.text, "problem: win-64 zig-proj 9.7.1: build number _0 is below the published _1\n") != null);
    try testing.expect(mem.indexOf(u8, r.text, "problem: win-64 zig-zlib 1.3.1: build number _0 is published as zig-zlib-1.3.1-zig_0000000_0.conda, this build is zig-zlib-1.3.1-zig_29ef852_0.conda: bump build.number\n") != null);
    try testing.expect(mem.indexOf(u8, r.text, "problem: win-64 zig-expat 2.7.3: build number _1 is below the published _2\n") != null);
    try testing.expect(mem.indexOf(u8, r.text, "win-64  zig-geos   3.14.1   zig_573ba6a_1  _0         new\n") != null);
    try testing.expect(mem.indexOf(u8, r.text, "published comparison FAILED: 3 problem(s)") != null);
}

test "parseRepodata: build string, sha256 and the v3 section" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\{"info":{"subdir":"win-64"},"packages":{},"packages.conda":{},"v3":{"conda":{"blast-2.17.0-ha1ecfd9_206":
        \\{"build":"ha1ecfd9_206","build_number":206,"name":"blast","sha256":"2a","version":"2.17.0","flags":["toolchain:zig"]}}}}
    ;
    const records = try parsed(a, &.{text});
    try testing.expectEqual(@as(usize, 1), records.len);
    try testing.expectEqualStrings("blast-2.17.0-ha1ecfd9_206.conda", records[0].file);
    try testing.expectEqualStrings("ha1ecfd9_206", records[0].build);
    try testing.expectEqualStrings("2a", records[0].sha256);
    try testing.expectEqual(@as(u64, 206), records[0].build_number);
    try testing.expectError(error.BadRepodata, parsed(a, &.{"{\"v3\":[]}"}));
}

test "loadPublished: a channel directory; a missing subdir is empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = try std.fs.path.join(a, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    try tmp.dir.createDirPath(io, "ch/win-64");
    try tmp.dir.writeFile(io, .{ .sub_path = "ch/win-64/repodata.json", .data = try fixture(a, "win-64", &.{.{ "zig-zlib-1.3.1-zig_29ef852_0.conda", "zig-zlib", "1.3.1", 0, "aa" }}) });
    var records: std.ArrayList(Record) = .empty;
    // a trailing slash, as a URL may have
    try loadPublished(io, a, try std.fs.path.join(a, &.{ base, "ch/" }), &.{ "win-64", "win-arm64" }, &records);
    try testing.expectEqual(@as(usize, 1), records.items.len);
    try testing.expectEqualStrings("win-64", records.items[0].subdir);
    try testing.expectError(error.BadRepodata, loadPublished(io, a, try std.fs.path.join(a, &.{ base, "nochannel" }), &.{"win-64"}, &records));
}

test "run: usage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqual(@as(u8, 2), run(testing.io, a, &.{ "x", "--published" }));
    try testing.expectEqual(@as(u8, 2), run(testing.io, a, &.{ "--published=", "x" }));
    try testing.expectEqual(@as(u8, 2), run(testing.io, a, &.{"--bogus"}));
}
