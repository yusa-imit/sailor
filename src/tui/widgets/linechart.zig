//! LineChart widget — line chart with axis labels and multiple series
//!
//! Example usage:
//!
//! ```zig
//! const series = [_]LineChart.Series{
//!     .{ .name = "CPU", .data = &[_]f64{ 10, 20, 15, 30, 25 }, .style = .{ .fg = .{ .indexed = 2 } } },
//!     .{ .name = "Memory", .data = &[_]f64{ 5, 15, 10, 25, 20 }, .style = .{ .fg = .{ .indexed = 4 } } },
//! };
//!
//! const chart = LineChart.init(&series)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Metrics"))
//!     .withXLabels(&[_][]const u8{ "00:00", "00:15", "00:30", "00:45", "01:00" })
//!     .withYAxisLabel("Usage %");
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

/// LineChart widget - line chart with axes and multiple series
pub const LineChart = struct {
    pub const Series = struct {
        name: []const u8,
        data: []const f64,
        style: Style = .{},
        marker: []const u8 = "•", // Default marker for data points
    };

    series: []const Series,
    block: ?Block = null,
    x_labels: []const []const u8 = &.{},
    y_axis_label: []const u8 = "",
    x_axis_label: []const u8 = "",
    min_y: ?f64 = null,
    max_y: ?f64 = null,
    show_legend: bool = true,
    show_axes: bool = true,
    legend_style: Style = .{},
    axis_style: Style = .{ .fg = .{ .indexed = 8 } }, // Dim gray

    /// Create a line chart with series
    pub fn init(series: []const Series) LineChart {
        return .{ .series = series };
    }

    /// Set the block (border) for this line chart
    pub fn withBlock(self: LineChart, new_block: Block) LineChart {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set X-axis labels
    pub fn withXLabels(self: LineChart, labels: []const []const u8) LineChart {
        var result = self;
        result.x_labels = labels;
        return result;
    }

    /// Set Y-axis label
    pub fn withYAxisLabel(self: LineChart, label: []const u8) LineChart {
        var result = self;
        result.y_axis_label = label;
        return result;
    }

    /// Set X-axis label
    pub fn withXAxisLabel(self: LineChart, label: []const u8) LineChart {
        var result = self;
        result.x_axis_label = label;
        return result;
    }

    /// Set minimum Y value for scaling
    pub fn withMinY(self: LineChart, min: f64) LineChart {
        var result = self;
        result.min_y = min;
        return result;
    }

    /// Set maximum Y value for scaling
    pub fn withMaxY(self: LineChart, max: f64) LineChart {
        var result = self;
        result.max_y = max;
        return result;
    }

    /// Show or hide legend
    pub fn withShowLegend(self: LineChart, show: bool) LineChart {
        var result = self;
        result.show_legend = show;
        return result;
    }

    /// Show or hide axes
    pub fn withShowAxes(self: LineChart, show: bool) LineChart {
        var result = self;
        result.show_axes = show;
        return result;
    }

    /// Set legend style
    pub fn withLegendStyle(self: LineChart, new_style: Style) LineChart {
        var result = self;
        result.legend_style = new_style;
        return result;
    }

    /// Set axis style
    pub fn withAxisStyle(self: LineChart, new_style: Style) LineChart {
        var result = self;
        result.axis_style = new_style;
        return result;
    }

    /// Calculate min and max Y values across all series
    fn calcYRange(series: []const Series) struct { min: f64, max: f64 } {
        if (series.len == 0) return .{ .min = 0, .max = 0 };

        var min_val: f64 = std.math.floatMax(f64);
        var max_val: f64 = -std.math.floatMax(f64);

        for (series) |s| {
            for (s.data) |val| {
                if (val < min_val) min_val = val;
                if (val > max_val) max_val = val;
            }
        }

        if (min_val > max_val) return .{ .min = 0, .max = 0 };
        return .{ .min = min_val, .max = max_val };
    }

    /// Get max data length across all series
    fn maxDataLen(series: []const Series) usize {
        var max_len: usize = 0;
        for (series) |s| {
            if (s.data.len > max_len) max_len = s.data.len;
        }
        return max_len;
    }

    /// Scale Y value to pixel row
    fn scaleY(value: f64, min: f64, max: f64, height: usize) usize {
        if (max == min) return height / 2;
        const range = max - min;
        const normalized = (value - min) / range;
        const scaled = normalized * @as(f64, @floatFromInt(height - 1));
        const row = @as(usize, @intFromFloat(scaled));
        // Invert because Y=0 is top of screen
        return height - 1 - @min(row, height - 1);
    }

    /// Render Y-axis with labels
    fn renderYAxis(self: LineChart, buf: *Buffer, area: Rect, min: f64, max: f64) void {
        if (area.width < 6 or area.height < 3) return;

        const y_label_width: u16 = 5; // Space for value labels like "99.9"

        // Draw Y-axis line
        for (0..area.height) |dy| {
            buf.setCell(area.x + y_label_width, area.y + @as(u16, @intCast(dy)), '│', self.axis_style);
        }

        // Draw Y-axis labels (top, middle, bottom)
        var label_buf: [16]u8 = undefined;

        // Top label (max)
        const top_label = std.fmt.bufPrint(&label_buf, "{d:5.1}", .{max}) catch "  max";
        buf.setString(area.x, area.y, top_label, self.axis_style);

        // Middle label
        if (area.height > 4) {
            const mid = (max + min) / 2;
            const mid_label = std.fmt.bufPrint(&label_buf, "{d:5.1}", .{mid}) catch "  mid";
            buf.setString(area.x, area.y + area.height / 2, mid_label, self.axis_style);
        }

        // Bottom label (min)
        const bottom_label = std.fmt.bufPrint(&label_buf, "{d:5.1}", .{min}) catch "  min";
        buf.setString(area.x, area.y + area.height - 1, bottom_label, self.axis_style);

        // Draw Y-axis label vertically if provided
        if (self.y_axis_label.len > 0 and area.height > self.y_axis_label.len) {
            const start_y = area.y + (area.height - @as(u16, @intCast(self.y_axis_label.len))) / 2;
            for (self.y_axis_label, 0..) |c, i| {
                buf.setCell(area.x, start_y + @as(u16, @intCast(i)), c, self.axis_style);
            }
        }
    }

    /// Render X-axis with labels
    fn renderXAxis(self: LineChart, buf: *Buffer, area: Rect, data_len: usize) void {
        if (area.width < 2 or area.height < 1) return;

        // Draw X-axis line
        for (0..area.width) |dx| {
            buf.setCell(area.x + @as(u16, @intCast(dx)), area.y, '─', self.axis_style);
        }

        // Draw X-axis labels
        if (self.x_labels.len > 0 and data_len > 0) {
            const label_count = @min(self.x_labels.len, data_len);
            for (0..label_count) |i| {
                const x_pos = (i * area.width) / @max(data_len - 1, 1);
                if (x_pos < area.width) {
                    const label = self.x_labels[i];
                    const label_x = area.x + @as(u16, @intCast(x_pos));
                    if (label_x + @as(u16, @intCast(label.len)) <= area.x + area.width) {
                        buf.setString(label_x, area.y + 1, label, self.axis_style);
                    }
                }
            }
        }

        // Draw X-axis label centered below
        if (self.x_axis_label.len > 0 and area.width > self.x_axis_label.len and area.height > 2) {
            const label_x = area.x + (area.width - @as(u16, @intCast(self.x_axis_label.len))) / 2;
            buf.setString(label_x, area.y + area.height - 1, self.x_axis_label, self.axis_style);
        }
    }

    /// Render legend
    fn renderLegend(self: LineChart, buf: *Buffer, area: Rect) void {
        if (area.height < 1 or area.width < 2) return;

        var x_offset: u16 = area.x;
        for (self.series) |s| {
            if (x_offset >= area.x + area.width) break;

            // Render marker
            const marker_cp = std.unicode.utf8Decode(s.marker) catch ' ';
            buf.setCell(x_offset, area.y, marker_cp, s.style);
            x_offset += 1;

            // Render name
            if (x_offset < area.x + area.width) {
                buf.setString(x_offset, area.y, s.name, self.legend_style);
                x_offset += @intCast(s.name.len + 2); // Add spacing
            }
        }
    }

    /// Render a single data series as a line
    fn renderSeries(_: LineChart, buf: *Buffer, area: Rect, series: Series, min: f64, max: f64) void {
        if (series.data.len == 0 or area.width == 0 or area.height == 0) return;

        const data_len = series.data.len;
        const width = area.width;
        const height = area.height;

        // Plot points and connect with lines
        for (0..data_len) |i| {
            const value = series.data[i];
            const x_pos = if (data_len > 1) (i * width) / (data_len - 1) else width / 2;
            const y_pos = scaleY(value, min, max, height);

            if (x_pos < width and y_pos < height) {
                const px = area.x + @as(u16, @intCast(x_pos));
                const py = area.y + @as(u16, @intCast(y_pos));

                // Draw marker at data point
                const marker_cp = std.unicode.utf8Decode(series.marker) catch '•';
                buf.setCell(px, py, marker_cp, series.style);

                // Connect to previous point with line
                if (i > 0) {
                    const prev_x = if (data_len > 1) ((i - 1) * width) / (data_len - 1) else width / 2;
                    const prev_y = scaleY(series.data[i - 1], min, max, height);

                    drawLine(buf, area.x, area.y, @intCast(prev_x), @intCast(prev_y), @intCast(x_pos), @intCast(y_pos), series.style);
                }
            }
        }
    }

    /// Draw a line between two points using Bresenham's algorithm
    fn drawLine(buf: *Buffer, area_x: u16, area_y: u16, x0: usize, y0: usize, x1: usize, y1: usize, line_style: Style) void {
        const dx_signed = @as(i32, @intCast(x1)) - @as(i32, @intCast(x0));
        const dy_signed = @as(i32, @intCast(y1)) - @as(i32, @intCast(y0));
        const dx = @abs(dx_signed);
        const dy = @abs(dy_signed);
        const sx: i32 = if (dx_signed > 0) 1 else -1;
        const sy: i32 = if (dy_signed > 0) 1 else -1;

        var err = dx - dy;
        var x = @as(i32, @intCast(x0));
        var y = @as(i32, @intCast(y0));

        while (true) {
            // Plot point
            if (x >= 0 and y >= 0) {
                const px = area_x + @as(u16, @intCast(x));
                const py = area_y + @as(u16, @intCast(y));
                buf.setCell(px, py, '·', line_style);
            }

            if (x == @as(i32, @intCast(x1)) and y == @as(i32, @intCast(y1))) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    /// Render the line chart widget
    pub fn render(self: LineChart, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0 or self.series.len == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Reserve space for legend at top
        var chart_area = inner_area;
        if (self.show_legend and inner_area.height > 1) {
            renderLegend(self, buf, .{
                .x = inner_area.x,
                .y = inner_area.y,
                .width = inner_area.width,
                .height = 1,
            });
            chart_area.y += 1;
            chart_area.height -|= 1;
        }

        if (chart_area.height < 3 or chart_area.width < 10) return;

        // Calculate Y range
        const y_range = calcYRange(self.series);
        const min_y = self.min_y orelse y_range.min;
        const max_y = self.max_y orelse y_range.max;

        // Reserve space for Y-axis
        var plot_area = chart_area;
        if (self.show_axes) {
            const y_axis_width: u16 = 6; // 5 for labels + 1 for axis line
            renderYAxis(self, buf, .{
                .x = chart_area.x,
                .y = chart_area.y,
                .width = y_axis_width,
                .height = chart_area.height -| 3, // Reserve 3 rows for X-axis
            }, min_y, max_y);
            plot_area.x += y_axis_width;
            plot_area.width -|= y_axis_width;
        }

        // Reserve space for X-axis at bottom
        if (self.show_axes and plot_area.height > 3) {
            const x_axis_height: u16 = 3; // axis line + labels + x-axis label
            renderXAxis(self, buf, .{
                .x = plot_area.x,
                .y = plot_area.y + plot_area.height - x_axis_height,
                .width = plot_area.width,
                .height = x_axis_height,
            }, maxDataLen(self.series));
            plot_area.height -|= x_axis_height;
        }

        if (plot_area.width == 0 or plot_area.height == 0) return;

        // Render each series
        for (self.series) |series| {
            renderSeries(self, buf, plot_area, series, min_y, max_y);
        }
    }
};

// Tests
const testing = std.testing;

test "LineChart.init" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series);
    try testing.expectEqual(1, chart.series.len);
    try testing.expect(chart.show_legend);
    try testing.expect(chart.show_axes);
}

test "LineChart.withBlock" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const block = (Block{}).withTitle("Chart");
    const chart = LineChart.init(&series).withBlock(block);
    try testing.expect(chart.block != null);
}

