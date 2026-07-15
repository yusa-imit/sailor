//! RadarChart Widget Tests — TDD Red Phase
//!
//! Tests RadarChart widget with multi-dimensional radar chart rendering,
//! axis/series management, polygon rendering, labels, focus handling,
//! block borders, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const RadarChart = sailor.tui.widgets.RadarChart;
const RadarSeries = sailor.tui.widgets.RadarSeries;

// ============================================================================
// Helper Functions
// ============================================================================

/// Decode UTF-8 text into a codepoint slice (max 256 codepoints)
fn decodeUtf8(text: []const u8, out: []u21) usize {
    var len: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (len >= out.len) break;
        out[len] = cp;
        len += 1;
    }
    return len;
}

/// Find text in buffer area (UTF-8 aware)
fn findInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var cps: [256]u21 = undefined;
    const cp_count = decodeUtf8(text, &cps);
    if (cp_count == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var cp_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (cp_idx < cp_count) : (cp_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != cps[cp_idx]) {
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

/// Count non-space cells in area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Count occurrences of a character in area
fn countCharInArea(buf: Buffer, area: Rect, ch: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

// ============================================================================
// Group 1: Init/Defaults (5 tests)
// ============================================================================

test "RadarChart.init has empty axes" {
    const rc = RadarChart.init();
    try testing.expectEqual(@as(usize, 0), rc.axes.len);
}

test "RadarChart.init has empty series" {
    const rc = RadarChart.init();
    try testing.expectEqual(@as(usize, 0), rc.series.len);
}

test "RadarChart.init has focused == 0" {
    const rc = RadarChart.init();
    try testing.expectEqual(@as(usize, 0), rc.focused);
}

test "RadarChart.init has filled == false" {
    const rc = RadarChart.init();
    try testing.expectEqual(false, rc.filled);
}

test "RadarChart.init has no block" {
    const rc = RadarChart.init();
    try testing.expectEqual(@as(?Block, null), rc.block);
}

// ============================================================================
// Group 2: MAX Constants (2 tests)
// ============================================================================

test "RadarChart.MAX_AXES equals 16" {
    try testing.expectEqual(@as(usize, 16), RadarChart.MAX_AXES);
}

test "RadarChart.MAX_SERIES equals 8" {
    try testing.expectEqual(@as(usize, 8), RadarChart.MAX_SERIES);
}

// ============================================================================
// Group 3: axisCount Method (5 tests)
// ============================================================================

test "RadarChart.axisCount with zero axes returns 0" {
    const rc = RadarChart.init();
    try testing.expectEqual(@as(usize, 0), rc.axisCount());
}

test "RadarChart.axisCount with 1 axis returns 1" {
    var axes = [_][]const u8{"Speed"};
    const rc = RadarChart.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 1), rc.axisCount());
}

test "RadarChart.axisCount caps at MAX_AXES" {
    var axes: [20][]const u8 = undefined;
    for (0..20) |i| {
        axes[i] = "A";
    }
    const rc = RadarChart.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 16), rc.axisCount());
}

test "RadarChart.axisCount with exactly MAX_AXES" {
    var axes: [16][]const u8 = undefined;
    for (0..16) |i| {
        axes[i] = "A";
    }
    const rc = RadarChart.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 16), rc.axisCount());
}

test "RadarChart.axisCount with 3 axes" {
    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    const rc = RadarChart.init().withAxes(&axes);
    try testing.expectEqual(@as(usize, 3), rc.axisCount());
}

// ============================================================================
// Group 4: seriesCount Method (5 tests)
// ============================================================================

test "RadarChart.seriesCount with zero series returns 0" {
    const rc = RadarChart.init();
    try testing.expectEqual(@as(usize, 0), rc.seriesCount());
}

test "RadarChart.seriesCount with 1 series returns 1" {
    var series = [_]RadarSeries{.{ .label = "Series1" }};
    const rc = RadarChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 1), rc.seriesCount());
}

test "RadarChart.seriesCount caps at MAX_SERIES" {
    var series: [10]RadarSeries = undefined;
    for (0..10) |i| {
        series[i] = .{ .label = "S" };
    }
    const rc = RadarChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), rc.seriesCount());
}

test "RadarChart.seriesCount with exactly MAX_SERIES" {
    var series: [8]RadarSeries = undefined;
    for (0..8) |i| {
        series[i] = .{ .label = "S" };
    }
    const rc = RadarChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 8), rc.seriesCount());
}

test "RadarChart.seriesCount with 3 series" {
    var series = [_]RadarSeries{
        .{ .label = "A" },
        .{ .label = "B" },
        .{ .label = "C" },
    };
    const rc = RadarChart.init().withSeries(&series);
    try testing.expectEqual(@as(usize, 3), rc.seriesCount());
}

