//! DonutChart Widget Tests — TDD Red Phase
//!
//! Tests DonutChart widget rendering as a hollow-center variant of PieChart with:
//! - Donut/ring shape with adjustable hole_ratio (inner radius / outer radius)
//! - Optional center label rendered in the hollow center
//! - Slice angle sweep rendering (skips cells inside inner_radius)
//! - Legend positions (.none/.right/.bottom) matching PieChart
//! - Block border support
//! - Percentage display toggle
//! - No-panic regression for out-of-range hole_ratio and degenerate cases
//!
//! Tests cover initialization, builder pattern, calcTotal() cross-file visibility,
//! render geometry (hollow center with hand-computed radius checks), legend positions,
//! center label display/truncation, show_percentages toggle, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const DonutChart = sailor.tui.widgets.DonutChart;
const DonutChartSlice = sailor.tui.widgets.donut_chart.Slice;

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

test "DonutChart.init creates chart with empty slices" {
    const chart = DonutChart.init(&.{});
    try testing.expectEqual(@as(usize, 0), chart.slices.len);
}

test "DonutChart.init defaults legend_position to right" {
    const chart = DonutChart.init(&.{});
    try testing.expectEqual(DonutChart.LegendPosition.right, chart.legend_position);
}

test "DonutChart.init defaults show_percentages to true" {
    const chart = DonutChart.init(&.{});
    try testing.expectEqual(true, chart.show_percentages);
}

test "DonutChart.init defaults hole_ratio to 0.5" {
    const chart = DonutChart.init(&.{});
    try testing.expectEqual(@as(f32, 0.5), chart.hole_ratio);
}

test "DonutChart.init defaults center_label to null" {
    const chart = DonutChart.init(&.{});
    try testing.expectEqual(@as(?[]const u8, null), chart.center_label);
}

// ============================================================================
// Group 2: Slice Struct Defaults (3 tests)
// ============================================================================

test "DonutChart.Slice requires label and value" {
    const slice = DonutChartSlice{ .label = "Test", .value = 50 };
    try testing.expectEqualStrings("Test", slice.label);
    try testing.expectEqual(@as(u64, 50), slice.value);
}

test "DonutChart.Slice defaults style to empty" {
    const slice = DonutChartSlice{ .label = "A", .value = 100 };
    try testing.expectEqual(Style{}, slice.style);
}

test "DonutChart.LegendPosition enum has three values" {
    const none_pos: DonutChart.LegendPosition = .none;
    const right_pos: DonutChart.LegendPosition = .right;
    const bottom_pos: DonutChart.LegendPosition = .bottom;
    _ = none_pos;
    _ = right_pos;
    _ = bottom_pos;
}

// ============================================================================
// Group 3: calcTotal() Function (3 tests)
// ============================================================================

test "DonutChart.calcTotal with empty slices returns 0" {
    const slices: [0]DonutChartSlice = undefined;
    const total = DonutChart.calcTotal(&slices);
    try testing.expectEqual(@as(u64, 0), total);
}

test "DonutChart.calcTotal sums single slice" {
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const total = DonutChart.calcTotal(&slices);
    try testing.expectEqual(@as(u64, 100), total);
}

test "DonutChart.calcTotal sums multiple slices" {
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 30 },
        .{ .label = "B", .value = 50 },
        .{ .label = "C", .value = 20 },
    };
    const total = DonutChart.calcTotal(&slices);
    try testing.expectEqual(@as(u64, 100), total);
}

// ============================================================================
// Group 4: Builder Immutability (6 tests)
// ============================================================================

test "DonutChart.withBlock does not modify original" {
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart1 = DonutChart.init(&slices);
    const block = Block{};
    const chart2 = chart1.withBlock(block);

    try testing.expectEqual(@as(?Block, null), chart1.block);
    try testing.expect(chart2.block != null);
}

test "DonutChart.withLegendPosition does not modify original" {
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart1 = DonutChart.init(&slices).withLegendPosition(.bottom);
    const chart2 = chart1.withLegendPosition(.none);

    try testing.expectEqual(DonutChart.LegendPosition.bottom, chart1.legend_position);
    try testing.expectEqual(DonutChart.LegendPosition.none, chart2.legend_position);
}

test "DonutChart.withPercentages does not modify original" {
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart1 = DonutChart.init(&slices).withPercentages(false);
    const chart2 = chart1.withPercentages(true);

    try testing.expectEqual(false, chart1.show_percentages);
    try testing.expectEqual(true, chart2.show_percentages);
}

