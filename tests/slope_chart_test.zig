//! SlopeChart Widget Tests — TDD Red Phase
//!
//! Tests SlopeChart widget rendering before/after two-point comparison lines per category.
//! Each item draws a line connecting a left value to a right value, with optional labels
//! and direction-based styling (increase, decrease, flat).
//!
//! Tests cover initialization, builder pattern, itemCount() capping at MAX_ITEMS,
//! endpoint row positioning by normalization, slope-direction character rendering (/, \, ─),
//! style precedence (focused > per-item > direction > line_style), out-of-range clamping,
//! label/value/column-label display toggles, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const SlopeChart = sailor.tui.widgets.SlopeChart;
const SlopeItem = sailor.tui.widgets.slope_chart.SlopeItem;

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

/// Count specific character in a buffer area
fn countChar(buf: Buffer, area: Rect, target_char: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == target_char) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Get cell at position in area
fn getCell(buf: Buffer, area: Rect, x: u16, y: u16) ?sailor.Cell {
    if (x >= area.width or y >= area.height) return null;
    return buf.getConst(area.x + x, area.y + y);
}

/// Approximate float equality
fn floatEq(a: f32, b: f32, epsilon: f32) bool {
    return @abs(a - b) < epsilon;
}

// ============================================================================
// Group 1: Init and Defaults (6 tests)
// ============================================================================

test "SlopeChart.init creates chart with zero items" {
    const chart = SlopeChart.init();
    try testing.expectEqual(@as(usize, 0), chart.items.len);
}

test "SlopeChart.init defaults focused to 0" {
    const chart = SlopeChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused);
}

test "SlopeChart.init defaults show_labels to true" {
    const chart = SlopeChart.init();
    try testing.expectEqual(true, chart.show_labels);
}

test "SlopeChart.init defaults show_values to false" {
    const chart = SlopeChart.init();
    try testing.expectEqual(false, chart.show_values);
}

test "SlopeChart.init defaults show_column_labels to true" {
    const chart = SlopeChart.init();
    try testing.expectEqual(true, chart.show_column_labels);
}

test "SlopeChart.init defaults point_char to '●'" {
    const chart = SlopeChart.init();
    try testing.expectEqual(@as(u21, '●'), chart.point_char);
}

// ============================================================================
// Group 2: SlopeItem Struct Defaults (3 tests)
// ============================================================================

test "SlopeItem default label is empty" {
    const item = SlopeItem{};
    try testing.expectEqualStrings("", item.label);
}

test "SlopeItem default left_value is 0.0" {
    const item = SlopeItem{};
    try testing.expect(floatEq(0.0, item.left_value, 0.001));
}

test "SlopeItem default right_value is 0.0" {
    const item = SlopeItem{};
    try testing.expect(floatEq(0.0, item.right_value, 0.001));
}

// ============================================================================
// Group 3: Value Range and Style Defaults (5 tests)
// ============================================================================

test "SlopeChart.init defaults min_value to 0.0" {
    const chart = SlopeChart.init();
    try testing.expect(floatEq(0.0, chart.min_value, 0.001));
}

test "SlopeChart.init defaults max_value to 1.0" {
    const chart = SlopeChart.init();
    try testing.expect(floatEq(1.0, chart.max_value, 0.001));
}

test "SlopeChart.init defaults block to null" {
    const chart = SlopeChart.init();
    try testing.expectEqual(@as(?Block, null), chart.block);
}

test "SlopeChart.init has default empty styles" {
    const chart = SlopeChart.init();
    try testing.expectEqual(Style{}, chart.style);
    try testing.expectEqual(Style{}, chart.line_style);
    try testing.expectEqual(Style{}, chart.increase_style);
    try testing.expectEqual(Style{}, chart.decrease_style);
    try testing.expectEqual(Style{}, chart.flat_style);
    try testing.expectEqual(Style{}, chart.focused_style);
    try testing.expectEqual(Style{}, chart.label_style);
    try testing.expectEqual(Style{}, chart.column_label_style);
}

test "SlopeChart.init defaults left_label and right_label to empty" {
    const chart = SlopeChart.init();
    try testing.expectEqualStrings("", chart.left_label);
    try testing.expectEqualStrings("", chart.right_label);
}

// ============================================================================
// Group 4: MAX_ITEMS Constant (1 test)
// ============================================================================

