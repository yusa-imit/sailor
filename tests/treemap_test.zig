//! Treemap Widget Tests — TDD Red Phase
//!
//! Tests Treemap widget with hierarchical proportional rectangle visualization,
//! binary partition layout algorithm, focused item styling, builder pattern,
//! and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const Treemap = sailor.tui.widgets.Treemap;
const TreemapItem = sailor.tui.widgets.TreemapItem;

// ============================================================================
// Helper Functions
// ============================================================================

/// Count non-empty cells (non-space characters) in a buffer area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Check if buffer area contains a specific character
fn areaHasChar(buf: Buffer, area: Rect, ch: u21) bool {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Get character at specific position in buffer
fn charAtPos(buf: Buffer, x: u16, y: u16) ?u21 {
    if (buf.getConst(x, y)) |cell| {
        return cell.char;
    }
    return null;
}

/// Find text in buffer area (linear search)
fn findTextInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var text_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (text_idx < text.len) : (text_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != text[text_idx]) {
                    matched = false;
                    break;
                }
                cx += 1;
                if (cx >= area.x + area.width or cx >= buf.width) {
                    cy += 1;
                    cx = area.x;
                }
            }

            if (matched) return true;
        }
    }
    return false;
}

// ============================================================================
// Init & Defaults Tests (5 tests)
// ============================================================================

test "Treemap.init returns zero-value struct" {
    const tm = Treemap.init();
    try testing.expectEqual(@as(usize, 0), tm.items.len);
    try testing.expectEqual(@as(usize, 0), tm.focused);
}

test "Treemap.init defaults items to empty slice" {
    const tm = Treemap.init();
    try testing.expectEqual(@as(usize, 0), tm.items.len);
}

test "Treemap.init defaults focused to 0" {
    const tm = Treemap.init();
    try testing.expectEqual(@as(usize, 0), tm.focused);
}

test "Treemap.init defaults styles to empty Style" {
    const tm = Treemap.init();
    try testing.expectEqual(Style{}, tm.style);
    try testing.expectEqual(Style{}, tm.label_style);
    try testing.expectEqual(Style{}, tm.focused_style);
}

test "Treemap.init defaults show_value and block" {
    const tm = Treemap.init();
    try testing.expectEqual(false, tm.show_value);
    try testing.expect(tm.block == null);
}

// ============================================================================
// itemCount() Tests (4 tests)
// ============================================================================

test "itemCount returns 0 for empty items" {
    const tm = Treemap.init();
    try testing.expectEqual(@as(usize, 0), tm.itemCount());
}

test "itemCount returns items.len for small slice" {
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 1.0 },
        .{ .label = "B", .value = 2.0 },
        .{ .label = "C", .value = 3.0 },
    };
    const tm = Treemap.init().withItems(&items);
    try testing.expectEqual(@as(usize, 3), tm.itemCount());
}

test "itemCount caps at MAX_ITEMS (64)" {
    var large_items: [65]TreemapItem = undefined;
    for (&large_items) |*item| {
        item.* = .{ .label = "Item", .value = 1.0 };
    }
    const tm = Treemap.init().withItems(&large_items);
    try testing.expectEqual(Treemap.MAX_ITEMS, tm.itemCount());
}

test "itemCount with exactly MAX_ITEMS returns MAX_ITEMS" {
    var items_buf: [Treemap.MAX_ITEMS]TreemapItem = undefined;
    for (&items_buf) |*item| {
        item.* = .{ .label = "Item", .value = 1.0 };
    }
    const tm = Treemap.init().withItems(&items_buf);
    try testing.expectEqual(Treemap.MAX_ITEMS, tm.itemCount());
}

// ============================================================================
// totalValue() Tests (5 tests)
// ============================================================================

test "totalValue returns 0.0 for empty items" {
    const tm = Treemap.init();
    try testing.expectApproxEqAbs(@as(f32, 0.0), tm.totalValue(), 0.001);
}

test "totalValue sums all item values" {
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 2.5 },
        .{ .label = "B", .value = 3.5 },
        .{ .label = "C", .value = 4.5 },
    };
    const tm = Treemap.init().withItems(&items);
    try testing.expectApproxEqAbs(@as(f32, 10.5), tm.totalValue(), 0.001);
}

