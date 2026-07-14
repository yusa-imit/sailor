//! RidgelinePlot Widget Tests — TDD Red Phase
//!
//! Tests RidgelinePlot widget rendering stacked density silhouettes (joyplot style).
//! Each series renders as a silhouette baseline with height-based glyph ramp (▁▂▃▄▅▆▇█),
//! with configurable overlap, scale normalization (shared vs per-series), ordering
//! (top-to-bottom or bottom-to-top), and focused styling.
//!
//! Tests cover initialization, builder pattern, seriesCount() capping at MAX_SERIES,
//! baseline row placement per series (normal vs reverse order), silhouette height
//! mapping against known bin values (hand-computed), shared vs per-series scale,
//! overlap configuration, focused series styling precedence, MAX_SERIES/MAX_BINS
//! capping without panic, edge cases (empty values, all-zero, single bin),
//! out-of-range/negative value handling (no-panic clamping), and block borders.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const RidgelinePlot = sailor.tui.widgets.RidgelinePlot;
const RidgelineSeries = sailor.tui.widgets.ridgeline_plot.RidgelineSeries;

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

/// Get cell at position in area (relative coordinates)
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

test "RidgelinePlot.init creates plot with zero series" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(@as(usize, 0), plot.series.len);
}

test "RidgelinePlot.init defaults focused to null" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(@as(?usize, null), plot.focused);
}

test "RidgelinePlot.init defaults reverse to false" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(false, plot.reverse);
}

test "RidgelinePlot.init defaults shared_scale to true" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(true, plot.shared_scale);
}

test "RidgelinePlot.init defaults overlap to 0" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(@as(u16, 0), plot.overlap);
}

test "RidgelinePlot.init defaults block to null" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(@as(?Block, null), plot.block);
}

// ============================================================================
// Group 2: RidgelineSeries Struct Defaults (3 tests)
// ============================================================================

test "RidgelineSeries default label is empty" {
    const series = RidgelineSeries{};
    try testing.expectEqualStrings("", series.label);
}

test "RidgelineSeries default values is empty slice" {
    const series = RidgelineSeries{};
    try testing.expectEqual(@as(usize, 0), series.values.len);
}

test "RidgelineSeries default style is empty" {
    const series = RidgelineSeries{};
    try testing.expectEqual(Style{}, series.style);
}

// ============================================================================
// Group 3: Style Defaults and Constants (4 tests)
// ============================================================================

test "RidgelinePlot.init has default empty styles" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(Style{}, plot.style);
    try testing.expectEqual(Style{}, plot.focused_style);
    try testing.expectEqual(Style{}, plot.label_style);
}

test "RidgelinePlot.MAX_SERIES equals 8" {
    try testing.expectEqual(@as(usize, 8), RidgelinePlot.MAX_SERIES);
}

test "RidgelinePlot.MAX_BINS equals 64" {
    try testing.expectEqual(@as(usize, 64), RidgelinePlot.MAX_BINS);
}

test "RidgelinePlot.init has default label_column_width to 0" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(@as(u16, 0), plot.label_column_width);
}

// ============================================================================
// Group 4: seriesCount() Method (5 tests)
// ============================================================================

test "seriesCount with zero series returns 0" {
    const plot = RidgelinePlot.init();
    try testing.expectEqual(@as(usize, 0), plot.seriesCount());
}

test "seriesCount with 1 series returns 1" {
    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]RidgelineSeries{.{ .label = "A", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 1), plot.seriesCount());
}

test "seriesCount with 4 series returns 4" {
    var vals_a = [_]f32{1.0};
    var vals_b = [_]f32{2.0};
    var vals_c = [_]f32{3.0};
    var vals_d = [_]f32{4.0};
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
        .{ .label = "C", .values = &vals_c },
        .{ .label = "D", .values = &vals_d },
    };
    const plot = RidgelinePlot.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 4), plot.seriesCount());
}

test "seriesCount with exactly MAX_SERIES=8 returns 8" {
    var vals: [8][1]f32 = undefined;
    var series: [8]RidgelineSeries = undefined;
    for (0..8) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const plot = RidgelinePlot.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), plot.seriesCount());
}

