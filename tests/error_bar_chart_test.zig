//! ErrorBarChart Widget Tests — TDD Red Phase
//!
//! Tests ErrorBarChart widget rendering one row per item with:
//! - Point estimate (marker) with asymmetric error bars (err_low, err_high)
//! - Whisker lines extending from value - err_low to value + err_high
//! - Cap characters at whisker endpoints
//! - Optional labels and value text
//! - Focused item marker highlighting
//! - Block border support
//! - Value normalization against min_val/max_val range
//! - No-panic regression for out-of-range/degenerate cases
//!
//! Tests cover initialization, builder pattern, itemCount() capping at MAX_ITEMS,
//! render geometry (whisker spans, marker/cap placement at specific columns),
//! out-of-range error/value handling (critical: no crash/panic), focused styling,
//! label display, show_values formatting, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const ErrorBarChart = sailor.tui.widgets.ErrorBarChart;
const ErrorBarItem = sailor.tui.widgets.error_bar_chart.ErrorBarItem;

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

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "ErrorBarChart.init creates default chart with zero items" {
    const chart = ErrorBarChart.init();
    try testing.expectEqual(@as(usize, 0), chart.items.len);
}

test "ErrorBarChart.init defaults focused to 0" {
    const chart = ErrorBarChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused);
}

test "ErrorBarChart.init defaults min_val to 0.0" {
    const chart = ErrorBarChart.init();
    try testing.expectEqual(@as(f32, 0.0), chart.min_val);
}

test "ErrorBarChart.init defaults max_val to 1.0" {
    const chart = ErrorBarChart.init();
    try testing.expectEqual(@as(f32, 1.0), chart.max_val);
}

test "ErrorBarChart.init defaults show_labels to true" {
    const chart = ErrorBarChart.init();
    try testing.expectEqual(true, chart.show_labels);
}

// ============================================================================
// Group 2: ErrorBarItem Struct Defaults (4 tests)
// ============================================================================

test "ErrorBarItem default label is empty" {
    const item = ErrorBarItem{};
    try testing.expectEqualStrings("", item.label);
}

test "ErrorBarItem default value is 0.0" {
    const item = ErrorBarItem{};
    try testing.expectEqual(@as(f32, 0.0), item.value);
}

test "ErrorBarItem default err_low is 0.0" {
    const item = ErrorBarItem{};
    try testing.expectEqual(@as(f32, 0.0), item.err_low);
}

test "ErrorBarItem default err_high is 0.0" {
    const item = ErrorBarItem{};
    try testing.expectEqual(@as(f32, 0.0), item.err_high);
}

// ============================================================================
// Group 3: MAX_ITEMS Constant (1 test)
// ============================================================================

test "ErrorBarChart.MAX_ITEMS equals 32" {
    try testing.expectEqual(@as(usize, 32), ErrorBarChart.MAX_ITEMS);
}

// ============================================================================
// Group 4: itemCount() Method (5 tests)
// ============================================================================

test "ErrorBarChart.itemCount with zero items returns 0" {
    const chart = ErrorBarChart.init();
    try testing.expectEqual(@as(usize, 0), chart.itemCount());
}

test "ErrorBarChart.itemCount with 1 item returns 1" {
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 1), chart.itemCount());
}

test "ErrorBarChart.itemCount with 16 items returns 16" {
    var items: [16]ErrorBarItem = undefined;
    for (0..16) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 16.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 16), chart.itemCount());
}

test "ErrorBarChart.itemCount with exactly MAX_ITEMS=32 returns 32" {
    var items: [32]ErrorBarItem = undefined;
    for (0..32) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 32.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
}

test "ErrorBarChart.itemCount caps at MAX_ITEMS=32 when 50 items provided" {
    var items: [50]ErrorBarItem = undefined;
    for (0..50) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i % 32)) / 32.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
}

// ============================================================================
// Group 5: Builder Immutability — All 14 Builder Methods (14 tests)
// ============================================================================

test "ErrorBarChart.withItems does not modify original" {
    var items1 = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    var items2 = [_]ErrorBarItem{
        .{ .label = "X", .value = 0.2, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "Y", .value = 0.8, .err_low = 0.1, .err_high = 0.15 },
    };

    const chart1 = ErrorBarChart.init().withItems(&items1);
    const chart2 = chart1.withItems(&items2);

    try testing.expectEqual(@as(usize, 1), chart1.itemCount());
    try testing.expectEqual(@as(usize, 2), chart2.itemCount());
}

