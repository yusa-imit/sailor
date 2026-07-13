//! ParallelCoordinates Widget — multi-dimensional data as parallel axes with polylines
//!
//! The ParallelCoordinates widget displays multi-dimensional data as a set of parallel
//! vertical axes. Each data item is drawn as a polyline connecting its normalized values
//! on each axis, allowing visual comparison of multi-dimensional properties.
//!
//! ## Features
//! - Up to 8 axes and 16 items (MAX_AXES, MAX_ITEMS)
//! - Configurable axis labels, min/max ranges
//! - Normalized value mapping to row positions
//! - Per-item polylines with optional styling
//! - Focused item highlighting
//! - Optional axis labels and range displays
//! - Block border support
//! - No heap allocations
//! - Robust out-of-range handling
//!
//! ## Usage
//! ```zig
//! var axes = [_]PCAxis{
//!     .{ .label = "CPU", .min = 0.0, .max = 100.0 },
//!     .{ .label = "Memory", .min = 0.0, .max = 100.0 },
//! };
//! var values = [_]f32{ 45.0, 72.0 };
//! var items = [_]PCItem{.{ .label = "Server1", .values = &values }};
//! var chart = ParallelCoordinates.init()
//!     .withAxes(&axes)
//!     .withItems(&items);
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

/// Single axis for parallel coordinates
pub const PCAxis = struct {
    /// Label for this axis
    label: []const u8 = "",
    /// Minimum value for this axis
    min: f32 = 0.0,
    /// Maximum value for this axis
    max: f32 = 1.0,
};

/// Single data item (series) for parallel coordinates
pub const PCItem = struct {
    /// Label for this item
    label: []const u8 = "",
    /// Values for each axis (one per axis)
    values: []const f32 = &.{},
    /// Style for rendering this item's polyline
    style: Style = .{},
};