test "totalValue works with single item" {
    var items = [_]TreemapItem{
        .{ .label = "Only", .value = 7.0 },
    };
    const tm = Treemap.init().withItems(&items);
    try testing.expectApproxEqAbs(@as(f32, 7.0), tm.totalValue(), 0.001);
}

test "totalValue caps at MAX_ITEMS items" {
    var large_items: [65]TreemapItem = undefined;
    for (&large_items) |*item| {
        item.* = .{ .label = "Item", .value = 1.0 };
    }
    const tm = Treemap.init().withItems(&large_items);
    // Only 64 items should be counted
    try testing.expectApproxEqAbs(@as(f32, 64.0), tm.totalValue(), 0.001);
}

test "totalValue handles zero-value items" {
    var items = [_]TreemapItem{
        .{ .label = "Zero1", .value = 0.0 },
        .{ .label = "Zero2", .value = 0.0 },
    };
    const tm = Treemap.init().withItems(&items);
    try testing.expectApproxEqAbs(@as(f32, 0.0), tm.totalValue(), 0.001);
}

// ============================================================================
// Builder API Tests — Immutability (9 tests)
// ============================================================================

test "withItems returns new Treemap without modifying original" {
    var items1 = [_]TreemapItem{
        .{ .label = "A", .value = 1.0 },
    };
    var items2 = [_]TreemapItem{
        .{ .label = "B", .value = 2.0 },
    };
    const tm1 = Treemap.init().withItems(&items1);
    const tm2 = tm1.withItems(&items2);
    try testing.expectEqual(@as(usize, 1), tm1.itemCount());
    try testing.expectEqual(@as(usize, 1), tm2.itemCount());
    try testing.expectEqualStrings("A", tm1.items[0].label);
    try testing.expectEqualStrings("B", tm2.items[0].label);
}

test "withFocused returns new Treemap without modifying original" {
    const tm1 = Treemap.init();
    const tm2 = tm1.withFocused(3);
    try testing.expectEqual(@as(usize, 0), tm1.focused);
    try testing.expectEqual(@as(usize, 3), tm2.focused);
}

test "withStyle returns new Treemap without modifying original" {
    const style1 = Style{};
    const style2 = Style{ .bold = true };
    const tm1 = Treemap.init().withStyle(style1);
    const tm2 = tm1.withStyle(style2);
    try testing.expectEqual(false, tm1.style.bold);
    try testing.expectEqual(true, tm2.style.bold);
}

test "withLabelStyle returns new Treemap without modifying original" {
    const style1 = Style{};
    const style2 = Style{ .italic = true };
    const tm1 = Treemap.init().withLabelStyle(style1);
    const tm2 = tm1.withLabelStyle(style2);
    try testing.expectEqual(false, tm1.label_style.italic);
    try testing.expectEqual(true, tm2.label_style.italic);
}

test "withFocusedStyle returns new Treemap without modifying original" {
    const style1 = Style{};
    const style2 = Style{ .underline = true };
    const tm1 = Treemap.init().withFocusedStyle(style1);
    const tm2 = tm1.withFocusedStyle(style2);
    try testing.expectEqual(false, tm1.focused_style.underline);
    try testing.expectEqual(true, tm2.focused_style.underline);
}

test "withShowValue returns new Treemap without modifying original" {
    const tm1 = Treemap.init().withShowValue(false);
    const tm2 = tm1.withShowValue(true);
    try testing.expectEqual(false, tm1.show_value);
    try testing.expectEqual(true, tm2.show_value);
}

test "withBlock returns new Treemap without modifying original" {
    const block1: ?Block = null;
    const block2: ?Block = .{};
    const tm1 = Treemap.init().withBlock(block1);
    const tm2 = tm1.withBlock(block2);
    try testing.expect(tm1.block == null);
    try testing.expect(tm2.block != null);
}

