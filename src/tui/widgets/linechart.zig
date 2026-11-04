//! LineChart widget — line chart with axis labels and multiple series
//!
//! Example usage:
//!
//! ```zig
//! const series = [_]LineChart.Series{
//!     .{ .name = "CPU", .data = &[_]f64{ 10, 20, 15, 30, 25 } },
//!     .{ .name = "Memory", .data = &[_]f64{ 5, 15, 10, 25, 20 } },
//! };
//!
//! const chart = LineChart.init(&series)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Metrics"))
//!     .withXLabels(&[_][]const u8{ "00:00", "00:15", "00:30", "00:45", "01:00" })
//!     .withYAxisLabel("Usage %");
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
const line_iter_mod = @import("../line_iter.zig");
const Block = block_mod.Block;
const Cell = buffer_mod.Cell;
const markerChar = @import("scatterplot.zig").markerChar;
const assert = std.debug.assert;

/// LineChart widget - line chart with axes and multiple series
pub const LineChart = struct {
    pub const Series = struct {
        name: []const u8,
        data: []const f64,
        style: Style = .{},
        marker: []const u8 = "•", // Default marker for data points
    };

    series: []const Series,
    block: ?Block = null,
    x_labels: []const []const u8 = &.{},
    y_axis_label: []const u8 = "",
    x_axis_label: []const u8 = "",
    min_y: ?f64 = null,
    max_y: ?f64 = null,
    show_legend: bool = true,
    show_axes: bool = true,
    legend_style: Style = .{},
    axis_style: Style = .{ .fg = .{ .indexed = 8 } }, // Dim gray

    /// Create a line chart with series
    pub fn init(series: []const Series) LineChart {
        return .{ .series = series };
    }

    /// Set the block (border) for this line chart
    pub fn withBlock(self: LineChart, new_block: Block) LineChart {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set X-axis labels
    pub fn withXLabels(self: LineChart, labels: []const []const u8) LineChart {
        var result = self;
        result.x_labels = labels;
        return result;
    }

    /// Set Y-axis label
    pub fn withYAxisLabel(self: LineChart, label: []const u8) LineChart {
        var result = self;
        result.y_axis_label = label;
        return result;
    }

    /// Set X-axis label
    pub fn withXAxisLabel(self: LineChart, label: []const u8) LineChart {
        var result = self;
        result.x_axis_label = label;
        return result;
    }

    /// Set minimum Y value for scaling
    pub fn withMinY(self: LineChart, min: f64) LineChart {
        var result = self;
        result.min_y = min;
        return result;
    }

    /// Set maximum Y value for scaling
    pub fn withMaxY(self: LineChart, max: f64) LineChart {
        var result = self;
        result.max_y = max;
        return result;
    }

    /// Show or hide legend
    pub fn withShowLegend(self: LineChart, show: bool) LineChart {
        var result = self;
        result.show_legend = show;
        return result;
    }

    /// Show or hide axes
    pub fn withShowAxes(self: LineChart, show: bool) LineChart {
        var result = self;
        result.show_axes = show;
        return result;
    }

    /// Set legend style
    pub fn withLegendStyle(self: LineChart, new_style: Style) LineChart {
        var result = self;
        result.legend_style = new_style;
        return result;
    }

    /// Set axis style
    pub fn withAxisStyle(self: LineChart, new_style: Style) LineChart {
        var result = self;
        result.axis_style = new_style;
        return result;
    }

    const Range = struct { min: f64, max: f64 };

    /// Calculate min and max Y values across all series, ignoring NaN and infinite samples.
    fn calcYRange(series: []const Series) Range {
        var min_val: f64 = std.math.floatMax(f64);
        var max_val: f64 = -std.math.floatMax(f64);

        for (series) |s| {
            for (s.data) |val| {
                if (!std.math.isFinite(val)) continue;
                if (val < min_val) min_val = val;
                if (val > max_val) max_val = val;
            }
        }

        if (min_val > max_val) return .{ .min = 0, .max = 0 };
        return .{ .min = min_val, .max = max_val };
    }

    /// Get max data length across all series
    fn maxDataLen(series: []const Series) usize {
        var max_len: usize = 0;
        for (series) |s| {
            if (s.data.len > max_len) max_len = s.data.len;
        }
        return max_len;
    }

    /// Scale Y value to pixel row. Non-finite values map to the middle row.
    fn scaleY(value: f64, min: f64, max: f64, height: usize) usize {
        if (height == 0) return 0;
        if (max == min or !std.math.isFinite(value)) return height / 2;
        const range = max - min;
        const normalized = (value - min) / range;
        const scaled = normalized * @as(f64, @floatFromInt(height - 1));
        if (!std.math.isFinite(scaled)) return height / 2;
        const clamped = std.math.clamp(scaled, 0, @as(f64, @floatFromInt(height - 1)));
        const row = @as(usize, @intFromFloat(clamped));
        // Invert because Y=0 is top of screen
        return height - 1 - @min(row, height - 1);
    }

    /// Column of sample `index` out of `count` samples spread over `width` columns; the first
    /// sample sits on column 0 and the last on column `width - 1`.
    fn scaleX(index: usize, count: usize, width: usize) usize {
        assert(width > 0);
        assert(index < count);
        if (count == 1) return @divFloor(width, 2);
        const column = @divFloor(index * (width - 1), count - 1);
        assert(column < width);
        return column;
    }

    /// Render Y-axis with labels; `area` is exactly `y_axis_width` columns wide.
    fn renderYAxis(self: LineChart, buf: *Buffer, area: Rect, min: f64, max: f64) void {
        assert(area.width == y_axis_width);
        assert(std.math.isFinite(min));
        assert(std.math.isFinite(max));
        if (area.height < 3) return;

        const axis_cell = Cell.init('│', self.axis_style);
        var dy: u16 = 0;
        while (dy < area.height) : (dy += 1) {
            buf.set(area.x + y_label_width, area.y + dy, axis_cell);
        }

        // Value labels: top (max), middle, bottom (min).
        var label_buf: [16]u8 = undefined;
        const mid_dy: u16 = area.height / 2;
        const has_mid = area.height > 4;
        buf.setString(area.x, area.y, axisLabel(&label_buf, max), self.axis_style);
        if (has_mid) {
            const mid = min / 2 + max / 2;
            buf.setString(area.x, area.y + mid_dy, axisLabel(&label_buf, mid), self.axis_style);
        }
        const bottom = axisLabel(&label_buf, min);
        buf.setString(area.x, area.y + area.height - 1, bottom, self.axis_style);

        // Vertical title in column 0, skipping rows that hold a value label.
        self.renderYTitle(buf, area, if (has_mid) mid_dy else null);
    }

    /// Draw `y_axis_label` top to bottom in column `area.x`, centered, one code point per row.
    fn renderYTitle(self: LineChart, buf: *Buffer, area: Rect, mid_row: ?u16) void {
        assert(area.height >= 3);
        const rows_count: usize = area.height;
        if (self.y_axis_label.len == 0) return;
        const view = std.unicode.Utf8View.init(self.y_axis_label) catch return;
        const count = std.unicode.utf8CountCodepoints(self.y_axis_label) catch return;
        if (count >= rows_count) return;
        var row: usize = @divFloor(rows_count - count, 2);
        var it = view.iterator();
        while (it.nextCodepoint()) |cp| : (row += 1) {
            assert(row < rows_count);
            const is_mid = if (mid_row) |mid| row == mid else false;
            if (row == 0 or row == rows_count - 1 or is_mid) continue;
            const y = area.y + @as(u16, @intCast(row));
            buf.set(area.x, y, Cell.init(cp, self.axis_style));
        }
    }

    /// Format an axis value into at most `y_label_width` right-aligned cells; "#####" if it
    /// cannot fit.
    fn axisLabel(out: *[16]u8, value: f64) []const u8 {
        assert(std.math.isFinite(value));
        assert(out.len >= y_label_width);
        const overflow = "#####";
        const text = std.fmt.bufPrint(out, "{d:5.1}", .{value}) catch return overflow;
        if (text.len <= y_label_width) return text;
        const whole = std.fmt.bufPrint(out, "{d:5.0}", .{value}) catch return overflow;
        if (whole.len <= y_label_width) return whole;
        return overflow;
    }

    /// Render X-axis with labels
    fn renderXAxis(self: LineChart, buf: *Buffer, area: Rect, data_len: usize) void {
        assert(area.height == x_axis_height);
        assert(area.width > 0);

        const axis_cell = Cell.init('─', self.axis_style);
        var dx: u16 = 0;
        while (dx < area.width) : (dx += 1) {
            buf.set(area.x + dx, area.y, axis_cell);
        }

        // Sample labels, shifted left when they would overrun the right edge.
        const label_count = @min(self.x_labels.len, data_len);
        for (self.x_labels[0..label_count], 0..) |label, i| {
            const cells = cellCount(label);
            if (cells > area.width) continue;
            const x_pos = scaleX(i, data_len, area.width);
            const label_x = area.x + @as(u16, @intCast(@min(x_pos, area.width - cells)));
            buf.setString(label_x, area.y + 1, label, self.axis_style);
        }

        // Axis title centered on the last row.
        const title_cells = cellCount(self.x_axis_label);
        if (title_cells == 0 or title_cells >= area.width) return;
        const title_x = area.x + @divFloor(area.width - title_cells, 2);
        buf.setString(title_x, area.y + 2, self.x_axis_label, self.axis_style);
    }

    /// Render legend: for each series its marker, then its name, clipped to `area`.
    fn renderLegend(self: LineChart, buf: *Buffer, area: Rect) void {
        assert(area.height == 1);
        assert(area.width > 0);

        var x: u32 = area.x;
        const x_end: u32 = @as(u32, area.x) + area.width;
        for (self.series) |s| {
            if (x >= x_end) break;
            buf.set(@intCast(x), area.y, Cell.init(markerChar(s.marker), s.style));
            x += 1;
            if (x >= x_end) break;

            const room: usize = x_end - x;
            const name = truncateCells(s.name, room);
            buf.setString(@intCast(x), area.y, name, self.legend_style);
            x += @as(u32, @intCast(cellCount(name))) + legend_gap;
        }
    }

    /// Render a single data series: line segments first, then markers on top of them.
    fn renderSeries(buf: *Buffer, area: Rect, series: Series, min: f64, max: f64) void {
        assert(area.width > 0);
        assert(area.height > 0);
        if (series.data.len == 0) return;

        const count = series.data.len;
        const width: usize = area.width;
        const height: usize = area.height;
        var i: usize = 1;
        while (i < count) : (i += 1) {
            const x0: i32 = @intCast(scaleX(i - 1, count, width));
            const y0: i32 = @intCast(scaleY(series.data[i - 1], min, max, height));
            const x1: i32 = @intCast(scaleX(i, count, width));
            const y1: i32 = @intCast(scaleY(series.data[i], min, max, height));
            drawLine(buf, area, .{ x0, y0 }, .{ x1, y1 }, series.style);
        }

        const marker = Cell.init(markerChar(series.marker), series.style);
        for (series.data, 0..) |value, index| {
            const px: u16 = @intCast(scaleX(index, count, width));
            const py: u16 = @intCast(scaleY(value, min, max, height));
            buf.set(area.x + px, area.y + py, marker);
        }
    }

    /// Draw a line between two plot-relative points using Bresenham's algorithm.
    fn drawLine(buf: *Buffer, area: Rect, from: [2]i32, to: [2]i32, line_style: Style) void {
        assert(from[0] >= 0);
        assert(from[1] >= 0);
        assert(to[0] < area.width);
        assert(to[1] < area.height);
        var line = line_iter_mod.LineIter.init(from[0], from[1], to[0], to[1]);
        const cell = Cell.init('·', line_style);
        while (line.next()) |point| {
            assert(point.x >= 0);
            assert(point.y >= 0);
            const px: u16 = @intCast(point.x);
            const py: u16 = @intCast(point.y);
            buf.set(area.x + px, area.y + py, cell);
        }
    }

    /// Y range honoring finite `min_y`/`max_y` overrides; non-finite overrides are ignored.
    fn resolveRange(self: LineChart) Range {
        const auto = calcYRange(self.series);
        const min = if (self.min_y) |v| (if (std.math.isFinite(v)) v else auto.min) else auto.min;
        const max = if (self.max_y) |v| (if (std.math.isFinite(v)) v else auto.max) else auto.max;
        return .{ .min = min, .max = max };
    }

    /// Render axes and series into `chart_area` (below the legend).
    fn renderChart(self: LineChart, buf: *Buffer, chart_area: Rect) void {
        assert(chart_area.height >= 3);
        assert(chart_area.width >= 10);
        const range = self.resolveRange();

        var plot_area = chart_area;
        if (self.show_axes) {
            renderYAxis(self, buf, .{
                .x = chart_area.x,
                .y = chart_area.y,
                .width = y_axis_width,
                .height = chart_area.height -| x_axis_height,
            }, range.min, range.max);
            plot_area.x += y_axis_width;
            plot_area.width -= y_axis_width;
        }

        if (self.show_axes and plot_area.height > x_axis_height) {
            renderXAxis(self, buf, .{
                .x = plot_area.x,
                .y = plot_area.y + plot_area.height - x_axis_height,
                .width = plot_area.width,
                .height = x_axis_height,
            }, maxDataLen(self.series));
            plot_area.height -= x_axis_height;
        }

        if (plot_area.width == 0 or plot_area.height == 0) return;
        for (self.series) |series| {
            renderSeries(buf, plot_area, series, range.min, range.max);
        }
    }

    /// Render the line chart widget
    pub fn render(self: LineChart, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0 or self.series.len == 0) return;

        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        // Clip to the buffer so coordinate arithmetic below cannot overflow u16.
        inner_area = inner_area.intersection(Rect.fromSize(buf.width, buf.height)) orelse return;
        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Reserve space for legend at top
        var chart_area = inner_area;
        if (self.show_legend and inner_area.height > 1) {
            renderLegend(self, buf, .{
                .x = inner_area.x,
                .y = inner_area.y,
                .width = inner_area.width,
                .height = 1,
            });
            chart_area.y += 1;
            chart_area.height -= 1;
        }

        if (chart_area.height < 3 or chart_area.width < 10) return;
        self.renderChart(buf, chart_area);
    }
};