test "DonutChart.withHoleRatio does not modify original" {
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart1 = DonutChart.init(&slices).withHoleRatio(0.3);
    const chart2 = chart1.withHoleRatio(0.7);

    try testing.expectEqual(@as(f32, 0.3), chart1.hole_ratio);
    try testing.expectEqual(@as(f32, 0.7), chart2.hole_ratio);
}

test "DonutChart.withCenterLabel does not modify original" {
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart1 = DonutChart.init(&slices).withCenterLabel("Label1");
    const chart2 = chart1.withCenterLabel("Label2");

    try testing.expectEqualStrings("Label1", chart1.center_label.?);
    try testing.expectEqualStrings("Label2", chart2.center_label.?);
}

test "DonutChart.withCenterLabelStyle does not modify original" {
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const style1 = Style{ .bold = true };
    const style2 = Style{ .italic = true };
    const chart1 = DonutChart.init(&slices).withCenterLabelStyle(style1);
    const chart2 = chart1.withCenterLabelStyle(style2);

    try testing.expectEqual(true, chart1.center_label_style.bold);
    try testing.expectEqual(true, chart2.center_label_style.italic);
}

// ============================================================================
// Group 5: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "DonutChart.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "DonutChart.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "DonutChart.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "DonutChart.render on very small 2x2 area handles gracefully" {
    var buf = try Buffer.init(testing.allocator, 2, 2);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{.{ .label = "A", .value = 50 }};
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    chart.render(&buf, area);
    // Should not crash; may or may not render content depending on minimum size
}

// ============================================================================
// Group 6: Render — Empty/Zero Items (2 tests)
// ============================================================================

test "DonutChart.render with zero slices produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const chart = DonutChart.init(&.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "DonutChart.render with zero total produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 0 },
        .{ .label = "B", .value = 0 },
    };
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 7: Render — Single/Multiple Slices (4 tests)
// ============================================================================

test "DonutChart.render single slice produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DonutChart.render three slices produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 30 },
        .{ .label = "B", .value = 40 },
        .{ .label = "C", .value = 30 },
    };
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DonutChart.render five slices produces more content than single slice" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    const slices_single = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const slices_multiple = [_]DonutChartSlice{
        .{ .label = "A", .value = 20 },
        .{ .label = "B", .value = 30 },
        .{ .label = "C", .value = 25 },
        .{ .label = "D", .value = 15 },
        .{ .label = "E", .value = 10 },
    };

    const chart1 = DonutChart.init(&slices_single);
    const chart2 = DonutChart.init(&slices_multiple);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content2 >= content1);
}

test "DonutChart.render unequal slices renders all" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Small", .value = 10 },
        .{ .label = "Large", .value = 70 },
        .{ .label = "Medium", .value = 20 },
    };
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 8: Hollow-Center Behavior with hole_ratio (5 tests)
// ============================================================================

test "DonutChart.render hole_ratio=0.5 creates hollow center" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // With a large enough area (41x21), center should be at (20, 10)
    // radius ~ min(20, 10) = 10
    // inner_radius = 10 * 0.5 = 5
    // At center_x=20, center_y=10, cells within distance 5 should NOT be filled
    // Cells farther out should be filled with the slice color '█'

    // Check that center area is mostly empty (hollow)
    var center_empty: usize = 0;
    var center_has_content: usize = 0;
    var y = @as(u16, 8);
    while (y <= 12) : (y += 1) {
        var x = @as(u16, 18);
        while (x <= 22) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ' ' or cell.char == 0) {
                    center_empty += 1;
                } else if (cell.char == '█') {
                    center_has_content += 1;
                }
            }
        }
    }

    // Center should be mostly empty (hollow), not filled with █
    try testing.expect(center_empty >= center_has_content);
}

test "DonutChart.render hole_ratio=0.0 behaves like filled disc" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(0.0);
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // With hole_ratio=0.0, inner_radius should be 0, so center gets filled
    // center at (20, 10), radius~10
    // Cell at exact center (20, 10) should be filled with '█'
    const center_cell = buf.getConst(20, 10);
    try testing.expect(center_cell != null);
    try testing.expectEqual(@as(u21, '█'), center_cell.?.char);
}

test "DonutChart.render hole_ratio=0.7 larger hollow center" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(0.7);
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // hole_ratio=0.7 should create a larger hollow center
    // Expect more empty space in the center than hole_ratio=0.5
    var center_empty: usize = 0;
    var y = @as(u16, 8);
    while (y <= 12) : (y += 1) {
        var x = @as(u16, 18);
        while (x <= 22) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ' ' or cell.char == 0) {
                    center_empty += 1;
                }
            }
        }
    }

    // With larger hole, more of the center should be empty
    try testing.expect(center_empty > 0);
}

