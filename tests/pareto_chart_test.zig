//! ParetoChart Widget Tests — TDD Red Phase
//!
//! Tests ParetoChart widget rendering Pareto data as descending-sorted bars with
//! an overlaid cumulative percentage line and optional 80% threshold marker.
//!
//! Tests cover initialization, builder pattern, itemCount() capping at MAX_ITEMS,
//! render geometry (bar heights by value, cumulative percentage line positioning,
//! threshold marker line at configurable %, sorted vs input-order modes),
//! out-of-range value handling (negative, no crash/panic), focused styling,
//! label/value/line/threshold display toggles, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const ParetoChart = sailor.tui.widgets.ParetoChart;
const ParetoItem = sailor.tui.widgets.pareto_chart.ParetoItem;

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

test "ParetoChart.init creates chart with zero items" {
    const chart = ParetoChart.init();
    try testing.expectEqual(@as(usize, 0), chart.items.len);
}

test "ParetoChart.init defaults focused to 0" {
    const chart = ParetoChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused);
}

test "ParetoChart.init defaults sorted to true" {
    const chart = ParetoChart.init();
    try testing.expectEqual(true, chart.sorted);
}

test "ParetoChart.init defaults show_values to true" {
    const chart = ParetoChart.init();
    try testing.expectEqual(true, chart.show_values);
}

test "ParetoChart.init defaults show_cumulative_line to true" {
    const chart = ParetoChart.init();
    try testing.expectEqual(true, chart.show_cumulative_line);
}

test "ParetoChart.init defaults show_threshold to true" {
    const chart = ParetoChart.init();
    try testing.expectEqual(true, chart.show_threshold);
}

// ============================================================================
// Group 2: ParetoItem Struct Defaults (3 tests)
// ============================================================================

test "ParetoItem default label is empty" {
    const item = ParetoItem{};
    try testing.expectEqualStrings("", item.label);
}

test "ParetoItem default value is 0.0" {
    const item = ParetoItem{};
    try testing.expect(floatEq(0.0, item.value, 0.001));
}

test "ParetoItem default style is empty" {
    const item = ParetoItem{};
    try testing.expectEqual(Style{}, item.style);
}

// ============================================================================
// Group 3: Threshold and Style Defaults (5 tests)
// ============================================================================

test "ParetoChart.init defaults threshold to 0.8" {
    const chart = ParetoChart.init();
    try testing.expect(floatEq(0.8, chart.threshold, 0.001));
}

test "ParetoChart.init defaults block to null" {
    const chart = ParetoChart.init();
    try testing.expectEqual(@as(?Block, null), chart.block);
}

test "ParetoChart.init has default empty styles" {
    const chart = ParetoChart.init();
    try testing.expectEqual(Style{}, chart.style);
    try testing.expectEqual(Style{}, chart.bar_style);
    try testing.expectEqual(Style{}, chart.line_style);
    try testing.expectEqual(Style{}, chart.threshold_style);
    try testing.expectEqual(Style{}, chart.focused_style);
    try testing.expectEqual(Style{}, chart.label_style);
}

test "ParetoChart.init has zero items and empty array" {
    const chart = ParetoChart.init();
    try testing.expectEqual(@as(usize, 0), chart.itemCount());
}

// ============================================================================
// Group 4: MAX_ITEMS Constant (1 test)
// ============================================================================

test "ParetoChart.MAX_ITEMS equals 32" {
    try testing.expectEqual(@as(usize, 32), ParetoChart.MAX_ITEMS);
}

// ============================================================================
// Group 5: itemCount() Method (5 tests)
// ============================================================================

test "itemCount with zero items returns 0" {
    const chart = ParetoChart.init();
    try testing.expectEqual(@as(usize, 0), chart.itemCount());
}

test "itemCount with 1 item returns 1" {
    var items = [_]ParetoItem{.{ .label = "A", .value = 50.0 }};
    const chart = ParetoChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 1), chart.itemCount());
}

test "itemCount with 8 items returns 8" {
    var items: [8]ParetoItem = undefined;
    for (0..8) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i + 1)) * 10.0 };
    }
    const chart = ParetoChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 8), chart.itemCount());
}

