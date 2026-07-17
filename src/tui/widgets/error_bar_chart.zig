//! ErrorBarChart Widget — Measurement uncertainty visualization
//!
//! The ErrorBarChart widget displays categorical items with point estimates
//! and asymmetric error bars, showing measurement uncertainty or confidence
//! intervals. One item per row, with whiskers extending from value-err_low
//! to value+err_high.
//!
//! ## Features
//! - Up to 32 items arranged top-to-bottom
//! - Asymmetric error bars (err_low, err_high)
//! - Point estimate marker with customizable character
//! - Whisker caps at error bounds
//! - Optional labels and value display
//! - Focused item highlighting
//! - Per-item styling
//! - Block border support
//! - No heap allocations
//! - No panic on degenerate/out-of-range inputs
//!
//! ## Usage
//! ```zig
//! const items = [_]ErrorBarItem{
//!     .{ .label = "Exp A", .value = 95.5, .err_low = 5.2, .err_high = 6.1 },
//!     .{ .label = "Exp B", .value = 87.3, .err_low = 8.1, .err_high = 7.9 },
//! };
//!
//! const chart = ErrorBarChart.init()
//!     .withItems(&items)
//!     .withMinVal(60.0)
//!     .withMaxVal(115.0)
//!     .withShowValues(true);
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

/// A single item in the error bar chart
pub const ErrorBarItem = struct {
    /// Label for the item
    label: []const u8 = "",
    /// Point estimate value (center of error bar)
    value: f32 = 0.0,
    /// Lower error magnitude (value - err_low is lower bound)
    err_low: f32 = 0.0,
    /// Upper error magnitude (value + err_high is upper bound)
    err_high: f32 = 0.0,
    /// Optional custom style for this item
    style: Style = .{},
};

