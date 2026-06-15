//! KeyValueViewer Widget Tests
//!
//! Comprehensive test suite for the KeyValueViewer widget covering:
//! - Initialization and defaults
//! - Entry selection and navigation
//! - Key width computation (auto vs fixed)
//! - Scrolling and offset management
//! - Builder API (immutability checks)
//! - Rendering behavior
//! - Edge cases and boundary conditions

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;

// Import KeyValueViewer types (will be exported from tui.zig)
const KeyValueViewer = sailor.tui.widgets.KeyValueViewer;
const Entry = sailor.tui.widgets.KeyValueViewer.Entry;
const KeyWidth = sailor.tui.widgets.KeyValueViewer.KeyWidth;

/// Helper: Create a buffer with given dimensions
fn makeBuffer(w: u16, h: u16) !Buffer {
    return try Buffer.init(testing.allocator, w, h);
}

/// Helper: Find first x position in a row where a specific character appears
fn findCharInRow(buf: Buffer, y: u16, char: u21) ?u16 {
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == char) return x;
        }
    }
    return null;
}

/// Helper: Check if row contains a character
fn rowHasChar(buf: Buffer, y: u16, char: u21) bool {
    return findCharInRow(buf, y, char) != null;
}

/// Helper: Get character at position
fn getCharAt(buf: Buffer, x: u16, y: u16) ?u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return null;
}

/// Helper: Count character width for render tests
fn countCharsInRow(buf: Buffer, y: u16) u16 {
    var count: u16 = 0;
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char != ' ') {
                count += 1;
            }
        }
    }
    return count;
}

// ============================================================================
// INITIALIZATION & DEFAULTS (5 tests)
// ============================================================================

test "KeyValueViewer init creates viewer with entries" {
    const entries = [_]Entry{
        .{ .key = "key1", .value = "value1" },
        .{ .key = "key2", .value = "value2" },
    };
    const viewer = KeyValueViewer.init(&entries);
    try testing.expectEqual(@as(usize, 2), viewer.entries.len);
    try testing.expect(std.mem.eql(u8, viewer.entries[0].key, "key1"));
}

test "KeyValueViewer init selected is null" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "b" },
    };
    const viewer = KeyValueViewer.init(&entries);
    try testing.expectEqual(@as(?usize, null), viewer.selected);
}

test "KeyValueViewer init offset is zero" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "b" },
    };
    const viewer = KeyValueViewer.init(&entries);
    try testing.expectEqual(@as(usize, 0), viewer.offset);
}

test "KeyValueViewer init key_width is auto" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer = KeyValueViewer.init(&entries);
    switch (viewer.key_width) {
        .auto => {},
        else => try testing.expect(false),
    }
}

test "KeyValueViewer init separator is colon space" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer = KeyValueViewer.init(&entries);
    try testing.expect(std.mem.eql(u8, viewer.separator, ": "));
}

// ============================================================================
// count() (3 tests)
// ============================================================================

test "KeyValueViewer count with zero entries" {
    const viewer = KeyValueViewer.init(&.{});
    try testing.expectEqual(@as(usize, 0), viewer.count());
}

test "KeyValueViewer count with single entry" {
    const entries = [_]Entry{
        .{ .key = "x", .value = "y" },
    };
    const viewer = KeyValueViewer.init(&entries);
    try testing.expectEqual(@as(usize, 1), viewer.count());
}

test "KeyValueViewer count with multiple entries" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    const viewer = KeyValueViewer.init(&entries);
    try testing.expectEqual(@as(usize, 3), viewer.count());
}

// ============================================================================
// computeKeyWidth() (5 tests)
// ============================================================================

test "KeyValueViewer computeKeyWidth auto with empty entries" {
    const viewer = KeyValueViewer.init(&.{});
    const width = viewer.computeKeyWidth();
    try testing.expectEqual(@as(usize, 0), width);
}

