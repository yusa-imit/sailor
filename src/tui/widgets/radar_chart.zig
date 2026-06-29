//! RadarChart Widget — multi-dimensional radar/spider chart visualization
//!
//! The RadarChart widget displays multi-dimensional data as a polygon on a radial grid.
//! Each axis radiates from the center, and data values form vertices on those axes.
//!
//! ## Features
//! - Configurable axes (up to 16)
//! - Multiple data series (up to 8)
//! - Customizable fill/outline rendering
//! - Focused series highlighting
//! - Block border support
//! - Axis labels
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var axes = [_][]const u8{ "Speed", "Power", "Skill" };
//! var values = [_]f32{ 0.8, 0.6, 0.9 };
//! var series = [_]RadarSeries{.{ .label = "Hero", .values = &values }};
//! var chart = RadarChart.init()
//!     .withAxes(&axes)
//!     .withSeries(&series)
//!     .withFilled(true);
//! chart.render(&buf, area);
//! ```

const std = @import("std");
const math = std.math;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// A single data series for the radar chart
pub const RadarSeries = struct {
    /// Label for this series (optional)
    label: []const u8 = "",
    /// Values for each axis (should match axis count, 0.0-1.0 range)
    values: []const f32 = &.{},
    /// Style for rendering this series
    style: Style = .{},
};

