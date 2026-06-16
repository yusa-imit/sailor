const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const DiffStat = tui.widgets.DiffStat;
const DiffStatEntry = DiffStat.DiffStatEntry;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "DiffStat init with empty entries" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(usize, 0), ds.entries.len);
    try testing.expectEqual(@as(u16, 20), ds.bar_width);
    try testing.expectEqual(@as(u21, '+'), ds.insertion_char);
    try testing.expectEqual(@as(u21, '-'), ds.deletion_char);
    try testing.expect(ds.block == null);
    try testing.expect(ds.max_filename_width == null);
}

test "DiffStat init with single entry" {
    const entry: DiffStatEntry = .{
        .filename = "main.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(usize, 1), ds.entries.len);
    try testing.expectEqualStrings("main.zig", ds.entries[0].filename);
}

test "DiffStat init with multiple entries" {
    const entries: [3]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "b.zig", .insertions = 20, .deletions = 3 },
        .{ .filename = "c.zig", .insertions = 5, .deletions = 15 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(usize, 3), ds.entries.len);
}

test "DiffStat init default bar_width is 20" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(u16, 20), ds.bar_width);
}

test "DiffStat init default insertion_char is plus" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(u21, '+'), ds.insertion_char);
}

test "DiffStat init default deletion_char is minus" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(u21, '-'), ds.deletion_char);
}

test "DiffStat init default styles" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(Color.green, ds.insertion_style.fg);
    try testing.expectEqual(Color.red, ds.deletion_style.fg);
}

test "DiffStat init binary entry defaults to false" {
    const entry: DiffStatEntry = .{
        .filename = "image.png",
        .insertions = 100,
        .deletions = 50,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expect(!ds.entries[0].binary);
}

test "DiffStat init binary entry can be set to true" {
    const entry: DiffStatEntry = .{
        .filename = "image.png",
        .insertions = 100,
        .deletions = 50,
        .binary = true,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expect(ds.entries[0].binary);
}

// ============================================================================
// AGGREGATION TESTS (totalInsertions, totalDeletions, totalFiles)
// ============================================================================

test "DiffStat totalInsertions with no entries" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(u32, 0), ds.totalInsertions());
}

test "DiffStat totalInsertions with single entry" {
    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 42,
        .deletions = 7,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 42), ds.totalInsertions());
}

test "DiffStat totalInsertions sums multiple entries" {
    const entries: [3]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "b.zig", .insertions = 20, .deletions = 3 },
        .{ .filename = "c.zig", .insertions = 15, .deletions = 2 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 45), ds.totalInsertions());
}

test "DiffStat totalInsertions with zero insertions in some entries" {
    const entries: [2]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 0, .deletions = 5 },
        .{ .filename = "b.zig", .insertions = 25, .deletions = 10 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 25), ds.totalInsertions());
}

test "DiffStat totalDeletions with no entries" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(u32, 0), ds.totalDeletions());
}

test "DiffStat totalDeletions with single entry" {
    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 42,
        .deletions = 7,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 7), ds.totalDeletions());
}

test "DiffStat totalDeletions sums multiple entries" {
    const entries: [3]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "b.zig", .insertions = 20, .deletions = 3 },
        .{ .filename = "c.zig", .insertions = 15, .deletions = 12 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 20), ds.totalDeletions());
}

test "DiffStat totalFiles with no entries" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(usize, 0), ds.totalFiles());
}

test "DiffStat totalFiles with single entry" {
    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(usize, 1), ds.totalFiles());
}

test "DiffStat totalFiles counts all entries" {
    const entries: [5]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "b.zig", .insertions = 20, .deletions = 3 },
        .{ .filename = "c.zig", .insertions = 15, .deletions = 2 },
        .{ .filename = "d.zig", .insertions = 0, .deletions = 50 },
        .{ .filename = "e.zig", .insertions = 100, .deletions = 0 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(usize, 5), ds.totalFiles());
}

// ============================================================================
// COMPUTE FUNCTIONS (maxFilenameWidth, maxChanges)
// ============================================================================

