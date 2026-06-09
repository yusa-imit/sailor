//! MultiSelectList Widget Tests — v2.24.0
//!
//! Tests MultiSelectList widget for multi-selection with cursor navigation,
//! selection toggling, and rendering with visual symbols.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;

// Import the multi_select_list module
// Will be accessible via: sailor.tui.multi_select_list (exported from tui.zig)
const multi_select_module = sailor.tui.multi_select_list;
const MultiSelectList = multi_select_module.MultiSelectList;

// ============================================================================
// Test Suite: Initialization and Default State
// ============================================================================

test "MultiSelectList with items and selections initializes correctly" {
    var selections = [_]bool{ false, false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "Item 1", "Item 2", "Item 3" },
        .selections = &selections,
    };
    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expectEqual(@as(usize, 3), list.selections.len);
}

test "MultiSelectList default cursor is 0" {
    var selections = [_]bool{ false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B" },
        .selections = &selections,
    };
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "MultiSelectList default countSelected is 0 when all unselected" {
    var selections = [_]bool{ false, false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    try testing.expectEqual(@as(usize, 0), list.countSelected());
}

// ============================================================================
// Test Suite: moveCursorUp
// ============================================================================

test "moveCursorUp decreases cursor from 2 to 1" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 2,
    };
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

test "moveCursorUp clamps cursor at 0" {
    var selections = [_]bool{ false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B" },
        .selections = &selections,
        .cursor = 0,
    };
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "moveCursorUp from position 1 moves to 0" {
    var selections = [_]bool{ false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B" },
        .selections = &selections,
        .cursor = 1,
    };
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "moveCursorUp on empty items does not crash" {
    var selections: [0]bool = undefined;
    var list = MultiSelectList{
        .items = &[_][]const u8{},
        .selections = &selections,
        .cursor = 0,
    };
    list.moveCursorUp();
    // Should not panic; cursor remains valid
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

// ============================================================================
// Test Suite: moveCursorDown
// ============================================================================

test "moveCursorDown increases cursor from 0 to 1" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 0,
    };
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

test "moveCursorDown clamps cursor at items.len - 1" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 2,
    };
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "moveCursorDown on empty items does not crash" {
    var selections: [0]bool = undefined;
    var list = MultiSelectList{
        .items = &[_][]const u8{},
        .selections = &selections,
        .cursor = 0,
    };
    list.moveCursorDown();
    // Should not panic; cursor remains valid
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

// ============================================================================
// Test Suite: toggleCursor
// ============================================================================

test "toggleCursor changes selections[cursor] from false to true" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 1,
    };
    list.toggleCursor();
    try testing.expect(list.selections[1]);
}

test "toggleCursor changes selections[cursor] from true to false" {
    var selections = [_]bool{ false, true, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 1,
    };
    list.toggleCursor();
    try testing.expect(!list.selections[1]);
}

test "toggleCursor at position 0 toggles selections[0]" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 0,
    };
    list.toggleCursor();
    try testing.expect(list.selections[0]);
}

test "toggleCursor does not move cursor position" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 2,
    };
    list.toggleCursor();
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

// ============================================================================
// Test Suite: selectAll / deselectAll
// ============================================================================

test "selectAll sets all selections to true" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    list.selectAll();
    try testing.expect(list.selections[0]);
    try testing.expect(list.selections[1]);
    try testing.expect(list.selections[2]);
}

test "deselectAll sets all selections to false" {
    var selections = [_]bool{ true, true, true };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    list.deselectAll();
    try testing.expect(!list.selections[0]);
    try testing.expect(!list.selections[1]);
    try testing.expect(!list.selections[2]);
}

test "selectAll on empty items does not crash" {
    var selections: [0]bool = undefined;
    var list = MultiSelectList{
        .items = &[_][]const u8{},
        .selections = &selections,
    };
    list.selectAll();
    // Should not crash
}

test "deselectAll on empty items does not crash" {
    var selections: [0]bool = undefined;
    var list = MultiSelectList{
        .items = &[_][]const u8{},
        .selections = &selections,
    };
    list.deselectAll();
    // Should not crash
}

test "countSelected after selectAll is items.len" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    list.selectAll();
    try testing.expectEqual(@as(usize, 3), list.countSelected());
}

test "countSelected after deselectAll is 0" {
    var selections = [_]bool{ true, true, true };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    list.deselectAll();
    try testing.expectEqual(@as(usize, 0), list.countSelected());
}

// ============================================================================
// Test Suite: countSelected
// ============================================================================

test "countSelected returns 0 when all false" {
    var selections = [_]bool{ false, false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    try testing.expectEqual(@as(usize, 0), list.countSelected());
}

test "countSelected returns 2 when 2 of 3 selected" {
    var selections = [_]bool{ true, false, true };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    try testing.expectEqual(@as(usize, 2), list.countSelected());
}

test "countSelected returns 3 when all true" {
    var selections = [_]bool{ true, true, true };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    try testing.expectEqual(@as(usize, 3), list.countSelected());
}

// ============================================================================
// Test Suite: isSelected
// ============================================================================

test "isSelected returns true for selected item" {
    var selections = [_]bool{ false, true, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    try testing.expect(list.isSelected(1));
}

test "isSelected returns false for unselected item" {
    var selections = [_]bool{ false, true, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };
    try testing.expect(!list.isSelected(0));
}

test "isSelected returns false for out-of-bounds index" {
    var selections = [_]bool{ true, true };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B" },
        .selections = &selections,
    };
    try testing.expect(!list.isSelected(5));
}

// ============================================================================
// Test Suite: render basic
// ============================================================================

test "render on zero-area does not crash" {
    var selections = [_]bool{ false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "Item 1", "Item 2" },
        .selections = &selections,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    list.render(&buf, area);
    // Should not crash or panic
}

test "render on zero-height area does not crash" {
    var selections = [_]bool{ false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "Item 1", "Item 2" },
        .selections = &selections,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    list.render(&buf, area);
    // Should not crash or panic
}

test "render single item writes text to buffer" {
    var selections = [_]bool{ false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "Item", "Other" },
        .selections = &selections,
        .cursor = 1,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // First item (row 0, no cursor) should show unselected_symbol '[ ]' → '[' at col 0
    const cell = buf.getConst(0, 0);
    try testing.expectEqual('[', cell.?.char);
}

test "render cursor symbol appears at cursor row" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 1,
        .cursor_symbol = "> ",
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Row 1 (cursor position) should start with '>'
    const cell = buf.getConst(0, 1);
    try testing.expectEqual('>', cell.?.char);
}

