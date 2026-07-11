//! ViolinPlot Widget — density distributions as centered silhouettes
//!
//! The ViolinPlot widget displays multiple data series as vertical density
//! silhouettes, each rendered symmetrically around a center column within
//! its horizontal band. All series share a global min/max scale for
//! cross-series comparison.
//!
//! ## Features
//! - Up to 8 series (MAX_SERIES)
//! - Up to 64 vertical bins (MAX_BINS)
//! - Shared value scale across all series
//! - Symmetric violin rendering around center column
//! - Focused series highlighting
//! - Optional label row at bottom
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const series = [_]ViolinSeries{
//!     .{ .label = "A", .values = &values_a },
//!     .{ .label = "B", .values = &values_b },
//! };
//!
//! const plot = ViolinPlot.init()
//!     .withSeries(&series)
//!     .withShowLabels(true)
//!     .withFocused(0);
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

/// Single series in a violin plot
pub const ViolinSeries = struct {
    /// Label for the series
    label: []const u8 = "",
    /// Data values
    values: []const f32 = &.{},
    /// Optional custom style for this series
    style: Style = .{},
};

pub const ViolinPlot = struct {
    /// Maximum number of series (capped at 8 for rendering)
    pub const MAX_SERIES: usize = 8;
    /// Maximum number of vertical bins
    pub const MAX_BINS: usize = 64;

    /// Array of series to display
    series: []const ViolinSeries = &.{},
    /// Index of the focused series for highlighting
    focused: usize = 0,
    /// Whether to render series labels
    show_labels: bool = true,
    /// Base style applied to all series
    style: Style = .{},
    /// Style for the focused series
    focused_style: Style = .{},
    /// Style for series labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a ViolinPlot with all defaults
    pub fn init() ViolinPlot {
        return .{};
    }

    /// Count of series to render (capped at MAX_SERIES)
    pub fn seriesCount(self: ViolinPlot) usize {
        return @min(self.series.len, MAX_SERIES);
    }

    /// Set series array
    pub fn withSeries(self: ViolinPlot, s: []const ViolinSeries) ViolinPlot {
        var result = self;
        result.series = s;
        return result;
    }

    /// Set focused series index
    pub fn withFocused(self: ViolinPlot, idx: usize) ViolinPlot {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: ViolinPlot, show: bool) ViolinPlot {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: ViolinPlot, s: Style) ViolinPlot {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: ViolinPlot, s: Style) ViolinPlot {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: ViolinPlot, s: Style) ViolinPlot {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: ViolinPlot, b: ?Block) ViolinPlot {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the violin plot to the buffer
    pub fn render(self: ViolinPlot, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;
        // Need minimum area to render
        if (area.width < 2 or area.height < 2) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        const n = self.seriesCount();
        if (n == 0) return;

        // Need minimum area to render
        if (inner.width == 0 or inner.height == 0) return;

        // ========== Step 1: Find global min/max across all values ==========
        var global_min: f32 = 0.0;
        var global_max: f32 = 0.0;
        var has_values = false;

        for (0..n) |i| {
            const series_values = self.series[i].values;
            for (series_values) |val| {
                if (!has_values) {
                    global_min = val;
                    global_max = val;
                    has_values = true;
                } else {
                    if (val < global_min) global_min = val;
                    if (val > global_max) global_max = val;
                }
            }
        }

        if (!has_values) return;

        // Handle zero-range case (min == max)
        if (global_min == global_max) {
            // Render all values at a single row in the middle
            renderConstantCase(self, buf, inner, n);
            return;
        }

        // ========== Step 2: Calculate bin height ==========
        var bin_height = inner.height;
        if (self.show_labels and inner.height > 0) {
            bin_height = inner.height - 1;
        }

        if (bin_height == 0) return;

        const num_bins = @min(MAX_BINS, bin_height);
        if (num_bins == 0) return;

        const value_range = global_max - global_min;
        const bin_width = value_range / @as(f32, @floatFromInt(num_bins));

        // ========== Step 3: Bin the data and compute max bin count ==========
        var bin_counts: [MAX_SERIES][MAX_BINS]usize = undefined;
        for (0..MAX_SERIES) |i| {
            for (0..MAX_BINS) |j| {
                bin_counts[i][j] = 0;
            }
        }

        var global_max_bin_count: usize = 0;

        for (0..n) |series_idx| {
            const series_values = self.series[series_idx].values;
            for (series_values) |val| {
                if (val >= global_min and val <= global_max) {
                    var bin_idx: usize = 0;
                    if (bin_width > 0.0) {
                        bin_idx = @min(@as(usize, @intFromFloat((val - global_min) / bin_width)), num_bins - 1);
                    }
                    bin_counts[series_idx][bin_idx] += 1;
                    if (bin_counts[series_idx][bin_idx] > global_max_bin_count) {
                        global_max_bin_count = bin_counts[series_idx][bin_idx];
                    }
                }
            }
        }

        if (global_max_bin_count == 0) return;

        // ========== Step 4: Calculate band width per series ==========
        const band_width = inner.width / n;
        if (band_width == 0) return;

        // ========== Step 5: Render violins ==========
        for (0..n) |series_idx| {
            const band_start: u16 = inner.x + @as(u16, @intCast(series_idx * band_width));
            const band_end_exclusive: u16 = if (series_idx + 1 == n)
                inner.x + inner.width
            else
                band_start + @as(u16, @intCast(band_width));

            const actual_band_width = band_end_exclusive - band_start;
            if (actual_band_width == 0) continue;

            const center_col: u16 = band_start + (actual_band_width / 2);

            // Render each bin row from top (high values) to bottom (low values)
            for (0..num_bins) |bin_idx| {
                // Rows are numbered from top (bin_idx=num_bins-1) to bottom (bin_idx=0)
                const inverted_bin_idx = num_bins - 1 - bin_idx;
                const row_y: u16 = inner.y + @as(u16, @intCast(inverted_bin_idx));

                const count = bin_counts[series_idx][bin_idx];
                if (count == 0) continue;

                // Calculate how many columns to fill (symmetric around center)
                const fill_width_f32: f32 = (@as(f32, @floatFromInt(actual_band_width)) * @as(f32, @floatFromInt(count))) / @as(f32, @floatFromInt(global_max_bin_count));
                const fill_width_half: u16 = @intFromFloat(@min(fill_width_f32 / 2.0, @as(f32, @floatFromInt(actual_band_width))));

                // Determine style
                var cell_style = self.series[series_idx].style;
                if (self.style.bold or self.style.dim or self.style.italic or self.style.underline or
                    self.style.blink or self.style.reverse or self.style.strikethrough or
                    self.style.fg != null or self.style.bg != null) {
                    // Merge with base style
                    if (cell_style.fg == null and self.style.fg != null) cell_style.fg = self.style.fg;
                    if (cell_style.bg == null and self.style.bg != null) cell_style.bg = self.style.bg;
                    if (!cell_style.bold and self.style.bold) cell_style.bold = true;
                    if (!cell_style.dim and self.style.dim) cell_style.dim = true;
                    if (!cell_style.italic and self.style.italic) cell_style.italic = true;
                    if (!cell_style.underline and self.style.underline) cell_style.underline = true;
                    if (!cell_style.blink and self.style.blink) cell_style.blink = true;
                    if (!cell_style.reverse and self.style.reverse) cell_style.reverse = true;
                    if (!cell_style.strikethrough and self.style.strikethrough) cell_style.strikethrough = true;
                }

                if (series_idx == self.focused) {
                    cell_style = self.focused_style;
                }

                // Draw left side (from center-1 leftward)
                if (center_col > band_start) {
                    var x: i32 = @as(i32, @intCast(center_col)) - 1;
                    var remaining = fill_width_half;
                    while (remaining > 0 and x >= @as(i32, @intCast(band_start))) : (x -= 1) {
                        if (row_y < buf.height and @as(u16, @intCast(x)) < buf.width) {
                            buf.set(@as(u16, @intCast(x)), row_y, Cell.init('█', cell_style));
                        }
                        remaining -= 1;
                    }
                }

                // Draw center
                if (center_col < buf.width and row_y < buf.height) {
                    buf.set(center_col, row_y, Cell.init('█', cell_style));
                }

                // Draw right side (from center+1 rightward)
                if (center_col < band_end_exclusive - 1) {
                    var x: u16 = center_col + 1;
                    var remaining = fill_width_half;
                    while (remaining > 0 and x < band_end_exclusive and x < buf.width) : (x += 1) {
                        if (row_y < buf.height) {
                            buf.set(x, row_y, Cell.init('█', cell_style));
                        }
                        remaining -= 1;
                    }
                }
            }
        }

        // ========== Step 6: Render labels if enabled ==========
        if (self.show_labels and bin_height < inner.height) {
            const label_row: u16 = inner.y + @as(u16, @intCast(bin_height));

            for (0..n) |series_idx| {
                const label = self.series[series_idx].label;
                if (label.len == 0) continue;

                const band_start: u16 = inner.x + @as(u16, @intCast(series_idx * band_width));
                const band_end_exclusive: u16 = if (series_idx + 1 == n)
                    inner.x + inner.width
                else
                    band_start + @as(u16, @intCast(band_width));

                const actual_band_width = band_end_exclusive - band_start;
                if (actual_band_width == 0) continue;

                // Center the label in the band
                const label_start_col: u16 = band_start + (actual_band_width / 2);

                // Determine label style
                var lbl_style = self.label_style;
                if (series_idx == self.focused) {
                    lbl_style = self.focused_style;
                }

                // Write label character(s)
                var col: u16 = label_start_col;
                for (label) |ch| {
                    if (col >= buf.width or label_row >= buf.height) break;
                    if (col >= band_start and col < band_end_exclusive) {
                        buf.set(col, label_row, Cell.init(ch, lbl_style));
                    }
                    col += 1;
                }
            }
        }
    }
};

/// Special case: all values are identical (global_min == global_max)
fn renderConstantCase(self: ViolinPlot, buf: *Buffer, inner: Rect, n: usize) void {
    const band_width = inner.width / n;
    if (band_width == 0) return;

    // Calculate usable height (reserve 1 row for labels if needed)
    var usable_height = inner.height;
    if (self.show_labels and inner.height > 0) {
        usable_height = inner.height - 1;
    }
    if (usable_height == 0) return;

    // Render multiple rows around center for symmetry
    const middle_row_f32: f32 = @as(f32, @floatFromInt(inner.y)) + @as(f32, @floatFromInt(usable_height)) / 2.0;
    const middle_row: u16 = @as(u16, @intFromFloat(middle_row_f32));

    // Determine how many rows to fill (at least 1 above, 1 below for symmetry)
    const min_rows = if (usable_height < 3) usable_height else usable_height / 2;

    for (0..n) |series_idx| {
        const band_start: u16 = inner.x + @as(u16, @intCast(series_idx * band_width));
        const band_end_exclusive: u16 = if (series_idx + 1 == n)
            inner.x + inner.width
        else
            band_start + @as(u16, @intCast(band_width));

        const actual_band_width = band_end_exclusive - band_start;
        if (actual_band_width == 0) continue;

        var cell_style = self.series[series_idx].style;
        if (series_idx == self.focused) {
            cell_style = self.focused_style;
        }

        // Fill rows around middle for symmetry
        if (middle_row >= inner.y) {
            // Fill above middle
            var row: i32 = @as(i32, @intCast(middle_row));
            var rows_filled: usize = 0;
            while (rows_filled < min_rows and row >= @as(i32, @intCast(inner.y))) : (row -= 1) {
                if (row >= 0 and row < @as(i32, @intCast(buf.height))) {
                    var x: u16 = band_start;
                    while (x < band_end_exclusive and x < buf.width) : (x += 1) {
                        buf.set(x, @as(u16, @intCast(row)), Cell.init('█', cell_style));
                    }
                }
                rows_filled += 1;
            }
        }

        if (middle_row + 1 < inner.y + usable_height) {
            // Fill below middle (starting from middle + 1)
            var row: u16 = middle_row + 1;
            var rows_filled: usize = 0;
            while (rows_filled < min_rows and row < inner.y + usable_height and row < buf.height) : (row += 1) {
                var x: u16 = band_start;
                while (x < band_end_exclusive and x < buf.width) : (x += 1) {
                    buf.set(x, row, Cell.init('█', cell_style));
                }
                rows_filled += 1;
            }
        }
    }

    // Render labels if enabled
    if (self.show_labels and inner.height > 1) {
        const label_row: u16 = inner.y + @as(u16, @intCast(inner.height)) - 1;
        if (label_row < buf.height) {
            for (0..n) |series_idx| {
                const label = self.series[series_idx].label;
                if (label.len == 0) continue;

                const band_start: u16 = inner.x + @as(u16, @intCast(series_idx * band_width));
                const band_end_exclusive: u16 = if (series_idx + 1 == n)
                    inner.x + inner.width
                else
                    band_start + @as(u16, @intCast(band_width));

                const actual_band_width = band_end_exclusive - band_start;
                if (actual_band_width == 0) continue;

                var lbl_style = self.label_style;
                if (series_idx == self.focused) {
                    lbl_style = self.focused_style;
                }

                var col: u16 = band_start + (actual_band_width / 2);
                for (label) |ch| {
                    if (col >= buf.width or label_row >= buf.height) break;
                    if (col >= band_start and col < band_end_exclusive) {
                        buf.set(col, label_row, Cell.init(ch, lbl_style));
                    }
                    col += 1;
                }
            }
        }
    }
}
