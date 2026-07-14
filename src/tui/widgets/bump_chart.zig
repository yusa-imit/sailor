//! BumpChart Widget — multi-time-point rank-over-time lines per category
//!
//! The BumpChart widget displays rank-over-time data for multiple series/categories.
//! Each series draws a polyline connecting its ranks across time points, where rank 1 (best)
//! appears at the top row, and higher rank numbers appear lower. Direction characters ('/', '\', '─')
//! indicate whether rank improved, worsened, or stayed flat between adjacent timepoints.
//!
//! ## Features
//! - Up to 8 series (MAX_SERIES)
//! - Up to 16 time points per series (MAX_TIMEPOINTS)
//! - Rank-to-row mapping: rank 1 (best) at top, higher ranks lower
//! - Direction-based glyph rendering (/, \, ─)
//! - Rank ties: multiple series at same rank appear on same row without crashing
//! - Optional per-series end labels (show_labels)
//! - Optional timepoint header labels (show_timepoint_labels)
//! - Focused series highlighting with precedence-based styling
//! - Block border support
//! - No heap allocations
//! - Robust out-of-range handling (rank==0, rank>maxRank clamp safely)
//!
//! ## Usage
//! ```zig
//! var series = [_]BumpSeries{
//!     .{ .label = "Team A", .ranks = &[_]u32{ 1, 2, 3, 2 } },
//!     .{ .label = "Team B", .ranks = &[_]u32{ 3, 1, 2, 1 } },
//! };
//!
//! var labels = [_][]const u8{ "2020", "2021", "2022", "2023" };
//!
//! const chart = BumpChart.init()
//!     .withSeries(&series)
//!     .withTimepointLabels(&labels)
//!     .withShowTimepointLabels(true)
//!     .withShowLabels(true)
//!     .withFocused(0)
//!     .withBlock(.{});
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

/// Single series in a bump chart
pub const BumpSeries = struct {
    /// Label for this series (e.g., team/category name)
    label: []const u8 = "",
    /// Ranks at each timepoint (1-based, 1=best/top rank)
    ranks: []const u32 = &.{},
    /// Optional per-series style override
    style: Style = .{},
};

/// BumpChart widget for multi-time-point rank-over-time visualization
pub const BumpChart = struct {
    /// Maximum number of series (capped at 8 for rendering)
    pub const MAX_SERIES: usize = 8;
    /// Maximum number of timepoints per series
    pub const MAX_TIMEPOINTS: usize = 16;

    /// Array of series to display
    series: []const BumpSeries = &.{},
    /// Index of the focused series for highlighting
    focused: usize = 0,
    /// Optional column headers (one per timepoint)
    timepoint_labels: []const []const u8 = &.{},
    /// Whether to render per-series end labels (right of last timepoint)
    show_labels: bool = true,
    /// Whether to render timepoint header row (column labels)
    show_timepoint_labels: bool = false,
    /// Base style applied to all elements
    style: Style = .{},
    /// Style for rank-connection lines
    line_style: Style = .{},
    /// Style for focused series (overrides per-series style when set)
    focused_style: Style = .{},
    /// Style for series end labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a BumpChart with all defaults
    pub fn init() BumpChart {
        return .{};
    }

    /// Count of series to render (capped at MAX_SERIES)
    pub fn seriesCount(self: BumpChart) usize {
        return @min(self.series.len, MAX_SERIES);
    }

    /// Count of timepoints to render (capped at MAX_TIMEPOINTS)
    /// Returns the maximum ranks.len across all series, or 0 if no series
    pub fn timepointCount(self: BumpChart) usize {
        if (self.series.len == 0) return 0;
        var max_len: usize = 0;
        for (0..@min(self.series.len, MAX_SERIES)) |i| {
            const len = @min(self.series[i].ranks.len, MAX_TIMEPOINTS);
            if (len > max_len) max_len = len;
        }
        return max_len;
    }

    /// Maximum rank value across all series/timepoints
    /// Returns 0 if no series or all ranks empty
    pub fn maxRank(self: BumpChart) u32 {
        var max: u32 = 0;
        for (0..@min(self.series.len, MAX_SERIES)) |i| {
            for (self.series[i].ranks) |rank| {
                if (rank > max) max = rank;
            }
        }
        return max;
    }

    /// Set series array
    pub fn withSeries(self: BumpChart, s: []const BumpSeries) BumpChart {
        var result = self;
        result.series = s;
        return result;
    }

    /// Set focused series index
    pub fn withFocused(self: BumpChart, idx: usize) BumpChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set timepoint labels array
    pub fn withTimepointLabels(self: BumpChart, labels: []const []const u8) BumpChart {
        var result = self;
        result.timepoint_labels = labels;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: BumpChart, show: bool) BumpChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_timepoint_labels flag
    pub fn withShowTimepointLabels(self: BumpChart, show: bool) BumpChart {
        var result = self;
        result.show_timepoint_labels = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: BumpChart, s: Style) BumpChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set line_style
    pub fn withLineStyle(self: BumpChart, s: Style) BumpChart {
        var result = self;
        result.line_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: BumpChart, s: Style) BumpChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: BumpChart, s: Style) BumpChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: BumpChart, b: ?Block) BumpChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the bump chart to the buffer
    pub fn render(self: BumpChart, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        // Need valid inner area
        if (inner.width == 0 or inner.height == 0) return;

        const n_series = self.seriesCount();
        const n_timepoints = self.timepointCount();

        // Early exit if no series or timepoints
        if (n_series == 0 or n_timepoints == 0) return;

        // Reserve row for timepoint labels if enabled
        var plot_area = inner;
        var timepoint_labels_row_idx: ?u16 = null;
        if (self.show_timepoint_labels and plot_area.height > 0) {
            timepoint_labels_row_idx = plot_area.y;
            plot_area.y += 1;
            if (plot_area.height > 0) plot_area.height -= 1;
        }

        // Reserve column for end labels if enabled
        var labels_column_width: u16 = 0;
        if (self.show_labels) {
            labels_column_width = 8; // default label width
            if (plot_area.width > labels_column_width) {
                plot_area.width -= labels_column_width;
            } else {
                labels_column_width = 0; // not enough width
            }
        }

        if (plot_area.width == 0 or plot_area.height == 0) return;

        // Render timepoint labels if enabled
        if (self.show_timepoint_labels and timepoint_labels_row_idx != null) {
            renderTimepointLabels(buf, inner, timepoint_labels_row_idx.?, n_timepoints, self.timepoint_labels);
        }

        // Get max rank for row scaling
        const max_rank = self.maxRank();

        // Draw non-focused series first
        for (0..n_series) |series_idx| {
            if (series_idx == self.focused) continue; // Skip focused, draw it last
            drawSeries(buf, plot_area, self.series[series_idx], n_timepoints, max_rank, self.line_style, self.style);
        }

        // Draw focused series last (on top)
        if (self.focused < n_series) {
            // Check if focused_style is explicitly set
            const focused_style_is_set = self.focused_style.bold or self.focused_style.dim or
                self.focused_style.italic or self.focused_style.underline or self.focused_style.blink or
                self.focused_style.reverse or self.focused_style.strikethrough or
                self.focused_style.fg != null or self.focused_style.bg != null;

            const series_style = if (focused_style_is_set) self.focused_style else self.series[self.focused].style;
            drawSeries(buf, plot_area, self.series[self.focused], n_timepoints, max_rank, self.line_style, series_style);
        }

        // Render end labels if enabled
        if (self.show_labels and labels_column_width > 0) {
            renderEndLabels(buf, plot_area, n_series, self.series, n_timepoints, max_rank, self.label_style);
        }
    }
};

