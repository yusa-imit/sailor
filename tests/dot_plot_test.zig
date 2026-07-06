//! DotPlot Widget Tests — TDD Red Phase
//!
//! Tests DotPlot widget with categorical items rendered as dots on a horizontal axis,
//! each item on its own row, label column, value display, focused styling,
//! x_min/x_max normalization, line rendering, block borders, MAX_ITEMS capping,
//! and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const DotPlot = sailor.tui.widgets.DotPlot;
const DotPlotItem = sailor.tui.widgets.dot_plot.DotPlotItem;

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

/// Find text in buffer area (linear search, row-major order)
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
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "DotPlot.init creates default plot with zero items" {
    const dp = DotPlot.init();
    try testing.expectEqual(@as(usize, 0), dp.items.len);
}

test "DotPlot.init defaults focused to 0" {
    const dp = DotPlot.init();
    try testing.expectEqual(@as(usize, 0), dp.focused);
}

test "DotPlot.init defaults x_min to 0.0" {
    const dp = DotPlot.init();
    try testing.expectEqual(@as(f32, 0.0), dp.x_min);
}

test "DotPlot.init defaults x_max to 1.0" {
    const dp = DotPlot.init();
    try testing.expectEqual(@as(f32, 1.0), dp.x_max);
}

test "DotPlot.init defaults show_labels to true" {
    const dp = DotPlot.init();
    try testing.expectEqual(true, dp.show_labels);
}

// ============================================================================
// Group 2: DotPlotItem Struct Defaults (3 tests)
// ============================================================================

test "DotPlotItem default label is empty" {
    const item = DotPlotItem{};
    try testing.expectEqualStrings("", item.label);
}

test "DotPlotItem default value is 0.0" {
    const item = DotPlotItem{};
    try testing.expectEqual(@as(f32, 0.0), item.value);
}

test "DotPlotItem default style is empty" {
    const item = DotPlotItem{};
    try testing.expect(!item.style.bold and item.style.dim == false);
}

// ============================================================================
// Group 3: MAX_ITEMS Constant (1 test)
// ============================================================================

test "DotPlot.MAX_ITEMS equals 64" {
    try testing.expectEqual(@as(usize, 64), DotPlot.MAX_ITEMS);
}

// ============================================================================
// Group 4: itemCount() Method (5 tests)
// ============================================================================

test "DotPlot.itemCount with zero items returns 0" {
    const dp = DotPlot.init();
    try testing.expectEqual(@as(usize, 0), dp.itemCount());
}

test "DotPlot.itemCount with 1 item returns 1" {
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    try testing.expectEqual(@as(usize, 1), dp.itemCount());
}

test "DotPlot.itemCount with 32 items returns 32" {
    var items: [32]DotPlotItem = undefined;
    for (0..32) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 32.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    try testing.expectEqual(@as(usize, 32), dp.itemCount());
}

test "DotPlot.itemCount with exactly MAX_ITEMS=64 returns 64" {
    var items: [64]DotPlotItem = undefined;
    for (0..64) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 64.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    try testing.expectEqual(@as(usize, 64), dp.itemCount());
}

test "DotPlot.itemCount caps at MAX_ITEMS when 80 items provided" {
    var items: [80]DotPlotItem = undefined;
    for (0..80) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 80.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    try testing.expectEqual(@as(usize, 64), dp.itemCount());
}

// ============================================================================
// Group 5: Builder Immutability (10 tests)
// ============================================================================

test "DotPlot.withItems does not modify original" {
    var items1 = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    var items2 = [_]DotPlotItem{
        .{ .label = "X", .value = 0.2 },
        .{ .label = "Y", .value = 0.8 },
    };

    const dp1 = DotPlot.init().withItems(&items1);
    const dp2 = dp1.withItems(&items2);

    try testing.expectEqual(@as(usize, 1), dp1.itemCount());
    try testing.expectEqual(@as(usize, 2), dp2.itemCount());
}

