//! DotPlot Widget — Cleveland dot plot visualization
//!
//! The DotPlot widget displays categorical items as dots on a horizontal axis,
//! with one item per row. Each dot position is determined by normalization against
//! x_min and x_max range. A dashed line connects the label to the dot.
//!
//! ## Features
//! - Up to 64 items arranged top-to-bottom
//! - Dots positioned by value normalization on horizontal axis
//! - Optional horizontal dashed lines from label to dot
//! - Focused item highlighting
//! - Optional value labels
//! - Per-item styling
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const items = [_]DotPlotItem{
//!     .{ .label = "Item A", .value = 0.3 },
//!     .{ .label = "Item B", .value = 0.7 },
//! };
//!
//! const plot = DotPlot.init()
//!     .withItems(&items)
//!     .withXMin(0.0)
//!     .withXMax(1.0)
//!     .withShowLabels(true)
//!     .withShowValues(false);
//!
//! plot.render(&buf, area);
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

/// A single item in the dot plot
pub const DotPlotItem = struct {
    /// Label for the item
    label: []const u8 = "",
    /// Value (determines dot position on x axis)
    value: f32 = 0.0,
    /// Optional custom style for this item
    style: Style = .{},
};

pub const DotPlot = struct {
    /// Maximum number of items (capped at 64 for rendering)
    pub const MAX_ITEMS: usize = 64;

    /// Array of items to display
    items: []const DotPlotItem = &.{},
    /// Index of the focused item for highlighting
    focused: usize = 0,
    /// Minimum value for x-axis normalization
    x_min: f32 = 0.0,
    /// Maximum value for x-axis normalization
    x_max: f32 = 1.0,
    /// Whether to render labels
    show_labels: bool = true,
    /// Whether to render values after dots
    show_values: bool = false,
    /// Character to use for dots
    dot_char: u21 = '●',
    /// Base style applied to all elements
    style: Style = .{},
    /// Style for dots
    dot_style: Style = .{},
    /// Style for the focused item's dot
    focused_style: Style = .{},
    /// Style for labels
    label_style: Style = .{},
    /// Style for grid lines
    line_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a DotPlot with all defaults
    pub fn init() DotPlot {
        return .{};
    }

    /// Count of items to render (capped at MAX_ITEMS)
    pub fn itemCount(self: DotPlot) usize {
        return @min(self.items.len, MAX_ITEMS);
    }

    /// Set items array
    pub fn withItems(self: DotPlot, items: []const DotPlotItem) DotPlot {
        var result = self;
        result.items = items;
        return result;
    }

    /// Set focused item index
    pub fn withFocused(self: DotPlot, idx: usize) DotPlot {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set x_min for normalization
    pub fn withXMin(self: DotPlot, v: f32) DotPlot {
        var result = self;
        result.x_min = v;
        return result;
    }

    /// Set x_max for normalization
    pub fn withXMax(self: DotPlot, v: f32) DotPlot {
        var result = self;
        result.x_max = v;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: DotPlot, show: bool) DotPlot {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: DotPlot, show: bool) DotPlot {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set dot_char
    pub fn withDotChar(self: DotPlot, ch: u21) DotPlot {
        var result = self;
        result.dot_char = ch;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: DotPlot, s: Style) DotPlot {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set dot style
    pub fn withDotStyle(self: DotPlot, s: Style) DotPlot {
        var result = self;
        result.dot_style = s;
        return result;
    }

    /// Set focused style
    pub fn withFocusedStyle(self: DotPlot, s: Style) DotPlot {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: DotPlot, s: Style) DotPlot {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set line style
    pub fn withLineStyle(self: DotPlot, s: Style) DotPlot {
        var result = self;
        result.line_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: DotPlot, b: ?Block) DotPlot {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the dot plot to the buffer
    pub fn render(self: DotPlot, buf: *Buffer, area: Rect) void {
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

            // Compute dot x position
            const range = self.x_max - self.x_min;
            const dot_col = if (range == 0.0 or plot_width <= 1)
                0
            else blk: {
                const t = (item.value - self.x_min) / range;
                const t_clamped = @max(0.0, @min(1.0, t));
                break :blk @as(u16, @intFromFloat(@round(t_clamped * @as(f32, @floatFromInt(plot_width - 1)))));
            };

            const dot_abs_x = plot_x + dot_col;

            // Draw dashed line from plot_x to dot_col (exclusive)
            var col = plot_x;
            while (col < dot_abs_x and col < buf.width) : (col += 1) {
                buf.set(col, row_y, Cell.init('─', self.line_style));
            }

            // Draw dot
            var final_dot_style = self.dot_style;
            if (i == self.focused) {
                final_dot_style = self.focused_style;
            }
            if (dot_abs_x < buf.width) {
                buf.set(dot_abs_x, row_y, Cell.init(self.dot_char, final_dot_style));
            }

            // Draw value if enabled
            if (self.show_values) {
                drawValueLabel(buf, dot_abs_x, row_y, item.value, self.style);
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

    // Draw at dot_x + 1
    if (x + 1 < buf.width and y < buf.height) {
        buf.setString(x + 1, y, value_str[0..@min(str_len, 15)], style);
    }
}