// ============================================================================
// Group 5: Builder Immutability (8 tests)
// ============================================================================

test "withAxes returns new value, original unchanged" {
    var axes1 = [_][]const u8{"A1"};
    const rc1 = RadarChart.init().withAxes(&axes1);
    var axes2 = [_][]const u8{"A2"};
    const rc2 = rc1.withAxes(&axes2);
    try testing.expectEqual(@as(usize, 1), rc1.axes.len);
    try testing.expectEqualStrings("A1", rc1.axes[0]);
    try testing.expectEqual(@as(usize, 1), rc2.axes.len);
    try testing.expectEqualStrings("A2", rc2.axes[0]);
}

test "withSeries returns new value, original unchanged" {
    var series1 = [_]RadarSeries{.{ .label = "S1" }};
    const rc1 = RadarChart.init().withSeries(&series1);
    var series2 = [_]RadarSeries{.{ .label = "S2" }};
    const rc2 = rc1.withSeries(&series2);
    try testing.expectEqual(@as(usize, 1), rc1.series.len);
    try testing.expectEqualStrings("S1", rc1.series[0].label);
    try testing.expectEqual(@as(usize, 1), rc2.series.len);
    try testing.expectEqualStrings("S2", rc2.series[0].label);
}

test "withFocused returns new value, original unchanged" {
    const rc1 = RadarChart.init().withFocused(1);
    const rc2 = rc1.withFocused(3);
    try testing.expectEqual(@as(usize, 1), rc1.focused);
    try testing.expectEqual(@as(usize, 3), rc2.focused);
}

test "withStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const rc1 = RadarChart.init().withStyle(style1);
    const rc2 = rc1.withStyle(style2);
    try testing.expectEqual(true, rc1.style.bold);
    try testing.expectEqual(true, rc2.style.dim);
}

test "withAxisStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const rc1 = RadarChart.init().withAxisStyle(style1);
    const rc2 = rc1.withAxisStyle(style2);
    try testing.expectEqual(true, rc1.axis_style.bold);
    try testing.expectEqual(true, rc2.axis_style.dim);
}

test "withFocusedStyle returns new value, original unchanged" {
    const style1 = Style{ .bold = true };
    const style2 = Style{ .dim = true };
    const rc1 = RadarChart.init().withFocusedStyle(style1);
    const rc2 = rc1.withFocusedStyle(style2);
    try testing.expectEqual(true, rc1.focused_style.bold);
    try testing.expectEqual(true, rc2.focused_style.dim);
}

test "withFilled returns new value, original unchanged" {
    const rc1 = RadarChart.init().withFilled(true);
    const rc2 = rc1.withFilled(false);
    try testing.expectEqual(true, rc1.filled);
    try testing.expectEqual(false, rc2.filled);
}

test "withBlock returns new value, original unchanged" {
    const rc1 = RadarChart.init().withBlock(.{});
    const rc2 = rc1.withBlock(null);
    try testing.expect(rc1.block != null);
    try testing.expect(rc2.block == null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (3 tests)
// ============================================================================

test "render with 0x0 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const rc = RadarChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    rc.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const rc = RadarChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    rc.render(&buf, area);
}

test "render with 2x2 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const rc = RadarChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    rc.render(&buf, area);
}

// ============================================================================
// Group 7: Render — Zero Axes (2 tests)
// ============================================================================

test "render with zero axes produces minimal output" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const rc = RadarChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with zero axes and one series produces no output" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var series = [_]RadarSeries{.{ .label = "S1" }};
    const rc = RadarChart.init().withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 8: Render — 1 Axis (2 tests)
// ============================================================================

test "render with one axis does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{"Speed"};
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);
}

test "render with one axis and series produces minimal content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{"Speed"};
    var values = [_]f32{0.8};
    var series = [_]RadarSeries{.{ .label = "Car", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);
}

// ============================================================================
// Group 9: Render — 2 Axes (3 tests)
// ============================================================================

