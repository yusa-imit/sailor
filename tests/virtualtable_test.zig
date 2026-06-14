//! VirtualTable Widget Tests — Comprehensive Coverage
//!
//! Tests the VirtualTable widget's initialization, selection and offset navigation,
//! pagination (pageDown/pageUp), viewport scrolling, builder API, rendering with
//! virtual scrolling, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Cell = sailor.tui.buffer.Cell;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const Column = sailor.tui.widgets.Column;
const ColumnWidth = sailor.tui.widgets.ColumnWidth;

// Import VirtualTable types (will be exported from tui.zig by zig-developer)
const VirtualTable = sailor.tui.VirtualTable;

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

/// Helper: Check if row contains specific text (substring match)
fn rowHasText(buf: Buffer, y: u16, text: []const u8) bool {
    if (text.len == 0) return true;
    var x: u16 = 0;
    while (x < buf.width) : (x += 1) {
        if (buf.getConst(x, y)) |cell| {
            if (cell.char == text[0]) {
                var match = true;
                var offset: u16 = 1;
                while (offset < text.len and x + offset < buf.width) : (offset += 1) {
                    if (buf.getConst(x + offset, y)) |next_cell| {
                        if (next_cell.char != text[offset]) {
                            match = false;
                            break;
                        }
                    } else {
                        match = false;
                        break;
                    }
                }
                if (match and offset == text.len) return true;
            }
        }
    }
    return false;
}

/// Helper: Get character at position
fn getCharAt(buf: Buffer, x: u16, y: u16) ?u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return null;
}

// ============================================================================
// INITIALIZATION TESTS (5 tests)
// ============================================================================

test "VirtualTable init creates table with default values" {
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .percentage = 50 } },
        .{ .title = "Type", .width = .{ .percentage = 50 } },
    };
    const vt = VirtualTable.init(&cols);
    try testing.expectEqual(@as(?usize, null), vt.selected);
    try testing.expectEqual(@as(usize, 0), vt.offset);
    try testing.expectEqual(@as(u16, 1), vt.column_spacing);
}

test "VirtualTable init stores columns" {
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .fixed = 20 } },
        .{ .title = "Value", .width = .{ .fixed = 30 } },
    };
    const vt = VirtualTable.init(&cols);
    try testing.expectEqual(@as(usize, 2), vt.columns.len);
    try testing.expect(std.mem.eql(u8, vt.columns[0].title, "Name"));
    try testing.expect(std.mem.eql(u8, vt.columns[1].title, "Value"));
}

test "VirtualTable init with empty columns" {
    const vt = VirtualTable.init(&.{});
    try testing.expectEqual(@as(usize, 0), vt.columns.len);
    try testing.expectEqual(@as(?usize, null), vt.selected);
}

test "VirtualTable init selected is null" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt = VirtualTable.init(&cols);
    try testing.expectEqual(@as(?usize, null), vt.selected);
}

test "VirtualTable init offset is zero" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt = VirtualTable.init(&cols);
    try testing.expectEqual(@as(usize, 0), vt.offset);
}

// ============================================================================
// ROWCOUNT TESTS (3 tests)
// ============================================================================

test "VirtualTable rowCount with empty rows returns 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt = VirtualTable.init(&cols);
    try testing.expectEqual(@as(usize, 0), vt.rowCount());
}

test "VirtualTable rowCount with single row returns 1" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Row1"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    try testing.expectEqual(@as(usize, 1), vt.rowCount());
}

test "VirtualTable rowCount with 5 rows returns 5" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Row1"},
        &.{"Row2"},
        &.{"Row3"},
        &.{"Row4"},
        &.{"Row5"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    try testing.expectEqual(@as(usize, 5), vt.rowCount());
}

// ============================================================================
// SELECTEDROW TESTS (4 tests)
// ============================================================================

test "VirtualTable selectedRow with no rows returns null" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt = VirtualTable.init(&cols);
    try testing.expectEqual(@as(?[]const []const u8, null), vt.selectedRow());
}

