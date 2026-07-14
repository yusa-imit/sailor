//! SlopeChart Widget — before/after two-point comparison lines per category
//!
//! The SlopeChart widget displays before/after comparisons as diagonal lines
//! connecting two points (left value, right value) for each item. Each item draws
//! a line with optional labels, and direction-based coloring (increase, decrease, flat).
//!
//! ## Features
//! - Up to 16 items (MAX_ITEMS)
//! - Two-point values per item normalized to [min_value, max_value]
//! - Slope direction detection (/, \, ─ characters)
//! - Direction-based styling (increase, decrease, flat)
//! - Optional item labels at endpoints
//! - Optional numeric values at endpoints
//! - Optional column labels (left/right headers)
//! - Focused item highlighting
//! - Block border support
//! - No heap allocations
//! - Robust out-of-range handling (no panics)
//!
//! ## Usage
//! ```zig
//! const items = [_]SlopeItem{
//!     .{ .label = "Revenue", .left_value = 50.0, .right_value = 75.0 },
//!     .{ .label = "Costs", .left_value = 30.0, .right_value = 40.0 },
//! };
//!
//! const chart = SlopeChart.init()
//!     .withItems(&items)
//!     .withMinValue(0.0)
//!     .withMaxValue(100.0)
//!     .withLeftLabel("Q1")
//!     .withRightLabel("Q2")
//!     .withShowLabels(true)
//!     .withShowValues(true);
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

/// Single item in a slope chart
pub const SlopeItem = struct {
    /// Label for this item
    label: []const u8 = "",
    /// Left side value (e.g., before/baseline)
    left_value: f32 = 0.0,
    /// Right side value (e.g., after/current)
    right_value: f32 = 0.0,
    /// Optional per-item style override
    style: Style = .{},
};