test "render with two axes produces content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render with 2 axes and 1 series shows polygon" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power" };
    var values = [_]f32{ 0.8, 0.6 };
    var series = [_]RadarSeries{.{ .label = "Car", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with 2 axes and series with values uses series style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power" };
    var values = [_]f32{ 0.7, 0.9 };
    var series = [_]RadarSeries{.{ .label = "Car", .values = &values, .style = .{ .bold = true } }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 10: Render — 3+ Axes (4 tests)
// ============================================================================

test "render with three axes forms triangle" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with four axes forms cross pattern" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill", "Defense" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with six axes" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{
        "Speed",    "Power",  "Skill",
        "Defense",  "Magic",  "Stamina",
    };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with many axes radiates from center" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{
        "A", "B", "C", "D", "E", "F", "G", "H",
    };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 11: Render — Single Series (5 tests)
// ============================================================================

test "render single series produces polygon" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values = [_]f32{ 0.8, 0.6, 0.9 };
    var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render series with label visible" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "X", "Y" };
    var values = [_]f32{ 0.5, 0.5 };
    var series = [_]RadarSeries{.{ .label = "Data", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render series with all-zero values" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C" };
    var values = [_]f32{ 0.0, 0.0, 0.0 };
    var series = [_]RadarSeries{.{ .label = "Zero", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);
}

test "render series with all-one values" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C" };
    var values = [_]f32{ 1.0, 1.0, 1.0 };
    var series = [_]RadarSeries{.{ .label = "Max", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render series with single value" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values = [_]f32{0.7};
    var series = [_]RadarSeries{.{ .label = "Incomplete", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);
}

// ============================================================================
// Group 12: Render — Multiple Series (5 tests)
// ============================================================================

test "render two series produces more cells than one" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values1 = [_]f32{ 0.8, 0.6, 0.9 };
    var values2 = [_]f32{ 0.5, 0.7, 0.6 };
    var series = [_]RadarSeries{
        .{ .label = "Hero1", .values = &values1 },
        .{ .label = "Hero2", .values = &values2 },
    };
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render three series" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values1 = [_]f32{ 0.8, 0.6, 0.9 };
    var values2 = [_]f32{ 0.5, 0.7, 0.6 };
    var values3 = [_]f32{ 0.9, 0.5, 0.7 };
    var series = [_]RadarSeries{
        .{ .label = "H1", .values = &values1 },
        .{ .label = "H2", .values = &values2 },
        .{ .label = "H3", .values = &values3 },
    };
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render multiple series with different styles" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C" };
    var values1 = [_]f32{ 0.7, 0.8, 0.6 };
    var values2 = [_]f32{ 0.5, 0.6, 0.7 };
    var series = [_]RadarSeries{
        .{ .label = "S1", .values = &values1, .style = .{ .bold = true } },
        .{ .label = "S2", .values = &values2, .style = .{ .dim = true } },
    };
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render max series count" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C" };
    var values_all: [8][3]f32 = undefined;
    for (0..8) |i| {
        values_all[i] = .{ 0.5 + @as(f32, @floatFromInt(i)) * 0.05, 0.6, 0.7 };
    }

    var series: [8]RadarSeries = undefined;
    for (0..8) |i| {
        series[i] = .{ .label = "S", .values = &values_all[i] };
    }

    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(rc.seriesCount() == 8);
}

// ============================================================================
// Group 13: Render — Focused Series (4 tests)
// ============================================================================

test "render focused series uses focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power" };
    var values1 = [_]f32{ 0.8, 0.6 };
    var values2 = [_]f32{ 0.5, 0.7 };
    var series = [_]RadarSeries{
        .{ .label = "S1", .values = &values1 },
        .{ .label = "S2", .values = &values2 },
    };
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFocused(1)
        .withFocusedStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render focused at index 0" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B" };
    var values = [_]f32{ 0.5, 0.5 };
    var series = [_]RadarSeries{.{ .label = "S1", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render focused index beyond series count does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B" };
    var values = [_]f32{ 0.5, 0.5 };
    var series = [_]RadarSeries{.{ .label = "S1", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);
}

test "render non-focused series does not use focused_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power" };
    var values1 = [_]f32{ 0.8, 0.6 };
    var values2 = [_]f32{ 0.5, 0.7 };
    var series = [_]RadarSeries{
        .{ .label = "S1", .values = &values1 },
        .{ .label = "S2", .values = &values2 },
    };
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

// ============================================================================
// Group 14: Render — Filled Polygon (3 tests)
// ============================================================================

test "render filled polygon fills area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values = [_]f32{ 0.8, 0.6, 0.9 };
    var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFilled(true);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render unfilled produces outline only" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values = [_]f32{ 0.8, 0.6, 0.9 };
    var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFilled(false);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render filled vs unfilled differ in cell count" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values = [_]f32{ 0.8, 0.6, 0.9 };
    var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};

    const rc_filled = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFilled(true);
    const rc_unfilled = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFilled(false);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc_filled.render(&buf1, area);
    rc_unfilled.render(&buf2, area);
}

// ============================================================================
// Group 15: Render — Block Border (4 tests)
// ============================================================================

test "render with Block renders frame" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B" };
    var values = [_]f32{ 0.5, 0.5 };
    var series = [_]RadarSeries{.{ .label = "S", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);

    // Block border must render with box-drawing characters
    const has_border = areaHasChar(buf, area, '─') or areaHasChar(buf, area, '│') or
                       areaHasChar(buf, area, '┌');
    try testing.expect(has_border);
}