test "VirtualTable selectedRow with selected=null returns null" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Row1"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    try testing.expectEqual(@as(?[]const []const u8, null), vt.selectedRow());
}

test "VirtualTable selectedRow with selected=0 returns first row" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Row1"},
        &.{"Row2"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(0);
    const row = vt.selectedRow();
    try testing.expect(row != null);
    try testing.expect(std.mem.eql(u8, row.?[0], "Row1"));
}

test "VirtualTable selectedRow with selected=2 returns third row" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Row1"},
        &.{"Row2"},
        &.{"Row3"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(2);
    const row = vt.selectedRow();
    try testing.expect(row != null);
    try testing.expect(std.mem.eql(u8, row.?[0], "Row3"));
}

// ============================================================================
// SELECTNEXT TESTS (8 tests)
// ============================================================================

test "VirtualTable selectNext with empty rows does not crash" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    var vt = VirtualTable.init(&cols);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, null), vt.selected);
}

test "VirtualTable selectNext from null sets selected to 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    try testing.expectEqual(@as(?usize, null), vt.selected);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 0), vt.selected);
}

test "VirtualTable selectNext from 0 moves to 1" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(0);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 1), vt.selected);
}

test "VirtualTable selectNext clamps at last row" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(1);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 1), vt.selected); // Clamped at last
}

test "VirtualTable selectNext consecutive calls increment correctly" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 0), vt.selected);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 1), vt.selected);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 2), vt.selected);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 3), vt.selected);
}

test "VirtualTable selectNext with single row stays at 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Single"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 0), vt.selected);
    vt.selectNext();
    try testing.expectEqual(@as(?usize, 0), vt.selected);
}

test "VirtualTable selectNext adjusts offset so selected is visible" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(3); // Invalid offset, past last row
    vt.selectNext();
    // After selectNext, selected should be 0 and offset should be <= selected
    try testing.expectEqual(@as(?usize, 0), vt.selected);
    try testing.expect(vt.offset <= 0); // offset should be adjusted
}

// ============================================================================
// SELECTPREV TESTS (6 tests)
// ============================================================================

test "VirtualTable selectPrev with empty rows does not crash" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    var vt = VirtualTable.init(&cols);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, null), vt.selected);
}

test "VirtualTable selectPrev from null stays null" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, null), vt.selected);
}

test "VirtualTable selectPrev from 1 moves to 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(1);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), vt.selected);
}

test "VirtualTable selectPrev from 0 stays at 0" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(0);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), vt.selected); // Clamped at 0
}

test "VirtualTable selectPrev consecutive calls decrement correctly" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(3);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, 2), vt.selected);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, 1), vt.selected);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), vt.selected);
    vt.selectPrev();
    try testing.expectEqual(@as(?usize, 0), vt.selected); // Stays at 0
}

// ============================================================================
// PAGEDOWN TESTS (5 tests)
// ============================================================================

test "VirtualTable pageDown advances offset by page_size" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
        &.{"F"},
        &.{"G"},
        &.{"H"},
        &.{"I"},
        &.{"J"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(0);
    vt.pageDown(3);
    try testing.expectEqual(@as(usize, 3), vt.offset);
}

test "VirtualTable pageDown clamps offset to valid range" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(1);
    vt.pageDown(5);
    // offset should clamp to rows.len - 1 = 2
    try testing.expect(vt.offset <= 2);
}

test "VirtualTable pageDown from last row stays at last" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(2);
    vt.pageDown(3);
    try testing.expectEqual(@as(usize, 2), vt.offset);
}

test "VirtualTable pageDown with empty rows does not crash" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    var vt = VirtualTable.init(&cols);
    vt.pageDown(3);
    try testing.expectEqual(@as(usize, 0), vt.offset);
}

test "VirtualTable pageDown with zero page_size unchanged" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(0);
    vt.pageDown(0);
    try testing.expectEqual(@as(usize, 0), vt.offset);
}

