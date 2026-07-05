//! WaterfallChart Widget — cumulative flow visualization
//!
//! The WaterfallChart widget displays sequential contributions to a total,
//! showing how intermediate values arrive at a final result. Bars are
//! categorized by kind:
//! - .relative: cumulative delta (starts from running total, adds value)
//! - .absolute: resets the baseline (goes from 0 to value, updates total)
//! - .total: shows the running total without changing it
//!
//! ## Features
//! - Up to 32 bars arranged left-to-right
//! - Three waterfall kinds: relative, absolute, total
//! - Focused bar highlighting
//! - Optional value labels and connector lines
//! - Separate styling for positive/negative/total bars
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const bars = [_]WaterfallBar{
//!     .{ .label = "Start", .value = 100.0, .kind = .relative },
//!     .{ .label = "Delta", .value = 20.0, .kind = .relative },
//!     .{ .label = "Total", .value = 120.0, .kind = .total },
//! };
//!
//! const chart = WaterfallChart.init()
//!     .withBars(&bars)
//!     .withShowValues(true)
//!     .withShowConnectors(true);
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

/// Waterfall bar kind: how it contributes to the running total
pub const WaterfallKind = enum {
    /// Cumulative delta: bar floats from running_total to running_total + value
    relative,
    /// Absolute baseline reset: bar goes from 0 to value, updates running_total
    absolute,
    /// Running total display: bar shows running_total without changing it
    total,
};

/// Single bar in a waterfall chart
pub const WaterfallBar = struct {
    /// Label for the bar
    label: []const u8 = "",
    /// Value (positive or negative)
    value: f32 = 0.0,
    /// How the bar contributes: relative, absolute, or total
    kind: WaterfallKind = .relative,
    /// Optional custom style for this bar
    style: Style = .{},
};

pub const WaterfallChart = struct {
    /// Maximum number of bars (capped at 32 for rendering)
    pub const MAX_BARS: usize = 32;

    /// Array of bars to display
    bars: []const WaterfallBar = &.{},
    /// Index of the focused bar for highlighting
    focused: usize = 0,
    /// Whether to render value labels on bars
    show_values: bool = true,
    /// Whether to render connector lines between bars
    show_connectors: bool = true,
    /// Style for positive-value bars (relative/absolute increasing)
    positive_style: Style = .{},
    /// Style for negative-value bars (relative/absolute decreasing)
    negative_style: Style = .{},
    /// Style for total bars (.total kind)
    total_style: Style = .{},
    /// Style for the focused bar
    focused_style: Style = .{},
    /// Style for connector lines
    connector_style: Style = .{},
    /// Base style applied to all bars
    style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a WaterfallChart with all defaults
    pub fn init() WaterfallChart {
        return .{};
    }

    /// Count of bars to render (capped at MAX_BARS)
    pub fn barCount(self: WaterfallChart) usize {
        return @min(self.bars.len, MAX_BARS);
    }

    /// Set bars array
    pub fn withBars(self: WaterfallChart, bars: []const WaterfallBar) WaterfallChart {
        var result = self;
        result.bars = bars;
        return result;
    }

    /// Set focused bar index
    pub fn withFocused(self: WaterfallChart, idx: usize) WaterfallChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: WaterfallChart, show: bool) WaterfallChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set show_connectors flag
    pub fn withShowConnectors(self: WaterfallChart, show: bool) WaterfallChart {
        var result = self;
        result.show_connectors = show;
        return result;
    }

    /// Set positive_style
    pub fn withPositiveStyle(self: WaterfallChart, s: Style) WaterfallChart {
        var result = self;
        result.positive_style = s;
        return result;
    }

    /// Set negative_style
    pub fn withNegativeStyle(self: WaterfallChart, s: Style) WaterfallChart {
        var result = self;
        result.negative_style = s;
        return result;
    }

    /// Set total_style
    pub fn withTotalStyle(self: WaterfallChart, s: Style) WaterfallChart {
        var result = self;
        result.total_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: WaterfallChart, s: Style) WaterfallChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set connector_style
    pub fn withConnectorStyle(self: WaterfallChart, s: Style) WaterfallChart {
        var result = self;
        result.connector_style = s;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: WaterfallChart, s: Style) WaterfallChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: WaterfallChart, b: ?Block) WaterfallChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the waterfall chart to the buffer
    pub fn render(self: WaterfallChart, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need at least 3x3 inner area to render anything
        if (inner.width < 3 or inner.height < 3) return;

        const n = self.barCount();
        if (n == 0) return;

        // Column width per bar
        const col_width = inner.width / @as(u16, @intCast(n));
        if (col_width == 0) return;

        // ========== Pass 1: Calculate running totals and find min/max ==========
        var running_total: f32 = 0.0;
        var min_val: f32 = 0.0;
        var max_val: f32 = 0.0;
        var running_totals: [MAX_BARS]f32 = undefined;

        for (0..n) |i| {
            const bar = self.bars[i];
            running_totals[i] = running_total;

            // Update running total and track min/max
            switch (bar.kind) {
                .relative => {
                    running_total += bar.value;
                },
                .absolute => {
                    running_total = bar.value;
                },
                .total => {
                    // total kind doesn't change running_total
                },
            }

            // Track the range for scaling
            if (bar.kind == .total) {
                const val = running_total;
                if (val < min_val) min_val = val;
                if (val > max_val) max_val = val;
            } else {
                const start = running_totals[i];
                const end = if (bar.kind == .absolute) bar.value else running_total;
                const bar_min = @min(start, end);
                const bar_max = @max(start, end);
                if (bar_min < min_val) min_val = bar_min;
                if (bar_max > max_val) max_val = bar_max;
            }
        }

        // Ensure we have a valid range for scaling
        if (max_val == min_val) {
            if (max_val == 0.0) {
                max_val = 1.0;
            } else {
                min_val = 0.0;
            }
        }

        const value_range = max_val - min_val;

        // ========== Pass 2: Render bars ==========
        for (0..n) |i| {
            const bar = self.bars[i];
            const bar_start = running_totals[i];

            // Determine bar float and top positions
            var bar_float: f32 = 0.0;
            var bar_top: f32 = 0.0;
            switch (bar.kind) {
                .relative => {
                    bar_float = bar_start;
                    bar_top = bar_start + bar.value;
                },
                .absolute => {
                    bar_float = 0.0;
                    bar_top = bar.value;
                },
                .total => {
                    bar_float = 0.0;
                    bar_top = bar_start;
                },
            }

            // Convert float values to pixel rows (y=0 at top, increases downward)
            // Map [min_val, max_val] -> [inner.y + inner.height - 1, inner.y]
            const float_row_f32: f32 = @as(f32, @floatFromInt(inner.height)) - 1.0 -
                (@as(f32, @floatFromInt(inner.height)) - 1.0) * (bar_float - min_val) / value_range;
            const top_row_f32: f32 = @as(f32, @floatFromInt(inner.height)) - 1.0 -
                (@as(f32, @floatFromInt(inner.height)) - 1.0) * (bar_top - min_val) / value_range;

            var float_row: i32 = @intFromFloat(@round(float_row_f32));
            var top_row: i32 = @intFromFloat(@round(top_row_f32));

            // Clamp to bounds
            const inner_top: i32 = @intCast(inner.y);
            const inner_bottom: i32 = @intCast(inner.y + inner.height - 1);
            if (float_row > inner_bottom) float_row = inner_bottom;
            if (float_row < inner_top) float_row = inner_top;
            if (top_row > inner_bottom) top_row = inner_bottom;
            if (top_row < inner_top) top_row = inner_top;

            // Ensure top < float for rendering
            if (top_row > float_row) {
                const tmp = top_row;
                top_row = float_row;
                float_row = tmp;
            }

            // Calculate column range for this bar
            const col_start = inner.x + @as(u16, @intCast(i)) * col_width;
            const col_end = if (i == n - 1)
                inner.x + inner.width
            else
                col_start + col_width;

            // Determine bar style
            const is_focused = (i == self.focused);
            var bar_style = if (bar.kind == .total)
                self.total_style
            else if (bar.value >= 0.0)
                self.positive_style
            else
                self.negative_style;

            // Merge with focused style if applicable
            if (is_focused) {
                bar_style = self.focused_style;
            }

            // Fill bar with █ character
            var row: i32 = top_row;
            while (row <= float_row) : (row += 1) {
                if (row >= inner_top and row < inner_bottom + 1) {
                    for (col_start..col_end) |col| {
                        if (col < buf.width) {
                            const y: u16 = @intCast(row);
                            buf.set(@intCast(col), y, Cell.init('█', bar_style));
                        }
                    }
                }
            }

            // Render value label if enabled
            if (self.show_values) {
                // Format value as string (simple integer formatting)
                var value_str: [16]u8 = undefined;
                const value_to_display = bar.value;
                const int_part: i32 = @intFromFloat(value_to_display);
                var str_len: usize = 0;

                if (int_part < 0) {
                    value_str[0] = '-';
                    str_len = 1;
                    const abs_val: u32 = @intCast(-int_part);
                    var digit_count: usize = 0;
                    var temp = abs_val;
                    while (temp > 0) : (temp /= 10) digit_count += 1;
                    if (digit_count == 0) digit_count = 1;
                    temp = abs_val;
                    for (0..digit_count) |_| {
                        value_str[str_len + digit_count - 1] = @as(u8, @intCast(temp % 10 + 48));
                        temp /= 10;
                    }
                    str_len += digit_count;
                } else if (int_part == 0 and bar.value >= 0) {
                    value_str[0] = '+';
                    value_str[1] = '0';
                    str_len = 2;
                } else {
                    value_str[0] = '+';
                    str_len = 1;
                    const abs_val: u32 = @intCast(int_part);
                    var digit_count: usize = 0;
                    var temp = abs_val;
                    while (temp > 0) : (temp /= 10) digit_count += 1;
                    if (digit_count == 0) digit_count = 1;
                    temp = abs_val;
                    for (0..digit_count) |_| {
                        value_str[str_len + digit_count - 1] = @as(u8, @intCast(temp % 10 + 48));
                        temp /= 10;
                    }
                    str_len += digit_count;
                }

                // Place label at top of bar
                const label_row: u16 = @intCast(if (top_row >= inner_top) top_row else inner_top);
                if (label_row < buf.height and col_start < buf.width) {
                    buf.setString(col_start, label_row, value_str[0..str_len], bar_style);
                }
            }

            // Render connector line if enabled and not the last bar
            if (self.show_connectors and i < n - 1) {
                const next_bar_start = if (bar.kind == .relative)
                    running_total
                else if (bar.kind == .absolute)
                    bar.value
                else
                    running_total;

                const next_float_row_f32: f32 = @as(f32, @floatFromInt(inner.height)) - 1.0 -
                    (@as(f32, @floatFromInt(inner.height)) - 1.0) * (next_bar_start - min_val) / value_range;
                var next_float_row: i32 = @intFromFloat(@round(next_float_row_f32));

                if (next_float_row > inner_bottom) next_float_row = inner_bottom;
                if (next_float_row < inner_top) next_float_row = inner_top;

                // Draw horizontal connector from this bar's right edge to next bar's left edge
                const connector_y: u16 = @intCast(next_float_row);
                if (connector_y < buf.height) {
                    for (col_end..@min(@as(u16, @intCast(col_end)) + col_width, inner.x + inner.width)) |col| {
                        if (col < buf.width) {
                            buf.set(@intCast(col), connector_y, Cell.init('─', self.connector_style));
                        }
                    }
                }
            }
        }
    }
};
