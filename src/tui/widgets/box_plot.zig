//! BoxPlot Widget — box-and-whisker plots with quartile distribution stats
//!
//! The BoxPlot widget displays multiple data series as box-and-whisker plots,
//! showing five-number-summary statistics (min, Q1, median, Q3, max) and outliers.
//! Each series gets a vertical column band with a centered box. All series share
//! a global value scale for cross-series comparison.
//!
//! ## Features
//! - Up to 8 series (MAX_SERIES)
//! - Up to 64 samples per series (MAX_SAMPLES)
//! - Five-number-summary with linear interpolation percentiles
//! - Outlier detection (1.5x IQR beyond Q1/Q3)
//! - Shared value scale across all series
//! - Focused series highlighting
//! - Optional label row at bottom
//! - Block border support
//! - No heap allocations
//!
//! ## Usage
//! ```zig
//! const series = [_]BoxPlotSeries{
//!     .{ .label = "A", .values = &values_a },
//!     .{ .label = "B", .values = &values_b },
//! };
//!
//! const plot = BoxPlot.init()
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

/// Single series in a box plot
pub const BoxPlotSeries = struct {
    /// Label for the series
    label: []const u8 = "",
    /// Data values
    values: []const f32 = &.{},
    /// Optional custom style for this series
    style: Style = .{},
};

/// Five-number summary statistics (min, Q1, median, Q3, max)
pub const FiveNumberSummary = struct {
    min: f32 = 0.0,
    q1: f32 = 0.0,
    median: f32 = 0.0,
    q3: f32 = 0.0,
    max: f32 = 0.0,
    whisker_low: f32 = 0.0,
    whisker_high: f32 = 0.0,
};

/// Compute five-number-summary for values using linear interpolation percentiles
pub fn fiveNumberSummary(values: []const f32) FiveNumberSummary {
    if (values.len == 0) {
        return .{};
    }

    // Copy values to stack buffer (cap at MAX_SAMPLES)
    var scratch: [BoxPlot.MAX_SAMPLES]f32 = undefined;
    const n = @min(values.len, BoxPlot.MAX_SAMPLES);
    @memcpy(scratch[0..n], values[0..n]);

    // Sort in place using insertion sort
    for (1..n) |i| {
        const key = scratch[i];
        var j: i32 = @as(i32, @intCast(i)) - 1;
        while (j >= 0 and scratch[@as(usize, @intCast(j))] > key) : (j -= 1) {
            scratch[@as(usize, @intCast(j + 1))] = scratch[@as(usize, @intCast(j))];
        }
        scratch[@as(usize, @intCast(j + 1))] = key;
    }

    const sorted = scratch[0..n];
    const min_val = sorted[0];
    const max_val = sorted[n - 1];

    // Linear interpolation percentile (R-7 method)
    // idx = p * (n - 1)
    const percentile = struct {
        fn calc(data: []const f32, p: f32) f32 {
            if (data.len == 1) return data[0];
            const n_f32 = @as(f32, @floatFromInt(data.len));
            const idx = p * (n_f32 - 1.0);
            const lo_idx = @as(usize, @intFromFloat(@floor(idx)));
            const hi_idx = @min(lo_idx + 1, data.len - 1);
            const frac = idx - @as(f32, @floatFromInt(lo_idx));
            return data[lo_idx] + (data[hi_idx] - data[lo_idx]) * frac;
        }
    };

    const q1 = percentile.calc(sorted, 0.25);
    const median = percentile.calc(sorted, 0.5);
    const q3 = percentile.calc(sorted, 0.75);

    const iqr = q3 - q1;
    const whisker_low_fence = q1 - 1.5 * iqr;
    const whisker_high_fence = q3 + 1.5 * iqr;

    // Find actual whisker endpoints (min/max within fence)
    var whisker_low = q1; // default: no lower whisker
    var whisker_high = q3; // default: no upper whisker

    // Find minimum value within whisker_low_fence
    for (sorted) |val| {
        if (val >= whisker_low_fence) {
            whisker_low = val;
            break;
        }
    }

    // Find maximum value within whisker_high_fence
    for (0..sorted.len) |i| {
        const idx = sorted.len - 1 - i;
        const val = sorted[idx];
        if (val <= whisker_high_fence) {
            whisker_high = val;
            break;
        }
    }

    return .{
        .min = min_val,
        .q1 = q1,
        .median = median,
        .q3 = q3,
        .max = max_val,
        .whisker_low = whisker_low,
        .whisker_high = whisker_high,
    };
}

