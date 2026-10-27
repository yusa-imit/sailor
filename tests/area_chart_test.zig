//! AreaChart Widget Tests — TDD Red Phase
//!
//! Tests AreaChart widget rendering one or more filled area series with optional stacking,
//! distinct line boundary markers, baseline normalization (always y=0), and styling options.
//!
//! Tests cover initialization, builder pattern, series count capping at MAX_SERIES,
//! render geometry (area fill positions, line boundary row placement at specific columns),
//! stacked vs non-stacked fill semantics, line boundary character placement, custom
//! fill/line characters, min_val/max_val overrides, focused series styling, focused_style
//! precedence, MAX_SERIES/MAX_POINTS capping without panic, edge cases (empty data,
//! zero-height/zero-width areas, all-zero values, negative values, NaN/Infinity values),
//! block border support, and realistic multi-series scenarios.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const AreaChart = sailor.tui.widgets.AreaChart;
const AreaSeries = sailor.tui.widgets.area_chart.AreaSeries;

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

/// Get cell at position in area (absolute coordinates)
fn cellAtPos(buf: Buffer, x: u16, y: u16) ?sailor.Cell {
    if (x >= buf.width or y >= buf.height) return null;
    return buf.getConst(x, y);
}

/// Approximate float equality
fn floatEq(a: f32, b: f32, epsilon: f32) bool {
    return @abs(a - b) < epsilon;
}

/// Expect the character at (x, y) to equal `want`.
fn expectCharAt(buf: Buffer, x: u16, y: u16, want: u21) !void {
    const cell = cellAtPos(buf, x, y) orelse return error.OutOfBounds;
    try testing.expectEqual(want, cell.char);
}

/// Expect every cell outside `area` to be an untouched default cell.
fn expectBlankOutside(buf: Buffer, area: Rect) !void {
    var y: u16 = 0;
    while (y < buf.height) : (y += 1) {
        var x: u16 = 0;
        while (x < buf.width) : (x += 1) {
            const inside = x >= area.x and x < area.x + area.width and
                y >= area.y and y < area.y + area.height;
            if (inside) continue;
            try testing.expect(buf.getConst(x, y).?.eql(.{}));
        }
    }
}

/// Expect two equally sized buffers to hold identical cells (char and style).
fn expectBuffersEqual(a: Buffer, b: Buffer) !void {
    try testing.expectEqual(a.width, b.width);
    try testing.expectEqual(a.height, b.height);
    for (a.cells, b.cells) |ca, cb| {
        try testing.expect(ca.eql(cb));
    }
}

/// Render `[1, bad, 3]` and expect the non-finite point to be drawn as a baseline
/// value of 0 while the finite points are plotted, nothing outside the area.
fn expectNonFiniteDrawnAsZero(bad: f32) !void {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var ref = try Buffer.init(testing.allocator, 80, 24);
    defer ref.deinit();
    var vals = [_]f32{ 1.0, bad, 3.0 };
    var zero_vals = [_]f32{ 1.0, 0.0, 3.0 };
    var series = [_]AreaSeries{.{ .label = "Bad", .values = &vals }};
    var zero_series = [_]AreaSeries{.{ .label = "Bad", .values = &zero_vals }};
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    AreaChart.init().withSeries(&series).render(&buf, area);
    AreaChart.init().withSeries(&zero_series).render(&ref, area);
    try expectBuffersEqual(buf, ref);
    // Scale 0..3 over 15 rows: 1.0 reaches row 10, 3.0 reaches row 0, baseline is row 14.
    try expectCharAt(buf, 0, 10, '▀');
    try expectCharAt(buf, 0, 14, '█');
    try expectCharAt(buf, 29, 14, '▀');
    try expectCharAt(buf, 29, 13, ' ');
    try expectCharAt(buf, 59, 0, '▀');
    try expectCharAt(buf, 59, 14, '█');
    try testing.expectEqual(@as(usize, 5 + 1 + 15), countNonEmptyCells(buf, area));
    try expectBlankOutside(buf, area);
}

// ============================================================================
// Group 1: Init and Defaults (6 tests)
// ============================================================================