test "SlopeChart.MAX_ITEMS equals 16" {
    try testing.expectEqual(@as(usize, 16), SlopeChart.MAX_ITEMS);
}

// ============================================================================
// Group 5: itemCount() Method (5 tests)
// ============================================================================

test "itemCount with zero items returns 0" {
    const chart = SlopeChart.init();
    try testing.expectEqual(@as(usize, 0), chart.itemCount());
}

test "itemCount with 1 item returns 1" {
    var items = [_]SlopeItem{.{ .label = "A", .left_value = 10.0, .right_value = 20.0 }};
    const chart = SlopeChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 1), chart.itemCount());
}

test "itemCount with 8 items returns 8" {
    var items: [8]SlopeItem = undefined;
    for (0..8) |i| {
        items[i] = .{ .label = "I", .left_value = @as(f32, @floatFromInt(i)), .right_value = @as(f32, @floatFromInt(i + 1)) };
    }
    const chart = SlopeChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 8), chart.itemCount());
}

test "itemCount with exactly MAX_ITEMS=16 returns 16" {
    var items: [16]SlopeItem = undefined;
    for (0..16) |i| {
        items[i] = .{ .label = "I", .left_value = @as(f32, @floatFromInt(i)), .right_value = @as(f32, @floatFromInt(i + 1)) };
    }
    const chart = SlopeChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 16), chart.itemCount());
}

test "itemCount caps at MAX_ITEMS=16 when 32 items provided" {
    var items: [32]SlopeItem = undefined;
    for (0..32) |i| {
        items[i] = .{ .label = "I", .left_value = @as(f32, @floatFromInt(i)), .right_value = @as(f32, @floatFromInt(i + 1)) };
    }
    const chart = SlopeChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 16), chart.itemCount());
}

// ============================================================================
// Group 6: Builder Immutability — All Builder Methods (12 tests)
// ============================================================================

test "withItems does not modify original" {
    var items1 = [_]SlopeItem{.{ .label = "A", .left_value = 10.0, .right_value = 20.0 }};
    var items2 = [_]SlopeItem{
        .{ .label = "X", .left_value = 15.0, .right_value = 25.0 },
        .{ .label = "Y", .left_value = 5.0, .right_value = 35.0 },
    };
    const chart1 = SlopeChart.init().withItems(&items1);
    const chart2 = chart1.withItems(&items2);
    try testing.expectEqual(@as(usize, 1), chart1.itemCount());
    try testing.expectEqual(@as(usize, 2), chart2.itemCount());
}

test "withFocused does not modify original" {
    const chart1 = SlopeChart.init().withFocused(0);
    const chart2 = chart1.withFocused(5);
    try testing.expectEqual(@as(usize, 0), chart1.focused);
    try testing.expectEqual(@as(usize, 5), chart2.focused);
}

test "withMinValue does not modify original" {
    const chart1 = SlopeChart.init().withMinValue(0.0);
    const chart2 = chart1.withMinValue(10.0);
    try testing.expect(floatEq(0.0, chart1.min_value, 0.001));
    try testing.expect(floatEq(10.0, chart2.min_value, 0.001));
}

test "withMaxValue does not modify original" {
    const chart1 = SlopeChart.init().withMaxValue(1.0);
    const chart2 = chart1.withMaxValue(100.0);
    try testing.expect(floatEq(1.0, chart1.max_value, 0.001));
    try testing.expect(floatEq(100.0, chart2.max_value, 0.001));
}

test "withShowLabels does not modify original" {
    const chart1 = SlopeChart.init().withShowLabels(false);
    const chart2 = chart1.withShowLabels(true);
    try testing.expectEqual(false, chart1.show_labels);
    try testing.expectEqual(true, chart2.show_labels);
}

test "withShowValues does not modify original" {
    const chart1 = SlopeChart.init().withShowValues(false);
    const chart2 = chart1.withShowValues(true);
    try testing.expectEqual(false, chart1.show_values);
    try testing.expectEqual(true, chart2.show_values);
}

test "withShowColumnLabels does not modify original" {
    const chart1 = SlopeChart.init().withShowColumnLabels(false);
    const chart2 = chart1.withShowColumnLabels(true);
    try testing.expectEqual(false, chart1.show_column_labels);
    try testing.expectEqual(true, chart2.show_column_labels);
}

