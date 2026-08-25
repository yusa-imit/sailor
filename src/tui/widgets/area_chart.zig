//! AreaChart Widget — filled area chart with optional stacking
//!
//! The AreaChart widget displays one or more data series as filled areas,
//! with optional stacking. Each area spans from a baseline (y=0) to the
//! series value, with an optional top-boundary line character.
//!
//! ## Features
//! - Up to 8 series (MAX_SERIES)
//! - Up to 64 points per series (MAX_POINTS)
//! - Non-stacked: areas overlap with later series on top
//! - Stacked: areas cumulative stack vertically
//! - Auto-scale includes baseline (y=0) in range
//! - Custom fill and line boundary characters
//! - Min/max value overrides for scaling
//! - Focused series highlighting
//! - Block border support
//! - No heap allocations
//! - Robust NaN/Infinity handling
//!
//! ## Usage
//! ```zig
//! const series = [_]AreaSeries{
//!     .{ .label = "A", .values = &values_a },
//!     .{ .label = "B", .values = &values_b },
//! };
//!
//! const chart = AreaChart.init()
//!     .withSeries(&series)
//!     .withStacked(false)
//!     .withShowLine(true);
//!
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

/// Single series in an area chart
pub const AreaSeries = struct {
    /// Label for the series
    label: []const u8 = "",
    /// Data values
    values: []const f32 = &.{},
    /// Optional custom style for this series
    style: Style = .{},
};