pub const BoxPlot = struct {
    /// Maximum number of series (capped at 8 for rendering)
    pub const MAX_SERIES: usize = 8;
    /// Maximum number of samples per series
    pub const MAX_SAMPLES: usize = 64;

    /// Array of series to display
    series: []const BoxPlotSeries = &.{},
    /// Index of the focused series for highlighting
    focused: usize = 0,
    /// Whether to render series labels
    show_labels: bool = true,
    /// Whether to show outlier markers
    show_outliers: bool = true,
    /// Base style applied to all series
    style: Style = .{},
    /// Style for box elements
    box_style: Style = .{},
    /// Style for median line
    median_style: Style = .{},
    /// Style for whisker lines
    whisker_style: Style = .{},
    /// Style for outlier markers
    outlier_style: Style = .{},
    /// Style for the focused series
    focused_style: Style = .{},
    /// Style for series labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a BoxPlot with all defaults
    pub fn init() BoxPlot {
        return .{};
    }

    /// Count of series to render (capped at MAX_SERIES)
    pub fn seriesCount(self: BoxPlot) usize {
        return @min(self.series.len, MAX_SERIES);
    }

    /// Set series array
    pub fn withSeries(self: BoxPlot, s: []const BoxPlotSeries) BoxPlot {
        var result = self;
        result.series = s;
        return result;
    }

    /// Set focused series index
    pub fn withFocused(self: BoxPlot, idx: usize) BoxPlot {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: BoxPlot, show: bool) BoxPlot {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_outliers flag
    pub fn withShowOutliers(self: BoxPlot, show: bool) BoxPlot {
        var result = self;
        result.show_outliers = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: BoxPlot, s: Style) BoxPlot {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set box_style
    pub fn withBoxStyle(self: BoxPlot, s: Style) BoxPlot {
        var result = self;
        result.box_style = s;
        return result;
    }

    /// Set median_style
    pub fn withMedianStyle(self: BoxPlot, s: Style) BoxPlot {
        var result = self;
        result.median_style = s;
        return result;
    }

    /// Set whisker_style
    pub fn withWhiskerStyle(self: BoxPlot, s: Style) BoxPlot {
        var result = self;
        result.whisker_style = s;
        return result;
    }

    /// Set outlier_style
    pub fn withOutlierStyle(self: BoxPlot, s: Style) BoxPlot {
        var result = self;
        result.outlier_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: BoxPlot, s: Style) BoxPlot {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: BoxPlot, s: Style) BoxPlot {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: BoxPlot, b: ?Block) BoxPlot {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the box plot to the buffer
    pub fn render(self: BoxPlot, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;
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

        // ========== Step 1: Compute summaries and find global min/max ==========
        var summaries: [MAX_SERIES]FiveNumberSummary = undefined;
        var global_min: f32 = 0.0;
        var global_max: f32 = 0.0;
        var has_values = false;

        for (0..n) |i| {
            const series_vals = self.series[i].values;
            if (series_vals.len == 0) {
                summaries[i] = .{};
            } else {
                summaries[i] = fiveNumberSummary(series_vals);
                const s = summaries[i];

                if (!has_values) {
                    global_min = s.whisker_low;
                    global_max = s.whisker_high;
                    has_values = true;
                } else {
                    if (s.whisker_low < global_min) global_min = s.whisker_low;
                    if (s.whisker_high > global_max) global_max = s.whisker_high;
                }
            }
        }

        if (!has_values) return;

        // ========== Step 2: Calculate plot height and label row reservation ==========
        var plot_height = inner.height;
        if (self.show_labels and inner.height > 0) {
            plot_height = inner.height - 1;
        }

        if (plot_height == 0) return;

        // ========== Step 3: Calculate value-to-row mapping ==========
        const valueToRow = struct {
            fn calc(value: f32, min_val: f32, max_val: f32, height: usize, plot_y: usize) usize {
                if (max_val == min_val) {
                    // Degenerate case: all values identical, center in middle row
                    return plot_y + height / 2;
                }
                const normalized = (value - min_val) / (max_val - min_val);
                const row_offset = @as(f32, @floatFromInt(height - 1)) * normalized;
                const row_from_top = @as(i32, @intFromFloat(@round(row_offset)));
                const row_from_bottom: i32 = @as(i32, @intCast(height - 1)) - row_from_top;
                const final_row = @max(0, row_from_bottom);
                return plot_y + @as(usize, @intCast(final_row)); // invert: top=max, bottom=min
            }
        };

        // ========== Step 4: Render per-series boxes ==========
        const band_width = if (n > 0) (inner.width / @as(usize, @intCast(n))) else inner.width;

        for (0..n) |i| {
            const series_vals = self.series[i].values;
            if (series_vals.len == 0) continue;

            const summary = summaries[i];
            const band_start = inner.x + i * band_width;
            const band_center = band_start + band_width / 2;

            // Determine which style to use (focused or regular)
            const use_focused = (i == self.focused);
            const series_style = self.series[i].style;
            const series_has_style = series_style.bold or series_style.dim or series_style.italic or
                series_style.underline or series_style.blink or series_style.reverse or
                series_style.strikethrough or series_style.fg != null or series_style.bg != null;
            const effective_box_style = if (use_focused) self.focused_style else if (series_has_style) series_style else self.box_style;
            const effective_whisker_style = if (use_focused) self.focused_style else self.whisker_style;
            const effective_median_style = if (use_focused) self.focused_style else self.median_style;
            const effective_outlier_style = if (use_focused) self.focused_style else self.outlier_style;

            // Compute row positions
            const row_q3 = valueToRow.calc(summary.q3, global_min, global_max, plot_height, inner.y);
            const row_q1 = valueToRow.calc(summary.q1, global_min, global_max, plot_height, inner.y);
            const row_median = valueToRow.calc(summary.median, global_min, global_max, plot_height, inner.y);
            const row_whisker_high = valueToRow.calc(summary.whisker_high, global_min, global_max, plot_height, inner.y);
            const row_whisker_low = valueToRow.calc(summary.whisker_low, global_min, global_max, plot_height, inner.y);

            // Render whisker line (upper)
            if (row_whisker_high < row_q3) {
                var row = row_whisker_high;
                while (row <= row_q3) : (row += 1) {
                    buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row)), Cell.init('│', effective_whisker_style));
                }
            }

            // Render whisker cap (upper)
            if (row_whisker_high < inner.y + plot_height) {
                buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row_whisker_high)), Cell.init('─', effective_whisker_style));
            }

            // Render whisker line (lower)
            if (row_q1 < row_whisker_low) {
                var row = row_q1;
                while (row <= row_whisker_low) : (row += 1) {
                    buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row)), Cell.init('│', effective_whisker_style));
                }
            }

            // Render whisker cap (lower)
            if (row_whisker_low < inner.y + plot_height) {
                buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row_whisker_low)), Cell.init('─', effective_whisker_style));
            }

            // Render box (from the smaller row/higher value row_q3 down to the
            // larger row/lower value row_q1 — row numbers increase downward while
            // values decrease downward, so row_q3 <= row_q1 in the normal case).
            const box_top = @min(row_q1, row_q3);
            const box_bottom = @max(row_q1, row_q3);
            {
                var row = box_top;
                while (row <= box_bottom) : (row += 1) {
                    buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row)), Cell.init('█', effective_box_style));
                }
            }

            // Render median line
            if (row_median < inner.y + plot_height) {
                buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row_median)), Cell.init('━', effective_median_style));
            }

            // Render outliers if enabled
            if (self.show_outliers) {
                const iqr = summary.q3 - summary.q1;
                const whisker_low_fence = summary.q1 - 1.5 * iqr;
                const whisker_high_fence = summary.q3 + 1.5 * iqr;

                const sample_count = @min(series_vals.len, MAX_SAMPLES);
                for (series_vals[0..sample_count]) |val| {
                    if (val < whisker_low_fence or val > whisker_high_fence) {
                        const row = valueToRow.calc(val, global_min, global_max, plot_height, inner.y);
                        if (row < inner.y + plot_height) {
                            buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(row)), Cell.init('·', effective_outlier_style));
                        }
                    }
                }
            }
        }

        // ========== Step 5: Render labels if enabled ==========
        if (self.show_labels and inner.height > 1) {
            const label_row = inner.y + plot_height;
            for (0..n) |i| {
                const series_vals = self.series[i].values;
                if (series_vals.len == 0) continue;

                const band_start = inner.x + i * band_width;
                const band_center = band_start + band_width / 2;

                const series = self.series[i];
                if (series.label.len > 0) {
                    // Render first character of label at center of band
                    const char = series.label[0];
                    buf.set(@as(u16, @intCast(band_center)), @as(u16, @intCast(label_row)), Cell.init(char, self.label_style));
                }
            }
        }
    }
};