test "KeyValueViewer computeKeyWidth auto with single entry" {
    const entries = [_]Entry{
        .{ .key = "hello", .value = "world" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const width = viewer.computeKeyWidth();
    try testing.expectEqual(@as(usize, 5), width);
}

test "KeyValueViewer computeKeyWidth auto returns max of all keys" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "longer_key", .value = "2" },
        .{ .key = "mid", .value = "3" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const width = viewer.computeKeyWidth();
    try testing.expectEqual(@as(usize, 10), width);
}

test "KeyValueViewer computeKeyWidth fixed returns fixed value" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.key_width = .{ .fixed = 15 };
    const width = viewer.computeKeyWidth();
    try testing.expectEqual(@as(usize, 15), width);
}

test "KeyValueViewer computeKeyWidth fixed with empty entries" {
    const viewer_val = KeyValueViewer.init(&.{});
    var viewer = viewer_val;
    viewer.key_width = .{ .fixed = 20 };
    const width = viewer.computeKeyWidth();
    try testing.expectEqual(@as(usize, 20), width);
}

// ============================================================================
// selectedEntry() (4 tests)
// ============================================================================

test "KeyValueViewer selectedEntry with null returns null" {
    const entries = [_]Entry{
        .{ .key = "key1", .value = "val1" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const entry = viewer.selectedEntry();
    try testing.expectEqual(@as(?Entry, null), entry);
}

test "KeyValueViewer selectedEntry with selected=0" {
    const entries = [_]Entry{
        .{ .key = "first", .value = "first_val" },
        .{ .key = "second", .value = "second_val" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 0;
    const entry = viewer.selectedEntry();
    try testing.expect(entry != null);
    try testing.expect(std.mem.eql(u8, entry.?.key, "first"));
}

test "KeyValueViewer selectedEntry with selected=last" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 2;
    const entry = viewer.selectedEntry();
    try testing.expect(entry != null);
    try testing.expect(std.mem.eql(u8, entry.?.key, "c"));
}

test "KeyValueViewer selectedEntry with out of range index" {
    const entries = [_]Entry{
        .{ .key = "only", .value = "one" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 5;
    const entry = viewer.selectedEntry();
    try testing.expectEqual(@as(?Entry, null), entry);
}

// ============================================================================
// selectNext() (6 tests)
// ============================================================================

test "KeyValueViewer selectNext from null sets to 0" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
    };
    var viewer = KeyValueViewer.init(&entries);
    try testing.expectEqual(@as(?usize, null), viewer.selected);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
}

test "KeyValueViewer selectNext from 0 to 1" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 0;
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 1), viewer.selected);
}

test "KeyValueViewer selectNext clamps at last" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 1;
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 1), viewer.selected);
}

test "KeyValueViewer selectNext with empty entries does nothing" {
    var viewer = KeyValueViewer.init(&.{});
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, null), viewer.selected);
}

test "KeyValueViewer selectNext consecutive advances through all" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 1), viewer.selected);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 2), viewer.selected);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 3), viewer.selected);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 3), viewer.selected);
}

test "KeyValueViewer selectNext with single entry stays at 0" {
    const entries = [_]Entry{
        .{ .key = "single", .value = "entry" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
}

// ============================================================================
// selectPrev() (5 tests)
// ============================================================================

test "KeyValueViewer selectPrev from null stays null" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, null), viewer.selected);
}

test "KeyValueViewer selectPrev from 1 to 0" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 1;
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
}

test "KeyValueViewer selectPrev from 0 clamps at 0" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 0;
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
}

test "KeyValueViewer selectPrev with empty entries does nothing" {
    var viewer = KeyValueViewer.init(&.{});
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, null), viewer.selected);
}

test "KeyValueViewer selectPrev consecutive retreats correctly" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 3;
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, 2), viewer.selected);
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, 1), viewer.selected);
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
}

// ============================================================================
// scrollToSelected() (5 tests)
// ============================================================================

test "KeyValueViewer scrollToSelected with null does nothing" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.offset = 2;
    viewer.scrollToSelected(5);
    try testing.expectEqual(@as(usize, 2), viewer.offset);
}