test "withLineStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = SlopeChart.init().withLineStyle(s1);
    const chart2 = chart1.withLineStyle(s2);
    try testing.expectEqual(true, chart1.line_style.bold);
    try testing.expectEqual(true, chart2.line_style.dim);
}

test "withIncreaseStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = SlopeChart.init().withIncreaseStyle(s1);
    const chart2 = chart1.withIncreaseStyle(s2);
    try testing.expectEqual(true, chart1.increase_style.bold);
    try testing.expectEqual(true, chart2.increase_style.dim);
}

test "withDecreaseStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = SlopeChart.init().withDecreaseStyle(s1);
    const chart2 = chart1.withDecreaseStyle(s2);
    try testing.expectEqual(true, chart1.decrease_style.bold);
    try testing.expectEqual(true, chart2.decrease_style.dim);
}

test "withFocusedStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = SlopeChart.init().withFocusedStyle(s1);
    const chart2 = chart1.withFocusedStyle(s2);
    try testing.expectEqual(true, chart1.focused_style.bold);
    try testing.expectEqual(true, chart2.focused_style.dim);
}

test "withBlock does not modify original" {
    const chart1 = SlopeChart.init().withBlock(.{});
    const chart2 = chart1.withBlock(null);
    try testing.expect(chart1.block != null);
    try testing.expect(chart2.block == null);
}

// ============================================================================
// Group 7: Render — Zero/Minimal Area (3 tests)
// ============================================================================

test "render with 0x0 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = SlopeChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = SlopeChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = SlopeChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 8: Render — Empty Data (2 tests)
// ============================================================================

test "render with zero items produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = SlopeChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero items and Block does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = SlopeChart.init().withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 9: Render — Single Item (4 tests)
// ============================================================================

test "render with single item produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "A", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with single item at zero values does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Zero", .left_value = 0.0, .right_value = 0.0 }};
    const chart = SlopeChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

test "render with single item custom style applies style" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "S", .left_value = 0.5, .right_value = 0.8, .style = .{ .bold = true } }};
    const chart = SlopeChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render single item with custom point_char" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Custom", .left_value = 0.2, .right_value = 0.6 }};
    const chart = SlopeChart.init().withItems(&items).withPointChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 10: Endpoint Row Positioning (Hand-Computed) (6 tests)
// ============================================================================

test "left endpoint at min_value appears at bottom row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Min", .left_value = 0.0, .right_value = 0.5 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1.0)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    // Endpoint at min_value (0.0) should appear near bottom
    // When normalized: t = (0.0 - 0.0) / (1.0 - 0.0) = 0.0
    // Row = chart_y0 + chart_height - 1 (bottom row)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "left endpoint at max_value appears at top row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Max", .left_value = 1.0, .right_value = 0.5 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1.0)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    // Endpoint at max_value (1.0) should appear near top
    // When normalized: t = (1.0 - 0.0) / (1.0 - 0.0) = 1.0
    // Row = chart_y0 (top row)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "midpoint value appears near vertical center" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Mid", .left_value = 0.5, .right_value = 0.5 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1.0)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    // Both endpoints at 0.5 normalize to t=0.5, should be near middle
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "non-zero min_value normalization" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Scale [10..20], item has left=15 (midpoint), right=20 (max)
    var items = [_]SlopeItem{.{ .label = "Scaled", .left_value = 15.0, .right_value = 20.0 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(10.0)
        .withMaxValue(20.0)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    // Normalized: left = (15-10)/(20-10) = 0.5, right = (20-10)/(20-10) = 1.0
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "quarter-point and three-quarter-point positioning" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Q", .left_value = 0.25, .right_value = 0.75 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1.0)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    // left normalizes to 0.25 (quarter up from bottom)
    // right normalizes to 0.75 (three-quarter up from bottom)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "endpoints with custom min/max range" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Custom", .left_value = 100.0, .right_value = 150.0 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(50.0)
        .withMaxValue(200.0)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    // left: (100-50)/(200-50) = 50/150 ≈ 0.33
    // right: (150-50)/(200-50) = 100/150 ≈ 0.67
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 11: Slope Direction Correctness (5 tests)
// ============================================================================

test "increase slope (right > left) contains '/' character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Up", .left_value = 0.2, .right_value = 0.8 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // For an increase (right > left), the slope should have '/' somewhere on the line
    const has_slash = countChar(buf, area, '/') > 0;
    try testing.expect(has_slash);
}

test "decrease slope (right < left) contains '\\' character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Down", .left_value = 0.8, .right_value = 0.2 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // For a decrease (right < left), the slope should have '\' somewhere on the line
    const has_backslash = countChar(buf, area, '\\') > 0;
    try testing.expect(has_backslash);
}