test "LineChart.withXLabels" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const labels = [_][]const u8{ "A", "B" };
    const chart = LineChart.init(&series).withXLabels(&labels);
    try testing.expectEqual(2, chart.x_labels.len);
}

test "LineChart.withYAxisLabel" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withYAxisLabel("Value");
    try testing.expectEqualStrings("Value", chart.y_axis_label);
}

test "LineChart.withXAxisLabel" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withXAxisLabel("Time");
    try testing.expectEqualStrings("Time", chart.x_axis_label);
}

test "LineChart.withMinY" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withMinY(0.0);
    try testing.expectEqual(0.0, chart.min_y.?);
}

test "LineChart.withMaxY" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withMaxY(100.0);
    try testing.expectEqual(100.0, chart.max_y.?);
}

test "LineChart.withShowLegend" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withShowLegend(false);
    try testing.expect(!chart.show_legend);
}

test "LineChart.withShowAxes" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withShowAxes(false);
    try testing.expect(!chart.show_axes);
}

test "LineChart.withLegendStyle" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const style = Style{ .bold = true };
    const chart = LineChart.init(&series).withLegendStyle(style);
    try testing.expect(chart.legend_style.bold);
}

test "LineChart.withAxisStyle" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const style = Style{ .fg = .{ .indexed = 5 } };
    const chart = LineChart.init(&series).withAxisStyle(style);
    try testing.expectEqual(Color{ .indexed = 5 }, chart.axis_style.fg.?);
}

