//! BubbleChart Widget — 2D variable-size bubble visualization
//!
//! BubbleChart displays data points as bubbles on a 2D plot with X-Y coordinates
//! and variable bubble sizes. Features include:
//! - Variable-size bubble rendering (5 marker sizes)
//! - X-Y range scaling
//! - Focused bubble highlighting
//! - Optional axes and labels
//! - MAX_BUBBLES capping (64)
//! - Builder pattern configuration
//!
//! ## Usage
//! ```zig
//! var bubbles = [_]BubbleChart.Bubble{
//!     .{ .label = "A", .x = 0.3, .y = 0.7, .size = 0.5 },
//!     .{ .label = "B", .x = 0.8, .y = 0.2, .size = 0.8 },
//! };
//!
//! const chart = BubbleChart.init()
//!     .withBubbles(&bubbles)
//!     .withXMin(0.0).withXMax(1.0)
//!     .withYMin(0.0).withYMax(1.0);
//!
//! chart.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Map bubble size to marker character
fn markerForSize(size: f32) []const u8 {
    if (size < 0.2) return "·"; // U+00B7 middle dot
    if (size < 0.4) return "•"; // U+2022 bullet
    if (size < 0.6) return "○"; // U+25CB white circle
    if (size < 0.8) return "◉"; // U+25C9 fisheye
    return "●"; // U+25CF black circle
}

