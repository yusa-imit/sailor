//! MosaicPlot Widget — Marimekko-style variable-width-column + stacked-segment-height proportional chart
//!
//! The MosaicPlot widget displays data as a mosaic of rectangular segments, where each column's
//! width is proportional to the column's total value, and each segment's height within the column
//! is proportional to that segment's value. This creates a visual representation commonly used
//! in Marimekko-style charts for showing hierarchical proportions.
//!
//! ## Features
//! - Up to 16 columns (MAX_COLUMNS)
//! - Up to 8 segments per column (MAX_SEGMENTS_PER_COLUMN)
//! - Column widths proportional to column totals (cumulative-floor formula, no gaps/overlaps)
//! - Segment heights proportional within each column (cumulative-floor formula)
//! - Optional column header row with labels (show_column_labels)
//! - Optional segment labels (first character rendered in top-left, show_segment_labels)
//! - Focused column/segment highlighting with precedence-based styling
//! - Block border support
//! - No heap allocations
//! - Robust zero/negative-value handling (clamping, no panic)
//!
//! ## Usage
//! ```zig
//! var col1 = [_]MosaicSegment{
//!     .{ .label = "A", .value = 30, .style = .{ .bold = true } },
//!     .{ .label = "B", .value = 20 },
//! };
//! var col2 = [_]MosaicSegment{
//!     .{ .label = "X", .value = 40 },
//!     .{ .label = "Y", .value = 10 },
//! };
//!
//! var cols = [_]MosaicColumn{
//!     .{ .label = "Column1", .segments = &col1 },
//!     .{ .label = "Column2", .segments = &col2 },
//! };
//!
//! const plot = MosaicPlot.init()
//!     .withColumns(&cols)
//!     .withShowColumnLabels(true)
//!     .withShowSegmentLabels(true)
//!     .withFocusedColumn(0)
//!     .withFocusedSegment(0)
//!     .withFocusedStyle(.{ .reverse = true })
//!     .withBlock(.{});
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

/// Single segment within a column
pub const MosaicSegment = struct {
    /// Label for this segment (e.g., category name)
    label: []const u8 = "",
    /// Numeric value (negative values clamp to 0)
    value: f32 = 0,
    /// Per-segment style override
    style: Style = .{},
};

/// Single column in a mosaic plot
pub const MosaicColumn = struct {
    /// Label for this column (rendered in header row if show_column_labels)
    label: []const u8 = "",
    /// Array of segments within this column
    segments: []const MosaicSegment = &.{},
    /// Per-column style (not directly used in render, but available for app logic)
    style: Style = .{},
};

