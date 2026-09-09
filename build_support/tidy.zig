//! Tiger Style tidy checker: line length, function length (with a shrinking baseline ratchet),
//! module header presence, and banned patterns (catch unreachable without proof, unproven
//! @panic, debug prints, std.time usage, std.crypto.random usage, usize in serialization-format
//! structs) over sailor's src/ and build.zig.

const std = @import("std");
const assert = std.debug.assert;

pub const Violation = struct {
    file: []const u8,
    check: []const u8, // e.g. "line_length", "function_length", "missing_header",
    // "catch_unreachable", "panic", "debug_print", "time_usage", "crypto_random",
    // "usize_in_wire_format"
    name: []const u8, // function name for function_length; "-" for file-level checks
    actual: u32,
    baseline: u32,
};

/// Counts lines whose length (in bytes) exceeds `max`.
pub fn countLongLines(text: []const u8, max: usize) u32 {
    assert(max > 0);
    var violations: u32 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var lines_seen_max: u32 = 0;
    while (lines.next()) |raw_line| {
        assert(lines_seen_max < std.math.maxInt(u32));
        lines_seen_max += 1;
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (line.len > max) violations += 1;
    }
    assert(violations <= lines_seen_max);
    return violations;
}

/// True if the first non-blank line of `text` starts with "//!".
pub fn hasModuleHeader(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var lines_seen_max: u32 = 0;
    while (lines.next()) |line| {
        assert(lines_seen_max < std.math.maxInt(u32));
        lines_seen_max += 1;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        const found = std.mem.startsWith(u8, trimmed, "//!");
        // Positive space: a genuine "//!" header always starts with "//".
        if (found) assert(std.mem.startsWith(u8, trimmed, "//"));
        return found;
    }
    // Negative space: an all-blank (or empty) text has no header.
    assert(std.mem.trim(u8, text, " \t\r\n").len == 0);
    return false;
}

/// Counts lines containing "catch unreachable" that do NOT also contain a `//` comment
/// on the same line (a bare, unproven catch-unreachable).
pub fn countUnprovenCatchUnreachable(text: []const u8) u32 {
    const needle = "catch unreachable";
    var violations: u32 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var lines_seen_max: u32 = 0;
    while (lines.next()) |line| {
        assert(lines_seen_max < std.math.maxInt(u32));
        lines_seen_max += 1;
        if (std.mem.indexOf(u8, line, needle) == null) continue;
        if (std.mem.indexOf(u8, line, "//") != null) continue;
        violations += 1;
    }
    assert(violations <= lines_seen_max);
    return violations;
}

/// Counts lines containing "@panic(" that do NOT also contain a `//` comment on the same
/// line (a bare, unproven panic). Mirrors `countUnprovenCatchUnreachable`: panicking on
/// programmer error (an assertion helper, a test-only leak guard) is legitimate and only
/// needs a proof comment; panicking on user data is not, and this check has no exemption
/// for that case beyond requiring the comment to exist.
pub fn countUnprovenPanic(text: []const u8) u32 {
    const needle = "@panic(";
    var violations: u32 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var lines_seen_max: u32 = 0;
    while (lines.next()) |line| {
        assert(lines_seen_max < std.math.maxInt(u32));
        lines_seen_max += 1;
        if (std.mem.indexOf(u8, line, needle) == null) continue;
        if (std.mem.indexOf(u8, line, "//") != null) continue;
        violations += 1;
    }
    assert(violations <= lines_seen_max);
    return violations;
}

/// Counts lines containing `needle` where the trimmed line does not start with "//"
/// (i.e. real usage, not a comment mentioning it).
pub fn countLiveOccurrences(text: []const u8, needle: []const u8) u32 {
    assert(needle.len > 0);
    var live: u32 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var lines_seen_max: u32 = 0;
    while (lines.next()) |line| {
        assert(lines_seen_max < std.math.maxInt(u32));
        lines_seen_max += 1;
        if (std.mem.indexOf(u8, line, needle) == null) continue;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        live += 1;
    }
    assert(live <= lines_seen_max);
    return live;
}

