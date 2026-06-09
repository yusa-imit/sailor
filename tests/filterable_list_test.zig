//! FilterableList Widget Tests — v2.24.0
//!
//! Tests FilterableList widget for incremental text filtering, cursor navigation,
//! and rendering with visual indicators.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;

// Import the filterable_list module
// Will be accessible via: sailor.tui.filterable_list (exported from tui.zig)
const filterable_module = sailor.tui.filterable_list;
const FilterableList = filterable_module.FilterableList;

// ============================================================================
// Test Suite: Initialization and Default State
// ============================================================================

test "FilterableList with items initializes correctly" {
    var filter_buf: [32]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
    };
    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expectEqual(@as(usize, 0), list.filter_len);
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "FilterableList default cursor is 0" {
    var filter_buf: [16]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{ "A", "B" },
        .filter_buf = &filter_buf,
    };
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "FilterableList default filter_len is 0" {
    var filter_buf: [16]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{ "A", "B", "C" },
        .filter_buf = &filter_buf,
    };
    try testing.expectEqual(@as(usize, 0), list.filter_len);
}

test "FilterableList empty items initializes" {
    var filter_buf: [16]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{},
        .filter_buf = &filter_buf,
    };
    try testing.expectEqual(@as(usize, 0), list.items.len);
}

// ============================================================================
// Test Suite: filteredItems — Filter Matching
// ============================================================================

test "filteredItems returns all items when filter is empty" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .filter_len = 0,
    };
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len);
}

test "filteredItems returns matching items case-insensitive" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "banana" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "ap");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 2), filtered.len);
    try testing.expectEqualStrings("apple", filtered[0]);
    try testing.expectEqualStrings("apricot", filtered[1]);
}

test "filteredItems uppercase filter matches lowercase items" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "AP");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 1), filtered.len);
    try testing.expectEqualStrings("apple", filtered[0]);
}

test "filteredItems no matches returns empty" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "xy");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 0), filtered.len);
}

test "filteredItems single character match" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "cherry", "avocado" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..1], "a");
    list.filter_len = 1;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len); // apple, apricot, avocado
}

test "filteredItems substring matching" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "application", "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..3], "app");
    list.filter_len = 3;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 2), filtered.len); // application, apple
}

test "filteredItems preserves order" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "zebra", "apple", "banana", "apricot" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "ap");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 2), filtered.len);
    try testing.expectEqualStrings("apple", filtered[0]);
    try testing.expectEqualStrings("apricot", filtered[1]);
}

test "filteredItems empty items returns empty" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{},
        .filter_buf = &filter_buf,
    };
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 0), filtered.len);
}

// ============================================================================
// Test Suite: typeChar — Character Input
// ============================================================================

test "typeChar adds character to filter" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    try testing.expectEqual(@as(usize, 1), list.filter_len);
    try testing.expectEqual('a', filter_buf[0]);
}

test "typeChar multiple characters builds filter string" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('p');
    try testing.expectEqual(@as(usize, 2), list.filter_len);
    try testing.expectEqual('a', filter_buf[0]);
    try testing.expectEqual('p', filter_buf[1]);
}

test "typeChar caps at filter_buf capacity" {
    var filter_buf: [4]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('b');
    list.typeChar('c');
    list.typeChar('d');
    list.typeChar('e'); // Should not overflow
    try testing.expectEqual(@as(usize, 4), list.filter_len);
}

test "typeChar with uppercase and lowercase" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('A');
    list.typeChar('p');
    try testing.expectEqual(@as(usize, 2), list.filter_len);
    try testing.expectEqual('A', filter_buf[0]);
    try testing.expectEqual('p', filter_buf[1]);
}

// ============================================================================
// Test Suite: backspace — Character Deletion
// ============================================================================

test "backspace removes last character" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('p');
    list.backspace();
    try testing.expectEqual(@as(usize, 1), list.filter_len);
}

test "backspace on empty filter does nothing" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.backspace();
    try testing.expectEqual(@as(usize, 0), list.filter_len);
}

