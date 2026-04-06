//! ScatterPlot widget — X-Y coordinate plotting with markers
//!
//! Example usage:
//!
//! ```zig
//! const series = [_]ScatterPlot.Series{
//!     .{
//!         .name = "Group A",
//!         .points = &[_]ScatterPlot.Point{
//!             .{ .x = 1.0, .y = 2.0 },
//!             .{ .x = 2.0, .y = 3.5 },
//!             .{ .x = 3.0, .y = 1.5 },
//!         },
//!         .style = .{ .fg = .{ .indexed = 2 } },
//!         .marker = "●",
//!     },
//! };
//!
//! const chart = ScatterPlot.init(&series)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Scatter"))
//!     .withXAxisLabel("Time (s)")
//!     .withYAxisLabel("Value");
//!
//! chart.render(&buffer, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// ScatterPlot widget - X-Y coordinate plotting with markers
pub const ScatterPlot = struct {
    pub const Point = struct {
        x: f64,
        y: f64,
    };

    pub const Series = struct {
        name: []const u8,
        points: []const Point,
        style: Style = .{},
        marker: []const u8 = "•", // Default marker
    };

    series: []const Series,
    block: ?Block = null,
    x_axis_label: []const u8 = "",
    y_axis_label: []const u8 = "",
    min_x: ?f64 = null,
    max_x: ?f64 = null,
    min_y: ?f64 = null,
    max_y: ?f64 = null,
    show_legend: bool = true,
    show_axes: bool = true,
    legend_style: Style = .{},
    axis_style: Style = .{ .fg = .{ .indexed = 8 } }, // Dim gray

    /// Create a scatter plot with series
    pub fn init(series: []const Series) ScatterPlot {
        return .{ .series = series };
    }

    /// Set the block (border) for this scatter plot
    pub fn withBlock(self: ScatterPlot, new_block: Block) ScatterPlot {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set X-axis label
    pub fn withXAxisLabel(self: ScatterPlot, label: []const u8) ScatterPlot {
        var result = self;
        result.x_axis_label = label;
        return result;
    }

    /// Set Y-axis label
    pub fn withYAxisLabel(self: ScatterPlot, label: []const u8) ScatterPlot {
        var result = self;
        result.y_axis_label = label;
        return result;
    }

    /// Set minimum X value for scaling
    pub fn withMinX(self: ScatterPlot, min: f64) ScatterPlot {
        var result = self;
        result.min_x = min;
        return result;
    }

    /// Set maximum X value for scaling
    pub fn withMaxX(self: ScatterPlot, max: f64) ScatterPlot {
        var result = self;
        result.max_x = max;
        return result;
    }

    /// Set minimum Y value for scaling
    pub fn withMinY(self: ScatterPlot, min: f64) ScatterPlot {
        var result = self;
        result.min_y = min;
        return result;
    }

    /// Set maximum Y value for scaling
    pub fn withMaxY(self: ScatterPlot, max: f64) ScatterPlot {
        var result = self;
        result.max_y = max;
        return result;
    }

    /// Show or hide legend
    pub fn withShowLegend(self: ScatterPlot, show: bool) ScatterPlot {
        var result = self;
        result.show_legend = show;
        return result;
    }

    /// Show or hide axes
    pub fn withShowAxes(self: ScatterPlot, show: bool) ScatterPlot {
        var result = self;
        result.show_axes = show;
        return result;
    }

    /// Set legend style
    pub fn withLegendStyle(self: ScatterPlot, new_style: Style) ScatterPlot {
        var result = self;
        result.legend_style = new_style;
        return result;
    }

    /// Set axis style
    pub fn withAxisStyle(self: ScatterPlot, new_style: Style) ScatterPlot {
        var result = self;
        result.axis_style = new_style;
        return result;
    }

    /// Calculate min and max values across all series
    fn calcRange(series: []const Series) struct { min_x: f64, max_x: f64, min_y: f64, max_y: f64 } {
        if (series.len == 0) return .{ .min_x = 0, .max_x = 0, .min_y = 0, .max_y = 0 };

        var min_x_val: f64 = std.math.floatMax(f64);
        var max_x_val: f64 = -std.math.floatMax(f64);
        var min_y_val: f64 = std.math.floatMax(f64);
        var max_y_val: f64 = -std.math.floatMax(f64);

        for (series) |s| {
            for (s.points) |point| {
                if (point.x < min_x_val) min_x_val = point.x;
                if (point.x > max_x_val) max_x_val = point.x;
                if (point.y < min_y_val) min_y_val = point.y;
                if (point.y > max_y_val) max_y_val = point.y;
            }
        }

        if (min_x_val > max_x_val) return .{ .min_x = 0, .max_x = 0, .min_y = 0, .max_y = 0 };
        if (min_y_val > max_y_val) return .{ .min_x = 0, .max_x = 0, .min_y = 0, .max_y = 0 };

        return .{ .min_x = min_x_val, .max_x = max_x_val, .min_y = min_y_val, .max_y = max_y_val };
    }

    /// Render the scatter plot
    pub fn render(self: ScatterPlot, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.width == 0 or render_area.height == 0) return;
        if (self.series.len == 0) return;

        // Calculate ranges
        const auto_range = calcRange(self.series);
        const min_x = self.min_x orelse auto_range.min_x;
        const max_x = self.max_x orelse auto_range.max_x;
        const min_y = self.min_y orelse auto_range.min_y;
        const max_y = self.max_y orelse auto_range.max_y;

        if (max_x <= min_x or max_y <= min_y) return;

        // Reserve space for axes and labels
        const y_axis_width: u16 = if (self.show_axes) 8 else 0; // Space for Y-axis labels
        const x_axis_height: u16 = if (self.show_axes) 2 else 0; // X-axis + label
        const legend_height: u16 = if (self.show_legend and self.series.len > 0) 1 else 0;

        const plot_area = Rect{
            .x = render_area.x + y_axis_width,
            .y = render_area.y,
            .width = if (render_area.width > y_axis_width) render_area.width - y_axis_width else 0,
            .height = if (render_area.height > x_axis_height + legend_height)
                render_area.height - x_axis_height - legend_height
            else 0,
        };

        if (plot_area.width == 0 or plot_area.height == 0) return;

        // Draw Y-axis
        if (self.show_axes and y_axis_width > 0) {
            // Draw Y-axis line
            var y: u16 = plot_area.y;
            while (y < plot_area.y + plot_area.height) : (y += 1) {
                buf.setChar(render_area.x + y_axis_width - 1, y, '│', self.axis_style);
            }

            // Y-axis labels (min, mid, max)
            const label_buf_size = 8;
            var label_buf: [label_buf_size]u8 = undefined;

            // Max label (top)
            const max_label = std.fmt.bufPrint(&label_buf, "{d:.1}", .{max_y}) catch "---";
            const max_x_pos: u16 = if (render_area.x + y_axis_width > @as(u16, @intCast(max_label.len)))
                render_area.x + y_axis_width - @as(u16, @intCast(max_label.len)) - 1
            else render_area.x;
            buf.setString(max_x_pos, plot_area.y, max_label, self.axis_style);

            // Mid label
            const mid_y = (max_y + min_y) / 2.0;
            const mid_label = std.fmt.bufPrint(&label_buf, "{d:.1}", .{mid_y}) catch "---";
            const mid_y_pos = plot_area.y + plot_area.height / 2;
            const mid_x_pos = if (render_area.x + y_axis_width > @as(u16, @intCast(mid_label.len)))
                render_area.x + y_axis_width - @as(u16, @intCast(mid_label.len)) - 1
            else render_area.x;
            buf.setString(mid_x_pos, mid_y_pos, mid_label, self.axis_style);

            // Min label (bottom)
            const min_label = std.fmt.bufPrint(&label_buf, "{d:.1}", .{min_y}) catch "---";
            const min_y_pos = plot_area.y + plot_area.height - 1;
            const min_x_pos = if (render_area.x + y_axis_width > @as(u16, @intCast(min_label.len)))
                render_area.x + y_axis_width - @as(u16, @intCast(min_label.len)) - 1
            else render_area.x;
            buf.setString(min_x_pos, min_y_pos, min_label, self.axis_style);

            // Y-axis label (vertical text)
            if (self.y_axis_label.len > 0) {
                const label_y = plot_area.y + (plot_area.height / 2);
                buf.setString(render_area.x, label_y, self.y_axis_label, self.axis_style);
            }
        }

        // Draw X-axis
        if (self.show_axes and x_axis_height > 0) {
            // Draw X-axis line
            const x_axis_y = plot_area.y + plot_area.height;
            var x: u16 = plot_area.x;
            while (x < plot_area.x + plot_area.width) : (x += 1) {
                buf.setChar(x, x_axis_y, '─', self.axis_style);
            }

            // X-axis labels (min, mid, max)
            var label_buf: [8]u8 = undefined;

            // Min label (left)
            const min_x_label = std.fmt.bufPrint(&label_buf, "{d:.1}", .{min_x}) catch "---";
            buf.setString(plot_area.x, x_axis_y + 1, min_x_label, self.axis_style);

            // Mid label
            const mid_x = (max_x + min_x) / 2.0;
            const mid_x_label = std.fmt.bufPrint(&label_buf, "{d:.1}", .{mid_x}) catch "---";
            const mid_x_pos = plot_area.x + plot_area.width / 2;
            if (mid_x_pos + mid_x_label.len <= plot_area.x + plot_area.width) {
                buf.setString(mid_x_pos, x_axis_y + 1, mid_x_label, self.axis_style);
            }

            // Max label (right)
            const max_x_label = std.fmt.bufPrint(&label_buf, "{d:.1}", .{max_x}) catch "---";
            const max_x_pos = if (plot_area.x + plot_area.width > @as(u16, @intCast(max_x_label.len)))
                plot_area.x + plot_area.width - @as(u16, @intCast(max_x_label.len))
            else plot_area.x;
            buf.setString(max_x_pos, x_axis_y + 1, max_x_label, self.axis_style);

            // X-axis label
            if (self.x_axis_label.len > 0) {
                const label_x = plot_area.x + (plot_area.width / 2) - @as(u16, @intCast(@min(self.x_axis_label.len / 2, plot_area.width / 2)));
                buf.setString(label_x, x_axis_y + 1, self.x_axis_label, self.axis_style);
            }
        }

        // Plot points
        for (self.series) |s| {
            for (s.points) |point| {
                // Map point to screen coordinates with bounds clamping
                const x_range = max_x - min_x;
                const y_range = max_y - min_y;

                const x_norm = (point.x - min_x) / x_range;
                const y_norm = (point.y - min_y) / y_range;

                // Clamp to valid u16 range before casting
                const x_offset_f = @min(@max(x_norm * @as(f64, @floatFromInt(plot_area.width - 1)), 0), @as(f64, @floatFromInt(plot_area.width - 1)));
                const y_offset_f = @min(@max(y_norm * @as(f64, @floatFromInt(plot_area.height - 1)), 0), @as(f64, @floatFromInt(plot_area.height - 1)));

                const screen_x = plot_area.x + @as(u16, @intFromFloat(x_offset_f));
                const screen_y = plot_area.y + plot_area.height - 1 - @as(u16, @intFromFloat(y_offset_f));

                // Draw marker
                if (screen_x >= plot_area.x and screen_x < plot_area.x + plot_area.width and
                    screen_y >= plot_area.y and screen_y < plot_area.y + plot_area.height)
                {
                    // Use first character of marker
                    const marker_char = if (s.marker.len > 0)
                        std.unicode.utf8Decode(s.marker) catch '•'
                    else '•';
                    buf.setChar(screen_x, screen_y, marker_char, s.style);
                }
            }
        }

        // Draw legend
        if (self.show_legend and self.series.len > 0) {
            const legend_y = render_area.y + render_area.height - 1;
            var offset: u16 = 0;

            for (self.series) |s| {
                if (offset + s.name.len + 4 > render_area.width) break;

                // Draw marker
                const marker_char = if (s.marker.len > 0)
                    std.unicode.utf8Decode(s.marker) catch '•'
                else '•';
                buf.setChar(render_area.x + offset, legend_y, marker_char, s.style);
                offset += 2;

                // Draw name
                buf.setString(render_area.x + offset, legend_y, s.name, self.legend_style);
                offset += @intCast(s.name.len + 2);
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ScatterPlot.init" {
    const series = [_]ScatterPlot.Series{
        .{
            .name = "A",
            .points = &[_]ScatterPlot.Point{.{ .x = 1, .y = 2 }},
        },
    };
    const plot = ScatterPlot.init(&series);
    try std.testing.expectEqual(1, plot.series.len);
    try std.testing.expect(plot.show_legend);
    try std.testing.expect(plot.show_axes);
}

test "ScatterPlot.withBlock" {
    const series = [_]ScatterPlot.Series{
        .{ .name = "A", .points = &[_]ScatterPlot.Point{} },
    };
    const plot = ScatterPlot.init(&series).withBlock((Block{}));
    try std.testing.expect(plot.block != null);
}

test "ScatterPlot.withAxisLabels" {
    const series = [_]ScatterPlot.Series{
        .{ .name = "A", .points = &[_]ScatterPlot.Point{} },
    };
    const plot = ScatterPlot.init(&series)
        .withXAxisLabel("Time")
        .withYAxisLabel("Value");
    try std.testing.expectEqualStrings("Time", plot.x_axis_label);
    try std.testing.expectEqualStrings("Value", plot.y_axis_label);
}

test "ScatterPlot.withRange" {
    const series = [_]ScatterPlot.Series{
        .{ .name = "A", .points = &[_]ScatterPlot.Point{} },
    };
    const plot = ScatterPlot.init(&series)
        .withMinX(0)
        .withMaxX(100)
        .withMinY(-10)
        .withMaxY(10);
    try std.testing.expectEqual(0, plot.min_x.?);
    try std.testing.expectEqual(100, plot.max_x.?);
    try std.testing.expectEqual(-10, plot.min_y.?);
    try std.testing.expectEqual(10, plot.max_y.?);
}

test "ScatterPlot.withShowLegend" {
    const series = [_]ScatterPlot.Series{
        .{ .name = "A", .points = &[_]ScatterPlot.Point{} },
    };
    const plot = ScatterPlot.init(&series).withShowLegend(false);
    try std.testing.expect(!plot.show_legend);
}

test "ScatterPlot.withShowAxes" {
    const series = [_]ScatterPlot.Series{
        .{ .name = "A", .points = &[_]ScatterPlot.Point{} },
    };
    const plot = ScatterPlot.init(&series).withShowAxes(false);
    try std.testing.expect(!plot.show_axes);
}

test "ScatterPlot.calcRange single series" {
    const series = [_]ScatterPlot.Series{
        .{
            .name = "A",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 5 },
                .{ .x = 3, .y = 2 },
                .{ .x = 2, .y = 8 },
            },
        },
    };
    const range = ScatterPlot.calcRange(&series);
    try std.testing.expectEqual(1, range.min_x);
    try std.testing.expectEqual(3, range.max_x);
    try std.testing.expectEqual(2, range.min_y);
    try std.testing.expectEqual(8, range.max_y);
}

test "ScatterPlot.calcRange multiple series" {
    const series = [_]ScatterPlot.Series{
        .{
            .name = "A",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 5 },
                .{ .x = 3, .y = 2 },
            },
        },
        .{
            .name = "B",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 0, .y = 10 },
                .{ .x = 5, .y = 1 },
            },
        },
    };
    const range = ScatterPlot.calcRange(&series);
    try std.testing.expectEqual(0, range.min_x);
    try std.testing.expectEqual(5, range.max_x);
    try std.testing.expectEqual(1, range.min_y);
    try std.testing.expectEqual(10, range.max_y);
}