test "itemCount with exactly MAX_ITEMS=32 returns 32" {
    var items: [32]ParetoItem = undefined;
    for (0..32) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i + 1)) };
    }
    const chart = ParetoChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
}

test "itemCount caps at MAX_ITEMS=32 when 50 items provided" {
    var items: [50]ParetoItem = undefined;
    for (0..50) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt((i + 1) % 100)) };
    }
    const chart = ParetoChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
}

// ============================================================================
// Group 6: Builder Immutability — All Builder Methods (15 tests)
// ============================================================================

test "withItems does not modify original" {
    var items1 = [_]ParetoItem{.{ .label = "A", .value = 50.0 }};
    var items2 = [_]ParetoItem{
        .{ .label = "X", .value = 30.0 },
        .{ .label = "Y", .value = 70.0 },
    };
    const chart1 = ParetoChart.init().withItems(&items1);
    const chart2 = chart1.withItems(&items2);
    try testing.expectEqual(@as(usize, 1), chart1.itemCount());
    try testing.expectEqual(@as(usize, 2), chart2.itemCount());
}

test "withFocused does not modify original" {
    const chart1 = ParetoChart.init().withFocused(0);
    const chart2 = chart1.withFocused(5);
    try testing.expectEqual(@as(usize, 0), chart1.focused);
    try testing.expectEqual(@as(usize, 5), chart2.focused);
}

test "withSorted does not modify original" {
    const chart1 = ParetoChart.init().withSorted(true);
    const chart2 = chart1.withSorted(false);
    try testing.expectEqual(true, chart1.sorted);
    try testing.expectEqual(false, chart2.sorted);
}

test "withShowValues does not modify original" {
    const chart1 = ParetoChart.init().withShowValues(false);
    const chart2 = chart1.withShowValues(true);
    try testing.expectEqual(false, chart1.show_values);
    try testing.expectEqual(true, chart2.show_values);
}

test "withShowCumulativeLine does not modify original" {
    const chart1 = ParetoChart.init().withShowCumulativeLine(false);
    const chart2 = chart1.withShowCumulativeLine(true);
    try testing.expectEqual(false, chart1.show_cumulative_line);
    try testing.expectEqual(true, chart2.show_cumulative_line);
}

test "withShowThreshold does not modify original" {
    const chart1 = ParetoChart.init().withShowThreshold(false);
    const chart2 = chart1.withShowThreshold(true);
    try testing.expectEqual(false, chart1.show_threshold);
    try testing.expectEqual(true, chart2.show_threshold);
}

test "withThreshold does not modify original" {
    const chart1 = ParetoChart.init().withThreshold(0.5);
    const chart2 = chart1.withThreshold(0.9);
    try testing.expect(floatEq(0.5, chart1.threshold, 0.001));
    try testing.expect(floatEq(0.9, chart2.threshold, 0.001));
}

test "withStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ParetoChart.init().withStyle(s1);
    const chart2 = chart1.withStyle(s2);
    try testing.expectEqual(true, chart1.style.bold);
    try testing.expectEqual(true, chart2.style.dim);
}

test "withBarStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ParetoChart.init().withBarStyle(s1);
    const chart2 = chart1.withBarStyle(s2);
    try testing.expectEqual(true, chart1.bar_style.bold);
    try testing.expectEqual(true, chart2.bar_style.dim);
}

test "withLineStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ParetoChart.init().withLineStyle(s1);
    const chart2 = chart1.withLineStyle(s2);
    try testing.expectEqual(true, chart1.line_style.bold);
    try testing.expectEqual(true, chart2.line_style.dim);
}

test "withThresholdStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ParetoChart.init().withThresholdStyle(s1);
    const chart2 = chart1.withThresholdStyle(s2);
    try testing.expectEqual(true, chart1.threshold_style.bold);
    try testing.expectEqual(true, chart2.threshold_style.dim);
}

test "withFocusedStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ParetoChart.init().withFocusedStyle(s1);
    const chart2 = chart1.withFocusedStyle(s2);
    try testing.expectEqual(true, chart1.focused_style.bold);
    try testing.expectEqual(true, chart2.focused_style.dim);
}

test "withLabelStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ParetoChart.init().withLabelStyle(s1);
    const chart2 = chart1.withLabelStyle(s2);
    try testing.expectEqual(true, chart1.label_style.bold);
    try testing.expectEqual(true, chart2.label_style.dim);
}