pub const ErrorBarChart = struct {
    /// Maximum number of items (capped at 32 for rendering)
    pub const MAX_ITEMS: usize = 32;

    /// Array of items to display
    items: []const ErrorBarItem = &.{},
    /// Index of the focused item for highlighting
    focused: usize = 0,
    /// Minimum value for range normalization
    min_val: f32 = 0.0,
    /// Maximum value for range normalization
    max_val: f32 = 1.0,
    /// Whether to render labels
    show_labels: bool = true,
    /// Whether to render values after marker
    show_values: bool = false,
    /// Character to use for marker (point estimate)
    marker_char: u21 = '●',
    /// Character to use for whisker caps at error bounds
    cap_char: u21 = '─',
    /// Character to use for whisker line
    whisker_char: u21 = '│',
    /// Base style applied to whiskers
    style: Style = .{},
    /// Style for marker (point estimate)
    marker_style: Style = .{},
    /// Style for the focused item's marker
    focused_style: Style = .{},
    /// Style for labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize an ErrorBarChart with all defaults
    pub fn init() ErrorBarChart {
        return .{};
    }

    /// Count of items to render (capped at MAX_ITEMS)
    pub fn itemCount(self: ErrorBarChart) usize {
        return @min(self.items.len, MAX_ITEMS);
    }

    /// Set items array
    pub fn withItems(self: ErrorBarChart, items: []const ErrorBarItem) ErrorBarChart {
        var result = self;
        result.items = items;
        return result;
    }

    /// Set focused item index
    pub fn withFocused(self: ErrorBarChart, idx: usize) ErrorBarChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set min_val for normalization
    pub fn withMinVal(self: ErrorBarChart, v: f32) ErrorBarChart {
        var result = self;
        result.min_val = v;
        return result;
    }

    /// Set max_val for normalization
    pub fn withMaxVal(self: ErrorBarChart, v: f32) ErrorBarChart {
        var result = self;
        result.max_val = v;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: ErrorBarChart, show: bool) ErrorBarChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: ErrorBarChart, show: bool) ErrorBarChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set marker_char
    pub fn withMarkerChar(self: ErrorBarChart, ch: u21) ErrorBarChart {
        var result = self;
        result.marker_char = ch;
        return result;
    }

    /// Set cap_char
    pub fn withCapChar(self: ErrorBarChart, ch: u21) ErrorBarChart {
        var result = self;
        result.cap_char = ch;
        return result;
    }

    /// Set whisker_char
    pub fn withWhiskerChar(self: ErrorBarChart, ch: u21) ErrorBarChart {
        var result = self;
        result.whisker_char = ch;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: ErrorBarChart, s: Style) ErrorBarChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set marker style
    pub fn withMarkerStyle(self: ErrorBarChart, s: Style) ErrorBarChart {
        var result = self;
        result.marker_style = s;
        return result;
    }

    /// Set focused style
    pub fn withFocusedStyle(self: ErrorBarChart, s: Style) ErrorBarChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: ErrorBarChart, s: Style) ErrorBarChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: ErrorBarChart, b: ?Block) ErrorBarChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the error bar chart to the buffer
    pub fn render(self: ErrorBarChart, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need at least 2 columns for plot
        if (inner.width < 2 or inner.height == 0) return;

        const n = self.itemCount();
        if (n == 0) return;

        // Compute label column width
        var max_label_len: usize = 0;
        if (self.show_labels) {
            for (self.items[0..n]) |item| {
                if (item.label.len > max_label_len) {
                    max_label_len = item.label.len;
                }
            }
        }

        // Cap label column at inner_width / 3, but minimum 0
        const label_col_width = if (self.show_labels and max_label_len > 0)
            @min(max_label_len, inner.width / 3)
        else
            0;

        // Plot area starts after label column (+ 1 separator space if labels present)
        const separator = if (label_col_width > 0) @as(u16, 1) else @as(u16, 0);
        const plot_x = inner.x + @as(u16, @intCast(label_col_width)) + separator;
        const plot_width = if (inner.width > label_col_width + separator)
            inner.width - @as(u16, @intCast(label_col_width)) - separator
        else
            0;

        if (plot_width == 0) return;

        // Render items (up to inner.height rows)
        for (0..@min(n, inner.height)) |i| {
            const item = self.items[i];
            const row_y = inner.y + @as(u16, @intCast(i));
            if (row_y >= buf.height) break;

            // Draw label if enabled
            if (self.show_labels and label_col_width > 0 and item.label.len > 0) {
                const label_len = @min(item.label.len, label_col_width);
                buf.setString(inner.x, row_y, item.label[0..label_len], self.label_style);
            }

            // Compute normalized positions for value and error bounds
            const range = self.max_val - self.min_val;

            // Normalize value to [0, 1]
            const value_norm = if (range == 0.0)
                0.0
            else
                @max(0.0, @min(1.0, (item.value - self.min_val) / range));

            // Normalize error bounds to [0, 1]
            const low_bound = item.value - item.err_low;
            const high_bound = item.value + item.err_high;

            const low_norm = if (range == 0.0)
                0.0
            else
                @max(0.0, @min(1.0, (low_bound - self.min_val) / range));

            const high_norm = if (range == 0.0)
                0.0
            else
                @max(0.0, @min(1.0, (high_bound - self.min_val) / range));

            // Convert normalized positions to column indices
            const low_col = @as(u16, @intFromFloat(@round(low_norm * @as(f32, @floatFromInt(plot_width - 1)))));
            const high_col = @as(u16, @intFromFloat(@round(high_norm * @as(f32, @floatFromInt(plot_width - 1)))));
            const value_col = @as(u16, @intFromFloat(@round(value_norm * @as(f32, @floatFromInt(plot_width - 1)))));

            const low_abs_x = plot_x + low_col;
            const high_abs_x = plot_x + high_col;
            const value_abs_x = plot_x + value_col;

            // Draw whisker span from low to high (inclusive)
            var col = low_abs_x;
            while (col <= high_abs_x and col < buf.width) : (col += 1) {
                buf.set(col, row_y, Cell.init(self.whisker_char, self.style));
            }

            // Draw caps at whisker endpoints
            if (low_abs_x < buf.width) {
                buf.set(low_abs_x, row_y, Cell.init(self.cap_char, self.style));
            }
            if (high_abs_x < buf.width) {
                buf.set(high_abs_x, row_y, Cell.init(self.cap_char, self.style));
            }

            // Draw marker at value position (always wins, drawn last)
            var marker_style = self.marker_style;
            if (i == self.focused) {
                marker_style = self.focused_style;
            }
            if (value_abs_x < buf.width) {
                buf.set(value_abs_x, row_y, Cell.init(self.marker_char, marker_style));
            }

            // Draw value if enabled
            if (self.show_values) {
                drawValueLabel(buf, value_abs_x, row_y, item.value, self.style);
            }
        }
    }
};

/// Helper: Format and draw value label
fn drawValueLabel(buf: *Buffer, x: u16, y: u16, value: f32, style: Style) void {
    var value_str: [16]u8 = undefined;
    const int_part: i32 = @intFromFloat(value);
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
    } else if (int_part == 0 and value >= 0) {
        value_str[0] = '0';
        str_len = 1;
    } else {
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

    // Draw at x + 1
    if (x + 1 < buf.width and y < buf.height) {
        buf.setString(x + 1, y, value_str[0..@min(str_len, 15)], style);
    }
}