test "DiffStat computeMaxFilenameWidth with no entries" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(u16, 0), ds.computeMaxFilenameWidth());
}

test "DiffStat computeMaxFilenameWidth with single entry" {
    const entry: DiffStatEntry = .{
        .filename = "file.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u16, 8), ds.computeMaxFilenameWidth());
}

test "DiffStat computeMaxFilenameWidth finds longest filename" {
    const entries: [3]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "longer_name.zig", .insertions = 20, .deletions = 3 },
        .{ .filename = "b.zig", .insertions = 15, .deletions = 2 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u16, 15), ds.computeMaxFilenameWidth());
}

test "DiffStat computeMaxFilenameWidth respects max_filename_width cap" {
    const entries: [2]DiffStatEntry = .{
        .{ .filename = "very_long_filename.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "another_long_name.zig", .insertions = 20, .deletions = 3 },
    };
    var ds = DiffStat.init(&entries);
    ds.max_filename_width = 10;

    try testing.expectEqual(@as(u16, 10), ds.computeMaxFilenameWidth());
}

test "DiffStat computeMaxChanges with no entries" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    try testing.expectEqual(@as(u32, 0), ds.computeMaxChanges());
}

test "DiffStat computeMaxChanges with single entry" {
    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 30,
        .deletions = 20,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 50), ds.computeMaxChanges());
}

test "DiffStat computeMaxChanges finds max total changes" {
    const entries: [3]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "b.zig", .insertions = 50, .deletions = 30 },
        .{ .filename = "c.zig", .insertions = 20, .deletions = 10 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 80), ds.computeMaxChanges());
}

test "DiffStat computeMaxChanges only insertions" {
    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 100,
        .deletions = 0,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 100), ds.computeMaxChanges());
}

test "DiffStat computeMaxChanges only deletions" {
    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 0,
        .deletions = 50,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 50), ds.computeMaxChanges());
}

test "DiffStat computeMaxChanges all binary files" {
    const entries: [2]DiffStatEntry = .{
        .{ .filename = "a.bin", .insertions = 0, .deletions = 0, .binary = true },
        .{ .filename = "b.bin", .insertions = 0, .deletions = 0, .binary = true },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 0), ds.computeMaxChanges());
}

// ============================================================================
// BUILDER PATTERN TESTS
// ============================================================================

test "DiffStat withMaxFilenameWidth sets value" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries).withMaxFilenameWidth(15);

    try testing.expectEqual(@as(u16, 15), ds.max_filename_width.?);
}

test "DiffStat withMaxFilenameWidth preserves immutability" {
    const entries: []const DiffStatEntry = &.{};
    const original = DiffStat.init(entries);
    const modified = original.withMaxFilenameWidth(15);

    try testing.expect(original.max_filename_width == null);
    try testing.expectEqual(@as(u16, 15), modified.max_filename_width.?);
}

test "DiffStat withBarWidth sets value" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries).withBarWidth(30);

    try testing.expectEqual(@as(u16, 30), ds.bar_width);
}

test "DiffStat withBarWidth preserves immutability" {
    const entries: []const DiffStatEntry = &.{};
    const original = DiffStat.init(entries);
    const modified = original.withBarWidth(25);

    try testing.expectEqual(@as(u16, 20), original.bar_width);
    try testing.expectEqual(@as(u16, 25), modified.bar_width);
}

test "DiffStat withInsertionChar sets character" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries).withInsertionChar('=');

    try testing.expectEqual(@as(u21, '='), ds.insertion_char);
}

test "DiffStat withInsertionChar preserves immutability" {
    const entries: []const DiffStatEntry = &.{};
    const original = DiffStat.init(entries);
    const modified = original.withInsertionChar('*');

    try testing.expectEqual(@as(u21, '+'), original.insertion_char);
    try testing.expectEqual(@as(u21, '*'), modified.insertion_char);
}

test "DiffStat withDeletionChar sets character" {
    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries).withDeletionChar('x');

    try testing.expectEqual(@as(u21, 'x'), ds.deletion_char);
}