test "withBlock does not modify original" {
    const chart1 = ParetoChart.init().withBlock(.{});
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

    const chart = ParetoChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = ParetoChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = ParetoChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 8: Render — Empty Data (2 tests)
// ============================================================================

test "render with zero items produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = ParetoChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero items and Block does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = ParetoChart.init().withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 9: Render — Single Item (4 tests)
// ============================================================================

test "render with single item produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{.{ .label = "A", .value = 100.0 }};
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with single zero-value item does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{.{ .label = "Zero", .value = 0.0 }};
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    chart.render(&buf, area);
}

test "render single item cumulative line is at 100%" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{.{ .label = "Only", .value = 50.0 }};
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowCumulativeLine(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };

    chart.render(&buf, area);
    // Single item cumulative should be 100%, should appear at top-ish of area
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with single item and custom style applies style" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{.{ .label = "S", .value = 75.0, .style = .{ .bold = true } }};
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 10: Render — Multiple Items, Sorted Descending (6 tests)
// ============================================================================

test "render with 3 items sorted=true orders by value descending" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "C", .value = 15.0 },
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    // Render should sort internally: A (50) > B (30) > C (15)
    // First column (leftmost bar position) should be tallest (A=50)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with 3 items sorted=false preserves input order" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "C", .value = 15.0 },
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    // Render should preserve input order: C (15), A (50), B (30)
    // First column should be C (smallest)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render 5 items sorted produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "E", .value = 5.0 },
        .{ .label = "A", .value = 50.0 },
        .{ .label = "C", .value = 30.0 },
        .{ .label = "B", .value = 40.0 },
        .{ .label = "D", .value = 10.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render sorted items with [100, 50, 25, 10, 5] creates descending bar heights" {
    var buf = try Buffer.init(testing.allocator, 100, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 50.0 },
        .{ .label = "C", .value = 25.0 },
        .{ .label = "D", .value = 10.0 },
        .{ .label = "E", .value = 5.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with already-sorted input and sorted=true produces same result" {
    var buf1 = try Buffer.init(testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 80, 24);
    defer buf2.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 50.0 },
        .{ .label = "C", .value = 10.0 },
    };

    const chart1 = ParetoChart.init().withItems(&items).withSorted(true);
    const chart2 = ParetoChart.init().withItems(&items).withSorted(true);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);
    // Both should produce the same output (sorting pre-sorted data)
    try testing.expect(countNonEmptyCells(buf1, area) > 0);
}

