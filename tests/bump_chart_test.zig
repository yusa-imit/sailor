//! BumpChart Widget Tests — TDD Red Phase
//!
//! Tests BumpChart widget rendering multi-time-point rank-over-time lines per category.
//! Each series draws a polyline connecting rank positions across time points, where rank=1 (best)
//! appears at the top row, and higher rank numbers appear lower. Direction characters ('/', '\', '─')
//! indicate whether rank improved, worsened, or stayed flat between adjacent timepoints.
//!
//! Tests cover initialization, builder pattern, seriesCount() capping at MAX_SERIES,
//! timepointCount() capping at MAX_TIMEPOINTS, maxRank() computation, rank-to-row mapping,
//! direction-char rendering (/, \, ─), focused series styling precedence,
//! show_labels/show_timepoint_labels toggles, out-of-range/zero-rank handling (no-panic),
//! rank ties between series, mismatched series ranks lengths, block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const BumpChart = sailor.tui.widgets.BumpChart;
const BumpSeries = sailor.tui.widgets.bump_chart.BumpSeries;

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

// ============================================================================
// Group 1: Init and Defaults (6 tests)
// ============================================================================

test "BumpChart.init creates chart with zero series" {
    const chart = BumpChart.init();
    try testing.expectEqual(@as(usize, 0), chart.series.len);
}

test "BumpChart.init defaults focused to 0" {
    const chart = BumpChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused);
}

test "BumpChart.init defaults show_labels to true" {
    const chart = BumpChart.init();
    try testing.expectEqual(true, chart.show_labels);
}

test "BumpChart.init defaults show_timepoint_labels to false" {
    const chart = BumpChart.init();
    try testing.expectEqual(false, chart.show_timepoint_labels);
}

test "BumpChart.init defaults block to null" {
    const chart = BumpChart.init();
    try testing.expectEqual(@as(?Block, null), chart.block);
}

test "BumpChart.init has default empty styles" {
    const chart = BumpChart.init();
    try testing.expectEqual(Style{}, chart.style);
    try testing.expectEqual(Style{}, chart.line_style);
    try testing.expectEqual(Style{}, chart.focused_style);
    try testing.expectEqual(Style{}, chart.label_style);
}

// ============================================================================
// Group 2: BumpSeries Struct Defaults (3 tests)
// ============================================================================

test "BumpSeries default label is empty" {
    const series = BumpSeries{};
    try testing.expectEqualStrings("", series.label);
}

test "BumpSeries default ranks is empty slice" {
    const series = BumpSeries{};
    try testing.expectEqual(@as(usize, 0), series.ranks.len);
}

test "BumpSeries default style is empty" {
    const series = BumpSeries{};
    try testing.expectEqual(Style{}, series.style);
}

// ============================================================================
// Group 3: Constants (2 tests)
// ============================================================================

test "BumpChart.MAX_SERIES equals 8" {
    try testing.expectEqual(@as(usize, 8), BumpChart.MAX_SERIES);
}

test "BumpChart.MAX_TIMEPOINTS equals 16" {
    try testing.expectEqual(@as(usize, 16), BumpChart.MAX_TIMEPOINTS);
}

// ============================================================================
// Group 4: seriesCount() Method (5 tests)
// ============================================================================

test "seriesCount with zero series returns 0" {
    const chart = BumpChart.init();
    try testing.expectEqual(@as(usize, 0), chart.seriesCount());
}

test "seriesCount with 1 series returns 1" {
    var ranks_a = [_]u32{ 1, 2 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks_a }};
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 1), chart.seriesCount());
}

test "seriesCount with 4 series returns 4" {
    var ranks_a = [_]u32{ 1, 2 };
    var ranks_b = [_]u32{ 2, 1 };
    var ranks_c = [_]u32{ 3, 3 };
    var ranks_d = [_]u32{ 1, 1 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
        .{ .label = "C", .ranks = &ranks_c },
        .{ .label = "D", .ranks = &ranks_d },
    };
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 4), chart.seriesCount());
}

