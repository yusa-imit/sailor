//! EditableTable tests — v2.17.0
//!
//! Tests inline table editing with cell navigation, edit mode, and rendering.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;

const EditableTable = sailor.tui.widgets.EditableTable;
const CellState = sailor.tui.widgets.CellState;

fn makeBuffer(allocator: std.mem.Allocator, w: u16, h: u16) !Buffer {
    return Buffer.init(allocator, w, h);
}

// ============================================================================
// State initialization
// ============================================================================

test "EditableTable default state" {
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
        &[_][]const u8{ "Bob", "25" },
    };
    const table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    try testing.expectEqual(@as(usize, 0), table.selected_row);
    try testing.expectEqual(@as(usize, 0), table.selected_col);
    try testing.expect(!table.is_editing);
    try testing.expectEqual(@as(usize, 0), table.scroll_top);
}

test "EditableTable with fixed col_widths" {
    var col_widths = [_]u16{ 10, 5 };
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
    };
    const table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .col_widths = &col_widths,
    };
    try testing.expectEqual(@as(usize, 2), table.col_widths.len);
    try testing.expectEqual(@as(u16, 10), table.col_widths[0]);
}

// ============================================================================
// Navigation — moveDown
// ============================================================================

test "moveDown — cursor moves to next row" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
        &[_][]const u8{ "B1", "B2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table.moveDown();
    try testing.expectEqual(@as(usize, 1), table.selected_row);
}

test "moveDown — cursor stays at last row" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
        &[_][]const u8{ "B1" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_row = 1,
    };
    table.moveDown();
    try testing.expectEqual(@as(usize, 1), table.selected_row);
}

test "moveDown — multiple times visits all rows" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A" },
        &[_][]const u8{ "B" },
        &[_][]const u8{ "C" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table.moveDown();
    try testing.expectEqual(@as(usize, 1), table.selected_row);
    table.moveDown();
    try testing.expectEqual(@as(usize, 2), table.selected_row);
    table.moveDown();
    try testing.expectEqual(@as(usize, 2), table.selected_row);
}

// ============================================================================
// Navigation — moveUp
// ============================================================================

test "moveUp — cursor moves to previous row" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A" },
        &[_][]const u8{ "B" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_row = 1,
    };
    table.moveUp();
    try testing.expectEqual(@as(usize, 0), table.selected_row);
}

test "moveUp — cursor stays at first row" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A" },
        &[_][]const u8{ "B" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_row = 0,
    };
    table.moveUp();
    try testing.expectEqual(@as(usize, 0), table.selected_row);
}

test "moveUp then moveDown returns to start" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A" },
        &[_][]const u8{ "B" },
        &[_][]const u8{ "C" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_row = 1,
    };
    table.moveUp();
    try testing.expectEqual(@as(usize, 0), table.selected_row);
    table.moveDown();
    try testing.expectEqual(@as(usize, 1), table.selected_row);
}

// ============================================================================
// Navigation — moveRight
// ============================================================================

test "moveRight — cursor moves to next column" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table.moveRight();
    try testing.expectEqual(@as(usize, 1), table.selected_col);
}

test "moveRight — cursor stays at last column" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_col = 1,
    };
    table.moveRight();
    try testing.expectEqual(@as(usize, 1), table.selected_col);
}

test "moveRight — empty headers is safe" {
    var table = EditableTable{
        .headers = &.{},
        .rows = &.{},
    };
    table.moveRight();
    try testing.expectEqual(@as(usize, 0), table.selected_col);
}

// ============================================================================
// Navigation — moveLeft
// ============================================================================

test "moveLeft — cursor moves to previous column" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_col = 1,
    };
    table.moveLeft();
    try testing.expectEqual(@as(usize, 0), table.selected_col);
}

test "moveLeft — cursor stays at first column" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_col = 0,
    };
    table.moveLeft();
    try testing.expectEqual(@as(usize, 0), table.selected_col);
}

// ============================================================================
// Edit mode — startEdit
// ============================================================================

test "startEdit — enters edit mode" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    try testing.expect(!table.is_editing);
    table.startEdit();
    try testing.expect(table.is_editing);
}

test "startEdit — copies cell text to edit buffer" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    const text = table.editText();
    try testing.expectEqualStrings("Alice", text);
}

test "startEdit — clears previous edit buffer" {
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
        &[_][]const u8{ "Bob", "25" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.moveDown();
    table.startEdit();
    const text = table.editText();
    try testing.expectEqualStrings("Bob", text);
}

// ============================================================================
// Edit mode — insertChar
// ============================================================================

test "insertChar — appends character to edit buffer" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.insertChar('A');
    try testing.expectEqualStrings("A", table.editText());
}