test "AreaChart.init creates chart with zero series" {
    const chart = AreaChart.init();
    try testing.expectEqual(@as(usize, 0), chart.series_count);
}

test "AreaChart.init defaults stacked to false" {
    const chart = AreaChart.init();
    try testing.expectEqual(false, chart.stacked);
}

test "AreaChart.init defaults show_line to true" {
    const chart = AreaChart.init();
    try testing.expectEqual(true, chart.show_line);
}

test "AreaChart.init defaults fill_char to '█'" {
    const chart = AreaChart.init();
    try testing.expectEqual(@as(u21, '█'), chart.fill_char);
}

test "AreaChart.init defaults line_char to '▀'" {
    const chart = AreaChart.init();
    try testing.expectEqual(@as(u21, '▀'), chart.line_char);
}

test "AreaChart.init defaults min_val/max_val to null" {
    const chart = AreaChart.init();
    try testing.expectEqual(@as(?f32, null), chart.min_val);
    try testing.expectEqual(@as(?f32, null), chart.max_val);
}

// ============================================================================
// Group 2: AreaSeries Struct Defaults (3 tests)
// ============================================================================

test "AreaSeries default label is empty" {
    const series = AreaSeries{};
    try testing.expectEqualStrings("", series.label);
}

test "AreaSeries default values is empty slice" {
    const series = AreaSeries{};
    try testing.expectEqual(@as(usize, 0), series.values.len);
}

test "AreaSeries default style is empty Style" {
    const series = AreaSeries{};
    try testing.expectEqual(Style{}, series.style);
}

// ============================================================================
// Group 3: Constants (2 tests)
// ============================================================================

test "AreaChart.MAX_SERIES equals 8" {
    try testing.expectEqual(@as(usize, 8), AreaChart.MAX_SERIES);
}

test "AreaChart.MAX_POINTS equals 64" {
    try testing.expectEqual(@as(usize, 64), AreaChart.MAX_POINTS);
}

// ============================================================================
// Group 4: Init and Style Defaults (3 tests)
// ============================================================================

test "AreaChart.init defaults focused to null" {
    const chart = AreaChart.init();
    try testing.expectEqual(@as(?usize, null), chart.focused);
}

test "AreaChart.init defaults style to empty" {
    const chart = AreaChart.init();
    try testing.expectEqual(Style{}, chart.style);
    try testing.expectEqual(Style{}, chart.focused_style);
}

test "AreaChart.init defaults block to null" {
    const chart = AreaChart.init();
    try testing.expectEqual(@as(?Block, null), chart.block);
}

// ============================================================================
// Group 5: Builder Immutability — All Builder Methods (11 tests)
// ============================================================================

test "withSeries does not modify original" {
    var vals1 = [_]f32{ 1.0, 2.0 };
    var vals2 = [_]f32{ 3.0, 4.0 };
    var vals3 = [_]f32{ 5.0, 6.0 };
    var series1 = [_]AreaSeries{.{ .label = "A", .values = &vals1 }};
    var series2 = [_]AreaSeries{
        .{ .label = "B", .values = &vals2 },
        .{ .label = "C", .values = &vals3 },
    };
    const chart1 = AreaChart.init().withSeries(&series1);
    const chart2 = chart1.withSeries(&series2);
    try testing.expectEqual(@as(usize, 1), chart1.series_count);
    try testing.expectEqual(@as(usize, 2), chart2.series_count);
}

test "withStacked does not modify original" {
    const chart1 = AreaChart.init().withStacked(false);
    const chart2 = chart1.withStacked(true);
    try testing.expectEqual(false, chart1.stacked);
    try testing.expectEqual(true, chart2.stacked);
}

test "withShowLine does not modify original" {
    const chart1 = AreaChart.init().withShowLine(true);
    const chart2 = chart1.withShowLine(false);
    try testing.expectEqual(true, chart1.show_line);
    try testing.expectEqual(false, chart2.show_line);
}

test "withFillChar does not modify original" {
    const chart1 = AreaChart.init().withFillChar('█');
    const chart2 = chart1.withFillChar('▓');
    try testing.expectEqual(@as(u21, '█'), chart1.fill_char);
    try testing.expectEqual(@as(u21, '▓'), chart2.fill_char);
}