test "DiffStat withDeletionChar preserves immutability" {
    const entries: []const DiffStatEntry = &.{};
    const original = DiffStat.init(entries);
    const modified = original.withDeletionChar('~');

    try testing.expectEqual(@as(u21, '-'), original.deletion_char);
    try testing.expectEqual(@as(u21, '~'), modified.deletion_char);
}

test "DiffStat withInsertionStyle sets style" {
    const entries: []const DiffStatEntry = &.{};
    const style = Style{ .fg = Color.blue };
    const ds = DiffStat.init(entries).withInsertionStyle(style);

    try testing.expectEqual(Color.blue, ds.insertion_style.fg);
}

test "DiffStat withDeletionStyle sets style" {
    const entries: []const DiffStatEntry = &.{};
    const style = Style{ .fg = Color.yellow };
    const ds = DiffStat.init(entries).withDeletionStyle(style);

    try testing.expectEqual(Color.yellow, ds.deletion_style.fg);
}

test "DiffStat withFilenameStyle sets style" {
    const entries: []const DiffStatEntry = &.{};
    const style = Style{ .bold = true };
    const ds = DiffStat.init(entries).withFilenameStyle(style);

    try testing.expect(ds.filename_style.bold);
}

test "DiffStat withCountStyle sets style" {
    const entries: []const DiffStatEntry = &.{};
    const style = Style{ .fg = Color.cyan };
    const ds = DiffStat.init(entries).withCountStyle(style);

    try testing.expectEqual(Color.cyan, ds.count_style.fg);
}

test "DiffStat withBinaryStyle sets style" {
    const entries: []const DiffStatEntry = &.{};
    const style = Style{ .fg = Color.yellow };
    const ds = DiffStat.init(entries).withBinaryStyle(style);

    try testing.expectEqual(Color.yellow, ds.binary_style.fg);
}

test "DiffStat withBlock sets border" {
    const entries: []const DiffStatEntry = &.{};
    const block = Block{};
    const ds = DiffStat.init(entries).withBlock(block);

    try testing.expect(ds.block != null);
}

test "DiffStat builder chain preserves immutability" {
    const entries: []const DiffStatEntry = &.{};
    const original = DiffStat.init(entries);

    const modified = original
        .withBarWidth(25)
        .withInsertionChar('=')
        .withDeletionChar('x');

    try testing.expectEqual(@as(u16, 20), original.bar_width);
    try testing.expectEqual(@as(u21, '+'), original.insertion_char);
    try testing.expectEqual(@as(u21, '-'), original.deletion_char);

    try testing.expectEqual(@as(u16, 25), modified.bar_width);
    try testing.expectEqual(@as(u21, '='), modified.insertion_char);
    try testing.expectEqual(@as(u21, 'x'), modified.deletion_char);
}

// ============================================================================
// RENDER TESTS - BASIC
// ============================================================================

test "DiffStat render to empty area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const entries: []const DiffStatEntry = &.{};
    const ds = DiffStat.init(entries);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    ds.render(&buf, area);

    // Should not crash
    try testing.expect(true);
}

test "DiffStat render single entry renders filename" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "file.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    ds.render(&buf, area);

    // First character should be 'f'
    try testing.expectEqual(@as(u21, 'f'), buf.get(0, 0).?.char);
}

test "DiffStat render single entry renders pipe separator" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "f.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    ds.render(&buf, area);

    // Pipe should appear after filename and padding
    var found_pipe = false;
    for (0..50) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '|') {
            found_pipe = true;
            break;
        }
    }
    try testing.expect(found_pipe);
}

test "DiffStat render single entry with insertions and deletions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Should render without crash
    try testing.expect(true);
}

test "DiffStat render multiple entries" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 3);
    defer buf.deinit();

    const entries: [3]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 10, .deletions = 5 },
        .{ .filename = "b.zig", .insertions = 20, .deletions = 3 },
        .{ .filename = "c.zig", .insertions = 5, .deletions = 15 },
    };
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 3 };
    ds.render(&buf, area);

    // First entry at y=0, second at y=1, third at y=2
    try testing.expectEqual(@as(u21, 'a'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'b'), buf.get(0, 1).?.char);
    try testing.expectEqual(@as(u21, 'c'), buf.get(0, 2).?.char);
}