test "insertChar — multiple chars build up string" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.insertChar('A');
    table.insertChar('l');
    table.insertChar('i');
    table.insertChar('c');
    table.insertChar('e');
    try testing.expectEqualStrings("Alice", table.editText());
}

test "insertChar — respects buffer length limit" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "" },
    };
    var edit_buf = [_]u8{0} ** 5;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.insertChar('A');
    table.insertChar('B');
    table.insertChar('C');
    table.insertChar('D');
    table.insertChar('E');
    table.insertChar('F'); // Should not fit
    const text = table.editText();
    try testing.expect(text.len <= 5);
}

// ============================================================================
// Edit mode — deleteChar
// ============================================================================

test "deleteChar — removes last character from edit buffer" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.deleteChar();
    try testing.expectEqualStrings("Alic", table.editText());
}

test "deleteChar — multiple times empties buffer" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Hi" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.deleteChar();
    table.deleteChar();
    try testing.expectEqualStrings("", table.editText());
}

test "deleteChar — on empty buffer is safe" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.deleteChar();
    try testing.expectEqualStrings("", table.editText());
}

// ============================================================================
// Edit mode — confirmEdit
// ============================================================================

test "confirmEdit — exits edit mode" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    try testing.expect(table.is_editing);
    table.confirmEdit();
    try testing.expect(!table.is_editing);
}

test "confirmEdit — when not editing is safe" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.confirmEdit();
    try testing.expect(!table.is_editing);
}

// ============================================================================
// Edit mode — cancelEdit
// ============================================================================

test "cancelEdit — exits edit mode" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.cancelEdit();
    try testing.expect(!table.is_editing);
}

test "cancelEdit — when not editing is safe" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.cancelEdit();
    try testing.expect(!table.is_editing);
}

// ============================================================================
// Query — currentCell
// ============================================================================

test "currentCell — returns selected cell text" {
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    const cell = table.currentCell();
    try testing.expect(cell != null);
    try testing.expectEqualStrings("Alice", cell.?);
}

test "currentCell — different positions" {
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
        &[_][]const u8{ "Bob", "25" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table.moveRight();
    const cell = table.currentCell();
    try testing.expect(cell != null);
    try testing.expectEqualStrings("30", cell.?);
}

test "currentCell — null when no rows" {
    var headers = [_][]const u8{ "Name" };
    var table = EditableTable{
        .headers = &headers,
        .rows = &.{},
    };
    const cell = table.currentCell();
    try testing.expect(cell == null);
}

// ============================================================================
// Query — editText
// ============================================================================

test "editText — returns empty string when not editing" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    const text = table.editText();
    try testing.expectEqualStrings("", text);
}

test "editText — returns current edit content when editing" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.insertChar('X');
    const text = table.editText();
    try testing.expectEqualStrings("AliceX", text);
}

// ============================================================================
// Render — edge cases
// ============================================================================

test "render — zero area is safe" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 5 });
}

test "render — zero height is safe" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 0 });
}

test "render — empty rows is safe" {
    var headers = [_][]const u8{ "Col1" };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &.{},
        .edit_buffer = &edit_buf,
    };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
}

test "render — empty headers is safe" {
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &.{},
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
}

// ============================================================================
// Render — styling
// ============================================================================

test "render — selected row uses selected_style" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
        .selected_style = .{ .reverse = true },
    };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
    const cell = buf.get(0, 0);
    try testing.expect(cell.style.reverse);
}

test "render — editing cell uses editing_style" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
        .editing_style = .{ .fg = Color.yellow },
    };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit();
    table.startEdit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
    const cell = buf.get(0, 0);
    try testing.expectEqual(Color.yellow, cell.style.fg);
}

test "render — header row uses header_style" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
        .header_style = .{ .bold = true },
    };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
}

// ============================================================================
// Render — scroll
// ============================================================================

test "render — scroll_top hides top rows" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
        &[_][]const u8{ "B1" },
        &[_][]const u8{ "C1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
        .scroll_top = 1,
    };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
}

test "render — scroll past all content is safe" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
        .scroll_top = 100,
    };
    var buf = try makeBuffer(testing.allocator, 20, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 5 });
}

// ============================================================================
// Builder methods
// ============================================================================

test "withBlock — sets block wrapper" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    const block = Block{ .borders = .all, .title = "Table" };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table = table.withBlock(block);
    try testing.expect(table.block != null);
    try testing.expectEqualStrings("Table", table.block.?.title);
}

test "withScroll — sets scroll position" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table = table.withScroll(5);
    try testing.expectEqual(@as(usize, 5), table.scroll_top);
}