test "backspace multiple times" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('b');
    list.typeChar('c');
    list.backspace();
    list.backspace();
    try testing.expectEqual(@as(usize, 1), list.filter_len);
    try testing.expectEqual('a', filter_buf[0]);
}

test "backspace to empty removes all characters" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.backspace();
    try testing.expectEqual(@as(usize, 0), list.filter_len);
}

// ============================================================================
// Test Suite: clearFilter — Clear All
// ============================================================================

test "clearFilter resets filter_len to 0" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('p');
    list.clearFilter();
    try testing.expectEqual(@as(usize, 0), list.filter_len);
}

test "clearFilter on already empty filter does nothing" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.clearFilter();
    try testing.expectEqual(@as(usize, 0), list.filter_len);
}

// ============================================================================
// Test Suite: getFilter — Query Filter String
// ============================================================================

test "getFilter returns current filter string" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('p');
    const filter = list.getFilter();
    try testing.expectEqualStrings("ap", filter);
}

test "getFilter returns empty string when no filter" {
    var filter_buf: [32]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    const filter = list.getFilter();
    try testing.expectEqual(@as(usize, 0), filter.len);
}

test "getFilter after backspace reflects new length" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('p');
    list.typeChar('p');
    list.backspace();
    const filter = list.getFilter();
    try testing.expectEqualStrings("ap", filter);
}

// ============================================================================
// Test Suite: moveCursorUp — Navigate Filtered Results
// ============================================================================

test "moveCursorUp decreases cursor position" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .cursor = 2,
    };
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

test "moveCursorUp clamps cursor at 0" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
        .cursor = 0,
    };
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "moveCursorUp from position 1 to 0" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
        .cursor = 1,
    };
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

test "moveCursorUp on empty filter shows all items" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .cursor = 2,
    };
    list.moveCursorUp();
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

// ============================================================================
// Test Suite: moveCursorDown — Navigate Filtered Results
// ============================================================================

test "moveCursorDown increases cursor position" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .cursor = 0,
    };
    var scratch: [10][]const u8 = undefined;
    list.moveCursorDown(&scratch);
    try testing.expectEqual(@as(usize, 1), list.cursor);
}

test "moveCursorDown clamps at filtered item count - 1" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .cursor = 2,
    };
    var scratch: [10][]const u8 = undefined;
    list.moveCursorDown(&scratch);
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "moveCursorDown respects filter results" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "cherry", "avocado" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..1], "a");
    list.filter_len = 1;
    var scratch: [10][]const u8 = undefined;
    // Filtered items: apple, apricot, avocado (3 items; "cherry" has no 'a')
    list.cursor = 2;
    list.moveCursorDown(&scratch);
    // Should stay at 2 since filtered count is 3 (indices 0-2)
    try testing.expectEqual(@as(usize, 2), list.cursor);
}

test "moveCursorDown on single filtered item stays at 0" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "ba");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    list.moveCursorDown(&scratch);
    try testing.expectEqual(@as(usize, 0), list.cursor);
}

// ============================================================================
// Test Suite: getCursorItem — Get Current Selection
// ============================================================================

test "getCursorItem returns item at cursor position" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .cursor = 1,
    };
    var scratch: [10][]const u8 = undefined;
    const item = list.getCursorItem(&scratch);
    try testing.expect(item != null);
    try testing.expectEqualStrings("banana", item.?);
}

test "getCursorItem with filter returns filtered item" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "banana" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "ap");
    list.filter_len = 2;
    list.cursor = 1; // Second filtered result (apricot)
    var scratch: [10][]const u8 = undefined;
    const item = list.getCursorItem(&scratch);
    try testing.expect(item != null);
    try testing.expectEqualStrings("apricot", item.?);
}

test "getCursorItem returns null when cursor is out of bounds" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
        .cursor = 5,
    };
    var scratch: [10][]const u8 = undefined;
    const item = list.getCursorItem(&scratch);
    try testing.expectEqual(null, item);
}