/// Counts struct-field declarations of the exact form `usize` type (patterns like
/// ": usize,", ": usize;", ": usize\n" at end of line) anywhere in `text`. Used only
/// against known serialization/wire-format files.
pub fn countUsizeFields(text: []const u8) u32 {
    const needle = ": usize";
    var violations: u32 = 0;
    var search_start: usize = 0;
    var iterations_max: u32 = 0;
    while (std.mem.indexOfPos(u8, text, search_start, needle)) |pos| {
        assert(iterations_max < std.math.maxInt(u32));
        iterations_max += 1;
        const after = pos + needle.len;
        const next: u8 = if (after < text.len) text[after] else '\n';
        if (next == ',' or next == ';' or next == '\n' or next == ' ') violations += 1;
        search_start = after;
    }
    assert(search_start <= text.len);
    return violations;
}

pub const FunctionSpan = struct {
    name: []const u8,
    line_count: u32,
};

const lines_per_file_max: u32 = 200_000;
const functions_per_file_max: u32 = 20_000;

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// True if `trimmed` (already whitespace-trimmed) looks like the start of a function
/// definition: it mentions "fn " and its brace opens on this same line.
fn isFunctionStartLine(trimmed: []const u8) bool {
    return std.mem.indexOf(u8, trimmed, "fn ") != null and
        std.mem.endsWith(u8, trimmed, "{");
}

/// Extracts the identifier immediately following the first "fn " in `trimmed`.
fn extractFunctionName(trimmed: []const u8) ?[]const u8 {
    const marker = "fn ";
    const marker_pos = std.mem.indexOf(u8, trimmed, marker) orelse return null;
    const start = marker_pos + marker.len;
    var end = start;
    while (end < trimmed.len and isIdentChar(trimmed[end])) : (end += 1) {}
    if (end == start) return null;
    return trimmed[start..end];
}

/// Net brace delta (opens minus closes) of a single line.
fn braceDelta(line: []const u8) i32 {
    var delta: i32 = 0;
    for (line) |c| {
        if (c == '{') delta += 1;
        if (c == '}') delta -= 1;
    }
    return delta;
}

/// Heuristically finds top-level and nested `fn` definitions in `text` (lines containing
/// "fn " that end with "{" after trimming, brace-matched to their closing "}"), returning
/// each one's name and line count (inclusive of both braces).
pub fn findFunctions(gpa: std.mem.Allocator, text: []const u8) ![]FunctionSpan {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);

    var line_iter = std.mem.splitScalar(u8, text, '\n');
    while (line_iter.next()) |line| {
        assert(lines.items.len < lines_per_file_max);
        try lines.append(gpa, line);
    }

    var spans: std.ArrayList(FunctionSpan) = .empty;
    errdefer spans.deinit(gpa);

    var i: usize = 0;
    while (i < lines.items.len) : (i += 1) {
        assert(spans.items.len < functions_per_file_max);
        const trimmed = std.mem.trim(u8, lines.items[i], " \t\r");
        if (!isFunctionStartLine(trimmed)) continue;
        const name = extractFunctionName(trimmed) orelse continue;

        var depth: i32 = braceDelta(lines.items[i]);
        var j = i;
        while (depth > 0 and j + 1 < lines.items.len) {
            j += 1;
            depth += braceDelta(lines.items[j]);
        }
        const line_count: u32 = @intCast(j - i + 1);
        try spans.append(gpa, .{ .name = name, .line_count = line_count });
    }
    assert(spans.items.len <= lines.items.len);
    return spans.toOwnedSlice(gpa);
}

pub const BaselineEntry = struct {
    file: []const u8,
    check: []const u8,
    name: []const u8,
    count: u32,
};

const baseline_entries_max: u32 = 200_000;

/// Parses the pipe-delimited baseline file format `path|check|name|count`, one entry per
/// non-empty, non-comment (`#`-prefixed) line.
pub fn parseBaseline(gpa: std.mem.Allocator, text: []const u8) ![]BaselineEntry {
    var entries: std.ArrayList(BaselineEntry) = .empty;
    errdefer entries.deinit(gpa);

    var lines = std.mem.splitScalar(u8, text, '\n');
    var lines_seen_max: u32 = 0;
    while (lines.next()) |raw_line| {
        assert(lines_seen_max < lines_per_file_max);
        lines_seen_max += 1;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        var fields = std.mem.splitScalar(u8, line, '|');
        const file = fields.next() orelse continue;
        const check = fields.next() orelse continue;
        const name = fields.next() orelse continue;
        const count_str = fields.next() orelse continue;
        const count = try std.fmt.parseInt(u32, count_str, 10);

        assert(entries.items.len < baseline_entries_max);
        try entries.append(gpa, .{ .file = file, .check = check, .name = name, .count = count });
    }
    assert(entries.items.len <= lines_seen_max);
    return entries.toOwnedSlice(gpa);
}