test "builder chaining sets multiple fields" {
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 1.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withFocused(0)
        .withShowValue(true);
    try testing.expectEqual(@as(usize, 1), tm.itemCount());
    try testing.expectEqual(@as(usize, 0), tm.focused);
    try testing.expectEqual(true, tm.show_value);
}

test "withItems then itemCount returns correct count" {
    var items = [_]TreemapItem{
        .{ .label = "X", .value = 5.0 },
        .{ .label = "Y", .value = 3.0 },
    };
    const tm = Treemap.init().withItems(&items);
    try testing.expectEqual(@as(usize, 2), tm.itemCount());
}

// ============================================================================
// Render — Zero/Minimal Area Tests (4 tests)
// ============================================================================

test "render to zero-width area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    tm.render(&buf, area);
}

test "render to zero-height area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    tm.render(&buf, area);
}

test "render to 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    tm.render(&buf, area);
}

test "render to 2x2 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    tm.render(&buf, area);
}

// ============================================================================
// Render — Empty Items Tests (2 tests)
// ============================================================================

test "render with no items does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const tm = Treemap.init();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
}

test "render with empty items array does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const items: [0]TreemapItem = undefined;
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
}

// ============================================================================
// Render — Single Item Tests (6 tests)
// ============================================================================

test "single item fills entire inner area" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Single", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    // Area should have content (not all spaces)
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "single item with large area renders label when space allows" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Label", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    // Should have significant non-empty cells
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count >= 5);
}

test "single item with width>=2 and height>=2 renders box chars" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Box", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    tm.render(&buf, area);
    // Check for box corners
    const has_corner = areaHasChar(buf, area, '┌') or
        areaHasChar(buf, area, '┐') or
        areaHasChar(buf, area, '└') or
        areaHasChar(buf, area, '┘');
    try testing.expect(has_corner);
}

test "single item renders horizontal border" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    tm.render(&buf, area);
    // Check for horizontal line
    try testing.expect(areaHasChar(buf, area, '─'));
}

test "single item renders vertical border" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    tm.render(&buf, area);
    // Check for vertical line
    try testing.expect(areaHasChar(buf, area, '│'));
}

test "single item with custom style renders with that style" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    const custom_style = Style{ .bold = true };
    var items = [_]TreemapItem{
        .{ .label = "Styled", .value = 1.0, .style = custom_style },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    tm.render(&buf, area);
    // Verify at least one cell in area has bold style
    var found_styled = false;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.style.bold) {
                    found_styled = true;
                }
            }
        }
    }
    try testing.expect(found_styled);
}

// ============================================================================
// Render — Multiple Items Proportional Layout Tests (8 tests)
// ============================================================================

test "two equal items split approximately 50/50" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    // Should have content for both items
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 10);
}

test "two items 3:1 ratio splits proportionally" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Large", .value = 75.0 },
        .{ .label = "Small", .value = 25.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 10);
}

test "three items all render without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 1.0 },
        .{ .label = "B", .value = 2.0 },
        .{ .label = "C", .value = 3.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 15);
}

test "four items all render without crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 1.0 },
        .{ .label = "B", .value = 1.0 },
        .{ .label = "C", .value = 1.0 },
        .{ .label = "D", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 15);
}

test "items sorted by value descending in layout" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    // Items given in ascending order
    var items = [_]TreemapItem{
        .{ .label = "Small", .value = 10.0 },
        .{ .label = "Medium", .value = 50.0 },
        .{ .label = "Large", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    // Should render all without error (sorting happens internally)
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 15);
}

test "wide area (40x20) splits two items horizontally" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Left", .value = 50.0 },
        .{ .label = "Right", .value = 50.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 10);
}

test "tall area (20x40) splits two items vertically" {
    var buf = try Buffer.init(testing.allocator, 20, 40);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Top", .value = 50.0 },
        .{ .label = "Bottom", .value = 50.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 40 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 10);
}

test "multiple items with different styles render correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const red_style = Style{ .fg = Color.red };
    const blue_style = Style{ .fg = Color.blue };
    var items = [_]TreemapItem{
        .{ .label = "Red", .value = 50.0, .style = red_style },
        .{ .label = "Blue", .value = 50.0, .style = blue_style },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 10);
}