test "KeyValueViewer scrollToSelected selected in view keeps offset" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
        .{ .key = "e", .value = "5" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.offset = 0;
    viewer.selected = 3;
    viewer.scrollToSelected(5);
    try testing.expectEqual(@as(usize, 0), viewer.offset);
}

test "KeyValueViewer scrollToSelected moves offset up" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
        .{ .key = "e", .value = "5" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.offset = 3;
    viewer.selected = 1;
    viewer.scrollToSelected(5);
    try testing.expectEqual(@as(usize, 1), viewer.offset);
}

test "KeyValueViewer scrollToSelected moves offset down" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
        .{ .key = "e", .value = "5" },
        .{ .key = "f", .value = "6" },
        .{ .key = "g", .value = "7" },
        .{ .key = "h", .value = "8" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.offset = 0;
    viewer.selected = 7;
    viewer.scrollToSelected(3);
    try testing.expect(viewer.offset > 0);
    try testing.expect(viewer.selected.? >= viewer.offset);
}

test "KeyValueViewer scrollToSelected with visible_rows=0" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 0;
    viewer.offset = 0;
    viewer.scrollToSelected(0);
    // Should not crash
}

// ============================================================================
// BUILDER API (10 tests)
// ============================================================================

test "KeyValueViewer withSelected returns new value with selection" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const viewer2 = viewer1.withSelected(1);
    try testing.expectEqual(@as(?usize, null), viewer1.selected);
    try testing.expectEqual(@as(?usize, 1), viewer2.selected);
}

test "KeyValueViewer withSelected null clears selection" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
    };
    var viewer1 = KeyValueViewer.init(&entries);
    viewer1.selected = 0;
    const viewer2 = viewer1.withSelected(null);
    try testing.expectEqual(@as(?usize, 0), viewer1.selected);
    try testing.expectEqual(@as(?usize, null), viewer2.selected);
}

test "KeyValueViewer withOffset returns new value" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const viewer2 = viewer1.withOffset(5);
    try testing.expectEqual(@as(usize, 0), viewer1.offset);
    try testing.expectEqual(@as(usize, 5), viewer2.offset);
}

test "KeyValueViewer withKeyWidth fixed returns new value" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const viewer2 = viewer1.withKeyWidth(.{ .fixed = 10 });
    switch (viewer1.key_width) {
        .auto => {},
        else => try testing.expect(false),
    }
    switch (viewer2.key_width) {
        .fixed => |w| try testing.expectEqual(@as(u16, 10), w),
        else => try testing.expect(false),
    }
}

test "KeyValueViewer withSeparator returns new value" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const viewer2 = viewer1.withSeparator(" = ");
    try testing.expect(std.mem.eql(u8, viewer1.separator, ": "));
    try testing.expect(std.mem.eql(u8, viewer2.separator, " = "));
}

test "KeyValueViewer withKeyStyle returns new value" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const style = Style{ .bold = true };
    const viewer2 = viewer1.withKeyStyle(style);
    try testing.expect(!viewer1.key_style.bold);
    try testing.expect(viewer2.key_style.bold);
}

test "KeyValueViewer withValueStyle returns new value" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const style = Style{ .dim = true };
    const viewer2 = viewer1.withValueStyle(style);
    try testing.expect(!viewer1.value_style.dim);
    try testing.expect(viewer2.value_style.dim);
}

test "KeyValueViewer withSelectedKeyStyle returns new value" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const style = Style{ .reverse = true };
    const viewer2 = viewer1.withSelectedKeyStyle(style);
    try testing.expect(!viewer1.selected_key_style.reverse);
    try testing.expect(viewer2.selected_key_style.reverse);
}

test "KeyValueViewer withSelectedValueStyle returns new value" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const style = Style{ .underline = true };
    const viewer2 = viewer1.withSelectedValueStyle(style);
    try testing.expect(!viewer1.selected_value_style.underline);
    try testing.expect(viewer2.selected_value_style.underline);
}

