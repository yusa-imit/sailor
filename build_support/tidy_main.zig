//! CLI entry point for the Tiger Style tidy checker. Walks `<src-dir>` plus the single
//! `<build-zig-path>` file, computes violation counts using `tidy.zig`'s pure functions, and
//! either writes a fresh `<baseline-path>` (`generate`) or fails when any actual count exceeds
//! its recorded baseline entry (`check`). This is a thin CLI shell, not a library: it allocates
//! from one arena for the whole process lifetime and exits via `std.process.exit`.

const std = @import("std");
const tidy = @import("tidy.zig");
const assert = std.debug.assert;

/// Files where `usize` struct fields are checked (serialization/wire formats); every other
/// file reports zero for the `usize_in_wire_format` check.
const wire_format_files = [_][]const u8{
    "src/state_persist.zig",
    "src/termcap.zig",
    "src/tui/sixel.zig",
    "src/tui/kitty.zig",
    "src/tui/iterm2.zig",
    "src/tui/image_renderer.zig",
    "src/tui/adaptive_renderer.zig",
};

const line_length_max: usize = 100;
const function_length_max: u32 = 70;
const file_bytes_max: usize = 8 * 1024 * 1024;
const files_max: u32 = 100_000;

const Mode = enum { check, generate };

/// One non-zero (file, check, name) actual count found by a sweep of the tree.
const Count = struct {
    file: []const u8,
    check: []const u8,
    name: []const u8,
    actual: u32,
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len != 5) {
        std.debug.print(
            "usage: tidy <check|generate> <src-dir> <build-zig-path> <baseline-path>\n",
            .{},
        );
        std.process.exit(2);
    }
    const mode = std.meta.stringToEnum(Mode, args[1]) orelse {
        std.debug.print("tidy: unknown mode '{s}' (want check|generate)\n", .{args[1]});
        std.process.exit(2);
    };

    const counts = try collectCounts(arena, args[2], args[3]);
    switch (mode) {
        .generate => try writeBaseline(arena, args[4], counts),
        .check => try runCheck(arena, args[4], counts),
    }
}

fn isWireFormatFile(path: []const u8) bool {
    for (wire_format_files) |known| {
        if (std.mem.eql(u8, path, known)) return true;
    }
    return false;
}

/// Appends one non-zero-count entry; zero counts are never interesting to either mode.
fn appendCount(
    gpa: std.mem.Allocator,
    counts: *std.ArrayList(Count),
    file: []const u8,
    check: []const u8,
    name: []const u8,
    actual: u32,
) !void {
    if (actual == 0) return;
    try counts.append(gpa, .{ .file = file, .check = check, .name = name, .actual = actual });
}

/// Computes every check's actual count for one file's text and appends the non-zero ones.
fn appendFileCounts(
    arena: std.mem.Allocator,
    counts: *std.ArrayList(Count),
    path: []const u8,
    is_build_script: bool,
) !void {
    assert(path.len > 0);
    const text = try std.fs.cwd().readFileAlloc(arena, path, file_bytes_max);
    assert(text.len <= file_bytes_max);

    try appendCount(arena, counts, path, "line_length", "-", tidy.countLongLines(text, line_length_max));
    if (!is_build_script) {
        const missing: u32 = if (tidy.hasModuleHeader(text)) 0 else 1;
        try appendCount(arena, counts, path, "missing_header", "-", missing);
    }
    try appendCount(
        arena,
        counts,
        path,
        "catch_unreachable",
        "-",
        tidy.countUnprovenCatchUnreachable(text),
    );
    try appendCount(
        arena,
        counts,
        path,
        "debug_print",
        "-",
        tidy.countLiveOccurrences(text, "std.debug.print"),
    );
    try appendCount(arena, counts, path, "time_usage", "-", tidy.countLiveOccurrences(text, "std.time."));
    try appendCount(arena, counts, path, "panic", "-", tidy.countUnprovenPanic(text));

    if (isWireFormatFile(path)) {
        try appendCount(arena, counts, path, "usize_in_wire_format", "-", tidy.countUsizeFields(text));
    }

    const spans = try tidy.findFunctions(arena, text);
    for (spans) |span| {
        if (span.line_count > function_length_max) {
            try appendCount(arena, counts, path, "function_length", span.name, span.line_count);
        }
    }
}