/// ParallelCoordinates widget for multi-dimensional data visualization
pub const ParallelCoordinates = struct {
    /// Maximum number of axes
    pub const MAX_AXES: usize = 8;
    /// Maximum number of items
    pub const MAX_ITEMS: usize = 16;

    /// Array of axis definitions
    axes: []const PCAxis = &.{},
    /// Array of data items
    items: []const PCItem = &.{},
    /// Index of focused item for highlighting
    focused: usize = 0,
    /// Whether to display axis labels
    show_labels: bool = true,
    /// Whether to display axis min/max values
    show_axis_range: bool = true,
    /// Base style for all elements
    style: Style = .{},
    /// Style for axis lines
    axis_style: Style = .{},
    /// Style for focused item polyline
    focused_style: Style = .{},
    /// Style for labels and range text
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a ParallelCoordinates with defaults
    pub fn init() ParallelCoordinates {
        return .{};
    }

    /// Count of axes to render (capped at MAX_AXES)
    pub fn axisCount(self: ParallelCoordinates) usize {
        return @min(self.axes.len, MAX_AXES);
    }

    /// Count of items to render (capped at MAX_ITEMS)
    pub fn itemCount(self: ParallelCoordinates) usize {
        return @min(self.items.len, MAX_ITEMS);
    }

    /// Set axes array
    pub fn withAxes(self: ParallelCoordinates, axes: []const PCAxis) ParallelCoordinates {
        var result = self;
        result.axes = axes;
        return result;
    }

    /// Set items array
    pub fn withItems(self: ParallelCoordinates, items: []const PCItem) ParallelCoordinates {
        var result = self;
        result.items = items;
        return result;
    }

    /// Set focused item index
    pub fn withFocused(self: ParallelCoordinates, idx: usize) ParallelCoordinates {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: ParallelCoordinates, show: bool) ParallelCoordinates {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_axis_range flag
    pub fn withShowAxisRange(self: ParallelCoordinates, show: bool) ParallelCoordinates {
        var result = self;
        result.show_axis_range = show;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: ParallelCoordinates, s: Style) ParallelCoordinates {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set axis_style
    pub fn withAxisStyle(self: ParallelCoordinates, s: Style) ParallelCoordinates {
        var result = self;
        result.axis_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: ParallelCoordinates, s: Style) ParallelCoordinates {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: ParallelCoordinates, s: Style) ParallelCoordinates {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: ParallelCoordinates, b: ?Block) ParallelCoordinates {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the parallel coordinates chart to the buffer
    pub fn render(self: ParallelCoordinates, buf: *Buffer, area: Rect) void {
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

        const n_axes = self.axisCount();
        const n_items = self.itemCount();

        // Early exit if no axes
        if (n_axes == 0) return;

        // For single axis, just draw the vertical line without polylines
        if (n_axes == 1) {
            drawAxis(buf, inner, 0, self.axes, self.axis_style, self.label_style, self.show_labels, self.show_axis_range);
            return;
        }

        // Draw each axis as a vertical line
        for (0..n_axes) |i| {
            drawAxis(buf, inner, i, self.axes, self.axis_style, self.label_style, self.show_labels, self.show_axis_range);
        }

        // Draw polylines for each item
        for (0..n_items) |item_idx| {
            const item = self.items[item_idx];
            const is_focused = item_idx == self.focused;

            // Check if focused_style is explicitly set
            const focused_style_is_set = self.focused_style.bold or self.focused_style.dim or
                self.focused_style.italic or self.focused_style.underline or self.focused_style.blink or
                self.focused_style.reverse or self.focused_style.strikethrough or
                self.focused_style.fg != null or self.focused_style.bg != null;

            const item_style = if (is_focused and focused_style_is_set) self.focused_style else item.style;

            // Draw polyline connecting consecutive axes
            for (0..n_axes - 1) |axis_idx| {
                const axis_i = self.axes[axis_idx];
                const axis_i1 = self.axes[axis_idx + 1];

                // Get values for this item on these two axes
                var value_i: f32 = 0.0;
                if (axis_idx < item.values.len) {
                    value_i = item.values[axis_idx];
                }

                var value_i1: f32 = 0.0;
                if (axis_idx + 1 < item.values.len) {
                    value_i1 = item.values[axis_idx + 1];
                }

                // Normalize values to [0, 1]
                const t_i = normalizeValue(value_i, axis_i.min, axis_i.max);
                const t_i1 = normalizeValue(value_i1, axis_i1.min, axis_i1.max);

                // Calculate screen coordinates
                const x_i = axisX(inner, axis_idx, n_axes);
                const y_i = axisY(inner, t_i);

                const x_i1 = axisX(inner, axis_idx + 1, n_axes);
                const y_i1 = axisY(inner, t_i1);

                // Draw line between the two points
                drawLine(buf, inner, @as(i32, @intCast(x_i)), @as(i32, @intCast(y_i)),
                         @as(i32, @intCast(x_i1)), @as(i32, @intCast(y_i1)), item_style);
            }
        }
    }
};

/// Normalize a value to [0, 1] range given axis min/max
fn normalizeValue(value: f32, min: f32, max: f32) f32 {
    // Guard against division by zero (min == max)
    if (max == min) {
        return 0.5; // Midpoint fallback for zero-range axes
    }

    const normalized = (value - min) / (max - min);
    return math.clamp(normalized, 0.0, 1.0);
}

/// Calculate x coordinate for an axis at given index
fn axisX(inner: Rect, axis_idx: usize, n_axes: usize) u16 {
    if (n_axes == 1) {
        // Single axis: center it
        return inner.x + inner.width / 2;
    }

    const idx_f = @as(f32, @floatFromInt(axis_idx));
    const n_f = @as(f32, @floatFromInt(n_axes - 1));
    const frac = idx_f / n_f;
    const x_offset = @as(u16, @intFromFloat(frac * @as(f32, @floatFromInt(inner.width - 1))));
    return inner.x + x_offset;
}

/// Calculate y coordinate for a normalized value (t in [0, 1])
/// t=0 maps to bottom (inner.y + inner.height - 1)
/// t=1 maps to top (inner.y)
fn axisY(inner: Rect, t: f32) u16 {
    if (inner.height == 0) return inner.y;

    const height_minus_1 = if (inner.height > 1) inner.height - 1 else 0;
    const offset = @as(u16, @intFromFloat(t * @as(f32, @floatFromInt(height_minus_1))));
    const row = inner.y + height_minus_1 - offset;
    return row;
}

/// Draw a vertical axis line
fn drawAxis(buf: *Buffer, area: Rect, axis_idx: usize, axes: []const PCAxis,
            axis_style: Style, label_style: Style, show_labels: bool, show_axis_range: bool) void {
    if (axis_idx >= axes.len or area.height == 0) return;

    const axis = axes[axis_idx];
    const n_axes = axes.len;
    const x = axisX(area, axis_idx, n_axes);

    // Draw vertical line
    for (0..area.height) |y_offset| {
        const y = area.y + @as(u16, @intCast(y_offset));
        buf.set(x, y, Cell.init('│', axis_style));
    }

    // Draw axis label at top if enabled
    if (show_labels and axis.label.len > 0) {
        renderText(buf, x, area.y, area.x + area.width, axis.label, label_style, true);
    }

    // Draw min/max range labels if enabled
    if (show_axis_range) {
        // Min value at bottom
        var min_buf: [16]u8 = undefined;
        const min_str = formatFloat(&min_buf, axis.min);
        if (area.height > 0) {
            const y_bottom = area.y + area.height - 1;
            renderText(buf, x, y_bottom, area.x + area.width, min_str, label_style, false);
        }

        // Max value at top
        var max_buf: [16]u8 = undefined;
        const max_str = formatFloat(&max_buf, axis.max);
        if (area.height > 1) {
            renderText(buf, x, area.y, area.x + area.width, max_str, label_style, true);
        }
    }
}

/// Draw a line using Bresenham's algorithm
fn drawLine(buf: *Buffer, area: Rect, x0: i32, y0: i32, x1: i32, y1: i32, style_arg: Style) void {
    const dx = @abs(x1 - x0);
    const dy = @abs(y1 - y0);
    const sx: i32 = if (x1 > x0) 1 else -1;
    const sy: i32 = if (y1 > y0) 1 else -1;
    var err = @as(i32, @intCast(dx)) - @as(i32, @intCast(dy));
    var x = x0;
    var y = y0;

    while (true) {
        // Bounds check before plotting
        if (x >= 0 and y >= 0) {
            const px: u16 = @intCast(x);
            const py: u16 = @intCast(y);
            if (px >= area.x and px < area.x + area.width and
                py >= area.y and py < area.y + area.height) {
                buf.set(px, py, Cell.init('·', style_arg));
            }
        }

        if (x == x1 and y == y1) break;

        const e2 = 2 * err;
        if (e2 > -@as(i32, @intCast(dy))) {
            err -= @as(i32, @intCast(dy));
            x += sx;
        }
        if (e2 < @as(i32, @intCast(dx))) {
            err += @as(i32, @intCast(dx));
            y += sy;
        }
    }
}

/// Format a float value into a string
fn formatFloat(buf: *[16]u8, value: f32) []const u8 {
    const result = std.fmt.bufPrint(buf, "{d:.0}", .{value}) catch "?";
    return result;
}

/// Render text at a position, truncated/padded to fit within bounds
fn renderText(buf: *Buffer, x: u16, y: u16, max_x: u16, text: []const u8, style: Style, center: bool) void {
    if (y >= buf.height) return;

    const available_width = if (x < max_x) max_x - x else 0;
    if (available_width == 0) return;

    var start_x = x;
    if (center and text.len < available_width) {
        // Center the text
        const padding = (available_width - @as(u16, @intCast(text.len))) / 2;
        start_x = x + padding;
    }

    var pos = start_x;
    for (0..@min(text.len, available_width)) |i| {
        if (pos >= max_x) break;
        const char = text[i];
        buf.set(pos, y, Cell.init(char, style));
        pos += 1;
    }
}

// ============================================================================
// In-file library tests (minimal — main test suite in tests/parallel_coordinates_test.zig)
// ============================================================================

test "ParallelCoordinates.init creates empty chart" {
    const pc = ParallelCoordinates.init();
    try std.testing.expectEqual(@as(usize, 0), pc.axes.len);
    try std.testing.expectEqual(@as(usize, 0), pc.items.len);
}

test "PCAxis defaults" {
    const axis = PCAxis{};
    try std.testing.expectEqualStrings("", axis.label);
    try std.testing.expect(@abs(axis.min - 0.0) < 0.001);
    try std.testing.expect(@abs(axis.max - 1.0) < 0.001);
}

test "PCItem defaults" {
    const item = PCItem{};
    try std.testing.expectEqualStrings("", item.label);
    try std.testing.expectEqual(@as(usize, 0), item.values.len);
}

test "ParallelCoordinates.axisCount caps at MAX_AXES" {
    var axes: [12]PCAxis = undefined;
    for (0..12) |i| {
        axes[i] = .{};
    }
    const pc = ParallelCoordinates.init().withAxes(&axes);
    try std.testing.expectEqual(@as(usize, 8), pc.axisCount());
}

test "ParallelCoordinates.itemCount caps at MAX_ITEMS" {
    var items: [20]PCItem = undefined;
    for (0..20) |i| {
        items[i] = .{};
    }
    const pc = ParallelCoordinates.init().withItems(&items);
    try std.testing.expectEqual(@as(usize, 16), pc.itemCount());
}

test "normalizeValue clamps to [0, 1]" {
    try std.testing.expect(normalizeValue(50.0, 0.0, 100.0) > 0.4 and normalizeValue(50.0, 0.0, 100.0) < 0.6);
    try std.testing.expect(normalizeValue(150.0, 0.0, 100.0) > 0.99);
    try std.testing.expect(normalizeValue(-50.0, 0.0, 100.0) < 0.01);
}

test "normalizeValue handles zero-range axes" {
    const t = normalizeValue(5.0, 5.0, 5.0);
    try std.testing.expect(t >= 0.0 and t <= 1.0);
}