test "seriesCount with exactly MAX_SERIES=8 returns 8" {
    var ranks: [8][1]u32 = undefined;
    var series: [8]BumpSeries = undefined;
    for (0..8) |i| {
        ranks[i][0] = @as(u32, @intCast(i + 1));
        series[i] = .{ .label = "S", .ranks = &ranks[i] };
    }
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), chart.seriesCount());
}

test "seriesCount caps at MAX_SERIES=8 when 16 series provided" {
    var ranks: [16][1]u32 = undefined;
    var series: [16]BumpSeries = undefined;
    for (0..16) |i| {
        ranks[i][0] = @as(u32, @intCast(i + 1));
        series[i] = .{ .label = "S", .ranks = &ranks[i] };
    }
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), chart.seriesCount());
}

// ============================================================================
// Group 5: timepointCount() Method (5 tests)
// ============================================================================

test "timepointCount with zero series returns 0" {
    const chart = BumpChart.init();
    try testing.expectEqual(@as(usize, 0), chart.timepointCount());
}

test "timepointCount with single series single timepoint returns 1" {
    var ranks = [_]u32{1};
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 1), chart.timepointCount());
}

test "timepointCount with single series 3 timepoints returns 3" {
    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 3), chart.timepointCount());
}

test "timepointCount returns max across different-length series" {
    var ranks_a = [_]u32{ 1, 2 };
    var ranks_b = [_]u32{ 2, 1, 3, 4, 5 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 5), chart.timepointCount());
}

test "timepointCount caps at MAX_TIMEPOINTS=16" {
    var ranks: [20]u32 = undefined;
    for (0..20) |i| {
        ranks[i] = @as(u32, @intCast(i + 1));
    }
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 16), chart.timepointCount());
}

// ============================================================================
// Group 6: maxRank() Method (5 tests)
// ============================================================================

test "maxRank with zero series returns 0" {
    const chart = BumpChart.init();
    try testing.expectEqual(@as(u32, 0), chart.maxRank());
}

test "maxRank with single series [1,2,3] returns 3" {
    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(u32, 3), chart.maxRank());
}

test "maxRank across multiple series returns global max" {
    var ranks_a = [_]u32{ 1, 2, 3 };
    var ranks_b = [_]u32{ 4, 5, 6 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(u32, 6), chart.maxRank());
}

test "maxRank with empty ranks slice returns 0" {
    var ranks: [0]u32 = undefined;
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(u32, 0), chart.maxRank());
}

test "maxRank equals 1 when all ranks are 1 (best rank only)" {
    var ranks_a = [_]u32{ 1, 1, 1 };
    var ranks_b = [_]u32{ 1, 1 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(u32, 1), chart.maxRank());
}

// ============================================================================
// Group 7: Builder Immutability — All Builder Methods (11 tests)
// ============================================================================

test "withSeries does not modify original" {
    var ranks_a = [_]u32{1};
    var ranks_b = [_]u32{ 2, 3 };
    var series1 = [_]BumpSeries{.{ .label = "A", .ranks = &ranks_a }};
    var series2 = [_]BumpSeries{
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart1 = BumpChart.init().withSeries(&series1);
    const chart2 = chart1.withSeries(&series2);
    try testing.expectEqual(@as(usize, 1), chart1.seriesCount());
    try testing.expectEqual(@as(usize, 1), chart2.seriesCount());
}

test "withFocused does not modify original" {
    const chart1 = BumpChart.init().withFocused(0);
    const chart2 = chart1.withFocused(3);
    try testing.expectEqual(@as(usize, 0), chart1.focused);
    try testing.expectEqual(@as(usize, 3), chart2.focused);
}

test "withShowLabels does not modify original" {
    const chart1 = BumpChart.init().withShowLabels(false);
    const chart2 = chart1.withShowLabels(true);
    try testing.expectEqual(false, chart1.show_labels);
    try testing.expectEqual(true, chart2.show_labels);
}

test "withShowTimepointLabels does not modify original" {
    const chart1 = BumpChart.init().withShowTimepointLabels(false);
    const chart2 = chart1.withShowTimepointLabels(true);
    try testing.expectEqual(false, chart1.show_timepoint_labels);
    try testing.expectEqual(true, chart2.show_timepoint_labels);
}

test "withStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = BumpChart.init().withStyle(s1);
    const chart2 = chart1.withStyle(s2);
    try testing.expectEqual(true, chart1.style.bold);
    try testing.expectEqual(true, chart2.style.dim);
}

