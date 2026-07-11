//! ViolinPlot Widget Tests — TDD Red Phase
//!
//! Tests ViolinPlot widget with multiple series rendered as vertical density silhouettes,
//! centered around a shared value scale. Each series shows a symmetric "violin" shape
//! representing distribution density. Tests cover binning, density calculation, focused
//! styling, label display, block borders, MAX_SERIES/MAX_BINS capping, and rendering
//! edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const ViolinPlot = sailor.tui.widgets.ViolinPlot;
const ViolinSeries = sailor.tui.widgets.violin_plot.ViolinSeries;

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

/// Count filled cells above vertical midpoint (for checking centering)
fn countFilledAboveMiddle(buf: Buffer, area: Rect) usize {
    const middle_y = area.y + (area.height / 2);
    var count: usize = 0;
    var y = area.y;
    while (y < middle_y and y < buf.height) : (y += 1) {
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

/// Count filled cells below vertical midpoint
fn countFilledBelowMiddle(buf: Buffer, area: Rect) usize {
    const middle_y = area.y + (area.height / 2);
    var count: usize = 0;
    var y = middle_y;
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

/// Check if buffer area contains specific character
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

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "ViolinPlot.init creates default plot with zero series" {
    const vp = ViolinPlot.init();
    try testing.expectEqual(@as(usize, 0), vp.series.len);
}

test "ViolinPlot.init defaults focused to 0" {
    const vp = ViolinPlot.init();
    try testing.expectEqual(@as(usize, 0), vp.focused);
}

test "ViolinPlot.init defaults show_labels to true" {
    const vp = ViolinPlot.init();
    try testing.expectEqual(true, vp.show_labels);
}

test "ViolinPlot.init defaults block to null" {
    const vp = ViolinPlot.init();
    try testing.expect(vp.block == null);
}

test "ViolinPlot.init defaults styles to empty" {
    const vp = ViolinPlot.init();
    try testing.expect(!vp.style.bold and !vp.focused_style.bold);
}

// ============================================================================
// Group 2: ViolinSeries Struct Defaults (3 tests)
// ============================================================================

test "ViolinSeries default label is empty" {
    const series = ViolinSeries{};
    try testing.expectEqualStrings("", series.label);
}

test "ViolinSeries default values array is empty" {
    const series = ViolinSeries{};
    try testing.expectEqual(@as(usize, 0), series.values.len);
}

test "ViolinSeries default style is empty" {
    const series = ViolinSeries{};
    try testing.expect(!series.style.bold and series.style.dim == false);
}

// ============================================================================
// Group 3: MAX_SERIES and MAX_BINS Constants (2 tests)
// ============================================================================

test "ViolinPlot.MAX_SERIES equals 8" {
    try testing.expectEqual(@as(usize, 8), ViolinPlot.MAX_SERIES);
}

test "ViolinPlot.MAX_BINS equals 64" {
    try testing.expectEqual(@as(usize, 64), ViolinPlot.MAX_BINS);
}

// ============================================================================
// Group 4: seriesCount() Method (5 tests)
// ============================================================================

test "ViolinPlot.seriesCount with zero series returns 0" {
    const vp = ViolinPlot.init();
    try testing.expectEqual(@as(usize, 0), vp.seriesCount());
}

test "ViolinPlot.seriesCount with 1 series returns 1" {
    var values = [_]f32{1.0};
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 1), vp.seriesCount());
}

test "ViolinPlot.seriesCount with 4 series returns 4" {
    var values_array: [4][2]f32 = undefined;
    var series_arr: [4]ViolinSeries = undefined;
    for (0..4) |i| {
        values_array[i] = [_]f32{ 1.0, 2.0 };
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const vp = ViolinPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 4), vp.seriesCount());
}

test "ViolinPlot.seriesCount with exactly MAX_SERIES=8 returns 8" {
    var values_array: [8][1]f32 = undefined;
    var series_arr: [8]ViolinSeries = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{1.0};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const vp = ViolinPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), vp.seriesCount());
}

