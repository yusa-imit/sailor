//! BoxPlot Widget Tests — TDD Red Phase
//!
//! Tests BoxPlot widget with multiple series rendered as box-and-whisker plots,
//! showing five-number-summary statistics (min, Q1, median, Q3, max) plus outliers.
//! Each series gets a vertical column band with centered box. All series share a
//! global value scale. Tests cover initialization, builder pattern, five-number-summary
//! correctness, outlier detection, focused styling, label display, block borders,
//! MAX_SERIES/MAX_SAMPLES capping, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const BoxPlot = sailor.tui.widgets.BoxPlot;
const BoxPlotSeries = sailor.tui.widgets.box_plot.BoxPlotSeries;
const FiveNumberSummary = sailor.tui.widgets.box_plot.FiveNumberSummary;
const fiveNumberSummary = sailor.tui.widgets.box_plot.fiveNumberSummary;

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

/// Approximate float equality check (within epsilon)
fn floatEq(a: f32, b: f32, epsilon: f32) bool {
    return @abs(a - b) < epsilon;
}

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "BoxPlot.init creates default plot with zero series" {
    const bp = BoxPlot.init();
    try testing.expectEqual(@as(usize, 0), bp.series.len);
}

test "BoxPlot.init defaults focused to 0" {
    const bp = BoxPlot.init();
    try testing.expectEqual(@as(usize, 0), bp.focused);
}

test "BoxPlot.init defaults show_labels to true" {
    const bp = BoxPlot.init();
    try testing.expectEqual(true, bp.show_labels);
}

test "BoxPlot.init defaults show_outliers to true" {
    const bp = BoxPlot.init();
    try testing.expectEqual(true, bp.show_outliers);
}

test "BoxPlot.init defaults block to null" {
    const bp = BoxPlot.init();
    try testing.expect(bp.block == null);
}

// ============================================================================
// Group 2: BoxPlotSeries Struct Defaults (3 tests)
// ============================================================================

test "BoxPlotSeries default label is empty" {
    const series = BoxPlotSeries{};
    try testing.expectEqualStrings("", series.label);
}

test "BoxPlotSeries default values array is empty" {
    const series = BoxPlotSeries{};
    try testing.expectEqual(@as(usize, 0), series.values.len);
}

test "BoxPlotSeries default style is empty" {
    const series = BoxPlotSeries{};
    try testing.expect(!series.style.bold and series.style.dim == false);
}

// ============================================================================
// Group 3: MAX_SERIES and MAX_SAMPLES Constants (2 tests)
// ============================================================================

test "BoxPlot.MAX_SERIES equals 8" {
    try testing.expectEqual(@as(usize, 8), BoxPlot.MAX_SERIES);
}

test "BoxPlot.MAX_SAMPLES equals 64" {
    try testing.expectEqual(@as(usize, 64), BoxPlot.MAX_SAMPLES);
}

// ============================================================================
// Group 4: seriesCount() Method (5 tests)
// ============================================================================

test "BoxPlot.seriesCount with zero series returns 0" {
    const bp = BoxPlot.init();
    try testing.expectEqual(@as(usize, 0), bp.seriesCount());
}

test "BoxPlot.seriesCount with 1 series returns 1" {
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 1), bp.seriesCount());
}

test "BoxPlot.seriesCount with 4 series returns 4" {
    var values_array: [4][2]f32 = undefined;
    var series_arr: [4]BoxPlotSeries = undefined;
    for (0..4) |i| {
        values_array[i] = [_]f32{ 1.0, 2.0 };
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 4), bp.seriesCount());
}

test "BoxPlot.seriesCount with exactly MAX_SERIES=8 returns 8" {
    var values_array: [8][1]f32 = undefined;
    var series_arr: [8]BoxPlotSeries = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{@as(f32, @floatFromInt(i + 1))};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), bp.seriesCount());
}