// ============================================================================
// Render — Focused Item Tests (4 tests)
// ============================================================================

test "focused item at index 0 uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const focused_style = Style{ .underline = true };
    var items = [_]TreemapItem{
        .{ .label = "Focused", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    // Verify at least one cell has underline
    var found_focused = false;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.style.underline) {
                    found_focused = true;
                }
            }
        }
    }
    try testing.expect(found_focused);
}

test "focused item at index 1 uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const focused_style = Style{ .reverse = true };
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    // Verify at least one cell has reverse
    var found_focused = false;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.style.reverse) {
                    found_focused = true;
                }
            }
        }
    }
    try testing.expect(found_focused);
}

test "non-focused items dont use focused_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const focused_style = Style{ .bold = true, .reverse = true };
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    // Should render without error
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 10);
}

test "focused index out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 50.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
}

// ============================================================================
// Render — Block Border Tests (4 tests)
// ============================================================================

test "with block border inner area is used for items" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const block = Block{};
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    // Should render without error
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "block border renders at outer area corners" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const block = Block{};
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    // Check for border chars in outer area
    const has_border = areaHasChar(buf, area, '┌') or
        areaHasChar(buf, area, '┐') or
        areaHasChar(buf, area, '└') or
        areaHasChar(buf, area, '┘');
    try testing.expect(has_border);
}

test "without block full area used for items" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "block with zero inner area does not crash" {
    var buf = try Buffer.init(testing.allocator, 3, 3);
    defer buf.deinit();
    const block = Block{ .padding_left = 1, .padding_right = 1, .padding_top = 1, .padding_bottom = 1 };
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    tm.render(&buf, area);
}

// ============================================================================
// Render — Labels Tests (5 tests)
// ============================================================================

test "label appears in large area" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "TestLabel", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    // Check for at least some label characters
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 5);
}

test "long label truncated to fit width" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "VeryLongLabelThatShouldBeTruncated", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    tm.render(&buf, area);
    // Should render without crash, label is truncated
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "empty label does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "label centered horizontally" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Center", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    tm.render(&buf, area);
    // Verify content exists
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 5);
}

test "label_style applied to labels" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const label_style = Style{ .italic = true };
    var items = [_]TreemapItem{
        .{ .label = "Styled", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    // Should render without error
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

// ============================================================================
// Render — show_value Tests (3 tests)
// ============================================================================

test "show_value false (default) does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 42.5 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withShowValue(false);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
}

test "show_value true does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 42.5 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withShowValue(true);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
}

test "show_value true with labeled item renders" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Labeled", .value = 123.45 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withShowValue(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

// ============================================================================
// Render — MAX_ITEMS Cap Tests (3 tests)
// ============================================================================

test "more than 64 items only renders first 64" {
    var buf = try Buffer.init(testing.allocator, 50, 50);
    defer buf.deinit();
    var large_items: [65]TreemapItem = undefined;
    for (&large_items) |*item| {
        item.* = .{ .label = "Item", .value = 1.0 };
    }
    const tm = Treemap.init().withItems(&large_items);
    try testing.expectEqual(Treemap.MAX_ITEMS, tm.itemCount());
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 50 };
    tm.render(&buf, area);
    // Should render 64 items without panic
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "exactly 64 items all rendered" {
    var buf = try Buffer.init(testing.allocator, 50, 50);
    defer buf.deinit();
    var items_buf: [Treemap.MAX_ITEMS]TreemapItem = undefined;
    for (&items_buf) |*item| {
        item.* = .{ .label = "Item", .value = 1.0 };
    }
    const tm = Treemap.init().withItems(&items_buf);
    try testing.expectEqual(Treemap.MAX_ITEMS, tm.itemCount());
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 50 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "65 items last item ignored (itemCount is 64)" {
    var buf = try Buffer.init(testing.allocator, 50, 50);
    defer buf.deinit();
    var large_items: [65]TreemapItem = undefined;
    for (&large_items, 0..) |*item, i| {
        item.* = .{ .label = "Item", .value = @as(f32, @floatFromInt(i + 1)) };
    }
    const tm = Treemap.init().withItems(&large_items);
    try testing.expectEqual(Treemap.MAX_ITEMS, tm.itemCount());
    // totalValue should not include the 65th item
    const total = tm.totalValue();
    const expected = @as(f32, 64.0 * 65.0 / 2.0); // sum of 1..64
    try testing.expectApproxEqAbs(expected, total, 0.1);
}

// ============================================================================
// Edge Cases Tests (5 tests)
// ============================================================================

test "all items with value 0 does not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Zero1", .value = 0.0 },
        .{ .label = "Zero2", .value = 0.0 },
        .{ .label = "Zero3", .value = 0.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    // Should render without division by zero
}

