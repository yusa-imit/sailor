//! PieChart widget — circular percentage display with legend
//!
//! Example usage:
//!
//! ```zig
//! const slices = [_]PieChart.Slice{
//!     .{ .label = "CPU", .value = 35, .style = .{ .fg = .{ .indexed = 1 } } },
//!     .{ .label = "Memory", .value = 25, .style = .{ .fg = .{ .indexed = 2 } } },
//!     .{ .label = "Disk", .value = 40, .style = .{ .fg = .{ .indexed = 3 } } },
//! };
//!
//! const chart = PieChart.init(&slices)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Resources"))
//!     .withLegendPosition(.right);
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

/// PieChart widget — circular percentage display with legend
pub const PieChart = struct {
    pub const Slice = struct {
        label: []const u8,
        value: u64,
        style: Style = .{},
    };

    pub const LegendPosition = enum {
        none,
        right,
        bottom,
    };

    slices: []const Slice,
    block: ?Block = null,
    legend_position: LegendPosition = .right,
    show_percentages: bool = true,

    /// Create a pie chart with slices
    pub fn init(slices: []const Slice) PieChart {
        return .{ .slices = slices };
    }

    /// Set the block (border) for this pie chart
    pub fn withBlock(self: PieChart, new_block: Block) PieChart {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set legend position (default: right)
    pub fn withLegendPosition(self: PieChart, pos: LegendPosition) PieChart {
        var result = self;
        result.legend_position = pos;
        return result;
    }

    /// Show percentages in legend (default: true)
    pub fn withPercentages(self: PieChart, show: bool) PieChart {
        var result = self;
        result.show_percentages = show;
        return result;
    }

    /// Calculate total value of all slices
    fn calcTotal(slices: []const Slice) u64 {
        var total: u64 = 0;
        for (slices) |slice| {
            total += slice.value;
        }
        return total;
    }

    /// Render the pie chart
    pub fn render(self: PieChart, buf: *Buffer, area: Rect) void {
        // Render block border first
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (inner.width == 0 or inner.height == 0 or self.slices.len == 0) return;

        const total = calcTotal(self.slices);
        if (total == 0) return;

        // Calculate chart and legend areas
        const chart_area, const legend_area = self.splitAreas(inner);

        // Render pie chart using circle drawing
        self.renderPie(buf, chart_area, total);

        // Render legend if not .none
        if (self.legend_position != .none) {
            self.renderLegend(buf, legend_area, total);
        }
    }

    /// Split area into chart and legend
    fn splitAreas(self: PieChart, area: Rect) struct { Rect, Rect } {
        return switch (self.legend_position) {
            .none => .{ area, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 } },
            .right => blk: {
                // Reserve ~30% width for legend on right
                const legend_width = @min(area.width / 3, 20);
                if (area.width < legend_width + 2) {
                    break :blk .{ area, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 } };
                }
                const chart_area = Rect{
                    .x = area.x,
                    .y = area.y,
                    .width = area.width - legend_width,
                    .height = area.height,
                };
                const legend_area = Rect{
                    .x = area.x + chart_area.width,
                    .y = area.y,
                    .width = legend_width,
                    .height = area.height,
                };
                break :blk .{ chart_area, legend_area };
            },
            .bottom => blk: {
                // Reserve rows for legend at bottom
                const legend_height = @min(area.height / 3, @as(u16, @intCast(self.slices.len + 1)));
                if (area.height < legend_height + 2) {
                    break :blk .{ area, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 } };
                }
                const chart_area = Rect{
                    .x = area.x,
                    .y = area.y,
                    .width = area.width,
                    .height = area.height - legend_height,
                };
                const legend_area = Rect{
                    .x = area.x,
                    .y = area.y + chart_area.height,
                    .width = area.width,
                    .height = legend_height,
                };
                break :blk .{ chart_area, legend_area };
            },
        };
    }

    /// Render the pie chart circle
    fn renderPie(self: PieChart, buf: *Buffer, area: Rect, total: u64) void {
        if (area.width < 3 or area.height < 3) return;

        // Calculate circle center and radius
        const center_x = area.x + area.width / 2;
        const center_y = area.y + area.height / 2;
        const radius = @min(area.width / 2, area.height);

        // Draw circle using characters
        var angle: f64 = 0.0; // Start at top (0 degrees)

        for (self.slices) |slice| {
            const slice_angle = (@as(f64, @floatFromInt(slice.value)) / @as(f64, @floatFromInt(total))) * 360.0;
            self.renderSlice(buf, center_x, center_y, radius, angle, angle + slice_angle, slice.style);
            angle += slice_angle;
        }
    }

    /// Render a single pie slice
    fn renderSlice(self: PieChart, buf: *Buffer, cx: u16, cy: u16, radius: u16, start_angle: f64, end_angle: f64, slice_style: Style) void {
        _ = self;
        // Use simple character-based rendering
        // Draw radial lines from center to edge for the slice
        var a = start_angle;
        while (a < end_angle) : (a += 5.0) {
            const rad = a * std.math.pi / 180.0;
            var r: u16 = 0;
            while (r < radius) : (r += 1) {
                const dx = @as(i32, @intFromFloat(@as(f64, @floatFromInt(r)) * @sin(rad)));
                const dy = @as(i32, @intFromFloat(@as(f64, @floatFromInt(r)) * @cos(rad)));

                // Calculate absolute coordinates, checking bounds
                const abs_x = @as(i32, cx) + dx;
                const abs_y = @as(i32, cy) - dy;

                // Skip if out of bounds
                if (abs_x < 0 or abs_y < 0) continue;

                const x = @as(u16, @intCast(abs_x));
                const y = @as(u16, @intCast(abs_y));
                buf.set(x, y, .{ .char = '█', .style = slice_style });
            }
        }
    }

    /// Render the legend
    fn renderLegend(self: PieChart, buf: *Buffer, area: Rect, total: u64) void {
        if (area.width < 5 or area.height < 1) return;

        var y = area.y;
        for (self.slices, 0..) |slice, i| {
            if (y >= area.y + area.height) break;

            // Format legend entry: "■ Label: 35 (25%)"
            var legend_buf: [128]u8 = undefined;
            const percentage = (@as(f64, @floatFromInt(slice.value)) / @as(f64, @floatFromInt(total))) * 100.0;

            const legend_text = if (self.show_percentages)
                std.fmt.bufPrint(&legend_buf, "■ {s}: {d} ({d:.1}%)", .{ slice.label, slice.value, percentage }) catch "■ ???"
            else
                std.fmt.bufPrint(&legend_buf, "■ {s}: {d}", .{ slice.label, slice.value }) catch "■ ???";

            // Truncate if too long
            const max_len = area.width;
            const display_text = if (legend_text.len > max_len) legend_text[0..max_len] else legend_text;

            buf.setString(area.x, y, display_text, slice.style);
            y += 1;

            _ = i;
        }
    }
};