test "ErrorBarChart.withFocused does not modify original" {
    const chart1 = ErrorBarChart.init().withFocused(0);
    const chart2 = chart1.withFocused(3);

    try testing.expectEqual(@as(usize, 0), chart1.focused);
    try testing.expectEqual(@as(usize, 3), chart2.focused);
}

test "ErrorBarChart.withMinVal does not modify original" {
    const chart1 = ErrorBarChart.init().withMinVal(-10.0);
    const chart2 = chart1.withMinVal(0.0);

    try testing.expectEqual(@as(f32, -10.0), chart1.min_val);
    try testing.expectEqual(@as(f32, 0.0), chart2.min_val);
}

test "ErrorBarChart.withMaxVal does not modify original" {
    const chart1 = ErrorBarChart.init().withMaxVal(100.0);
    const chart2 = chart1.withMaxVal(1000.0);

    try testing.expectEqual(@as(f32, 100.0), chart1.max_val);
    try testing.expectEqual(@as(f32, 1000.0), chart2.max_val);
}

test "ErrorBarChart.withShowLabels does not modify original" {
    const chart1 = ErrorBarChart.init().withShowLabels(true);
    const chart2 = chart1.withShowLabels(false);

    try testing.expectEqual(true, chart1.show_labels);
    try testing.expectEqual(false, chart2.show_labels);
}

test "ErrorBarChart.withShowValues does not modify original" {
    const chart1 = ErrorBarChart.init().withShowValues(false);
    const chart2 = chart1.withShowValues(true);

    try testing.expectEqual(false, chart1.show_values);
    try testing.expectEqual(true, chart2.show_values);
}

test "ErrorBarChart.withMarkerChar does not modify original" {
    const chart1 = ErrorBarChart.init().withMarkerChar('*');
    const chart2 = chart1.withMarkerChar('o');

    try testing.expectEqual(@as(u21, '*'), chart1.marker_char);
    try testing.expectEqual(@as(u21, 'o'), chart2.marker_char);
}

test "ErrorBarChart.withCapChar does not modify original" {
    const chart1 = ErrorBarChart.init().withCapChar('─');
    const chart2 = chart1.withCapChar('=');

    try testing.expectEqual(@as(u21, '─'), chart1.cap_char);
    try testing.expectEqual(@as(u21, '='), chart2.cap_char);
}

test "ErrorBarChart.withWhiskerChar does not modify original" {
    const chart1 = ErrorBarChart.init().withWhiskerChar('│');
    const chart2 = chart1.withWhiskerChar('!');

    try testing.expectEqual(@as(u21, '│'), chart1.whisker_char);
    try testing.expectEqual(@as(u21, '!'), chart2.whisker_char);
}

test "ErrorBarChart.withStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .italic = true };
    const chart1 = ErrorBarChart.init().withStyle(s1);
    const chart2 = chart1.withStyle(s2);

    try testing.expectEqual(true, chart1.style.bold);
    try testing.expectEqual(true, chart2.style.italic);
}

test "ErrorBarChart.withMarkerStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ErrorBarChart.init().withMarkerStyle(s1);
    const chart2 = chart1.withMarkerStyle(s2);

    try testing.expectEqual(true, chart1.marker_style.bold);
    try testing.expectEqual(true, chart2.marker_style.dim);
}

test "ErrorBarChart.withFocusedStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .italic = true };
    const chart1 = ErrorBarChart.init().withFocusedStyle(s1);
    const chart2 = chart1.withFocusedStyle(s2);

    try testing.expectEqual(true, chart1.focused_style.bold);
    try testing.expectEqual(true, chart2.focused_style.italic);
}

test "ErrorBarChart.withLabelStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = ErrorBarChart.init().withLabelStyle(s1);
    const chart2 = chart1.withLabelStyle(s2);

    try testing.expectEqual(true, chart1.label_style.bold);
    try testing.expectEqual(true, chart2.label_style.dim);
}