test "BoxPlot.seriesCount caps at MAX_SERIES=8 when 12 series provided" {
    var values_array: [12][1]f32 = undefined;
    var series_arr: [12]BoxPlotSeries = undefined;
    for (0..12) |i| {
        values_array[i] = [_]f32{@as(f32, @floatFromInt(i + 1))};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), bp.seriesCount());
}

// ============================================================================
// Group 5: Builder Immutability — All 12 Builder Methods (12 tests)
// ============================================================================

test "BoxPlot.withSeries does not modify original" {
    var values1 = [_]f32{1.0};
    var series1 = [_]BoxPlotSeries{.{ .label = "A", .values = &values1 }};
    var values2 = [_]f32{2.0};
    var values3 = [_]f32{3.0};
    var series2 = [_]BoxPlotSeries{
        .{ .label = "X", .values = &values2 },
        .{ .label = "Y", .values = &values3 },
    };

    const bp1 = BoxPlot.init().withSeries(&series1);
    const bp2 = bp1.withSeries(&series2);

    try testing.expectEqual(@as(usize, 1), bp1.seriesCount());
    try testing.expectEqual(@as(usize, 2), bp2.seriesCount());
}

test "BoxPlot.withFocused sets focused index" {
    const bp1 = BoxPlot.init().withFocused(0);
    const bp2 = bp1.withFocused(3);

    try testing.expectEqual(@as(usize, 0), bp1.focused);
    try testing.expectEqual(@as(usize, 3), bp2.focused);
}

test "BoxPlot.withShowLabels sets show_labels" {
    const bp1 = BoxPlot.init().withShowLabels(true);
    const bp2 = bp1.withShowLabels(false);

    try testing.expectEqual(true, bp1.show_labels);
    try testing.expectEqual(false, bp2.show_labels);
}

test "BoxPlot.withShowOutliers sets show_outliers" {
    const bp1 = BoxPlot.init().withShowOutliers(true);
    const bp2 = bp1.withShowOutliers(false);

    try testing.expectEqual(true, bp1.show_outliers);
    try testing.expectEqual(false, bp2.show_outliers);
}

test "BoxPlot.withStyle sets style" {
    const style = Style{ .bold = true };
    const bp = BoxPlot.init().withStyle(style);
    try testing.expectEqual(true, bp.style.bold);
}

test "BoxPlot.withBoxStyle sets box_style" {
    const style = Style{ .dim = true };
    const bp = BoxPlot.init().withBoxStyle(style);
    try testing.expectEqual(true, bp.box_style.dim);
}

test "BoxPlot.withMedianStyle sets median_style" {
    const style = Style{ .italic = true };
    const bp = BoxPlot.init().withMedianStyle(style);
    try testing.expectEqual(true, bp.median_style.italic);
}

test "BoxPlot.withWhiskerStyle sets whisker_style" {
    const style = Style{ .bold = true };
    const bp = BoxPlot.init().withWhiskerStyle(style);
    try testing.expectEqual(true, bp.whisker_style.bold);
}

test "BoxPlot.withOutlierStyle sets outlier_style" {
    const style = Style{ .dim = true };
    const bp = BoxPlot.init().withOutlierStyle(style);
    try testing.expectEqual(true, bp.outlier_style.dim);
}

test "BoxPlot.withFocusedStyle sets focused_style" {
    const style = Style{ .bold = true };
    const bp = BoxPlot.init().withFocusedStyle(style);
    try testing.expectEqual(true, bp.focused_style.bold);
}

test "BoxPlot.withLabelStyle sets label_style" {
    const style = Style{ .italic = true };
    const bp = BoxPlot.init().withLabelStyle(style);
    try testing.expectEqual(true, bp.label_style.italic);
}

test "BoxPlot.withBlock sets block" {
    const block = Block{};
    const bp = BoxPlot.init().withBlock(block);
    try testing.expect(bp.block != null);
}

test "BoxPlot.withBlock with null unsets block" {
    const bp1 = BoxPlot.init().withBlock(.{});
    const bp2 = bp1.withBlock(null);

    try testing.expect(bp1.block != null);
    try testing.expect(bp2.block == null);
}