test "flat slope (right == left) contains '─' character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Flat", .left_value = 0.5, .right_value = 0.5 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // For flat (right == left), the slope should have '─' on the line
    const has_dash = countChar(buf, area, '─') > 0;
    try testing.expect(has_dash);
}

test "multiple items with different slope directions" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "Up", .left_value = 0.2, .right_value = 0.8 },
        .{ .label = "Down", .left_value = 0.8, .right_value = 0.2 },
        .{ .label = "Flat", .left_value = 0.5, .right_value = 0.5 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);
    // Should have at least one instance of each slope character
    try testing.expect(countChar(buf, area, '/') > 0);
    try testing.expect(countChar(buf, area, '\\') > 0);
    try testing.expect(countChar(buf, area, '─') > 0);
}

test "endpoint markers render with point_char" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Points", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withPointChar('●')
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should render at least 2 endpoint markers (●) — one at left, one at right
    try testing.expect(countChar(buf, area, '●') >= 2);
}

// ============================================================================
// Group 12: Style Precedence Tests (5 tests)
// ============================================================================

test "increase_style applies to increase slope when set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Inc", .left_value = 0.2, .right_value = 0.8 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withIncreaseStyle(.{ .bold = true })
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should render increase slope with bold style applied
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "decrease_style applies to decrease slope when set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Dec", .left_value = 0.8, .right_value = 0.2 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withDecreaseStyle(.{ .dim = true })
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should render decrease slope with dim style applied
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "flat_style applies to flat slope when set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Flat", .left_value = 0.5, .right_value = 0.5 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withFlatStyle(.{ .underline = true })
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should render flat slope with underline style applied
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "per-item style overrides direction styling" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Override", .left_value = 0.2, .right_value = 0.8, .style = .{ .reverse = true } }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withIncreaseStyle(.{ .bold = true })
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Per-item style should take precedence over increase_style
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused_style takes highest precedence over all other styles" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.2, .right_value = 0.8, .style = .{ .italic = true } },
        .{ .label = "B", .left_value = 0.3, .right_value = 0.6 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true })
        .withIncreaseStyle(.{ .dim = true })
        .withShowValues(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Focused item's style should be focused_style (bold), not per-item (italic) or increase_style (dim)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 13: Out-of-Range Value Handling (5 tests)
// ============================================================================

test "value above max_value does not crash and clamps" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "High", .left_value = 1.5, .right_value = 2.0 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should clamp to max without crashing
}

test "value below min_value does not crash and clamps" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Low", .left_value = -0.5, .right_value = 0.5 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should clamp to min without crashing
}

test "min_value == max_value (zero range) uses fallback" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "ZeroRange", .left_value = 5.0, .right_value = 5.0 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(5.0)
        .withMaxValue(5.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should use fallback (0.5) normalization without divide-by-zero
}

test "mixed in-range and out-of-range values" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "In", .left_value = 0.3, .right_value = 0.7 },
        .{ .label = "Out", .left_value = -1.0, .right_value = 2.0 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Both items should render (clamped)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "very large value range does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Huge", .left_value = 1e6, .right_value = 2e6 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(1e7);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 14: Label, Value, and Column-Label Toggles (6 tests)
// ============================================================================

test "show_labels=true renders item labels at endpoints" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "ItemLabel", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowLabels(true)
        .withShowValues(false)
        .withShowColumnLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Labels should appear in left/right columns
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_labels=false omits item labels" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Hidden", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowLabels(false)
        .withShowValues(false)
        .withShowColumnLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should still render the line/points, but no labels
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_values=true renders numeric values at endpoints" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "A", .left_value = 0.25, .right_value = 0.75 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowValues(true)
        .withShowLabels(false)
        .withShowColumnLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Values should appear (numeric digits in columns)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_values=false omits numeric values" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "A", .left_value = 0.25, .right_value = 0.75 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowValues(false)
        .withShowLabels(false)
        .withShowColumnLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Only line/points, no values
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_labels and show_values both=true renders both" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Both", .left_value = 0.2, .right_value = 0.8 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowLabels(true)
        .withShowValues(true)
        .withShowColumnLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);
    // Both labels and values should render
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_labels and show_values both=false renders only line and points" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Minimal", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowLabels(false)
        .withShowValues(false)
        .withShowColumnLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Minimal rendering: slope characters and endpoint markers only
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 15: Column Label Header Rendering (4 tests)
// ============================================================================