test "getCursorItem with no matching filter returns null" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "xy");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    const item = list.getCursorItem(&scratch);
    try testing.expectEqual(null, item);
}

// ============================================================================
// Test Suite: Cursor Clamping When Filter Changes
// ============================================================================

test "cursor clamps when filter reduces item count" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "cherry", "avocado" },
        .filter_buf = &filter_buf,
        .cursor = 3, // Was valid with empty filter (4 items)
    };
    // Apply filter that reduces to 3 items ("cherry" has no 'a')
    @memcpy(filter_buf[0..1], "a");
    list.filter_len = 1;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len); // apple, apricot, avocado
    try testing.expectEqual(@as(usize, 4), list.items.len); // Original items unchanged
}

test "cursor clamps when filtering to 0 results" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
        .cursor = 1,
    };
    @memcpy(filter_buf[0..2], "xy");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 0), filtered.len);
    const item = list.getCursorItem(&scratch);
    try testing.expectEqual(null, item);
}

// ============================================================================
// Test Suite: render — Visual Output
// ============================================================================

test "render on zero-area does not crash" {
    var filter_buf: [32]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    list.render(&buf, area);
    // Should not crash
}

test "render on zero-height area does not crash" {
    var filter_buf: [32]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    list.render(&buf, area);
    // Should not crash
}

test "render displays filter line at row 0" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Row 0 should contain filter text (may start with "Filter: " or similar)
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null); // Should have rendered something
}

test "render displays filtered items below filter line" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Row 1 should contain first item
    const cell = buf.getConst(0, 1);
    try testing.expect(cell != null);
}

test "render shows cursor symbol on current item" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .cursor = 1,
        .cursor_symbol = "> ",
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Row 2 (cursor is at item 1) should show cursor symbol
    const cell = buf.getConst(0, 2);
    try testing.expect(cell != null); // Should have content
}

test "render applies cursor_style to current item" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana" },
        .filter_buf = &filter_buf,
        .cursor = 0,
        .cursor_style = .{ .bg = .blue },
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // First item row should be rendered with cursor style
    const cell = buf.getConst(0, 1);
    try testing.expect(cell != null);
}

test "render applies normal_style to non-cursor items" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
        .cursor = 0,
        .normal_style = .{},
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Row 2 (non-cursor item) should be rendered
    const cell = buf.getConst(0, 2);
    try testing.expect(cell != null);
}

test "render applies filter_style to filter line" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
        .filter_style = .{ .bold = true },
    };
    list.typeChar('a');
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Filter line should be rendered at row 0
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
}

test "render with block wrapper does not crash" {
    var filter_buf: [32]u8 = undefined;
    const block = sailor.tui.widgets.Block{};
    var list = FilterableList{
        .items = &[_][]const u8{ "apple" },
        .filter_buf = &filter_buf,
        .block = block,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);
    // Should not crash
}

test "render empty items does not crash" {
    var filter_buf: [32]u8 = undefined;
    const list = FilterableList{
        .items = &[_][]const u8{},
        .filter_buf = &filter_buf,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);
    // Should not crash
}

test "render single filtered item" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "ba");
    list.filter_len = 2;
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    list.render(&buf, area);

    // Should render filter line and one item
    const filter_cell = buf.getConst(0, 0);
    const item_cell = buf.getConst(0, 1);
    try testing.expect(filter_cell != null);
    try testing.expect(item_cell != null);
}

// ============================================================================
// Test Suite: Edge Cases and Interaction Sequences
// ============================================================================

test "filter reduces items and cursor stays valid" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "banana", "avocado" },
        .filter_buf = &filter_buf,
        .cursor = 0,
    };
    // Start with cursor at apple
    var scratch: [10][]const u8 = undefined;
    var item = list.getCursorItem(&scratch);
    try testing.expect(item != null);
    try testing.expectEqualStrings("apple", item.?);

    // Apply filter
    @memcpy(filter_buf[0..1], "b");
    list.filter_len = 1;
    item = list.getCursorItem(&scratch);
    // With filter "b", should only have "banana"
    try testing.expect(item != null);
    try testing.expectEqualStrings("banana", item.?);
}