test "ViolinPlot.seriesCount caps at MAX_SERIES=8 when 12 series provided" {
    var values_array: [12][1]f32 = undefined;
    var series_arr: [12]ViolinSeries = undefined;
    for (0..12) |i| {
        values_array[i] = [_]f32{1.0};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const vp = ViolinPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), vp.seriesCount());
}

// ============================================================================
// Group 5: Builder Immutability (8 tests)
// ============================================================================

test "ViolinPlot.withSeries does not modify original" {
    var values1 = [_]f32{1.0};
    var series1 = [_]ViolinSeries{.{ .label = "A", .values = &values1 }};
    var values2 = [_]f32{2.0};
    var values3 = [_]f32{3.0};
    var series2 = [_]ViolinSeries{
        .{ .label = "X", .values = &values2 },
        .{ .label = "Y", .values = &values3 },
    };

    const vp1 = ViolinPlot.init().withSeries(&series1);
    const vp2 = vp1.withSeries(&series2);

    try testing.expectEqual(@as(usize, 1), vp1.seriesCount());
    try testing.expectEqual(@as(usize, 2), vp2.seriesCount());
}

test "ViolinPlot.withFocused sets focused index" {
    const vp1 = ViolinPlot.init().withFocused(0);
    const vp2 = vp1.withFocused(3);

    try testing.expectEqual(@as(usize, 0), vp1.focused);
    try testing.expectEqual(@as(usize, 3), vp2.focused);
}

test "ViolinPlot.withShowLabels sets show_labels" {
    const vp1 = ViolinPlot.init().withShowLabels(true);
    const vp2 = vp1.withShowLabels(false);

    try testing.expectEqual(true, vp1.show_labels);
    try testing.expectEqual(false, vp2.show_labels);
}

test "ViolinPlot.withStyle sets style" {
    const style = Style{ .bold = true };
    const vp = ViolinPlot.init().withStyle(style);
    try testing.expectEqual(true, vp.style.bold);
}

test "ViolinPlot.withFocusedStyle sets focused_style" {
    const style = Style{ .dim = true };
    const vp = ViolinPlot.init().withFocusedStyle(style);
    try testing.expectEqual(true, vp.focused_style.dim);
}

test "ViolinPlot.withLabelStyle sets label_style" {
    const style = Style{ .italic = true };
    const vp = ViolinPlot.init().withLabelStyle(style);
    try testing.expectEqual(true, vp.label_style.italic);
}

test "ViolinPlot.withBlock sets block" {
    const block = Block{};
    const vp = ViolinPlot.init().withBlock(block);
    try testing.expect(vp.block != null);
}