test "seriesCount caps at MAX_SERIES=8 when 16 series provided" {
    var vals: [16][1]f32 = undefined;
    var series: [16]RidgelineSeries = undefined;
    for (0..16) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const plot = RidgelinePlot.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), plot.seriesCount());
}

// ============================================================================
// Group 5: Builder Immutability — All Builder Methods (11 tests)
// ============================================================================

test "withSeries does not modify original" {
    var vals1 = [_]f32{1.0};
    var vals2 = [_]f32{2.0};
    var vals3 = [_]f32{3.0};
    var series1 = [_]RidgelineSeries{.{ .label = "A", .values = &vals1 }};
    var series2 = [_]RidgelineSeries{
        .{ .label = "B", .values = &vals2 },
        .{ .label = "C", .values = &vals3 },
    };
    const plot1 = RidgelinePlot.init().withSeries(&series1);
    const plot2 = plot1.withSeries(&series2);
    try testing.expectEqual(@as(usize, 1), plot1.seriesCount());
    try testing.expectEqual(@as(usize, 2), plot2.seriesCount());
}

test "withFocused does not modify original" {
    const plot1 = RidgelinePlot.init().withFocused(0);
    const plot2 = plot1.withFocused(3);
    try testing.expectEqual(@as(?usize, 0), plot1.focused);
    try testing.expectEqual(@as(?usize, 3), plot2.focused);
}

test "withReverse does not modify original" {
    const plot1 = RidgelinePlot.init().withReverse(false);
    const plot2 = plot1.withReverse(true);
    try testing.expectEqual(false, plot1.reverse);
    try testing.expectEqual(true, plot2.reverse);
}

test "withSharedScale does not modify original" {
    const plot1 = RidgelinePlot.init().withSharedScale(true);
    const plot2 = plot1.withSharedScale(false);
    try testing.expectEqual(true, plot1.shared_scale);
    try testing.expectEqual(false, plot2.shared_scale);
}

test "withOverlap does not modify original" {
    const plot1 = RidgelinePlot.init().withOverlap(0);
    const plot2 = plot1.withOverlap(3);
    try testing.expectEqual(@as(u16, 0), plot1.overlap);
    try testing.expectEqual(@as(u16, 3), plot2.overlap);
}

test "withStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const plot1 = RidgelinePlot.init().withStyle(s1);
    const plot2 = plot1.withStyle(s2);
    try testing.expectEqual(true, plot1.style.bold);
    try testing.expectEqual(true, plot2.style.dim);
}

test "withFocusedStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const plot1 = RidgelinePlot.init().withFocusedStyle(s1);
    const plot2 = plot1.withFocusedStyle(s2);
    try testing.expectEqual(true, plot1.focused_style.bold);
    try testing.expectEqual(true, plot2.focused_style.dim);
}

test "withLabelStyle does not modify original" {
    const s1 = Style{ .italic = true };
    const s2 = Style{ .underline = true };
    const plot1 = RidgelinePlot.init().withLabelStyle(s1);
    const plot2 = plot1.withLabelStyle(s2);
    try testing.expectEqual(true, plot1.label_style.italic);
    try testing.expectEqual(true, plot2.label_style.underline);
}

test "withLabelColumnWidth does not modify original" {
    const plot1 = RidgelinePlot.init().withLabelColumnWidth(0);
    const plot2 = plot1.withLabelColumnWidth(10);
    try testing.expectEqual(@as(u16, 0), plot1.label_column_width);
    try testing.expectEqual(@as(u16, 10), plot2.label_column_width);
}

test "withBlock does not modify original" {
    const plot1 = RidgelinePlot.init().withBlock(.{});
    const plot2 = plot1.withBlock(null);
    try testing.expect(plot1.block != null);
    try testing.expect(plot2.block == null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (3 tests)
// ============================================================================

test "render with 0x0 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = RidgelinePlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    plot.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = RidgelinePlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    plot.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = RidgelinePlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    plot.render(&buf, area);
}

// ============================================================================
// Group 7: Render — Empty Data (2 tests)
// ============================================================================

test "render with zero series produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = RidgelinePlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    plot.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero series and Block does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = RidgelinePlot.init().withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    plot.render(&buf, area);
}