const y_label_width: u16 = 5; // value labels like " 99.9"
const y_axis_width: u16 = y_label_width + 1; // labels plus the axis line
const x_axis_height: u16 = 3; // axis line, tick labels, axis title
const legend_gap: u32 = 2; // blank cells between legend entries

/// Number of code points in `text` (its length in bytes if it is not valid UTF-8).
fn cellCount(text: []const u8) u16 {
    const count = std.unicode.utf8CountCodepoints(text) catch text.len;
    return @intCast(@min(count, std.math.maxInt(u16)));
}

/// Longest prefix of `text` holding at most `cells_max` code points, cut on a boundary.
fn truncateCells(text: []const u8, cells_max: usize) []const u8 {
    assert(cells_max <= std.math.maxInt(u32));
    var end: usize = 0;
    var cells: usize = 0;
    while (end < text.len and cells < cells_max) : (cells += 1) {
        const step = std.unicode.utf8ByteSequenceLength(text[end]) catch 1;
        end = @min(end + step, text.len);
    }
    assert(end <= text.len);
    return text[0..end];
}
// Tests
const testing = std.testing;

test "LineChart.init" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series);
    try testing.expectEqual(1, chart.series.len);
    try testing.expect(chart.show_legend);
    try testing.expect(chart.show_axes);
}

