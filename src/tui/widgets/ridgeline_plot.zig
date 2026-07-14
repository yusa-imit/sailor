//! RidgelinePlot Widget — stacked density silhouettes (joyplot style)
//!
//! The RidgelinePlot widget displays multiple data series as horizontal density
//! silhouettes stacked vertically, each rendered with a height-based glyph ramp.
//! Each series gets its own baseline row, and silhouettes can optionally overlap
//! into rows above (configurable).
//!
//! ## Features
//! - Up to 8 series (MAX_SERIES)
//! - Up to 64 bins per series (MAX_BINS)
//! - Shared or per-series scale normalization
//! - Top-to-bottom or bottom-to-top ordering (reverse flag)
//! - Configurable overlap between silhouettes
//! - Focused series highlighting
//! - Optional label column
//! - Block border support
//! - No heap allocations
//! - Robust handling of edge cases (empty, all-zero, single bin)
//! - Safe handling of out-of-range values (negative, inf, nan)
//!
//! ## Usage
//! ```zig
//! const series = [_]RidgelineSeries{
//!     .{ .label = "A", .values = &values_a },
//!     .{ .label = "B", .values = &values_b },
//! };
//!
//! const plot = RidgelinePlot.init()
//!     .withSeries(&series)
//!     .withSharedScale(true)
//!     .withOverlap(1)
//!     .withReverse(false);
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

/// Single series in a ridgeline plot
pub const RidgelineSeries = struct {
    /// Label for the series
    label: []const u8 = "",
    /// Data values (pre-binned density/frequency samples)
    values: []const f32 = &.{},
    /// Optional custom style for this series
    style: Style = .{},
};