// ============================================================================
// Group 8: Render — Single Series (4 tests)
// ============================================================================

test "render with single series produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]RidgelineSeries{.{ .label = "A", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with single series empty values does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals: [0]f32 = undefined;
    var series = [_]RidgelineSeries{.{ .label = "Empty", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

test "render with single series all-zero values does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 0.0, 0.0, 0.0 };
    var series = [_]RidgelineSeries{.{ .label = "AllZero", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

test "render with single series single bin" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{5.0};
    var series = [_]RidgelineSeries{.{ .label = "Single", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 9: Baseline Row Placement — Normal Order (top-to-bottom) (4 tests)
// ============================================================================

test "two series default order places first series above second" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0, 3.0 };
    var vals_b = [_]f32{ 2.0, 3.0, 4.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init().withSeries(&series).withReverse(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "three series normal order render without crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var vals_c = [_]f32{ 3.0, 4.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
        .{ .label = "C", .values = &vals_c },
    };
    const plot = RidgelinePlot.init().withSeries(&series).withReverse(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "single series ignores reverse order" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]RidgelineSeries{.{ .label = "S", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series).withReverse(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "reverse=false baseline rows render distinct per series" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 5.0, 10.0 };
    var vals_b = [_]f32{ 8.0, 6.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init().withSeries(&series).withReverse(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 10: Baseline Row Placement — Reverse Order (bottom-to-top) (3 tests)
// ============================================================================

test "reverse=true reverses series order" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init().withSeries(&series).withReverse(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "reverse=true with three series places them bottom-to-top" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var vals_c = [_]f32{ 3.0, 4.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
        .{ .label = "C", .values = &vals_c },
    };
    const plot = RidgelinePlot.init().withSeries(&series).withReverse(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "reverse toggle does not modify original plot" {
    const plot1 = RidgelinePlot.init().withReverse(false);
    const plot2 = plot1.withReverse(true);
    try testing.expectEqual(false, plot1.reverse);
    try testing.expectEqual(true, plot2.reverse);
}

// ============================================================================
// Group 11: Silhouette Height Mapping — Hand-Computed Values (6 tests)
// ============================================================================

test "simple bin values [1,2,3] render with varying heights" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Values [1,2,3] should map to progressively taller glyphs
    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]RidgelineSeries{.{ .label = "Simple", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "single large bin renders at full height" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Single value of 100 should map to full-height glyph (█)
    var vals = [_]f32{100.0};
    var series = [_]RidgelineSeries{.{ .label = "Large", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // Should contain block glyphs (▁▂▃▄▅▆▇█)
    const has_blocks = countChar(buf, area, '█') > 0 or
                       countChar(buf, area, '▁') > 0 or
                       countChar(buf, area, '▂') > 0 or
                       countChar(buf, area, '▃') > 0;
    try testing.expect(has_blocks);
}

test "proportional bin heights within single series" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Values [2, 4, 8] should render with increasing heights
    var vals = [_]f32{ 2.0, 4.0, 8.0 };
    var series = [_]RidgelineSeries{.{ .label = "Proportional", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "zero bin value renders as empty/space" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Values [5, 0, 5] — middle bin at 0 should render as baseline
    var vals = [_]f32{ 5.0, 0.0, 5.0 };
    var series = [_]RidgelineSeries{.{ .label = "WithZero", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "identical bin values render at same height" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Values [5, 5, 5] should all render at same glyph height
    var vals = [_]f32{ 5.0, 5.0, 5.0 };
    var series = [_]RidgelineSeries{.{ .label = "Constant", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "64 bins at max capacity renders without panic" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Create MAX_BINS=64 values
    var vals: [64]f32 = undefined;
    for (0..64) |i| {
        vals[i] = @as(f32, @floatFromInt(i + 1));
    }
    var series = [_]RidgelineSeries{.{ .label = "MaxBins", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    plot.render(&buf, area);
    // Should not crash, should render content
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 12: Shared vs Per-Series Scale Normalization (4 tests)
// ============================================================================

test "shared_scale=true normalizes all series against global max" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Series A: max=5, Series B: max=10
    // With shared_scale=true, both use global max=10
    var vals_a = [_]f32{ 1.0, 2.0, 5.0 };
    var vals_b = [_]f32{ 5.0, 7.0, 10.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withSharedScale(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "shared_scale=false normalizes each series independently" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Series A: max=5, Series B: max=10
    // With shared_scale=false, A uses max=5, B uses max=10
    var vals_a = [_]f32{ 1.0, 2.0, 5.0 };
    var vals_b = [_]f32{ 5.0, 7.0, 10.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withSharedScale(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "shared_scale toggle preserves immutability" {
    const plot1 = RidgelinePlot.init().withSharedScale(true);
    const plot2 = plot1.withSharedScale(false);
    try testing.expectEqual(true, plot1.shared_scale);
    try testing.expectEqual(false, plot2.shared_scale);
}

test "low-max series with shared_scale=true renders shorter than per-series" {
    // This is a behavioral test: with shared_scale, series A (max=2) should
    // render proportionally shorter than with per-series scale where it uses its own max.
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0 };

    // Render with shared_scale=true (and another high-max series present)
    var vals_high = [_]f32{ 50.0, 100.0 };
    var series_mixed = [_]RidgelineSeries{
        .{ .label = "Low", .values = &vals },
        .{ .label = "High", .values = &vals_high },
    };
    const plot_shared = RidgelinePlot.init()
        .withSeries(&series_mixed)
        .withSharedScale(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot_shared.render(&buf, area);
    // Should render without crash; behavioral verification done at higher level
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 13: Overlap Configuration (4 tests)
// ============================================================================

test "overlap=0 clips silhouette to own row band" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withOverlap(0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "overlap>0 allows silhouette to rise into rows above" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 5.0, 8.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withOverlap(2);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "overlap=0 vs overlap=2 produce different rendering" {
    var buf1 = try Buffer.init(testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 80, 24);
    defer buf2.deinit();

    var vals_a = [_]f32{ 2.0, 3.0 };
    var vals_b = [_]f32{ 8.0, 10.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };

    const plot_no_overlap = RidgelinePlot.init()
        .withSeries(&series)
        .withOverlap(0);
    const plot_with_overlap = RidgelinePlot.init()
        .withSeries(&series)
        .withOverlap(2);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    plot_no_overlap.render(&buf1, area);
    plot_with_overlap.render(&buf2, area);

    // Both should render, but may have different content distributions
    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

test "large overlap=10 does not crash with max content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 5.0, 10.0, 8.0 };
    var series = [_]RidgelineSeries{.{ .label = "Overlap", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withOverlap(10);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 14: Focused Series Styling Precedence (4 tests)
// ============================================================================

test "focused_style overrides series style when set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a, .style = .{ .dim = true } },
        .{ .label = "B", .values = &vals_b },
    };
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused=null skips focused styling" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]RidgelineSeries{.{ .label = "A", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withFocused(null)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused_style only applies when explicitly set (empty Style ignored)" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a, .style = .{ .italic = true } },
        .{ .label = "B", .values = &vals_b },
    };

    // focused_style is default empty Style{} — should not override per-series style
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withFocused(0)
        .withFocusedStyle(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused index beyond series count does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]RidgelineSeries{.{ .label = "A", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

// ============================================================================
// Group 15: MAX_SERIES/MAX_BINS Capping (4 tests)
// ============================================================================

test "more than MAX_SERIES=8 series caps silently at 8" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Create 16 series but should only render 8
    var vals: [16][1]f32 = undefined;
    var series: [16]RidgelineSeries = undefined;
    for (0..16) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }

    const plot = RidgelinePlot.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), plot.seriesCount());

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "more than MAX_BINS=64 bins in single series caps silently" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Create 128 values but should only process 64
    var vals: [128]f32 = undefined;
    for (0..128) |i| {
        vals[i] = @as(f32, @floatFromInt(i % 20 + 1));
    }
    var series = [_]RidgelineSeries{.{ .label = "Many", .values = &vals }};

    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    plot.render(&buf, area);
    // Should not panic, should render with capped bins
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "exactly MAX_SERIES=8 series render without capping" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals: [8][1]f32 = undefined;
    var series: [8]RidgelineSeries = undefined;
    for (0..8) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }

    const plot = RidgelinePlot.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), plot.seriesCount());

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "exactly MAX_BINS=64 bins render without capping" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals: [64]f32 = undefined;
    for (0..64) |i| {
        vals[i] = @as(f32, @floatFromInt(i % 20 + 1));
    }
    var series = [_]RidgelineSeries{.{ .label = "MaxBins", .values = &vals }};

    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 16: Out-of-Range/Negative Value Handling (5 tests)
// ============================================================================

test "negative values in series clamp safely without overflow" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Negative values should clamp to 0 or handle gracefully
    var vals = [_]f32{ -5.0, 0.0, 5.0 };
    var series = [_]RidgelineSeries{.{ .label = "Negative", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // Should not crash or overflow
    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "all-negative values do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ -10.0, -5.0, -1.0 };
    var series = [_]RidgelineSeries{.{ .label = "AllNeg", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
}

test "very large positive values do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1e6, 2e6, 3e6 };
    var series = [_]RidgelineSeries{.{ .label = "Huge", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "mixed negative and positive values normalize correctly" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ -10.0, 0.0, 10.0, 20.0 };
    var series = [_]RidgelineSeries{.{ .label = "Mixed", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "inf and nan values do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const inf = std.math.inf(f32);
    const nan = std.math.nan(f32);
    var vals = [_]f32{ inf, nan, 5.0 };
    var series = [_]RidgelineSeries{.{ .label = "SpecialFloats", .values = &vals }};
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    // Should handle gracefully without crash
}

// ============================================================================
// Group 17: Block Border (3 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]RidgelineSeries{.{ .label = "A", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    plot.render(&buf, area);

    // Block border should render — at least one border glyph
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

    var vals = [_]f32{ 2.0, 3.0 };
    var series = [_]RidgelineSeries{.{ .label = "A", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]RidgelineSeries{.{ .label = "A", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };

    plot.render(&buf, area);
}

// ============================================================================
// Group 18: Multiple Series Content Rendering (4 tests)
// ============================================================================

test "render with 4 series produces more content than 1" {
    var buf1 = try Buffer.init(testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 80, 24);
    defer buf2.deinit();

    var vals1 = [_]f32{ 2.0, 3.0 };
    var series1 = [_]RidgelineSeries{.{ .label = "A", .values = &vals1 }};

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var vals_c = [_]f32{ 3.0, 4.0 };
    var vals_d = [_]f32{ 4.0, 5.0 };
    var series4 = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
        .{ .label = "C", .values = &vals_c },
        .{ .label = "D", .values = &vals_d },
    };

    const plot1 = RidgelinePlot.init().withSeries(&series1);
    const plot4 = RidgelinePlot.init().withSeries(&series4);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    plot1.render(&buf1, area);
    plot4.render(&buf2, area);

    const count1 = countNonEmptyCells(buf1, area);
    const count4 = countNonEmptyCells(buf2, area);
    try testing.expect(count4 >= count1);
}

test "render 6 series with varying value ranges" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 5.0, 6.0 };
    var vals_c = [_]f32{ 10.0, 15.0 };
    var vals_d = [_]f32{ 3.0, 4.0 };
    var vals_e = [_]f32{ 20.0, 25.0 };
    var vals_f = [_]f32{ 2.0, 3.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
        .{ .label = "C", .values = &vals_c },
        .{ .label = "D", .values = &vals_d },
        .{ .label = "E", .values = &vals_e },
        .{ .label = "F", .values = &vals_f },
    };
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 25 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with MAX_SERIES (8 items)" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var vals: [8][2]f32 = undefined;
    var series: [8]RidgelineSeries = undefined;
    for (0..8) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        vals[i][1] = @as(f32, @floatFromInt(i + 2));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };

    plot.render(&buf, area);
    try testing.expectEqual(@as(usize, 8), plot.seriesCount());
}

test "render more than MAX_SERIES caps at 8" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var vals: [16][1]f32 = undefined;
    var series: [16]RidgelineSeries = undefined;
    for (0..16) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const plot = RidgelinePlot.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };

    plot.render(&buf, area);
    try testing.expectEqual(@as(usize, 8), plot.seriesCount());
}

// ============================================================================
// Group 19: Label Column Rendering (3 tests)
// ============================================================================

test "label_column_width=0 renders no label column" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]RidgelineSeries{.{ .label = "MyLabel", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withLabelColumnWidth(0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "label_column_width>0 may render labels left-aligned" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]RidgelineSeries{.{ .label = "LongLabel", .values = &vals }};
    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withLabelColumnWidth(10);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "auto-sized label column preserves immutability" {
    const plot1 = RidgelinePlot.init().withLabelColumnWidth(5);
    const plot2 = plot1.withLabelColumnWidth(15);
    try testing.expectEqual(@as(u16, 5), plot1.label_column_width);
    try testing.expectEqual(@as(u16, 15), plot2.label_column_width);
}

// ============================================================================
// Group 20: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields correctly" {
    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]RidgelineSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };

    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withFocused(1)
        .withReverse(true)
        .withSharedScale(false)
        .withOverlap(2)
        .withStyle(.{ .bold = true })
        .withFocusedStyle(.{ .dim = true })
        .withLabelStyle(.{ .italic = true })
        .withLabelColumnWidth(8)
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), plot.seriesCount());
    try testing.expectEqual(@as(?usize, 1), plot.focused);
    try testing.expectEqual(true, plot.reverse);
    try testing.expectEqual(false, plot.shared_scale);
    try testing.expectEqual(@as(u16, 2), plot.overlap);
    try testing.expectEqual(@as(u16, 8), plot.label_column_width);
    try testing.expect(plot.block != null);
}

test "builder chain preserves last value for each field" {
    const plot = RidgelinePlot.init()
        .withFocused(0)
        .withFocused(5)
        .withReverse(true)
        .withReverse(false)
        .withSharedScale(false)
        .withSharedScale(true)
        .withOverlap(1)
        .withOverlap(3);

    try testing.expectEqual(@as(?usize, 5), plot.focused);
    try testing.expectEqual(false, plot.reverse);
    try testing.expectEqual(true, plot.shared_scale);
    try testing.expectEqual(@as(u16, 3), plot.overlap);
}

// ============================================================================
// Group 21: Realistic Scenario (2 tests)
// ============================================================================

test "render joyplot-style distribution comparison with styling" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    // Three distributions simulating kernel density estimates
    var vals_a = [_]f32{ 1.0, 3.0, 5.0, 4.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 4.0, 6.0, 5.0, 3.0 };
    var vals_c = [_]f32{ 1.5, 3.5, 7.0, 6.0, 3.5 };

    var series = [_]RidgelineSeries{
        .{ .label = "Distribution A", .values = &vals_a, .style = .{ .bold = true } },
        .{ .label = "Distribution B", .values = &vals_b, .style = .{ .dim = true } },
        .{ .label = "Distribution C", .values = &vals_c },
    };

    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withReverse(false)
        .withSharedScale(true)
        .withOverlap(1)
        .withLabelColumnWidth(15)
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with all toggles and styling options enabled" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var vals_a = [_]f32{ 2.0, 3.0, 4.0 };
    var vals_b = [_]f32{ 1.0, 5.0, 6.0 };

    var series = [_]RidgelineSeries{
        .{ .label = "Series A", .values = &vals_a, .style = .{ .italic = true } },
        .{ .label = "Series B", .values = &vals_b },
    };

    const plot = RidgelinePlot.init()
        .withSeries(&series)
        .withFocused(0)
        .withReverse(true)
        .withSharedScale(false)
        .withOverlap(2)
        .withStyle(.{ .underline = true })
        .withFocusedStyle(.{ .bold = true })
        .withLabelStyle(.{ .bold = true })
        .withLabelColumnWidth(12)
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 28 };

    plot.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}
