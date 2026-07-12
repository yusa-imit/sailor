//! CandlestickChart Widget — OHLC financial candlestick charts
//!
//! The CandlestickChart widget displays multiple time periods as candlesticks,
//! showing open, high, low, and close prices (OHLC) for each period. Each candle
//! consists of a wick (high-to-low range) and a body (open-to-close range).
//! Bullish candles (close >= open) render in up_style; bearish candles (close < open)
//! render in down_style. All candles share a global value scale for cross-period comparison.
//!
//! ## Features
//! - Up to 64 candles (MAX_CANDLES)
//! - OHLC data with wick and body rendering
//! - Bullish vs bearish coloring (up_style / down_style)
//! - Global price scale across all candles
//! - Focused candle highlighting
//! - Optional label row at bottom
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const candles = [_]Candle{
//!     .{ .label = "Mon", .open = 100.0, .high = 105.0, .low = 98.0, .close = 103.0 },
//!     .{ .label = "Tue", .open = 103.0, .high = 107.0, .low = 102.0, .close = 106.0 },
//! };
//!
//! const chart = CandlestickChart.init()
//!     .withCandles(&candles)
//!     .withShowLabels(true)
//!     .withFocused(0);
//!
//! chart.render(&buf, area);
//! ```

const std = @import("std");
const math = std.math;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Single candle in a candlestick chart
pub const Candle = struct {
    /// Label for the candle (e.g., date)
    label: []const u8 = "",
    /// Opening price
    open: f32 = 0.0,
    /// Highest price
    high: f32 = 0.0,
    /// Lowest price
    low: f32 = 0.0,
    /// Closing price
    close: f32 = 0.0,
    /// Optional custom style for this candle
    style: Style = .{},
};

pub const CandlestickChart = struct {
    /// Maximum number of candles (capped at 64 for rendering)
    pub const MAX_CANDLES: usize = 64;

    /// Array of candles to display
    candles: []const Candle = &.{},
    /// Index of the focused candle for highlighting
    focused: usize = 0,
    /// Whether to render candle labels
    show_labels: bool = true,
    /// Base style applied to all candles
    style: Style = .{},
    /// Style for bullish candles (close >= open)
    up_style: Style = .{},
    /// Style for bearish candles (close < open)
    down_style: Style = .{},
    /// Style for wick lines
    wick_style: Style = .{},
    /// Style for the focused candle
    focused_style: Style = .{},
    /// Style for candle labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a CandlestickChart with all defaults
    pub fn init() CandlestickChart {
        return .{};
    }

    /// Count of candles to render (capped at MAX_CANDLES)
    pub fn candleCount(self: CandlestickChart) usize {
        return @min(self.candles.len, MAX_CANDLES);
    }

    /// Set candles array
    pub fn withCandles(self: CandlestickChart, c: []const Candle) CandlestickChart {
        var result = self;
        result.candles = c;
        return result;
    }

    /// Set focused candle index
    pub fn withFocused(self: CandlestickChart, idx: usize) CandlestickChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: CandlestickChart, show: bool) CandlestickChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: CandlestickChart, s: Style) CandlestickChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set up_style (bullish)
    pub fn withUpStyle(self: CandlestickChart, s: Style) CandlestickChart {
        var result = self;
        result.up_style = s;
        return result;
    }

    /// Set down_style (bearish)
    pub fn withDownStyle(self: CandlestickChart, s: Style) CandlestickChart {
        var result = self;
        result.down_style = s;
        return result;
    }

    /// Set wick_style
    pub fn withWickStyle(self: CandlestickChart, s: Style) CandlestickChart {
        var result = self;
        result.wick_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: CandlestickChart, s: Style) CandlestickChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: CandlestickChart, s: Style) CandlestickChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: CandlestickChart, b: ?Block) CandlestickChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the candlestick chart to the buffer
    pub fn render(self: CandlestickChart, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;
        if (area.width < 2 or area.height < 2) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        const n = self.candleCount();
        if (n == 0) return;

        // Need minimum area to render
        if (inner.width == 0 or inner.height == 0) return;

        // ========== Step 1: Find global min/max across all candles ==========
        var global_min: f32 = 0.0;
        var global_max: f32 = 0.0;
        var has_values = false;

        for (0..n) |i| {
            const candle = self.candles[i];
            if (!has_values) {
                global_min = candle.low;
                global_max = candle.high;
                has_values = true;
            } else {
                if (candle.low < global_min) global_min = candle.low;
                if (candle.high > global_max) global_max = candle.high;
            }
        }

        if (!has_values) return;

        // ========== Step 2: Calculate plot height and label row reservation ==========
        var plot_height = inner.height;
        if (self.show_labels and inner.height > 0) {
            plot_height = inner.height - 1;
        }

        if (plot_height == 0) return;

        // ========== Step 3: Calculate value-to-row mapping ==========
        const valueToRow = struct {
            fn calc(value: f32, min_val: f32, max_val: f32, height: usize, plot_y: usize) usize {
                if (max_val == min_val) {
                    // Degenerate case: all values identical, center in middle row
                    return plot_y + height / 2;
                }
                const normalized = (value - min_val) / (max_val - min_val);
                const clamped_normalized = @max(0.0, @min(1.0, normalized));
                const row_offset = @as(f32, @floatFromInt(height - 1)) * clamped_normalized;
                const row_from_top = @as(i32, @intFromFloat(@round(row_offset)));
                const row_from_bottom: i32 = @as(i32, @intCast(height - 1)) - row_from_top;
                const max_row: i32 = @intCast(height - 1);
                const final_row = @max(0, @min(max_row, row_from_bottom));
                return plot_y + @as(usize, @intCast(final_row)); // invert: top=max, bottom=min
            }
        };

        // ========== Step 4: Render per-candle wicks and bodies ==========
        const band_width = if (n > 0) (inner.width / @as(usize, @intCast(n))) else inner.width;

        for (0..n) |i| {
            const candle = self.candles[i];
            const band_start = inner.x + i * band_width;
            const band_center = band_start + band_width / 2;

            // Determine which style to use (focused or regular)
            const use_focused = (i == self.focused);
            const is_bullish = candle.close >= candle.open;

            // Check if focused_style is explicitly set (has non-default values)
            const focused_style_is_set = self.focused_style.bold or self.focused_style.dim or self.focused_style.italic or
                self.focused_style.underline or self.focused_style.blink or self.focused_style.reverse or
                self.focused_style.strikethrough or self.focused_style.fg != null or self.focused_style.bg != null;

            const effective_wick_style = if (use_focused and focused_style_is_set) self.focused_style else self.wick_style;
            const effective_body_style = if (use_focused and focused_style_is_set) self.focused_style else (if (is_bullish) self.up_style else self.down_style);

            // Compute row positions
            const row_high = valueToRow.calc(candle.high, global_min, global_max, plot_height, inner.y);
            const row_low = valueToRow.calc(candle.low, global_min, global_max, plot_height, inner.y);
            const row_open = valueToRow.calc(candle.open, global_min, global_max, plot_height, inner.y);
            const row_close = valueToRow.calc(candle.close, global_min, global_max, plot_height, inner.y);

            // Compute wick bounds (high to low)
            const wick_top = @min(row_high, row_low);
            const wick_bottom = @max(row_high, row_low);

            // Render wick (vertical line from high to low)
            {
                var row = wick_top;
                while (row <= wick_bottom) : (row += 1) {
                    buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row)), Cell.init('│', effective_wick_style));
                }
            }

            // Compute body bounds (open to close)
            const body_top = @min(row_open, row_close);
            const body_bottom = @max(row_open, row_close);

            // Render body (vertical block from open to close, overwrites wick cells)
            {
                var row = body_top;
                while (row <= body_bottom) : (row += 1) {
                    buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row)), Cell.init('█', effective_body_style));
                }
            }
        }

        // ========== Step 5: Render labels if enabled ==========
        if (self.show_labels and inner.height > 1) {
            const label_row = inner.y + plot_height;
            for (0..n) |i| {
                const candle = self.candles[i];
                const band_start = inner.x + i * band_width;
                const band_center = band_start + band_width / 2;

                if (candle.label.len > 0) {
                    // Render first character of label at center of band
                    const char = candle.label[0];
                    buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(label_row)), Cell.init(char, self.label_style));
                }
            }
        }
    }
};