/// Looks up the recorded baseline count for (file, check, name); returns 0 if absent.
pub fn baselineCount(
    entries: []const BaselineEntry,
    file: []const u8,
    check: []const u8,
    name: []const u8,
) u32 {
    assert(file.len > 0);
    assert(check.len > 0);
    var entries_scanned_max: u32 = 0;
    for (entries) |entry| {
        assert(entries_scanned_max < baseline_entries_max);
        entries_scanned_max += 1;
        const file_matches = std.mem.eql(u8, entry.file, file);
        const check_matches = std.mem.eql(u8, entry.check, check);
        const name_matches = std.mem.eql(u8, entry.name, name);
        if (file_matches and check_matches and name_matches) return entry.count;
    }
    assert(entries_scanned_max == entries.len);
    return 0;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "countLongLines: text with no long lines reports zero violations" {
    const text = "short\nalso short\nfine\n";
    try testing.expectEqual(@as(u32, 0), countLongLines(text, 100));
}

test "countLongLines: single 101-char line over max=100 is one violation" {
    const long_line = "a" ** 101;
    const text = try std.fmt.allocPrint(testing.allocator, "short\n{s}\nshort\n", .{long_line});
    defer testing.allocator.free(text);
    try testing.expectEqual(@as(u32, 1), countLongLines(text, 100));
}

test "countLongLines: a line of exactly 100 chars is not a violation (boundary)" {
    const exact_line = "a" ** 100;
    const text = try std.fmt.allocPrint(testing.allocator, "{s}\n", .{exact_line});
    defer testing.allocator.free(text);
    try testing.expectEqual(@as(u32, 0), countLongLines(text, 100));
}

test "countLongLines: a CRLF-terminated line of exactly 100 chars is not a violation" {
    const exact_line = "a" ** 100;
    const text = try std.fmt.allocPrint(testing.allocator, "{s}\r\n", .{exact_line});
    defer testing.allocator.free(text);
    try testing.expectEqual(@as(u32, 0), countLongLines(text, 100));
}

test "countLongLines: empty text has zero violations" {
    try testing.expectEqual(@as(u32, 0), countLongLines("", 100));
}

test "hasModuleHeader: text starting with //! doc comment is true" {
    try testing.expect(hasModuleHeader("//! foo\nconst std = @import(\"std\");\n"));
}

test "hasModuleHeader: blank lines then //! doc comment is still true" {
    try testing.expect(hasModuleHeader("\n\n//! foo\nconst std = @import(\"std\");\n"));
}

test "hasModuleHeader: file starting with code and no header is false" {
    try testing.expect(!hasModuleHeader("const std = @import(\"std\");\n"));
}

test "hasModuleHeader: file starting with a regular // comment (not //!) is false" {
    try testing.expect(!hasModuleHeader("// not a module doc\nconst std = @import(\"std\");\n"));
}

test "countUnprovenCatchUnreachable: bare catch unreachable with no comment is one violation" {
    const text = "foo() catch unreachable;\n";
    try testing.expectEqual(@as(u32, 1), countUnprovenCatchUnreachable(text));
}

test "countUnprovenCatchUnreachable: catch unreachable with proof comment is not flagged" {
    const text = "foo() catch unreachable; // proven because X\n";
    try testing.expectEqual(@as(u32, 0), countUnprovenCatchUnreachable(text));
}

test "countUnprovenCatchUnreachable: text with no occurrences is zero" {
    const text = "const x = try foo();\n";
    try testing.expectEqual(@as(u32, 0), countUnprovenCatchUnreachable(text));
}

test "countUnprovenCatchUnreachable: two bare occurrences on separate lines count both" {
    const text =
        \\a() catch unreachable;
        \\b() catch unreachable;
        \\
    ;
    try testing.expectEqual(@as(u32, 2), countUnprovenCatchUnreachable(text));
}

test "countUnprovenPanic: bare @panic with no comment is one violation" {
    const text = "@panic(\"boom\");\n";
    try testing.expectEqual(@as(u32, 1), countUnprovenPanic(text));
}

test "countUnprovenPanic: @panic with proof comment is not flagged" {
    const text = "@panic(\"boom\"); // programmer error, not user data\n";
    try testing.expectEqual(@as(u32, 0), countUnprovenPanic(text));
}

test "countUnprovenPanic: text with no occurrences is zero" {
    const text = "const x = try foo();\n";
    try testing.expectEqual(@as(u32, 0), countUnprovenPanic(text));
}

test "countUnprovenPanic: two bare occurrences on separate lines count both" {
    const text =
        \\if (a) @panic("a");
        \\if (b) @panic("b");
        \\
    ;
    try testing.expectEqual(@as(u32, 2), countUnprovenPanic(text));
}

test "countLiveOccurrences: real std.debug.print call is one live occurrence" {
    const text = "std.debug.print(\"hi\\n\", .{});\n";
    try testing.expectEqual(@as(u32, 1), countLiveOccurrences(text, "std.debug.print"));
}

test "countLiveOccurrences: needle only inside a // comment is not live" {
    const text = "// std.debug.print(\"hi\\n\", .{});\n";
    try testing.expectEqual(@as(u32, 0), countLiveOccurrences(text, "std.debug.print"));
}

test "countLiveOccurrences: one real call plus one commented-out call counts only the real one" {
    const text =
        \\std.debug.print("real\n", .{});
        \\// std.debug.print("dead code\n", .{});
        \\
    ;
    try testing.expectEqual(@as(u32, 1), countLiveOccurrences(text, "std.debug.print"));
}

test "countLiveOccurrences: std.time.* usage detection follows the same live/comment rule" {
    const text =
        \\const now = std.time.milliTimestamp();
        \\// const later = std.time.milliTimestamp();
        \\
    ;
    try testing.expectEqual(@as(u32, 1), countLiveOccurrences(text, "std.time."));
}

test "countLiveOccurrences: std.crypto.random usage detection follows the same live/comment rule" {
    const text =
        \\const jitter = std.crypto.random.uintAtMost(u64, 100);
        \\// const jitter = std.crypto.random.uintAtMost(u64, 100);
        \\
    ;
    try testing.expectEqual(@as(u32, 1), countLiveOccurrences(text, "std.crypto.random"));
}

test "countUsizeFields: trailing-comma usize field is one violation" {
    const text = "pub const Header = struct {\n    offset: usize,\n};\n";
    try testing.expectEqual(@as(u32, 1), countUsizeFields(text));
}

test "countUsizeFields: trailing-semicolon usize field is one violation" {
    const text = "var count: usize;\n";
    try testing.expectEqual(@as(u32, 1), countUsizeFields(text));
}

test "countUsizeFields: usize field at end of line with nothing after is one violation" {
    const text = "pub const Header = struct {\n    len: usize\n};\n";
    try testing.expectEqual(@as(u32, 1), countUsizeFields(text));
}

test "countUsizeFields: a u32 field is not counted" {
    const text = "pub const Header = struct {\n    offset: u32,\n};\n";
    try testing.expectEqual(@as(u32, 0), countUsizeFields(text));
}

test "countUsizeFields: two usize fields count both" {
    const text = "pub const Header = struct {\n    offset: usize,\n    len: usize,\n};\n";
    try testing.expectEqual(@as(u32, 2), countUsizeFields(text));
}

test "findFunctions: single 5-line function is found with correct name and line count" {
    const text =
        \\fn foo() void {
        \\    const x = 1;
        \\    const y = 2;
        \\    _ = x + y;
        \\}
    ;
    const spans = try findFunctions(testing.allocator, text);
    defer testing.allocator.free(spans);
    try testing.expectEqual(@as(usize, 1), spans.len);
    try testing.expectEqualStrings("foo", spans[0].name);
    try testing.expectEqual(@as(u32, 5), spans[0].line_count);
}

test "findFunctions: two functions in one file are returned in order with correct lengths" {
    const text =
        \\fn foo() void {
        \\    return;
        \\}
        \\
        \\fn bar() u32 {
        \\    const x = 1;
        \\    const y = 2;
        \\    return x + y;
        \\}
    ;
    const spans = try findFunctions(testing.allocator, text);
    defer testing.allocator.free(spans);
    try testing.expectEqual(@as(usize, 2), spans.len);
    try testing.expectEqualStrings("foo", spans[0].name);
    try testing.expectEqual(@as(u32, 3), spans[0].line_count);
    try testing.expectEqualStrings("bar", spans[1].name);
    try testing.expectEqual(@as(u32, 5), spans[1].line_count);
}

test "findFunctions: nested braces do not truncate the outer function at the first close" {
    const text =
        \\fn outer() void {
        \\    if (true) {
        \\        for (0..3) |i| {
        \\            _ = i;
        \\        }
        \\    }
        \\    const done = true;
        \\    _ = done;
        \\}
    ;
    const spans = try findFunctions(testing.allocator, text);
    defer testing.allocator.free(spans);
    try testing.expectEqual(@as(usize, 1), spans.len);
    try testing.expectEqualStrings("outer", spans[0].name);
    // Full span from "fn outer" line to the final closing brace, not the first
    // closing brace belonging to the nested `for` block.
    try testing.expectEqual(@as(u32, 9), spans[0].line_count);
}

test "parseBaseline: parses a single pipe-delimited entry into exact fields" {
    const text = "src/repl.zig|function_length|handleKey|275\n";
    const entries = try parseBaseline(testing.allocator, text);
    defer testing.allocator.free(entries);
    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expectEqualStrings("src/repl.zig", entries[0].file);
    try testing.expectEqualStrings("function_length", entries[0].check);
    try testing.expectEqualStrings("handleKey", entries[0].name);
    try testing.expectEqual(@as(u32, 275), entries[0].count);
}

test "parseBaseline: comment lines and blank lines are skipped" {
    const text =
        \\# this is a comment
        \\src/a.zig|function_length|foo|71
        \\
        \\# another comment
        \\src/b.zig|function_length|bar|72
        \\
    ;
    const entries = try parseBaseline(testing.allocator, text);
    defer testing.allocator.free(entries);
    try testing.expectEqual(@as(usize, 2), entries.len);
    try testing.expectEqualStrings("src/a.zig", entries[0].file);
    try testing.expectEqualStrings("src/b.zig", entries[1].file);
}

test "baselineCount: returns the parsed count for a matching (file, check, name) triple" {
    const text = "src/repl.zig|function_length|handleKey|275\n";
    const entries = try parseBaseline(testing.allocator, text);
    defer testing.allocator.free(entries);
    const count = baselineCount(entries, "src/repl.zig", "function_length", "handleKey");
    try testing.expectEqual(@as(u32, 275), count);
}

test "baselineCount: returns zero for a non-matching triple" {
    const text = "src/repl.zig|function_length|handleKey|275\n";
    const entries = try parseBaseline(testing.allocator, text);
    defer testing.allocator.free(entries);
    const count = baselineCount(entries, "src/other.zig", "function_length", "handleKey");
    try testing.expectEqual(@as(u32, 0), count);
}

test "baselineCount: distinguishes by check and name, not just file" {
    const text =
        \\src/repl.zig|function_length|handleKey|275
        \\src/repl.zig|function_length|render|60
        \\
    ;
    const entries = try parseBaseline(testing.allocator, text);
    defer testing.allocator.free(entries);
    try testing.expectEqual(
        @as(u32, 60),
        baselineCount(entries, "src/repl.zig", "function_length", "render"),
    );
    try testing.expectEqual(
        @as(u32, 0),
        baselineCount(entries, "src/repl.zig", "catch_unreachable", "render"),
    );
}

test "ratchet contract: actual over baseline is flagged as grown, actual under is not" {
    const text = "src/repl.zig|function_length|handleKey|70\n";
    const entries = try parseBaseline(testing.allocator, text);
    defer testing.allocator.free(entries);
    const baseline = baselineCount(entries, "src/repl.zig", "function_length", "handleKey");

    const grown_actual: u32 = 75;
    const shrunk_actual: u32 = 65;

    // A function that grew past its recorded baseline must be flagged...
    try testing.expect(grown_actual > baseline);
    // ...but one that shrank below its recorded baseline must not be.
    try testing.expect(!(shrunk_actual > baseline));
}