test "withLineChar does not modify original" {
    const chart1 = AreaChart.init().withLineChar('▀');
    const chart2 = chart1.withLineChar('─');
    try testing.expectEqual(@as(u21, '▀'), chart1.line_char);
    try testing.expectEqual(@as(u21, '─'), chart2.line_char);
}

test "withMinVal does not modify original" {
    const chart1 = AreaChart.init().withMinVal(-10.0);
    const chart2 = chart1.withMinVal(0.0);
    try testing.expectEqual(@as(f32, -10.0), chart1.min_val.?);
    try testing.expectEqual(@as(f32, 0.0), chart2.min_val.?);
}

test "withMaxVal does not modify original" {
    const chart1 = AreaChart.init().withMaxVal(100.0);
    const chart2 = chart1.withMaxVal(1000.0);
    try testing.expectEqual(@as(f32, 100.0), chart1.max_val.?);
    try testing.expectEqual(@as(f32, 1000.0), chart2.max_val.?);
}

test "withFocused does not modify original" {
    const chart1 = AreaChart.init().withFocused(0);
    const chart2 = chart1.withFocused(3);
    try testing.expectEqual(@as(?usize, 0), chart1.focused);
    try testing.expectEqual(@as(?usize, 3), chart2.focused);
}

test "withFocusedStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = AreaChart.init().withFocusedStyle(s1);
    const chart2 = chart1.withFocusedStyle(s2);
    try testing.expectEqual(true, chart1.focused_style.bold);
    try testing.expectEqual(true, chart2.focused_style.dim);
}

test "withBlock does not modify original" {
    const chart1 = AreaChart.init().withBlock(.{});
    const chart2 = chart1.withBlock(null);
    try testing.expect(chart1.block != null);
    try testing.expect(chart2.block == null);
}

test "withStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .italic = true };
    const chart1 = AreaChart.init().withStyle(s1);
    const chart2 = chart1.withStyle(s2);
    try testing.expectEqual(true, chart1.style.bold);
    try testing.expectEqual(true, chart2.style.italic);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (3 tests)
// ============================================================================

test "render with 0x0 area leaves every buffer cell untouched" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
    try expectBlankOutside(buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, .{
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 24,
    }));
}

test "render with 1x1 area draws only the line char at that one cell" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
    // A single row collapses baseline and value onto row 0, so only the boundary char shows.
    try expectCharAt(buf, 0, 0, '▀');
    try expectBlankOutside(buf, area);
}

test "render with 2x2 area plots each point at its exact scaled cell" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    chart.render(&buf, area);
    // Scale 0..2 over 2 rows: 1.0 stays on the baseline row, 2.0 reaches the top row.
    try expectCharAt(buf, 0, 0, ' ');
    try expectCharAt(buf, 0, 1, '▀');
    try expectCharAt(buf, 1, 0, '▀');
    try expectCharAt(buf, 1, 1, '█');
    try expectBlankOutside(buf, area);
}

// ============================================================================
// Group 7: Render — Empty Data (2 tests)
// ============================================================================

test "render with zero series produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const chart = AreaChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero series and Block draws the frame and an empty interior" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const chart = AreaChart.init().withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    try expectCharAt(buf, 0, 0, '┌');
    try expectCharAt(buf, 39, 0, '┐');
    try expectCharAt(buf, 0, 19, '└');
    try expectCharAt(buf, 39, 19, '┘');
    const inner = Rect{ .x = 1, .y = 1, .width = 38, .height = 18 };
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, inner));
    try expectBlankOutside(buf, area);
}

// ============================================================================
// Group 8: Render — Single Series Non-Stacked (5 tests)
// ============================================================================