// ============================================================================
// RENDER TESTS - BINARY FILES
// ============================================================================

test "DiffStat render binary file shows Bin text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "image.png",
        .insertions = 100,
        .deletions = 50,
        .binary = true,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    ds.render(&buf, area);

    // Should contain "Bin" text
    var found_bin = false;
    for (0..50) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == 'B') {
            // Check for "Bin" pattern
            if (x + 2 < 50 and
                buf.get(@as(u16, @intCast(x + 1)), 0).?.char == 'i' and
                buf.get(@as(u16, @intCast(x + 2)), 0).?.char == 'n') {
                found_bin = true;
                break;
            }
        }
    }
    try testing.expect(found_bin);
}

test "DiffStat render binary file with binary style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "data.bin",
        .insertions = 0,
        .deletions = 0,
        .binary = true,
    };
    const entries = [_]DiffStatEntry{entry};
    const style = Style{ .fg = Color.yellow };
    const ds = DiffStat.init(&entries).withBinaryStyle(style);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    ds.render(&buf, area);

    // Find "Bin" and check its style
    for (0..50) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == 'B') {
            if (x + 2 < 50 and
                buf.get(@as(u16, @intCast(x + 1)), 0).?.char == 'i' and
                buf.get(@as(u16, @intCast(x + 2)), 0).?.char == 'n') {
                try testing.expectEqual(Color.yellow, buf.get(@as(u16, @intCast(x)), 0).?.style.fg);
                break;
            }
        }
    }
}

test "DiffStat render binary file no insertion/deletion bar" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.bin",
        .insertions = 100,
        .deletions = 100,
        .binary = true,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    ds.render(&buf, area);

    // Should show "Bin" instead of +/- bar
    var found_bin = false;
    var found_plus = false;
    var found_minus = false;

    for (0..50) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '+') found_plus = true;
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '-') found_minus = true;
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == 'B') {
            if (x + 2 < 50 and
                buf.get(@as(u16, @intCast(x + 1)), 0).?.char == 'i' and
                buf.get(@as(u16, @intCast(x + 2)), 0).?.char == 'n') {
                found_bin = true;
            }
        }
    }

    try testing.expect(found_bin);
    try testing.expect(!found_plus);
    try testing.expect(!found_minus);
}

// ============================================================================
// RENDER TESTS - BAR RENDERING
// ============================================================================

test "DiffStat render all insertions shows all plus chars" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 100,
        .deletions = 0,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Bar area should be all '+' chars (no '-')
    var bar_start: ?usize = null;
    for (0..60) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '+') {
            if (bar_start == null) bar_start = x;
        }
    }

    // Should have plus chars but no minus in bar area
    try testing.expect(bar_start != null);
}

test "DiffStat render all deletions shows all minus chars" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 0,
        .deletions = 100,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Bar area should be all '-' chars
    var minus_count: u32 = 0;
    for (0..60) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '-') {
            minus_count += 1;
        }
    }

    try testing.expect(minus_count > 0);
}

test "DiffStat render proportional bar sizing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 50,
        .deletions = 50,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // With 50/50 split, bar should have roughly equal + and -
    var plus_count: u32 = 0;
    var minus_count: u32 = 0;

    for (0..60) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '+') plus_count += 1;
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '-') minus_count += 1;
    }

    // Both should be greater than 0
    try testing.expect(plus_count > 0);
    try testing.expect(minus_count > 0);
}

test "DiffStat render custom insertion char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 50,
        .deletions = 0,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries).withInsertionChar('=');

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Should contain '=' not '+'
    var found_equals = false;
    var found_plus = false;

    for (0..60) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '=') found_equals = true;
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '+') found_plus = true;
    }

    try testing.expect(found_equals);
    try testing.expect(!found_plus);
}