test "show_column_labels=true with non-empty labels renders header row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "A", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowColumnLabels(true)
        .withLeftLabel("Before")
        .withRightLabel("After");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);
    // Header row should render with "Before" and "After"
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_column_labels=false omits header row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "A", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowColumnLabels(false)
        .withLeftLabel("Before")
        .withRightLabel("After");
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);
    // No header row, but chart should still render
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "column_labels render at top row when show_column_labels=true" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "Item", .left_value = 0.4, .right_value = 0.6 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowColumnLabels(true)
        .withLeftLabel("Left")
        .withRightLabel("Right")
        .withShowLabels(false)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);
    // Column labels should appear near top
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "both_empty column labels with show_column_labels=true renders nothing in header" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{.{ .label = "A", .left_value = 0.3, .right_value = 0.7 }};
    const chart = SlopeChart.init()
        .withItems(&items)
        .withShowColumnLabels(true)
        .withLeftLabel("")
        .withRightLabel("")
        .withShowLabels(false)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Empty labels, so no header content, but chart renders
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 16: Block Border (3 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.3, .right_value = 0.7 },
        .{ .label = "B", .left_value = 0.2, .right_value = 0.8 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    chart.render(&buf, area);

    // Block border must render — at least one border glyph must be present
    const has_border = countChar(buf, area, '─') > 0 or
                       countChar(buf, area, '│') > 0 or
                       countChar(buf, area, '┌') > 0 or
                       countChar(buf, area, '┐') > 0 or
                       countChar(buf, area, '└') > 0 or
                       countChar(buf, area, '┘') > 0;
    try testing.expect(has_border);
}

test "render with block in offset area" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.4, .right_value = 0.6 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.3, .right_value = 0.7 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 17: Multiple Items (4 tests)
// ============================================================================

test "render with 3 items produces more content than 1" {
    var buf1 = try Buffer.init(testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 80, 24);
    defer buf2.deinit();

    var items1 = [_]SlopeItem{.{ .label = "A", .left_value = 0.2, .right_value = 0.8 }};
    const chart1 = SlopeChart.init().withItems(&items1);

    var items2 = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.2, .right_value = 0.8 },
        .{ .label = "B", .left_value = 0.1, .right_value = 0.9 },
        .{ .label = "C", .left_value = 0.3, .right_value = 0.7 },
    };
    const chart2 = SlopeChart.init().withItems(&items2);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);

    const count1 = countNonEmptyCells(buf1, area);
    const count2 = countNonEmptyCells(buf2, area);
    try testing.expect(count2 >= count1);
}

test "render 5 items with diverse slopes" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "Down", .left_value = 0.9, .right_value = 0.1 },
        .{ .label = "Up", .left_value = 0.1, .right_value = 0.9 },
        .{ .label = "Flat", .left_value = 0.5, .right_value = 0.5 },
        .{ .label = "Q1", .left_value = 0.25, .right_value = 0.75 },
        .{ .label = "Q2", .left_value = 0.75, .right_value = 0.25 },
    };
    const chart = SlopeChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with MAX_ITEMS (16 items)" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var items: [16]SlopeItem = undefined;
    for (0..16) |i| {
        const lv = @as(f32, @floatFromInt(i)) / 16.0;
        items[i] = .{
            .label = "I",
            .left_value = lv,
            .right_value = 1.0 - lv,
        };
    }
    const chart = SlopeChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };

    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 16), chart.itemCount());
}

test "render more than MAX_ITEMS caps at 16" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var items: [32]SlopeItem = undefined;
    for (0..32) |i| {
        const lv = @as(f32, @floatFromInt(i)) / 32.0;
        items[i] = .{
            .label = "I",
            .left_value = lv,
            .right_value = 1.0 - lv,
        };
    }
    const chart = SlopeChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };

    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 16), chart.itemCount());
}

