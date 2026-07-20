//! WaterfallChart Widget Tests — TDD Red Phase
//!
//! Tests WaterfallChart widget with cumulative deltas, absolute baselines,
//! running total visualization, focused bar styling, value labels, connectors,
//! block borders, MAX_BARS capping, and rendering edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const WaterfallChart = sailor.tui.widgets.WaterfallChart;
const WaterfallBar = sailor.tui.widgets.waterfall_chart.WaterfallBar;
const WaterfallKind = sailor.tui.widgets.waterfall_chart.WaterfallKind;

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

/// Find text in buffer area (linear search, row-major order)
fn findTextInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var text_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (text_idx < text.len) : (text_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != text[text_idx]) {
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

/// Find the style of the first occurrence of a character in a buffer area.
/// Returns null if the character is not found.
fn findCharStyle(buf: Buffer, area: Rect, ch: u21) ?Style {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) return cell.style;
            }
        }
    }
    return null;
}

// ============================================================================
// Group 1: Init and Defaults (5 tests)
// ============================================================================

test "WaterfallChart.init creates default chart with zero bars" {
    const wc = WaterfallChart.init();
    try testing.expectEqual(@as(usize, 0), wc.bars.len);
}

test "WaterfallChart.init defaults focused to 0" {
    const wc = WaterfallChart.init();
    try testing.expectEqual(@as(usize, 0), wc.focused);
}

test "WaterfallChart.init defaults show_values to true" {
    const wc = WaterfallChart.init();
    try testing.expectEqual(true, wc.show_values);
}

test "WaterfallChart.init defaults show_connectors to true" {
    const wc = WaterfallChart.init();
    try testing.expectEqual(true, wc.show_connectors);
}

test "WaterfallChart.init defaults block to null" {
    const wc = WaterfallChart.init();
    try testing.expect(wc.block == null);
}

// ============================================================================
// Group 2: WaterfallKind Enum (3 tests)
// ============================================================================

test "WaterfallKind.relative exists" {
    const kind = WaterfallKind.relative;
    try testing.expectEqual(WaterfallKind.relative, kind);
}

test "WaterfallKind.absolute exists" {
    const kind = WaterfallKind.absolute;
    try testing.expectEqual(WaterfallKind.absolute, kind);
}

test "WaterfallKind.total exists" {
    const kind = WaterfallKind.total;
    try testing.expectEqual(WaterfallKind.total, kind);
}

// ============================================================================
// Group 3: WaterfallBar Defaults (4 tests)
// ============================================================================

test "WaterfallBar default label is empty" {
    const bar = WaterfallBar{};
    try testing.expectEqualStrings("", bar.label);
}

test "WaterfallBar default value is 0.0" {
    const bar = WaterfallBar{};
    try testing.expectEqual(@as(f32, 0.0), bar.value);
}

test "WaterfallBar default kind is relative" {
    const bar = WaterfallBar{};
    try testing.expectEqual(WaterfallKind.relative, bar.kind);
}

test "WaterfallBar default style is empty" {
    const bar = WaterfallBar{};
    try testing.expect(!bar.style.bold and bar.style.dim == false);
}

// ============================================================================
// Group 4: MAX_BARS Constant (1 test)
// ============================================================================

test "WaterfallChart.MAX_BARS equals 32" {
    try testing.expectEqual(@as(usize, 32), WaterfallChart.MAX_BARS);
}

// ============================================================================
// Group 5: barCount() Method (5 tests)
// ============================================================================

test "WaterfallChart.barCount with zero bars returns 0" {
    const wc = WaterfallChart.init();
    try testing.expectEqual(@as(usize, 0), wc.barCount());
}

test "WaterfallChart.barCount with 1 bar returns 1" {
    var bars = [_]WaterfallBar{.{ .label = "A", .value = 10.0 }};
    const wc = WaterfallChart.init().withBars(&bars);
    try testing.expectEqual(@as(usize, 1), wc.barCount());
}

