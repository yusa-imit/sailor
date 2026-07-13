//! ParetoChart Widget — descending-sorted bars with cumulative percentage line
//!
//! The ParetoChart widget displays Pareto data as vertical bars sorted by value
//! (highest on left), with an overlaid cumulative percentage line and optional
//! 80% threshold marker. Ideal for visualizing the Pareto principle (80/20 rule)
//! where a few items dominate the total.
//!
//! ## Features
//! - Up to 32 items (MAX_ITEMS)
//! - Descending bar height by value (when sorted=true)
//! - Cumulative percentage line overlay
//! - Configurable threshold marker (default 80%)
//! - Optional value labels on bars
//! - Focused item highlighting
//! - Block border support
//! - No heap allocations
//! - Robust out-of-range handling (no panics on negative/zero/huge values)
//!
//! ## Usage
//! ```zig
//! const items = [_]ParetoItem{
//!     .{ .label = "Bugs", .value = 80.0 },
//!     .{ .label = "Feature Reqs", .value = 50.0 },
//!     .{ .label = "Documentation", .value = 20.0 },
//! };
//!
//! const chart = ParetoChart.init()
//!     .withItems(&items)
//!     .withSorted(true)
//!     .withShowCumulativeLine(true)
//!     .withThreshold(0.8);
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

/// Single item in a Pareto chart
pub const ParetoItem = struct {
    /// Label for the item (e.g., "Bugs", "Feature Requests")
    label: []const u8 = "",
    /// Value to display
    value: f32 = 0.0,
    /// Optional custom style for this item
    style: Style = .{},
};