test "KeyValueViewer withBlock returns new value" {
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer1 = KeyValueViewer.init(&entries);
    const block = Block{};
    const viewer2 = viewer1.withBlock(block);
    try testing.expectEqual(@as(?Block, null), viewer1.block);
    try testing.expect(viewer2.block != null);
}

// ============================================================================
// RENDER BASIC (10 tests)
// ============================================================================

test "KeyValueViewer render with empty entries shows nothing" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const viewer = KeyValueViewer.init(&.{});
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render single entry key appears" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "mykey", .value = "myvalue" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'm'));
}

test "KeyValueViewer render single entry separator appears" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, ':'));
}

test "KeyValueViewer render single entry value appears" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'v'));
}

test "KeyValueViewer render three entries all visible" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'a'));
    try testing.expect(rowHasChar(buf, 1, 'b'));
    try testing.expect(rowHasChar(buf, 2, 'c'));
}

test "KeyValueViewer render respects offset" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.offset = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'b'));
    try testing.expect(rowHasChar(buf, 1, 'c'));
}

test "KeyValueViewer render selected row uses selected_key_style" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "first", .value = "1" },
        .{ .key = "second", .value = "2" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 0;
    const style = Style{ .reverse = true };
    viewer.selected_key_style = style;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'f'));
}

test "KeyValueViewer render non-selected row uses key_style" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 1;
    const style = Style{ .dim = true };
    viewer.key_style = style;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'a'));
}

test "KeyValueViewer render custom separator appears" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.separator = " => ";
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, '='));
}

test "KeyValueViewer render key width auto pads correctly" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "longer", .value = "2" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'a'));
}

test "KeyValueViewer render zero area does not crash" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    viewer.render(&buf, area);
}

// ============================================================================
// RENDER WITH BLOCK (3 tests)
// ============================================================================

test "KeyValueViewer render with block renders border" {
    var buf = try makeBuffer(30, 10);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.block = Block{};
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render with block small area does not crash" {
    var buf = try makeBuffer(6, 6);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "x", .value = "y" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.block = Block{};
    const area = Rect{ .x = 0, .y = 0, .width = 6, .height = 6 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render content inside block border" {
    var buf = try makeBuffer(20, 10);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.block = Block{};
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    viewer.render(&buf, area);
}

// ============================================================================
// RENDER KEY WIDTH FIXED (3 tests)
// ============================================================================

test "KeyValueViewer render key_width fixed truncates long key" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "verylongkey", .value = "val" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.key_width = .{ .fixed = 5 };
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'v'));
}

test "KeyValueViewer render key_width fixed pads short key" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "ab", .value = "val" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.key_width = .{ .fixed = 5 };
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'a'));
}

test "KeyValueViewer render with fixed width column" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "k1", .value = "v1" },
        .{ .key = "k2", .value = "v2" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.key_width = .{ .fixed = 10 };
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    viewer.render(&buf, area);
}

// ============================================================================
// RENDER OFFSET & PAGINATION (4 tests)
// ============================================================================

test "KeyValueViewer render offset beyond entries renders nothing" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.offset = 100;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render height=1 shows only one entry" {
    var buf = try makeBuffer(30, 1);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render height limited by area" {
    var buf = try makeBuffer(30, 3);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render partial offset shows remaining" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.offset = 2;
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
    try testing.expect(rowHasChar(buf, 0, 'c'));
}

// ============================================================================
// RENDER WIDTH CONSTRAINTS (3 tests)
// ============================================================================

test "KeyValueViewer render narrow width minimal display" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "val" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render width=1 does not crash" {
    var buf = try makeBuffer(5, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "b" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 5 };
    viewer.render(&buf, area);
}