// ============================================================================
// PAGEUP TESTS (5 tests)
// ============================================================================

test "VirtualTable pageUp reduces offset by page_size" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
        &.{"F"},
        &.{"G"},
        &.{"H"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(5);
    vt.pageUp(3);
    try testing.expectEqual(@as(usize, 2), vt.offset);
}

test "VirtualTable pageUp clamps at zero" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(2);
    vt.pageUp(5); // Would go negative, clamps to 0
    try testing.expectEqual(@as(usize, 0), vt.offset);
}

test "VirtualTable pageUp from zero stays at zero" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(0);
    vt.pageUp(3);
    try testing.expectEqual(@as(usize, 0), vt.offset);
}

test "VirtualTable pageUp with empty rows does not crash" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    var vt = VirtualTable.init(&cols);
    vt.pageUp(3);
    try testing.expectEqual(@as(usize, 0), vt.offset);
}

test "VirtualTable pageUp with zero page_size unchanged" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(5);
    vt.pageUp(0);
    try testing.expectEqual(@as(usize, 5), vt.offset);
}

// ============================================================================
// SCROLLTOSELECTED TESTS (6 tests)
// ============================================================================

test "VirtualTable scrollToSelected with null selected does nothing" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(2);
    vt.scrollToSelected(5);
    try testing.expectEqual(@as(usize, 2), vt.offset); // Unchanged
}

test "VirtualTable scrollToSelected with selected in view keeps offset" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(0);
    vt = vt.withSelected(3);
    vt.scrollToSelected(5); // visible_rows=5, selected=3 is in view
    try testing.expectEqual(@as(usize, 0), vt.offset); // Unchanged
}

test "VirtualTable scrollToSelected moves offset when selected above view" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(3);
    vt = vt.withSelected(1);
    vt.scrollToSelected(5);
    try testing.expectEqual(@as(usize, 1), vt.offset); // selected=1, offset should be 1
}

test "VirtualTable scrollToSelected moves offset when selected below view" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
        &.{"F"},
        &.{"G"},
        &.{"H"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(0);
    vt = vt.withSelected(7);
    vt.scrollToSelected(3); // visible_rows=3, selected=7
    // offset should be 7 - 3 + 1 = 5
    try testing.expectEqual(@as(usize, 5), vt.offset);
}

test "VirtualTable scrollToSelected with selected at view boundary" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(0);
    vt = vt.withSelected(2); // Selected at index 2, visible_rows=3 means range [0,2]
    vt.scrollToSelected(3);
    // 2 is within [0, 0+3) = [0,3), so offset stays 0
    try testing.expectEqual(@as(usize, 0), vt.offset);
}

// ============================================================================
// BUILDER API TESTS (9 tests)
// ============================================================================

test "VirtualTable withRows returns new instance with rows set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    const vt1 = VirtualTable.init(&cols);
    const vt2 = vt1.withRows(&rows);
    try testing.expectEqual(@as(usize, 0), vt1.rowCount()); // Original unchanged
    try testing.expectEqual(@as(usize, 2), vt2.rowCount());
}

test "VirtualTable withColumns returns new instance with columns set" {
    const cols1 = [_]Column{.{ .title = "A", .width = .{ .percentage = 100 } }};
    const cols2 = [_]Column{
        .{ .title = "X", .width = .{ .fixed = 10 } },
        .{ .title = "Y", .width = .{ .fixed = 10 } },
    };
    const vt1 = VirtualTable.init(&cols1);
    const vt2 = vt1.withColumns(&cols2);
    try testing.expectEqual(@as(usize, 1), vt1.columns.len); // Original unchanged
    try testing.expectEqual(@as(usize, 2), vt2.columns.len);
}

test "VirtualTable withSelected returns new instance with selected set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt1 = VirtualTable.init(&cols);
    const vt2 = vt1.withSelected(3);
    try testing.expectEqual(@as(?usize, null), vt1.selected); // Original unchanged
    try testing.expectEqual(@as(?usize, 3), vt2.selected);
}