test "LineChart.calcYRange empty" {
    const series = [_]LineChart.Series{};
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(0.0, range.min);
    try testing.expectEqual(0.0, range.max);
}

test "LineChart.calcYRange single value" {
    const data = [_]f64{42.0};
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(42.0, range.min);
    try testing.expectEqual(42.0, range.max);
}

test "LineChart.calcYRange multiple values" {
    const data = [_]f64{ 10.0, 20.0, 5.0, 30.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(5.0, range.min);
    try testing.expectEqual(30.0, range.max);
}

test "LineChart.calcYRange multiple series" {
    const data1 = [_]f64{ 10.0, 20.0 };
    const data2 = [_]f64{ 5.0, 30.0 };
    const series = [_]LineChart.Series{
        .{ .name = "A", .data = &data1 },
        .{ .name = "B", .data = &data2 },
    };
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(5.0, range.min);
    try testing.expectEqual(30.0, range.max);
}

test "LineChart.maxDataLen empty" {
    const series = [_]LineChart.Series{};
    try testing.expectEqual(0, LineChart.maxDataLen(&series));
}

test "LineChart.maxDataLen single series" {
    const data = [_]f64{ 1.0, 2.0, 3.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    try testing.expectEqual(3, LineChart.maxDataLen(&series));
}

test "LineChart.maxDataLen multiple series" {
    const data1 = [_]f64{ 1.0, 2.0 };
    const data2 = [_]f64{ 1.0, 2.0, 3.0, 4.0 };
    const series = [_]LineChart.Series{
        .{ .name = "A", .data = &data1 },
        .{ .name = "B", .data = &data2 },
    };
    try testing.expectEqual(4, LineChart.maxDataLen(&series));
}

test "LineChart.scaleY basic" {
    const height: usize = 10;
    try testing.expectEqual(0, LineChart.scaleY(100.0, 0.0, 100.0, height)); // max -> top
    try testing.expectEqual(9, LineChart.scaleY(0.0, 0.0, 100.0, height)); // min -> bottom
    try testing.expectEqual(5, LineChart.scaleY(50.0, 0.0, 100.0, height)); // mid -> middle
}

test "LineChart.scaleY same min and max" {
    const height: usize = 10;
    try testing.expectEqual(5, LineChart.scaleY(42.0, 42.0, 42.0, height));
}

test "LineChart.render empty area" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{1.0};
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "LineChart.render empty series" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit(testing.allocator);

    const series = [_]LineChart.Series{};
    const chart = LineChart.init(&series);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    // Should not crash
}

test "LineChart.render single point" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{50.0};
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });
    // Should render without crashing
}