test "LineChart.withBlock" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const block = (Block{}).withTitle("Chart", .top_left);
    const chart = LineChart.init(&series).withBlock(block);
    try testing.expect(chart.block != null);
}

test "LineChart.withXLabels" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const labels = [_][]const u8{ "A", "B" };
    const chart = LineChart.init(&series).withXLabels(&labels);
    try testing.expectEqual(2, chart.x_labels.len);
}

test "LineChart.withYAxisLabel" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withYAxisLabel("Value");
    try testing.expectEqualStrings("Value", chart.y_axis_label);
}

test "LineChart.withXAxisLabel" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withXAxisLabel("Time");
    try testing.expectEqualStrings("Time", chart.x_axis_label);
}

test "LineChart.withMinY" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withMinY(0.0);
    try testing.expectEqual(0.0, chart.min_y.?);
}

test "LineChart.withMaxY" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withMaxY(100.0);
    try testing.expectEqual(100.0, chart.max_y.?);
}

test "LineChart.withShowLegend" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withShowLegend(false);
    try testing.expect(!chart.show_legend);
}

test "LineChart.withShowAxes" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const chart = LineChart.init(&series).withShowAxes(false);
    try testing.expect(!chart.show_axes);
}

test "LineChart.withLegendStyle" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const style = Style{ .bold = true };
    const chart = LineChart.init(&series).withLegendStyle(style);
    try testing.expect(chart.legend_style.bold);
}