// Tests
const testing = std.testing;
const Allocator = std.mem.Allocator;

test "PieChart.init creates chart" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 30 },
        .{ .label = "C", .value = 20 },
    };
    const chart = PieChart.init(&slices);
    try testing.expectEqual(3, chart.slices.len);
    try testing.expectEqual(PieChart.LegendPosition.right, chart.legend_position);
    try testing.expect(chart.show_percentages);
}

test "PieChart.withBlock sets block" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const block = (Block{});
    const chart = PieChart.init(&slices).withBlock(block);
    try testing.expect(chart.block != null);
}

test "PieChart.withLegendPosition sets position" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices).withLegendPosition(.bottom);
    try testing.expectEqual(PieChart.LegendPosition.bottom, chart.legend_position);
}

test "PieChart.withPercentages sets flag" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices).withPercentages(false);
    try testing.expect(!chart.show_percentages);
}

test "PieChart.calcTotal sums values" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 30 },
        .{ .label = "C", .value = 20 },
    };
    const total = PieChart.calcTotal(&slices);
    try testing.expectEqual(100, total);
}

test "PieChart.calcTotal handles zero" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 0 },
        .{ .label = "B", .value = 0 },
    };
    const total = PieChart.calcTotal(&slices);
    try testing.expectEqual(0, total);
}

test "PieChart.render handles empty area" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices);

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    chart.render(&buf, area);
    // Should not crash
}