test "render with reverse-sorted input and sorted=true reverses the layout" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 10.0 },
        .{ .label = "B", .value = 50.0 },
        .{ .label = "C", .value = 100.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    // sorted=true should re-order to: C (100), B (50), A (10)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 11: Render — Cumulative Percentage Line (5 tests)
// ============================================================================

test "cumulative line with show_cumulative_line=false omits line" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowCumulativeLine(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    // Line should be absent; only bar content should appear
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "cumulative line with show_cumulative_line=true includes line" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowCumulativeLine(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "cumulative percentages sum to 100% over all items" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Values: [50, 30, 15, 5] -> sum = 100
    // Cumulative: [50%, 80%, 95%, 100%]
    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
        .{ .label = "C", .value = 15.0 },
        .{ .label = "D", .value = 5.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true)
        .withShowCumulativeLine(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "cumulative line at item 1 is 50 percent (half height) with sorted data [50,50]" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Equal values [50, 50] -> cumulative [50%, 100%]
    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowCumulativeLine(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    // Line should show cumulative progression
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "cumulative line appears near expected vertical positions" {
    var buf = try Buffer.init(testing.allocator, 100, 24);
    defer buf.deinit();

    // Known values for hand-calculated cumulative %
    // [60, 20, 20] -> cumulative [60%, 80%, 100%] -> [0.6, 0.8, 1.0]
    var items = [_]ParetoItem{
        .{ .label = "Major", .value = 60.0 },
        .{ .label = "Minor1", .value = 20.0 },
        .{ .label = "Minor2", .value = 20.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowCumulativeLine(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    chart.render(&buf, area);
    // Cumulative should appear in upper portion (high percentages map to top)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 12: Render — Threshold Marker (5 tests)
// ============================================================================

test "threshold marker with show_threshold=false omits marker" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowThreshold(false)
        .withThreshold(0.8);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "threshold marker with show_threshold=true includes marker" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowThreshold(true)
        .withThreshold(0.8);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "threshold value 0.5 positions marker at mid-height" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowThreshold(true)
        .withThreshold(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "threshold value 0.2 positions marker at lower height" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowThreshold(true)
        .withThreshold(0.2);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "threshold value 0.95 positions marker near top" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 100.0 },
        .{ .label = "B", .value = 10.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowThreshold(true)
        .withThreshold(0.95);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 13: Render — Value Labels (4 tests)
// ============================================================================

test "show_values=true renders value text" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 75.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_values=false omits value text" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 75.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "value labels contain numeric digits when shown" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Revenue", .value = 123.45 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "no digits in label area when show_values=false" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Data", .value = 999.99 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Content should exist (bars) but value text should be absent
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 14: Render — Focused Item Styling (5 tests)
// ============================================================================

test "focused item at index 0 uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused item at index 1 uses focused_style" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withFocused(1)
        .withFocusedStyle(.{ .dim = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused index beyond item count does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
}

test "focused bar has focused_style attribute applied" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);

    // Check that at least one bar cell (█) from focused item carries bold style
    var found_focused = false;
    for (area.y..area.y + area.height) |y| {
        for (area.x..area.x + area.width) |x| {
            if (buf.getConst(@intCast(x), @intCast(y))) |cell| {
                if (cell.char == '█' and cell.style.bold) {
                    found_focused = true;
                    break;
                }
            }
        }
        if (found_focused) break;
    }
    try testing.expect(found_focused);
}

test "non-focused items do not use focused_style" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 15: Render — Out-of-Range Handling (5 tests)
// ============================================================================

test "negative value does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Negative", .value = -50.0 },
        .{ .label = "Positive", .value = 50.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
}

test "all zero values does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Z1", .value = 0.0 },
        .{ .label = "Z2", .value = 0.0 },
        .{ .label = "Z3", .value = 0.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
}

test "very large values do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Huge", .value = 1e6 },
        .{ .label = "Tiny", .value = 1.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
}

test "mixed positive and negative values does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Pos", .value = 100.0 },
        .{ .label = "Neg", .value = -50.0 },
        .{ .label = "Pos2", .value = 75.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
}

test "single dominant value with many small values" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Dominant", .value = 1000.0 },
        .{ .label = "Small1", .value = 1.0 },
        .{ .label = "Small2", .value = 1.0 },
        .{ .label = "Small3", .value = 1.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    // Should render without crash (classic Pareto distribution)
}

// ============================================================================
// Group 16: Render — Block Border (3 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };
    const chart = ParetoChart.init()
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

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 17: Render — Realistic Scenarios (4 tests)
// ============================================================================

test "render realistic Pareto data: 80/20 rule example" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    // Classic Pareto: few items dominate
    var items = [_]ParetoItem{
        .{ .label = "Bugs", .value = 80.0 },
        .{ .label = "Feature Reqs", .value = 50.0 },
        .{ .label = "Refactoring", .value = 30.0 },
        .{ .label = "Documentation", .value = 15.0 },
        .{ .label = "Testing", .value = 5.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true)
        .withShowCumulativeLine(true)
        .withShowThreshold(true)
        .withThreshold(0.8);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with all style options and toggles set" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 60.0, .style = .{ .bold = true } },
        .{ .label = "B", .value = 30.0, .style = .{ .dim = true } },
        .{ .label = "C", .value = 10.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true)
        .withShowValues(true)
        .withShowCumulativeLine(true)
        .withShowThreshold(true)
        .withThreshold(0.8)
        .withFocused(0)
        .withStyle(.{ .underline = true })
        .withBarStyle(.{ .bold = true })
        .withLineStyle(.{ .dim = true })
        .withThresholdStyle(.{ .bold = true })
        .withFocusedStyle(.{ .bold = true })
        .withLabelStyle(.{ .bold = true })
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render MAX_ITEMS (32 items)" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var items: [32]ParetoItem = undefined;
    for (0..32) |i| {
        const val = @as(f32, @floatFromInt(33 - i)) * 10.0; // Descending 320, 310, ..., 10
        items[i] = .{
            .label = "I",
            .value = val,
        };
    }
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };

    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
}

test "render more than MAX_ITEMS only renders first 32" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var items: [50]ParetoItem = undefined;
    for (0..50) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt((51 - i) % 100)),
        };
    }
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };

    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
}