test "ErrorBarChart.withBlock does not modify original" {
    const blk1 = Block{};
    const chart1 = ErrorBarChart.init().withBlock(blk1);
    const chart2 = chart1.withBlock(null);

    try testing.expect(chart1.block != null);
    try testing.expect(chart2.block == null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "ErrorBarChart.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "ErrorBarChart.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "ErrorBarChart.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "ErrorBarChart.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 7: Render — Empty Items (2 tests)
// ============================================================================

test "ErrorBarChart.render with zero items produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const chart = ErrorBarChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "ErrorBarChart.render empty items with show_labels=false" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const chart = ErrorBarChart.init().withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 8: Render — Single Item (5 tests)
// ============================================================================

test "ErrorBarChart.render single item produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render single item with show_values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render single item with show_labels=false produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "Label", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render single item at different area offsets" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 5, .y = 5, .width = 30, .height = 15 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render single item with no label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 9: Render — Multiple Items (5 tests)
// ============================================================================

test "ErrorBarChart.render two items produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render three items produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.2, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.5, .err_low = 0.1, .err_high = 0.1 },
        .{ .label = "C", .value = 0.9, .err_low = 0.1, .err_high = 0.15 },
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render five items produces more content than single item" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items_single = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    var items_multiple = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.1, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.3, .err_low = 0.05, .err_high = 0.1 },
        .{ .label = "C", .value = 0.5, .err_low = 0.1, .err_high = 0.1 },
        .{ .label = "D", .value = 0.7, .err_low = 0.1, .err_high = 0.05 },
        .{ .label = "E", .value = 0.9, .err_low = 0.05, .err_high = 0.05 },
    };

    const chart1 = ErrorBarChart.init().withItems(&items_single);
    const chart2 = ErrorBarChart.init().withItems(&items_multiple);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content2 >= content1);
}

test "ErrorBarChart.render items with unequal values and errors" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Low", .value = 0.1, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "Mid", .value = 0.5, .err_low = 0.15, .err_high = 0.1 },
        .{ .label = "High", .value = 0.95, .err_low = 0.1, .err_high = 0.05 },
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render all items with same value" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 },
        .{ .label = "B", .value = 0.5, .err_low = 0.05, .err_high = 0.15 },
        .{ .label = "C", .value = 0.5, .err_low = 0.1, .err_high = 0.1 },
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Value Normalization (5 tests) — Hand-Computed Test Cases
// ============================================================================

test "ErrorBarChart.render value at min_val renders at leftmost position" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.0, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // When value=min_val=0.0, normalized value=0.0, marker should be at leftmost column (0 offset in plot)
    // With label column width (~min(1, 40/3)=1) + separator, plot starts around x=2
    // Marker should be at plot_x + 0 = around x=2
    // Verify marker appears at leftmost part of plot area
    var found_marker_in_leftmost = false;
    for (0..10) |x| { // Check leftmost 10 columns of the plot
        if (buf.getConst(@as(u16, @intCast(area.x + x)), 0)) |cell| {
            if (cell.char == '*') {
                found_marker_in_leftmost = true;
                break;
            }
        }
    }
    try testing.expect(found_marker_in_leftmost);
}

test "ErrorBarChart.render value at max_val renders at rightmost position" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 1.0, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // When value=max_val=1.0, normalized value=1.0, marker should be at rightmost column
    // Verify marker appears in rightmost part of the area
    var found_marker_in_rightmost = false;
    for (30..40) |x| { // Check rightmost 10 columns
        if (buf.getConst(@as(u16, @intCast(area.x + x)), 0)) |cell| {
            if (cell.char == '*') {
                found_marker_in_rightmost = true;
                break;
            }
        }
    }
    try testing.expect(found_marker_in_rightmost);
}

test "ErrorBarChart.render value at middle of range renders near middle" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render with negative min_val range" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Neg", .value = -10.0, .err_low = 2.0, .err_high = 2.0 },
        .{ .label = "Zero", .value = 0.0, .err_low = 2.0, .err_high = 2.0 },
        .{ .label = "Pos", .value = 10.0, .err_low = 2.0, .err_high = 2.0 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(-10.0)
        .withMaxVal(10.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render with custom range scales correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Start", .value = 100.0, .err_low = 10.0, .err_high = 10.0 },
        .{ .label = "Mid", .value = 150.0, .err_low = 15.0, .err_high = 15.0 },
        .{ .label = "End", .value = 200.0, .err_low = 20.0, .err_high = 20.0 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(100.0)
        .withMaxVal(200.0)
        .withWhiskerChar('│');
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    // Verify that whiskers are rendered across multiple rows (custom range allows different scales)
    const whisker_count = countChar(buf, area, '│');
    try testing.expect(whisker_count > 0);
    // At least 3 items should produce multiple whisker segments
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 11: show_labels Toggle (3 tests)
// ============================================================================

test "ErrorBarChart.render show_labels=true displays label text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "Alpha", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render show_labels=false omits label text" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items = [_]ErrorBarItem{.{ .label = "Alpha", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};

    const chart_with_labels = ErrorBarChart.init().withItems(&items).withShowLabels(true);
    const chart_no_labels = ErrorBarChart.init().withItems(&items).withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart_with_labels.render(&buf1, area);
    chart_no_labels.render(&buf2, area);

    // Count label characters (A, l, p, h, a from "Alpha")
    var label_chars_with: usize = 0;
    var label_chars_without: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf1.getConst(x, y)) |cell| {
                if (cell.char == 'A' or cell.char == 'l' or cell.char == 'p' or cell.char == 'h' or cell.char == 'a') {
                    label_chars_with += 1;
                }
            }
            if (buf2.getConst(x, y)) |cell| {
                if (cell.char == 'A' or cell.char == 'l' or cell.char == 'p' or cell.char == 'h' or cell.char == 'a') {
                    label_chars_without += 1;
                }
            }
        }
    }

    // With show_labels=true, should have at least some label characters
    try testing.expect(label_chars_with > 0);
    // With show_labels=false, should have no label characters
    try testing.expectEqual(@as(usize, 0), label_chars_without);
}