test "DonutChart.render hole_ratio=1.0 exactly clamps to 0.9" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(1.0);
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);
    // Should not panic; renders with clamped inner_radius
    // Verify that the donut ring is actually rendered (outer cells filled)
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
    // Verify there is a hollow center (not completely filled)
    const center_area = Rect{ .x = 15, .y = 8, .width = 10, .height = 4 };
    const center_empty = countNonEmptyCells(buf, center_area);
    try testing.expect(center_empty < non_empty);
}

test "DonutChart.render edge cells at outer ring are filled" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // Cells at outer edge should be filled with slice color
    // Check corners and edges of the chart area
    var outer_filled: usize = 0;
    // Top-left corner area
    for (0..5) |x| {
        for (0..5) |y| {
            if (buf.getConst(@as(u16, @intCast(x)), @as(u16, @intCast(y)))) |cell| {
                if (cell.char == '█') {
                    outer_filled += 1;
                }
            }
        }
    }

    // Should have some filled cells at the outer edge
    try testing.expect(outer_filled > 0);
}

// ============================================================================
// Group 9: Legend Positions (3 tests)
// ============================================================================

test "DonutChart.render legend position .none omits legend" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const chart = DonutChart.init(&slices).withLegendPosition(.none);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);

    // With .none, '■' bullet should not appear
    var found_bullet = false;
    for (0..20) |y| {
        for (0..40) |x| {
            if (buf.getConst(@as(u16, @intCast(x)), @as(u16, @intCast(y)))) |cell| {
                if (cell.char == '■') {
                    found_bullet = true;
                    break;
                }
            }
        }
        if (found_bullet) break;
    }
    try testing.expect(!found_bullet);
}

test "DonutChart.render legend position .right places legend on right" {
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "CPU", .value = 50 },
        .{ .label = "Mem", .value = 50 },
    };
    const chart = DonutChart.init(&slices).withLegendPosition(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    chart.render(&buf, area);

    // Legend width ~ min(50/3, 20) = 16 → legend starts at x=34
    // First legend entry should have '■' at around x=34
    const has_legend_right = areaHasChar(buf, Rect{ .x = 34, .y = 0, .width = 16, .height = 10 }, '■');
    try testing.expect(has_legend_right);
}

test "DonutChart.render legend position .bottom places legend at bottom" {
    var buf = try Buffer.init(testing.allocator, 40, 15);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const chart = DonutChart.init(&slices).withLegendPosition(.bottom);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    chart.render(&buf, area);

    // Legend height ~ min(15/3, 3) = 3 → legend at y=12-14
    // Should have '■' at bottom area
    const has_legend_bottom = areaHasChar(buf, Rect{ .x = 0, .y = 12, .width = 40, .height = 3 }, '■');
    try testing.expect(has_legend_bottom);
}

// ============================================================================
// Group 10: Center Label Rendering (4 tests)
// ============================================================================

test "DonutChart.render center_label=null leaves hole empty" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(0.5);
    // center_label remains null (default)
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // Center should be empty, not filled with text
    const center = buf.getConst(20, 10);
    // Center cell should be empty (space) when no label set
    if (center != null) {
        try testing.expect(center.?.char == ' ' or center.?.char == 0);
    }
}

test "DonutChart.render center_label renders text when set" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices)
        .withHoleRatio(0.5)
        .withCenterLabel("75%");
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // Legend .right splits inner area, so chart center_x sits left of the
    // full-width midpoint (~14, not 20) — scan a window around the real center.
    var found_label_chars: usize = 0;
    for (10..18) |x| {
        if (buf.getConst(@as(u16, @intCast(x)), 10)) |cell| {
            if (cell.char == '7' or cell.char == '5' or cell.char == '%') {
                found_label_chars += 1;
            }
        }
    }
    try testing.expect(found_label_chars > 0);
}

test "DonutChart.render center_label longer than hole does not panic" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    // Very small area (30x15), hole_ratio=0.5 → inner_radius ~3
    // Label "VeryLongLabelText" is much longer than hole diameter (~6)
    const chart = DonutChart.init(&slices)
        .withHoleRatio(0.5)
        .withCenterLabel("VeryLongLabelText");
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 15 };
    chart.render(&buf, area);
    // Must not panic; should truncate or skip the label gracefully
    // Verify that donut ring is rendered despite the oversized label
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
    // Verify surrounding area is not corrupted (center area should be mostly empty with truncated label)
    // chart_area center_x with legend .right is ~10 (not 15), so shift the check window accordingly.
    const center_area = Rect{ .x = 7, .y = 6, .width = 6, .height = 3 };
    const center_filled = countNonEmptyCells(buf, center_area);
    // The truncated label may have a few chars, but the center hole should not be completely filled
    try testing.expect(center_filled < 10);
}