test "LineChart.withAxisStyle" {
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &[_]f64{1.0} },
    };
    const style = Style{ .fg = .{ .indexed = 5 } };
    const chart = LineChart.init(&series).withAxisStyle(style);
    try testing.expectEqual(Color{ .indexed = 5 }, chart.axis_style.fg.?);
}

test "LineChart.calcYRange empty" {
    const series = [_]LineChart.Series{};
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(0.0, range.min);
    try testing.expectEqual(0.0, range.max);
}

test "LineChart.calcYRange single value" {
    const data = [_]f64{42.0};
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(42.0, range.min);
    try testing.expectEqual(42.0, range.max);
}

test "LineChart.calcYRange multiple values" {
    const data = [_]f64{ 10.0, 20.0, 5.0, 30.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(5.0, range.min);
    try testing.expectEqual(30.0, range.max);
}

test "LineChart.calcYRange multiple series" {
    const data1 = [_]f64{ 10.0, 20.0 };
    const data2 = [_]f64{ 5.0, 30.0 };
    const series = [_]LineChart.Series{
        .{ .name = "A", .data = &data1 },
        .{ .name = "B", .data = &data2 },
    };
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(5.0, range.min);
    try testing.expectEqual(30.0, range.max);
}

test "LineChart.maxDataLen empty" {
    const series = [_]LineChart.Series{};
    try testing.expectEqual(0, LineChart.maxDataLen(&series));
}

test "LineChart.maxDataLen single series" {
    const data = [_]f64{ 1.0, 2.0, 3.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    try testing.expectEqual(3, LineChart.maxDataLen(&series));
}

test "LineChart.maxDataLen multiple series" {
    const data1 = [_]f64{ 1.0, 2.0 };
    const data2 = [_]f64{ 1.0, 2.0, 3.0, 4.0 };
    const series = [_]LineChart.Series{
        .{ .name = "A", .data = &data1 },
        .{ .name = "B", .data = &data2 },
    };
    try testing.expectEqual(4, LineChart.maxDataLen(&series));
}

test "LineChart.scaleY basic" {
    const height: usize = 10;
    try testing.expectEqual(0, LineChart.scaleY(100.0, 0.0, 100.0, height)); // max -> top
    try testing.expectEqual(9, LineChart.scaleY(0.0, 0.0, 100.0, height)); // min -> bottom
    try testing.expectEqual(5, LineChart.scaleY(50.0, 0.0, 100.0, height)); // mid -> middle
}

test "LineChart.scaleY same min and max" {
    const height: usize = 10;
    try testing.expectEqual(5, LineChart.scaleY(42.0, 42.0, 42.0, height));
}
test "LineChart.calcYRange ignores NaN and infinite samples" {
    const data = [_]f64{ std.math.nan(f64), 4.0, std.math.inf(f64), -std.math.inf(f64), 8.0 };
    const series = [_]LineChart.Series{.{ .name = "N", .data = &data }};
    const range = LineChart.calcYRange(&series);
    try testing.expectEqual(4.0, range.min);
    try testing.expectEqual(8.0, range.max);

    const only_bad = [_]f64{std.math.nan(f64)};
    const bad_series = [_]LineChart.Series{.{ .name = "N", .data = &only_bad }};
    try testing.expectEqual(0.0, LineChart.calcYRange(&bad_series).max);
}

test "LineChart.scaleX puts first sample on column 0 and last on the last column" {
    try testing.expectEqual(0, LineChart.scaleX(0, 5, 24));
    try testing.expectEqual(23, LineChart.scaleX(4, 5, 24));
    try testing.expectEqual(11, LineChart.scaleX(2, 5, 24));
    try testing.expectEqual(7, LineChart.scaleX(0, 1, 14));
    try testing.expectEqual(0, LineChart.scaleX(1, 2, 1));
}

/// Assert that the cells of row `y` starting at `x` hold exactly the codepoints of `text`.
fn expectRow(buf: Buffer, x: u16, y: u16, text: []const u8) !void {
    var iter = std.unicode.Utf8View.initUnchecked(text).iterator();
    var i: u16 = 0;
    while (iter.nextCodepoint()) |cp| : (i += 1) {
        try testing.expectEqual(cp, buf.getChar(x + i, y));
    }
}

/// Assert that every cell of the buffer is the default blank cell.
fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

/// Count the cells of the buffer that hold `char`.
fn countChar(buf: Buffer, char: u21) usize {
    var count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == char) count += 1;
    }
    return count;
}

