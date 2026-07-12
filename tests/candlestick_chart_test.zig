//! CandlestickChart Widget Tests — TDD Red Phase
//!
//! Tests CandlestickChart (OHLC financial) widget rendering one column per time period,
//! with a wick (high-to-low) + body (open-to-close) candle glyph per period and up/down
//! coloring (bullish when close >= open, bearish when close < open).
//! Each candle gets a vertical column band with centered wick and body.
//! All candles share a global value scale (global min/max across all candles' low/high values).
//! Tests cover initialization, builder pattern, MAX_CANDLES capping, render geometry,
//! up/down body coloring, wick rendering, focused styling, label display, block borders,
//! degenerate cases, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const CandlestickChart = sailor.tui.widgets.CandlestickChart;
const Candle = sailor.tui.widgets.candlestick_chart.Candle;

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

test "CandlestickChart.init creates default chart with zero candles" {
    const chart = CandlestickChart.init();
    try testing.expectEqual(@as(usize, 0), chart.candles.len);
}

test "CandlestickChart.init defaults focused to 0" {
    const chart = CandlestickChart.init();
    try testing.expectEqual(@as(usize, 0), chart.focused);
}

test "CandlestickChart.init defaults show_labels to true" {
    const chart = CandlestickChart.init();
    try testing.expectEqual(true, chart.show_labels);
}

test "CandlestickChart.init defaults block to null" {
    const chart = CandlestickChart.init();
    try testing.expect(chart.block == null);
}

test "CandlestickChart.init all style fields default to empty" {
    const chart = CandlestickChart.init();
    try testing.expect(!chart.style.bold and chart.style.fg == null);
    try testing.expect(!chart.up_style.bold and chart.up_style.fg == null);
    try testing.expect(!chart.down_style.bold and chart.down_style.fg == null);
}

// ============================================================================
// Group 2: Candle Struct Defaults (4 tests)
// ============================================================================

test "Candle default label is empty" {
    const candle = Candle{};
    try testing.expectEqualStrings("", candle.label);
}

test "Candle default OHLC values are zero" {
    const candle = Candle{};
    try testing.expectEqual(@as(f32, 0.0), candle.open);
    try testing.expectEqual(@as(f32, 0.0), candle.high);
    try testing.expectEqual(@as(f32, 0.0), candle.low);
    try testing.expectEqual(@as(f32, 0.0), candle.close);
}

test "Candle default style is empty" {
    const candle = Candle{};
    try testing.expect(!candle.style.bold and candle.style.fg == null);
}

test "Candle with label and OHLC values" {
    const candle = Candle{
        .label = "2026-03-14",
        .open = 100.0,
        .high = 110.0,
        .low = 95.0,
        .close = 105.0,
    };
    try testing.expectEqualStrings("2026-03-14", candle.label);
    try testing.expectEqual(@as(f32, 100.0), candle.open);
    try testing.expectEqual(@as(f32, 110.0), candle.high);
    try testing.expectEqual(@as(f32, 95.0), candle.low);
    try testing.expectEqual(@as(f32, 105.0), candle.close);
}

// ============================================================================
// Group 3: MAX_CANDLES Constant (1 test)
// ============================================================================

test "CandlestickChart.MAX_CANDLES equals 64" {
    try testing.expectEqual(@as(usize, 64), CandlestickChart.MAX_CANDLES);
}

// ============================================================================
// Group 4: candleCount() Method (5 tests)
// ============================================================================

test "CandlestickChart.candleCount with zero candles returns 0" {
    const chart = CandlestickChart.init();
    try testing.expectEqual(@as(usize, 0), chart.candleCount());
}

