//! TimeSeriesChart widget — time-based line chart with axis labels
//!
//! Example usage:
//!
//! ```zig
//! const allocator = std.heap.page_allocator;
//! const timestamps = [_]i64{ 1700000000, 1700003600, 1700007200 }; // Unix timestamps
//! const data = [_]f64{ 10.5, 15.2, 12.8 };
//!
//! const chart = try TimeSeriesChart.init(allocator, &timestamps, &data)
//!     .withBlock(Block.init().withBorders(.all).withTitle("CPU Usage"))
//!     .withYAxisLabel("Percent")
//!     .withTimeFormat(.hour_minute);
//!
//! chart.render(&buffer, area);
//! chart.deinit();
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

/// TimeSeriesChart widget - time-based line chart with axis labels
pub const TimeSeriesChart = struct {
    pub const TimeFormat = enum {
        unix, // Raw Unix timestamp
        hour_minute, // HH:MM
        date_time, // MM/DD HH:MM
        iso8601, // YYYY-MM-DD HH:MM:SS
    };

    allocator: std.mem.Allocator,
    timestamps: []const i64, // Unix timestamps
    values: []const f64,
    block: ?Block = null,
    y_axis_label: []const u8 = "",
    min_y: ?f64 = null,
    max_y: ?f64 = null,
    line_style: Style = .{ .fg = .{ .indexed = 2 } }, // Green
    axis_style: Style = .{ .fg = .{ .indexed = 8 } }, // Dim gray
    time_format: TimeFormat = .hour_minute,
    show_points: bool = true,
    point_char: u21 = '●',

    /// Create a time series chart (caller owns lifetime, must call deinit)
    pub fn init(allocator: std.mem.Allocator, timestamps: []const i64, values: []const f64) !TimeSeriesChart {
        if (timestamps.len != values.len) return error.MismatchedArrayLengths;
        return .{
            .allocator = allocator,
            .timestamps = timestamps,
            .values = values,
        };
    }

    /// Free resources
    pub fn deinit(self: *TimeSeriesChart) void {
        _ = self;
        // Currently no dynamic allocations, but keeping for future extensions
    }

    /// Set the block (border) for this chart
    pub fn withBlock(self: TimeSeriesChart, new_block: Block) TimeSeriesChart {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set Y-axis label
    pub fn withYAxisLabel(self: TimeSeriesChart, label: []const u8) TimeSeriesChart {
        var result = self;
        result.y_axis_label = label;
        return result;
    }

    /// Set minimum Y value for scaling
    pub fn withMinY(self: TimeSeriesChart, min: f64) TimeSeriesChart {
        var result = self;
        result.min_y = min;
        return result;
    }

    /// Set maximum Y value for scaling
    pub fn withMaxY(self: TimeSeriesChart, max: f64) TimeSeriesChart {
        var result = self;
        result.max_y = max;
        return result;
    }

    /// Set line style
    pub fn withLineStyle(self: TimeSeriesChart, new_style: Style) TimeSeriesChart {
        var result = self;
        result.line_style = new_style;
        return result;
    }

    /// Set axis style
    pub fn withAxisStyle(self: TimeSeriesChart, new_style: Style) TimeSeriesChart {
        var result = self;
        result.axis_style = new_style;
        return result;
    }

    /// Set time format for X-axis labels
    pub fn withTimeFormat(self: TimeSeriesChart, format: TimeFormat) TimeSeriesChart {
        var result = self;
        result.time_format = format;
        return result;
    }

    /// Show or hide data points
    pub fn withShowPoints(self: TimeSeriesChart, show: bool) TimeSeriesChart {
        var result = self;
        result.show_points = show;
        return result;
    }

    /// Set point marker character
    pub fn withPointChar(self: TimeSeriesChart, char: u21) TimeSeriesChart {
        var result = self;
        result.point_char = char;
        return result;
    }

    /// Calculate min and max Y values
    fn calcYRange(values: []const f64) struct { min: f64, max: f64 } {
        if (values.len == 0) return .{ .min = 0, .max = 0 };

        var min_val: f64 = std.math.floatMax(f64);
        var max_val: f64 = -std.math.floatMax(f64);

        for (values) |val| {
            if (val < min_val) min_val = val;
            if (val > max_val) max_val = val;
        }

        if (min_val > max_val) return .{ .min = 0, .max = 0 };
        return .{ .min = min_val, .max = max_val };
    }

    /// Format a Unix timestamp according to the time format
    fn formatTimestamp(timestamp: i64, format: TimeFormat, buf: []u8) ![]const u8 {
        const secs: u64 = @intCast(@max(0, timestamp));
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = secs };
        const day_seconds = epoch_seconds.getDaySeconds();
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        const hour = day_seconds.getHoursIntoDay();
        const minute = day_seconds.getMinutesIntoHour();
        const second = day_seconds.getSecondsIntoMinute();

        return switch (format) {
            .unix => std.fmt.bufPrint(buf, "{d}", .{timestamp}),
            .hour_minute => std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}", .{ hour, minute }),
            .date_time => std.fmt.bufPrint(buf, "{d:0>2}/{d:0>2} {d:0>2}:{d:0>2}", .{
                month_day.month.numeric(),
                month_day.day_index + 1,
                hour,
                minute,
            }),
            .iso8601 => std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                hour,
                minute,
                second,
            }),
        };
    }

    /// Render the time series chart
    pub fn render(self: TimeSeriesChart, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.width == 0 or render_area.height == 0) return;
        if (self.timestamps.len == 0 or self.values.len == 0) return;

        // Calculate Y range
        const auto_range = calcYRange(self.values);
        const min_y = self.min_y orelse auto_range.min;
        const max_y = self.max_y orelse auto_range.max;

        if (max_y <= min_y) return;

        // Reserve space for axes
        const y_axis_width: u16 = 8; // Space for Y-axis labels
        const x_axis_height: u16 = 2; // X-axis + labels

        const plot_area = Rect{
            .x = render_area.x + y_axis_width,
            .y = render_area.y,
            .width = if (render_area.width > y_axis_width) render_area.width - y_axis_width else 0,
            .height = if (render_area.height > x_axis_height) render_area.height - x_axis_height else 0,
        };

        if (plot_area.width == 0 or plot_area.height == 0) return;

        // Draw Y-axis
        var y: u16 = plot_area.y;
        while (y < plot_area.y + plot_area.height) : (y += 1) {
            buf.setChar(render_area.x + y_axis_width - 1, y, '│', self.axis_style);
        }

        // Y-axis labels
        var label_buf: [16]u8 = undefined;

        // Max label (top)
        const max_label = std.fmt.bufPrint(&label_buf, "{d:.1}", .{max_y}) catch "---";
        const max_x_pos = if (render_area.x + y_axis_width > @as(u16, @intCast(max_label.len)))
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

        // Y-axis label
        if (self.y_axis_label.len > 0) {
            const label_y = plot_area.y + (plot_area.height / 2);
            buf.setString(render_area.x, label_y, self.y_axis_label, self.axis_style);
        }

        // Draw X-axis
        const x_axis_y = plot_area.y + plot_area.height;
        var x: u16 = plot_area.x;
        while (x < plot_area.x + plot_area.width) : (x += 1) {
            buf.setChar(x, x_axis_y, '─', self.axis_style);
        }

        // X-axis time labels (start, mid, end)
        var time_buf: [32]u8 = undefined;

        // Start time
        const start_time = formatTimestamp(self.timestamps[0], self.time_format, &time_buf) catch "---";
        buf.setString(plot_area.x, x_axis_y + 1, start_time, self.axis_style);

        // Mid time
        if (self.timestamps.len > 1) {
            const mid_idx = self.timestamps.len / 2;
            const mid_time = formatTimestamp(self.timestamps[mid_idx], self.time_format, &time_buf) catch "---";
            const mid_time_x = plot_area.x + plot_area.width / 2;
            if (mid_time_x + mid_time.len <= plot_area.x + plot_area.width) {
                buf.setString(mid_time_x, x_axis_y + 1, mid_time, self.axis_style);
            }
        }

        // End time
        const end_time = formatTimestamp(self.timestamps[self.timestamps.len - 1], self.time_format, &time_buf) catch "---";
        const end_x_pos = if (plot_area.x + plot_area.width > @as(u16, @intCast(end_time.len)))
            plot_area.x + plot_area.width - @as(u16, @intCast(end_time.len))
        else plot_area.x;
        buf.setString(end_x_pos, x_axis_y + 1, end_time, self.axis_style);

        // Plot data points and lines
        if (self.timestamps.len == 0) return;

        const min_time = self.timestamps[0];
        const max_time = self.timestamps[self.timestamps.len - 1];
        if (max_time <= min_time) return;

        const time_range = @as(f64, @floatFromInt(max_time - min_time));
        const y_range = max_y - min_y;

        var prev_screen_x: ?u16 = null;
        var prev_screen_y: ?u16 = null;

        for (self.timestamps, self.values) |timestamp, value| {
            // Map to screen coordinates
            const x_norm = @as(f64, @floatFromInt(timestamp - min_time)) / time_range;
            const y_norm = (value - min_y) / y_range;

            const screen_x = plot_area.x + @as(u16, @intFromFloat(x_norm * @as(f64, @floatFromInt(plot_area.width - 1))));
            const screen_y = plot_area.y + plot_area.height - 1 - @as(u16, @intFromFloat(y_norm * @as(f64, @floatFromInt(plot_area.height - 1))));

            if (screen_x >= plot_area.x and screen_x < plot_area.x + plot_area.width and
                screen_y >= plot_area.y and screen_y < plot_area.y + plot_area.height)
            {
                // Draw line from previous point
                if (prev_screen_x != null and prev_screen_y != null) {
                    const px = prev_screen_x.?;
                    const py = prev_screen_y.?;

                    // Simple line drawing (connect points with line chars)
                    const dx = @as(i32, screen_x) - @as(i32, px);
                    const dy = @as(i32, screen_y) - @as(i32, py);

                    if (dx == 0 and dy == 0) {
                        // Same point, skip
                    } else if (dx == 0) {
                        // Vertical line
                        const start_y = @min(py, screen_y);
                        const end_y = @max(py, screen_y);
                        var line_y = start_y;
                        while (line_y <= end_y) : (line_y += 1) {
                            buf.setChar(px, line_y, '│', self.line_style);
                        }
                    } else if (dy == 0) {
                        // Horizontal line
                        const start_x = @min(px, screen_x);
                        const end_x = @max(px, screen_x);
                        var line_x = start_x;
                        while (line_x <= end_x) : (line_x += 1) {
                            buf.setChar(line_x, py, '─', self.line_style);
                        }
                    } else {
                        // Diagonal line (simple bresenham approximation)
                        const steps = @max(@abs(dx), @abs(dy));
                        var i: i32 = 0;
                        while (i <= steps) : (i += 1) {
                            const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
                            const interp_x = @as(u16, @intFromFloat(@as(f64, @floatFromInt(px)) + t * @as(f64, @floatFromInt(dx))));
                            const interp_y = @as(u16, @intFromFloat(@as(f64, @floatFromInt(py)) + t * @as(f64, @floatFromInt(dy))));

                            if (interp_x >= plot_area.x and interp_x < plot_area.x + plot_area.width and
                                interp_y >= plot_area.y and interp_y < plot_area.y + plot_area.height)
                            {
                                buf.setChar(interp_x, interp_y, '─', self.line_style);
                            }
                        }
                    }
                }

                // Draw point marker
                if (self.show_points) {
                    buf.setChar(screen_x, screen_y, self.point_char, self.line_style);
                }

                prev_screen_x = screen_x;
                prev_screen_y = screen_y;
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TimeSeriesChart.init" {
    const timestamps = [_]i64{ 1000, 2000, 3000 };
    const values = [_]f64{ 1.0, 2.0, 3.0 };
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    try std.testing.expectEqual(3, chart.timestamps.len);
    try std.testing.expectEqual(3, chart.values.len);
}

test "TimeSeriesChart.init mismatched lengths" {
    const timestamps = [_]i64{ 1000, 2000 };
    const values = [_]f64{ 1.0, 2.0, 3.0 };
    const result = TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    try std.testing.expectError(error.MismatchedArrayLengths, result);
}

test "TimeSeriesChart.withBlock" {
    const timestamps = [_]i64{1000};
    const values = [_]f64{1.0};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    const with_block = chart.withBlock(Block.init());
    try std.testing.expect(with_block.block != null);
}

test "TimeSeriesChart.withYAxisLabel" {
    const timestamps = [_]i64{1000};
    const values = [_]f64{1.0};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    const with_label = chart.withYAxisLabel("CPU %");
    try std.testing.expectEqualStrings("CPU %", with_label.y_axis_label);
}

test "TimeSeriesChart.withMinMaxY" {
    const timestamps = [_]i64{1000};
    const values = [_]f64{1.0};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    const with_range = chart.withMinY(0).withMaxY(100);
    try std.testing.expectEqual(0, with_range.min_y.?);
    try std.testing.expectEqual(100, with_range.max_y.?);
}

test "TimeSeriesChart.withTimeFormat" {
    const timestamps = [_]i64{1000};
    const values = [_]f64{1.0};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    const with_format = chart.withTimeFormat(.iso8601);
    try std.testing.expectEqual(.iso8601, with_format.time_format);
}

test "TimeSeriesChart.withShowPoints" {
    const timestamps = [_]i64{1000};
    const values = [_]f64{1.0};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    const no_points = chart.withShowPoints(false);
    try std.testing.expect(!no_points.show_points);
}

test "TimeSeriesChart.calcYRange" {
    const values = [_]f64{ 1.5, 3.2, 2.1, 4.8 };
    const range = TimeSeriesChart.calcYRange(&values);
    try std.testing.expectEqual(1.5, range.min);
    try std.testing.expectEqual(4.8, range.max);
}

test "TimeSeriesChart.calcYRange empty" {
    const values = [_]f64{};
    const range = TimeSeriesChart.calcYRange(&values);
    try std.testing.expectEqual(0, range.min);
    try std.testing.expectEqual(0, range.max);
}

test "TimeSeriesChart.formatTimestamp hour_minute" {
    var buf: [32]u8 = undefined;
    // 1700000000 = 2023-11-14 22:13:20 UTC
    const result = try TimeSeriesChart.formatTimestamp(1700000000, .hour_minute, &buf);
    try std.testing.expectEqualStrings("22:13", result);
}

test "TimeSeriesChart.render empty" {
    const timestamps = [_]i64{};
    const values = [_]f64{};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    var buffer = try Buffer.init(std.testing.allocator, 30, 15);
    defer buffer.deinit();

    chart.render(&buffer, Rect{ .x = 0, .y = 0, .width = 30, .height = 15 });
    // Should not crash
}

test "TimeSeriesChart.render with data" {
    const timestamps = [_]i64{ 1700000000, 1700003600, 1700007200 };
    const values = [_]f64{ 10.5, 15.2, 12.8 };
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    var buffer = try Buffer.init(std.testing.allocator, 50, 20);
    defer buffer.deinit();

    chart.render(&buffer, Rect{ .x = 0, .y = 0, .width = 50, .height = 20 });

    // Verify Y-axis was drawn
    var found_y_axis = false;
    for (0..buffer.height) |y| {
        for (0..buffer.width) |x| {
            const cell = buffer.get(@intCast(x), @intCast(y));
            if (cell.char == '│') {
                found_y_axis = true;
                break;
            }
        }
        if (found_y_axis) break;
    }
    try std.testing.expect(found_y_axis);
}

test "TimeSeriesChart.render with block" {
    const timestamps = [_]i64{1700000000};
    const values = [_]f64{10.0};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    const with_block = chart.withBlock(Block.init().withBorders(.all).withTitle("TimeSeries"));

    var buffer = try Buffer.init(std.testing.allocator, 40, 20);
    defer buffer.deinit();

    with_block.render(&buffer, Rect{ .x = 0, .y = 0, .width = 40, .height = 20 });

    // Check for title
    const title_cell = buffer.get(1, 0);
    try std.testing.expectEqual('T', title_cell.char);
}

test "TimeSeriesChart.render zero-size area" {
    const timestamps = [_]i64{1000};
    const values = [_]f64{1.0};
    var chart = try TimeSeriesChart.init(std.testing.allocator, &timestamps, &values);
    defer chart.deinit();

    var buffer = try Buffer.init(std.testing.allocator, 10, 10);
    defer buffer.deinit();

    chart.render(&buffer, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}