pub const RidgelinePlot = struct {
    /// Maximum number of series (capped at 8 for rendering)
    pub const MAX_SERIES: usize = 8;
    /// Maximum number of bins per series
    pub const MAX_BINS: usize = 64;

    /// Array of series to display
    series: []const RidgelineSeries = &.{},
    /// Index of the focused series for highlighting (null = no focus)
    focused: ?usize = null,
    /// Whether to reverse series order (bottom-to-top instead of top-to-bottom)
    reverse: bool = false,
    /// Whether to use shared scale (all series use global max) or per-series scale
    shared_scale: bool = true,
    /// Number of rows silhouettes can rise above their baseline
    overlap: u16 = 0,
    /// Base style applied to all silhouettes
    style: Style = .{},
    /// Style for the focused series
    focused_style: Style = .{},
    /// Style for series labels
    label_style: Style = .{},
    /// Width of label column (0 = no labels)
    label_column_width: u16 = 0,
    /// Optional block border
    block: ?Block = null,

    /// Initialize a RidgelinePlot with all defaults
    pub fn init() RidgelinePlot {
        return .{};
    }

    /// Count of series to render (capped at MAX_SERIES)
    pub fn seriesCount(self: RidgelinePlot) usize {
        return @min(self.series.len, MAX_SERIES);
    }

    /// Set series array
    pub fn withSeries(self: RidgelinePlot, s: []const RidgelineSeries) RidgelinePlot {
        var result = self;
        result.series = s;
        return result;
    }

    /// Set focused series index
    pub fn withFocused(self: RidgelinePlot, idx: ?usize) RidgelinePlot {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set reverse order flag
    pub fn withReverse(self: RidgelinePlot, r: bool) RidgelinePlot {
        var result = self;
        result.reverse = r;
        return result;
    }

    /// Set shared_scale flag
    pub fn withSharedScale(self: RidgelinePlot, s: bool) RidgelinePlot {
        var result = self;
        result.shared_scale = s;
        return result;
    }

    /// Set overlap value
    pub fn withOverlap(self: RidgelinePlot, o: u16) RidgelinePlot {
        var result = self;
        result.overlap = o;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: RidgelinePlot, s: Style) RidgelinePlot {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: RidgelinePlot, s: Style) RidgelinePlot {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: RidgelinePlot, s: Style) RidgelinePlot {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set label_column_width
    pub fn withLabelColumnWidth(self: RidgelinePlot, w: u16) RidgelinePlot {
        var result = self;
        result.label_column_width = w;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: RidgelinePlot, b: ?Block) RidgelinePlot {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the ridgeline plot to the buffer
    pub fn render(self: RidgelinePlot, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        const n = self.seriesCount();
        if (n == 0) return;

        // Need minimum area for rendering
        if (inner.width < 2 or inner.height < 1) return;

        // Compute global max for shared scale (if needed)
        var global_max: f32 = 0.0;
        if (self.shared_scale) {
            for (self.series[0..n]) |series| {
                for (series.values) |val| {
                    const clamped = clampValue(val);
                    if (clamped > global_max) {
                        global_max = clamped;
                    }
                }
            }
        }

        // Handle edge case: all values are 0 or missing
        if (global_max == 0.0) {
            global_max = 1.0;
        }

        // Calculate content area (excluding label column)
        var content_area = inner;
        var label_col_width: u16 = 0;
        if (self.label_column_width > 0) {
            label_col_width = @min(self.label_column_width, content_area.width);
            content_area.x += label_col_width;
            content_area.width = if (content_area.width > label_col_width) content_area.width - label_col_width else 0;
        }

        // Calculate baseline rows
        const row_height_per_series = if (n > 0)
            @max(1, inner.height / @as(u16, @intCast(n)))
        else
            1;

        // Render each series
        for (0..n) |i| {
            const series_idx = if (self.reverse) n - 1 - i else i;
            const series = self.series[series_idx];

            // Calculate baseline row for this series
            const baseline_row = if (self.reverse)
                @as(u16, @intCast(i)) * row_height_per_series
            else
                @as(u16, @intCast(i)) * row_height_per_series;

            // Clamp baseline row to valid area
            if (baseline_row >= inner.height) continue;

            // Determine scale for this series
            var series_max: f32 = global_max;
            if (!self.shared_scale) {
                series_max = 0.0;
                for (series.values) |val| {
                    const clamped = clampValue(val);
                    if (clamped > series_max) {
                        series_max = clamped;
                    }
                }
                if (series_max == 0.0) {
                    series_max = 1.0;
                }
            }

            // Determine if this series is focused
            const is_focused = if (self.focused) |f| f == series_idx else false;

            // Determine style to use
            var series_style = series.style;
            if (is_focused) {
                // Apply focused style only if it's explicitly set (not empty)
                if (self.focused_style.bold or self.focused_style.dim or
                    self.focused_style.italic or self.focused_style.underline or
                    self.focused_style.blink or self.focused_style.reverse or
                    self.focused_style.strikethrough or
                    self.focused_style.fg != null or self.focused_style.bg != null) {
                    series_style = self.focused_style;
                }
            } else {
                // Use base style if series style is empty
                if (series_style.fg == null and series_style.bg == null and
                    !series_style.bold and !series_style.dim and
                    !series_style.italic and !series_style.underline and
                    !series_style.blink and !series_style.reverse and
                    !series_style.strikethrough) {
                    series_style = self.style;
                }
            }

            // Render label if label_column_width > 0
            if (label_col_width > 0) {
                renderSeriesLabel(buf, inner, baseline_row, series.label, self.label_style, label_col_width);
            }

            // Render silhouette for this series
            if (content_area.width > 0) {
                renderSilhouette(buf, content_area, baseline_row, series.values,
                                series_max, series_style, self.overlap, inner.height);
            }
        }
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Glyph ramp for block-height visualization (8 levels)
fn getBlockGlyph(level: u32) u21 {
    return switch (level) {
        0 => ' ',
        1 => '▁',
        2 => '▂',
        3 => '▃',
        4 => '▄',
        5 => '▅',
        6 => '▆',
        7 => '▇',
        else => '█',
    };
}

/// Clamp float value to [0, inf), handling negative/inf/nan
fn clampValue(val: f32) f32 {
    if (math.isNan(val) or !math.isFinite(val)) {
        return 0.0;
    }
    return @max(0.0, val);
}

/// Render label for a series
fn renderSeriesLabel(
    buf: *Buffer,
    area: Rect,
    baseline_row: u16,
    label: []const u8,
    label_style: Style,
    label_col_width: u16,
) void {
    if (label.len == 0) return;
    if (baseline_row >= area.height) return;

    const label_y = area.y + baseline_row;
    var label_x: u16 = area.x;

    // Render label characters (left-aligned, truncated to fit)
    for (label, 0..) |ch, i| {
        if (label_x >= area.x + label_col_width) break;
        if (i >= label.len) break;

        buf.set(label_x, label_y, .{
            .char = @as(u21, ch),
            .style = label_style,
        });
        label_x += 1;
    }

    // Fill remaining space with spaces
    while (label_x < area.x + label_col_width) {
        buf.set(label_x, label_y, .{
            .char = ' ',
            .style = label_style,
        });
        label_x += 1;
    }
}

/// Render silhouette for a series
fn renderSilhouette(
    buf: *Buffer,
    area: Rect,
    baseline_row: u16,
    values: []const f32,
    max_val: f32,
    style: Style,
    overlap: u16,
    total_height: u16,
) void {
    if (area.width == 0 or baseline_row >= total_height) return;
    if (values.len == 0 or max_val == 0.0) return;

    const max_bins = @min(values.len, RidgelinePlot.MAX_BINS);
    if (max_bins == 0) return;

    // Determine how many pixels wide each bin gets
    const pixels_per_bin = if (area.width > 0) @max(1, @as(f32, @floatFromInt(area.width)) / @as(f32, @floatFromInt(max_bins))) else 1;

    // Render each bin
    var bin_start_x: f32 = 0;
    for (0..max_bins) |bin_idx| {
        const val = clampValue(values[bin_idx]);

        // Normalize value to [0, 1]
        const normalized = if (max_val > 0.0) val / max_val else 0.0;

        // Clamp to [0, 1]
        const clamped_norm = @min(1.0, @max(0.0, normalized));

        // Map to glyph level (0-8)
        const level = @as(u32, @intFromFloat(clamped_norm * 8.0));
        const glyph = getBlockGlyph(level);

        // Determine pixel x position for this bin
        const bin_end_x = @as(f32, @floatFromInt(@as(u32, @intCast(bin_idx + 1)))) * pixels_per_bin;
        const x_floor = @as(u16, @intFromFloat(bin_start_x));

        // Render glyph at baseline
        if (x_floor < area.x + area.width and baseline_row < total_height) {
            const x_pos = area.x + x_floor;
            const y_pos = area.y + baseline_row;
            buf.set(x_pos, y_pos, .{
                .char = glyph,
                .style = style,
            });
        }

        // Render overlap rows above (if overlap > 0 and level > 1)
        if (overlap > 0 and level > 1) {
            const height_in_rows = @as(u16, @intFromFloat(clamped_norm * @as(f32, @floatFromInt(overlap + 1))));

            for (1..@min(height_in_rows + 1, overlap + 1)) |overlap_offset| {
                if (baseline_row < @as(u16, @intCast(overlap_offset))) {
                    // Would go above baseline, skip
                    break;
                }

                const overlap_row = baseline_row - @as(u16, @intCast(overlap_offset));
                if (overlap_row >= total_height) continue;

                if (x_floor < area.x + area.width) {
                    const x_pos = area.x + x_floor;
                    const y_pos = area.y + overlap_row;
                    buf.set(x_pos, y_pos, .{
                        .char = '█',
                        .style = style,
                    });
                }
            }
        }

        bin_start_x = bin_end_x;
    }
}

// ============================================================================
// Tests
// ============================================================================

// Tests are in tests/ridgeline_plot_test.zig per project convention