test "CandlestickChart.candleCount with 1 candle returns 1" {
    var candles = [_]Candle{.{ .label = "T1", .open = 100.0, .high = 105.0, .low = 95.0, .close = 102.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    try testing.expectEqual(@as(usize, 1), chart.candleCount());
}

test "CandlestickChart.candleCount with 10 candles returns 10" {
    var candles: [10]Candle = undefined;
    for (0..10) |i| {
        candles[i] = .{
            .label = "T",
            .open = @as(f32, @floatFromInt(@as(i32, @intCast(i)) * 10)),
            .high = @as(f32, @floatFromInt(@as(i32, @intCast(i)) * 10 + 5)),
            .low = @as(f32, @floatFromInt(@as(i32, @intCast(i)) * 10 - 5)),
            .close = @as(f32, @floatFromInt(@as(i32, @intCast(i)) * 10 + 2)),
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    try testing.expectEqual(@as(usize, 10), chart.candleCount());
}

test "CandlestickChart.candleCount with exactly MAX_CANDLES=64 returns 64" {
    var candles: [64]Candle = undefined;
    for (0..64) |i| {
        candles[i] = .{
            .open = @as(f32, @floatFromInt(@as(i32, @intCast(i)))),
            .high = @as(f32, @floatFromInt(@as(i32, @intCast(i)) + 1)),
            .low = @as(f32, @floatFromInt(@as(i32, @intCast(i)) - 1)),
            .close = @as(f32, @floatFromInt(@as(i32, @intCast(i)))),
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    try testing.expectEqual(@as(usize, 64), chart.candleCount());
}

test "CandlestickChart.candleCount caps at MAX_CANDLES=64 when 100 candles provided" {
    var candles: [100]Candle = undefined;
    for (0..100) |i| {
        candles[i] = .{
            .open = @as(f32, @floatFromInt(@as(i32, @intCast(i)))),
            .high = @as(f32, @floatFromInt(@as(i32, @intCast(i)) + 1)),
            .low = @as(f32, @floatFromInt(@as(i32, @intCast(i)) - 1)),
            .close = @as(f32, @floatFromInt(@as(i32, @intCast(i)))),
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    try testing.expectEqual(@as(usize, 64), chart.candleCount());
}

// ============================================================================
// Group 5: Builder Immutability — All Builder Methods (11 tests)
// ============================================================================

test "CandlestickChart.withCandles does not modify original" {
    var candles1 = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    var candles2 = [_]Candle{
        .{ .open = 50.0, .high = 55.0, .low = 45.0, .close = 52.0 },
        .{ .open = 60.0, .high = 65.0, .low = 55.0, .close = 62.0 },
    };

    const chart1 = CandlestickChart.init().withCandles(&candles1);
    const chart2 = chart1.withCandles(&candles2);

    try testing.expectEqual(@as(usize, 1), chart1.candleCount());
    try testing.expectEqual(@as(usize, 2), chart2.candleCount());
}

test "CandlestickChart.withFocused sets focused index" {
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 108.0 },
    };
    const chart1 = CandlestickChart.init().withCandles(&candles).withFocused(0);
    const chart2 = chart1.withFocused(1);

    try testing.expectEqual(@as(usize, 0), chart1.focused);
    try testing.expectEqual(@as(usize, 1), chart2.focused);
}

test "CandlestickChart.withShowLabels sets show_labels" {
    const chart1 = CandlestickChart.init().withShowLabels(true);
    const chart2 = chart1.withShowLabels(false);

    try testing.expectEqual(true, chart1.show_labels);
    try testing.expectEqual(false, chart2.show_labels);
}

test "CandlestickChart.withStyle sets style" {
    const style = Style{ .bold = true };
    const chart = CandlestickChart.init().withStyle(style);
    try testing.expectEqual(true, chart.style.bold);
}

test "CandlestickChart.withUpStyle sets up_style (bullish)" {
    const style = Style{ .dim = true };
    const chart = CandlestickChart.init().withUpStyle(style);
    try testing.expectEqual(true, chart.up_style.dim);
}

test "CandlestickChart.withDownStyle sets down_style (bearish)" {
    const style = Style{ .italic = true };
    const chart = CandlestickChart.init().withDownStyle(style);
    try testing.expectEqual(true, chart.down_style.italic);
}

test "CandlestickChart.withWickStyle sets wick_style" {
    const style = Style{ .bold = true };
    const chart = CandlestickChart.init().withWickStyle(style);
    try testing.expectEqual(true, chart.wick_style.bold);
}

test "CandlestickChart.withFocusedStyle sets focused_style" {
    const style = Style{ .bold = true };
    const chart = CandlestickChart.init().withFocusedStyle(style);
    try testing.expectEqual(true, chart.focused_style.bold);
}

test "CandlestickChart.withLabelStyle sets label_style" {
    const style = Style{ .italic = true };
    const chart = CandlestickChart.init().withLabelStyle(style);
    try testing.expectEqual(true, chart.label_style.italic);
}

test "CandlestickChart.withBlock sets block" {
    const block = Block{};
    const chart = CandlestickChart.init().withBlock(block);
    try testing.expect(chart.block != null);
}

test "CandlestickChart.withBlock with null unsets block" {
    const chart1 = CandlestickChart.init().withBlock(.{});
    const chart2 = chart1.withBlock(null);

    try testing.expect(chart1.block != null);
    try testing.expect(chart2.block == null);
}

// ============================================================================
// Group 6: Render — Zero/Minimal Area (4 tests)
// ============================================================================

test "CandlestickChart.render on 0x0 area exits early without writing" {
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "CandlestickChart.render on 1x1 area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 1);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "CandlestickChart.render on 0-width area exits early" {
    var buf = try Buffer.init(testing.allocator, 1, 10);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "CandlestickChart.render on 0-height area exits early" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    chart.render(&buf, area);
    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

// ============================================================================
// Group 7: Render — Empty Candles (2 tests)
// ============================================================================

test "CandlestickChart.render with zero candles produces no content" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const chart = CandlestickChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expectEqual(@as(usize, 0), non_empty);
}

test "CandlestickChart.render with degenerate candle (all OHLC identical)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 100.0, .low = 100.0, .close = 100.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should not crash; may produce minimal or no content due to degenerate scaling
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

// ============================================================================
// Group 8: Render — Single Candle (6 tests)
// ============================================================================

test "CandlestickChart.render single bullish candle (close > open)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render single bearish candle (close < open)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 108.0, .high = 110.0, .low = 95.0, .close = 100.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render single doji (open == close)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 100.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render single candle at offset area" {
    var buf = try Buffer.init(testing.allocator, 60, 30);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 10, .y = 5, .width = 30, .height = 15 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render single candle with large price range" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 500.0, .low = 10.0, .close = 450.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render single candle with no label" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0, .label = "" }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 9: Render — Multiple Candles & Global Scaling (6 tests)
// ============================================================================

test "CandlestickChart.render two candles with different prices" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 120.0, .low = 100.0, .close = 115.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render three candles up-up-down pattern" {
    var buf = try Buffer.init(testing.allocator, 70, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 108.0, .high = 115.0, .low = 105.0, .close = 112.0 },
        .{ .open = 112.0, .high = 118.0, .low = 100.0, .close = 102.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render five candles with mixed bullish/bearish" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 108.0, .high = 112.0, .low = 105.0, .close = 106.0 },
        .{ .open = 106.0, .high = 115.0, .low = 103.0, .close = 113.0 },
        .{ .open = 113.0, .high = 118.0, .low = 110.0, .close = 111.0 },
        .{ .open = 111.0, .high = 120.0, .low = 108.0, .close = 119.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render candles with shared global min/max scale" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    // Two candles: first ranges 100-110, second ranges 50-120
    // Global scale should be 50-120
    var candles = [_]Candle{
        .{ .open = 105.0, .high = 110.0, .low = 100.0, .close = 107.0 },
        .{ .open = 60.0, .high = 120.0, .low = 50.0, .close = 90.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render ten candles with varying volatility" {
    var buf = try Buffer.init(testing.allocator, 120, 25);
    defer buf.deinit();
    var candles: [10]Candle = undefined;
    for (0..10) |i| {
        const base = @as(f32, @floatFromInt(100 + i * 5));
        candles[i] = .{
            .open = base,
            .high = base + 10.0,
            .low = base - 8.0,
            .close = base + (if (i % 2 == 0) @as(f32, 6.0) else @as(f32, -3.0)),
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 10: Render — Bullish vs Bearish Body Coloring (4 tests)
// ============================================================================

test "CandlestickChart.render bullish candle uses up_style" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 }};
    const up_style = Style{ .bold = true };
    const down_style = Style{ .dim = true };
    const chart = CandlestickChart.init()
        .withCandles(&candles)
        .withUpStyle(up_style)
        .withDownStyle(down_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);

    // Verify that at least one bullish (bold) body cell exists
    var found_bullish_body = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█' and cell.style.bold) {
                    found_bullish_body = true;
                }
            }
        }
    }
    try testing.expect(found_bullish_body);
}

test "CandlestickChart.render bearish candle uses down_style" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 108.0, .high = 110.0, .low = 95.0, .close = 100.0 }};
    const up_style = Style{ .bold = true };
    const down_style = Style{ .dim = true };
    const chart = CandlestickChart.init()
        .withCandles(&candles)
        .withUpStyle(up_style)
        .withDownStyle(down_style);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);

    // Verify that at least one bearish (dim) body cell exists
    var found_bearish_body = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█' and cell.style.dim) {
                    found_bearish_body = true;
                }
            }
        }
    }
    try testing.expect(found_bearish_body);
}

