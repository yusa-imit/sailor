//! DonutChart widget — hollow-center variant of PieChart with optional center label
//!
//! Example usage:
//!
//! ```zig
//! const slices = [_]DonutChart.Slice{
//!     .{ .label = "CPU", .value = 35, .style = .{ .fg = .{ .indexed = 1 } } },
//!     .{ .label = "Memory", .value = 25, .style = .{ .fg = .{ .indexed = 2 } } },
//!     .{ .label = "Disk", .value = 40, .style = .{ .fg = .{ .indexed = 3 } } },
//! };
//!
//! const chart = DonutChart.init(&slices)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Resources"))
//!     .withHoleRatio(0.5)
//!     .withCenterLabel("75%");
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

/// A single slice in the donut chart
pub const Slice = struct {
    label: []const u8,
    value: u64,
    style: Style = .{},
};

/// DonutChart widget — hollow-center circular percentage display with legend
pub const DonutChart = struct {
    pub const LegendPosition = enum {
        none,
        right,
        bottom,
    };

    slices: []const Slice,
    block: ?Block = null,
    legend_position: LegendPosition = .right,
    show_percentages: bool = true,
    hole_ratio: f32 = 0.5,
    center_label: ?[]const u8 = null,
    center_label_style: Style = .{},

    /// Create a donut chart with slices
    pub fn init(slices: []const Slice) DonutChart {
        return .{ .slices = slices };
    }

    /// Set the block (border) for this donut chart
    pub fn withBlock(self: DonutChart, new_block: Block) DonutChart {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set legend position (default: right)
    pub fn withLegendPosition(self: DonutChart, pos: LegendPosition) DonutChart {
        var result = self;
        result.legend_position = pos;
        return result;
    }

    /// Show percentages in legend (default: true)
    pub fn withPercentages(self: DonutChart, show: bool) DonutChart {
        var result = self;
        result.show_percentages = show;
        return result;
    }

    /// Set hole ratio (inner radius / outer radius), clamped to [0.0, 0.9] at render time
    pub fn withHoleRatio(self: DonutChart, ratio: f32) DonutChart {
        var result = self;
        result.hole_ratio = ratio;
        return result;
    }

    /// Set center label to display in the hollow center
    pub fn withCenterLabel(self: DonutChart, label: []const u8) DonutChart {
        var result = self;
        result.center_label = label;
        return result;
    }

    /// Set style for center label
    pub fn withCenterLabelStyle(self: DonutChart, style: Style) DonutChart {
        var result = self;
        result.center_label_style = style;
        return result;
    }

    /// Calculate total value of all slices
    pub fn calcTotal(slices: []const Slice) u64 {
        var total: u64 = 0;
        for (slices) |slice| {
            total += slice.value;
        }
        return total;
    }

    /// Render the donut chart
    pub fn render(self: DonutChart, buf: *Buffer, area: Rect) void {
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

        // Render donut chart using circle drawing with hollow center
        self.renderDonut(buf, chart_area, total);

        // Render center label if set (must align with chart_area used by renderDonut)
        if (self.center_label) |label| {
            self.renderCenterLabel(buf, chart_area, label);
        }

        // Render legend if not .none
        if (self.legend_position != .none) {
            self.renderLegend(buf, legend_area, total);
        }
    }

    /// Split area into chart and legend (mirror PieChart.splitAreas)
    fn splitAreas(self: DonutChart, area: Rect) struct { Rect, Rect } {
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

    /// Render the donut chart circle with hollow center
    fn renderDonut(self: DonutChart, buf: *Buffer, area: Rect, total: u64) void {
        if (area.width < 3 or area.height < 3) return;

        // Calculate circle center and radius
        const center_x = area.x + area.width / 2;
        const center_y = area.y + area.height / 2;
        const radius = @min(area.width / 2, area.height);

        // Clamp hole_ratio to valid range [0.0, 0.9]
        const clamped_hole_ratio = @min(@max(self.hole_ratio, 0.0), 0.9);
        const inner_radius = @as(u16, @intFromFloat(@as(f32, @floatFromInt(radius)) * clamped_hole_ratio));

        // Draw donut using angle sweeps
        var angle: f64 = 0.0; // Start at top (0 degrees)

        for (self.slices) |slice| {
            const slice_angle = (@as(f64, @floatFromInt(slice.value)) / @as(f64, @floatFromInt(total))) * 360.0;
            self.renderSlice(buf, center_x, center_y, radius, inner_radius, angle, angle + slice_angle, slice.style);
            angle += slice_angle;
        }
    }

    /// Render a single donut slice (ring segment)
    fn renderSlice(self: DonutChart, buf: *Buffer, cx: u16, cy: u16, radius: u16, inner_radius: u16, start_angle: f64, end_angle: f64, slice_style: Style) void {
        _ = self;
        // Use simple character-based rendering
        // Draw radial lines from inner to outer radius for the slice
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

                // Check if cell distance is outside inner_radius (to create hollow center)
                const dist_sq = dx * dx + dy * dy;
                const inner_radius_sq = @as(i32, @intCast(inner_radius)) * @as(i32, @intCast(inner_radius));
                if (dist_sq < inner_radius_sq) continue;

                const x = @as(u16, @intCast(abs_x));
                const y = @as(u16, @intCast(abs_y));
                buf.set(x, y, .{ .char = '█', .style = slice_style });
            }
        }
    }

    /// Render the center label in the hollow area
    fn renderCenterLabel(self: DonutChart, buf: *Buffer, area: Rect, label: []const u8) void {
        if (area.width < 3 or area.height < 3 or label.len == 0) return;

        // Calculate center position
        const center_x = area.x + area.width / 2;
        const center_y = area.y + area.height / 2;
        const radius = @min(area.width / 2, area.height);

        // Clamp hole_ratio to valid range
        const clamped_hole_ratio = @min(@max(self.hole_ratio, 0.0), 0.9);
        const inner_radius = @as(u16, @intFromFloat(@as(f32, @floatFromInt(radius)) * clamped_hole_ratio));

        // If inner_radius is too small, don't render label
        if (inner_radius < 1) return;

        // Available width for label is approximately 2 * inner_radius
        const max_label_len = @as(usize, inner_radius) * 2;

        // Truncate label if necessary
        const display_len = @min(label.len, max_label_len);
        if (display_len == 0) return;

        // Calculate starting x position to center the label
        const start_x = @as(i32, @intCast(center_x)) - @as(i32, @intCast(display_len / 2));

        // Render label characters from left to right
        var x_offset: usize = 0;
        while (x_offset < display_len) : (x_offset += 1) {
            const abs_x = start_x + @as(i32, @intCast(x_offset));

            // Skip if out of bounds horizontally
            if (abs_x < 0) continue;

            const x = @as(u16, @intCast(abs_x));
            const char = label[x_offset];

            buf.set(x, center_y, .{ .char = char, .style = self.center_label_style });
        }
    }

    /// Render the legend (mirror PieChart.renderLegend)
    fn renderLegend(self: DonutChart, buf: *Buffer, area: Rect, total: u64) void {
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