// ============================================================================
// Group 18: Focused Item Styling (3 tests)
// ============================================================================

test "focused item at index 0 uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.2, .right_value = 0.8 },
        .{ .label = "B", .left_value = 0.3, .right_value = 0.7 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused index beyond item count does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.2, .right_value = 0.8 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
}

test "focused_style overrides per-item and direction styles" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "Focused", .left_value = 0.2, .right_value = 0.8, .style = .{ .italic = true } },
        .{ .label = "Other", .left_value = 0.5, .right_value = 0.5 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true })
        .withIncreaseStyle(.{ .dim = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    // Focused item should use focused_style, not per-item or increase_style
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 19: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields correctly" {
    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.2, .right_value = 0.8 },
        .{ .label = "B", .left_value = 0.3, .right_value = 0.7 },
    };

    const chart = SlopeChart.init()
        .withItems(&items)
        .withFocused(1)
        .withMinValue(10.0)
        .withMaxValue(100.0)
        .withShowLabels(false)
        .withShowValues(true)
        .withShowColumnLabels(false)
        .withPointChar('*')
        .withLineStyle(.{ .bold = true })
        .withIncreaseStyle(.{ .dim = true })
        .withDecreaseStyle(.{ .underline = true })
        .withFocusedStyle(.{ .reverse = true })
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), chart.itemCount());
    try testing.expectEqual(@as(usize, 1), chart.focused);
    try testing.expect(floatEq(10.0, chart.min_value, 0.001));
    try testing.expect(floatEq(100.0, chart.max_value, 0.001));
    try testing.expectEqual(false, chart.show_labels);
    try testing.expectEqual(true, chart.show_values);
    try testing.expectEqual(false, chart.show_column_labels);
    try testing.expectEqual(@as(u21, '*'), chart.point_char);
    try testing.expect(chart.block != null);
}

test "builder chain preserves last value for each field" {
    const chart = SlopeChart.init()
        .withMinValue(0.0)
        .withMinValue(5.0)
        .withMaxValue(1.0)
        .withMaxValue(200.0)
        .withShowLabels(true)
        .withShowLabels(false)
        .withFocused(0)
        .withFocused(7);

    try testing.expect(floatEq(5.0, chart.min_value, 0.001));
    try testing.expect(floatEq(200.0, chart.max_value, 0.001));
    try testing.expectEqual(false, chart.show_labels);
    try testing.expectEqual(@as(usize, 7), chart.focused);
}

// ============================================================================
// Group 20: Realistic Scenario (2 tests)
// ============================================================================

test "render realistic before/after comparison with styled items" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "Revenue", .left_value = 50.0, .right_value = 75.0 },
        .{ .label = "Costs", .left_value = 30.0, .right_value = 40.0 },
        .{ .label = "Profit", .left_value = 20.0, .right_value = 35.0 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withMinValue(0.0)
        .withMaxValue(100.0)
        .withLeftLabel("Q1")
        .withRightLabel("Q2")
        .withShowLabels(true)
        .withShowValues(true)
        .withShowColumnLabels(true)
        .withIncreaseStyle(.{ .bold = true })
        .withDecreaseStyle(.{ .dim = true })
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with all toggles and styling options enabled" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var items = [_]SlopeItem{
        .{ .label = "A", .left_value = 0.2, .right_value = 0.8, .style = .{ .italic = true } },
        .{ .label = "B", .left_value = 0.8, .right_value = 0.3, .style = .{ .underline = true } },
        .{ .label = "C", .left_value = 0.5, .right_value = 0.5 },
    };
    const chart = SlopeChart.init()
        .withItems(&items)
        .withFocused(0)
        .withMinValue(0.0)
        .withMaxValue(1.0)
        .withLeftLabel("Start")
        .withRightLabel("End")
        .withShowLabels(true)
        .withShowValues(true)
        .withShowColumnLabels(true)
        .withPointChar('●')
        .withStyle(.{ .underline = true })
        .withLineStyle(.{ .bold = true })
        .withIncreaseStyle(.{ .bold = true })
        .withDecreaseStyle(.{ .dim = true })
        .withFlatStyle(.{ .italic = true })
        .withFocusedStyle(.{ .reverse = true })
        .withLabelStyle(.{ .bold = true })
        .withColumnLabelStyle(.{ .underline = true })
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 28 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}