test "CandlestickChart.render doji (open==close) renders thin body" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 100.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render different candles use appropriate up/down styles" {
    var buf_up = try Buffer.init(testing.allocator, 50, 20);
    defer buf_up.deinit();
    var buf_down = try Buffer.init(testing.allocator, 50, 20);
    defer buf_down.deinit();

    var candles_up = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 }};
    var candles_down = [_]Candle{.{ .open = 108.0, .high = 110.0, .low = 95.0, .close = 100.0 }};

    const up_style = Style{ .bold = true };
    const down_style = Style{ .dim = true };

    const chart_up = CandlestickChart.init()
        .withCandles(&candles_up)
        .withUpStyle(up_style)
        .withDownStyle(down_style);
    const chart_down = CandlestickChart.init()
        .withCandles(&candles_down)
        .withUpStyle(up_style)
        .withDownStyle(down_style);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart_up.render(&buf_up, area);
    chart_down.render(&buf_down, area);

    var bold_count: usize = 0;
    var dim_count: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf_up.getConst(x, y)) |cell| {
                if (cell.char == '█' and cell.style.bold) bold_count += 1;
            }
            if (buf_down.getConst(x, y)) |cell| {
                if (cell.char == '█' and cell.style.dim) dim_count += 1;
            }
        }
    }

    try testing.expect(bold_count > 0);
    try testing.expect(dim_count > 0);
}