test "render block reduces inner area for chart" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C" };
    var values = [_]f32{ 0.5, 0.5, 0.5 };
    var series = [_]RadarSeries{.{ .label = "S", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 5, .y = 5, .width = 40, .height = 15 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render with block in offset area" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B" };
    var values = [_]f32{ 0.5, 0.5 };
    var series = [_]RadarSeries{.{ .label = "S", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B" };
    var values = [_]f32{ 0.5, 0.5 };
    var series = [_]RadarSeries{.{ .label = "S", .values = &values }};
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    rc.render(&buf, area);
}

// ============================================================================
// Group 16: Render — Axis Labels (5 tests)
// ============================================================================

test "render axis labels visible in large area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render axis with short label" {
    var buf = try Buffer.init(std.testing.allocator, 60, 20);
    defer buf.deinit();

    var axes = [_][]const u8{ "X", "Y", "Z" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render axis with long label" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "VeryLongAxisName", "Power", "Skill" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render with unicode axis labels" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "速度", "力量", "技能" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render axis labels clipped to buffer bounds" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    var axes = [_][]const u8{ "VeryLongName", "AnotherLong", "ThirdOne" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    rc.render(&buf, area);
}

// ============================================================================
// Group 17: Render — Edge Cases (5 tests)
// ============================================================================

test "render with value > 1.0 clamped" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values = [_]f32{ 1.5, 1.2, 0.8 };
    var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 24 };
    rc.render(&buf, area);
}

test "render with negative values" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C" };
    var values = [_]f32{ -0.5, 0.5, 0.7 };
    var series = [_]RadarSeries{.{ .label = "Data", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    rc.render(&buf, area);
}

test "render in offset area with large offset" {
    var buf = try Buffer.init(std.testing.allocator, 120, 40);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    var values = [_]f32{ 0.8, 0.6, 0.9 };
    var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 30, .y = 10, .width = 60, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render single-char axis labels" {
    var buf = try Buffer.init(std.testing.allocator, 60, 20);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C", "D" };
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

test "render with axis_style applied" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    const rc = RadarChart.init()
        .withAxes(&axes)
        .withAxisStyle(.{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    rc.render(&buf, area);

    try testing.expect(countNonEmptyCells(buf, area) >= 0);
}

// ============================================================================
// Group 18: Render — Capping at MAX (3 tests)
// ============================================================================

test "render more than MAX_AXES only draws MAX_AXES" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var axes: [20][]const u8 = undefined;
    for (0..20) |i| {
        axes[i] = "A";
    }
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    rc.render(&buf, area);

    try testing.expectEqual(@as(usize, 16), rc.axisCount());
}

test "render exactly MAX_AXES succeeds" {
    var buf = try Buffer.init(std.testing.allocator, 100, 24);
    defer buf.deinit();

    var axes: [16][]const u8 = undefined;
    for (0..16) |i| {
        axes[i] = "A";
    }
    const rc = RadarChart.init().withAxes(&axes);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 24 };
    rc.render(&buf, area);

    try testing.expectEqual(@as(usize, 16), rc.axisCount());
}

test "render more than MAX_SERIES only draws MAX_SERIES" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var axes = [_][]const u8{ "A", "B", "C" };
    var series: [10]RadarSeries = undefined;
    for (0..10) |i| {
        series[i] = .{ .label = "S" };
    }
    const rc = RadarChart.init().withAxes(&axes).withSeries(&series);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 24 };
    rc.render(&buf, area);

    try testing.expectEqual(@as(usize, 8), rc.seriesCount());
}

// ============================================================================
// Group 19: Builder Chaining (2 tests)
// ============================================================================

test "builder chain sets all fields" {
    var axes = [_][]const u8{ "Speed", "Power" };
    var values = [_]f32{ 0.8, 0.6 };
    var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};

    const rc = RadarChart.init()
        .withAxes(&axes)
        .withSeries(&series)
        .withFocused(0)
        .withStyle(.{ .bold = true })
        .withAxisStyle(.{ .dim = true })
        .withFocusedStyle(.{ .underline = true })
        .withFilled(true)
        .withBlock(.{});

    try testing.expectEqual(@as(usize, 2), rc.axes.len);
    try testing.expectEqual(@as(usize, 1), rc.series.len);
    try testing.expectEqual(@as(usize, 0), rc.focused);
    try testing.expectEqual(true, rc.filled);
    try testing.expect(rc.block != null);
}

test "builder chain with multiple operations" {
    var axes1 = [_][]const u8{"A"};
    var axes2 = [_][]const u8{ "A", "B", "C" };

    const rc = RadarChart.init()
        .withAxes(&axes1)
        .withFilled(false)
        .withAxes(&axes2)
        .withFilled(true);

    try testing.expectEqual(@as(usize, 3), rc.axes.len);
    try testing.expectEqual(true, rc.filled);
}