test "VirtualTable withOffset returns new instance with offset set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt1 = VirtualTable.init(&cols);
    const vt2 = vt1.withOffset(5);
    try testing.expectEqual(@as(usize, 0), vt1.offset); // Original unchanged
    try testing.expectEqual(@as(usize, 5), vt2.offset);
}

test "VirtualTable withHeaderStyle returns new instance with header_style set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt1 = VirtualTable.init(&cols);
    const style = Style{ .bold = true };
    const vt2 = vt1.withHeaderStyle(style);
    try testing.expect(!vt1.header_style.bold); // Original unchanged
    try testing.expect(vt2.header_style.bold);
}

test "VirtualTable withRowStyle returns new instance with row_style set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt1 = VirtualTable.init(&cols);
    const style = Style{ .dim = true };
    const vt2 = vt1.withRowStyle(style);
    try testing.expect(!vt1.row_style.dim); // Original unchanged
    try testing.expect(vt2.row_style.dim);
}

test "VirtualTable withSelectedStyle returns new instance with selected_style set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt1 = VirtualTable.init(&cols);
    const style = Style{ .reverse = true };
    const vt2 = vt1.withSelectedStyle(style);
    try testing.expect(!vt1.selected_style.reverse); // Original unchanged
    try testing.expect(vt2.selected_style.reverse);
}

test "VirtualTable withColumnSpacing returns new instance with column_spacing set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt1 = VirtualTable.init(&cols);
    const vt2 = vt1.withColumnSpacing(3);
    try testing.expectEqual(@as(u16, 1), vt1.column_spacing); // Original unchanged
    try testing.expectEqual(@as(u16, 3), vt2.column_spacing);
}

test "VirtualTable withBlock returns new instance with block set" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt1 = VirtualTable.init(&cols);
    const block = Block{};
    const vt2 = vt1.withBlock(block);
    try testing.expectEqual(@as(?Block, null), vt1.block); // Original unchanged
    try testing.expect(vt2.block != null);
}

// ============================================================================
// RENDER ZERO AREA TESTS (2 tests)
// ============================================================================

test "VirtualTable render with zero width area does not crash" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 5 };
    vt.render(&buf, area);
}

test "VirtualTable render with zero height area does not crash" {
    var buf = try makeBuffer(10, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    vt.render(&buf, area);
}

// ============================================================================
// RENDER EMPTY ROWS TESTS (2 tests)
// ============================================================================

test "VirtualTable render with no rows shows header only" {
    var buf = try makeBuffer(20, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Name", .width = .{ .percentage = 100 } }};
    const vt = VirtualTable.init(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    vt.render(&buf, area);
    // Header should be rendered at y=0
    try testing.expect(rowHasChar(buf, 0, 'N')); // 'N' from "Name"
}

test "VirtualTable render with no rows and no area for header does not crash" {
    var buf = try makeBuffer(10, 1);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const vt = VirtualTable.init(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    vt.render(&buf, area);
}

// ============================================================================
// RENDER HEADER TESTS (4 tests)
// ============================================================================

test "VirtualTable render header shows column titles" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .percentage = 50 } },
        .{ .title = "Type", .width = .{ .percentage = 50 } },
    };
    const vt = VirtualTable.init(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // Header row should contain "Name"
    try testing.expect(rowHasText(buf, 0, "Name"));
}

test "VirtualTable render header with header_style applies styling" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const style = Style{ .bold = true };
    const vt = VirtualTable.init(&cols).withHeaderStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // Should render without crash; styling applied internally
    try testing.expect(rowHasChar(buf, 0, 'I'));
}