// ============================================================================
// In-file library tests (minimal — main test suite in tests/box_plot_test.zig)
// ============================================================================

test "BoxPlot.init creates default plot" {
    const bp = BoxPlot.init();
    try std.testing.expectEqual(@as(usize, 0), bp.series.len);
    try std.testing.expectEqual(true, bp.show_labels);
    try std.testing.expectEqual(true, bp.show_outliers);
}

test "BoxPlot.seriesCount caps at MAX_SERIES" {
    var values_array: [10][1]f32 = undefined;
    var series_arr: [10]BoxPlotSeries = undefined;
    for (0..10) |i| {
        values_array[i] = [_]f32{@as(f32, @floatFromInt(i))};
        series_arr[i] = .{ .values = &values_array[i] };
    }
    const bp = BoxPlot.init().withSeries(&series_arr);
    try std.testing.expectEqual(@as(usize, 8), bp.seriesCount());
}

test "fiveNumberSummary computes correct quartiles for [1,2,3,4,5]" {
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const fns = fiveNumberSummary(&values);
    try std.testing.expectEqual(@as(f32, 1.0), fns.min);
    try std.testing.expectEqual(@as(f32, 5.0), fns.max);
    try std.testing.expectEqual(@as(f32, 3.0), fns.median);
    try std.testing.expectEqual(@as(f32, 2.0), fns.q1);
    try std.testing.expectEqual(@as(f32, 4.0), fns.q3);
}