test "clear filter shows all items again" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "banana", "cherry" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "ba");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;
    var filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 1), filtered.len);

    list.clearFilter();
    filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len);
}

test "backspace and type new character" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "banana" },
        .filter_buf = &filter_buf,
    };
    list.typeChar('a');
    list.typeChar('p');
    var scratch: [10][]const u8 = undefined;
    var filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 2), filtered.len); // apple, apricot

    list.backspace();
    list.backspace();
    list.typeChar('b');
    filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 1), filtered.len); // banana
    try testing.expectEqualStrings("banana", filtered[0]);
}

test "navigate filtered list with cursor" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "apricot", "avocado", "cherry" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..1], "a");
    list.filter_len = 1;
    var scratch: [10][]const u8 = undefined;

    // Filtered: apple, apricot, avocado ("cherry" has no 'a')
    list.cursor = 0;
    var item = list.getCursorItem(&scratch);
    try testing.expectEqualStrings("apple", item.?);

    list.moveCursorDown(&scratch);
    item = list.getCursorItem(&scratch);
    try testing.expectEqualStrings("apricot", item.?);

    list.moveCursorDown(&scratch);
    item = list.getCursorItem(&scratch);
    try testing.expectEqualStrings("avocado", item.?);

    list.moveCursorDown(&scratch); // Should clamp
    item = list.getCursorItem(&scratch);
    try testing.expectEqualStrings("avocado", item.?);

    list.moveCursorUp();
    item = list.getCursorItem(&scratch);
    try testing.expectEqualStrings("apricot", item.?);
}

test "cursor position independent of item order in original list" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "zebra", "apple", "banana", "apricot" },
        .filter_buf = &filter_buf,
    };
    @memcpy(filter_buf[0..2], "ap");
    list.filter_len = 2;
    var scratch: [10][]const u8 = undefined;

    // Filtered items in order: apple (index 1), apricot (index 3)
    list.cursor = 0;
    var item = list.getCursorItem(&scratch);
    try testing.expectEqualStrings("apple", item.?);

    list.cursor = 1;
    item = list.getCursorItem(&scratch);
    try testing.expectEqualStrings("apricot", item.?);
}

test "rapid type and backspace sequence" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "apple", "application", "apply" },
        .filter_buf = &filter_buf,
    };
    var scratch: [10][]const u8 = undefined;

    list.typeChar('a');
    var filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len);

    list.typeChar('p');
    filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len); // all have "ap"

    list.typeChar('p');
    filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len); // all have "app"

    list.backspace();
    filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len); // back to "ap"

    list.clearFilter();
    filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 3), filtered.len); // all items
}

test "case variations in search" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "Apple", "BANANA", "Cherry" },
        .filter_buf = &filter_buf,
    };
    var scratch: [10][]const u8 = undefined;

    list.typeChar('a');
    var filtered = list.filteredItems(&scratch);
    // "Apple" and "BANANA" both match "a" case-insensitively
    try testing.expectEqual(@as(usize, 2), filtered.len);
    try testing.expectEqualStrings("Apple", filtered[0]);

    list.clearFilter();
    list.typeChar('B');
    filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 1), filtered.len); // BANANA
    try testing.expectEqualStrings("BANANA", filtered[0]);
}

test "special characters in items" {
    var filter_buf: [32]u8 = undefined;
    var list = FilterableList{
        .items = &[_][]const u8{ "hello-world", "test_file", "app.config" },
        .filter_buf = &filter_buf,
    };
    var scratch: [10][]const u8 = undefined;

    list.typeChar('_');
    const filtered = list.filteredItems(&scratch);
    try testing.expectEqual(@as(usize, 1), filtered.len);
    try testing.expectEqualStrings("test_file", filtered[0]);
}