test "ScatterPlot.render empty" {
    const series = [_]ScatterPlot.Series{};
    const plot = ScatterPlot.init(&series);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    plot.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // Should not crash with empty series
}

test "ScatterPlot.render with data" {
    const series = [_]ScatterPlot.Series{
        .{
            .name = "Group A",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 2 },
                .{ .x = 2, .y = 4 },
                .{ .x = 3, .y = 3 },
            },
            .style = .{ .fg = .{ .indexed = 2 } },
        },
    };
    const plot = ScatterPlot.init(&series);

    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    plot.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 15 });

    // Verify some markers were plotted (check for '•' in buffer)
    var found = false;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '•') {
                found = true;
                break;
            }
        }
        if (found) break;
    }
    try std.testing.expect(found);
}

test "ScatterPlot.render with block" {
    const series = [_]ScatterPlot.Series{
        .{
            .name = "Test",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 1 },
            },
        },
    };
    const plot = ScatterPlot.init(&series)
        .withBlock((Block{}).withBorders(.all).withTitle("Scatter"));

    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    plot.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 15 });

    // Check for title
    const title_cell = buf.get(1, 0);
    try std.testing.expectEqual('S', title_cell.char);
}

test "ScatterPlot.render zero-size area" {
    const series = [_]ScatterPlot.Series{
        .{ .name = "A", .points = &[_]ScatterPlot.Point{.{ .x = 1, .y = 1 }} },
    };
    const plot = ScatterPlot.init(&series);

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    plot.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "ScatterPlot.render with axes disabled" {
    const series = [_]ScatterPlot.Series{
        .{
            .name = "NoAxes",
            .points = &[_]ScatterPlot.Point{
                .{ .x = 1, .y = 2 },
            },
        },
    };
    const plot = ScatterPlot.init(&series).withShowAxes(false);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    plot.render(&buf, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Verify no axis characters ('│', '─')
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            try std.testing.expect(cell.char != '│');
            try std.testing.expect(cell.char != '─');
        }
    }
}