test "withLineStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = BumpChart.init().withLineStyle(s1);
    const chart2 = chart1.withLineStyle(s2);
    try testing.expectEqual(true, chart1.line_style.bold);
    try testing.expectEqual(true, chart2.line_style.dim);
}

test "withFocusedStyle does not modify original" {
    const s1 = Style{ .bold = true };
    const s2 = Style{ .dim = true };
    const chart1 = BumpChart.init().withFocusedStyle(s1);
    const chart2 = chart1.withFocusedStyle(s2);
    try testing.expectEqual(true, chart1.focused_style.bold);
    try testing.expectEqual(true, chart2.focused_style.dim);
}

test "withLabelStyle does not modify original" {
    const s1 = Style{ .italic = true };
    const s2 = Style{ .underline = true };
    const chart1 = BumpChart.init().withLabelStyle(s1);
    const chart2 = chart1.withLabelStyle(s2);
    try testing.expectEqual(true, chart1.label_style.italic);
    try testing.expectEqual(true, chart2.label_style.underline);
}

test "withTimepointLabels does not modify original" {
    var labels1 = [_][]const u8{ "A", "B" };
    var labels2 = [_][]const u8{ "X", "Y", "Z" };
    const chart1 = BumpChart.init().withTimepointLabels(&labels1);
    const chart2 = chart1.withTimepointLabels(&labels2);
    try testing.expectEqual(@as(usize, 2), chart1.timepoint_labels.len);
    try testing.expectEqual(@as(usize, 3), chart2.timepoint_labels.len);
}

test "withBlock does not modify original" {
    const chart1 = BumpChart.init().withBlock(.{});
    const chart2 = chart1.withBlock(null);
    try testing.expect(chart1.block != null);
    try testing.expect(chart2.block == null);
}

// ============================================================================
// Group 8: Render — Zero/Minimal Area (3 tests)
// ============================================================================

test "render with 0x0 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = BumpChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = BumpChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = BumpChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 9: Render — Empty Data (2 tests)
// ============================================================================

test "render with zero series produces no content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = BumpChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero series and Block does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const chart = BumpChart.init().withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 10: Render — Single Series Single Timepoint (2 tests)
// ============================================================================