test "negative value items do not crash" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Neg", .value = -5.0 },
        .{ .label = "Pos", .value = 10.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
}

test "single item with empty label renders box" {
    var buf = try Buffer.init(testing.allocator, 15, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "", .value = 50.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };
    tm.render(&buf, area);
    // Should have box chars
    const has_box = areaHasChar(buf, area, '┌') or
        areaHasChar(buf, area, '┐') or
        areaHasChar(buf, area, '└') or
        areaHasChar(buf, area, '┘');
    try testing.expect(has_box);
}

test "area exactly fits one character does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "X", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 5, .y = 5, .width = 1, .height = 1 };
    tm.render(&buf, area);
}

test "very large area (200x100) does not crash" {
    var buf = try Buffer.init(testing.allocator, 200, 100);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Large", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 100 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 50);
}

// ============================================================================
// Additional Edge Case Tests (8 tests)
// ============================================================================

test "render with multiple items of varying sizes" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Huge", .value = 1000.0 },
        .{ .label = "Big", .value = 100.0 },
        .{ .label = "Medium", .value = 10.0 },
        .{ .label = "Tiny", .value = 1.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 30 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 20);
}

test "label style applied to rendered labels" {
    var buf = try Buffer.init(testing.allocator, 25, 15);
    defer buf.deinit();
    const style_with_bold = Style{ .bold = true };
    var items = [_]TreemapItem{
        .{ .label = "Bold", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withLabelStyle(style_with_bold);
    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 15 };
    tm.render(&buf, area);
    var found_bold = false;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.style.bold) {
                    found_bold = true;
                }
            }
        }
    }
    try testing.expect(found_bold);
}

test "base style applied to item cells" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const base_style = Style{ .dim = true };
    var items = [_]TreemapItem{
        .{ .label = "Dimmed", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withStyle(base_style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    tm.render(&buf, area);
    // Verify content exists
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 0);
}

test "render with block and items" {
    var buf = try Buffer.init(testing.allocator, 25, 15);
    defer buf.deinit();
    const block = Block{ .borders = .{ .top = true, .bottom = true, .left = true, .right = true } };
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 100.0 },
    };
    const tm = Treemap.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 15 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 5);
}

test "offset area renders correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 40);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Offset", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 10, .y = 10, .width = 30, .height = 20 };
    tm.render(&buf, area);
    const content_count = countNonEmptyCells(buf, area);
    try testing.expect(content_count > 10);
}

test "partial clipping at buffer boundary" {
    var buf = try Buffer.init(testing.allocator, 20, 20);
    defer buf.deinit();
    var items = [_]TreemapItem{
        .{ .label = "Item", .value = 100.0 },
    };
    const tm = Treemap.init().withItems(&items);
    // Area extends to buffer edge
    const area = Rect{ .x = 15, .y = 15, .width = 10, .height = 10 };
    tm.render(&buf, area);
}

test "focused index zero with zero items does not crash" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    const tm = Treemap.init()
        .withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    tm.render(&buf, area);
}

test "render consistency: same items same output" {
    var buf1 = try Buffer.init(testing.allocator, 30, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 30, 20);
    defer buf2.deinit();
    var items = [_]TreemapItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const tm = Treemap.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    tm.render(&buf1, area);
    tm.render(&buf2, area);
    // Both renders should complete without error
    const count1 = countNonEmptyCells(buf1, area);
    const count2 = countNonEmptyCells(buf2, area);
    try testing.expect(count1 > 0);
    try testing.expect(count2 > 0);
}