test "LineChart.render empty area and empty series draw nothing" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    const data = [_]f64{1.0};
    const series = [_]LineChart.Series{.{ .name = "Test", .data = &data }};
    LineChart.init(&series).render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try expectBlank(buf);

    const none = [_]LineChart.Series{};
    LineChart.init(&none).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    try expectBlank(buf);
}

test "LineChart.render lays out legend, axes, labels and series cells" {
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const data = [_]f64{ 0.0, 10.0 };
    const series = [_]LineChart.Series{
        .{ .name = "S", .data = &data, .style = .{ .fg = .{ .indexed = 2 } } },
    };
    const labels = [_][]const u8{ "a", "b" };
    const chart = LineChart.init(&series)
        .withMinY(0.0).withMaxY(10.0).withXLabels(&labels)
        .withYAxisLabel("Val").withXAxisLabel("Time");
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 10 });

    // Legend on row 0: marker, then name.
    try expectRow(buf, 0, 0, "•S");
    try testing.expectEqual(@as(?Color, .{ .indexed = 2 }), buf.getStyle(0, 0).fg);
    // Y axis: line in column 5 rows 1..6, value labels, title skipping label rows.
    try testing.expectEqual(@as(u21, '│'), buf.getChar(5, 1));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(5, 6));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(5, 7));
    try expectRow(buf, 0, 1, " 10.0");
    try expectRow(buf, 0, 4, "  5.0");
    try expectRow(buf, 0, 6, "  0.0");
    try testing.expectEqual(@as(u21, 'V'), buf.getChar(0, 2));
    try testing.expectEqual(@as(u21, 'a'), buf.getChar(0, 3));
    // 'l' would land on the middle value label's row, so it is skipped.
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 5));
    try testing.expectEqual(@as(usize, 0), countChar(buf, 'l'));
    // X axis: line on row 7 from column 6, labels on row 8, title on row 9.
    try testing.expectEqual(@as(u21, '─'), buf.getChar(6, 7));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(29, 7));
    try testing.expectEqual(@as(u21, 'a'), buf.getChar(6, 8));
    try testing.expectEqual(@as(u21, 'b'), buf.getChar(29, 8));
    try expectRow(buf, 16, 9, "Time");
    // Series: markers on both end points (the right-most column is drawn) and 22 line cells.
    try testing.expectEqual(@as(u21, '•'), buf.getChar(6, 6));
    try testing.expectEqual(@as(u21, '•'), buf.getChar(29, 1));
    try testing.expectEqual(@as(?Color, .{ .indexed = 2 }), buf.getStyle(29, 1).fg);
    try testing.expectEqual(@as(usize, 22), countChar(buf, '·'));
    try testing.expectEqual(@as(usize, 3), countChar(buf, '•')); // legend + 2 markers
}