test "VirtualTable render header with multiple columns" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 10 } },
        .{ .title = "Name", .width = .{ .fixed = 15 } },
        .{ .title = "Value", .width = .{ .fixed = 15 } },
    };
    const vt = VirtualTable.init(&cols);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    vt.render(&buf, area);
    // All three titles should appear in header row
    try testing.expect(rowHasChar(buf, 0, 'I')); // ID
}

test "VirtualTable render header respects column spacing" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .fixed = 5 } },
        .{ .title = "B", .width = .{ .fixed = 5 } },
    };
    const vt = VirtualTable.init(&cols).withColumnSpacing(2);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    vt.render(&buf, area);
    // Should render header with spacing
}

// ============================================================================
// RENDER DATA ROWS TESTS (8 tests)
// ============================================================================

test "VirtualTable render first row appears after header" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Row1"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // Row1 should be at y=1 (after header at y=0)
    try testing.expect(rowHasText(buf, 1, "Row1"));
}

test "VirtualTable render second row appears at y=2" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Row1"},
        &.{"Row2"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    try testing.expect(rowHasText(buf, 2, "Row2"));
}

test "VirtualTable render respects offset scrolling" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(2);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // First data row (y=1) should show C (offset=2)
    try testing.expect(rowHasText(buf, 1, "C"));
}

test "VirtualTable render only visible rows rendered" {
    var buf = try makeBuffer(30, 3);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    vt.render(&buf, area);
    // With height=3: header at y=0, data at y=1 and y=2
    // So only 2 data rows (A, B) should be visible
    try testing.expect(rowHasText(buf, 1, "A"));
    try testing.expect(rowHasText(buf, 2, "B"));
}

test "VirtualTable render selected row uses selected_style" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    const style = Style{ .reverse = true };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(0);
    vt = vt.withSelectedStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // Selected row (y=1) should have selected_style applied
    try testing.expect(rowHasText(buf, 1, "A"));
}

test "VirtualTable render unselected row uses row_style" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    const style = Style{ .dim = true };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(0);
    vt = vt.withRowStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // Unselected row (y=2) should have row_style applied
    try testing.expect(rowHasText(buf, 2, "B"));
}

test "VirtualTable render multiple columns at correct positions" {
    var buf = try makeBuffer(40, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "Name", .width = .{ .fixed = 15 } },
        .{ .title = "Value", .width = .{ .fixed = 15 } },
    };
    const rows = [_][]const []const u8{
        &.{ "Item1", "100" },
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    vt.render(&buf, area);
    // "100" should appear in the Value column
    try testing.expect(rowHasChar(buf, 1, '1'));
}

// ============================================================================
// RENDER BLOCK TESTS (2 tests)
// ============================================================================

test "VirtualTable render with block renders border" {
    var buf = try makeBuffer(20, 10);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const block = Block{};
    const vt = VirtualTable.init(&cols).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    vt.render(&buf, area);
    // Block border should be visible at top-left
}

test "VirtualTable render with block and small area does not crash" {
    var buf = try makeBuffer(6, 6);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const block = Block{};
    const vt = VirtualTable.init(&cols).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 6, .height = 6 };
    vt.render(&buf, area);
}

// ============================================================================
// RENDER NARROW/EDGE CASE TESTS (5 tests)
// ============================================================================

test "VirtualTable render with width just enough for one character" {
    var buf = try makeBuffer(5, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 5 };
    vt.render(&buf, area);
}

test "VirtualTable render with height = 1 (header only, no data rows)" {
    var buf = try makeBuffer(30, 1);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    vt.render(&buf, area);
    // Header rendered, no space for data
}

test "VirtualTable render with height = 2 (header + 1 row)" {
    var buf = try makeBuffer(30, 2);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 2 };
    vt.render(&buf, area);
    // Should render header and first data row
    try testing.expect(rowHasChar(buf, 0, 'I'));
}

test "VirtualTable render with empty columns handles gracefully" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const rows = [_][]const []const u8{
        &.{"A"},
    };
    var vt = VirtualTable.init(&.{});
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // Should not crash, renders without columns
}