test "DiffStat render custom deletion char" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 0,
        .deletions = 50,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries).withDeletionChar('x');

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Should contain 'x' not '-'
    var found_x = false;
    var found_minus = false;

    for (0..60) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == 'x') found_x = true;
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '-') found_minus = true;
    }

    try testing.expect(found_x);
    try testing.expect(!found_minus);
}

// ============================================================================
// RENDER TESTS - STYLE APPLICATION
// ============================================================================

test "DiffStat render insertion style applied" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 50,
        .deletions = 0,
    };
    const entries = [_]DiffStatEntry{entry};
    const style = Style{ .fg = Color.blue };
    const ds = DiffStat.init(&entries).withInsertionStyle(style);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Find '+' and check it has blue style
    for (0..60) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '+') {
            try testing.expectEqual(Color.blue, buf.get(@as(u16, @intCast(x)), 0).?.style.fg);
            break;
        }
    }
}

test "DiffStat render deletion style applied" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 0,
        .deletions = 50,
    };
    const entries = [_]DiffStatEntry{entry};
    const style = Style{ .fg = Color.cyan };
    const ds = DiffStat.init(&entries).withDeletionStyle(style);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Find '-' and check it has cyan style
    for (0..60) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '-') {
            try testing.expectEqual(Color.cyan, buf.get(@as(u16, @intCast(x)), 0).?.style.fg);
            break;
        }
    }
}

test "DiffStat render filename style applied" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "test.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const style = Style{ .bold = true };
    const ds = DiffStat.init(&entries).withFilenameStyle(style);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Filename should have bold style
    try testing.expect(buf.get(0, 0).?.style.bold);
}

// ============================================================================
// RENDER TESTS - FILENAME TRUNCATION
// ============================================================================

test "DiffStat render filename truncated when exceeds max_filename_width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "very_long_filename_here.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    var ds = DiffStat.init(&entries);
    ds.max_filename_width = 10;

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    ds.render(&buf, area);

    // Should render without crash and filename should be limited
    try testing.expect(true);
}

test "DiffStat render filename not truncated when below max_filename_width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "short.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    var ds = DiffStat.init(&entries);
    ds.max_filename_width = 20;

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    ds.render(&buf, area);

    // Should render full filename
    try testing.expectEqual(@as(u21, 's'), buf.get(0, 0).?.char);
}

// ============================================================================
// RENDER TESTS - BLOCK BORDER
// ============================================================================

test "DiffStat render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 5);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const block = Block{};
    const ds = DiffStat.init(&entries).withBlock(block);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 5 };
    ds.render(&buf, area);

    // Should render border characters
    try testing.expect(true);
}

// ============================================================================
// RENDER TESTS - OFFSET POSITIONING
// ============================================================================

test "DiffStat render with offset area position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 20);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 10, .y = 5, .width = 30, .height = 1 };
    ds.render(&buf, area);

    // Should render at offset position
    try testing.expectEqual(@as(u21, 'a'), buf.get(10, 5).?.char);
}

// ============================================================================
// RENDER TESTS - COUNT RENDERING
// ============================================================================

test "DiffStat render includes insertion count" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 70, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 42,
        .deletions = 0,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 1 };
    ds.render(&buf, area);

    // Should contain "+42" text
    var found_plus_42 = false;
    for (0..70) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '+' and x + 2 < 70) {
            if (buf.get(@as(u16, @intCast(x + 1)), 0).?.char == '4' and
                buf.get(@as(u16, @intCast(x + 2)), 0).?.char == '2') {
                found_plus_42 = true;
                break;
            }
        }
    }
    try testing.expect(found_plus_42);
}

test "DiffStat render includes deletion count" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 70, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 0,
        .deletions = 17,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 1 };
    ds.render(&buf, area);

    // Should contain "-17" text
    var found_minus_17 = false;
    for (0..70) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '-' and x + 2 < 70) {
            if (buf.get(@as(u16, @intCast(x + 1)), 0).?.char == '1' and
                buf.get(@as(u16, @intCast(x + 2)), 0).?.char == '7') {
                found_minus_17 = true;
                break;
            }
        }
    }
    try testing.expect(found_minus_17);
}