test "LineChart.render multiple points" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0, 15.0, 30.0, 25.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data, .style = .{ .fg = .{ .indexed = 2 } } },
    };
    const chart = LineChart.init(&series);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should render line connecting points
}

test "LineChart.render multiple series" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data1 = [_]f64{ 10.0, 20.0, 15.0 };
    const data2 = [_]f64{ 5.0, 25.0, 10.0 };
    const series = [_]LineChart.Series{
        .{ .name = "A", .data = &data1, .style = .{ .fg = .{ .indexed = 2 } } },
        .{ .name = "B", .data = &data2, .style = .{ .fg = .{ .indexed = 4 } } },
    };
    const chart = LineChart.init(&series);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should render both series
}

test "LineChart.render with block" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const block = (Block{}).withBorders(.all).withTitle("Chart");
    const chart = LineChart.init(&series).withBlock(block);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should render chart inside block
}

test "LineChart.render with x labels" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const labels = [_][]const u8{ "A", "B", "C" };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series).withXLabels(&labels);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should render with X-axis labels
}

test "LineChart.render with axis labels" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series)
        .withYAxisLabel("Val")
        .withXAxisLabel("Time");

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should render with axis labels
}

test "LineChart.render without legend" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series).withShowLegend(false);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should render without legend
}

test "LineChart.render without axes" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series).withShowAxes(false);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should render without axes
}

test "LineChart.render with custom min/max" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series).withMinY(0.0).withMaxY(50.0);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should scale with custom range
}

test "LineChart.render small area" {
    var buf = try Buffer.init(testing.allocator, 5, 3);
    defer buf.deinit(testing.allocator);

    const data = [_]f64{ 10.0, 20.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart = LineChart.init(&series);

    chart.render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 3 });
    // Should handle gracefully
}