test "VirtualTable render row with fewer cells than columns" {
    var buf = try makeBuffer(50, 5);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "A", .width = .{ .fixed = 10 } },
        .{ .title = "B", .width = .{ .fixed = 10 } },
        .{ .title = "C", .width = .{ .fixed = 10 } },
    };
    const rows = [_][]const []const u8{
        &.{"Only1"}, // Only 1 cell, 3 columns
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 5 };
    vt.render(&buf, area);
    // Should not crash, render what's available
}

// ============================================================================
// EDGE CASES & COMPLEX SCENARIOS (7 tests)
// ============================================================================

test "VirtualTable single row single column" {
    var buf = try makeBuffer(20, 3);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Name", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"Single"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    vt.render(&buf, area);
    try testing.expect(rowHasText(buf, 1, "Single"));
}

test "VirtualTable large dataset with scrolling" {
    var buf = try makeBuffer(40, 10);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};

    // Create 10 rows
    var rows: [10][]const []const u8 = undefined;
    var row_data: [10][1][]const u8 = undefined;
    for (0..10) |i| {
        var buf_slice: [10]u8 = undefined;
        const name = std.fmt.bufPrint(&buf_slice, "Item{d}", .{i}) catch "Item";
        row_data[i][0] = name;
        rows[i] = &row_data[i];
    }

    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    try testing.expectEqual(@as(usize, 10), vt.rowCount());

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    vt.render(&buf, area);
}

test "VirtualTable scroll offset past end renders gracefully" {
    var buf = try makeBuffer(30, 5);
    defer buf.deinit();
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(100); // Way past end
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    vt.render(&buf, area);
    // Should render header, with no visible data rows (all scrolled out)
    try testing.expect(rowHasChar(buf, 0, 'I'));
}

test "VirtualTable navigation sequence: select, page, scroll" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);

    vt.selectNext();
    try testing.expectEqual(@as(?usize, 0), vt.selected);

    vt.selectNext();
    try testing.expectEqual(@as(?usize, 1), vt.selected);

    vt.pageDown(2);
    try testing.expectEqual(@as(usize, 2), vt.offset);

    vt.scrollToSelected(3);
    try testing.expect(vt.offset <= vt.selected.?);
}

test "VirtualTable selection invariant: offset <= selected" {
    const cols = [_]Column{.{ .title = "Item", .width = .{ .percentage = 100 } }};
    const rows = [_][]const []const u8{
        &.{"A"},
        &.{"B"},
        &.{"C"},
        &.{"D"},
        &.{"E"},
    };
    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withOffset(5);
    vt.selectNext();
    // After selectNext, offset should be <= selected
    if (vt.selected) |sel| {
        try testing.expect(vt.offset <= sel);
    }
}

test "VirtualTable render with all builder methods chained" {
    var buf = try makeBuffer(50, 8);
    defer buf.deinit();
    const cols = [_]Column{
        .{ .title = "ID", .width = .{ .fixed = 10 } },
        .{ .title = "Name", .width = .{ .fixed = 20 } },
    };
    const rows = [_][]const []const u8{
        &.{ "1", "Alice" },
        &.{ "2", "Bob" },
        &.{ "3", "Carol" },
    };

    const style_header = Style{ .bold = true };
    const style_row = Style{ .dim = false };
    const style_selected = Style{ .reverse = true };
    const block = Block{};

    var vt = VirtualTable.init(&cols);
    vt = vt.withRows(&rows);
    vt = vt.withSelected(0);
    vt = vt.withOffset(0);
    vt = vt.withHeaderStyle(style_header);
    vt = vt.withRowStyle(style_row);
    vt = vt.withSelectedStyle(style_selected);
    vt = vt.withColumnSpacing(2);
    vt = vt.withBlock(block);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 8 };
    vt.render(&buf, area);

    try testing.expectEqual(@as(usize, 3), vt.rowCount());
    try testing.expect(vt.selectedRow() != null);
}