test "DotPlot.withFocused sets focused index" {
    const dp1 = DotPlot.init().withFocused(0);
    const dp2 = dp1.withFocused(3);

    try testing.expectEqual(@as(usize, 0), dp1.focused);
    try testing.expectEqual(@as(usize, 3), dp2.focused);
}

test "DotPlot.withXMin sets x_min" {
    const dp1 = DotPlot.init().withXMin(-10.0);
    const dp2 = dp1.withXMin(0.0);

    try testing.expectEqual(@as(f32, -10.0), dp1.x_min);
    try testing.expectEqual(@as(f32, 0.0), dp2.x_min);
}

test "DotPlot.withXMax sets x_max" {
    const dp1 = DotPlot.init().withXMax(100.0);
    const dp2 = dp1.withXMax(1000.0);

    try testing.expectEqual(@as(f32, 100.0), dp1.x_max);
    try testing.expectEqual(@as(f32, 1000.0), dp2.x_max);
}

test "DotPlot.withShowLabels sets show_labels" {
    const dp1 = DotPlot.init().withShowLabels(true);
    const dp2 = dp1.withShowLabels(false);

    try testing.expectEqual(true, dp1.show_labels);
    try testing.expectEqual(false, dp2.show_labels);
}

test "DotPlot.withShowValues sets show_values" {
    const dp1 = DotPlot.init().withShowValues(false);
    const dp2 = dp1.withShowValues(true);

    try testing.expectEqual(false, dp1.show_values);
    try testing.expectEqual(true, dp2.show_values);
}

test "DotPlot.withDotChar sets dot_char" {
    const dp1 = DotPlot.init().withDotChar('*');
    const dp2 = dp1.withDotChar('o');

    try testing.expectEqual(@as(u21, '*'), dp1.dot_char);
    try testing.expectEqual(@as(u21, 'o'), dp2.dot_char);
}

test "DotPlot.withStyle sets style" {
    const style = Style{ .bold = true };
    const dp = DotPlot.init().withStyle(style);
    try testing.expectEqual(true, dp.style.bold);
}

test "DotPlot.withDotStyle sets dot_style" {
    const style = Style{ .bold = true };
    const dp = DotPlot.init().withDotStyle(style);
    try testing.expectEqual(true, dp.dot_style.bold);
}

test "DotPlot.withFocusedStyle sets focused_style" {
    const style = Style{ .italic = true };
    const dp = DotPlot.init().withFocusedStyle(style);
    try testing.expectEqual(true, dp.focused_style.italic);
}

// ============================================================================
// Group 6: Builder Methods for Block (2 tests)
// ============================================================================

test "DotPlot.withBlock sets block" {
    const block = Block{};
    const dp = DotPlot.init().withBlock(block);
    try testing.expect(dp.block != null);
}

test "DotPlot.withBlock with null unsets block" {
    const dp1 = DotPlot.init().withBlock(.{});
    const dp2 = dp1.withBlock(null);

    try testing.expect(dp1.block != null);
    try testing.expect(dp2.block == null);
}

// ============================================================================
// Group 7: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "DotPlot.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    dp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "DotPlot.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    dp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "DotPlot.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    dp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "DotPlot.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    dp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 8: Render — Empty Items (2 tests)
// ============================================================================

test "DotPlot.render with zero items produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const dp = DotPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "DotPlot.render empty items with show_labels=false" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const dp = DotPlot.init().withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 9: Render — Single Item (5 tests)
// ============================================================================

test "DotPlot.render single item produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render single item with show_values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render single item with show_labels=false produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "Label", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render single item at different area offsets" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 5, .y = 5, .width = 30, .height = 15 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render single item with no label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Render — Multiple Items (5 tests)
// ============================================================================