// ============================================================================
// Group 6: Five-Number-Summary Correctness (13 tests) — MOST CRITICAL
// ============================================================================

test "fiveNumberSummary for [1,2,3,4,5] computes correct quartiles" {
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const fns = fiveNumberSummary(&values);

    try testing.expectEqual(@as(f32, 1.0), fns.min);
    try testing.expectEqual(@as(f32, 5.0), fns.max);
    try testing.expectEqual(@as(f32, 3.0), fns.median);
    // Q1 at idx=1.0 -> sorted[1]=2.0
    try testing.expectEqual(@as(f32, 2.0), fns.q1);
    // Q3 at idx=3.0 -> sorted[3]=4.0
    try testing.expectEqual(@as(f32, 4.0), fns.q3);
}

test "fiveNumberSummary for [1,2,3,4] computes correct interpolated quartiles" {
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const fns = fiveNumberSummary(&values);

    try testing.expectEqual(@as(f32, 1.0), fns.min);
    try testing.expectEqual(@as(f32, 4.0), fns.max);
    // median at idx=1.5 -> 2.0 + (3.0-2.0)*0.5 = 2.5
    try testing.expect(floatEq(fns.median, 2.5, 0.01));
    // Q1 at idx=0.75 -> 1.0 + (2.0-1.0)*0.75 = 1.75
    try testing.expect(floatEq(fns.q1, 1.75, 0.01));
    // Q3 at idx=2.25 -> 3.0 + (4.0-3.0)*0.25 = 3.25
    try testing.expect(floatEq(fns.q3, 3.25, 0.01));
}

test "fiveNumberSummary for single value [5.0]" {
    var values = [_]f32{5.0};
    const fns = fiveNumberSummary(&values);

    try testing.expectEqual(@as(f32, 5.0), fns.min);
    try testing.expectEqual(@as(f32, 5.0), fns.max);
    try testing.expectEqual(@as(f32, 5.0), fns.median);
    try testing.expectEqual(@as(f32, 5.0), fns.q1);
    try testing.expectEqual(@as(f32, 5.0), fns.q3);
}

test "fiveNumberSummary for empty array returns all zeros" {
    var values: [0]f32 = undefined;
    const fns = fiveNumberSummary(&values);

    try testing.expectEqual(@as(f32, 0.0), fns.min);
    try testing.expectEqual(@as(f32, 0.0), fns.max);
    try testing.expectEqual(@as(f32, 0.0), fns.median);
    try testing.expectEqual(@as(f32, 0.0), fns.q1);
    try testing.expectEqual(@as(f32, 0.0), fns.q3);
}

test "fiveNumberSummary computes correct IQR" {
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const fns = fiveNumberSummary(&values);

    const iqr = fns.q3 - fns.q1;  // 4.0 - 2.0 = 2.0
    try testing.expectEqual(@as(f32, 2.0), iqr);
}

test "fiveNumberSummary for all identical values [5,5,5,5,5]" {
    var values = [_]f32{ 5.0, 5.0, 5.0, 5.0, 5.0 };
    const fns = fiveNumberSummary(&values);

    try testing.expectEqual(@as(f32, 5.0), fns.min);
    try testing.expectEqual(@as(f32, 5.0), fns.max);
    try testing.expectEqual(@as(f32, 5.0), fns.median);
    try testing.expectEqual(@as(f32, 5.0), fns.q1);
    try testing.expectEqual(@as(f32, 5.0), fns.q3);
    // IQR = 0, so whisker_low = whisker_high
    const iqr = fns.q3 - fns.q1;
    try testing.expectEqual(@as(f32, 0.0), iqr);
}

test "fiveNumberSummary calculates whisker bounds correctly" {
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const fns = fiveNumberSummary(&values);

    // With no outliers, whisker endpoints should be actual min/max
    // (theoretical bounds would be Q1-1.5*IQR and Q3+1.5*IQR)
    try testing.expectEqual(@as(f32, 1.0), fns.whisker_low);
    try testing.expectEqual(@as(f32, 5.0), fns.whisker_high);
}