pub const AreaChart = struct {
    /// Maximum number of series (capped at 8 for rendering)
    pub const MAX_SERIES: usize = 8;
    /// Maximum number of points per series
    pub const MAX_POINTS: usize = 64;

    /// Array of series to display (cap at MAX_SERIES)
    series: [MAX_SERIES]AreaSeries = undefined,
    /// Number of series actually stored (0..MAX_SERIES)
    series_count: usize = 0,
    /// Whether to stack series (true) or overlay them (false)
    stacked: bool = false,
    /// Whether to show line character at series boundary
    show_line: bool = true,
    /// Character to fill area with (default '█')
    fill_char: u21 = '█',
    /// Character for top boundary line (default '▀')
    line_char: u21 = '▀',
    /// Minimum value for scale (null = auto)
    min_val: ?f32 = null,
    /// Maximum value for scale (null = auto)
    max_val: ?f32 = null,
    /// Index of focused series for highlighting (null = no focus)
    focused: ?usize = null,
    /// Style for focused series
    focused_style: Style = .{},
    /// Optional block border
    block: ?Block = null,
    /// Base style applied to all areas
    style: Style = .{},

    /// Initialize an AreaChart with all defaults
    pub fn init() AreaChart {
        return .{};
    }

    /// Set series array (caps at MAX_SERIES, copies into fixed array)
    pub fn withSeries(self: AreaChart, s: []const AreaSeries) AreaChart {
        var result = self;
        result.series_count = @min(s.len, MAX_SERIES);
        for (0..result.series_count) |i| {
            result.series[i] = s[i];
        }
        return result;
    }

    /// Set stacked flag
    pub fn withStacked(self: AreaChart, v: bool) AreaChart {
        var result = self;
        result.stacked = v;
        return result;
    }

    /// Set show_line flag
    pub fn withShowLine(self: AreaChart, v: bool) AreaChart {
        var result = self;
        result.show_line = v;
        return result;
    }

    /// Set fill character
    pub fn withFillChar(self: AreaChart, ch: u21) AreaChart {
        var result = self;
        result.fill_char = ch;
        return result;
    }

    /// Set line boundary character
    pub fn withLineChar(self: AreaChart, ch: u21) AreaChart {
        var result = self;
        result.line_char = ch;
        return result;
    }

    /// Set minimum value for scale
    pub fn withMinVal(self: AreaChart, v: f32) AreaChart {
        var result = self;
        result.min_val = v;
        return result;
    }

    /// Set maximum value for scale
    pub fn withMaxVal(self: AreaChart, v: f32) AreaChart {
        var result = self;
        result.max_val = v;
        return result;
    }

    /// Set focused series index
    pub fn withFocused(self: AreaChart, idx: ?usize) AreaChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: AreaChart, s: Style) AreaChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: AreaChart, b: ?Block) AreaChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: AreaChart, s: Style) AreaChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Render the area chart to the buffer
    pub fn render(self: AreaChart, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (self.series_count == 0) return;
        if (inner.width == 0 or inner.height == 0) return;

        // Compute data range
        const range = computeRange(self);

        // Determine actual min/max for scaling (always include baseline y=0)
        var scale_min = range.min;
        var scale_max = range.max;

        // Override with explicit min/max if set
        if (self.min_val) |min| {
            scale_min = min;
        }
        if (self.max_val) |max| {
            scale_max = max;
        }

        // Ensure scale_min <= 0 <= scale_max for proper baseline
        if (scale_max < 0) {
            scale_max = 0;
        }
        if (scale_min > 0) {
            scale_min = 0;
        }

        // Render areas
        if (self.stacked) {
            renderStackedAreas(self, buf, inner, scale_min, scale_max);
        } else {
            renderNonStackedAreas(self, buf, inner, scale_min, scale_max);
        }
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Range of data values
const Range = struct {
    min: f32,
    max: f32,
};

/// Compute min/max across all series' data values (clamped to valid f32)
fn computeRange(chart: AreaChart) Range {
    var min: f32 = 0.0;
    var max: f32 = 0.0;
    var has_data = false;

    for (0..chart.series_count) |i| {
        const series = chart.series[i];
        const point_count = @min(series.values.len, AreaChart.MAX_POINTS);

        for (0..point_count) |j| {
            const val = clampValue(series.values[j]);
            if (!has_data) {
                min = val;
                max = val;
                has_data = true;
            } else {
                if (val < min) min = val;
                if (val > max) max = val;
            }
        }
    }

    // Ensure range includes baseline (0)
    if (min > 0) min = 0;
    if (max < 0) max = 0;

    // For stacked, need to compute cumulative sums
    if (chart.stacked and chart.series_count > 1) {
        // Find the max point count across all series (series lengths may differ)
        var max_points: usize = 0;
        for (0..chart.series_count) |i| {
            const count = @min(chart.series[i].values.len, AreaChart.MAX_POINTS);
            if (count > max_points) max_points = count;
        }

        if (max_points > 0) {
            for (0..max_points) |col| {
                var sum_pos: f32 = 0.0;
                var sum_neg: f32 = 0.0;

                for (0..chart.series_count) |i| {
                    const series = chart.series[i];
                    if (col < series.values.len) {
                        const val = clampValue(series.values[col]);
                        if (val >= 0) {
                            sum_pos += val;
                        } else {
                            sum_neg += val;
                        }
                    }
                }

                if (sum_pos > max) max = sum_pos;
                if (sum_neg < min) min = sum_neg;
            }
        }
    }

    return .{ .min = min, .max = max };
}

/// Clamp float value, handling NaN and Infinity
fn clampValue(val: f32) f32 {
    if (!math.isFinite(val)) {
        return 0.0;
    }
    return val;
}

/// Scale a value to a row index (0 = top, height-1 = bottom)
fn scaleY(value: f32, scale_min: f32, scale_max: f32, height: u16) u16 {
    if (height == 0) return 0;
    if (scale_max == scale_min or !math.isFinite(value)) {
        return height / 2;
    }

    const range = scale_max - scale_min;
    const normalized = (value - scale_min) / range;
    const scaled = normalized * @as(f32, @floatFromInt(height - 1));

    if (!math.isFinite(scaled)) {
        return height / 2;
    }

    const clamped = @min(@as(f32, @floatFromInt(height - 1)), @max(0.0, scaled));
    const row = @as(u16, @intFromFloat(clamped));

    // Invert because Y=0 is top of screen
    return height - 1 - @min(row, height - 1);
}

/// Map a point index to an x column in the area
fn getPointColumn(point_idx: usize, total_points: usize, width: u16) u16 {
    if (width == 0) return 0;
    if (total_points == 0) return 0;

    if (total_points == 1) {
        // Single point: center
        return width / 2;
    }

    // Multiple points: distribute evenly
    const x_float = @as(f32, @floatFromInt(point_idx)) / @as(f32, @floatFromInt(total_points - 1)) * @as(f32, @floatFromInt(width - 1));
    return @as(u16, @intFromFloat(x_float));
}

/// Render non-stacked areas (later series overwrites earlier in same cell)
fn renderNonStackedAreas(
    chart: AreaChart,
    buf: *Buffer,
    area: Rect,
    scale_min: f32,
    scale_max: f32,
) void {
    for (0..chart.series_count) |series_idx| {
        const series = chart.series[series_idx];
        const point_count = @min(series.values.len, AreaChart.MAX_POINTS);

        if (point_count == 0) continue;

        // Get baseline row (y=0 in data coordinates)
        const baseline_row = scaleY(0.0, scale_min, scale_max, area.height);

        // Determine style
        const is_focused = if (chart.focused) |f| f == series_idx else false;
        var series_style = series.style;
        if (is_focused and (chart.focused_style.bold or chart.focused_style.dim or
            chart.focused_style.italic or chart.focused_style.underline or
            chart.focused_style.blink or chart.focused_style.reverse or
            chart.focused_style.strikethrough or
            chart.focused_style.fg != null or chart.focused_style.bg != null)) {
            series_style = chart.focused_style;
        } else if (!is_focused and (series_style.fg == null and series_style.bg == null and
            !series_style.bold and !series_style.dim and
            !series_style.italic and !series_style.underline and
            !series_style.blink and !series_style.reverse and
            !series_style.strikethrough)) {
            series_style = chart.style;
        }

        // Render each point
        for (0..point_count) |point_idx| {
            const val = clampValue(series.values[point_idx]);
            const val_row = scaleY(val, scale_min, scale_max, area.height);

            // Map point to column
            const col_offset = getPointColumn(point_idx, point_count, area.width);
            const col_x = area.x + col_offset;

            // Fill from baseline to value
            if (val_row <= baseline_row) {
                // Value above baseline
                var row = val_row;
                while (row <= baseline_row) : (row += 1) {
                    if (row < area.height and col_x < area.x + area.width) {
                        const y_pos = area.y + row;
                        if (row == val_row and chart.show_line) {
                            // Top boundary: use line character
                            buf.set(col_x, y_pos, .{
                                .char = chart.line_char,
                                .style = series_style,
                            });
                        } else {
                            // Fill: use fill character
                            buf.set(col_x, y_pos, .{
                                .char = chart.fill_char,
                                .style = series_style,
                            });
                        }
                    }
                }
            } else {
                // Value below baseline
                var row = baseline_row;
                while (row <= val_row) : (row += 1) {
                    if (row < area.height and col_x < area.x + area.width) {
                        const y_pos = area.y + row;
                        if (row == val_row and chart.show_line) {
                            // Top boundary: use line character
                            buf.set(col_x, y_pos, .{
                                .char = chart.line_char,
                                .style = series_style,
                            });
                        } else {
                            // Fill: use fill character
                            buf.set(col_x, y_pos, .{
                                .char = chart.fill_char,
                                .style = series_style,
                            });
                        }
                    }
                }
            }
        }
    }
}

/// Render stacked areas (series cumulatively stack)
fn renderStackedAreas(
    chart: AreaChart,
    buf: *Buffer,
    area: Rect,
    scale_min: f32,
    scale_max: f32,
) void {
    if (area.width == 0 or area.height == 0) return;

    // Find maximum point count across all series
    var max_points: usize = 0;
    for (0..chart.series_count) |i| {
        const series = chart.series[i];
        const count = @min(series.values.len, AreaChart.MAX_POINTS);
        if (count > max_points) max_points = count;
    }

    if (max_points == 0) return;

    // For each column (point position)
    for (0..max_points) |point_idx| {
        const col_offset = getPointColumn(point_idx, max_points, area.width);
        const col_x = area.x + col_offset;

        if (col_x >= area.x + area.width) continue;

        // Track cumulative sum for stacking
        var cum_pos: f32 = 0.0; // cumulative positive sum
        var cum_neg: f32 = 0.0; // cumulative negative sum

        // Render each series at this column
        for (0..chart.series_count) |series_idx| {
            const series = chart.series[series_idx];
            if (point_idx >= series.values.len) continue;

            const val = clampValue(series.values[point_idx]);

            // Determine style
            const is_focused = if (chart.focused) |f| f == series_idx else false;
            var series_style = series.style;
            if (is_focused and (chart.focused_style.bold or chart.focused_style.dim or
                chart.focused_style.italic or chart.focused_style.underline or
                chart.focused_style.blink or chart.focused_style.reverse or
                chart.focused_style.strikethrough or
                chart.focused_style.fg != null or chart.focused_style.bg != null)) {
                series_style = chart.focused_style;
            } else if (!is_focused and (series_style.fg == null and series_style.bg == null and
                !series_style.bold and !series_style.dim and
                !series_style.italic and !series_style.underline and
                !series_style.blink and !series_style.reverse and
                !series_style.strikethrough)) {
                series_style = chart.style;
            }

            // Calculate stacked position
            var bottom_row: u16 = undefined;
            var top_row: u16 = undefined;

            if (val >= 0) {
                // Positive value: stack above previous
                const bottom_val = cum_pos;
                const top_val = cum_pos + val;
                bottom_row = scaleY(bottom_val, scale_min, scale_max, area.height);
                top_row = scaleY(top_val, scale_min, scale_max, area.height);
                cum_pos += val;
            } else {
                // Negative value: stack below previous
                const bottom_val = cum_neg + val;
                const top_val = cum_neg;
                bottom_row = scaleY(bottom_val, scale_min, scale_max, area.height);
                top_row = scaleY(top_val, scale_min, scale_max, area.height);
                cum_neg += val;
            }

            // Fill from bottom to top
            if (top_row <= bottom_row) {
                // Normal case: top < bottom (higher values are lower on screen)
                var row = top_row;
                while (row <= bottom_row) : (row += 1) {
                    if (row < area.height and col_x < area.x + area.width) {
                        const y_pos = area.y + row;
                        if (row == top_row and chart.show_line) {
                            // Top boundary
                            buf.set(col_x, y_pos, .{
                                .char = chart.line_char,
                                .style = series_style,
                            });
                        } else {
                            // Fill
                            buf.set(col_x, y_pos, .{
                                .char = chart.fill_char,
                                .style = series_style,
                            });
                        }
                    }
                }
            } else {
                // Inverted case
                var row = bottom_row;
                while (row <= top_row) : (row += 1) {
                    if (row < area.height and col_x < area.x + area.width) {
                        const y_pos = area.y + row;
                        if (row == top_row and chart.show_line) {
                            // Top boundary
                            buf.set(col_x, y_pos, .{
                                .char = chart.line_char,
                                .style = series_style,
                            });
                        } else {
                            // Fill
                            buf.set(col_x, y_pos, .{
                                .char = chart.fill_char,
                                .style = series_style,
                            });
                        }
                    }
                }
            }
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

// Tests are in tests/area_chart_test.zig per project convention