test "fiveNumberSummary handles empty array" {
    var values: [0]f32 = undefined;
    const fns = fiveNumberSummary(&values);
    try std.testing.expectEqual(@as(f32, 0.0), fns.min);
    try std.testing.expectEqual(@as(f32, 0.0), fns.max);
}

test "fiveNumberSummary detects outliers correctly" {
    var values = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 100.0 };
    const fns = fiveNumberSummary(&values);
    try std.testing.expectEqual(@as(f32, 5.0), fns.whisker_high);
}

test "BoxPlot.render single series with one value produces no crash" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .label = "A", .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    bp.render(&buf, area);
}

test "BoxPlot.render on zero-area exits early" {
    var buf = try Buffer.init(std.testing.allocator, 0, 0);
    defer buf.deinit();
    var values = [_]f32{5.0};
    var series_arr = [_]BoxPlotSeries{.{ .values = &values }};
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    bp.render(&buf, area);
}

test "BoxPlot builder methods maintain immutability" {
    var values1 = [_]f32{1.0};
    var series1 = [_]BoxPlotSeries{.{ .values = &values1 }};
    var values2 = [_]f32{2.0};
    var series2 = [_]BoxPlotSeries{.{ .values = &values2 }};

    const bp1 = BoxPlot.init().withSeries(&series1);
    const bp2 = bp1.withSeries(&series2);

    try std.testing.expectEqual(@as(usize, 1), bp1.seriesCount());
    try std.testing.expectEqual(@as(usize, 1), bp2.seriesCount());
}

test "fiveNumberSummary respects MAX_SAMPLES truncation" {
    var values: [100]f32 = undefined;
    for (0..100) |i| {
        values[i] = @as(f32, @floatFromInt(i + 1));
    }
    const fns = fiveNumberSummary(&values);
    try std.testing.expectEqual(@as(f32, 1.0), fns.min);
    try std.testing.expectEqual(@as(f32, 64.0), fns.max);
}

test "BoxPlot.render two series produces content" {
    var buf = try Buffer.init(std.testing.allocator, 60, 20);
    defer buf.deinit();
    var values1 = [_]f32{ 1.0, 2.0, 3.0 };
    var values2 = [_]f32{ 5.0, 6.0, 7.0 };
    var series_arr = [_]BoxPlotSeries{
        .{ .label = "A", .values = &values1 },
        .{ .label = "B", .values = &values2 },
    };
    const bp = BoxPlot.init().withSeries(&series_arr);
    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    bp.render(&buf, area);
}