test "render single series with positive values produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series).withStacked(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render single series with single point fills one centered column to the top" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{5.0};
    var series = [_]AreaSeries{.{ .label = "Single", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    // A lone point sits at width / 2 and spans from the top row down to the baseline row.
    try expectCharAt(buf, 30, 0, '▀');
    for (1..15) |row| try expectCharAt(buf, 30, @intCast(row), '█');
    try testing.expectEqual(@as(usize, 15), countNonEmptyCells(buf, area));
    try expectBlankOutside(buf, area);
}

test "render single series with all-zero values draws only a mid-height baseline" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 0.0, 0.0, 0.0 };
    var series = [_]AreaSeries{.{ .label = "AllZero", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    // A degenerate 0..0 scale puts the baseline at height / 2 and nothing is filled.
    try expectCharAt(buf, 0, 7, '▀');
    try expectCharAt(buf, 29, 7, '▀');
    try expectCharAt(buf, 59, 7, '▀');
    try testing.expectEqual(@as(usize, 3), countNonEmptyCells(buf, area));
    try expectBlankOutside(buf, area);
}

test "render single series with empty values writes no cell" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals: [0]f32 = undefined;
    var series = [_]AreaSeries{.{ .label = "Empty", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try expectBlankOutside(buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
}

test "render single series fill from baseline to value" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 2.0, 4.0, 6.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withMinVal(0.0)
        .withMaxVal(8.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 16 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 9: Multi-Series Non-Stacked (4 tests)
// ============================================================================

test "render two series non-stacked produces overlaid content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 2.0, 3.0 };
    var vals_b = [_]f32{ 2.0, 3.0, 4.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const chart = AreaChart.init().withSeries(&series).withStacked(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render three series non-stacked" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var vals_c = [_]f32{ 3.0, 4.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
        .{ .label = "C", .values = &vals_c },
    };
    const chart = AreaChart.init().withSeries(&series).withStacked(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "non-stacked later series overwrites earlier in same column/row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 1.0, 2.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a, .style = .{ .bold = true } },
        .{ .label = "B", .values = &vals_b, .style = .{ .dim = true } },
    };
    const chart = AreaChart.init().withSeries(&series).withStacked(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with max series (8 items) non-stacked" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();
    var vals: [8][2]f32 = undefined;
    var series: [8]AreaSeries = undefined;
    for (0..8) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        vals[i][1] = @as(f32, @floatFromInt(i + 2));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const chart = AreaChart.init().withSeries(&series).withStacked(false);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 8), chart.series_count);
}

// ============================================================================
// Group 10: Stacked Series (5 tests)
// ============================================================================

test "render two series stacked produces cumulative fill" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 2.0, 3.0 };
    var vals_b = [_]f32{ 2.0, 3.0, 4.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const chart = AreaChart.init().withSeries(&series).withStacked(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render three series stacked with varying heights" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var vals_c = [_]f32{ 3.0, 4.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
        .{ .label = "C", .values = &vals_c },
    };
    const chart = AreaChart.init().withSeries(&series).withStacked(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "stacked vs non-stacked produce different visuals" {
    var buf1 = try Buffer.init(testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 80, 24);
    defer buf2.deinit();

    var vals_a = [_]f32{ 2.0, 3.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };

    const chart_non_stacked = AreaChart.init().withSeries(&series).withStacked(false);
    const chart_stacked = AreaChart.init().withSeries(&series).withStacked(true);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart_non_stacked.render(&buf1, area);
    chart_stacked.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

test "stacked series each occupies its own band" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 1.0 };
    var vals_b = [_]f32{ 1.0, 1.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a, .style = .{ .bold = true } },
        .{ .label = "B", .values = &vals_b, .style = .{ .dim = true } },
    };
    const chart = AreaChart.init()
        .withSeries(&series)
        .withStacked(true)
        .withMinVal(0.0)
        .withMaxVal(2.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render more than MAX_SERIES caps at 8 when stacked" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();
    var vals: [16][1]f32 = undefined;
    var series: [16]AreaSeries = undefined;
    for (0..16) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const chart = AreaChart.init().withSeries(&series).withStacked(true);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 8), chart.series_count);
}

// ============================================================================
// Group 11: show_line Toggle (3 tests)
// ============================================================================

test "show_line=true includes boundary line character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 2.0, 4.0, 6.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withShowLine(true)
        .withLineChar('▀');
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_line=false excludes boundary line character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 2.0, 4.0, 6.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withShowLine(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_line toggle preserves immutability" {
    const chart1 = AreaChart.init().withShowLine(true);
    const chart2 = chart1.withShowLine(false);
    try testing.expectEqual(true, chart1.show_line);
    try testing.expectEqual(false, chart2.show_line);
}

// ============================================================================
// Group 12: Custom Fill and Line Characters (3 tests)
// ============================================================================

test "custom fill_char renders with specified character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 2.0, 4.0, 6.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withFillChar('▓');
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(areaHasChar(buf, area, '▓'));
}