/// Joins `src_dir` and a walker-relative `sub_path` into a forward-slash repo-relative path,
/// stable across platforms so the baseline file diffs cleanly everywhere.
fn joinRelPath(arena: std.mem.Allocator, src_dir: []const u8, sub_path: []const u8) ![]const u8 {
    const joined = try std.fmt.allocPrint(arena, "{s}/{s}", .{ src_dir, sub_path });
    for (joined) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return joined;
}

/// Walks `src_dir` recursively for `.zig` files, plus the single `build_zig_path` file, and
/// returns every non-zero (file, check, name) count found.
fn collectCounts(
    arena: std.mem.Allocator,
    src_dir: []const u8,
    build_zig_path: []const u8,
) ![]Count {
    assert(src_dir.len > 0);
    assert(build_zig_path.len > 0);
    var counts: std.ArrayList(Count) = .empty;

    var dir = try std.fs.cwd().openDir(src_dir, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(arena);
    defer walker.deinit();

    var files_seen: u32 = 0;
    while (try walker.next()) |entry| {
        assert(files_seen < files_max);
        files_seen += 1;
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const rel_path = try joinRelPath(arena, src_dir, entry.path);
        try appendFileCounts(arena, &counts, rel_path, false);
    }

    try appendFileCounts(arena, &counts, build_zig_path, true);
    assert(counts.items.len <= files_seen * 8 + 8); // Bounded: ~8 checks per file at most.
    return counts.toOwnedSlice(arena);
}

fn lessThanCount(_: void, a: Count, b: Count) bool {
    if (!std.mem.eql(u8, a.file, b.file)) return std.mem.lessThan(u8, a.file, b.file);
    if (!std.mem.eql(u8, a.check, b.check)) return std.mem.lessThan(u8, a.check, b.check);
    return std.mem.lessThan(u8, a.name, b.name);
}

const baseline_header =
    "# Tiger Style tidy baseline — see docs/plans/001-*.md item 2. Only\n" ++
    "# shrinks: a listed function/file that grows past its recorded count fails tidy.\n";

/// Writes `baseline_path` as sorted, pipe-delimited `file|check|name|count` lines, one per
/// non-zero actual count, so re-generation from an unchanged tree is byte-for-byte stable.
fn writeBaseline(arena: std.mem.Allocator, baseline_path: []const u8, counts: []const Count) !void {
    assert(baseline_path.len > 0);
    const sorted = try arena.dupe(Count, counts);
    std.mem.sort(Count, sorted, {}, lessThanCount);

    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(arena, baseline_header);
    for (sorted) |c| {
        try buf.print(arena, "{s}|{s}|{s}|{d}\n", .{ c.file, c.check, c.name, c.actual });
    }
    assert(buf.items.len >= baseline_header.len);

    var file = try std.fs.cwd().createFile(baseline_path, .{});
    defer file.close();

    try file.writeAll(buf.items);
}

/// Parses `baseline_path`, compares every actual count against it, and prints one line per
/// violation to stderr; exits 1 if any violation was found, 0 otherwise.
fn runCheck(arena: std.mem.Allocator, baseline_path: []const u8, counts: []const Count) !void {
    assert(baseline_path.len > 0);
    const text = try std.fs.cwd().readFileAlloc(arena, baseline_path, file_bytes_max);
    const entries = try tidy.parseBaseline(arena, text);

    var violations: u32 = 0;
    for (counts) |c| {
        const baseline = tidy.baselineCount(entries, c.file, c.check, c.name);
        if (c.actual > baseline) {
            std.debug.print(
                "{s}:{s}:{s}: {d} > baseline {d}\n",
                .{ c.file, c.check, c.name, c.actual, baseline },
            );
            violations += 1;
        }
    }

    if (violations > 0) {
        std.debug.print("tidy: {d} violation(s)\n", .{violations});
        std.process.exit(1);
    }
    std.debug.print("tidy: clean ({d} tracked entries)\n", .{counts.len});
    std.process.exit(0);
}