test "render shows unselected_symbol for unselected item" {
    var selections = [_]bool{ false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "Item", "Other" },
        .selections = &selections,
        .unselected_symbol = "[ ] ",
        .cursor = 1,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Item 0 (no cursor) should show unselected_symbol '[ ]' → '[' at col 0
    const cell = buf.getConst(0, 0);
    try testing.expectEqual('[', cell.?.char);
}

test "render shows selected_symbol for selected item" {
    var selections = [_]bool{ true, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "Item", "Other" },
        .selections = &selections,
        .selected_symbol = "[x] ",
        .cursor = 1,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Item 0 (no cursor, selected) should show selected_symbol '[x]' → '[' at col 0
    const cell = buf.getConst(0, 0);
    try testing.expectEqual('[', cell.?.char);
}

test "render cursor on selected item shows cursor symbol" {
    var selections = [_]bool{ false, true, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 1,
        .cursor_symbol = "> ",
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Row 1 (cursor) should show cursor symbol '>'
    const cell = buf.getConst(0, 1);
    try testing.expectEqual('>', cell.?.char);
}

test "render multiple items on separate rows" {
    var selections = [_]bool{ false, false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "First", "Second", "Third" },
        .selections = &selections,
        .unselected_symbol = "",
        .cursor_symbol = "",
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // First item on row 0
    const cell0 = buf.getConst(0, 0);
    try testing.expectEqual('F', cell0.?.char);

    // Second item on row 1
    const cell1 = buf.getConst(0, 1);
    try testing.expectEqual('S', cell1.?.char);

    // Third item on row 2
    const cell2 = buf.getConst(0, 2);
    try testing.expectEqual('T', cell2.?.char);
}

// ============================================================================
// Test Suite: Edge Cases
// ============================================================================

test "single item list cursor stays at 0" {
    var selections = [_]bool{ false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "Only" },
        .selections = &selections,
        .cursor = 0,
    };
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 0), list.cursor);

    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "cursor at last position stays at last position on moveCursorDown" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 2,
    };
    list.moveCursorDown();
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "multiple toggleCursor calls alternate selection state" {
    var selections = [_]bool{ false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "Item" },
        .selections = &selections,
        .cursor = 0,
    };
    list.toggleCursor();
    try testing.expect(list.selections[0]);

    list.toggleCursor();
    try testing.expect(!list.selections[0]);

    list.toggleCursor();
    try testing.expect(list.selections[0]);
}

test "cursor position independent of selection state" {
    var selections = [_]bool{ true, false, true };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 1,
    };
    try testing.expectEqual(@as(usize, 1), list.cursor);
    try testing.expect(!list.selections[1]);
}

test "render with block does not crash" {
    var selections = [_]bool{ false };
    const block = sailor.tui.widgets.Block{};
    var list = MultiSelectList{
        .items = &[_][]const u8{ "Item" },
        .selections = &selections,
        .block = block,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);
    // Should not crash
}

test "selections and items must be same length" {
    var selections = [_]bool{ false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B" },
        .selections = &selections,
    };
    try testing.expectEqual(list.items.len, list.selections.len);
}

test "countSelected with one item selected" {
    var selections = [_]bool{ false, true, false, false };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C", "D" },
        .selections = &selections,
    };
    try testing.expectEqual(@as(usize, 1), list.countSelected());
}

test "render with custom styles does not crash" {
    var selections = [_]bool{ false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "Item" },
        .selections = &selections,
        .cursor_style = .{ .fg = .blue, .bold = true },
        .selected_style = .{ .fg = .cyan },
        .normal_style = .{ .dim = true },
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);
    // Should not crash
}

// ============================================================================
// Test Suite: Navigation Sequences
// ============================================================================

test "cursor navigation down then up returns to original position" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
        .cursor = 0,
    };
    list.moveCursorDown();
    list.moveCursorDown();
    list.moveCursorUp();
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "navigate to end and select all items" {
    var selections = [_]bool{ false, false, false };
    var list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .selections = &selections,
    };

    list.moveCursorDown();
    list.toggleCursor();
    list.moveCursorDown();
    list.toggleCursor();

    try testing.expectEqual(@as(usize, 2), list.countSelected());
}

test "countSelected matches manual selection verification" {
    var selections = [_]bool{ true, false, true, false, true };
    const list = MultiSelectList{
        .items = &[_][]const u8{ "A", "B", "C", "D", "E" },
        .selections = &selections,
    };

    var manual_count: usize = 0;
    for (selections) |sel| {
        if (sel) manual_count += 1;
    }
    try testing.expectEqual(manual_count, list.countSelected());
}