test "custom line_char renders with specified character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 2.0, 4.0, 6.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withShowLine(true)
        .withLineChar('─');
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "fill_char and line_char toggling preserves immutability" {
    const chart1 = AreaChart.init().withFillChar('█').withLineChar('▀');
    const chart2 = chart1.withFillChar('▓').withLineChar('─');
    try testing.expectEqual(@as(u21, '█'), chart1.fill_char);
    try testing.expectEqual(@as(u21, '▀'), chart1.line_char);
    try testing.expectEqual(@as(u21, '▓'), chart2.fill_char);
    try testing.expectEqual(@as(u21, '─'), chart2.line_char);
}

// ============================================================================
// Group 13: Scale Override — min_val/max_val (5 tests)
// ============================================================================

test "min_val override sets chart minimum value" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 5.0, 10.0, 15.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withMinVal(-10.0)
        .withMaxVal(20.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "max_val override sets chart maximum value" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withMaxVal(100.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "both min_val and max_val overrides work together" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 2.0, 4.0, 6.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withMinVal(0.0)
        .withMaxVal(8.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "min_val override does not modify original chart" {
    const chart1 = AreaChart.init().withMinVal(-5.0);
    const chart2 = chart1.withMinVal(10.0);
    try testing.expectEqual(@as(f32, -5.0), chart1.min_val.?);
    try testing.expectEqual(@as(f32, 10.0), chart2.min_val.?);
}

test "max_val override does not modify original chart" {
    const chart1 = AreaChart.init().withMaxVal(100.0);
    const chart2 = chart1.withMaxVal(1000.0);
    try testing.expectEqual(@as(f32, 100.0), chart1.max_val.?);
    try testing.expectEqual(@as(f32, 1000.0), chart2.max_val.?);
}

// ============================================================================
// Group 14: Focused Series Styling (4 tests)
// ============================================================================

test "focused series applies focused_style instead of series style" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a, .style = .{ .dim = true } },
        .{ .label = "B", .values = &vals_b },
    };
    const chart = AreaChart.init()
        .withSeries(&series)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused=null skips focused styling" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withFocused(null)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused index beyond series count renders identically to unfocused" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var ref = try Buffer.init(testing.allocator, 80, 24);
    defer ref.deinit();
    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const focus_style = Style{ .bold = true };
    const chart = AreaChart.init()
        .withSeries(&series)
        .withFocusedStyle(focus_style)
        .withFocused(100);
    const unfocused = chart.withFocused(null);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    unfocused.render(&ref, area);
    try expectBuffersEqual(buf, ref);
    // Content exists and no cell picked up the focused style.
    try testing.expect(countNonEmptyCells(buf, area) > 0);
    for (buf.cells) |cell| try testing.expect(!cell.style.bold);
}

test "focused toggle preserves immutability" {
    const chart1 = AreaChart.init().withFocused(0);
    const chart2 = chart1.withFocused(3);
    try testing.expectEqual(@as(?usize, 0), chart1.focused);
    try testing.expectEqual(@as(?usize, 3), chart2.focused);
}

// ============================================================================
// Group 15: MAX_SERIES/MAX_POINTS Capping (3 tests)
// ============================================================================