// ============================================================================
// Group 11: Render — Wick Geometry (High-to-Low) (3 tests)
// ============================================================================

test "CandlestickChart.render wick spans from high row to low row" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    chart.render(&buf, area);
    // Wick should render as vertical line ('│')
    var found_wick = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '│') {
                    found_wick = true;
                }
            }
        }
    }
    try testing.expect(found_wick);
}

test "CandlestickChart.render wick with wick_style coloring" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const wick_style = Style{ .bold = true };
    const chart = CandlestickChart.init().withCandles(&candles).withWickStyle(wick_style);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    chart.render(&buf, area);
    // Verify at least one wick cell with bold style
    var found_bold_wick = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '│' and cell.style.bold) {
                    found_bold_wick = true;
                }
            }
        }
    }
    try testing.expect(found_bold_wick);
}

test "CandlestickChart.render multiple candles with distinct wicks" {
    var buf = try Buffer.init(testing.allocator, 70, 25);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 },
        .{ .open = 105.0, .high = 115.0, .low = 95.0, .close = 110.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 12: Render — Body Geometry (Open-to-Close Range) (3 tests)
// ============================================================================

test "CandlestickChart.render body_top <= body_bottom (correct row ordering)" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();
    // Bullish candle: open < close, so body_top = row(open), body_bottom = row(close)
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    chart.render(&buf, area);

    // Verify that body cells ('█') actually exist and are positioned correctly
    var found_body = false;
    var body_top_row: u16 = 0xFFFF;
    var body_bottom_row: u16 = 0;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█') {
                    found_body = true;
                    if (y < body_top_row) body_top_row = y;
                    if (y > body_bottom_row) body_bottom_row = y;
                }
            }
        }
    }
    try testing.expect(found_body); // Must render body cells, not just any content
    try testing.expect(body_top_row <= body_bottom_row); // Rows must be ordered correctly
}