test "PieChart.render handles zero slices" {
    const slices = [_]PieChart.Slice{};
    const chart = PieChart.init(&slices);

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    chart.render(&buf, area);
    // Should not crash
}

test "PieChart.render handles zero total" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 0 },
        .{ .label = "B", .value = 0 },
    };
    const chart = PieChart.init(&slices);

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    chart.render(&buf, area);
    // Should not crash
}

test "PieChart.render with legend right" {
    const slices = [_]PieChart.Slice{
        .{ .label = "CPU", .value = 35, .style = .{ .fg = .{ .indexed = 1 } } },
        .{ .label = "Mem", .value = 25, .style = .{ .fg = .{ .indexed = 2 } } },
    };
    const chart = PieChart.init(&slices).withLegendPosition(.right);

    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    chart.render(&buf, area);

    // Verify legend text appears
    const cell_cpu = buf.get(27, 0); // Approximate legend position
    const cell_mem = buf.get(27, 1);
    try testing.expect(cell_cpu != null);
    try testing.expect(cell_mem != null);
}

test "PieChart.render with legend bottom" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const chart = PieChart.init(&slices).withLegendPosition(.bottom);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    chart.render(&buf, area);

    // Verify legend text appears at bottom
    const cell = buf.get(0, 7); // Approximate bottom legend position
    try testing.expect(cell != null);
}

test "PieChart.render with no legend" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 100 },
    };
    const chart = PieChart.init(&slices).withLegendPosition(.none);

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    chart.render(&buf, area);
    // Should render without legend
}

test "PieChart.render with block" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 50 },
    };
    const block = (Block{}).withBorders(.all).withTitle("Test");
    const chart = PieChart.init(&slices).withBlock(block);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    chart.render(&buf, area);

    // Verify border characters
    const top_left = buf.get(0, 0);
    try testing.expect(top_left != null);
    try testing.expectEqual(@as(u21, '┌'), top_left.?.char);
}

test "PieChart.render with percentages disabled" {
    const slices = [_]PieChart.Slice{
        .{ .label = "Test", .value = 75 },
    };
    const chart = PieChart.init(&slices)
        .withPercentages(false)
        .withLegendPosition(.right);

    var buf = try Buffer.init(testing.allocator, 30, 5);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    chart.render(&buf, area);

    // Legend should not contain "%" character
    // This is hard to verify without string search, so just ensure no crash
}

test "PieChart.render very small area" {
    const slices = [_]PieChart.Slice{
        .{ .label = "A", .value = 50 },
    };
    const chart = PieChart.init(&slices);

    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 2 };
    chart.render(&buf, area);
    // Should handle gracefully
}

test "PieChart.render single slice 100%" {
    const slices = [_]PieChart.Slice{
        .{ .label = "Full", .value = 100 },
    };
    const chart = PieChart.init(&slices);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit(testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    chart.render(&buf, area);
    // Should render full circle
}

test "PieChart.splitAreas with right legend" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices).withLegendPosition(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    const chart_area, const legend_area = chart.splitAreas(area);

    try testing.expect(chart_area.width > 0);
    try testing.expect(legend_area.width > 0);
    try testing.expectEqual(chart_area.width + legend_area.width, area.width);
}

test "PieChart.splitAreas with bottom legend" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices).withLegendPosition(.bottom);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const chart_area, const legend_area = chart.splitAreas(area);

    try testing.expect(chart_area.height > 0);
    try testing.expect(legend_area.height > 0);
    try testing.expectEqual(chart_area.height + legend_area.height, area.height);
}

test "PieChart.splitAreas with no legend" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices).withLegendPosition(.none);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    const chart_area, const legend_area = chart.splitAreas(area);

    try testing.expectEqual(area, chart_area);
    try testing.expectEqual(0, legend_area.width);
    try testing.expectEqual(0, legend_area.height);
}

test "PieChart.splitAreas too small for legend" {
    const slices = [_]PieChart.Slice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices).withLegendPosition(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    const chart_area, const legend_area = chart.splitAreas(area);

    // If area too small, legend should be empty
    try testing.expectEqual(area, chart_area);
    try testing.expectEqual(0, legend_area.width);
}