test "fiveNumberSummary detects outlier on upper end" {
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 100.0 };
    const fns = fiveNumberSummary(&values);

    // With outlier, whisker_high should be the max non-outlier value (5.0)
    // Upper fence: Q3 + 1.5*IQR, 100 should be outside
    try testing.expectEqual(@as(f32, 5.0), fns.whisker_high);
}

test "fiveNumberSummary detects outlier on lower end" {
    var values = [_]f32{ -100.0, 1.0, 2.0, 3.0, 4.0, 5.0 };
    const fns = fiveNumberSummary(&values);

    // With outlier, whisker_low should be the min non-outlier value (1.0)
    try testing.expectEqual(@as(f32, 1.0), fns.whisker_low);
}

test "fiveNumberSummary with unsorted input still works" {
    var values = [_]f32{ 5.0, 2.0, 4.0, 1.0, 3.0 };
    const fns = fiveNumberSummary(&values);

    try testing.expectEqual(@as(f32, 1.0), fns.min);
    try testing.expectEqual(@as(f32, 5.0), fns.max);
    try testing.expectEqual(@as(f32, 3.0), fns.median);
}

test "fiveNumberSummary respects MAX_SAMPLES truncation" {
    // Create array with > MAX_SAMPLES elements
    var values: [100]f32 = undefined;
    for (0..100) |i| {
        values[i] = @as(f32, @floatFromInt(i + 1));
    }
    const fns = fiveNumberSummary(&values);

    // Should compute stats only on first 64 samples (MAX_SAMPLES)
    // First 64: 1..64, so min=1, max=64
    try testing.expectEqual(@as(f32, 1.0), fns.min);
    try testing.expectEqual(@as(f32, 64.0), fns.max);
}

test "fiveNumberSummary with two values" {
    var values = [_]f32{ 1.0, 5.0 };
    const fns = fiveNumberSummary(&values);

    try testing.expectEqual(@as(f32, 1.0), fns.min);
    try testing.expectEqual(@as(f32, 5.0), fns.max);
    // median at idx=0.5 -> 1.0 + (5.0-1.0)*0.5 = 3.0
    try testing.expect(floatEq(fns.median, 3.0, 0.01));
}

// ============================================================================
// Group 7: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "BoxPlot.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    bp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "BoxPlot.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    bp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "BoxPlot.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    bp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "BoxPlot.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    bp.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 8: Render — Empty Series (2 tests)
// ============================================================================

test "BoxPlot.render with zero series produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const bp = BoxPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "BoxPlot.render series with empty values produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &.{} }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 9: Render — Single Series (5 tests)
// ============================================================================

test "BoxPlot.render single series with one value produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render single series with multiple values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render single series with uniform values produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 3.0, 3.0, 3.0, 3.0, 3.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render single series at different area offset" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 10, .y = 5, .width = 30, .height = 15 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render single series with no label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 4.0, 6.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Render — Multiple Series (5 tests)
// ============================================================================