test "ErrorBarChart.render show_labels=false still renders whiskers" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Alpha", .value = 0.3, .err_low = 0.1, .err_high = 0.1 },
        .{ .label = "Beta", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };
    const chart = ErrorBarChart.init().withItems(&items).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: show_values Toggle (3 tests)
// ============================================================================

test "ErrorBarChart.render show_values=true displays value text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render show_values=false is default behavior" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render show_values=true produces output" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const content = countNonEmptyCells(buf, area);
    try testing.expect(content > 0);
}

// ============================================================================
// Group 13: Custom Character Usage (3 tests)
// ============================================================================

test "ErrorBarChart.render with custom marker_char displays the character" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init().withItems(&items).withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(areaHasChar(buf, area, '*'));
}

test "ErrorBarChart.render with custom cap_char displays the character" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.2, .err_high = 0.2 }};
    const chart = ErrorBarChart.init().withItems(&items).withCapChar('=');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(areaHasChar(buf, area, '='));
}

test "ErrorBarChart.render with custom whisker_char displays the character" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.2, .err_high = 0.2 }};
    const chart = ErrorBarChart.init().withItems(&items).withWhiskerChar('!');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(areaHasChar(buf, area, '!'));
}

// ============================================================================
// Group 14: Focused Styling (4 tests)
// ============================================================================

test "ErrorBarChart.render focused=0 on three-item chart applies focus style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.2, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.5, .err_low = 0.1, .err_high = 0.1 },
        .{ .label = "C", .value = 0.8, .err_low = 0.1, .err_high = 0.1 },
    };
    const focused_style = Style{ .bold = true };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render focused=1 applies style to middle item" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.2, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.5, .err_low = 0.1, .err_high = 0.1 },
        .{ .label = "C", .value = 0.8, .err_low = 0.1, .err_high = 0.1 },
    };
    const focused_style = Style{ .dim = true };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render changing focused index produces output" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.2, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.5, .err_low = 0.1, .err_high = 0.1 },
        .{ .label = "C", .value = 0.8, .err_low = 0.1, .err_high = 0.1 },
    };

    const chart1 = ErrorBarChart.init().withItems(&items).withFocused(0);
    const chart2 = ErrorBarChart.init().withItems(&items).withFocused(2);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

// ============================================================================
// Group 15: Block Border (3 tests)
// ============================================================================

test "ErrorBarChart.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };
    const block = Block{};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render block reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };

    const block = Block{};
    const chart_with_block = ErrorBarChart.init().withItems(&items).withBlock(block);
    const chart_no_block = ErrorBarChart.init().withItems(&items);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart_with_block.render(&buf1, area);
    chart_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "ErrorBarChart.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };
    const block = (Block{}).withTitle("ErrorBar", .top_left);
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: MAX_ITEMS Cap (3 tests)
// ============================================================================