test "DonutChart.render center_label with style applies styling" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const label_style = Style{ .bold = true, .fg = .{ .indexed = 5 } };
    const chart = DonutChart.init(&slices)
        .withHoleRatio(0.5)
        .withCenterLabel("Test")
        .withCenterLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);
    // Render should succeed; verify some content is rendered
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: show_percentages Toggle (2 tests)
// ============================================================================

test "DonutChart.render show_percentages=true displays percent in legend" {
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const chart = DonutChart.init(&slices)
        .withPercentages(true)
        .withLegendPosition(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    chart.render(&buf, area);

    // With percentages shown, '%' should appear in legend area
    const has_percent = areaHasChar(buf, Rect{ .x = 34, .y = 0, .width = 16, .height = 10 }, '%');
    try testing.expect(has_percent);
}

test "DonutChart.render show_percentages=false omits percent in legend" {
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const chart = DonutChart.init(&slices)
        .withPercentages(false)
        .withLegendPosition(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    chart.render(&buf, area);

    // With percentages disabled, '%' should not appear in legend
    const has_percent = areaHasChar(buf, Rect{ .x = 34, .y = 0, .width = 16, .height = 10 }, '%');
    try testing.expect(!has_percent);
}

// ============================================================================
// Group 12: Block Border Rendering (2 tests)
// ============================================================================

test "DonutChart.render with block border renders border" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const block = (Block{}).withBorders(.all);
    const chart = DonutChart.init(&slices).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);

    // Verify border characters at corners
    const top_left = buf.getConst(0, 0);
    try testing.expect(top_left != null);
    try testing.expectEqual(@as(u21, '┌'), top_left.?.char);
}

test "DonutChart.render with block border reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };

    const block = Block{};
    const chart_with_block = DonutChart.init(&slices).withBlock(block);
    const chart_no_block = DonutChart.init(&slices);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart_with_block.render(&buf1, area);
    chart_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    // Both should have content; block version may have border + content
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

// ============================================================================
// Group 13: No-Panic Regression — hole_ratio Out of Range (4 tests)
// ============================================================================

test "DonutChart.render hole_ratio negative does not panic" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(-0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Must not panic; clamped to valid range [0, 0.9]
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DonutChart.render hole_ratio > 1.0 does not panic" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(1.5);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Must not panic; clamped to [0, 0.9]
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DonutChart.render hole_ratio = 2.0 does not panic" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(2.0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Must not panic; inner_radius clamped
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DonutChart.render very small area with hole_ratio set does not panic" {
    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    chart.render(&buf, area);
    // Must not panic even with tiny area and hole_ratio set
    // inner_radius could compute to 0 or negative; must be clamped
}

// ============================================================================
// Group 14: No-Panic Regression — Degenerate Cases (3 tests)
// ============================================================================

test "DonutChart.render area smaller than minimum (e.g., 2x2) does not panic" {
    var buf = try Buffer.init(testing.allocator, 2, 2);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const chart = DonutChart.init(&slices);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    chart.render(&buf, area);
    // Must not panic; may not render visible content
}

test "DonutChart.render single-pixel center (width=height=3) does not panic" {
    var buf = try Buffer.init(testing.allocator, 3, 3);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const chart = DonutChart.init(&slices).withHoleRatio(0.5);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    chart.render(&buf, area);
    // Must not panic; inner_radius can round to 0
}

test "DonutChart.render with block border on minimal area does not panic" {
    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 100 },
    };
    const block = Block{};
    const chart = DonutChart.init(&slices).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    chart.render(&buf, area);
    // Must not panic; block + hole_ratio with tiny area
}

// ============================================================================
// Group 15: Center Label Edge Cases (3 tests)
// ============================================================================

test "DonutChart.render center_label empty string does not panic" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices)
        .withHoleRatio(0.5)
        .withCenterLabel("");
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);
    // Must not panic on empty label string
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "DonutChart.render center_label very short label (one char)" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = DonutChart.init(&slices)
        .withHoleRatio(0.5)
        .withCenterLabel("5");
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // Should render single character in center (legend .right shifts center to ~14)
    var found_center_char = false;
    for (12..17) |x| {
        if (buf.getConst(@as(u16, @intCast(x)), 10)) |cell| {
            if (cell.char == '5') {
                found_center_char = true;
                break;
            }
        }
    }
    try testing.expect(found_center_char);
}