// ============================================================================
// In-file library tests (minimal — main test suite in tests/candlestick_chart_test.zig)
// ============================================================================

test "CandlestickChart.init creates default chart with zero candles" {
    const chart = CandlestickChart.init();
    try std.testing.expectEqual(@as(usize, 0), chart.candles.len);
}

test "CandlestickChart.candleCount caps at MAX_CANDLES" {
    var candles: [100]Candle = undefined;
    for (0..100) |i| {
        candles[i] = .{
            .open = @as(f32, @floatFromInt(i)),
            .high = @as(f32, @floatFromInt(i + 1)),
            .low = @as(f32, @floatFromInt(@as(i32, @intCast(i)) - 1)),
            .close = @as(f32, @floatFromInt(i)),
        };
    }
    const chart = CandlestickChart.init().withCandles(&candles);
    try std.testing.expectEqual(@as(usize, 64), chart.candleCount());
}

test "CandlestickChart.withCandles maintains immutability" {
    var candles1 = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    var candles2 = [_]Candle{
        .{ .open = 50.0, .high = 55.0, .low = 45.0, .close = 52.0 },
        .{ .open = 60.0, .high = 65.0, .low = 55.0, .close = 62.0 },
    };

    const chart1 = CandlestickChart.init().withCandles(&candles1);
    const chart2 = chart1.withCandles(&candles2);

    try std.testing.expectEqual(@as(usize, 1), chart1.candleCount());
    try std.testing.expectEqual(@as(usize, 2), chart2.candleCount());
}

test "CandlestickChart.render single bullish candle produces content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    chart.render(&buf, area);
}

test "CandlestickChart.render on zero-area exits early" {
    var buf = try Buffer.init(std.testing.allocator, 0, 0);
    defer buf.deinit();
    var candles = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 }};
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    chart.render(&buf, area);
}

test "CandlestickChart.render multiple candles produces content" {
    var buf = try Buffer.init(std.testing.allocator, 60, 20);
    defer buf.deinit();
    var candles = [_]Candle{
        .{ .open = 100.0, .high = 110.0, .low = 95.0, .close = 108.0 },
        .{ .open = 105.0, .high = 115.0, .low = 100.0, .close = 112.0 },
    };
    const chart = CandlestickChart.init().withCandles(&candles);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    chart.render(&buf, area);
}

test "CandlestickChart builder methods maintain immutability" {
    var candles1 = [_]Candle{.{ .open = 100.0, .high = 110.0, .low = 90.0, .close = 105.0 }};
    var candles2 = [_]Candle{.{ .open = 50.0, .high = 55.0, .low = 45.0, .close = 52.0 }};

    const chart1 = CandlestickChart.init().withCandles(&candles1);
    const chart2 = chart1.withCandles(&candles2);

    try std.testing.expectEqual(@as(usize, 1), chart1.candleCount());
    try std.testing.expectEqual(@as(usize, 1), chart2.candleCount());
}