test "LineChart.render keeps markers visible on top of connecting lines" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const data = [_]f64{ 0.0, 5.0, 10.0 };
    const series = [_]LineChart.Series{.{ .name = "M", .data = &data, .marker = "o" }};
    const chart = LineChart.init(&series).withShowLegend(false).withShowAxes(false);
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Plot is the whole 20x10 area: samples at columns 0, 9, 19.
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(0, 9));
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(9, 5));
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(19, 0));
    try testing.expectEqual(@as(usize, 3), countChar(buf, 'o'));
    try testing.expect(countChar(buf, '·') >= 17);
}

test "LineChart.render single point sits mid-plot" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const data = [_]f64{50.0};
    const series = [_]LineChart.Series{.{ .name = "Test", .data = &data }};
    LineChart.init(&series).render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Plot area x 6..19, y 1..6; the lone sample has no range so it lands mid-plot.
    try testing.expectEqual(@as(u21, '•'), buf.getChar(13, 4));
    try testing.expectEqual(@as(usize, 2), countChar(buf, '•')); // legend + sample
    try testing.expectEqual(@as(usize, 0), countChar(buf, '·'));
    try expectRow(buf, 0, 1, " 50.0");
}

test "LineChart.render draws inside a block" {
    var buf = try Buffer.init(testing.allocator, 30, 12);
    defer buf.deinit();

    const data = [_]f64{ 0.0, 10.0 };
    const series = [_]LineChart.Series{.{ .name = "B", .data = &data }};
    const block = (Block{}).withBorders(.all).withTitle("Chart", .top_left);
    const chart = LineChart.init(&series).withBlock(block).withShowAxes(false);
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 12 });

    try expectRow(buf, 2, 0, "Chart");
    try expectRow(buf, 1, 1, "•B"); // legend inside the border
    // Plot is the inner 28x9 area at (1, 2): first sample bottom-left, last top-right.
    try testing.expectEqual(@as(u21, '•'), buf.getChar(1, 10));
    try testing.expectEqual(@as(u21, '•'), buf.getChar(28, 2));
    try testing.expectEqual(@as(usize, 3), countChar(buf, '•'));
}

test "LineChart.render without legend or axes uses the whole area" {
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();

    const data = [_]f64{ 10.0, 20.0 };
    const series = [_]LineChart.Series{.{ .name = "Test", .data = &data }};
    const chart = LineChart.init(&series).withShowLegend(false).withShowAxes(false);
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });

    try testing.expectEqual(@as(u21, '•'), buf.getChar(0, 14));
    try testing.expectEqual(@as(u21, '•'), buf.getChar(29, 0));
    try testing.expectEqual(@as(usize, 0), countChar(buf, '│'));
    try testing.expectEqual(@as(usize, 0), countChar(buf, '─'));
    try testing.expectEqual(@as(usize, 2), countChar(buf, '•'));
}

test "LineChart.render with custom min/max scales against the override" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const data = [_]f64{ 10.0, 10.0 };
    const series = [_]LineChart.Series{.{ .name = "T", .data = &data }};
    const chart = LineChart.init(&series).withShowLegend(false).withShowAxes(false)
        .withMinY(0.0).withMaxY(90.0);
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // 10 of 0..90 over 10 rows is row index 1 from the bottom: y = 9 - 1 = 8.
    try testing.expectEqual(@as(u21, '•'), buf.getChar(0, 8));
    try testing.expectEqual(@as(u21, '•'), buf.getChar(19, 8));
    try testing.expectEqual(@as(usize, 18), countChar(buf, '·'));
}

