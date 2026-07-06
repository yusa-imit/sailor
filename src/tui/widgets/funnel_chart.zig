//! FunnelChart Widget — funnel/pyramid shape visualization
//!
//! The FunnelChart widget displays stages of a conversion funnel or pipeline,
//! with each stage represented as a horizontal bar centered in the available space.
//! Bar width is proportional to the stage value relative to the maximum value.
//! Stages stack top-to-bottom, creating a narrowing funnel effect.
//!
//! ## Features
//! - Up to 16 stages arranged top-to-bottom
//! - Bar width proportional to stage value
//! - Focused stage highlighting
//! - Optional value and percentage labels
//! - Per-stage styling
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const stages = [_]FunnelStage{
//!     .{ .label = "Visitors", .value = 1000.0 },
//!     .{ .label = "Signups", .value = 750.0 },
//!     .{ .label = "Active", .value = 500.0 },
//!     .{ .label = "Paid", .value = 100.0 },
//! };
//!
//! const chart = FunnelChart.init()
//!     .withStages(&stages)
//!     .withShowValues(true)
//!     .withShowPercentages(true);
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

/// A single stage in the funnel
pub const FunnelStage = struct {
    /// Label for the stage
    label: []const u8 = "",
    /// Value (width-determining)
    value: f32 = 0.0,
    /// Optional custom style for this stage
    style: Style = .{},
};

pub const FunnelChart = struct {
    /// Maximum number of stages (capped at 16 for rendering)
    pub const MAX_STAGES: usize = 16;

    /// Array of stages to display
    stages: []const FunnelStage = &.{},
    /// Index of the focused stage for highlighting
    focused: usize = 0,
    /// Base style applied to all stages
    style: Style = .{},
    /// Style for labels
    label_style: Style = .{},
    /// Style for values
    value_style: Style = .{},
    /// Style for the focused stage
    focused_style: Style = .{},
    /// Whether to render value labels on stages
    show_values: bool = true,
    /// Whether to render percentage labels
    show_percentages: bool = false,
    /// Optional block border
    block: ?Block = null,

    /// Initialize a FunnelChart with all defaults
    pub fn init() FunnelChart {
        return .{};
    }

    /// Count of stages to render (capped at MAX_STAGES)
    pub fn stageCount(self: FunnelChart) usize {
        return @min(self.stages.len, MAX_STAGES);
    }

    /// Maximum value across all stages (0.0 if empty)
    pub fn maxValue(self: FunnelChart) f32 {
        const n = self.stageCount();
        if (n == 0) return 0.0;

        var max: f32 = self.stages[0].value;
        for (1..n) |i| {
            if (self.stages[i].value > max) {
                max = self.stages[i].value;
            }
        }
        return max;
    }

    /// Set stages array
    pub fn withStages(self: FunnelChart, stages: []const FunnelStage) FunnelChart {
        var result = self;
        result.stages = stages;
        return result;
    }

    /// Set focused stage index
    pub fn withFocused(self: FunnelChart, idx: usize) FunnelChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: FunnelChart, show: bool) FunnelChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set show_percentages flag
    pub fn withShowPercentages(self: FunnelChart, show: bool) FunnelChart {
        var result = self;
        result.show_percentages = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: FunnelChart, s: Style) FunnelChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: FunnelChart, s: Style) FunnelChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set value style
    pub fn withValueStyle(self: FunnelChart, s: Style) FunnelChart {
        var result = self;
        result.value_style = s;
        return result;
    }

    /// Set focused style
    pub fn withFocusedStyle(self: FunnelChart, s: Style) FunnelChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: FunnelChart, b: ?Block) FunnelChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the funnel chart to the buffer
    pub fn render(self: FunnelChart, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need at least 2x2 inner area to render anything
        if (inner.width < 2 or inner.height < 2) return;

        const n = self.stageCount();
        if (n == 0) return;

        const max_val = self.maxValue();
        const row_height = @max(1, inner.height / @as(u16, @intCast(n)));

        // Render each stage
        for (0..n) |i| {
            const stage = self.stages[i];

            // Calculate stage area
            const stage_y = inner.y + @as(u16, @intCast(i)) * row_height;
            const stage_height = if (i == n - 1)
                inner.y + inner.height - stage_y
            else
                row_height;

            if (stage_y >= inner.y + inner.height) break;

            // Clamp to bounds
            const stage_area = Rect{
                .x = inner.x,
                .y = stage_y,
                .width = inner.width,
                .height = @min(stage_height, inner.y + inner.height - stage_y),
            };

            // Determine bar width based on value
            const bar_width = if (max_val > 0.0)
                @as(u16, @intFromFloat(stage.value / max_val * @as(f32, @floatFromInt(inner.width))))
            else
                inner.width;

            const clamped_width = @min(bar_width, inner.width);

            // Center the bar
            const bar_x = inner.x + (inner.width -| clamped_width) / 2;

            // Determine style
            const is_focused = (i == self.focused);
            var bar_style = stage.style;
            bar_style = self.style.merge(bar_style);
            if (is_focused) {
                bar_style = self.focused_style.merge(bar_style);
            }

            // Draw bar with '█' character
            if (clamped_width > 0 and stage_area.height > 0) {
                var row: u16 = stage_area.y;
                while (row < stage_area.y + stage_area.height and row < buf.height) : (row += 1) {
                    for (bar_x..bar_x + clamped_width) |col| {
                        if (col < buf.width) {
                            buf.set(@intCast(col), row, Cell.init('█', bar_style));
                        }
                    }
                }
            }

            // Draw value label if enabled
            if (self.show_values) {
                drawValueLabel(buf, stage_area, stage.value, self.value_style);
            }

            // Draw percentage label if enabled
            if (self.show_percentages and max_val > 0.0) {
                const percentage = (stage.value / max_val) * 100.0;
                drawPercentageLabel(buf, stage_area, percentage, self.value_style);
            }

            // Draw label if present
            if (stage.label.len > 0) {
                drawLabel(buf, stage_area, stage.label, self.label_style);
            }
        }
    }
};