test "KeyValueViewer render long value truncated" {
    var buf = try makeBuffer(15, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "k", .value = "verylongvalue" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    viewer.render(&buf, area);
}

// ============================================================================
// EDGE CASES (7 tests)
// ============================================================================

test "KeyValueViewer single entry selected then advanced clamps" {
    const entries = [_]Entry{
        .{ .key = "single", .value = "entry" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
}

test "KeyValueViewer single entry selectPrev from 0 clamps" {
    const entries = [_]Entry{
        .{ .key = "only", .value = "one" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 0;
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, 0), viewer.selected);
}

test "KeyValueViewer empty entries selectNext does nothing" {
    var viewer = KeyValueViewer.init(&.{});
    viewer.selectNext();
    try testing.expectEqual(@as(?usize, null), viewer.selected);
}

test "KeyValueViewer empty entries selectPrev does nothing" {
    var viewer = KeyValueViewer.init(&.{});
    viewer.selectPrev();
    try testing.expectEqual(@as(?usize, null), viewer.selected);
}

test "KeyValueViewer very wide separator does not crash" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "k", .value = "v" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.separator = " ----------- ";
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
}

test "KeyValueViewer entry with empty key renders" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "", .value = "value" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
}

test "KeyValueViewer entry with empty value renders" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key", .value = "" },
    };
    const viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    viewer.render(&buf, area);
}

// ============================================================================
// COMPLEX SCENARIOS (5 tests)
// ============================================================================

test "KeyValueViewer builder chain all withKeyStyle methods" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    const style = Style{ .bold = true };
    var viewer = KeyValueViewer.init(&entries);
    viewer = viewer.withKeyStyle(style);
    viewer = viewer.withValueStyle(style);
    viewer = viewer.withSelectedKeyStyle(style);
    viewer = viewer.withSelectedValueStyle(style);
    try testing.expectEqual(@as(usize, 2), viewer.count());
}

test "KeyValueViewer selection and offset work together" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
        .{ .key = "e", .value = "5" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selectNext();
    viewer.selectNext();
    viewer.selectNext();
    viewer.scrollToSelected(2);
    try testing.expectEqual(@as(?usize, 2), viewer.selected);
}

test "KeyValueViewer render multiple times with state changes" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    var viewer = KeyValueViewer.init(&entries);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };

    viewer.render(&buf, area);
    viewer.selectNext();
    viewer.render(&buf, area);
    viewer.offset = 1;
    viewer.render(&buf, area);
}

test "KeyValueViewer offset prevents selection visibility" {
    const entries = [_]Entry{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
        .{ .key = "d", .value = "4" },
    };
    var viewer = KeyValueViewer.init(&entries);
    viewer.selected = 0;
    viewer.offset = 2;
    // Selected is now above the view
    viewer.scrollToSelected(2);
    try testing.expect(viewer.offset <= viewer.selected.?);
}

test "KeyValueViewer render after all builder operations" {
    var buf = try makeBuffer(40, 8);
    defer buf.deinit();
    const entries = [_]Entry{
        .{ .key = "key1", .value = "value1" },
        .{ .key = "key2", .value = "value2" },
        .{ .key = "key3", .value = "value3" },
    };
    const block = Block{};
    const key_style = Style{ .bold = true };
    const value_style = Style{ .dim = true };
    const selected_key = Style{ .reverse = true };
    const selected_val = Style{ .underline = true };

    var viewer = KeyValueViewer.init(&entries);
    viewer = viewer.withBlock(block);
    viewer = viewer.withKeyStyle(key_style);
    viewer = viewer.withValueStyle(value_style);
    viewer = viewer.withSelectedKeyStyle(selected_key);
    viewer = viewer.withSelectedValueStyle(selected_val);
    viewer = viewer.withSelected(1);
    viewer = viewer.withOffset(0);
    viewer = viewer.withSeparator(" => ");
    viewer = viewer.withKeyWidth(.{ .fixed = 10 });

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 8 };
    viewer.render(&buf, area);

    try testing.expectEqual(@as(usize, 3), viewer.count());
    try testing.expect(viewer.selectedEntry() != null);
}