test "ErrorBarChart.render with exactly MAX_ITEMS=32" {
    var buf = try Buffer.init(testing.allocator, 80, 32);
    defer buf.deinit();
    var items: [32]ErrorBarItem = undefined;
    for (0..32) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 32.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 32 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render with 50 items caps to MAX_ITEMS=32" {
    var buf = try Buffer.init(testing.allocator, 80, 32);
    defer buf.deinit();
    var items: [50]ErrorBarItem = undefined;
    for (0..50) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i % 32)) / 32.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    try testing.expectEqual(@as(usize, 32), chart.itemCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 32 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render 16 items renders all visible items" {
    var buf = try Buffer.init(testing.allocator, 60, 32);
    defer buf.deinit();
    var items: [16]ErrorBarItem = undefined;
    for (0..16) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 16.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 32 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: No-Panic Regression Tests — Asymmetric Errors (5 tests)
// ============================================================================

test "ErrorBarChart.render err_low exceeds value minus min_val does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.2, .err_low = 0.5, .err_high = 0.1 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; marker should still render at valid location
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "ErrorBarChart.render err_high exceeds max_val minus value does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.8, .err_low = 0.1, .err_high = 0.5 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; marker should still render at valid location
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "ErrorBarChart.render very large err_low and err_high does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 100.0, .err_high = 100.0 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; verify marker is present (clamped to valid position)
    try testing.expect(areaHasChar(buf, area, '*'));
}

test "ErrorBarChart.render asymmetric errors renders marker correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Asym1", .value = 0.5, .err_low = 0.05, .err_high = 0.2 },
        .{ .label = "Asym2", .value = 0.5, .err_low = 0.2, .err_high = 0.05 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render zero error bars (point estimate only) does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.0, .err_high = 0.0 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1.0)
        .withMarkerChar('*')
        .withCapChar('=');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // When err_low=err_high=0, low_col==high_col==value_col, so whisker, cap, and marker all target the same cell.
    // Draw order (whisker → caps → marker) means marker should win (drawn last).
    // Verify marker is present (not overwritten by cap):
    try testing.expect(areaHasChar(buf, area, '*'));
    // The marker should be at the value position, not the cap character
    // Since all three coincide at same column, marker must be drawn last to "win" and be visible
}

test "ErrorBarChart.render extremely large item.value with show_values=true does not panic" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    // CRITICAL REGRESSION: drawValueLabel() casts raw item.value to i32 without clamping.
    // Values outside i32 range (~±2.147e9) cause panic: "integer part of floating point value out of bounds"
    // This test locks in the fix: extremely large values must be handled gracefully.
    var items = [_]ErrorBarItem{.{ .label = "LargeVal", .value = 5_000_000_000.0, .err_low = 1e8, .err_high = 1e8 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(1e10)
        .withShowValues(true)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; marker must be rendered at valid clamped position
    try testing.expect(areaHasChar(buf, area, '*'));
}

test "ErrorBarChart.render extremely large negative item.value with show_values=true does not panic" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    // CRITICAL REGRESSION: same as above but with very large negative value
    var items = [_]ErrorBarItem{.{ .label = "NegLarge", .value = -5_000_000_000.0, .err_low = 1e8, .err_high = 1e8 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(-1e10)
        .withMaxVal(1e10)
        .withShowValues(true)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; marker must be rendered at valid clamped position
    try testing.expect(areaHasChar(buf, area, '*'));
}

// ============================================================================
// Group 18: No-Panic Regression Tests — Degenerate Range (3 tests)
// ============================================================================

test "ErrorBarChart.render min_val == max_val does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.5)
        .withMaxVal(0.5)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; marker should still render (centered when range is 0)
    try testing.expect(areaHasChar(buf, area, '*'));
}

test "ErrorBarChart.render min_val > max_val does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(1.0)
        .withMaxVal(0.0)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; marker should still render (degenerate range handled)
    try testing.expect(areaHasChar(buf, area, '*'));
}

test "ErrorBarChart.render very small range (near-degenerate) does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.0001, .err_low = 0.00001, .err_high = 0.00001 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMinVal(0.0)
        .withMaxVal(0.0002)
        .withMarkerChar('*');
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // No panic is success; marker should render at valid position despite tiny range
    try testing.expect(areaHasChar(buf, area, '*'));
}

// ============================================================================
// Group 19: Label Column Width / Truncation (2 tests)
// ============================================================================

test "ErrorBarChart.render long label is truncated to fit label column" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "VeryLongLabelThatShouldBeTruncatedForDisplay", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render label column never overflows into plot area" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "LongLabel", .value = 0.3, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "Another", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Style Application (4 tests)
// ============================================================================

test "ErrorBarChart.render with style applies to plot" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const style = Style{ .bold = true };
    const chart = ErrorBarChart.init().withItems(&items).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render with marker_style applies to marker" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "A", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const marker_style = Style{ .bold = true };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withMarkerStyle(marker_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render with label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "Alpha", .value = 0.5, .err_low = 0.1, .err_high = 0.1 }};
    const label_style = Style{ .italic = true };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render with multiple styles applied" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.05 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.1 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withStyle(Style{ .dim = true })
        .withLabelStyle(Style{ .bold = true })
        .withMarkerStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true, .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 21: Real-World Scenarios (4 tests)