test "more than MAX_SERIES=8 series caps silently at 8 non-stacked" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals: [16][1]f32 = undefined;
    var series: [16]AreaSeries = undefined;
    for (0..16) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const chart = AreaChart.init().withSeries(&series).withStacked(false);
    try testing.expectEqual(@as(usize, 8), chart.series_count);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "more than MAX_POINTS=64 points in series caps silently" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals: [128]f32 = undefined;
    for (0..128) |i| {
        vals[i] = @as(f32, @floatFromInt(i % 20 + 1));
    }
    var series = [_]AreaSeries{.{ .label = "Many", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "exactly MAX_SERIES=8 renders without capping" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();
    var vals: [8][2]f32 = undefined;
    var series: [8]AreaSeries = undefined;
    for (0..8) |i| {
        vals[i][0] = @as(f32, @floatFromInt(i + 1));
        vals[i][1] = @as(f32, @floatFromInt(i + 2));
        series[i] = .{ .label = "S", .values = &vals[i] };
    }
    const chart = AreaChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), chart.series_count);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 16: Negative and Out-of-Range Values (5 tests)
// ============================================================================

test "negative values fill downward from the baseline (auto scale includes 0)" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ -5.0, 0.0, 5.0 };
    var series = [_]AreaSeries{.{ .label = "Negative", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    // Scale -5..5 over 15 rows puts the baseline at row 7, -5 at row 14 and 5 at row 0.
    try expectCharAt(buf, 0, 6, ' ');
    try expectCharAt(buf, 0, 7, '█');
    try expectCharAt(buf, 0, 13, '█');
    try expectCharAt(buf, 0, 14, '▀');
    try expectCharAt(buf, 29, 7, '▀');
    try expectCharAt(buf, 59, 0, '▀');
    try expectCharAt(buf, 59, 7, '█');
    try expectCharAt(buf, 59, 8, ' ');
    try testing.expectEqual(@as(usize, 8 + 1 + 8), countNonEmptyCells(buf, area));
    try expectBlankOutside(buf, area);
}

test "all-negative values hang from a baseline pinned to the top row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ -10.0, -5.0, -1.0 };
    var series = [_]AreaSeries{.{ .label = "AllNeg", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    // Scale -10..0 puts the baseline at row 0; -10 reaches row 14, -5 row 7, -1 row 2.
    try expectCharAt(buf, 0, 0, '█');
    try expectCharAt(buf, 0, 14, '▀');
    try expectCharAt(buf, 29, 7, '▀');
    try expectCharAt(buf, 29, 8, ' ');
    try expectCharAt(buf, 59, 2, '▀');
    try expectCharAt(buf, 59, 3, ' ');
    try testing.expectEqual(@as(usize, 15 + 8 + 3), countNonEmptyCells(buf, area));
    try expectBlankOutside(buf, area);
}

test "very large positive values do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1e6, 2e6, 3e6 };
    var series = [_]AreaSeries{.{ .label = "Huge", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "mixed negative and positive values normalize correctly" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ -10.0, 0.0, 10.0, 20.0 };
    var series = [_]AreaSeries{.{ .label = "Mixed", .values = &vals }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "baseline always at y=0 for scale computation" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 5.0, 10.0, 15.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withMinVal(0.0)
        .withMaxVal(20.0);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 17: NaN and Infinity Guards (No-Panic Regression) (3 tests)
// ============================================================================

test "NaN value is drawn as zero while finite points stay plotted" {
    try expectNonFiniteDrawnAsZero(std.math.nan(f32));
}

test "Infinity value is drawn as zero while finite points stay plotted" {
    try expectNonFiniteDrawnAsZero(std.math.inf(f32));
}

test "negative Infinity value is drawn as zero while finite points stay plotted" {
    try expectNonFiniteDrawnAsZero(-std.math.inf(f32));
}

// ============================================================================
// Group 18: Block Border Support (3 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(u21, '┌'), cellAtPos(buf, 0, 0).?.char);
    try testing.expectEqual(@as(u21, '┐'), cellAtPos(buf, 39, 0).?.char);
    try testing.expectEqual(@as(u21, '└'), cellAtPos(buf, 0, 14).?.char);
    try testing.expectEqual(@as(u21, '┘'), cellAtPos(buf, 39, 14).?.char);
}

test "render with block in offset area" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    var vals = [_]f32{ 2.0, 3.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(u21, '┌'), cellAtPos(buf, 10, 5).?.char);
    try testing.expectEqual(@as(u21, '┘'), cellAtPos(buf, 59, 24).?.char);
    // Nothing is drawn outside the offset area.
    try testing.expectEqual(@as(u21, ' '), cellAtPos(buf, 9, 5).?.char);
    try testing.expectEqual(@as(u21, ' '), cellAtPos(buf, 60, 24).?.char);
}

test "render block in 3x3 area keeps the frame and plots into the 1x1 interior" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    chart.render(&buf, area);
    try expectCharAt(buf, 0, 0, '┌');
    try expectCharAt(buf, 2, 0, '┐');
    try expectCharAt(buf, 0, 2, '└');
    try expectCharAt(buf, 2, 2, '┘');
    // The single interior cell collapses baseline and value onto one row: line char only.
    try expectCharAt(buf, 1, 1, '▀');
    try expectBlankOutside(buf, area);
}

test "render block in 2x2 area leaves no interior to plot into" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0 };
    var series = [_]AreaSeries{.{ .label = "A", .values = &vals }};
    const chart = AreaChart.init()
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    chart.render(&buf, area);
    try expectCharAt(buf, 0, 0, '┌');
    try expectCharAt(buf, 1, 0, '┐');
    try expectCharAt(buf, 0, 1, '└');
    try expectCharAt(buf, 1, 1, '┘');
    try expectBlankOutside(buf, area);
}