pub const SlopeChart = struct {
    /// Maximum number of items (capped at 16 for rendering)
    pub const MAX_ITEMS: usize = 16;

    /// Array of items to display
    items: []const SlopeItem = &.{},
    /// Index of the focused item for highlighting
    focused: usize = 0,
    /// Minimum value for normalization
    min_value: f32 = 0.0,
    /// Maximum value for normalization
    max_value: f32 = 1.0,
    /// Label for left column (before/baseline)
    left_label: []const u8 = "",
    /// Label for right column (after/current)
    right_label: []const u8 = "",
    /// Whether to render item labels at endpoints
    show_labels: bool = true,
    /// Whether to render numeric values at endpoints
    show_values: bool = false,
    /// Whether to render column header labels (left_label/right_label)
    show_column_labels: bool = true,
    /// Character to use for endpoint markers
    point_char: u21 = '●',
    /// Base style applied to all elements
    style: Style = .{},
    /// Style for slope lines
    line_style: Style = .{},
    /// Style for slopes with right > left
    increase_style: Style = .{},
    /// Style for slopes with right < left
    decrease_style: Style = .{},
    /// Style for slopes with right == left
    flat_style: Style = .{},
    /// Style for focused item
    focused_style: Style = .{},
    /// Style for item labels
    label_style: Style = .{},
    /// Style for column labels
    column_label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a SlopeChart with all defaults
    pub fn init() SlopeChart {
        return .{};
    }

    /// Count of items to render (capped at MAX_ITEMS)
    pub fn itemCount(self: SlopeChart) usize {
        return @min(self.items.len, MAX_ITEMS);
    }

    /// Set items array
    pub fn withItems(self: SlopeChart, i: []const SlopeItem) SlopeChart {
        var result = self;
        result.items = i;
        return result;
    }

    /// Set focused item index
    pub fn withFocused(self: SlopeChart, idx: usize) SlopeChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set min_value
    pub fn withMinValue(self: SlopeChart, v: f32) SlopeChart {
        var result = self;
        result.min_value = v;
        return result;
    }

    /// Set max_value
    pub fn withMaxValue(self: SlopeChart, v: f32) SlopeChart {
        var result = self;
        result.max_value = v;
        return result;
    }

    /// Set left_label
    pub fn withLeftLabel(self: SlopeChart, label: []const u8) SlopeChart {
        var result = self;
        result.left_label = label;
        return result;
    }

    /// Set right_label
    pub fn withRightLabel(self: SlopeChart, label: []const u8) SlopeChart {
        var result = self;
        result.right_label = label;
        return result;
    }

    /// Set show_labels flag
    pub fn withShowLabels(self: SlopeChart, show: bool) SlopeChart {
        var result = self;
        result.show_labels = show;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: SlopeChart, show: bool) SlopeChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set show_column_labels flag
    pub fn withShowColumnLabels(self: SlopeChart, show: bool) SlopeChart {
        var result = self;
        result.show_column_labels = show;
        return result;
    }

    /// Set point_char
    pub fn withPointChar(self: SlopeChart, ch: u21) SlopeChart {
        var result = self;
        result.point_char = ch;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set line_style
    pub fn withLineStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.line_style = s;
        return result;
    }

    /// Set increase_style
    pub fn withIncreaseStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.increase_style = s;
        return result;
    }

    /// Set decrease_style
    pub fn withDecreaseStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.decrease_style = s;
        return result;
    }

    /// Set flat_style
    pub fn withFlatStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.flat_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set column_label_style
    pub fn withColumnLabelStyle(self: SlopeChart, s: Style) SlopeChart {
        var result = self;
        result.column_label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: SlopeChart, b: ?Block) SlopeChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the slope chart to the buffer
    pub fn render(self: SlopeChart, buf: *Buffer, area: Rect) void {
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

        const n_items = self.itemCount();
        if (n_items == 0) return;

        // Calculate if we need a header row for column labels
        const has_column_labels = self.show_column_labels and
            (self.left_label.len > 0 or self.right_label.len > 0);
        const header_height: u16 = if (has_column_labels) 1 else 0;
        const chart_y0 = inner.y + header_height;
        const chart_height: u16 = if (inner.height > header_height)
            inner.height - header_height
        else
            0;

        // Draw column header row if needed
        if (has_column_labels) {
            drawColumnLabels(buf, inner, self.left_label, self.right_label, self.column_label_style);
        }

        // If no chart height left, just return
        if (chart_height == 0) return;

        // Create chart area for drawing
        var chart_area = inner;
        chart_area.y = chart_y0;
        chart_area.height = chart_height;

        // Calculate column widths for labels and values
        var left_col_width: u16 = 0;
        var right_col_width: u16 = 0;

        if (self.show_labels or self.show_values) {
            calculateColumnWidths(self, n_items, &left_col_width, &right_col_width, inner.width);
        }

        // Calculate line endpoints x positions
        const left_pad: u16 = if (left_col_width > 0) 1 else 0;
        const right_pad: u16 = if (right_col_width > 0) 1 else 0;
        const left_x = inner.x + left_col_width + left_pad;
        const right_x = inner.x + inner.width - 1 - right_col_width - right_pad;

        // Guard: if not enough horizontal space for slopes
        if (right_x <= left_x) {
            // Still render headers if present
            return;
        }

        // Check if focused_style is explicitly set
        const focused_style_is_set = styleIsSet(self.focused_style);

        // Render each item
        for (0..n_items) |i| {
            const item = self.items[i];
            const is_focused = (i == self.focused);

            // Normalize values
            const left_t = normalizeValue(item.left_value, self.min_value, self.max_value);
            const right_t = normalizeValue(item.right_value, self.min_value, self.max_value);

            // Calculate row positions in chart
            const left_row = axisY(chart_area, left_t);
            const right_row = axisY(chart_area, right_t);

            // Determine slope direction and character
            const slope_char: u21 = if (right_t > left_t)
                '/'
            else if (right_t < left_t)
                '\\'
            else
                '─';

            // Determine style for this item
            const item_style = if (is_focused and focused_style_is_set)
                self.focused_style
            else if (styleIsSet(item.style))
                item.style
            else
                switch (@as(u2, if (right_t > left_t) 1 else if (right_t < left_t) 2 else 0)) {
                    0 => if (styleIsSet(self.flat_style)) self.flat_style else self.line_style,
                    1 => if (styleIsSet(self.increase_style)) self.increase_style else self.line_style,
                    2 => if (styleIsSet(self.decrease_style)) self.decrease_style else self.line_style,
                    3 => unreachable,
                };

            // Draw the slope line using Bresenham
            drawLine(buf, chart_area, @as(i32, @intCast(left_x)), @as(i32, @intCast(left_row)),
                     @as(i32, @intCast(right_x)), @as(i32, @intCast(right_row)), slope_char, item_style);

            // Draw endpoints (after line so they're visible)
            buf.set(left_x, left_row, Cell.init(self.point_char, item_style));
            buf.set(right_x, right_row, Cell.init(self.point_char, item_style));

            // Draw labels and values if enabled
            if (self.show_labels or self.show_values) {
                drawItemLabelsAndValues(buf, inner, chart_area, item, i, left_x, right_x, left_row, right_row,
                                       left_col_width, right_col_width, self.show_labels, self.show_values,
                                       self.label_style);
            }
        }
    }
};

/// Check if a style has any attributes set
fn styleIsSet(s: Style) bool {
    return s.bold or s.dim or s.italic or s.underline or s.blink or
           s.reverse or s.strikethrough or s.fg != null or s.bg != null;
}

/// Normalize a value to [0, 1] range based on [min, max]
fn normalizeValue(value: f32, min: f32, max: f32) f32 {
    // Guard against division by zero (min == max)
    if (max == min) {
        return 0.5; // Midpoint fallback for zero-range
    }

    const normalized = (value - min) / (max - min);
    return math.clamp(normalized, 0.0, 1.0);
}

/// Calculate y coordinate for a normalized value (t in [0, 1])
/// t=0 maps to bottom (area.y + area.height - 1)
/// t=1 maps to top (area.y)
fn axisY(area: Rect, t: f32) u16 {
    if (area.height == 0) return area.y;

    const height_minus_1 = if (area.height > 1) area.height - 1 else 0;
    const offset = @as(u16, @intFromFloat(t * @as(f32, @floatFromInt(height_minus_1))));
    const row = area.y + height_minus_1 - offset;
    return row;
}