test "LineChart.render small area only draws the legend" {
    var buf = try Buffer.init(testing.allocator, 5, 3);
    defer buf.deinit();

    const data = [_]f64{ 10.0, 20.0 };
    const series = [_]LineChart.Series{.{ .name = "Test", .data = &data }};
    LineChart.init(&series).render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 3 });

    try expectRow(buf, 0, 0, "•Test");
    try testing.expectEqual(@as(usize, 1), countChar(buf, '•'));
    try testing.expectEqual(@as(usize, 0), countChar(buf, '·'));
}

test "LineChart.render clips the legend to the area" {
    var buf = try Buffer.init(testing.allocator, 30, 4);
    defer buf.deinit();

    const data = [_]f64{ 1.0, 2.0 };
    const series = [_]LineChart.Series{
        .{ .name = "LongSeriesName", .data = &data, .marker = "◆x" },
        .{ .name = "Second", .data = &data },
    };
    LineChart.init(&series).render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });

    // Marker uses the first code point only; the name is cut at the area's right edge.
    try expectRow(buf, 0, 0, "◆LongSer");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(8, 0));
    try testing.expectEqual(@as(usize, 1), countChar(buf, 'S')); // "Second" is not drawn
    try testing.expectEqual(@as(usize, 0), countChar(buf, 'x'));
}

test "LineChart.render fits oversized value labels without eating the axis line" {
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const data = [_]f64{ 0.0, 12345.6 };
    const series = [_]LineChart.Series{.{ .name = "Big", .data = &data }};
    LineChart.init(&series).render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 10 });

    try expectRow(buf, 0, 1, "12346");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(5, 1));
    try expectRow(buf, 0, 4, " 6173");
    try expectRow(buf, 0, 6, "  0.0");

    const huge = [_]f64{ 0.0, 123456789.0 };
    const huge_series = [_]LineChart.Series{.{ .name = "Big", .data = &huge }};
    buf.clear();
    LineChart.init(&huge_series).render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 10 });
    try expectRow(buf, 0, 1, "#####");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(5, 1));
}

test "LineChart.render ignores an area outside the buffer without overflow" {
    var buf = try Buffer.init(testing.allocator, 12, 10);
    defer buf.deinit();

    const data = [_]f64{ 1.0, 2.0 };
    const series = [_]LineChart.Series{.{ .name = "Far", .data = &data }};
    const chart = LineChart.init(&series);

    chart.render(&buf, .{ .x = 65530, .y = 65530, .width = 100, .height = 100 });
    try expectBlank(buf);
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 65535, .height = 65535 });
    try testing.expectEqual(@as(u21, '│'), buf.getChar(5, 1));
    try expectRow(buf, 0, 0, "•Far");
}

test "LineChart.render survives labels and names longer than u16" {
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    const long = [_]u8{'x'} ** 70000;
    const data = [_]f64{ 1.0, 2.0 };
    const series = [_]LineChart.Series{.{ .name = &long, .data = &data }};
    const labels = [_][]const u8{ &long, "ok" };
    const chart = LineChart.init(&series).withXLabels(&labels)
        .withXAxisLabel(&long).withYAxisLabel(&long);
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 10 });

    try expectRow(buf, 0, 0, "•xxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(5, 3));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(6, 7));
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(28, 8)); // second label, shifted to fit
    try testing.expectEqual(@as(u21, ' '), buf.getChar(6, 8)); // first label too wide: dropped
    try testing.expectEqual(@as(u21, ' '), buf.getChar(6, 9));
}

test "LineChart.render treats infinite samples like NaN and keeps the range finite" {
    const inf = std.math.inf(f64);
    var buf_inf = try Buffer.init(testing.allocator, 30, 12);
    defer buf_inf.deinit();
    var buf_mid = try Buffer.init(testing.allocator, 30, 12);
    defer buf_mid.deinit();

    const data_inf = [_]f64{ 0.0, inf, 10.0 };
    const data_mid = [_]f64{ 0.0, 5.0, 10.0 };
    const series_inf = [_]LineChart.Series{.{ .name = "I", .data = &data_inf }};
    const series_mid = [_]LineChart.Series{.{ .name = "I", .data = &data_mid }};
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 12 };
    LineChart.init(&series_inf).render(&buf_inf, area);
    LineChart.init(&series_mid).render(&buf_mid, area);

    try expectRow(buf_inf, 0, 1, " 10.0");
    try testing.expectEqualSlices(buffer_mod.Cell, buf_mid.cells, buf_inf.cells);
}