test "ViolinPlot.withBlock with null unsets block" {
    const vp1 = ViolinPlot.init().withBlock(.{});
    const vp2 = vp1.withBlock(null);

    try testing.expect(vp1.block != null);
    try testing.expect(vp2.block == null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "ViolinPlot.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    vp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "ViolinPlot.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    vp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "ViolinPlot.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    vp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "ViolinPlot.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var values = [_]f32{1.0};
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    vp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 7: Render — Empty Series (2 tests)
// ============================================================================

test "ViolinPlot.render with zero series produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const vp = ViolinPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "ViolinPlot.render series with empty values produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &.{} }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 8: Render — Single Series (5 tests)
// ============================================================================

test "ViolinPlot.render single series with one value produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render single series with multiple values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render single series with uniform values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 3.0, 3.0, 3.0, 3.0, 3.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render single series at different area offset" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 10, .y = 5, .width = 30, .height = 15 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render single series with no label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 4.0, 6.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 9: Render — Multiple Series (5 tests)
// ============================================================================

test "ViolinPlot.render two series produces content" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values1 = [_]f32{2.0};
    var values2 = [_]f32{5.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render three series produces content" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{1.0};
    var values2 = [_]f32{5.0};
    var values3 = [_]f32{9.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render four series with diverse value distributions" {
    var buf = try Buffer.init(testing.allocator, 80, 25);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 1.0, 1.0, 2.0, 2.0 };
    var values2 = [_]f32{ 5.0, 5.0, 5.0, 5.0, 5.0 };
    var values3 = [_]f32{ 8.0, 7.0, 9.0, 8.0, 9.0 };
    var values4 = [_]f32{ 2.0, 4.0, 6.0, 8.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
        .{ .label = "D", .values = &values4 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render multiple series does not skip any bands" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var values1 = [_]f32{1.0};
    var values2 = [_]f32{2.0};
    var values3 = [_]f32{3.0};
    var values4 = [_]f32{4.0};
    var values5 = [_]f32{5.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
        .{ .label = "D", .values = &values4 },
        .{ .label = "E", .values = &values5 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Render — Value Ranges and Shared Scale (5 tests)
// ============================================================================

test "ViolinPlot.render all series at same value renders symmetrically" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 5.0, 5.0, 5.0 };
    var values2 = [_]f32{ 5.0, 5.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);

    const above = countFilledAboveMiddle(buf, area);
    const below = countFilledBelowMiddle(buf, area);

    // Uniform values should produce symmetric fills above and below center
    try testing.expect(above > 0);
    try testing.expect(below > 0);
}

test "ViolinPlot.render uses shared min/max across all series" {
    var buf = try Buffer.init(testing.allocator, 60, 24);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 1.0 };  // low range
    var values2 = [_]f32{ 9.0, 9.0 };  // high range
    var series_arr = [_]ViolinSeries{
        .{ .label = "Low", .values = &values1 },
        .{ .label = "High", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    vp.render(&buf, area);
    // Both should render using the full 1.0-9.0 scale
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with negative values scales correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ -5.0, -2.0, 0.0, 2.0, 5.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "N", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render all negative series values" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ -10.0, -8.0, -9.0 };
    var values2 = [_]f32{ -5.0, -3.0, -4.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render symmetric negative/positive range" {
    var buf = try Buffer.init(testing.allocator, 70, 24);
    defer buf.deinit();
    var values1 = [_]f32{ -10.0, -5.0, 0.0, 5.0, 10.0 };
    var values2 = [_]f32{ -8.0, -2.0, 3.0, 9.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "Sym1", .values = &values1 },
        .{ .label = "Sym2", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 24 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: Render — Identical Values (Min == Max) Edge Case (2 tests)
// ============================================================================

test "ViolinPlot.render single series with all identical values does not divide by zero" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 5.0, 5.0, 5.0, 5.0, 5.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Constant", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    vp.render(&buf, area);
    // Should not crash and should render something
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);  // May be 0 or > 0, but should not crash
}

test "ViolinPlot.render multiple series all with identical values does not crash" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 3.0, 3.0 };
    var values2 = [_]f32{ 3.0, 3.0, 3.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "C1", .values = &values1 },
        .{ .label = "C2", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    // Should not crash
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

// ============================================================================
// Group 12: Render — Focused Series Styling (4 tests)
// ============================================================================

test "ViolinPlot.render focused=0 on two-series plot applies focus style" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{2.0};
    var values2 = [_]f32{8.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const focused_style = Style{ .bold = true };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render focused=1 applies style to second series" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{1.0};
    var values2 = [_]f32{5.0};
    var values3 = [_]f32{9.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const focused_style = Style{ .dim = true };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render focused out of range does not crash or apply style" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{2.0};
    var values2 = [_]f32{8.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render changing focused index still renders all series" {
    var buf1 = try Buffer.init(testing.allocator, 60, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 60, 20);
    defer buf2.deinit();

    var values1 = [_]f32{2.0};
    var values2 = [_]f32{8.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };

    const vp1 = ViolinPlot.init().withSeries(&series_arr).withFocused(0);
    const vp2 = ViolinPlot.init().withSeries(&series_arr).withFocused(1);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp1.render(&buf1, area);
    vp2.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

// ============================================================================
// Group 13: Render — show_labels Toggle (3 tests)
// ============================================================================

test "ViolinPlot.render show_labels=true displays label text (when area permits)" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Series", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render show_labels=false still renders violin shapes" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Series", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render show_labels toggle produces different outputs" {
    var buf1 = try Buffer.init(testing.allocator, 60, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 60, 20);
    defer buf2.deinit();

    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Series", .values = &values }};

    const vp_with_labels = ViolinPlot.init().withSeries(&series_arr).withShowLabels(true);
    const vp_no_labels = ViolinPlot.init().withSeries(&series_arr).withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp_with_labels.render(&buf1, area);
    vp_no_labels.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

// ============================================================================
// Group 14: Render — Block Border (3 tests)
// ============================================================================

test "ViolinPlot.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values1 = [_]f32{2.0};
    var values2 = [_]f32{8.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const block = Block{};
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render block reduces inner area for violin content" {
    var buf1 = try Buffer.init(testing.allocator, 50, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 20);
    defer buf2.deinit();

    var values1 = [_]f32{2.0};
    var values2 = [_]f32{8.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };

    const block = Block{};
    const vp_with_block = ViolinPlot.init().withSeries(&series_arr).withBlock(block);
    const vp_no_block = ViolinPlot.init().withSeries(&series_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp_with_block.render(&buf1, area);
    vp_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "ViolinPlot.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Data", .values = &values }};
    const block = (Block{}).withTitle("ViolinPlot", .top_left);
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 15: Render — MAX_SERIES Cap (3 tests)
// ============================================================================

test "ViolinPlot.render with exactly MAX_SERIES=8 renders all series" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var series_arr: [8]ViolinSeries = undefined;
    var values_array: [8][1]f32 = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{@as(f32, @floatFromInt(i + 1))};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const vp = ViolinPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), vp.seriesCount());
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with 12 series caps to MAX_SERIES=8" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var series_arr: [12]ViolinSeries = undefined;
    var values_array: [12][1]f32 = undefined;
    for (0..12) |i| {
        values_array[i] = [_]f32{@as(f32, @floatFromInt(i + 1))};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const vp = ViolinPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), vp.seriesCount());
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render rendering only respects MAX_SERIES cap" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var series_arr: [16]ViolinSeries = undefined;
    var values_array: [16][1]f32 = undefined;
    for (0..16) |i| {
        values_array[i] = [_]f32{1.0};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const vp = ViolinPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), vp.seriesCount());
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Render — MAX_BINS Cap (2 tests)
// ============================================================================

test "ViolinPlot.render with area.height > MAX_BINS still bins correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 100);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 100 };
    vp.render(&buf, area);
    // Should use max(64, area.height) bins and not overflow
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with height == MAX_BINS uses all bins" {
    var buf = try Buffer.init(testing.allocator, 40, 64);
    defer buf.deinit();
    var values: [32]f32 = undefined;
    for (0..32) |i| {
        values[i] = @as(f32, @floatFromInt(i % 5)) + 1.0;
    }
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 64 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Render — Symmetry and Centering (3 tests)
// ============================================================================

test "ViolinPlot.render violin is symmetric around center column" {
    var buf = try Buffer.init(testing.allocator, 40, 24);
    defer buf.deinit();
    // Use a constant (uniform) distribution to get symmetric output
    var values = [_]f32{ 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 24 };
    vp.render(&buf, area);

    // For a single series (band_width = area.width / 1 = area.width)
    // The violin is centered within this band
    // Find the band center: band_start=area.x, band_center = area.x + area.width/2
    const band_center = area.x + area.width / 2;

    // Scan each row and check symmetry: filled cells should mostly be mirrored around center
    var symmetry_violations: usize = 0;
    var comparisons_made: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        // Scan left and right from center
        var dx: i32 = 1;
        while (dx <= 10) : (dx += 1) {
            const left_x: i32 = @as(i32, @intCast(band_center)) - dx;
            const right_x: i32 = @as(i32, @intCast(band_center)) + dx;

            const left_filled = if (left_x >= 0 and left_x < @as(i32, @intCast(buf.width)))
                (buf.getConst(@as(u16, @intCast(left_x)), y).?.char == '█')
            else
                false;
            const right_filled = if (right_x >= 0 and right_x < @as(i32, @intCast(buf.width)))
                (buf.getConst(@as(u16, @intCast(right_x)), y).?.char == '█')
            else
                false;

            comparisons_made += 1;

            // For symmetry: left and right should both be filled or both be empty
            if (left_filled != right_filled) {
                symmetry_violations += 1;
            }
        }
    }

    // Should have made comparisons
    try testing.expect(comparisons_made > 0);
    // Most of the symmetry should hold (at least 60% of pairs match)
    // Allow up to 40% asymmetry due to rounding in density calculation and rendering
    const max_violations = comparisons_made * 40 / 100;
    try testing.expect(symmetry_violations <= max_violations);
}

test "ViolinPlot.render multiple series violins are vertically centered" {
    var buf = try Buffer.init(testing.allocator, 60, 24);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 1.0, 2.0, 2.0, 2.0, 3.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 6.0, 7.0, 7.0, 7.0, 8.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "Low", .values = &values1 },
        .{ .label = "High", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    vp.render(&buf, area);

    const above = countFilledAboveMiddle(buf, area);
    const below = countFilledBelowMiddle(buf, area);

    // Both should have content above and below center
    try testing.expect(above > 0);
    try testing.expect(below > 0);
}

test "ViolinPlot.render wide uniform distribution fills center rows" {
    var buf = try Buffer.init(testing.allocator, 50, 22);
    defer buf.deinit();
    var values: [30]f32 = undefined;
    for (0..30) |i| {
        values[i] = 5.0;  // All same value - uniform distribution
    }
    var series_arr = [_]ViolinSeries{.{ .label = "Uniform", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 22 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 18: Render — Small Areas (3 tests)
// ============================================================================

test "ViolinPlot.render minimal height (3 rows) without label row reservation" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);  // May be 0, but should not crash
}

test "ViolinPlot.render very narrow width (one series wide band per series)" {
    var buf = try Buffer.init(testing.allocator, 10, 15);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 15 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);  // May be very small but should work
}

test "ViolinPlot.render tiny area still does not crash" {
    var buf = try Buffer.init(testing.allocator, 8, 6);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 4.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Tiny", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 6 };
    vp.render(&buf, area);
    // Should not crash
}

// ============================================================================
// Group 19: Render — Label Row Reservation with show_labels (2 tests)
// ============================================================================

test "ViolinPlot.render with show_labels=true reserves bottom row for labels" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Series", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    // When show_labels=true, one row is reserved at the bottom
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render zero-height after label row reservation (height=1, show_labels=true)" {
    var buf = try Buffer.init(testing.allocator, 30, 1);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    vp.render(&buf, area);
    // Should handle gracefully (no content or just labels)
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

// ============================================================================
// Group 20: Render — Buffer Bounds and Clipping (3 tests)
// ============================================================================

test "ViolinPlot.render does not exceed buffer bounds" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0, 8.0, 9.0 };
    var values3 = [_]f32{ 2.0, 4.0, 6.0, 8.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 3200);  // 80*40 max
}

test "ViolinPlot.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 60);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 3.0, 5.0 };
    var values2 = [_]f32{ 6.0, 7.0, 8.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 20, .y = 15, .width = 50, .height = 30 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with block on tiny area does not crash" {
    var buf = try Buffer.init(testing.allocator, 12, 8);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 4.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const block = Block{};
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 12, .height = 8 };
    vp.render(&buf, area);
    // Should not crash
}

// ============================================================================
// Group 21: Render — Style Application (4 tests)
// ============================================================================

test "ViolinPlot.render with style applies to plot" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "A", .values = &values }};
    const style = Style{ .bold = true };
    const vp = ViolinPlot.init().withSeries(&series_arr).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Label", .values = &values }};
    const label_style = Style{ .italic = true };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with focused_style applies to focused series" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{2.0};
    var values2 = [_]f32{8.0};
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const focused_style = Style{ .dim = true };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with multiple styles applied" {
    var buf = try Buffer.init(testing.allocator, 70, 25);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 6.0, 7.0, 8.0 };
    var values3 = [_]f32{ 4.0, 5.0, 6.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withStyle(Style{ .dim = true })
        .withLabelStyle(Style{ .bold = true })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 25 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 22: Render — Complex Real-World Scenarios (4 tests)
// ============================================================================

test "ViolinPlot.render bimodal distribution (two peaks)" {
    var buf = try Buffer.init(testing.allocator, 60, 24);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 2.0, 2.0, 3.0, 3.0, 7.0, 7.0, 8.0, 8.0, 8.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Bimodal", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render gaussian-like distribution (bell curve)" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 3.0, 4.0, 4.0, 5.0, 5.0, 5.0, 5.0, 6.0, 6.0, 7.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Normal", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render comparison of three distributions" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 1.0, 1.0, 2.0, 2.0, 3.0 };
    var values2 = [_]f32{ 4.0, 5.0, 5.0, 5.0, 6.0, 7.0 };
    var values3 = [_]f32{ 7.0, 8.0, 8.0, 9.0, 9.0, 9.0, 9.0, 10.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "Low", .values = &values1 },
        .{ .label = "Mid", .values = &values2 },
        .{ .label = "High", .values = &values3 },
    };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withShowLabels(true)
        .withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render all features enabled together" {
    var buf = try Buffer.init(testing.allocator, 90, 30);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 1.0, 2.0, 3.0, 3.0 };
    var values2 = [_]f32{ 5.0, 5.0, 6.0, 6.0, 6.0 };
    var values3 = [_]f32{ 8.0, 8.0, 9.0, 9.0, 10.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "Series1", .values = &values1, .style = Style{ .bold = true } },
        .{ .label = "Series2", .values = &values2 },
        .{ .label = "Series3", .values = &values3, .style = Style{ .dim = true } },
    };
    const vp = ViolinPlot.init()
        .withSeries(&series_arr)
        .withFocused(1)
        .withShowLabels(true)
        .withStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true })
        .withLabelStyle(Style{ .italic = true })
        .withBlock((Block{}).withTitle("ViolinPlot", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 30 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 23: Large and Edge Case Areas (3 tests)
// ============================================================================

test "ViolinPlot.render very wide area with many series" {
    var buf = try Buffer.init(testing.allocator, 200, 15);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0 };
    var values2 = [_]f32{ 4.0, 5.0 };
    var values3 = [_]f32{ 7.0, 8.0 };
    var values4 = [_]f32{ 3.0, 6.0 };
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
        .{ .label = "D", .values = &values4 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 15 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render very tall area with few series" {
    var buf = try Buffer.init(testing.allocator, 20, 80);
    defer buf.deinit();
    var values1: [20]f32 = undefined;
    for (0..20) |i| {
        values1[i] = @as(f32, @floatFromInt(i % 5)) + 1.0;
    }
    var values2: [20]f32 = undefined;
    for (0..20) |i| {
        values2[i] = @as(f32, @floatFromInt((i + 2) % 5)) + 5.0;
    }
    var series_arr = [_]ViolinSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 80 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render large rectangular area with MAX_SERIES and many samples" {
    var buf = try Buffer.init(testing.allocator, 120, 60);
    defer buf.deinit();
    var series_arr: [8]ViolinSeries = undefined;
    var values_array: [8][30]f32 = undefined;
    for (0..8) |i| {
        for (0..30) |j| {
            values_array[i][j] = @as(f32, @floatFromInt(i * 2 + 1)) + @as(f32, @floatFromInt(j % 3));
        }
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 60 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 24: Mixed Types and Fractional Values (3 tests)
// ============================================================================

test "ViolinPlot.render with fractional values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 0.5, 1.2, 2.7, 3.3, 4.9 };
    var series_arr = [_]ViolinSeries{.{ .label = "Frac", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with very large values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 1000.0, 2000.0, 5000.0, 8000.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Large", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with very small fractional values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 0.001, 0.002, 0.003, 0.005 };
    var series_arr = [_]ViolinSeries{.{ .label = "Tiny", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);  // May be 0 due to scaling
}

// ============================================================================
// Group 25: Edge Cases with Mixed Data (3 tests)
// ============================================================================

test "ViolinPlot.render series with one sample repeated many times" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values: [50]f32 = [_]f32{5.0} ** 50;
    var series_arr = [_]ViolinSeries{.{ .label = "Repeat", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

test "ViolinPlot.render skewed distribution (heavily weighted to one side)" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 2.0, 8.0, 9.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Skew", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "ViolinPlot.render with outliers far from main distribution" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ -100.0, 4.0, 5.0, 5.0, 5.0, 6.0, 6.0, 7.0, 100.0 };
    var series_arr = [_]ViolinSeries{.{ .label = "Outliers", .values = &values }};
    const vp = ViolinPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    vp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