/// Draw a line using Bresenham's algorithm with a specific character
fn drawLine(buf: *Buffer, area: Rect, x0: i32, y0: i32, x1: i32, y1: i32, char: u21, style: Style) void {
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
                buf.set(px, py, Cell.init(char, style));
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

/// Calculate column widths for labels and values
fn calculateColumnWidths(chart: SlopeChart, n_items: usize, left_width: *u16, right_width: *u16, max_width: u16) void {
    var left_max: usize = 0;
    var right_max: usize = 0;

    for (0..n_items) |i| {
        const item = chart.items[i];
        var left_len: usize = 0;
        var right_len: usize = 0;

        if (chart.show_labels and item.label.len > 0) {
            left_len += item.label.len;
            right_len += item.label.len;
        }

        if (chart.show_values) {
            if (left_len > 0) left_len += 1; // space before value
            left_len += 4; // room for value like "0.5" or "100"
            if (right_len > 0) right_len += 1; // space before value
            right_len += 4; // room for value
        }

        if (left_len > left_max) left_max = left_len;
        if (right_len > right_max) right_max = right_len;
    }

    // Cap to 1/3 of available width each
    const cap = max_width / 3;
    left_width.* = @min(@as(u16, @intCast(@min(left_max, 100))), cap);
    right_width.* = @min(@as(u16, @intCast(@min(right_max, 100))), cap);
}

/// Draw column labels (left_label at left_x, right_label at right_x)
fn drawColumnLabels(buf: *Buffer, inner: Rect, left_label: []const u8, right_label: []const u8, style: Style) void {
    if (inner.height == 0) return;
    const header_y = inner.y;

    // Render left label (will be positioned near left side in render)
    // For simplicity, we'll place it left-aligned starting from inner.x
    if (left_label.len > 0) {
        var x = inner.x;
        for (left_label) |ch| {
            if (x < inner.x + inner.width) {
                buf.set(x, header_y, Cell.init(ch, style));
                x += 1;
            }
        }
    }

    // Render right label (right-aligned ending at inner.x + inner.width - 1)
    if (right_label.len > 0) {
        var x_end = inner.x + inner.width;
        if (x_end > right_label.len) {
            x_end -= @as(u16, @intCast(right_label.len));
        } else {
            x_end = inner.x;
        }

        var x = x_end;
        for (right_label) |ch| {
            if (x < inner.x + inner.width) {
                buf.set(x, header_y, Cell.init(ch, style));
                x += 1;
            }
        }
    }
}

/// Draw item labels and values at the endpoints
fn drawItemLabelsAndValues(buf: *Buffer, inner: Rect, chart_area: Rect, item: SlopeItem, item_idx: usize,
                          left_x: u16, right_x: u16, left_row: u16, right_row: u16,
                          left_col_width: u16, right_col_width: u16,
                          show_labels: bool, show_values: bool, style: Style) void {
    _ = item_idx; // Unused for now, but kept for future extension
    _ = chart_area; // Not currently used, but kept for context
    // Left column (label and/or value)
    if (left_col_width > 0) {
        var text_buf: [64]u8 = undefined;
        var text_len: usize = 0;

        if (show_labels and item.label.len > 0) {
            @memcpy(text_buf[0..item.label.len], item.label);
            text_len = item.label.len;
        }

        if (show_values) {
            if (text_len > 0) {
                text_buf[text_len] = ' ';
                text_len += 1;
            }
            var val_buf: [16]u8 = undefined;
            const val_str = std.fmt.bufPrint(&val_buf, "{d:.0}", .{item.left_value}) catch "?";
            @memcpy(text_buf[text_len..text_len + val_str.len], val_str);
            text_len += val_str.len;
        }

        if (text_len > 0) {
            // Left-align at inner.x
            var x = inner.x;
            for (text_buf[0..text_len]) |ch| {
                if (x < left_x) {
                    buf.set(x, left_row, Cell.init(ch, style));
                    x += 1;
                }
            }
        }
    }

    // Right column (value and/or label)
    if (right_col_width > 0) {
        var text_buf: [64]u8 = undefined;
        var text_len: usize = 0;

        if (show_values) {
            var val_buf: [16]u8 = undefined;
            const val_str = std.fmt.bufPrint(&val_buf, "{d:.0}", .{item.right_value}) catch "?";
            @memcpy(text_buf[0..val_str.len], val_str);
            text_len = val_str.len;
        }

        if (show_labels and item.label.len > 0) {
            if (text_len > 0) {
                text_buf[text_len] = ' ';
                text_len += 1;
            }
            @memcpy(text_buf[text_len..text_len + item.label.len], item.label);
            text_len += item.label.len;
        }

        if (text_len > 0) {
            // Left-align at right_x + 1
            var x = right_x + 1;
            for (text_buf[0..text_len]) |ch| {
                if (x < inner.x + inner.width) {
                    buf.set(x, right_row, Cell.init(ch, style));
                    x += 1;
                }
            }
        }
    }
}