/// MosaicPlot widget for proportional mosaic visualization
pub const MosaicPlot = struct {
    /// Maximum number of columns (capped at 16 for rendering)
    pub const MAX_COLUMNS: usize = 16;
    /// Maximum number of segments per column
    pub const MAX_SEGMENTS_PER_COLUMN: usize = 8;

    /// Array of columns to display
    columns: []const MosaicColumn = &.{},
    /// Index of the focused column for highlighting
    focused_column: usize = 0,
    /// Index of the focused segment within focused column
    focused_segment: usize = 0,
    /// Whether to render column header row with column labels
    show_column_labels: bool = true,
    /// Whether to render segment labels (first char in top-left of segment)
    show_segment_labels: bool = false,
    /// Base style applied to all elements
    style: Style = .{},
    /// Style for column/segment labels
    label_style: Style = .{},
    /// Style for focused segment (overrides segment.style when set)
    focused_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a MosaicPlot with all defaults
    pub fn init() MosaicPlot {
        return .{};
    }

    /// Count of columns to render (capped at MAX_COLUMNS)
    pub fn columnCount(self: MosaicPlot) usize {
        return @min(self.columns.len, MAX_COLUMNS);
    }

    /// Count of segments to render in a specific column (capped at MAX_SEGMENTS_PER_COLUMN)
    pub fn segmentCount(self: MosaicPlot, col_idx: usize) usize {
        if (col_idx >= self.columns.len) return 0;
        return @min(self.columns[col_idx].segments.len, MAX_SEGMENTS_PER_COLUMN);
    }

    /// Total value of a column (sum of segment values, clamped negatives to 0)
    pub fn columnTotal(self: MosaicPlot, col_idx: usize) f32 {
        if (col_idx >= self.columns.len) return 0;
        const col = self.columns[col_idx];
        const seg_count = self.segmentCount(col_idx);
        var total: f32 = 0;
        for (0..seg_count) |i| {
            const val = col.segments[i].value;
            total += @max(val, 0); // clamp negative to 0
        }
        return total;
    }

    /// Grand total value across all columns (sum of all columnTotals, capped at MAX_COLUMNS)
    pub fn grandTotal(self: MosaicPlot) f32 {
        const col_count = self.columnCount();
        var total: f32 = 0;
        for (0..col_count) |i| {
            total += self.columnTotal(i);
        }
        return total;
    }

    /// Set columns array (builder pattern)
    pub fn withColumns(self: MosaicPlot, cols: []const MosaicColumn) MosaicPlot {
        var result = self;
        result.columns = cols;
        return result;
    }

    /// Set focused column index (builder pattern)
    pub fn withFocusedColumn(self: MosaicPlot, idx: usize) MosaicPlot {
        var result = self;
        result.focused_column = idx;
        return result;
    }

    /// Set focused segment index (builder pattern)
    pub fn withFocusedSegment(self: MosaicPlot, idx: usize) MosaicPlot {
        var result = self;
        result.focused_segment = idx;
        return result;
    }

    /// Set show_column_labels flag (builder pattern)
    pub fn withShowColumnLabels(self: MosaicPlot, show: bool) MosaicPlot {
        var result = self;
        result.show_column_labels = show;
        return result;
    }

    /// Set show_segment_labels flag (builder pattern)
    pub fn withShowSegmentLabels(self: MosaicPlot, show: bool) MosaicPlot {
        var result = self;
        result.show_segment_labels = show;
        return result;
    }

    /// Set base style (builder pattern)
    pub fn withStyle(self: MosaicPlot, s: Style) MosaicPlot {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set label_style (builder pattern)
    pub fn withLabelStyle(self: MosaicPlot, s: Style) MosaicPlot {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set focused_style (builder pattern)
    pub fn withFocusedStyle(self: MosaicPlot, s: Style) MosaicPlot {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set block border (builder pattern)
    pub fn withBlock(self: MosaicPlot, b: ?Block) MosaicPlot {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the mosaic plot to the buffer
    pub fn render(self: MosaicPlot, buf: *Buffer, area: Rect) void {
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

        const n_columns = self.columnCount();

        // Reserve row for column labels if enabled
        var plot_area = inner;
        var label_row_idx: ?u16 = null;
        if (self.show_column_labels and plot_area.height > 0) {
            label_row_idx = plot_area.y;
            plot_area.y += 1;
            if (plot_area.height > 0) plot_area.height -= 1;
        }

        if (plot_area.width == 0 or plot_area.height == 0) {
            // No space for plot content, but border was already drawn
            return;
        }

        // Calculate grand total
        const grand_total = self.grandTotal();

        // If grand total is 0, no plot content to draw (but border was already rendered)
        if (grand_total == 0) {
            return;
        }

        // Render column labels if enabled
        if (self.show_column_labels and label_row_idx != null) {
            renderColumnLabels(buf, inner, label_row_idx.?, n_columns, self);
        }

        // Render columns and segments
        for (0..n_columns) |col_idx| {
            const col = self.columns[col_idx];
            const col_total = self.columnTotal(col_idx);

            // Skip columns with zero total
            if (col_total <= 0) continue;

            // Calculate cumulative x-coordinates for column boundaries
            var cumulative: f32 = 0;
            var col_x0: u16 = undefined;
            var col_x1: u16 = undefined;

            // col_x[col_idx]
            for (0..col_idx) |i| {
                cumulative += self.columnTotal(i);
            }
            col_x0 = plot_area.x + @as(u16, @intFromFloat(@floor(cumulative / grand_total * @as(f32, @floatFromInt(plot_area.width)))));

            // col_x[col_idx + 1]
            cumulative += col_total;
            col_x1 = plot_area.x + @as(u16, @intFromFloat(@floor(cumulative / grand_total * @as(f32, @floatFromInt(plot_area.width)))));

            // Ensure last column reaches plot_area.x + plot_area.width
            if (col_idx == n_columns - 1) {
                col_x1 = plot_area.x + plot_area.width;
            }

            const col_width = col_x1 - col_x0;
            if (col_width == 0) continue; // Skip zero-width columns

            // Render segments within this column
            const seg_count = self.segmentCount(col_idx);
            var seg_cumulative: f32 = 0;

            for (0..seg_count) |seg_idx| {
                const seg = col.segments[seg_idx];
                const seg_value = @max(seg.value, 0); // clamp negative to 0

                // Skip zero-value segments
                if (seg_value <= 0) continue;

                // Calculate segment y-coordinates within column
                var seg_y0: u16 = undefined;
                var seg_y1: u16 = undefined;

                // seg_y[seg_idx]
                seg_y0 = plot_area.y + @as(u16, @intFromFloat(@floor(seg_cumulative / col_total * @as(f32, @floatFromInt(plot_area.height)))));

                // seg_y[seg_idx + 1]
                seg_cumulative += seg_value;
                seg_y1 = plot_area.y + @as(u16, @intFromFloat(@floor(seg_cumulative / col_total * @as(f32, @floatFromInt(plot_area.height)))));

                // Ensure last segment reaches plot_area.y + plot_area.height
                if (seg_idx == seg_count - 1) {
                    seg_y1 = plot_area.y + plot_area.height;
                }

                const seg_height = seg_y1 - seg_y0;
                if (seg_height == 0) continue; // Skip zero-height segments

                // Create segment rectangle
                const seg_rect = Rect{
                    .x = col_x0,
                    .y = seg_y0,
                    .width = col_width,
                    .height = seg_height,
                };

                // Determine segment style
                const is_focused = (col_idx == self.focused_column and seg_idx == self.focused_segment);
                const focused_style_is_set = self.focused_style.bold or self.focused_style.dim or
                    self.focused_style.italic or self.focused_style.underline or self.focused_style.blink or
                    self.focused_style.reverse or self.focused_style.strikethrough or
                    self.focused_style.fg != null or self.focused_style.bg != null;

                const seg_style = if (is_focused and focused_style_is_set) self.focused_style else seg.style;

                // Fill segment rectangle with block character
                drawSegment(buf, seg_rect, seg_style);

                // Render segment label if enabled and segment is large enough
                if (self.show_segment_labels and seg.label.len > 0 and col_width >= 1 and seg_height >= 1) {
                    buf.set(col_x0, seg_y0, Cell.init(seg.label[0], self.label_style));
                }
            }
        }
    }
};

/// Render column labels in the header row
fn renderColumnLabels(buf: *Buffer, area: Rect, row_idx: u16, n_columns: usize, self: MosaicPlot) void {
    if (n_columns == 0) return;

    const grand_total = self.grandTotal();
    if (grand_total == 0) return;

    // Determine plot area for width calculations
    var plot_area = area;
    if (self.show_column_labels and row_idx == area.y and plot_area.height > 0) {
        plot_area.y += 1;
        if (plot_area.height > 0) plot_area.height -= 1;
    }

    var cumulative: f32 = 0;
    for (0..n_columns) |col_idx| {
        const col = self.columns[col_idx];

        // Calculate column x position using cumulative formula
        const col_total = self.columnTotal(col_idx);
        const col_x = plot_area.x + @as(u16, @intFromFloat(@floor(cumulative / grand_total * @as(f32, @floatFromInt(plot_area.width)))));

        cumulative += col_total;

        if (col.label.len > 0 and col_x < area.x + area.width) {
            const char = col.label[0];
            buf.set(col_x, row_idx, Cell.init(char, self.label_style));
        }
    }
}

/// Draw a filled segment rectangle
fn drawSegment(buf: *Buffer, area: Rect, style: Style) void {
    if (area.width == 0 or area.height == 0) return;

    // Fill entire segment with block character
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            buf.set(x, y, Cell.init('█', style));
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "MosaicPlot.init creates plot with zero columns" {
    const testing = std.testing;
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.columns.len);
}

test "MosaicPlot.init defaults focused_column to 0" {
    const testing = std.testing;
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.focused_column);
}

test "MosaicPlot.init defaults focused_segment to 0" {
    const testing = std.testing;
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.focused_segment);
}

test "MosaicPlot.init defaults show_column_labels to true" {
    const testing = std.testing;
    const plot = MosaicPlot.init();
    try testing.expectEqual(true, plot.show_column_labels);
}

test "MosaicPlot.init defaults show_segment_labels to false" {
    const testing = std.testing;
    const plot = MosaicPlot.init();
    try testing.expectEqual(false, plot.show_segment_labels);
}

test "MosaicPlot.columnCount with zero columns returns 0" {
    const testing = std.testing;
    const plot = MosaicPlot.init();
    try testing.expectEqual(@as(usize, 0), plot.columnCount());
}

test "columnTotal clamps negative values to 0" {
    const testing = std.testing;
    var segs = [_]MosaicSegment{
        .{ .value = 10 },
        .{ .value = -5 },
        .{ .value = 20 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(f32, 30), plot.columnTotal(0));
}

test "grandTotal clamps negative segment values" {
    const testing = std.testing;
    var segs = [_]MosaicSegment{
        .{ .value = 100 },
        .{ .value = -50 },
    };
    var cols = [_]MosaicColumn{.{ .segments = &segs }};
    const plot = MosaicPlot.init().withColumns(&cols);
    try testing.expectEqual(@as(f32, 100), plot.grandTotal());
}

test "render with 0x0 area does not crash" {
    const testing = std.testing;
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = MosaicPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    plot.render(&buf, area);
}

test "render with zero columns produces no content" {
    const testing = std.testing;
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const plot = MosaicPlot.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    plot.render(&buf, area);
}