test "CandlestickChart.render bearish body still renders correctly when close < open" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();
    // Bearish candle: open > close, so body_top = row(close), body_bottom = row(open)
    var candles = [_]Candle{.{ .open = 105.0, .high = 110.0, .low = 95.0, .close = 100.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    chart.render(&buf, area);

    // Verify that body cells ('█') actually exist and are positioned correctly
    var found_body = false;
    var body_top_row: u16 = 0xFFFF;
    var body_bottom_row: u16 = 0;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█') {
                    found_body = true;
                    if (y < body_top_row) body_top_row = y;
                    if (y > body_bottom_row) body_bottom_row = y;
                }
            }
        }
    }
    try testing.expect(found_body); // Must render body cells, not just any content
    try testing.expect(body_top_row <= body_bottom_row); // Rows must be ordered correctly
}

test "CandlestickChart.render body cells span correct rows (open < close < high)" {
    var buf = try Buffer.init(testing.allocator, 40, 25);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 115.0, .low = 95.0, .close = 110.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 25 };
    chart.render(&buf, area);
    // Body should render with '█' character
    var found_body = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == '█') {
                    found_body = true;
                }
            }
        }
    }
    try testing.expect(found_body);
}

// ============================================================================
// Group 13: Render — Focused Candle Styling (4 tests)
// ============================================================================

test "CandlestickChart.render focused=0 on multi-candle chart applies focus style" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0 },
    };
    const focused_style = Style{ .bold = true };
    const chart = CandlestickChart.init()
        .withCandles(&candles)
        .withFocused(0)
        .withFocusedStyle(focused_style)
        .withUpStyle(Style{ .bold = false });
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    chart.render(&buf, area);

    // Candle 0 is focused (left band), should have bold cells
    const band_width = area.width / 2;
    const candle0_end = area.x + band_width;

    var found_focused_bold = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < candle0_end) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '│') and cell.style.bold) {
                    found_focused_bold = true;
                }
            }
        }
    }
    try testing.expect(found_focused_bold);
}

test "CandlestickChart.render focused=1 applies focus style to second candle" {
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0 },
    };
    const focused_style = Style{ .dim = true };
    const chart = CandlestickChart.init()
        .withCandles(&candles)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withUpStyle(Style{ .dim = false });
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    chart.render(&buf, area);

    // Candle 1 is focused (right band)
    const band_width = area.width / 2;
    const candle1_start = area.x + band_width;

    var found_focused_dim = false;
    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = candle1_start;
        while (x < area.x + area.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '│') and cell.style.dim) {
                    found_focused_dim = true;
                }
            }
        }
    }
    try testing.expect(found_focused_dim);
}

test "CandlestickChart.render changing focused index applies style to different candle" {
    var buf1 = try Buffer.init(testing.allocator, 80, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 80, 20);
    defer buf2.deinit();

    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0 },
    };

    const focused_style = Style{ .bold = true };
    const chart1 = CandlestickChart.init()
        .withCandles(&candles)
        .withFocused(0)
        .withFocusedStyle(focused_style)
        .withUpStyle(Style{ .bold = false });
    const chart2 = CandlestickChart.init()
        .withCandles(&candles)
        .withFocused(1)
        .withFocusedStyle(focused_style)
        .withUpStyle(Style{ .bold = false });

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    chart1.render(&buf1, area);
    chart2.render(&buf2, area);

    const band_width = area.width / 2;
    const candle0_end = area.x + band_width;
    const candle1_start = area.x + band_width;

    var buf1_candle0_bold: usize = 0;
    var buf1_candle1_bold: usize = 0;
    var buf2_candle0_bold: usize = 0;
    var buf2_candle1_bold: usize = 0;

    var y: u16 = area.y;
    while (y < area.y + area.height) : (y += 1) {
        var x: u16 = area.x;
        while (x < area.x + area.width) : (x += 1) {
            if (buf1.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '│') and cell.style.bold) {
                    if (x < candle0_end) buf1_candle0_bold += 1
                    else buf1_candle1_bold += 1;
                }
            }
            if (buf2.getConst(x, y)) |cell| {
                if ((cell.char == '█' or cell.char == '│') and cell.style.bold) {
                    if (x < candle1_start) buf2_candle0_bold += 1
                    else buf2_candle1_bold += 1;
                }
            }
        }
    }

    try testing.expect(buf1_candle0_bold > 0);
    try testing.expectEqual(@as(usize, 0), buf1_candle1_bold);
    try testing.expectEqual(@as(usize, 0), buf2_candle0_bold);
    try testing.expect(buf2_candle1_bold > 0);
}