pub const ParetoChart = struct {
    /// Maximum number of items (capped at 32 for rendering)
    pub const MAX_ITEMS: usize = 32;

    /// Array of items to display
    items: []const ParetoItem = &.{},
    /// Index of the focused item for highlighting
    focused: usize = 0,
    /// Whether to sort items by value descending (true) or preserve input order (false)
    sorted: bool = true,
    /// Whether to render numeric value labels on bars
    show_values: bool = true,
    /// Whether to render the cumulative percentage line
    show_cumulative_line: bool = true,
    /// Whether to render the threshold marker line
    show_threshold: bool = true,
    /// Threshold value (0.0-1.0) for marker line (default 0.8 = 80%)
    threshold: f32 = 0.8,
    /// Base style applied to all items
    style: Style = .{},
    /// Style for bars
    bar_style: Style = .{},
    /// Style for cumulative line
    line_style: Style = .{},
    /// Style for threshold marker
    threshold_style: Style = .{},
    /// Style for focused item
    focused_style: Style = .{},
    /// Style for item labels
    label_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a ParetoChart with all defaults
    pub fn init() ParetoChart {
        return .{};
    }

    /// Count of items to render (capped at MAX_ITEMS)
    pub fn itemCount(self: ParetoChart) usize {
        return @min(self.items.len, MAX_ITEMS);
    }

    /// Set items array
    pub fn withItems(self: ParetoChart, i: []const ParetoItem) ParetoChart {
        var result = self;
        result.items = i;
        return result;
    }

    /// Set focused item index
    pub fn withFocused(self: ParetoChart, idx: usize) ParetoChart {
        var result = self;
        result.focused = idx;
        return result;
    }

    /// Set sorted flag
    pub fn withSorted(self: ParetoChart, s: bool) ParetoChart {
        var result = self;
        result.sorted = s;
        return result;
    }

    /// Set show_values flag
    pub fn withShowValues(self: ParetoChart, show: bool) ParetoChart {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set show_cumulative_line flag
    pub fn withShowCumulativeLine(self: ParetoChart, show: bool) ParetoChart {
        var result = self;
        result.show_cumulative_line = show;
        return result;
    }

    /// Set show_threshold flag
    pub fn withShowThreshold(self: ParetoChart, show: bool) ParetoChart {
        var result = self;
        result.show_threshold = show;
        return result;
    }

    /// Set threshold value
    pub fn withThreshold(self: ParetoChart, t: f32) ParetoChart {
        var result = self;
        result.threshold = t;
        return result;
    }

    /// Set base style
    pub fn withStyle(self: ParetoChart, s: Style) ParetoChart {
        var result = self;
        result.style = s;
        return result;
    }

    /// Set bar_style
    pub fn withBarStyle(self: ParetoChart, s: Style) ParetoChart {
        var result = self;
        result.bar_style = s;
        return result;
    }

    /// Set line_style
    pub fn withLineStyle(self: ParetoChart, s: Style) ParetoChart {
        var result = self;
        result.line_style = s;
        return result;
    }

    /// Set threshold_style
    pub fn withThresholdStyle(self: ParetoChart, s: Style) ParetoChart {
        var result = self;
        result.threshold_style = s;
        return result;
    }

    /// Set focused_style
    pub fn withFocusedStyle(self: ParetoChart, s: Style) ParetoChart {
        var result = self;
        result.focused_style = s;
        return result;
    }

    /// Set label_style
    pub fn withLabelStyle(self: ParetoChart, s: Style) ParetoChart {
        var result = self;
        result.label_style = s;
        return result;
    }

    /// Set block border
    pub fn withBlock(self: ParetoChart, b: ?Block) ParetoChart {
        var result = self;
        result.block = b;
        return result;
    }

    /// Render the Pareto chart to the buffer
    pub fn render(self: ParetoChart, buf: *Buffer, area: Rect) void {
        // Early exits for invalid areas
        if (area.width == 0 or area.height == 0) return;

        // Apply block border if present
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        const n = self.itemCount();
        if (n == 0) return;

        // Need minimum area to render
        if (inner.width == 0 or inner.height == 0) return;

        // ========== Step 1: Build sort order ==========
        // On-stack indices array for sorting (max 32 items)
        var indices: [MAX_ITEMS]usize = undefined;
        for (0..n) |i| {
            indices[i] = i;
        }

        // Sort indices by value descending if sorted=true
        if (self.sorted) {
            sortDescending(self.items[0..n], &indices, n);
        }

        // ========== Step 2: Find max value for scaling ==========
        var max_value: f32 = 0.0;
        for (0..n) |i| {
            const item = self.items[i];
            const val = @max(item.value, 0.0); // Treat negative as 0
            if (val > max_value) {
                max_value = val;
            }
        }

        // Guard against division by zero
        const safe_max_value = if (max_value > 0.0) max_value else 1.0;

        // ========== Step 3: Calculate total sum for cumulative % ==========
        var total_sum: f32 = 0.0;
        for (0..n) |i| {
            const item = self.items[i];
            const val = @max(item.value, 0.0);
            total_sum += val;
        }

        const safe_total_sum = if (total_sum > 0.0) total_sum else 1.0;

        // ========== Step 4: Check if focused_style is explicitly set ==========
        const focused_style_is_set = self.focused_style.bold or self.focused_style.dim or
            self.focused_style.italic or self.focused_style.underline or self.focused_style.blink or
            self.focused_style.reverse or self.focused_style.strikethrough or
            self.focused_style.fg != null or self.focused_style.bg != null;

        // ========== Step 5: Render bars and cumulative line ==========
        const bar_width = if (n > 0) (inner.width / @as(u16, @intCast(n))) else inner.width;
        var cumulative_sum: f32 = 0.0;

        for (0..n) |i| {
            const item_idx = indices[i];
            const item = self.items[item_idx];
            const is_focused = (item_idx == self.focused);

            const bar_x = inner.x + @as(u16, @intCast(i)) * bar_width;
            const bar_center = bar_x + bar_width / 2;

            const item_value = @max(item.value, 0.0);

            // ========== Render vertical bar ==========
            const normalized_value = item_value / safe_max_value;
            const bar_height_f = normalized_value * @as(f32, @floatFromInt(inner.height));
            const bar_height = @as(usize, @intFromFloat(@round(bar_height_f)));
            const bar_height_clamped = @min(bar_height, inner.height);

            const bar_style = if (is_focused and focused_style_is_set) self.focused_style else item.style;

            // Draw bar from bottom up
            if (bar_height_clamped > 0) {
                var bar_row: usize = 0;
                while (bar_row < bar_height_clamped) : (bar_row += 1) {
                    const row = inner.y + @as(u16, @intCast(inner.height - 1 - bar_row));
                    if (bar_center < inner.x + inner.width) {
                        buf.set(bar_center, row, Cell.init('█', bar_style));
                    }
                }
            }

            // ========== Render value label if enabled ==========
            if (self.show_values) {
                var value_text: [16]u8 = undefined;
                const value_str = std.fmt.bufPrint(&value_text, "{d:.0}", .{item_value}) catch "?";
                const label_y = inner.y + inner.height; // Below the bar area
                if (label_y < inner.y + inner.height + 2) {
                    var text_x = bar_center;
                    for (value_str) |ch| {
                        if (text_x < inner.x + inner.width) {
                            buf.set(text_x, label_y, Cell.init(ch, self.label_style));
                            text_x += 1;
                        }
                    }
                }
            }

            // ========== Render cumulative percentage line ==========
            if (self.show_cumulative_line) {
                cumulative_sum += item_value;
                const cumulative_percent = cumulative_sum / safe_total_sum;
                const cumulative_percent_clamped = std.math.clamp(cumulative_percent, 0.0, 1.0);

                const line_row_f = @as(f32, @floatFromInt(inner.height - 1)) * (1.0 - cumulative_percent_clamped);
                const line_row = @as(i32, @intFromFloat(@round(line_row_f)));
                const line_row_clamped = std.math.clamp(line_row, 0, @as(i32, @intCast(inner.height - 1)));

                const row = inner.y + @as(u16, @intCast(line_row_clamped));
                if (bar_center < inner.x + inner.width) {
                    buf.set(bar_center, row, Cell.init('•', self.line_style));
                }
            }
        }

        // ========== Step 6: Render threshold marker ==========
        if (self.show_threshold) {
            const threshold_clamped = std.math.clamp(self.threshold, 0.0, 1.0);
            const threshold_row_f = @as(f32, @floatFromInt(inner.height - 1)) * (1.0 - threshold_clamped);
            const threshold_row = @as(i32, @intFromFloat(@round(threshold_row_f)));
            const threshold_row_clamped = std.math.clamp(threshold_row, 0, @as(i32, @intCast(inner.height - 1)));

            const row = inner.y + @as(u16, @intCast(threshold_row_clamped));

            // Draw threshold line across the width
            var x = inner.x;
            while (x < inner.x + inner.width) : (x += 1) {
                buf.set(x, row, Cell.init('─', self.threshold_style));
            }
        }
    }
};

/// Sort indices array by corresponding item values in descending order
/// Uses simple insertion sort (good for small arrays up to MAX_ITEMS=32)
fn sortDescending(items: []const ParetoItem, indices: []usize, n: usize) void {
    for (1..n) |i| {
        var j = i;
        while (j > 0) {
            const prev_idx = indices[j - 1];
            const curr_idx = indices[j];
            const prev_val = @max(items[prev_idx].value, 0.0);
            const curr_val = @max(items[curr_idx].value, 0.0);

            if (prev_val >= curr_val) {
                break;
            }

            // Swap
            indices[j - 1] = curr_idx;
            indices[j] = prev_idx;
            j -= 1;
        }
    }
}

// ============================================================================
// In-file library tests (minimal — main test suite in tests/pareto_chart_test.zig)
// ============================================================================

test "ParetoChart.init creates default chart with zero items" {
    const chart = ParetoChart.init();
    try std.testing.expectEqual(@as(usize, 0), chart.items.len);
}

test "ParetoChart.init defaults sorted to true" {
    const chart = ParetoChart.init();
    try std.testing.expectEqual(true, chart.sorted);
}

test "ParetoChart.init defaults threshold to 0.8" {
    const chart = ParetoChart.init();
    try std.testing.expect(@abs(chart.threshold - 0.8) < 0.001);
}

test "ParetoChart.itemCount caps at MAX_ITEMS" {
    var items: [50]ParetoItem = undefined;
    for (0..50) |i| {
        items[i] = .{ .label = "I", .value = @as(f32, @floatFromInt(i)) };
    }
    const chart = ParetoChart.init().withItems(&items);
    try std.testing.expectEqual(@as(usize, 32), chart.itemCount());
}

test "ParetoChart.withItems maintains immutability" {
    var items1 = [_]ParetoItem{.{ .label = "A", .value = 50.0 }};
    var items2 = [_]ParetoItem{
        .{ .label = "X", .value = 30.0 },
        .{ .label = "Y", .value = 70.0 },
    };

    const chart1 = ParetoChart.init().withItems(&items1);
    const chart2 = chart1.withItems(&items2);

    try std.testing.expectEqual(@as(usize, 1), chart1.itemCount());
    try std.testing.expectEqual(@as(usize, 2), chart2.itemCount());
}

test "ParetoChart.render with zero area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    var items = [_]ParetoItem{.{ .label = "A", .value = 50.0 }};
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };

    chart.render(&buf, area);
    // No crash is success
}

test "ParetoChart.render with empty items renders nothing" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const chart = ParetoChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    chart.render(&buf, area);

    // Should produce no visible content
    var non_empty: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    non_empty += 1;
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), non_empty);
}

test "ParetoChart.render with single item produces content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 5);
    defer buf.deinit();

    var items = [_]ParetoItem{.{ .label = "Revenue", .value = 75.0 }};
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    chart.render(&buf, area);

    // Should produce some content
    var non_empty: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    non_empty += 1;
                }
            }
        }
    }
    try std.testing.expect(non_empty > 0);
}

test "ParetoChart.render with out-of-range value does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Huge", .value = 1_000_000.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    // This render should NOT panic/crash
    chart.render(&buf, area);
}

test "ParetoChart.render with negative value does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Negative", .value = -50.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
}

test "ParetoChart.render with all zero values does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    var items = [_]ParetoItem{
        .{ .label = "Z1", .value = 0.0 },
        .{ .label = "Z2", .value = 0.0 },
    };
    const chart = ParetoChart.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    chart.render(&buf, area);
}