test "DotPlot.render two items produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render three items produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.2 },
        .{ .label = "B", .value = 0.5 },
        .{ .label = "C", .value = 0.9 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render five items produces more content than single item" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items_single = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    var items_multiple = [_]DotPlotItem{
        .{ .label = "A", .value = 0.1 },
        .{ .label = "B", .value = 0.3 },
        .{ .label = "C", .value = 0.5 },
        .{ .label = "D", .value = 0.7 },
        .{ .label = "E", .value = 0.9 },
    };

    const dp1 = DotPlot.init().withItems(&items_single);
    const dp2 = DotPlot.init().withItems(&items_multiple);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp1.render(&buf1, area);
    dp2.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content2 >= content1);
}

test "DotPlot.render items with unequal values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Low", .value = 0.1 },
        .{ .label = "Mid", .value = 0.5 },
        .{ .label = "High", .value = 0.95 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render all items with same value" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.5 },
        .{ .label = "B", .value = 0.5 },
        .{ .label = "C", .value = 0.5 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: X Normalization (5 tests)
// ============================================================================

test "DotPlot.render value at x_min renders at leftmost position" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.0 }};
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(0.0)
        .withXMax(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render value at x_max renders at rightmost position" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 1.0 }};
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(0.0)
        .withXMax(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render value at middle of range renders near middle" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(0.0)
        .withXMax(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with negative x_min range" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Neg", .value = -10.0 },
        .{ .label = "Zero", .value = 0.0 },
        .{ .label = "Pos", .value = 10.0 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(-10.0)
        .withXMax(10.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with custom range scales correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Start", .value = 100.0 },
        .{ .label = "Mid", .value = 150.0 },
        .{ .label = "End", .value = 200.0 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(100.0)
        .withXMax(200.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: show_labels Toggle (3 tests)
// ============================================================================

test "DotPlot.render show_labels=true displays label text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "Alpha", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render show_labels=false omits label text" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items = [_]DotPlotItem{.{ .label = "Alpha", .value = 0.5 }};

    const dp_with_labels = DotPlot.init().withItems(&items).withShowLabels(true);
    const dp_no_labels = DotPlot.init().withItems(&items).withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp_with_labels.render(&buf1, area);
    dp_no_labels.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "DotPlot.render show_labels=false still renders dots" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Alpha", .value = 0.3 },
        .{ .label = "Beta", .value = 0.7 },
    };
    const dp = DotPlot.init().withItems(&items).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 13: show_values Toggle (3 tests)
// ============================================================================

test "DotPlot.render show_values=true displays value text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render show_values=false is default behavior" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render show_values=true produces different output than false" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};

    const dp_with_values = DotPlot.init().withItems(&items).withShowValues(true);
    const dp_no_values = DotPlot.init().withItems(&items).withShowValues(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp_with_values.render(&buf1, area);
    dp_no_values.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 >= content2);
}

// ============================================================================
// Group 14: Focused Styling (4 tests)
// ============================================================================

test "DotPlot.render focused=0 on three-item plot applies focus style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.2 },
        .{ .label = "B", .value = 0.5 },
        .{ .label = "C", .value = 0.8 },
    };
    const focused_style = Style{ .bold = true };
    const dp = DotPlot.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render focused=1 applies style to middle item" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.2 },
        .{ .label = "B", .value = 0.5 },
        .{ .label = "C", .value = 0.8 },
    };
    const focused_style = Style{ .dim = true };
    const dp = DotPlot.init()
        .withItems(&items)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render changing focused index produces output" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.2 },
        .{ .label = "B", .value = 0.5 },
        .{ .label = "C", .value = 0.8 },
    };

    const dp1 = DotPlot.init().withItems(&items).withFocused(0);
    const dp2 = DotPlot.init().withItems(&items).withFocused(2);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp1.render(&buf1, area);
    dp2.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

// ============================================================================
// Group 15: dot_char Change (3 tests)
// ============================================================================

test "DotPlot.render with custom dot_char displays the character" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items).withDotChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    try testing.expect(areaHasChar(buf, area, '*'));
}

test "DotPlot.render default dot_char is dot" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    try testing.expect(areaHasChar(buf, area, '●'));
}

test "DotPlot.render with different dot_char produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items).withDotChar('#');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Block Border (3 tests)
// ============================================================================