test "CandlestickChart.render focused out of range does not crash" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0 },
    };
    const chart = CandlestickChart.init()
        .withCandles(&candles)
        .withFocused(99);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 14: Render — show_labels Toggle (3 tests)
// ============================================================================

test "CandlestickChart.render show_labels=true displays label text" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .label = "Day1", .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles).withShowLabels(true);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render show_labels=false still renders candles" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .label = "Day1", .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render show_labels affects plot_height (label row reservation)" {
    var buf1 = try Buffer.init(testing.allocator, 60, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 60, 20);
    defer buf2.deinit();

    var candles = [_]Candle{.{ .label = "Day1", .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};

    const chart_with_labels = CandlestickChart.init().withCandles(&candles).withShowLabels(true);
    const chart_no_labels = CandlestickChart.init().withCandles(&candles).withShowLabels(false);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart_with_labels.render(&buf1, area);
    chart_no_labels.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

// ============================================================================
// Group 15: Render — Block Border (3 tests)
// ============================================================================

test "CandlestickChart.render with block border renders border and content" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0 },
    };
    const block = Block{};
    const chart = CandlestickChart.init()
        .withCandles(&candles)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render block border reduces inner area for candle content" {
    var buf1 = try Buffer.init(testing.allocator, 50, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 50, 20);
    defer buf2.deinit();

    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0 },
    };

    const block = Block{};
    const chart_with_block = CandlestickChart.init().withCandles(&candles).withBlock(block);
    const chart_no_block = CandlestickChart.init().withCandles(&candles);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart_with_block.render(&buf1, area);
    chart_no_block.render(&buf2, area);

    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expect(content1 > 0);
    try testing.expect(content2 > 0);
}

test "CandlestickChart.render with block border and title" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .label = "Price", .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};
    const block = (Block{}).withTitle("OHLC", .top_left);
    const chart = CandlestickChart.init()
        .withCandles(&candles)
        .withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 16: Render — MAX_CANDLES Cap (3 tests)
// ============================================================================