/// RadarChart widget for displaying multi-dimensional data
pub const RadarChart = struct {
    /// Maximum number of axes
    pub const MAX_AXES: usize = 16;
    /// Maximum number of series
    pub const MAX_SERIES: usize = 8;

    /// Array of axis labels
    axes: []const []const u8 = &.{},
    /// Array of data series
    series: []const RadarSeries = &.{},
    /// Index of focused series
    focused: usize = 0,
    /// Base style for all elements
    style: Style = .{},
    /// Style for axis lines
    axis_style: Style = .{},
    /// Style for focused series
    focused_style: Style = .{},
    /// Whether to fill polygons
    filled: bool = false,
    /// Optional block border
    block: ?Block = null,

    /// Initialize a new RadarChart with defaults
    pub fn init() RadarChart {
        return .{};
    }

    /// Return the effective axis count (capped at MAX_AXES)
    pub fn axisCount(self: RadarChart) usize {
        return @min(self.axes.len, MAX_AXES);
    }

    /// Return the effective series count (capped at MAX_SERIES)
    pub fn seriesCount(self: RadarChart) usize {
        return @min(self.series.len, MAX_SERIES);
    }

    /// Create a copy with different axes
    pub fn withAxes(self: RadarChart, axes: []const []const u8) RadarChart {
        var result = self;
        result.axes = axes;
        return result;
    }

    /// Create a copy with different series
    pub fn withSeries(self: RadarChart, series: []const RadarSeries) RadarChart {
        var result = self;
        result.series = series;
        return result;
    }

    /// Create a copy with different focused index
    pub fn withFocused(self: RadarChart, focused: usize) RadarChart {
        var result = self;
        result.focused = focused;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: RadarChart, style: Style) RadarChart {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different axis style
    pub fn withAxisStyle(self: RadarChart, axis_style: Style) RadarChart {
        var result = self;
        result.axis_style = axis_style;
        return result;
    }

    /// Create a copy with different focused style
    pub fn withFocusedStyle(self: RadarChart, focused_style: Style) RadarChart {
        var result = self;
        result.focused_style = focused_style;
        return result;
    }

    /// Create a copy with different filled mode
    pub fn withFilled(self: RadarChart, filled: bool) RadarChart {
        var result = self;
        result.filled = filled;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: RadarChart, block: ?Block) RadarChart {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render the radar chart to the buffer
    pub fn render(self: RadarChart, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Handle block border if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        // Require minimum area
        if (inner_area.width < 5 or inner_area.height < 5) return;

        const n_axes = self.axisCount();
        const n_series = self.seriesCount();

        // Need at least 2 axes to render anything
        if (n_axes < 2) return;

        // Calculate geometry
        const center_x = inner_area.x + inner_area.width / 2;
        const center_y = inner_area.y + inner_area.height / 2;
        const radius_raw = @min(inner_area.width / 2, inner_area.height / 2);
        const radius = if (radius_raw > 1) radius_raw - 1 else 0;

        if (radius == 0) return;

        // Draw axis lines and labels
        var axis_endpoints: [MAX_AXES][2]f32 = undefined;
        for (0..n_axes) |i| {
            const angle = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n_axes)) - std.math.pi / 2.0;
            const cos_a = std.math.cos(angle);
            const sin_a = std.math.sin(angle);

            const ex_f = @as(f32, @floatFromInt(center_x)) + @as(f32, @floatFromInt(radius)) * cos_a;
            const ey_f = @as(f32, @floatFromInt(center_y)) + @as(f32, @floatFromInt(radius)) * sin_a * 0.5;

            const ex = @as(i32, @intFromFloat(@round(ex_f)));
            const ey = @as(i32, @intFromFloat(@round(ey_f)));

            axis_endpoints[i][0] = ex_f;
            axis_endpoints[i][1] = ey_f;

            // Draw axis line using Bresenham
            drawLine(buf, inner_area, center_x, center_y, ex, ey, self.axis_style);

            // Draw axis label
            if (i < self.axes.len) {
                const label = self.axes[i];
                if (label.len > 0) {
                    drawAxisLabel(buf, inner_area, ex, ey, label, cos_a, sin_a, self.axis_style);
                }
            }
        }

        // Draw series polygons
        for (0..n_series) |s_idx| {
            const series_s = self.series[s_idx];
            const series_style = if (s_idx == self.focused) self.focused_style else series_s.style;

            // Collect polygon vertices
            var vertices: [MAX_AXES][2]f32 = undefined;
            for (0..n_axes) |i| {
                var value: f32 = 0.0;
                if (i < series_s.values.len) {
                    value = @min(@max(series_s.values[i], 0.0), 1.0);
                }

                const angle = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n_axes)) - std.math.pi / 2.0;
                const cos_a = std.math.cos(angle);
                const sin_a = std.math.sin(angle);

                const vx = @as(f32, @floatFromInt(center_x)) + value * @as(f32, @floatFromInt(radius)) * cos_a;
                const vy = @as(f32, @floatFromInt(center_y)) + value * @as(f32, @floatFromInt(radius)) * sin_a * 0.5;

                vertices[i][0] = vx;
                vertices[i][1] = vy;
            }

            // Draw polygon edges
            for (0..n_axes) |i| {
                const next = (i + 1) % n_axes;
                const x0 = @as(i32, @intFromFloat(@round(vertices[i][0])));
                const y0 = @as(i32, @intFromFloat(@round(vertices[i][1])));
                const x1 = @as(i32, @intFromFloat(@round(vertices[next][0])));
                const y1 = @as(i32, @intFromFloat(@round(vertices[next][1])));

                drawLine(buf, inner_area, x0, y0, x1, y1, series_style);
            }

            // If filled, perform simple fill using horizontal scanlines
            if (self.filled) {
                fillPolygon(buf, inner_area, &vertices, n_axes, center_x, center_y, series_style);
            }
        }
    }

    /// Draw a line using Bresenham's algorithm
    fn drawLine(buf: *Buffer, area: Rect, x0: i32, y0: i32, x1: i32, y1: i32, style_arg: Style) void {
        const dx = @abs(x1 - x0);
        const dy = @abs(y1 - y0);
        const sx: i32 = if (x1 > x0) 1 else -1;
        const sy: i32 = if (y1 > y0) 1 else -1;
        var err = @as(i32, @intCast(dx)) - @as(i32, @intCast(dy));
        var x = x0;
        var y = y0;

        while (true) {
            // Bounds check before plotting
            if (x >= 0 and y >= 0) {
                const px: u16 = @intCast(x);
                const py: u16 = @intCast(y);
                if (px >= area.x and px < area.x + area.width and
                    py >= area.y and py < area.y + area.height) {
                    buf.set(px, py, buffer_mod.Cell.init('·', style_arg));
                }
            }

            if (x == x1 and y == y1) break;

            const e2 = 2 * err;
            if (e2 > -@as(i32, @intCast(dy))) {
                err -= @as(i32, @intCast(dy));
                x += sx;
            }
            if (e2 < @as(i32, @intCast(dx))) {
                err += @as(i32, @intCast(dx));
                y += sy;
            }
        }
    }

    /// Draw an axis label near the endpoint
    fn drawAxisLabel(buf: *Buffer, area: Rect, ex: i32, ey: i32, label: []const u8, cos_a: f32, sin_a: f32, style_arg: Style) void {
        var label_x = ex;
        var label_y = ey;

        // Position label relative to endpoint
        if (cos_a > 0.3) {
            label_x += 2;
        } else if (cos_a < -0.3) {
            label_x -= @as(i32, @intCast(@min(label.len, 10))) - 1;
        } else {
            const label_width = @as(i32, @intCast(@min(label.len, 10)));
            label_x -= @divTrunc(label_width, 2);
        }

        if (sin_a * 0.5 < -0.15) {
            label_y -= 1;
        } else if (sin_a * 0.5 > 0.15) {
            label_y += 1;
        }

        // Bounds check and write label
        if (label_x >= 0 and label_y >= 0) {
            const ux: u16 = @intCast(label_x);
            const uy: u16 = @intCast(label_y);
            if (ux < area.x + area.width and uy < area.y + area.height) {
                buf.setString(ux, uy, label, style_arg);
            }
        }
    }

    /// Simple polygon fill using horizontal scanlines
    fn fillPolygon(buf: *Buffer, area: Rect, vertices: *const [MAX_AXES][2]f32, n_vertices: usize, _: u16, _: u16, style_arg: Style) void {
        if (n_vertices < 3) return;

        // Find bounding box
        var min_y = vertices[0][1];
        var max_y = vertices[0][1];
        for (1..n_vertices) |i| {
            min_y = @min(min_y, vertices[i][1]);
            max_y = @max(max_y, vertices[i][1]);
        }

        const y_start = @as(i32, @intFromFloat(@round(min_y)));
        const y_end = @as(i32, @intFromFloat(@round(max_y)));

        // For each scanline, check intersection and fill
        var y_scan = y_start;
        while (y_scan <= y_end) : (y_scan += 1) {
            if (y_scan < 0) continue;
            const uy: u16 = @intCast(y_scan);
            if (uy >= area.y + area.height) break;

            // Find x intersections with polygon edges at this scanline
            var intersections: [MAX_AXES]f32 = undefined;
            var int_count: usize = 0;

            for (0..n_vertices) |i| {
                const next = (i + 1) % n_vertices;
                const y_v0 = vertices[i][1];
                const y_v1 = vertices[next][1];
                const x_v0 = vertices[i][0];
                const x_v1 = vertices[next][0];

                if ((y_v0 <= @as(f32, @floatFromInt(y_scan)) and y_v1 >= @as(f32, @floatFromInt(y_scan))) or
                    (y_v1 <= @as(f32, @floatFromInt(y_scan)) and y_v0 >= @as(f32, @floatFromInt(y_scan)))) {
                    if (@abs(y_v1 - y_v0) > 0.001) {
                        const t = (@as(f32, @floatFromInt(y_scan)) - y_v0) / (y_v1 - y_v0);
                        const x_intersect = x_v0 + t * (x_v1 - x_v0);
                        if (int_count < MAX_AXES) {
                            intersections[int_count] = x_intersect;
                            int_count += 1;
                        }
                    }
                }
            }

            // Sort intersections and fill between pairs
            if (int_count >= 2) {
                for (0..int_count) |i| {
                    for (i + 1..int_count) |j| {
                        if (intersections[j] < intersections[i]) {
                            const tmp = intersections[i];
                            intersections[i] = intersections[j];
                            intersections[j] = tmp;
                        }
                    }
                }

                var i_fill: usize = 0;
                while (i_fill + 1 < int_count) : (i_fill += 2) {
                    var x_fill = @as(i32, @intFromFloat(@round(intersections[i_fill])));
                    const x_fill_end = @as(i32, @intFromFloat(@round(intersections[i_fill + 1])));

                    while (x_fill <= x_fill_end) : (x_fill += 1) {
                        if (x_fill >= 0) {
                            const ux: u16 = @intCast(x_fill);
                            if (ux >= area.x and ux < area.x + area.width) {
                                buf.set(ux, uy, buffer_mod.Cell.init('·', style_arg));
                            }
                        }
                    }
                }
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RadarChart.init has empty axes" {
    const rc = RadarChart.init();
    try std.testing.expectEqual(@as(usize, 0), rc.axes.len);
}

test "RadarChart.init has empty series" {
    const rc = RadarChart.init();
    try std.testing.expectEqual(@as(usize, 0), rc.series.len);
}

test "RadarChart.init has focused == 0" {
    const rc = RadarChart.init();
    try std.testing.expectEqual(@as(usize, 0), rc.focused);
}

test "RadarChart.init has filled == false" {
    const rc = RadarChart.init();
    try std.testing.expectEqual(false, rc.filled);
}

test "RadarChart.init has no block" {
    const rc = RadarChart.init();
    try std.testing.expectEqual(@as(?Block, null), rc.block);
}

test "RadarChart.MAX_AXES equals 16" {
    try std.testing.expectEqual(@as(usize, 16), RadarChart.MAX_AXES);
}

test "RadarChart.MAX_SERIES equals 8" {
    try std.testing.expectEqual(@as(usize, 8), RadarChart.MAX_SERIES);
}

test "RadarChart.axisCount with zero axes returns 0" {
    const rc = RadarChart.init();
    try std.testing.expectEqual(@as(usize, 0), rc.axisCount());
}

test "RadarChart.axisCount with 1 axis returns 1" {
    var axes = [_][]const u8{"Speed"};
    const rc = RadarChart.init().withAxes(&axes);
    try std.testing.expectEqual(@as(usize, 1), rc.axisCount());
}

test "RadarChart.axisCount caps at MAX_AXES" {
    var axes: [20][]const u8 = undefined;
    for (0..20) |i| {
        axes[i] = "A";
    }
    const rc = RadarChart.init().withAxes(&axes);
    try std.testing.expectEqual(@as(usize, 16), rc.axisCount());
}

test "RadarChart.axisCount with exactly MAX_AXES" {
    var axes: [16][]const u8 = undefined;
    for (0..16) |i| {
        axes[i] = "A";
    }
    const rc = RadarChart.init().withAxes(&axes);
    try std.testing.expectEqual(@as(usize, 16), rc.axisCount());
}

test "RadarChart.axisCount with 3 axes" {
    var axes = [_][]const u8{ "Speed", "Power", "Skill" };
    const rc = RadarChart.init().withAxes(&axes);
    try std.testing.expectEqual(@as(usize, 3), rc.axisCount());
}

test "RadarChart.seriesCount with zero series returns 0" {
    const rc = RadarChart.init();
    try std.testing.expectEqual(@as(usize, 0), rc.seriesCount());
}

test "RadarChart.seriesCount with 1 series returns 1" {
    var series = [_]RadarSeries{.{ .label = "Series1" }};
    const rc = RadarChart.init().withSeries(&series);
    try std.testing.expectEqual(@as(usize, 1), rc.seriesCount());
}

test "RadarChart.seriesCount caps at MAX_SERIES" {
    var series: [10]RadarSeries = undefined;
    for (0..10) |i| {
        series[i] = .{ .label = "S" };
    }
    const rc = RadarChart.init().withSeries(&series);
    try std.testing.expectEqual(@as(usize, 8), rc.seriesCount());
}

test "RadarChart.seriesCount with exactly MAX_SERIES" {
    var series: [8]RadarSeries = undefined;
    for (0..8) |i| {
        series[i] = .{ .label = "S" };
    }
    const rc = RadarChart.init().withSeries(&series);
    try std.testing.expectEqual(@as(usize, 8), rc.seriesCount());
}

test "RadarChart.seriesCount with 3 series" {
    var series = [_]RadarSeries{
        .{ .label = "A" },
        .{ .label = "B" },
        .{ .label = "C" },
    };
    const rc = RadarChart.init().withSeries(&series);
    try std.testing.expectEqual(@as(usize, 3), rc.seriesCount());
}