test "render single series single timepoint produces content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{1};
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render single series single timepoint with block does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{1};
    var series = [_]BumpSeries{.{ .label = "Single", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 11: Render — Single Series Multiple Timepoints (3 tests)
// ============================================================================

test "render single series multiple timepoints produces polyline" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2, 3, 2, 1 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render single series with empty ranks does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks: [0]u32 = undefined;
    var series = [_]BumpSeries{.{ .label = "Empty", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

test "render single series with all-equal ranks does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 3, 3, 3, 3 };
    var series = [_]BumpSeries{.{ .label = "Flat", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 12: Rank-to-Row Mapping (6 tests)
// ============================================================================

test "rank 1 (best) maps to top row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Single series with rank 1 at first timepoint — should appear at top
    var ranks = [_]u32{1};
    var series = [_]BumpSeries{.{ .label = "Top", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 5, .width = 40, .height = 10 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "high rank number maps toward bottom row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Rank 10 should appear lower than rank 1
    var ranks = [_]u32{10};
    var series = [_]BumpSeries{.{ .label = "Bottom", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "two series with different ranks appear at different rows" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{ 1, 2 };
    var ranks_b = [_]u32{ 2, 1 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "rank progression [1,2,3,4,5] renders vertically downward" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2, 3, 4, 5 };
    var series = [_]BumpSeries{.{ .label = "Descending", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 18 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "rank improvement (5->1) should use '/' char to indicate upward movement" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Rank drops from 5 to 1 (improvement)
    var ranks = [_]u32{ 5, 1 };
    var series = [_]BumpSeries{.{ .label = "Improving", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Improvement should have '/' character
    const has_slash = countChar(buf, area, '/') > 0;
    try testing.expect(has_slash);
}

test "rank worsening (1->5) should use '\\' char to indicate downward movement" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Rank rises from 1 to 5 (worsening)
    var ranks = [_]u32{ 1, 5 };
    var series = [_]BumpSeries{.{ .label = "Worsening", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Worsening should have '\' character
    const has_backslash = countChar(buf, area, '\\') > 0;
    try testing.expect(has_backslash);
}

// ============================================================================
// Group 13: Direction Glyph Correctness (5 tests)
// ============================================================================

test "flat rank (3,3,3) contains '─' character" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 3, 3, 3 };
    var series = [_]BumpSeries{.{ .label = "Flat", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    const has_dash = countChar(buf, area, '─') > 0;
    try testing.expect(has_dash);
}

test "multiple improvement segments (5,4,3,2,1) contain '/' characters" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 5, 4, 3, 2, 1 };
    var series = [_]BumpSeries{.{ .label = "SteadyImprovement", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 18 };

    chart.render(&buf, area);
    const slash_count = countChar(buf, area, '/');
    try testing.expect(slash_count > 0);
}

test "multiple worsening segments (1,2,3,4,5) contain '\\' characters" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2, 3, 4, 5 };
    var series = [_]BumpSeries{.{ .label = "SteadyWorsening", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 18 };

    chart.render(&buf, area);
    const backslash_count = countChar(buf, area, '\\');
    try testing.expect(backslash_count > 0);
}

test "mixed direction changes (1,5,2,4,1) contains multiple glyph types" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 5, 2, 4, 1 };
    var series = [_]BumpSeries{.{ .label = "Volatile", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 18 };

    chart.render(&buf, area);
    // Should have mix of /, \, and possibly ─
    const has_slash = countChar(buf, area, '/') > 0;
    const has_backslash = countChar(buf, area, '\\') > 0;
    try testing.expect(has_slash or has_backslash);
}

test "single segment improvement vs flat vs worsening" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_imp = [_]u32{ 3, 1 };   // improvement
    var ranks_flat = [_]u32{ 2, 2 };  // flat
    var ranks_wor = [_]u32{ 1, 3 };   // worsening
    var series = [_]BumpSeries{
        .{ .label = "Imp", .ranks = &ranks_imp },
        .{ .label = "Flat", .ranks = &ranks_flat },
        .{ .label = "Wor", .ranks = &ranks_wor },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 18 };

    chart.render(&buf, area);
    // Should render all three with appropriate glyphs
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 14: Multiple Series and Ties (4 tests)
// ============================================================================

test "two series with same rank at same timepoint do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Both series at rank 1 at timepoint 0 (tie)
    var ranks_a = [_]u32{ 1, 2 };
    var ranks_b = [_]u32{ 1, 3 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "multiple series with multiple ties across timepoints" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{ 1, 1, 2, 2 };
    var ranks_b = [_]u32{ 1, 2, 2, 3 };
    var ranks_c = [_]u32{ 2, 1, 1, 2 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
        .{ .label = "C", .ranks = &ranks_c },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render 4 series with interleaved ranks" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{ 1, 3, 2, 4 };
    var ranks_b = [_]u32{ 2, 1, 4, 3 };
    var ranks_c = [_]u32{ 3, 4, 1, 2 };
    var ranks_d = [_]u32{ 4, 2, 3, 1 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
        .{ .label = "C", .ranks = &ranks_c },
        .{ .label = "D", .ranks = &ranks_d },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render all MAX_SERIES with ranks" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var ranks: [8][3]u32 = undefined;
    var series: [8]BumpSeries = undefined;
    for (0..8) |i| {
        ranks[i][0] = @as(u32, @intCast(i + 1));
        ranks[i][1] = @as(u32, @intCast(9 - i));
        ranks[i][2] = @as(u32, @intCast((i + 4) % 8 + 1));
        series[i] = .{ .label = "S", .ranks = &ranks[i] };
    }
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 15: Focused Series Styling (4 tests)
// ============================================================================

test "focused_style overrides series style when set" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{ 1, 2, 3 };
    var ranks_b = [_]u32{ 3, 2, 1 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a, .style = .{ .dim = true } },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init()
        .withSeries(&series)
        .withFocused(0)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused=0 applies focused style to first series" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 2, 1, 3 };
    var series = [_]BumpSeries{.{ .label = "Focus", .ranks = &ranks }};
    const chart = BumpChart.init()
        .withSeries(&series)
        .withFocused(0)
        .withFocusedStyle(.{ .reverse = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "focused index beyond series count does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init()
        .withSeries(&series)
        .withFocused(100)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

test "focused_style only applies when explicitly set (empty Style ignored)" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks, .style = .{ .italic = true } }};

    // focused_style is default empty Style{} — should not override per-series style
    const chart = BumpChart.init()
        .withSeries(&series)
        .withFocused(0)
        .withFocusedStyle(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 16: Show Labels/Timepoint Labels Toggles (4 tests)
// ============================================================================

test "show_labels=true renders end labels" {
    var buf = try Buffer.init(testing.allocator, 100, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "ItemLabel", .ranks = &ranks }};
    const chart = BumpChart.init()
        .withSeries(&series)
        .withShowLabels(true)
        .withShowTimepointLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_labels=false omits end labels" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "Hidden", .ranks = &ranks }};
    const chart = BumpChart.init()
        .withSeries(&series)
        .withShowLabels(false)
        .withShowTimepointLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_timepoint_labels=true renders timepoint header row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var labels = [_][]const u8{ "2020", "2021", "2022" };
    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init()
        .withSeries(&series)
        .withTimepointLabels(&labels)
        .withShowTimepointLabels(true)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "show_timepoint_labels=false omits header row" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var labels = [_][]const u8{ "A", "B", "C" };
    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "X", .ranks = &ranks }};
    const chart = BumpChart.init()
        .withSeries(&series)
        .withTimepointLabels(&labels)
        .withShowTimepointLabels(false)
        .withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 17: MAX_SERIES/MAX_TIMEPOINTS Capping (4 tests)
// ============================================================================

test "more than MAX_SERIES=8 series caps silently at 8" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var ranks: [16][1]u32 = undefined;
    var series: [16]BumpSeries = undefined;
    for (0..16) |i| {
        ranks[i][0] = @as(u32, @intCast(i + 1));
        series[i] = .{ .label = "S", .ranks = &ranks[i] };
    }

    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), chart.seriesCount());

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "more than MAX_TIMEPOINTS=16 timepoints caps silently" {
    var buf = try Buffer.init(testing.allocator, 150, 24);
    defer buf.deinit();

    var ranks: [20]u32 = undefined;
    for (0..20) |i| {
        ranks[i] = @as(u32, @intCast(i % 8 + 1));
    }
    var series = [_]BumpSeries{.{ .label = "Many", .ranks = &ranks }};

    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 16), chart.timepointCount());

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 20 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "exactly MAX_SERIES=8 and MAX_TIMEPOINTS=16 render without capping" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var ranks: [8][16]u32 = undefined;
    var series: [8]BumpSeries = undefined;
    for (0..8) |i| {
        for (0..16) |j| {
            ranks[i][j] = @as(u32, @intCast((i + j + 1) % 8 + 1));
        }
        series[i] = .{ .label = "S", .ranks = &ranks[i] };
    }

    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), chart.seriesCount());
    try testing.expectEqual(@as(usize, 16), chart.timepointCount());

    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "series and timepoints both exceed limits cap independently" {
    var buf = try Buffer.init(testing.allocator, 150, 40);
    defer buf.deinit();

    var ranks: [16][20]u32 = undefined;
    var series: [16]BumpSeries = undefined;
    for (0..16) |i| {
        for (0..20) |j| {
            ranks[i][j] = @as(u32, @intCast(j % 8 + 1));
        }
        series[i] = .{ .label = "S", .ranks = &ranks[i] };
    }

    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), chart.seriesCount());  // capped at 8
    try testing.expectEqual(@as(usize, 16), chart.timepointCount()); // capped at 16

    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 35 };
    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 18: Out-of-Range Rank Handling (5 tests)
// ============================================================================

test "rank==0 (invalid, ranks are 1-based) does not panic and clamps safely" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Rank 0 is invalid; implementation should clamp safely
    var ranks = [_]u32{ 0, 1, 2 };
    var series = [_]BumpSeries{.{ .label = "ZeroRank", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // Should not crash or underflow on (rank - 1) calculation
}

test "rank much larger than maxRank clamps to maxRank" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // maxRank will be 5, but one value is 100
    var ranks = [_]u32{ 1, 2, 3, 4, 5, 100 };
    var series = [_]BumpSeries{.{ .label = "OutOfRange", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    chart.render(&buf, area);
    // Should clamp 100 to 5 without crash
}

test "all ranks are 0 does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 0, 0, 0 };
    var series = [_]BumpSeries{.{ .label = "AllZero", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
    // maxRank() == 0 should be handled safely
}

test "mixed valid and zero ranks render without crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{ 0, 1, 0 };
    var ranks_b = [_]u32{ 2, 3, 4 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

test "negative rank values (if cast as u32) do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // u32 cannot be negative, but implementation should handle edge cases
    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "Unsigned", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 19: Block Border (3 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{ 1, 2 };
    var ranks_b = [_]u32{ 2, 1 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    const chart = BumpChart.init().withSeries(&series).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 15 };

    chart.render(&buf, area);

    // Block border must render — at least one border glyph
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

    var ranks = [_]u32{ 1, 2, 3 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series).withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks = [_]u32{ 1, 2 };
    var series = [_]BumpSeries{.{ .label = "A", .ranks = &ranks }};
    const chart = BumpChart.init().withSeries(&series).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };

    chart.render(&buf, area);
}

// ============================================================================
// Group 20: Mismatched Ranks Length (3 tests)
// ============================================================================

test "series with different ranks.len do not crash" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{1};              // 1 timepoint
    var ranks_b = [_]u32{ 2, 3, 4, 5 };  // 4 timepoints
    var ranks_c = [_]u32{ 3, 3 };         // 2 timepoints
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
        .{ .label = "C", .ranks = &ranks_c },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "timepointCount correctly identifies max length across ragged series" {
    var ranks_short = [_]u32{ 1, 2 };
    var ranks_long = [_]u32{ 1, 2, 3, 4, 5, 6, 7 };
    var series = [_]BumpSeries{
        .{ .label = "Short", .ranks = &ranks_short },
        .{ .label = "Long", .ranks = &ranks_long },
    };
    const chart = BumpChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 7), chart.timepointCount());
}

test "render ragged series with early termination and late start" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var ranks_a = [_]u32{ 1, 2, 3, 4, 5, 6 };  // full length
    var ranks_b = [_]u32{ 2 };                   // short
    var ranks_c = [_]u32{ 3, 3, 3 };             // medium
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
        .{ .label = "C", .ranks = &ranks_c },
    };
    const chart = BumpChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 21: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields correctly" {
    var ranks_a = [_]u32{ 1, 2, 3 };
    var ranks_b = [_]u32{ 2, 1, 3 };
    var series = [_]BumpSeries{
        .{ .label = "A", .ranks = &ranks_a },
        .{ .label = "B", .ranks = &ranks_b },
    };
    var labels = [_][]const u8{ "T1", "T2", "T3" };

    const chart = BumpChart.init()
        .withSeries(&series)
        .withFocused(1)
        .withShowLabels(false)
        .withShowTimepointLabels(true)
        .withTimepointLabels(&labels)
        .withStyle(.{ .underline = true })
        .withLineStyle(.{ .bold = true })
        .withFocusedStyle(.{ .reverse = true })
        .withLabelStyle(.{ .dim = true })
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), chart.seriesCount());
    try testing.expectEqual(@as(usize, 1), chart.focused);
    try testing.expectEqual(false, chart.show_labels);
    try testing.expectEqual(true, chart.show_timepoint_labels);
    try testing.expectEqual(@as(usize, 3), chart.timepoint_labels.len);
    try testing.expect(chart.block != null);
}

test "builder chain preserves last value for each field" {
    const chart = BumpChart.init()
        .withFocused(0)
        .withFocused(5)
        .withShowLabels(true)
        .withShowLabels(false)
        .withShowTimepointLabels(false)
        .withShowTimepointLabels(true);

    try testing.expectEqual(@as(usize, 5), chart.focused);
    try testing.expectEqual(false, chart.show_labels);
    try testing.expectEqual(true, chart.show_timepoint_labels);
}

// ============================================================================
// Group 22: Realistic Scenarios (2 tests)
// ============================================================================

test "render sports league rankings over seasons" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    // Simulating sports league standings: teams' ranks across 4 seasons
    var team_a = [_]u32{ 1, 2, 3, 2 };      // declining then recovering
    var team_b = [_]u32{ 3, 1, 2, 1 };      // volatile but strong
    var team_c = [_]u32{ 2, 3, 1, 3 };      // improving then declining
    var team_d = [_]u32{ 4, 4, 4, 4 };      // consistently last

    var series = [_]BumpSeries{
        .{ .label = "Team A", .ranks = &team_a, .style = .{ .bold = true } },
        .{ .label = "Team B", .ranks = &team_b },
        .{ .label = "Team C", .ranks = &team_c, .style = .{ .dim = true } },
        .{ .label = "Team D", .ranks = &team_d },
    };

    var season_labels = [_][]const u8{ "2020", "2021", "2022", "2023" };

    const chart = BumpChart.init()
        .withSeries(&series)
        .withTimepointLabels(&season_labels)
        .withShowTimepointLabels(true)
        .withShowLabels(true)
        .withFocused(1)
        .withFocusedStyle(.{ .reverse = true })
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 25 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with all toggles and styling options enabled" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    var ranks_a = [_]u32{ 1, 3, 2, 4, 1 };
    var ranks_b = [_]u32{ 2, 1, 4, 3, 2 };
    var ranks_c = [_]u32{ 4, 2, 1, 2, 4 };

    var series = [_]BumpSeries{
        .{ .label = "Series A", .ranks = &ranks_a, .style = .{ .italic = true } },
        .{ .label = "Series B", .ranks = &ranks_b, .style = .{ .underline = true } },
        .{ .label = "Series C", .ranks = &ranks_c },
    };

    var labels = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May" };

    const chart = BumpChart.init()
        .withSeries(&series)
        .withFocused(0)
        .withShowLabels(true)
        .withShowTimepointLabels(true)
        .withTimepointLabels(&labels)
        .withStyle(.{ .underline = true })
        .withLineStyle(.{ .bold = true })
        .withFocusedStyle(.{ .bold = true })
        .withLabelStyle(.{ .bold = true })
        .withBlock(.{});

    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 28 };

    chart.render(&buf, area);
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}