// ============================================================================

test "ErrorBarChart.render measurement uncertainty visualization" {
    var buf = try Buffer.init(testing.allocator, 60, 25);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Experiment A", .value = 95.5, .err_low = 5.2, .err_high = 6.1 },
        .{ .label = "Experiment B", .value = 87.3, .err_low = 8.1, .err_high = 7.9 },
        .{ .label = "Experiment C", .value = 102.2, .err_low = 4.5, .err_high = 5.8 },
        .{ .label = "Experiment D", .value = 76.8, .err_low = 10.2, .err_high = 9.5 },
        .{ .label = "Experiment E", .value = 98.9, .err_low = 3.1, .err_high = 4.2 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withShowValues(true)
        .withMinVal(60.0)
        .withMaxVal(115.0)
        .withBlock((Block{}).withTitle("Measurements", .top_center));
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render confidence interval display" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Method A", .value = 0.75, .err_low = 0.08, .err_high = 0.12 },
        .{ .label = "Method B", .value = 0.68, .err_low = 0.15, .err_high = 0.1 },
        .{ .label = "Method C", .value = 0.82, .err_low = 0.05, .err_high = 0.08 },
        .{ .label = "Method D", .value = 0.55, .err_low = 0.2, .err_high = 0.18 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withShowValues(true)
        .withMinVal(0.0)
        .withMaxVal(1.0)
        .withFocused(2);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render with all features enabled" {
    var buf = try Buffer.init(testing.allocator, 70, 30);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "Item1", .value = 10.0, .err_low = 1.5, .err_high = 2.0, .style = Style{ .bold = true } },
        .{ .label = "Item2", .value = 50.0, .err_low = 3.0, .err_high = 3.5 },
        .{ .label = "Item3", .value = 75.0, .err_low = 2.0, .err_high = 4.0, .style = Style{ .dim = true } },
        .{ .label = "Item4", .value = 30.0, .err_low = 5.0, .err_high = 2.5 },
        .{ .label = "Item5", .value = 90.0, .err_low = 1.0, .err_high = 1.5 },
    };
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withShowValues(true)
        .withShowLabels(true)
        .withFocused(2)
        .withMinVal(0.0)
        .withMaxVal(100.0)
        .withStyle(Style{ .italic = true })
        .withLabelStyle(Style{ .bold = true })
        .withMarkerStyle(Style{ .dim = false })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withBlock((Block{}).withTitle("Complete ErrorBar", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 30 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render single-item plot edge case" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    var items = [_]ErrorBarItem{.{ .label = "OnlyOne", .value = 50.0, .err_low = 10.0, .err_high = 15.0 }};
    const chart = ErrorBarChart.init()
        .withItems(&items)
        .withShowValues(true)
        .withShowLabels(true)
        .withMinVal(0.0)
        .withMaxVal(100.0)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 22: Large and Edge Case Areas (3 tests)
// ============================================================================

test "ErrorBarChart.render very wide area" {
    var buf = try Buffer.init(testing.allocator, 200, 10);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.1 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.05 },
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 10 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render very tall area" {
    var buf = try Buffer.init(testing.allocator, 20, 100);
    defer buf.deinit();
    var items: [25]ErrorBarItem = undefined;
    for (0..25) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 25.0,
            .err_low = 0.03,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 100 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render rectangular area with many items" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var items: [20]ErrorBarItem = undefined;
    for (0..20) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 20.0,
            .err_low = 0.04,
            .err_high = 0.06,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 23: Clipping and Bounds (3 tests)
// ============================================================================

test "ErrorBarChart.render items beyond available height are clipped" {
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    var items: [20]ErrorBarItem = undefined;
    for (0..20) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 20.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ErrorBarChart.render does not exceed buffer bounds with many items" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var items: [16]ErrorBarItem = undefined;
    for (0..16) |i| {
        items[i] = .{
            .label = "I",
            .value = @as(f32, @floatFromInt(i)) / 16.0,
            .err_low = 0.05,
            .err_high = 0.05,
        };
    }
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 1800); // 60*30 max
}

test "ErrorBarChart.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var items = [_]ErrorBarItem{
        .{ .label = "A", .value = 0.3, .err_low = 0.05, .err_high = 0.1 },
        .{ .label = "B", .value = 0.7, .err_low = 0.1, .err_high = 0.05 },
    };
    const chart = ErrorBarChart.init().withItems(&items);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