/// Helper: Format and draw value label
fn drawValueLabel(buf: *Buffer, area: Rect, value: f32, style: Style) void {
    if (area.height == 0) return;

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

    // Draw at top of area
    const label_row: u16 = area.y;
    if (label_row < buf.height and area.x < buf.width) {
        buf.setString(area.x + 1, label_row, value_str[0..@min(str_len, 15)], style);
    }
}

/// Helper: Format and draw percentage label
fn drawPercentageLabel(buf: *Buffer, area: Rect, percentage: f32, style: Style) void {
    if (area.height == 0) return;

    var pct_str: [16]u8 = undefined;
    const pct_int: i32 = @intFromFloat(percentage);
    var str_len: usize = 0;

    const abs_val: u32 = if (pct_int < 0) @intCast(-pct_int) else @intCast(pct_int);
    var digit_count: usize = 0;
    var temp = abs_val;
    while (temp > 0) : (temp /= 10) digit_count += 1;
    if (digit_count == 0) digit_count = 1;
    temp = abs_val;
    for (0..digit_count) |_| {
        pct_str[digit_count - 1] = @as(u8, @intCast(temp % 10 + 48));
        temp /= 10;
    }
    str_len = digit_count;

    // Add % sign
    if (str_len < 15) {
        pct_str[str_len] = '%';
        str_len += 1;
    }

    // Draw at right side if there's room
    if (area.width > str_len + 2) {
        const label_row: u16 = area.y;
        if (label_row < buf.height and area.x + area.width >= str_len) {
            const draw_x = area.x + area.width - @as(u16, @intCast(str_len)) - 1;
            if (draw_x < buf.width) {
                buf.setString(draw_x, label_row, pct_str[0..str_len], style);
            }
        }
    }
}

/// Helper: Draw stage label
fn drawLabel(buf: *Buffer, area: Rect, label: []const u8, style: Style) void {
    if (area.height == 0 or label.len == 0) return;

    const label_row: u16 = area.y + area.height / 2;
    if (label_row < buf.height and area.x < buf.width) {
        // Draw label at center-left, truncated to fit
        const max_len = @min(label.len, area.width);
        buf.setString(area.x + 1, label_row, label[0..max_len], style);
    }
}