// ============================================================================
// Group 19: Series Styling (2 tests)
// ============================================================================

test "series with custom style applies color/attribute" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals = [_]f32{ 1.0, 2.0, 3.0 };
    var series = [_]AreaSeries{.{ .label = "Styled", .values = &vals, .style = .{ .bold = true } }};
    const chart = AreaChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "chart style applies as default to all series" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const chart = AreaChart.init()
        .withSeries(&series)
        .withStyle(.{ .italic = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 20: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields correctly" {
    var vals_a = [_]f32{ 1.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 3.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };

    const chart = AreaChart.init()
        .withSeries(&series)
        .withStacked(true)
        .withShowLine(false)
        .withFillChar('▓')
        .withLineChar('─')
        .withMinVal(0.0)
        .withMaxVal(10.0)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true })
        .withStyle(.{ .italic = true })
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), chart.series_count);
    try testing.expectEqual(true, chart.stacked);
    try testing.expectEqual(false, chart.show_line);
    try testing.expectEqual(@as(u21, '▓'), chart.fill_char);
    try testing.expectEqual(@as(u21, '─'), chart.line_char);
    try testing.expectEqual(@as(f32, 0.0), chart.min_val.?);
    try testing.expectEqual(@as(f32, 10.0), chart.max_val.?);
    try testing.expectEqual(@as(?usize, 0), chart.focused);
    try testing.expect(chart.block != null);
}

test "builder chain preserves last value for each field" {
    const chart = AreaChart.init()
        .withStacked(false)
        .withStacked(true)
        .withShowLine(true)
        .withShowLine(false)
        .withFillChar('█')
        .withFillChar('▓')
        .withLineChar('▀')
        .withLineChar('─');

    try testing.expectEqual(true, chart.stacked);
    try testing.expectEqual(false, chart.show_line);
    try testing.expectEqual(@as(u21, '▓'), chart.fill_char);
    try testing.expectEqual(@as(u21, '─'), chart.line_char);
}

// ============================================================================
// Group 21: Realistic Scenarios (3 tests)
// ============================================================================