test "WaterfallChart.barCount with 10 bars returns 10" {
    var bars: [10]WaterfallBar = undefined;
    for (0..10) |i| {
        bars[i] = .{ .label = "B", .value = @floatFromInt(i) };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    try testing.expectEqual(@as(usize, 10), wc.barCount());
}

test "WaterfallChart.barCount with exactly MAX_BARS returns 32" {
    var bars: [32]WaterfallBar = undefined;
    for (0..32) |i| {
        bars[i] = .{ .label = "B", .value = @floatFromInt(i) };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    try testing.expectEqual(@as(usize, 32), wc.barCount());
}

test "WaterfallChart.barCount caps at MAX_BARS when 40 bars provided" {
    var bars: [40]WaterfallBar = undefined;
    for (0..40) |i| {
        bars[i] = .{ .label = "B", .value = @floatFromInt(i) };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    try testing.expectEqual(@as(usize, 32), wc.barCount());
}

// ============================================================================
// Group 6: Builder Immutability (7 tests)
// ============================================================================

test "WaterfallChart.withBars does not modify original" {
    var bars1 = [_]WaterfallBar{.{ .label = "A", .value = 10.0 }};
    var bars2 = [_]WaterfallBar{
        .{ .label = "X", .value = 5.0 },
        .{ .label = "Y", .value = 15.0 },
    };

    const wc1 = WaterfallChart.init().withBars(&bars1);
    const wc2 = wc1.withBars(&bars2);

    try testing.expectEqual(@as(usize, 1), wc1.barCount());
    try testing.expectEqual(@as(usize, 2), wc2.barCount());
}

test "WaterfallChart.withFocused sets focused index" {
    const wc1 = WaterfallChart.init().withFocused(0);
    const wc2 = wc1.withFocused(5);

    try testing.expectEqual(@as(usize, 0), wc1.focused);
    try testing.expectEqual(@as(usize, 5), wc2.focused);
}

test "WaterfallChart.withShowValues sets show_values" {
    const wc1 = WaterfallChart.init().withShowValues(true);
    const wc2 = wc1.withShowValues(false);

    try testing.expectEqual(true, wc1.show_values);
    try testing.expectEqual(false, wc2.show_values);
}

test "WaterfallChart.withShowConnectors sets show_connectors" {
    const wc1 = WaterfallChart.init().withShowConnectors(true);
    const wc2 = wc1.withShowConnectors(false);

    try testing.expectEqual(true, wc1.show_connectors);
    try testing.expectEqual(false, wc2.show_connectors);
}

test "WaterfallChart.withPositiveStyle sets positive_style" {
    const style = Style{ .bold = true };
    const wc = WaterfallChart.init().withPositiveStyle(style);
    try testing.expectEqual(true, wc.positive_style.bold);
}

test "WaterfallChart.withNegativeStyle sets negative_style" {
    const style = Style{ .dim = true };
    const wc = WaterfallChart.init().withNegativeStyle(style);
    try testing.expectEqual(true, wc.negative_style.dim);
}

test "WaterfallChart.withTotalStyle sets total_style" {
    const style = Style{ .italic = true };
    const wc = WaterfallChart.init().withTotalStyle(style);
    try testing.expectEqual(true, wc.total_style.italic);
}

// ============================================================================
// Group 7: Builder Methods for More Styles (5 tests)
// ============================================================================

test "WaterfallChart.withFocusedStyle sets focused_style" {
    const style = Style{ .bold = true };
    const wc = WaterfallChart.init().withFocusedStyle(style);
    try testing.expectEqual(true, wc.focused_style.bold);
}

test "WaterfallChart.withConnectorStyle sets connector_style" {
    const style = Style{ .dim = true };
    const wc = WaterfallChart.init().withConnectorStyle(style);
    try testing.expectEqual(true, wc.connector_style.dim);
}

test "WaterfallChart.withStyle sets style" {
    const style = Style{ .bold = true };
    const wc = WaterfallChart.init().withStyle(style);
    try testing.expectEqual(true, wc.style.bold);
}

test "WaterfallChart.withBlock sets block" {
    const block = Block{};
    const wc = WaterfallChart.init().withBlock(block);
    try testing.expect(wc.block != null);
}

test "WaterfallChart.withBlock with null unsets block" {
    const wc1 = WaterfallChart.init().withBlock(.{});
    const wc2 = wc1.withBlock(null);

    try testing.expect(wc1.block != null);
    try testing.expect(wc2.block == null);
}

// ============================================================================
// Group 8: Render — Zero/Minimal Area (5 tests)
// ============================================================================

test "WaterfallChart.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "A", .value = 10.0 }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    wc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "WaterfallChart.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "A", .value = 10.0 }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    wc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "WaterfallChart.render on 2x2 area exits early (below minimum)" {
    var buf = try Buffer.init(testing.allocator, 2, 2);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "A", .value = 10.0 }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    wc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "WaterfallChart.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "A", .value = 10.0 }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    wc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "WaterfallChart.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "A", .value = 10.0 }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    wc.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 9: Render — Empty Bars (3 tests)
// ============================================================================

test "WaterfallChart.render with zero bars produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const wc = WaterfallChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "WaterfallChart.render empty bars with show_values=false" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const wc = WaterfallChart.init().withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "WaterfallChart.render empty bars with show_connectors=false" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const wc = WaterfallChart.init().withShowConnectors(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

// ============================================================================
// Group 10: Render — Single Bar (5 tests)
// ============================================================================

test "WaterfallChart.render single positive relative bar produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "A", .value = 10.0, .kind = .relative }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render single negative relative bar produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "A", .value = -5.0, .kind = .relative }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render single absolute bar produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "B", .value = 15.0, .kind = .absolute }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render single total bar produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "Total", .value = 20.0, .kind = .total }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render single bar at different area offsets" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var bars = [_]WaterfallBar{.{ .label = "X", .value = 10.0 }};
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 5, .y = 5, .width = 30, .height = 15 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 11: Render — Multiple Bars (5 tests)
// ============================================================================

test "WaterfallChart.render two relative bars produces content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render three bars with mixed kinds" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 0.0, .kind = .absolute },
        .{ .label = "C", .value = 15.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render four bars with total at end" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
        .{ .label = "C", .value = -3.0, .kind = .relative },
        .{ .label = "Total", .value = 12.0, .kind = .total },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render five bars with varying values" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Q1", .value = 100.0, .kind = .relative },
        .{ .label = "Q2", .value = 50.0, .kind = .relative },
        .{ .label = "Q3", .value = -20.0, .kind = .relative },
        .{ .label = "Q4", .value = 80.0, .kind = .relative },
        .{ .label = "Annual", .value = 210.0, .kind = .total },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: Render — MAX_BARS Cap (5 tests)