test "LineChart.render ignores non-finite min_y/max_y overrides" {
    var buf_bad = try Buffer.init(testing.allocator, 30, 12);
    defer buf_bad.deinit();
    var buf_auto = try Buffer.init(testing.allocator, 30, 12);
    defer buf_auto.deinit();

    const data = [_]f64{ 10.0, 20.0 };
    const series = [_]LineChart.Series{.{ .name = "I", .data = &data }};
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 12 };
    const bad = LineChart.init(&series).withMinY(-std.math.inf(f64)).withMaxY(std.math.inf(f64));
    bad.render(&buf_bad, area);
    LineChart.init(&series).render(&buf_auto, area);

    try testing.expectEqualSlices(buffer_mod.Cell, buf_auto.cells, buf_bad.cells);
}

test "LineChart.render with NaN data point falls back to safe value" {

    // Render with NaN in data
    var buf_nan = try Buffer.init(testing.allocator, 50, 20);
    defer buf_nan.deinit();

    const data_nan = [_]f64{ 10.0, std.math.nan(f64), 20.0 };
    const series_nan = [_]LineChart.Series{
        .{ .name = "Test", .data = &data_nan, .style = .{ .fg = .{ .indexed = 2 } } },
    };
    const chart_nan = LineChart.init(&series_nan);
    chart_nan.render(&buf_nan, .{ .x = 0, .y = 0, .width = 50, .height = 20 });

    // Render with midpoint fallback (which is what NaN should become)
    // scaleY(NaN, ..., height) returns height/2, which matches the data value 15.0.
    var buf_mid = try Buffer.init(testing.allocator, 50, 20);
    defer buf_mid.deinit();

    const data_mid = [_]f64{ 10.0, 15.0, 20.0 };
    const series_mid = [_]LineChart.Series{
        .{ .name = "Test", .data = &data_mid, .style = .{ .fg = .{ .indexed = 2 } } },
    };
    const chart_mid = LineChart.init(&series_mid);
    chart_mid.render(&buf_mid, .{ .x = 0, .y = 0, .width = 50, .height = 20 });

    // The NaN data point must render identically to the midpoint value.
    // Assert that the entire buffer renders identically.
    try testing.expectEqualSlices(buffer_mod.Cell, buf_nan.cells, buf_mid.cells);
}

test "LineChart.render with NaN min_y uses calculated value" {

    // Render with NaN min_y (should fall back to calculated min)
    var buf_nan_min = try Buffer.init(testing.allocator, 50, 20);
    defer buf_nan_min.deinit();

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart_nan_min = LineChart.init(&series).withMinY(std.math.nan(f64));
    chart_nan_min.render(&buf_nan_min, .{ .x = 0, .y = 0, .width = 50, .height = 20 });

    // Render without override (uses calculated range)
    var buf_normal = try Buffer.init(testing.allocator, 50, 20);
    defer buf_normal.deinit();
    const chart_normal = LineChart.init(&series);
    chart_normal.render(&buf_normal, .{ .x = 0, .y = 0, .width = 50, .height = 20 });

    // After fix, NaN min_y should be completely ignored and fall back to calculated min.
    // The buffer with NaN min_y should render identically to buffer without override.
    try testing.expectEqualSlices(buffer_mod.Cell, buf_nan_min.cells, buf_normal.cells);
}

test "LineChart.render with NaN max_y uses calculated value" {

    // Render with NaN max_y (should fall back to calculated max)
    var buf_nan_max = try Buffer.init(testing.allocator, 50, 20);
    defer buf_nan_max.deinit();

    const data = [_]f64{ 10.0, 20.0, 15.0 };
    const series = [_]LineChart.Series{
        .{ .name = "Test", .data = &data },
    };
    const chart_nan_max = LineChart.init(&series).withMaxY(std.math.nan(f64));
    chart_nan_max.render(&buf_nan_max, .{ .x = 0, .y = 0, .width = 50, .height = 20 });

    // Render without override (uses calculated range)
    var buf_normal = try Buffer.init(testing.allocator, 50, 20);
    defer buf_normal.deinit();
    const chart_normal = LineChart.init(&series);
    chart_normal.render(&buf_normal, .{ .x = 0, .y = 0, .width = 50, .height = 20 });

    // After fix, NaN max_y should be completely ignored and fall back to calculated max.
    // The buffer with NaN max_y should render identically to buffer without override.
    try testing.expectEqualSlices(buffer_mod.Cell, buf_nan_max.cells, buf_normal.cells);
}