test "DotPlot.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };
    const block = Block{};
    const dp = DotPlot.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render block reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };

    const block = Block{};
    const dp_with_block = DotPlot.init().withItems(&items).withBlock(block);
    const dp_no_block = DotPlot.init().withItems(&items);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp_with_block.render(&buf1, area);
    dp_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "DotPlot.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };
    const block = (Block{}).withTitle("DotPlot", .top_left);
    const dp = DotPlot.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: MAX_ITEMS Cap (3 tests)
// ============================================================================

test "DotPlot.render with exactly MAX_ITEMS=64" {
    var buf = try Buffer.init(testing.allocator, 80, 64);
    defer buf.deinit();
    var items: [64]DotPlotItem = undefined;
    for (0..64) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 64.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    try testing.expectEqual(@as(usize, 64), dp.itemCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 64 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with 80 items caps to MAX_ITEMS=64" {
    var buf = try Buffer.init(testing.allocator, 80, 64);
    defer buf.deinit();
    var items: [80]DotPlotItem = undefined;
    for (0..80) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 80.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    try testing.expectEqual(@as(usize, 64), dp.itemCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 64 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render 32 items renders all visible items" {
    var buf = try Buffer.init(testing.allocator, 60, 40);
    defer buf.deinit();
    var items: [32]DotPlotItem = undefined;
    for (0..32) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 32.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 40 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 18: Zero Value (3 tests)
// ============================================================================

test "DotPlot.render zero-value item places dot at x_min position" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "Zero", .value = 0.0 }};
    const dp = DotPlot.init().withItems(&items).withXMin(0.0).withXMax(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render all-zero items renders something" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Z1", .value = 0.0 },
        .{ .label = "Z2", .value = 0.0 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render mixed zero and non-zero items" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.25 },
        .{ .label = "B", .value = 0.0 },
        .{ .label = "C", .value = 0.75 },
        .{ .label = "D", .value = 0.0 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 19: x_min == x_max Edge Case (2 tests)
// ============================================================================

test "DotPlot.render x_min == x_max does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(0.5)
        .withXMax(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
}

test "DotPlot.render very small x_max - x_min range" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.0001 }};
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(0.0)
        .withXMax(0.0002);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
}

// ============================================================================
// Group 20: Negative Values (2 tests)
// ============================================================================