pub const BubbleChart = struct {
    /// Bubble represents a single data point on the chart
    pub const Bubble = struct {
        label: []const u8 = "",
        x: f32 = 0.0,
        y: f32 = 0.0,
        size: f32 = 0.5,
        style: Style = .{},

        /// Initialize a new Bubble with default values
        pub fn init() Bubble {
            return .{};
        }

        /// Set bubble label (builder pattern)
        pub fn withLabel(self: Bubble, label: []const u8) Bubble {
            var result = self;
            result.label = label;
            return result;
        }

        /// Set bubble X coordinate (builder pattern)
        pub fn withX(self: Bubble, x: f32) Bubble {
            var result = self;
            result.x = x;
            return result;
        }

        /// Set bubble Y coordinate (builder pattern)
        pub fn withY(self: Bubble, y: f32) Bubble {
            var result = self;
            result.y = y;
            return result;
        }

        /// Set bubble size (builder pattern)
        pub fn withSize(self: Bubble, size: f32) Bubble {
            var result = self;
            result.size = size;
            return result;
        }

        /// Set bubble style (builder pattern)
        pub fn withStyle(self: Bubble, style: Style) Bubble {
            var result = self;
            result.style = style;
            return result;
        }
    };

    pub const MAX_BUBBLES: usize = 64;

    bubbles: []const Bubble = &.{},
    focused: usize = 0,
    x_min: f32 = 0.0,
    x_max: f32 = 1.0,
    y_min: f32 = 0.0,
    y_max: f32 = 1.0,
    show_labels: bool = true,
    show_axes: bool = true,
    style: Style = .{},
    bubble_style: Style = .{},
    focused_style: Style = .{ .fg = .{ .indexed = 3 } },
    axis_style: Style = .{ .fg = .{ .indexed = 8 } },
    block: ?Block = null,

    /// Initialize a new BubbleChart with default values
    pub fn init() BubbleChart {
        return .{};
    }

    /// Return the number of bubbles to render (capped at MAX_BUBBLES)
    pub fn bubbleCount(self: BubbleChart) usize {
        return @min(self.bubbles.len, MAX_BUBBLES);
    }

    /// Set bubbles (builder pattern)
    pub fn withBubbles(self: BubbleChart, bubbles: []const Bubble) BubbleChart {
        var result = self;
        result.bubbles = bubbles;
        return result;
    }

    /// Set focused bubble index (builder pattern)
    pub fn withFocused(self: BubbleChart, idx: usize) BubbleChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set x_min (builder pattern)
    pub fn withXMin(self: BubbleChart, min: f32) BubbleChart {
        var result = self;
        result.x_min = min;
        return result;
    }

    /// Set x_max (builder pattern)
    pub fn withXMax(self: BubbleChart, max: f32) BubbleChart {
        var result = self;
        result.x_max = max;
        return result;
    }

    /// Set y_min (builder pattern)
    pub fn withYMin(self: BubbleChart, min: f32) BubbleChart {
        var result = self;
        result.y_min = min;
        return result;
    }

    /// Set y_max (builder pattern)
    pub fn withYMax(self: BubbleChart, max: f32) BubbleChart {
        var result = self;
        result.y_max = max;
        return result;
    }

    /// Set show_labels (builder pattern)
    pub fn withShowLabels(self: BubbleChart, show: bool) BubbleChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_axes (builder pattern)
    pub fn withShowAxes(self: BubbleChart, show: bool) BubbleChart {
        var result = self;
        result.show_axes = show;
        return result;
    }

    /// Set base style (builder pattern)
    pub fn withStyle(self: BubbleChart, s: Style) BubbleChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set bubble style (builder pattern)
    pub fn withBubbleStyle(self: BubbleChart, s: Style) BubbleChart {
        var result = self;
        result.bubble_style = s;
        return result;
    }

    /// Set focused style (builder pattern)
    pub fn withFocusedStyle(self: BubbleChart, s: Style) BubbleChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set axis style (builder pattern)
    pub fn withAxisStyle(self: BubbleChart, s: Style) BubbleChart {
        var result = self;
        result.axis_style = s;
        return result;
    }

    /// Set optional block border (builder pattern)
    pub fn withBlock(self: BubbleChart, b: Block) BubbleChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the bubble chart to the buffer
    pub fn render(self: BubbleChart, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block border if present
        var render_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.width == 0 or render_area.height == 0) return;

        // Calculate axis dimensions
        const y_axis_width: u16 = if (self.show_axes) 6 else 0; // 5 chars for labels + 1 for │
        const x_axis_height: u16 = if (self.show_axes) 2 else 0; // 1 for ─ + 1 for label

        // Calculate plot area
        const plot_area = Rect{
            .x = render_area.x + y_axis_width,
            .y = render_area.y,
            .width = if (render_area.width > y_axis_width) render_area.width - y_axis_width else 0,
            .height = if (render_area.height > x_axis_height) render_area.height - x_axis_height else 0,
        };

        if (plot_area.width == 0 or plot_area.height == 0) return;

        // Render bubbles
        const n = self.bubbleCount();
        if (n == 0) return;

        // Render axes if enabled (only if there are bubbles)
        if (self.show_axes) {
            renderAxes(buf, render_area, plot_area, self);
        }

        // Check for degenerate x/y ranges
        if (self.x_max <= self.x_min or self.y_max <= self.y_min) return;

        const x_span = self.x_max - self.x_min;
        const y_span = self.y_max - self.y_min;

        for (0..n) |i| {
            const bubble = self.bubbles[i];

            // Normalize coordinates to [0, 1] range
            const norm_x = (bubble.x - self.x_min) / x_span;
            const norm_y = (bubble.y - self.y_min) / y_span;

            // Skip bubbles outside the range
            if (norm_x < 0.0 or norm_x > 1.0 or norm_y < 0.0 or norm_y > 1.0) continue;

            // Calculate screen position (y-axis inverted: y_min at bottom, y_max at top)
            const col = plot_area.x + @as(u16, @intFromFloat(norm_x * @as(f32, @floatFromInt(plot_area.width - 1))));
            const row = plot_area.y + @as(u16, @intFromFloat((1.0 - norm_y) * @as(f32, @floatFromInt(plot_area.height - 1))));

            // Bounds check
            if (col >= buf.width or row >= buf.height) continue;

            // Determine style
            const effective_style = if (i == self.focused)
                self.focused_style.merge(bubble.style)
            else
                self.bubble_style.merge(bubble.style);

            // Render marker
            const marker = markerForSize(bubble.size);
            buf.setString(col, row, marker, effective_style);

            // Render label if enabled
            if (self.show_labels and bubble.label.len > 0 and col + 1 < buf.width) {
                const label_start = col + 1;
                const label_max_len = @as(u16, @intCast(buf.width)) - label_start;
                const label_len = @min(bubble.label.len, label_max_len);

                for (0..label_len) |j| {
                    const label_col = label_start + @as(u16, @intCast(j));
                    if (label_col >= buf.width) break;
                    buf.set(label_col, row, Cell{
                        .char = bubble.label[j],
                        .style = effective_style,
                    });
                }
            }
        }
    }

    /// Render axes (Y-axis, X-axis, corner, and labels)
    fn renderAxes(buf: *Buffer, render_area: Rect, plot_area: Rect, self: BubbleChart) void {
        // Y-axis (vertical line at x = render_area.x + 5)
        const y_axis_x = render_area.x + 5;
        for (plot_area.y..@min(plot_area.y + plot_area.height, buf.height)) |y| {
            if (y_axis_x < buf.width) {
                buf.set(y_axis_x, @intCast(y), Cell{ .char = '│', .style = self.axis_style });
            }
        }

        // X-axis (horizontal line at y = plot_area.y + plot_area.height)
        const x_axis_y = plot_area.y + plot_area.height;
        if (x_axis_y < buf.height) {
            for (plot_area.x..@min(plot_area.x + plot_area.width, buf.width)) |x| {
                buf.set(@intCast(x), x_axis_y, Cell{ .char = '─', .style = self.axis_style });
            }
        }

        // Corner intersection (┼)
        if (y_axis_x < buf.width and x_axis_y < buf.height) {
            buf.set(y_axis_x, x_axis_y, Cell{ .char = '┼', .style = self.axis_style });
        }

        // Y-axis labels (min at bottom, max at top, mid in middle)
        var y_min_buf: [5]u8 = undefined;
        var y_max_buf: [5]u8 = undefined;
        var y_mid_buf: [5]u8 = undefined;

        formatF32Into(&y_min_buf, self.y_min);
        formatF32Into(&y_max_buf, self.y_max);
        const y_mid = (self.y_min + self.y_max) / 2.0;
        formatF32Into(&y_mid_buf, y_mid);

        // Max at top (y = plot_area.y)
        if (plot_area.y < buf.height and y_axis_x >= 5) {
            buf.setString(render_area.x, plot_area.y, &y_max_buf, self.axis_style);
        }

        // Mid in middle
        if (plot_area.y + plot_area.height / 2 < buf.height and y_axis_x >= 5) {
            buf.setString(render_area.x, plot_area.y + plot_area.height / 2, &y_mid_buf, self.axis_style);
        }

        // Min at bottom
        if (x_axis_y < buf.height and y_axis_x >= 5) {
            buf.setString(render_area.x, x_axis_y, &y_min_buf, self.axis_style);
        }

        // X-axis labels (min at left, max at right, mid in center)
        var x_min_buf: [5]u8 = undefined;
        var x_max_buf: [5]u8 = undefined;
        var x_mid_buf: [5]u8 = undefined;

        formatF32Into(&x_min_buf, self.x_min);
        formatF32Into(&x_max_buf, self.x_max);
        const x_mid = (self.x_min + self.x_max) / 2.0;
        formatF32Into(&x_mid_buf, x_mid);

        const label_row = x_axis_y + 1;
        if (label_row < buf.height) {
            // Min at left
            if (plot_area.x < buf.width) {
                buf.setString(plot_area.x, label_row, &x_min_buf, self.axis_style);
            }

            // Mid in center
            const mid_x = plot_area.x + plot_area.width / 2;
            if (mid_x < buf.width) {
                buf.setString(mid_x, label_row, &x_mid_buf, self.axis_style);
            }

            // Max at right
            if (plot_area.x + plot_area.width > 5 and plot_area.x + plot_area.width <= buf.width) {
                const max_x = plot_area.x + plot_area.width - 5;
                buf.setString(max_x, label_row, &x_max_buf, self.axis_style);
            }
        }
    }

    /// Format an f32 into a buffer (left-aligned, max 5 chars)
    fn formatF32Into(buffer: *[5]u8, value: f32) void {
        @memset(buffer, ' ');

        // Simple formatting: convert to integer for display
        const int_val: i32 = @intFromFloat(value);
        var str_buf: [16]u8 = undefined;
        const str = std.fmt.bufPrint(&str_buf, "{d}", .{int_val}) catch "0";

        const copy_len = @min(str.len, 5);
        @memcpy(buffer[0..copy_len], str[0..copy_len]);
    }
};