/// Render timepoint labels in a header row
fn renderTimepointLabels(buf: *Buffer, area: Rect, row_idx: u16, n_timepoints: usize, labels: []const []const u8) void {
    for (0..n_timepoints) |tp_idx| {
        const x = timepointX(area, tp_idx, n_timepoints);
        if (x >= area.x and x < area.x + area.width and row_idx >= area.y and row_idx < area.y + area.height) {
            if (tp_idx < labels.len and labels[tp_idx].len > 0) {
                // Render first character of label
                const char = labels[tp_idx][0];
                buf.set(x, row_idx, Cell.init(char, .{}));
            }
        }
    }
}

/// Render end labels at the right of the plot area
fn renderEndLabels(buf: *Buffer, plot_area: Rect, n_series: usize, series: []const BumpSeries,
                    n_timepoints: usize, max_rank: u32, label_style: Style) void {
    if (plot_area.width == 0 or plot_area.height == 0) return;

    const label_x = plot_area.x + plot_area.width;

    for (0..n_series) |series_idx| {
        if (series_idx >= series.len) break;
        const ser = series[series_idx];
        if (ser.label.len == 0) continue;

        // Find the row for the last timepoint
        if (n_timepoints > 0 and ser.ranks.len > 0) {
            const last_rank_idx = @min(n_timepoints - 1, ser.ranks.len - 1);
            const rank = ser.ranks[last_rank_idx];
            const row = rankToRow(plot_area, rank, max_rank);

            if (row >= plot_area.y and row < plot_area.y + plot_area.height) {
                // Render first character of label at label_x, row
                if (label_x < buf.width) {
                    const char = ser.label[0];
                    buf.set(label_x, row, Cell.init(char, label_style));
                }
            }
        }
    }
}