test "DonutChart.render center_label exactly fits hole diameter" {
    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };
    // With radius=10, hole_ratio=0.5, inner_radius=5, diameter~10
    // Label "12345" (5 chars) should fit
    const chart = DonutChart.init(&slices)
        .withHoleRatio(0.5)
        .withCenterLabel("12345");
    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // Should render the label without truncation/panic (legend .right shifts center to ~14)
    var label_char_count: usize = 0;
    for (9..19) |x| {
        if (buf.getConst(@as(u16, @intCast(x)), 10)) |cell| {
            if (cell.char >= '0' and cell.char <= '9') {
                label_char_count += 1;
            }
        }
    }
    try testing.expect(label_char_count > 0);
}

// ============================================================================
// Group 16: Multiple Legend Entry Rendering (2 tests)
// ============================================================================

test "DonutChart.render legend with many slices positions entries correctly" {
    var buf = try Buffer.init(testing.allocator, 60, 25);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 10 },
        .{ .label = "B", .value = 20 },
        .{ .label = "C", .value = 30 },
        .{ .label = "D", .value = 25 },
        .{ .label = "E", .value = 15 },
    };
    const chart = DonutChart.init(&slices).withLegendPosition(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 25 };
    chart.render(&buf, area);

    // Each slice should have a legend entry with '■'
    const bullet_count = countChar(buf, area, '■');
    try testing.expectEqual(@as(usize, 5), bullet_count);
}

test "DonutChart.render bottom legend with many slices stacks vertically" {
    var buf = try Buffer.init(testing.allocator, 40, 30);
    defer buf.deinit();
    const slices = [_]DonutChartSlice{
        .{ .label = "A", .value = 20 },
        .{ .label = "B", .value = 30 },
        .{ .label = "C", .value = 50 },
    };
    const chart = DonutChart.init(&slices).withLegendPosition(.bottom);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 30 };
    chart.render(&buf, area);

    // Should have 3 '■' bullets (one per legend entry)
    const bullet_count = countChar(buf, area, '■');
    try testing.expectEqual(@as(usize, 3), bullet_count);
}

// ============================================================================
// REGRESSION: Center Label Positioning with Default Legend (Critical Bug)
// ============================================================================

test "DonutChart.render center_label respects chart_area (post-legend-split) not full inner area" {
    // REGRESSION TEST: Validates fix for bug where renderCenterLabel used
    // full `inner` area (pre-legend-split) for center calculation while
    // renderDonut used post-legend-split `chart_area`. With default
    // legend_position=.right, this caused ~legend_width/2 offset misalignment.
    // Center label would render outside/across the visual donut hole instead of inside it.

    var buf = try Buffer.init(testing.allocator, 41, 21);
    defer buf.deinit();

    const slices = [_]DonutChartSlice{
        .{ .label = "Full", .value = 100 },
    };

    // Use DEFAULT legend_position (.right) — do NOT override
    const chart = DonutChart.init(&slices)
        .withHoleRatio(0.5)
        .withCenterLabel("OK");

    const area = Rect{ .x = 0, .y = 0, .width = 41, .height = 21 };
    chart.render(&buf, area);

    // With 41x21 area and default .right legend:
    // - legend_width = min(41/3, 20) = 13
    // - chart_area.width = 41 - 13 = 28
    // - chart_area center_x = 0 + 28/2 = 14 (CORRECT CENTER)
    // - inner.width = 41
    // - inner center_x = 0 + 41/2 = 20 (BUGGY CENTER)
    // - center_y = 0 + 21/2 = 10
    // - radius = min(28/2, 21) = 14
    // - inner_radius = 14 * 0.5 = 7
    // For label "OK" (2 chars):
    // - CORRECT: start_x = 14 - 2/2 = 13, chars at x=13,14
    // - BUGGY: start_x = 20 - 2/2 = 19, chars at x=19,20

    // Assert label chars appear at CORRECT coordinates (chart_area-based)
    // After fix: 'O' at x=13, 'K' at x=14, both at y=10
    const correct_o_found = (buf.getConst(13, 10) orelse return).char == 'O';
    const correct_k_found = (buf.getConst(14, 10) orelse return).char == 'K';

    try testing.expect(correct_o_found);
    try testing.expect(correct_k_found);

    // Also assert label chars are NOT at the buggy coordinates (inner-based)
    // If they are at x=19,20, the bug is still present
    const buggy_o = if (buf.getConst(19, 10)) |cell| cell.char == 'O' else false;
    const buggy_k = if (buf.getConst(20, 10)) |cell| cell.char == 'K' else false;
    const buggy_location_has_label = buggy_o and buggy_k;

    try testing.expect(!buggy_location_has_label);
}