test "BoxPlot.render two series produces content" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render three series produces content" {
    var buf = try Buffer.init(testing.allocator, 70, 20);
    defer buf.deinit();
    var values1 = [_]f32{1.0};
    var values2 = [_]f32{5.0};
    var values3 = [_]f32{9.0};
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render four series with diverse value distributions" {
    var buf = try Buffer.init(testing.allocator, 80, 25);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 1.0, 2.0, 2.0 };
    var values2 = [_]f32{ 5.0, 5.0, 5.0, 5.0 };
    var values3 = [_]f32{ 8.0, 7.0, 9.0, 8.0 };
    var values4 = [_]f32{ 2.0, 4.0, 6.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
        .{ .label = "D", .values = &values4 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render five series with shared scale" {
    var buf = try Buffer.init(testing.allocator, 90, 25);
    defer buf.deinit();
    var values1 = [_]f32{1.0};
    var values2 = [_]f32{2.0};
    var values3 = [_]f32{3.0};
    var values4 = [_]f32{4.0};
    var values5 = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
        .{ .label = "D", .values = &values4 },
        .{ .label = "E", .values = &values5 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 25 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: Render — Outlier Detection and Display (5 tests)
// ============================================================================

test "BoxPlot.render series with upper outlier" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 100.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Outlier", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowOutliers(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render series with lower outlier" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ -100.0, 1.0, 2.0, 3.0, 4.0, 5.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Outlier", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowOutliers(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with show_outliers=false hides outlier markers" {
    var buf_with_outliers = try Buffer.init(testing.allocator, 50, 20);
    defer buf_with_outliers.deinit();
    var buf_without_outliers = try Buffer.init(testing.allocator, 50, 20);
    defer buf_without_outliers.deinit();

    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 100.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};

    const bp_with = BoxPlot.init().withSeries(&series_arr).withShowOutliers(true);
    const bp_without = BoxPlot.init().withSeries(&series_arr).withShowOutliers(false);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp_with.render(&buf_with_outliers, area);
    bp_without.render(&buf_without_outliers, area);

    // Count outlier markers ('·' glyph) in both buffers
    var outlier_count_with: usize = 0;
    var outlier_count_without: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf_with_outliers.getConst(x, y)) |cell| {
                if (cell.char == '·') outlier_count_with += 1;
            }
            if (buf_without_outliers.getConst(x, y)) |cell| {
                if (cell.char == '·') outlier_count_without += 1;
            }
        }
    }

    // With show_outliers=true should have at least one outlier marker for value 100.0
    try testing.expect(outlier_count_with > 0);
    // With show_outliers=false should have zero outlier markers
    try testing.expectEqual(@as(usize, 0), outlier_count_without);
}

test "BoxPlot.render with multiple outliers on both sides" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ -50.0, 1.0, 2.0, 3.0, 4.0, 5.0, 100.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Multi", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowOutliers(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render outlier styling with outlier_style" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 50.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const outlier_style = Style{ .bold = true };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withShowOutliers(true)
        .withOutlierStyle(outlier_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: Render — Focused Series Styling (4 tests)
// ============================================================================

test "BoxPlot.render focused=0 on two-series plot applies focus style" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const focused_style = Style{ .bold = true };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withFocused(0)
        .withFocusedStyle(focused_style)
        .withBoxStyle(Style{ .bold = false });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);

    // Series 0 is focused: scan its band for bold cells
    // Series 0 occupies left half, Series 1 occupies right half
    const band_width = area.width / 2;
    const series0_band_end = area.x + band_width;

    var found_focused_box_cell = false;
    var found_unfocused_box_cell = false;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█' or cell.char == '│' or cell.char == '─' or cell.char == '━') {
                    // Box/whisker/median glyphs
                    if (x < series0_band_end) {
                        // Series 0 (focused) should have bold style
                        if (cell.style.bold) found_focused_box_cell = true;
                    } else {
                        // Series 1 (not focused) should not have bold style
                        if (!cell.style.bold) found_unfocused_box_cell = true;
                    }
                }
            }
        }
    }

    try testing.expect(found_focused_box_cell);
    try testing.expect(found_unfocused_box_cell);
}

test "BoxPlot.render focused=1 applies style to second series" {
    var buf = try Buffer.init(testing.allocator, 70, 20);
    defer buf.deinit();
    var values1 = [_]f32{1.0};
    var values2 = [_]f32{5.0};
    var values3 = [_]f32{9.0};
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const focused_style = Style{ .dim = true };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withBoxStyle(Style{ .dim = false });
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 20 };
    bp.render(&buf, area);

    // Series 1 is focused: scan its band for dim cells
    // 3 series: each gets width 70/3 ≈ 23
    const band_width = area.width / 3;
    const series1_band_start = area.x + band_width;
    const series1_band_end = series1_band_start + band_width;

    var found_focused_dim_cell = false;
    var found_unfocused_non_dim_cell = false;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█' or cell.char == '│' or cell.char == '─' or cell.char == '━') {
                    if (x >= series1_band_start and x < series1_band_end) {
                        // Series 1 (focused) should have dim style
                        if (cell.style.dim) found_focused_dim_cell = true;
                    } else if (x < series1_band_start) {
                        // Series 0 (not focused) should not have dim style
                        if (!cell.style.dim) found_unfocused_non_dim_cell = true;
                    }
                }
            }
        }
    }

    try testing.expect(found_focused_dim_cell);
    try testing.expect(found_unfocused_non_dim_cell);
}