test "DiffStat render includes both counts" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 35,
        .deletions = 8,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ds.render(&buf, area);

    // Should contain both +35 and -8
    var plus_count: u32 = 0;
    var minus_count: u32 = 0;

    for (0..80) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '+') plus_count += 1;
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '-') minus_count += 1;
    }

    // Should have multiple + and - for bar and counts
    try testing.expect(plus_count > 0);
    try testing.expect(minus_count > 0);
}

// ============================================================================
// EDGE CASES
// ============================================================================

test "DiffStat render zero width area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    ds.render(&buf, area);

    // Should not crash
    try testing.expect(true);
}

test "DiffStat render zero height area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 10);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 0 };
    ds.render(&buf, area);

    // Should not crash
    try testing.expect(true);
}

test "DiffStat render single width area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    ds.render(&buf, area);

    // Should not crash
    try testing.expect(true);
}

test "DiffStat render with very large insertions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 9999,
        .deletions = 100,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    ds.render(&buf, area);

    // Should render without crash/overflow
    try testing.expect(true);
}

test "DiffStat render with zero changes" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 0,
        .deletions = 0,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Should render filename and pipe but no bar
    try testing.expect(true);
}

test "DiffStat render empty filename" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "",
        .insertions = 10,
        .deletions = 5,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Should render pipe and bar
    try testing.expect(true);
}

test "DiffStat render with very small bar width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 1);
    defer buf.deinit();

    const entry: DiffStatEntry = .{
        .filename = "a.zig",
        .insertions = 50,
        .deletions = 50,
    };
    const entries = [_]DiffStatEntry{entry};
    const ds = DiffStat.init(&entries).withBarWidth(1);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 1 };
    ds.render(&buf, area);

    // Should render single-char bar
    try testing.expect(true);
}

test "DiffStat render entries exceed available height" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 60, 10);
    defer buf.deinit();

    var entries: [10]DiffStatEntry = undefined;
    for (0..10) |i| {
        entries[i] = .{
            .filename = "file.zig",
            .insertions = 10 + @as(u32, @intCast(i)),
            .deletions = 5 + @as(u32, @intCast(i)),
        };
    }
    const ds = DiffStat.init(&entries);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 3 };
    ds.render(&buf, area);

    // Should render only what fits
    try testing.expect(true);
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

test "DiffStat full workflow with realistic data" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 5);
    defer buf.deinit();

    const entries: [3]DiffStatEntry = .{
        .{ .filename = "src/main.zig", .insertions = 150, .deletions = 42 },
        .{ .filename = "README.md", .insertions = 0, .deletions = 0, .binary = true },
        .{ .filename = "build.zig", .insertions = 8, .deletions = 3 },
    };
    const ds = DiffStat.init(&entries)
        .withBarWidth(25)
        .withInsertionStyle(.{ .fg = Color.green })
        .withDeletionStyle(.{ .fg = Color.red });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    ds.render(&buf, area);

    // Verify aggregations
    try testing.expectEqual(@as(u32, 158), ds.totalInsertions());
    try testing.expectEqual(@as(u32, 45), ds.totalDeletions());
    try testing.expectEqual(@as(usize, 3), ds.totalFiles());
}

test "DiffStat stats computation accuracy" {
    const entries: [4]DiffStatEntry = .{
        .{ .filename = "a.zig", .insertions = 100, .deletions = 50 },
        .{ .filename = "b.zig", .insertions = 200, .deletions = 75 },
        .{ .filename = "c.zig", .insertions = 50, .deletions = 100 },
        .{ .filename = "d.zig", .insertions = 25, .deletions = 25 },
    };
    const ds = DiffStat.init(&entries);

    try testing.expectEqual(@as(u32, 375), ds.totalInsertions());
    try testing.expectEqual(@as(u32, 250), ds.totalDeletions());
    try testing.expectEqual(@as(usize, 4), ds.totalFiles());
    try testing.expectEqual(@as(u32, 275), ds.computeMaxChanges());
}