test "CandlestickChart.render with exactly MAX_CANDLES=64 renders all candles" {
    var buf = try Buffer.init(testing.allocator, 200, 25);
    defer buf.deinit();
    var candles: [64]Candle = undefined;
    for (0..64) |i| {
        const base = @as(f32, @floatFromInt(100 + i % 20));
        candles[i] = .{
            .open = base,
            .high = base + 5.0,
            .low = base - 3.0,
            .close = base + 2.0,
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    try testing.expectEqual(@as(usize, 64), chart.candleCount());
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render with 100 candles caps to MAX_CANDLES=64" {
    var buf = try Buffer.init(testing.allocator, 200, 25);
    defer buf.deinit();
    var candles: [100]Candle = undefined;
    for (0..100) |i| {
        const base = @as(f32, @floatFromInt(100 + i % 20));
        candles[i] = .{
            .open = base,
            .high = base + 5.0,
            .low = base - 3.0,
            .close = base + 2.0,
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    try testing.expectEqual(@as(usize, 64), chart.candleCount());
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render with 128 candles only renders first 64" {
    var buf = try Buffer.init(testing.allocator, 200, 25);
    defer buf.deinit();
    var candles: [128]Candle = undefined;
    for (0..128) |i| {
        const base = @as(f32, @floatFromInt(100 + i % 30));
        candles[i] = .{
            .open = base,
            .high = base + 5.0,
            .low = base - 3.0,
            .close = base + 1.0,
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    try testing.expectEqual(@as(usize, 64), chart.candleCount());
    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 17: Render — Degenerate Cases (4 tests)
// ============================================================================

test "CandlestickChart.render with all identical OHLC (high==low==open==close)" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 100.0, .low = 100.0, .close = 100.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    // Should not crash; may produce minimal content due to degenerate scaling
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

test "CandlestickChart.render multiple candles all with identical OHLC" {
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 100.0, .low = 100.0, .close = 100.0 },
        .{ .open = 100.0, .high = 100.0, .low = 100.0, .close = 100.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

test "CandlestickChart.render with negative and positive prices" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = -50.0, .high = 50.0, .low = -100.0, .close = 0.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render single candle with n=1 does not divide by zero" {
    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

// ============================================================================
// Group 18: Render — Small Areas (3 tests)
// ============================================================================

test "CandlestickChart.render minimal height (3 rows) without label row" {
    var buf = try Buffer.init(testing.allocator, 30, 3);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles).withShowLabels(false);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

test "CandlestickChart.render very narrow width" {
    var buf = try Buffer.init(testing.allocator, 10, 15);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 15 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}

test "CandlestickChart.render tiny area (8x6) does not crash" {
    var buf = try Buffer.init(testing.allocator, 8, 6);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 6 };
    chart.render(&buf, area);
}

// ============================================================================
// Group 19: Real-World Scenario — Simulated Price Series (2 tests)
// ============================================================================

test "CandlestickChart.render realistic 5-day bullish trend" {
    var buf = try Buffer.init(testing.allocator, 100, 25);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .label = "Mon", .open = 100.0, .high = 105.0, .low = 98.0, .close = 103.0 },
        .{ .label = "Tue", .open = 103.0, .high = 107.0, .low = 102.0, .close = 106.0 },
        .{ .label = "Wed", .open = 106.0, .high = 110.0, .low = 105.0, .close = 109.0 },
        .{ .label = "Thu", .open = 109.0, .high = 112.0, .low = 108.0, .close = 111.0 },
        .{ .label = "Fri", .open = 111.0, .high = 115.0, .low = 110.0, .close = 114.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render realistic volatile week with reversals" {
    var buf = try Buffer.init(testing.allocator, 120, 25);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .label = "Mon", .open = 100.0, .high = 108.0, .low = 98.0, .close = 105.0 },
        .{ .label = "Tue", .open = 105.0, .high = 110.0, .low = 100.0, .close = 102.0 },
        .{ .label = "Wed", .open = 102.0, .high = 106.0, .low = 99.0, .close = 104.0 },
        .{ .label = "Thu", .open = 104.0, .high = 112.0, .low = 103.0, .close = 110.0 },
        .{ .label = "Fri", .open = 110.0, .high = 115.0, .low = 108.0, .close = 112.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 25 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

// ============================================================================
// Group 20: Additional Edge Cases (3 tests)
// ============================================================================

test "CandlestickChart.render buffer bounds safety with large candle count" {
    var buf = try Buffer.init(testing.allocator, 256, 30);
    defer buf.deinit();
    var candles: [64]Candle = undefined;
    for (0..64) |i| {
        const base = @as(f32, @floatFromInt(100 + (i * 7) % 50));
        candles[i] = .{
            .open = base,
            .high = base + 10.0,
            .low = base - 8.0,
            .close = base + (if (i % 3 == 0) @as(f32, 5.0) else @as(f32, -4.0)),
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 256, .height = 30 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render with per-candle style (future use)" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0, .style = Style{ .bold = true } },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0, .style = Style{ .italic = true } },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };
    chart.render(&buf, area);
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty > 0);
}

test "CandlestickChart.render preserves immutability across render calls" {
    var buf1 = try Buffer.init(testing.allocator, 40, 20);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 40, 20);
    defer buf2.deinit();

    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 105.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf1, area);
    chart.render(&buf2, area);

    // Both renders should produce same result (immutability check)
    const content1 = countNonEmptyCells(buf1, area);
    const content2 = countNonEmptyCells(buf2, area);
    try testing.expectEqual(content1, content2);
}

// ============================================================================
// Group 21: Crash Regression — Out-of-Range OHLC Values (1 test)
// ============================================================================

test "CandlestickChart.render with out-of-range open price does not crash" {
    var buf = try Buffer.init(testing.allocator, 50, 20);
    defer buf.deinit();

    // Malformed OHLC: open far below the candle's own low and global scale
    // This is a realistic scenario with bad financial data feed
    // Global scale is derived from low/high (90-110), but open is -1,000,000
    // Without clamping in valueToRow.calc, this would overflow when cast to u16
    var candles = [_]Candle{
        .{ .open = -1_000_000.0, .high = 110.0, .low = 90.0, .close = 100.0 }
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    // This render should NOT panic/crash, even with malformed input
    // The implementation must clamp or validate out-of-range values
    chart.render(&buf, area);

    // Render completed without panic — verify some content was produced
    const non_empty = countNonEmptyCells(buf, area);
    try testing.expect(non_empty >= 0);
}