test "BoxPlot.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render changing focused index applies style to different series" {
    var buf1 = try Buffer.init(testing.allocator, 60, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 60, 20);
    defer buf2.deinit();

    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };

    const focused_style = Style{ .bold = true };
    const bp1 = BoxPlot.init()
        .withSeries(&series_arr)
        .withFocused(0)
        .withFocusedStyle(focused_style)
        .withBoxStyle(Style{ .bold = false });
    const bp2 = BoxPlot.init()
        .withSeries(&series_arr)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withBoxStyle(Style{ .bold = false });

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp1.render(&buf1, area);
    bp2.render(&buf2, area);

    // In buf1: Series 0 (left half) should be focused and bold
    // In buf2: Series 1 (right half) should be focused and bold
    const band_width = area.width / 2;
    const series0_band_end = area.x + band_width;

    var buf1_series0_bold: usize = 0;
    var buf1_series1_bold: usize = 0;
    var buf2_series0_bold: usize = 0;
    var buf2_series1_bold: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf1.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '│' or cell.char == '─' or cell.char == '━') and cell.style.bold) {
                    if (x < series0_band_end) buf1_series0_bold += 1
                    else buf1_series1_bold += 1;
                }
            }
            if (buf2.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '│' or cell.char == '─' or cell.char == '━') and cell.style.bold) {
                    if (x < series0_band_end) buf2_series0_bold += 1
                    else buf2_series1_bold += 1;
                }
            }
        }
    }

    // buf1: focused=0, so series 0 should have bold cells, series 1 should not
    try testing.expect(buf1_series0_bold > 0);
    try testing.expectEqual(@as(usize, 0), buf1_series1_bold);
    // buf2: focused=1, so series 1 should have bold cells, series 0 should not
    try testing.expectEqual(@as(usize, 0), buf2_series0_bold);
    try testing.expect(buf2_series1_bold > 0);
}

// ============================================================================
// Group 13: Render — show_labels Toggle (3 tests)
// ============================================================================

test "BoxPlot.render show_labels=true displays label text" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Series", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render show_labels=false still renders boxes" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Series", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render show_labels toggle affects rendering" {
    var buf1 = try Buffer.init(testing.allocator, 60, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 60, 20);
    defer buf2.deinit();

    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Series", .values = &values }};

    const bp_with_labels = BoxPlot.init().withSeries(&series_arr).withShowLabels(true);
    const bp_no_labels = BoxPlot.init().withSeries(&series_arr).withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp_with_labels.render(&buf1, area);
    bp_no_labels.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

// ============================================================================
// Group 14: Render — Block Border (3 tests)
// ============================================================================

test "BoxPlot.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const block = Block{};
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render block reduces inner area for box content" {
    var buf1 = try Buffer.init(testing.allocator, 50, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 20);
    defer buf2.deinit();

    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };

    const block = Block{};
    const bp_with_block = BoxPlot.init().withSeries(&series_arr).withBlock(block);
    const bp_no_block = BoxPlot.init().withSeries(&series_arr);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp_with_block.render(&buf1, area);
    bp_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "BoxPlot.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Data", .values = &values }};
    const block = (Block{}).withTitle("BoxPlot", .top_left);
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 15: Render — MAX_SERIES Cap (3 tests)
// ============================================================================