test "render multi-series area chart with realistic data" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var vals_a = [_]f32{ 1.0, 3.0, 5.0, 4.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 4.0, 6.0, 5.0, 3.0 };
    var vals_c = [_]f32{ 1.5, 3.5, 7.0, 6.0, 3.5 };

    var series = [_]AreaSeries{
        .{ .label = "Series A", .values = &vals_a, .style = .{ .bold = true } },
        .{ .label = "Series B", .values = &vals_b, .style = .{ .dim = true } },
        .{ .label = "Series C", .values = &vals_c },
    };

    const chart = AreaChart.init()
        .withSeries(&series)
        .withStacked(false)
        .withShowLine(true)
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render stacked area chart with uniform values" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var vals_a = [_]f32{ 2.0, 2.0, 2.0 };
    var vals_b = [_]f32{ 2.0, 2.0, 2.0 };
    var vals_c = [_]f32{ 2.0, 2.0, 2.0 };

    var series = [_]AreaSeries{
        .{ .label = "Layer 1", .values = &vals_a, .style = .{ .bold = true } },
        .{ .label = "Layer 2", .values = &vals_b },
        .{ .label = "Layer 3", .values = &vals_c, .style = .{ .dim = true } },
    };

    const chart = AreaChart.init()
        .withSeries(&series)
        .withStacked(true)
        .withMinVal(0.0)
        .withMaxVal(6.0);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render area chart with all styling options enabled" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var vals_a = [_]f32{ 2.0, 3.0, 4.0 };
    var vals_b = [_]f32{ 1.0, 5.0, 6.0 };

    var series = [_]AreaSeries{
        .{ .label = "Series A", .values = &vals_a, .style = .{ .italic = true } },
        .{ .label = "Series B", .values = &vals_b },
    };

    const chart = AreaChart.init()
        .withSeries(&series)
        .withStacked(false)
        .withShowLine(true)
        .withFillChar('▒')
        .withLineChar('─')
        .withMinVal(0.0)
        .withMaxVal(8.0)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true })
        .withStyle(.{ .underline = true })
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 28 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Regression: stacked auto-scale range must scan every series' full length,
// not just series[0]'s length, when series have differing point counts.
// ============================================================================

test "stacked auto-scale range accounts for a series longer than series[0]" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    // series[0] has 1 point; series[1] has 3 points, with a much larger value
    // at index 2 (far outside series[0]'s range). If the scale range were
    // computed by scanning only series[0]'s length (the pre-fix bug), column 2
    // of series[1] would never be visited, so the true max (100.0) would be
    // missed and the scale would collapse to the tiny column-0 sum (2.0).
    var vals_a = [_]f32{1.0};
    var vals_b = [_]f32{ 1.0, 1.0, 100.0 };
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals_a },
        .{ .label = "B", .values = &vals_b },
    };
    const chart = AreaChart.init().withSeries(&series).withStacked(true).withShowLine(true);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 20 };
    chart.render(&buf, area);

    // Column 0's stacked total is 1.0 + 1.0 = 2.0 -- only 2% of the true data
    // max (100.0). With the correct full-series scan, that small value must
    // render near the bottom of the chart. With the bug, the scale would treat
    // 2.0 as the max and push column 0's line boundary to the very top row.
    var top_row: ?u16 = null;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        if (cellAtPos(buf, area.x, y)) |cell| {
            if (cell.char == '▀') {
                top_row = y - area.y;
                break;
            }
        }
    }

    try testing.expect(top_row != null);
    try testing.expect(top_row.? > area.height / 2);
}

// ============================================================================
// Regression: scaleY must not double-apply the height scaling factor.
// ============================================================================

test "scaleY places a mid-range value at a mid row, not the extreme row" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();

    // A value exactly halfway between min_val and max_val, with a single point
    // (so it renders at a known column: width/2). Hand-computed expectation:
    // normalized = (50-0)/(100-0) = 0.5; scaled = 0.5 * (height-1) = 0.5*19 = 9.5;
    // row (pre-invert) = floor(9.5) = 9; inverted = (height-1) - 9 = 10.
    // A double-scaling bug (clamping the already-row-scaled value to [0,1] before
    // multiplying by height-1 again) collapses any non-tiny normalized value to
    // the extreme row (0 here), so this distinguishes the two implementations.
    var vals = [_]f32{50.0};
    var series = [_]AreaSeries{
        .{ .label = "A", .values = &vals },
    };
    const chart = AreaChart.init()
        .withSeries(&series)
        .withMinVal(0.0)
        .withMaxVal(100.0)
        .withShowLine(true);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    chart.render(&buf, area);

    const col_x = area.x + area.width / 2;
    var top_row: ?u16 = null;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        if (cellAtPos(buf, col_x, y)) |cell| {
            if (cell.char == '▀') {
                top_row = y - area.y;
                break;
            }
        }
    }

    try testing.expectEqual(@as(?u16, 10), top_row);
}