/// Draw a single series as a polyline
fn drawSeries(buf: *Buffer, plot_area: Rect, series: BumpSeries,
              n_timepoints: usize, max_rank: u32, line_style: Style, series_style: Style) void {
    if (plot_area.width == 0 or plot_area.height == 0) return;
    if (n_timepoints == 0 or series.ranks.len == 0) return;

    const num_tp = @min(n_timepoints, series.ranks.len);
    if (num_tp == 0) return;

    // Draw each point and connecting segments
    for (0..num_tp) |tp_idx| {
        const rank = series.ranks[tp_idx];
        const row = rankToRow(plot_area, rank, max_rank);

        // Draw point at this timepoint
        const x = timepointX(plot_area, tp_idx, n_timepoints);

        if (x >= plot_area.x and x < plot_area.x + plot_area.width and
            row >= plot_area.y and row < plot_area.y + plot_area.height) {
            // Draw a glyph for the rank point
            const cell_char = '●';
            const cell_style = if (line_style.fg != null or line_style.bg != null or line_style.bold or line_style.dim or line_style.italic or line_style.underline or line_style.blink or line_style.reverse or line_style.strikethrough) line_style else series_style;
            buf.set(x, row, Cell.init(cell_char, cell_style));
        }

        // Draw connecting segment to next timepoint
        if (tp_idx < num_tp - 1) {
            const next_rank = series.ranks[tp_idx + 1];
            const next_row = rankToRow(plot_area, next_rank, max_rank);
            const next_x = timepointX(plot_area, tp_idx + 1, n_timepoints);

            // Determine direction character
            const dir_char: u21 = if (next_rank < rank)
                '/'  // rank improved (decreased)
            else if (next_rank > rank)
                '\\'  // rank worsened (increased)
            else
                '─'; // rank unchanged

            const segment_style = if (line_style.fg != null or line_style.bg != null or line_style.bold or line_style.dim or line_style.italic or line_style.underline or line_style.blink or line_style.reverse or line_style.strikethrough) line_style else series_style;

            // Draw segment between (x, row) and (next_x, next_row)
            drawLineSegment(buf, plot_area, @as(i32, @intCast(x)), @as(i32, @intCast(row)),
                           @as(i32, @intCast(next_x)), @as(i32, @intCast(next_row)), dir_char, segment_style);
        }
    }
}

/// Draw a line segment between two points using a direction character
fn drawLineSegment(buf: *Buffer, area: Rect, x0: i32, y0: i32, x1: i32, y1: i32, dir_char: u21, style: Style) void {
    // Use Bresenham-like line drawing with direction character
    const dx = x1 - x0;
    const dy = y1 - y0;

    if (dx == 0 and dy == 0) return; // No segment to draw

    // Determine number of steps
    const steps = @max(@abs(dx), @abs(dy));
    if (steps == 0) return;

    const steps_f = @as(f32, @floatFromInt(steps));
    const dx_f = @as(f32, @floatFromInt(dx)) / steps_f;
    const dy_f = @as(f32, @floatFromInt(dy)) / steps_f;

    for (1..steps) |i| {
        const frac = @as(f32, @floatFromInt(i)) / steps_f;
        const x = @as(i32, @intFromFloat(@as(f32, @floatFromInt(x0)) + dx_f * frac + 0.5));
        const y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(y0)) + dy_f * frac + 0.5));

        // Bounds check
        if (x >= 0 and y >= 0) {
            const ux: u16 = @intCast(x);
            const uy: u16 = @intCast(y);
            if (ux >= area.x and ux < area.x + area.width and
                uy >= area.y and uy < area.y + area.height) {
                buf.set(ux, uy, Cell.init(dir_char, style));
            }
        }
    }
}

/// Convert a rank value to a row index in the plot area
/// Rank 1 (best) maps to top row, higher ranks map lower
fn rankToRow(plot_area: Rect, rank: u32, max_rank: u32) u16 {
    // Clamp invalid ranks
    if (rank == 0 or rank > max_rank) {
        // Clamp rank to valid range [1, max_rank]
        const clamped = if (rank == 0) 1 else max_rank;
        return rankToRowSafe(plot_area, clamped, max_rank);
    }
    return rankToRowSafe(plot_area, rank, max_rank);
}

/// Internal safe rank-to-row conversion (assumes rank is in valid range)
fn rankToRowSafe(plot_area: Rect, rank: u32, max_rank: u32) u16 {
    if (plot_area.height == 0) return plot_area.y;

    // If max_rank is 0 or 1, all ranks map to the top row
    if (max_rank <= 1) {
        return plot_area.y;
    }

    // Formula: row = plot_area.y + round((rank - 1) / (max_rank - 1) * (height - 1))
    // Inverted: lower rank number = higher on screen (smaller row index)
    const rank_f = @as(f32, @floatFromInt(rank));
    const max_rank_f = @as(f32, @floatFromInt(max_rank));
    const height_f = @as(f32, @floatFromInt(plot_area.height));

    const frac = (rank_f - 1.0) / (max_rank_f - 1.0);
    const row_offset_f = frac * (height_f - 1.0);
    const row_offset = @as(u16, @intFromFloat(row_offset_f + 0.5));

    return plot_area.y + @min(row_offset, plot_area.height - 1);
}

/// Calculate x coordinate for a timepoint at given index
fn timepointX(area: Rect, tp_idx: usize, n_timepoints: usize) u16 {
    if (n_timepoints == 1) {
        // Single timepoint: center it
        return area.x + area.width / 2;
    }

    const idx_f = @as(f32, @floatFromInt(tp_idx));
    const n_f = @as(f32, @floatFromInt(n_timepoints - 1));
    const frac = idx_f / n_f;
    const x_offset = @as(u16, @intFromFloat(frac * @as(f32, @floatFromInt(area.width - 1))));
    return area.x + x_offset;
}