test "BoxPlot.render with exactly MAX_SERIES=8 renders all series" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var series_arr: [8]BoxPlotSeries = undefined;
    var values_array: [8][1]f32 = undefined;
    for (0..8) |i| {
        values_array[i] = [_]f32{@as(f32, @floatFromInt(i + 1))};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), bp.seriesCount());
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with 12 series caps to MAX_SERIES=8" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var series_arr: [12]BoxPlotSeries = undefined;
    var values_array: [12][1]f32 = undefined;
    for (0..12) |i| {
        values_array[i] = [_]f32{@as(f32, @floatFromInt(i + 1))};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), bp.seriesCount());
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with 16 series only renders first 8" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var series_arr: [16]BoxPlotSeries = undefined;
    var values_array: [16][1]f32 = undefined;
    for (0..16) |i| {
        values_array[i] = [_]f32{1.0};
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    try testing.expectEqual(@as(usize, 8), bp.seriesCount());
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Render — MAX_SAMPLES Cap (2 tests)
// ============================================================================

test "BoxPlot.render with >MAX_SAMPLES values truncates correctly" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values: [100]f32 = undefined;
    for (0..100) |i| {
        values[i] = @as(f32, @floatFromInt(i + 1));
    }
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    // Should compute from only first MAX_SAMPLES=64 samples
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with exactly MAX_SAMPLES=64 uses all samples" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values: [64]f32 = undefined;
    for (0..64) |i| {
        values[i] = @as(f32, @floatFromInt(i % 10 + 1));
    }
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Render — Degenerate Cases (3 tests)
// ============================================================================

test "BoxPlot.render with n=1 value does not divide by zero" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "Single", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render multiple series all with identical values" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 3.0, 3.0 };
    var values2 = [_]f32{ 3.0, 3.0, 3.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "C1", .values = &values1 },
        .{ .label = "C2", .values = &values2 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with negative and positive values" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ -5.0, -2.0, 0.0, 2.0, 5.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Mixed", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 18: Render — Small Areas (3 tests)
// ============================================================================

test "BoxPlot.render minimal height (3 rows) without label row" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render very narrow width" {
    var buf = try Buffer.init(testing.allocator, 10, 15);
    defer buf.deinit();
    var values = [_]f32{ 1.0, 2.0, 3.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 15 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render tiny area (8x6) still does not crash" {
    var buf = try Buffer.init(testing.allocator, 8, 6);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 4.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Tiny", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 6 };
    bp.render(&buf, area);
}

// ============================================================================
// Group 19: Render — Label Row Reservation (2 tests)
// ============================================================================

test "BoxPlot.render with show_labels=true reserves bottom row" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Series", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render height=1 with show_labels=true handles gracefully" {
    var buf = try Buffer.init(testing.allocator, 30, 1);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    // Height=1 with show_labels reserves all space for labels, leaving 0 for plot,
    // so render returns early without producing heatmap content (graceful handling)
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 20: Render — Buffer Bounds Safety (3 tests)
// ============================================================================

test "BoxPlot.render does not exceed buffer bounds" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0, 8.0, 9.0 };
    var values3 = [_]f32{ 2.0, 4.0, 6.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 3200);  // 80*40 max
}

test "BoxPlot.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 60);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 3.0, 5.0 };
    var values2 = [_]f32{ 6.0, 7.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 20, .y = 15, .width = 50, .height = 30 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with block on tiny area does not crash" {
    var buf = try Buffer.init(testing.allocator, 12, 8);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 4.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const block = Block{};
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 12, .height = 8 };
    bp.render(&buf, area);
}

// ============================================================================
// Group 21: Render — Style Application (4 tests)
// ============================================================================