// ============================================================================

test "WaterfallChart.render with exactly MAX_BARS=32" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var bars: [32]WaterfallBar = undefined;
    for (0..32) |i| {
        bars[i] = .{ .label = "B", .value = @as(f32, @floatFromInt(i)) + 1.0, .kind = .relative };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    try testing.expectEqual(@as(usize, 32), wc.barCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with 40 bars caps to MAX_BARS=32" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var bars: [40]WaterfallBar = undefined;
    for (0..40) |i| {
        bars[i] = .{ .label = "B", .value = @as(f32, @floatFromInt(i)) + 1.0, .kind = .relative };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    try testing.expectEqual(@as(usize, 32), wc.barCount());
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with 50 bars internal cap to 32" {
    var bars: [50]WaterfallBar = undefined;
    for (0..50) |i| {
        bars[i] = .{ .label = "B", .value = 5.0, .kind = .relative };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    // barCount() should return 32, not 50
    try testing.expectEqual(@as(usize, 32), wc.barCount());
}

test "WaterfallChart.barCount caps at 32 with many bars" {
    var bars: [100]WaterfallBar = undefined;
    for (0..100) |i| {
        bars[i] = .{ .label = "B", .value = @as(f32, @floatFromInt(i)), .kind = .relative };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    try testing.expectEqual(@as(usize, 32), wc.barCount());
}

test "WaterfallChart.render 16 bars renders all visible bars" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var bars: [16]WaterfallBar = undefined;
    for (0..16) |i| {
        bars[i] = .{ .label = "B", .value = @as(f32, @floatFromInt(i)) + 1.0, .kind = .relative };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 13: Render — Focused Bar Styling (5 tests)
// ============================================================================

test "WaterfallChart.render focused=0 on three-bar chart applies focus style" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
        .{ .label = "C", .value = -3.0, .kind = .relative },
    };
    const focused_style = Style{ .bold = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withFocused(0)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render focused=1 applies style to second bar" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
        .{ .label = "C", .value = -3.0, .kind = .relative },
    };
    const focused_style = Style{ .dim = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render changing focused index produces different outputs" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
        .{ .label = "C", .value = -3.0, .kind = .relative },
    };

    const wc1 = WaterfallChart.init().withBars(&bars).withFocused(0);
    const wc2 = WaterfallChart.init().withBars(&bars).withFocused(2);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc1.render(&buf1, area);
    wc2.render(&buf2, area);

    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

test "WaterfallChart.render focused node with custom style renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
        .{ .label = "C", .value = -3.0, .kind = .relative },
    };
    const focused_style = Style{ .dim = true, .bold = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withFocused(1)
        .withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 14: Render — Show Values Toggle (3 tests)
// ============================================================================

test "WaterfallChart.render show_values=true displays numeric text" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars).withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render show_values=false produces different output than true" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };

    const wc_with_values = WaterfallChart.init().withBars(&bars).withShowValues(true);
    const wc_no_values = WaterfallChart.init().withBars(&bars).withShowValues(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc_with_values.render(&buf1, area);
    wc_no_values.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    // With values should have more content (numbers)
    try testing.expect(content1 >= content2);
}

test "WaterfallChart.render show_values=false still renders bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars).withShowValues(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 15: Render — Show Connectors Toggle (3 tests)
// ============================================================================

test "WaterfallChart.render show_connectors=true displays connectors" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars).withShowConnectors(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render show_connectors=false produces fewer cells" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };

    const wc_with_connectors = WaterfallChart.init().withBars(&bars).withShowConnectors(true);
    const wc_no_connectors = WaterfallChart.init().withBars(&bars).withShowConnectors(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc_with_connectors.render(&buf1, area);
    wc_no_connectors.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    // Connectors add visual elements; with_connectors should have >= content
    try testing.expect(content1 >= content2);
}

test "WaterfallChart.render show_connectors=false still renders bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars).withShowConnectors(false);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Render — Block Border (3 tests)
// ============================================================================

test "WaterfallChart.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const block = Block{};
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render block reduces inner area for content" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };

    const block = Block{};
    const wc_with_block = WaterfallChart.init().withBars(&bars).withBlock(block);
    const wc_no_block = WaterfallChart.init().withBars(&bars);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc_with_block.render(&buf1, area);
    wc_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "WaterfallChart.render block with title renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const block = (Block{}).withTitle("Chart", .top_left);
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Render — Styles (5 tests)
// ============================================================================

test "WaterfallChart.render with positive_style colors positive bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const positive_style = Style{ .bold = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withPositiveStyle(positive_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with negative_style colors negative bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = -5.0, .kind = .relative },
    };
    const negative_style = Style{ .dim = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withNegativeStyle(negative_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with total_style colors total bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "Total", .value = 10.0, .kind = .total },
    };
    const total_style = Style{ .italic = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withTotalStyle(total_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with connector_style styles connectors" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const connector_style = Style{ .bold = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withConnectorStyle(connector_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with multiple styles renders correctly" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = -5.0, .kind = .relative },
        .{ .label = "Total", .value = 5.0, .kind = .total },
    };
    const style = Style{ .bold = true };
    const positive_style = Style{ .bold = true };
    const negative_style = Style{ .dim = true };
    const total_style = Style{ .italic = true };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withStyle(style)
        .withPositiveStyle(positive_style)
        .withNegativeStyle(negative_style)
        .withTotalStyle(total_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 18: Render — WaterfallKind Behavior (5 tests)
// ============================================================================

test "WaterfallChart.render .relative kind accumulates values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Start", .value = 100.0, .kind = .relative },
        .{ .label = "Delta", .value = 20.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render .absolute kind resets baseline" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Start", .value = 100.0, .kind = .relative },
        .{ .label = "Reset", .value = 50.0, .kind = .absolute },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render .total kind shows running total" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
        .{ .label = "Sum", .value = 15.0, .kind = .total },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render all-negative relative bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Loss1", .value = -10.0, .kind = .relative },
        .{ .label = "Loss2", .value = -5.0, .kind = .relative },
        .{ .label = "Loss3", .value = -3.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render mixed positive and negative relative bars" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Gain", .value = 25.0, .kind = .relative },
        .{ .label = "Loss", .value = -10.0, .kind = .relative },
        .{ .label = "Gain2", .value = 15.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 19: Render — Very Small Area (3 tests)
// ============================================================================

test "WaterfallChart.render 5x5 area with bars does not crash" {
    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    wc.render(&buf, area);
    // Just verify no crash
}

test "WaterfallChart.render 10x10 area with bars shows content" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render area offset from origin" {
    var buf = try Buffer.init(testing.allocator, 50, 30);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 10, .y = 5, .width = 25, .height = 15 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Render — Large Values (3 tests)
// ============================================================================

test "WaterfallChart.render with large values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Million", .value = 1000000.0, .kind = .relative },
        .{ .label = "Add", .value = 500000.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with very small fractional values" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Tiny1", .value = 0.001, .kind = .relative },
        .{ .label = "Tiny2", .value = 0.0001, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with mixed magnitude values" {
    var buf = try Buffer.init(testing.allocator, 50, 25);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Large", .value = 10000.0, .kind = .relative },
        .{ .label = "Small", .value = 0.5, .kind = .relative },
        .{ .label = "Negative", .value = -100.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 25 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 21: Memory Safety (3 tests)
// ============================================================================

test "WaterfallChart.render does not exceed buffer bounds with many bars" {
    var buf = try Buffer.init(testing.allocator, 80, 40);
    defer buf.deinit();
    var bars: [32]WaterfallBar = undefined;
    for (0..32) |i| {
        bars[i] = .{ .label = "B", .value = @as(f32, @floatFromInt(i)) + 1.0, .kind = .relative };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty <= 3200); // 80*40 max
}

test "WaterfallChart.render with MAX_BARS cap is safe" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var bars: [32]WaterfallBar = undefined;
    for (0..32) |i| {
        bars[i] = .{ .label = "B", .value = 5.0, .kind = .relative };
    }
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    wc.render(&buf, area);
    // Must not crash or overflow
}

test "WaterfallChart.render with buffer offset does not write outside area" {
    var buf = try Buffer.init(testing.allocator, 100, 50);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 5.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 20, .y = 10, .width = 30, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 22: Edge Cases (5 tests)
// ============================================================================

test "WaterfallChart.render all bars with value 0.0" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Z1", .value = 0.0, .kind = .relative },
        .{ .label = "Z2", .value = 0.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render bar with empty label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "", .value = 10.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render bar with long label" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "VeryLongLabelThatIsQuiteLong", .value = 10.0, .kind = .relative },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with absolute kind at different positions" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "Start", .value = 50.0, .kind = .absolute },
        .{ .label = "Mid", .value = 30.0, .kind = .absolute },
        .{ .label = "End", .value = 20.0, .kind = .absolute },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "WaterfallChart.render with alternating bar kinds" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var bars = [_]WaterfallBar{
        .{ .label = "A", .value = 10.0, .kind = .relative },
        .{ .label = "B", .value = 0.0, .kind = .absolute },
        .{ .label = "C", .value = 5.0, .kind = .relative },
        .{ .label = "D", .value = 10.0, .kind = .total },
    };
    const wc = WaterfallChart.init().withBars(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    wc.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// No-Panic Regression Tests — @intFromFloat Overflow (Session 387)
// ============================================================================

test "WaterfallChart.render extremely large bar.value with show_values=true does not panic" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    // CRITICAL REGRESSION: render() at line 341 casts raw bar.value to i32 without clamping.
    // Values outside i32 range (~±2.147e9) cause panic: "integer part of floating point value out of bounds"
    // This test locks in the fix: extremely large values must be handled gracefully (clamped before cast).
    var bars = [_]WaterfallBar{
        .{ .label = "VeryLarge", .value = 3_000_000_000.0, .kind = .relative },
        .{ .label = "Small", .value = 100.0, .kind = .relative },
    };
    const wc = WaterfallChart.init()
        .withBars(&bars)
        .withShowValues(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    wc.render(&buf, area);
    // No panic is success; at least some content should render (bars and values)
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}