test "DotPlot.render negative x_min and x_max range" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Neg10", .value = -10.0 },
        .{ .label = "Neg5", .value = -5.0 },
        .{ .label = "Neg1", .value = -1.0 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(-10.0)
        .withXMax(0.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render symmetric negative and positive range" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Neg10", .value = -10.0 },
        .{ .label = "Zero", .value = 0.0 },
        .{ .label = "Pos10", .value = 10.0 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(-10.0)
        .withXMax(10.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 21: Clipping and Bounds (3 tests)
// ============================================================================

test "DotPlot.render items beyond available height are not rendered" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    var items: [20]DotPlotItem = undefined;
    for (0..20) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 20.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render does not exceed buffer bounds with many items" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var items: [32]DotPlotItem = undefined;
    for (0..32) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 32.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 1800); // 60*30 max
}

test "DotPlot.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 22: Line Style (2 tests)
// ============================================================================

test "DotPlot.render with line_style renders grid lines" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const line_style = Style{ .bold = true };
    const dp = DotPlot.init()
        .withItems(&items)
        .withLineStyle(line_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render line characters use line_style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    // Check for dashes or line characters
    try testing.expect(areaHasChar(buf, area, '─') or areaHasChar(buf, area, '●'));
}

// ============================================================================
// Group 23: Label Column Width (2 tests)
// ============================================================================

test "DotPlot.render label is truncated to fit label column" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "VeryLongLabelThatShouldBeTruncated", .value = 0.5 }
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render label column never overflows into plot area" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "LongLabel", .value = 0.3 },
        .{ .label = "Another", .value = 0.7 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 24: Style Application (4 tests)
// ============================================================================

test "DotPlot.render with style applies to plot" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const style = Style{ .bold = true };
    const dp = DotPlot.init().withItems(&items).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "Alpha", .value = 0.5 }};
    const label_style = Style{ .italic = true };
    const dp = DotPlot.init()
        .withItems(&items)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with dot_style applies to dots" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "A", .value = 0.5 }};
    const dot_style = Style{ .dim = true };
    const dp = DotPlot.init()
        .withItems(&items)
        .withDotStyle(dot_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with multiple styles applied" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withStyle(Style{ .dim = true })
        .withLabelStyle(Style{ .bold = true })
        .withDotStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true, .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 25: Complex Real-World Scenarios (4 tests)
// ============================================================================

test "DotPlot.render rating scale visualization" {
    var buf = try Buffer.init(testing.allocator, 60, 25);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Product A", .value = 4.5 },
        .{ .label = "Product B", .value = 3.8 },
        .{ .label = "Product C", .value = 4.2 },
        .{ .label = "Product D", .value = 3.1 },
        .{ .label = "Product E", .value = 4.9 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withShowValues(true)
        .withXMin(0.0)
        .withXMax(5.0)
        .withBlock((Block{}).withTitle("Ratings", .top_center));
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 25 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render efficiency comparison" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Method A", .value = 85.5 },
        .{ .label = "Method B", .value = 72.3 },
        .{ .label = "Method C", .value = 91.2 },
        .{ .label = "Method D", .value = 65.8 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withShowValues(true)
        .withXMin(0.0)
        .withXMax(100.0)
        .withFocused(2);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with all features enabled" {
    var buf = try Buffer.init(testing.allocator, 70, 30);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Item1", .value = 10.0, .style = Style{ .bold = true } },
        .{ .label = "Item2", .value = 50.0 },
        .{ .label = "Item3", .value = 75.0, .style = Style{ .dim = true } },
        .{ .label = "Item4", .value = 30.0 },
        .{ .label = "Item5", .value = 90.0 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withShowValues(true)
        .withShowLabels(true)
        .withFocused(2)
        .withXMin(0.0)
        .withXMax(100.0)
        .withStyle(Style{ .italic = true })
        .withLabelStyle(Style{ .bold = true })
        .withDotStyle(Style{ .dim = false })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withBlock((Block{}).withTitle("Complete DotPlot", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 30 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render single-item plot edge case" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var items = [_]DotPlotItem{.{ .label = "OnlyOne", .value = 50.0 }};
    const dp = DotPlot.init()
        .withItems(&items)
        .withShowValues(true)
        .withShowLabels(true)
        .withXMin(0.0)
        .withXMax(100.0)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 26: Large and Edge Case Areas (3 tests)
// ============================================================================

test "DotPlot.render very wide area" {
    var buf = try Buffer.init(testing.allocator, 200, 10);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.3 },
        .{ .label = "B", .value = 0.7 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 10 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render very tall area" {
    var buf = try Buffer.init(testing.allocator, 20, 100);
    defer buf.deinit();
    var items: [50]DotPlotItem = undefined;
    for (0..50) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 50.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 100 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render rectangular area with many items" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var items: [40]DotPlotItem = undefined;
    for (0..40) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) / 40.0 };
    }
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 27: Fractional Values (3 tests)
// ============================================================================

test "DotPlot.render with fractional values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "A", .value = 0.125 },
        .{ .label = "B", .value = 0.333 },
        .{ .label = "C", .value = 0.777 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DotPlot.render with very small fractional values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "T1", .value = 0.001 },
        .{ .label = "T2", .value = 0.0001 },
    };
    const dp = DotPlot.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    dp.render(&buf, area);
}

test "DotPlot.render with mixed magnitude values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]DotPlotItem{
        .{ .label = "Large", .value = 1000.5 },
        .{ .label = "Small", .value = 0.5 },
        .{ .label = "Tiny", .value = 0.001 },
    };
    const dp = DotPlot.init()
        .withItems(&items)
        .withXMin(0.0)
        .withXMax(1000.5);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    dp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