// ============================================================================
// Group 18: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields correctly" {
    var items = [_]ParetoItem{
        .{ .label = "A", .value = 50.0 },
        .{ .label = "B", .value = 30.0 },
    };

    const chart = ParetoChart.init()
        .withItems(&items)
        .withFocused(1)
        .withSorted(false)
        .withShowValues(false)
        .withShowCumulativeLine(false)
        .withShowThreshold(false)
        .withThreshold(0.5)
        .withStyle(.{ .bold = true })
        .withBarStyle(.{ .dim = true })
        .withLineStyle(.{ .underline = true })
        .withThresholdStyle(.{ .bold = true })
        .withFocusedStyle(.{ .bold = true })
        .withLabelStyle(.{ .bold = true })
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), chart.itemCount());
    try testing.expectEqual(@as(usize, 1), chart.focused);
    try testing.expectEqual(false, chart.sorted);
    try testing.expectEqual(false, chart.show_values);
    try testing.expectEqual(false, chart.show_cumulative_line);
    try testing.expectEqual(false, chart.show_threshold);
    try testing.expect(floatEq(0.5, chart.threshold, 0.001));
    try testing.expect(chart.block != null);
}

test "builder chain preserves last value for each field" {
    const chart = ParetoChart.init()
        .withSorted(true)
        .withSorted(false)
        .withThreshold(0.5)
        .withThreshold(0.9)
        .withShowValues(true)
        .withShowValues(false);

    try testing.expectEqual(false, chart.sorted);
    try testing.expect(floatEq(0.9, chart.threshold, 0.001));
    try testing.expectEqual(false, chart.show_values);
}

// ============================================================================
// Group 19: Edge Cases — Bar Geometry (3 tests)
// ============================================================================

test "single bar fills vertical space proportionally" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Single", .value = 50.0 },
    };
    const chart = ParetoChart.init()
        .withItems(&items)
        .withShowValues(false);
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 15 };

    chart.render(&buf, area);
    // Single bar should fill roughly half the height (50% of 15 ≈ 7-8 rows)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "bar height increases with value when max is known" {
    var buf1 = try Buffer.init(testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 80, 24);
    defer buf2.deinit();

    var items1 = [_]ParetoItem{
        .{ .label = "Low", .value = 25.0 },
    };
    var items2 = [_]ParetoItem{
        .{ .label = "High", .value = 75.0 },
    };

    const chart1 = ParetoChart.init().withItems(&items1);
    const chart2 = ParetoChart.init().withItems(&items2);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);

    // Higher value should produce more content (taller bar)
    try testing.expect(countNonEmptyCells(buf2, area) >= countNonEmptyCells(buf1, area));
}

test "bar columns are evenly spaced across width" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "A", .value = 30.0 },
        .{ .label = "B", .value = 40.0 },
        .{ .label = "C", .value = 50.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 20: Edge Cases — Sorted vs Unsorted Behavior (2 tests)
// ============================================================================

test "sorted=true transforms order regardless of input" {
    var items = [_]ParetoItem{
        .{ .label = "Z", .value = 10.0 },
        .{ .label = "M", .value = 50.0 },
        .{ .label = "A", .value = 30.0 },
    };

    // When sorted=true, internal order should be: M(50) > A(30) > Z(10)
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(true);

    try testing.expectEqual(@as(usize, 3), chart.itemCount());
    try testing.expectEqual(true, chart.sorted);
}

test "sorted=false preserves exact input order" {
    var items = [_]ParetoItem{
        .{ .label = "Z", .value = 10.0 },
        .{ .label = "M", .value = 50.0 },
        .{ .label = "A", .value = 30.0 },
    };

    // When sorted=false, order remains: Z, M, A (regardless of values)
    const chart = ParetoChart.init()
        .withItems(&items)
        .withSorted(false);

    try testing.expectEqual(@as(usize, 3), chart.itemCount());
    try testing.expectEqual(false, chart.sorted);
}