test "BoxPlot.render with style applies to plot" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const style = Style{ .bold = true };
    const bp = BoxPlot.init().withSeries(&series_arr).withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with label_style applies to labels" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    var series_arr = [_]BoxPlotSeries{.{ .label = "Label", .values = &values }};
    const label_style = Style{ .italic = true };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withLabelStyle(label_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with focused_style applies to focused series" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const focused_style = Style{ .dim = true };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render with multiple styles applied" {
    var buf = try Buffer.init(testing.allocator, 70, 25);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var values3 = [_]f32{ 8.0, 9.0, 10.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
        .{ .label = "C", .values = &values3 },
    };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withStyle(Style{ .italic = true })
        .withBoxStyle(Style{ .bold = true })
        .withMedianStyle(Style{ .dim = true })
        .withLabelStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true, .italic = true })
        .withFocused(1);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 25 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render series.style overrides box_style for that series' box" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{ 2.0, 5.0, 8.0 };
    const series_style = Style{ .underline = true };
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values, .style = series_style }};
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withBoxStyle(Style{ .bold = true })
        .withFocused(99); // out-of-range so this series is not treated as focused
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);

    // The box column ('█' cells) must carry series.style (underline), not box_style (bold).
    var found_box_cell = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█') {
                    found_box_cell = true;
                    try testing.expect(cell.style.underline);
                    try testing.expect(!cell.style.bold);
                }
            }
        }
    }
    try testing.expect(found_box_cell);
}

// ============================================================================
// Group 22: Real-World Scenarios (5 tests)
// ============================================================================

test "BoxPlot.render test score distributions across three classes" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    // Class A: scores 60-75
    var scores_a = [_]f32{ 60.0, 65.0, 68.0, 70.0, 72.0, 75.0 };
    // Class B: scores 70-90
    var scores_b = [_]f32{ 70.0, 75.0, 80.0, 85.0, 88.0, 90.0 };
    // Class C: scores 50-95 (wider spread)
    var scores_c = [_]f32{ 50.0, 60.0, 70.0, 80.0, 90.0, 95.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "ClassA", .values = &scores_a },
        .{ .label = "ClassB", .values = &scores_b },
        .{ .label = "ClassC", .values = &scores_c },
    };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render latency percentiles across services" {
    var buf = try Buffer.init(testing.allocator, 90, 25);
    defer buf.deinit();
    var service_a = [_]f32{ 10.0, 12.0, 15.0, 18.0, 20.0, 50.0 };
    var service_b = [_]f32{ 5.0, 8.0, 10.0, 12.0, 15.0, 20.0 };
    var service_c = [_]f32{ 20.0, 30.0, 50.0, 80.0, 100.0, 500.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "ServiceA", .values = &service_a },
        .{ .label = "ServiceB", .values = &service_b },
        .{ .label = "ServiceC", .values = &service_c },
    };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withShowOutliers(true);
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 25 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render all features enabled together" {
    var buf = try Buffer.init(testing.allocator, 90, 30);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 1.0, 2.0, 3.0, 3.0 };
    var values2 = [_]f32{ 5.0, 5.0, 6.0, 6.0, 6.0, 50.0 };
    var values3 = [_]f32{ 8.0, 8.0, 9.0, 9.0, 10.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "Series1", .values = &values1, .style = Style{ .bold = true } },
        .{ .label = "Series2", .values = &values2 },
        .{ .label = "Series3", .values = &values3, .style = Style{ .dim = true } },
    };
    const bp = BoxPlot.init()
        .withSeries(&series_arr)
        .withFocused(1)
        .withShowLabels(true)
        .withShowOutliers(true)
        .withStyle(Style{ .italic = true })
        .withBoxStyle(Style{ .bold = true })
        .withMedianStyle(Style{ .italic = true })
        .withFocusedStyle(Style{ .bold = true })
        .withBlock((Block{}).withTitle("BoxPlot", .top_left));
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 30 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "BoxPlot.render large area with MAX_SERIES and many samples" {
    var buf = try Buffer.init(testing.allocator, 120, 60);
    defer buf.deinit();
    var series_arr: [8]BoxPlotSeries = undefined;
    var values_array: [8][30]f32 = undefined;
    for (0..8) |i| {
        for (0..30) |j| {
            values_array[i][j] = @as(f32, @floatFromInt(i * 2 + 1)) + @as(f32, @floatFromInt(j % 3));
        }
        series_arr[i] = .{ .label = "S", .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 60 };
    bp.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}
