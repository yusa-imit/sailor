//! BarChart widget — vertical bar chart with customizable styling
//!
//! Example usage:
//!
//! ```zig
//! const bars = [_]BarChart.Bar{
//!     .{ .label = "Jan", .value = 100 },
//!     .{ .label = "Feb", .value = 150 },
//!     .{ .label = "Mar", .value = 120 },
//! };
//!
//! const chart = BarChart.init(&bars)
//!     .withBlock(Block.init().withBorders(.all).withTitle("Sales"))
//!     .withBarStyle(.{ .fg = .{ .indexed = 2 } })
//!     .withBarWidth(5)
//!     .withBarGap(2);
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
const Block = block_mod.Block;

/// BarChart widget - vertical bar chart with labels
pub const BarChart = struct {
    pub const Bar = struct {
        label: []const u8,
        value: u64,
        style: Style = .{},
    };

    bars: []const Bar,
    max_value: ?u64 = null,
    block: ?Block = null,
    bar_width: usize = 3,
    bar_gap: usize = 1,
    bar_style: Style = .{},
    value_style: Style = .{},
    label_style: Style = .{},

    /// Create a bar chart with bars
    pub fn init(bars: []const Bar) BarChart {
        return .{ .bars = bars };
    }

    /// Set maximum value (for scaling). If null, uses max(bars)
    pub fn withMaxValue(self: BarChart, max: u64) BarChart {
        var result = self;
        result.max_value = max;
        return result;
    }

    /// Set the block (border) for this bar chart
    pub fn withBlock(self: BarChart, new_block: Block) BarChart {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set bar width (default: 3)
    pub fn withBarWidth(self: BarChart, width: usize) BarChart {
        var result = self;
        result.bar_width = width;
        return result;
    }

    /// Set gap between bars (default: 1)
    pub fn withBarGap(self: BarChart, gap: usize) BarChart {
        var result = self;
        result.bar_gap = gap;
        return result;
    }

    /// Set default style for all bars
    pub fn withBarStyle(self: BarChart, new_style: Style) BarChart {
        var result = self;
        result.bar_style = new_style;
        return result;
    }

    /// Set style for value labels above bars
    pub fn withValueStyle(self: BarChart, new_style: Style) BarChart {
        var result = self;
        result.value_style = new_style;
        return result;
    }

    /// Set style for bar labels below bars
    pub fn withLabelStyle(self: BarChart, new_style: Style) BarChart {
        var result = self;
        result.label_style = new_style;
        return result;
    }

    /// Calculate the maximum value in bars
    fn calcMaxValue(bars: []const Bar) u64 {
        if (bars.len == 0) return 0;
        var max: u64 = bars[0].value;
        for (bars[1..]) |bar| {
            if (bar.value > max) max = bar.value;
        }
        return max;
    }

    /// Render the bar chart
    pub fn render(self: BarChart, buf: *Buffer, area: Rect) void {
        // Render block border first
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (inner.width == 0 or inner.height == 0 or self.bars.len == 0) return;

        const max = self.max_value orelse calcMaxValue(self.bars);
        if (max == 0) return;

        // Reserve 1 line for values above bars, 1 line for labels below
        // Actual bar height is inner.height - 2
        if (inner.height < 3) return; // Need at least 3 rows (value, bar, label)

        const bar_height = inner.height - 2;

        // Calculate total width needed
        const bar_unit_width = self.bar_width + self.bar_gap;
        const total_width_needed = self.bars.len * bar_unit_width;

        // Calculate starting x position (centered)
        var x_offset: u16 = 0;
        if (total_width_needed < inner.width) {
            x_offset = @intCast((inner.width - total_width_needed) / 2);
        }

        // Render each bar
        for (self.bars, 0..) |bar, i| {
            const bar_x = inner.x + x_offset + @as(u16, @intCast(i * bar_unit_width));

            // Skip if bar goes beyond bounds
            if (bar_x >= inner.x + inner.width) break;

            // Calculate bar height (scaled)
            const scaled_height = if (max > 0)
                @min((bar.value * bar_height) / max, bar_height)
            else
                0;

            // Determine bar style (use bar-specific style if set, else default)
            const bar_s = if (bar.style.fg != null or bar.style.bg != null)
                bar.style
            else
                self.bar_style;

            // Render bar (from bottom up)
            const bar_start_y = inner.y + bar_height - @as(u16, @intCast(scaled_height));
            var y = bar_start_y;
            while (y < inner.y + bar_height) : (y += 1) {
                var dx: u16 = 0;
                while (dx < self.bar_width and bar_x + dx < inner.x + inner.width) : (dx += 1) {
                    buf.setCell(bar_x + dx, y + 1, '█', bar_s); // +1 to skip value line
                }
            }

            // Render value above bar
            const value_str = std.fmt.allocPrint(
                buf.allocator,
                "{d}",
                .{bar.value},
            ) catch return;
            defer buf.allocator.free(value_str);

            const value_x = bar_x + (self.bar_width / 2);
            if (value_x < inner.x + inner.width and value_str.len > 0) {
                buf.setString(value_x, inner.y, value_str, self.value_style);
            }

            // Render label below bar
            const label_y = inner.y + inner.height - 1;
            const label_x = bar_x;

            // Truncate label to fit bar width
            const label_len = @min(bar.label.len, self.bar_width);
            const label_slice = bar.label[0..label_len];

            if (label_x + label_len <= inner.x + inner.width) {
                buf.setString(label_x, label_y, label_slice, self.label_style);
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "BarChart.init creates empty chart" {
    const bars: []const BarChart.Bar = &.{};
    const chart = BarChart.init(bars);
    try testing.expectEqual(0, chart.bars.len);
}

test "BarChart.init with bars" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
        .{ .label = "B", .value = 20 },
        .{ .label = "C", .value = 15 },
    };
    const chart = BarChart.init(&bars);
    try testing.expectEqual(3, chart.bars.len);
    try testing.expectEqualStrings("A", chart.bars[0].label);
    try testing.expectEqual(10, chart.bars[0].value);
}

test "BarChart.withMaxValue sets max value" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
    };
    const chart = BarChart.init(&bars).withMaxValue(100);
    try testing.expectEqual(100, chart.max_value.?);
}

test "BarChart.withBlock sets block" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
    };
    const blk = Block.init().withTitle("Chart");
    const chart = BarChart.init(&bars).withBlock(blk);
    try testing.expect(chart.block != null);
}

test "BarChart.withBarWidth sets bar width" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
    };
    const chart = BarChart.init(&bars).withBarWidth(5);
    try testing.expectEqual(5, chart.bar_width);
}

test "BarChart.withBarGap sets bar gap" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
    };
    const chart = BarChart.init(&bars).withBarGap(2);
    try testing.expectEqual(2, chart.bar_gap);
}

test "BarChart.withBarStyle sets bar style" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
    };
    const style = Style{ .fg = Color.blue, .bold = true };
    const chart = BarChart.init(&bars).withBarStyle(style);
    try testing.expect(chart.bar_style.fg != null);
    try testing.expect(chart.bar_style.bold);
}

test "BarChart.withValueStyle sets value style" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
    };
    const style = Style{ .fg = Color.green };
    const chart = BarChart.init(&bars).withValueStyle(style);
    try testing.expect(chart.value_style.fg != null);
}

test "BarChart.withLabelStyle sets label style" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
    };
    const style = Style{ .fg = Color.yellow };
    const chart = BarChart.init(&bars).withLabelStyle(style);
    try testing.expect(chart.label_style.fg != null);
}

test "BarChart.calcMaxValue returns 0 for empty bars" {
    const bars: []const BarChart.Bar = &.{};
    try testing.expectEqual(0, BarChart.calcMaxValue(bars));
}

test "BarChart.calcMaxValue returns max value" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
        .{ .label = "B", .value = 25 },
        .{ .label = "C", .value = 15 },
    };
    try testing.expectEqual(25, BarChart.calcMaxValue(&bars));
}

test "BarChart.render renders empty chart" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const bars: []const BarChart.Bar = &.{};
    const chart = BarChart.init(bars);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    chart.render(&buf, area);
    // Should not crash
}

test "BarChart.render renders single bar" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
    };
    const chart = BarChart.init(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    chart.render(&buf, area);

    // Check that bar character is present (█)
    var found_bar = false;
    for (0..10) |y| {
        for (0..10) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '█') {
                found_bar = true;
                break;
            }
        }
    }
    try testing.expect(found_bar);
}

test "BarChart.render renders multiple bars" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 30 },
        .{ .label = "B", .value = 50 },
        .{ .label = "C", .value = 20 },
    };
    const chart = BarChart.init(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    chart.render(&buf, area);

    // Check that multiple bar characters are present
    var bar_count: usize = 0;
    for (0..10) |y| {
        for (0..20) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '█') {
                bar_count += 1;
            }
        }
    }
    try testing.expect(bar_count > 0);
}

test "BarChart.render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 15, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
    };
    const blk = Block.init().withBorders(.all);
    const chart = BarChart.init(&bars).withBlock(blk);
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };

    chart.render(&buf, area);

    // Check for border characters
    const top_left = buf.get(0, 0);
    try testing.expect(top_left.char == '┌');
}

test "BarChart.render with custom bar width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
    };
    const chart = BarChart.init(&bars).withBarWidth(5);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    chart.render(&buf, area);

    // Count bar width
    var width_count: usize = 0;
    const mid_y = 5; // middle row
    for (0..20) |x| {
        const cell = buf.get(@intCast(x), mid_y);
        if (cell.char == '█') {
            width_count += 1;
        }
    }
    // Should have at most 5 consecutive bar chars
    try testing.expect(width_count <= 5);
}

test "BarChart.render with custom bar style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
    };
    const style = Style{ .fg = Color.blue, .bold = true };
    const chart = BarChart.init(&bars).withBarStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    chart.render(&buf, area);

    // Find a bar cell and check style
    var found_styled_bar = false;
    for (0..10) |y| {
        for (0..10) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '█') {
                if (cell.style.bold) {
                    found_styled_bar = true;
                    break;
                }
            }
        }
    }
    try testing.expect(found_styled_bar);
}

test "BarChart.render with zero area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
    };
    const chart = BarChart.init(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    chart.render(&buf, area);
    // Should not crash
}

test "BarChart.render with max value" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
    };
    const chart = BarChart.init(&bars).withMaxValue(100);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    chart.render(&buf, area);

    // Bar should be scaled to 100, so half height
    var bar_count: usize = 0;
    for (0..10) |y| {
        for (0..10) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == '█') {
                bar_count += 1;
            }
        }
    }
    try testing.expect(bar_count > 0);
}

test "BarChart.render with per-bar style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 30, .style = .{ .fg = Color.red } },
        .{ .label = "B", .value = 50, .style = .{ .fg = Color.green } },
    };
    const chart = BarChart.init(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    chart.render(&buf, area);

    // Should render without crash (per-bar styles override default)
}

test "BarChart.render with labels" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "Jan", .value = 30 },
        .{ .label = "Feb", .value = 50 },
    };
    const chart = BarChart.init(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    chart.render(&buf, area);

    // Check that label characters are present
    var found_label = false;
    const label_y = 9; // bottom row
    for (0..20) |x| {
        const cell = buf.get(@intCast(x), label_y);
        if (cell.char == 'J' or cell.char == 'F') {
            found_label = true;
            break;
        }
    }
    try testing.expect(found_label);
}

test "BarChart.render with values" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 42 },
    };
    const chart = BarChart.init(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    chart.render(&buf, area);

    // Check that value characters are present (should show "42" at top)
    var found_digit = false;
    const value_y = 0; // top row
    for (0..20) |x| {
        const cell = buf.get(@intCast(x), value_y);
        if (cell.char == '4' or cell.char == '2') {
            found_digit = true;
            break;
        }
    }
    try testing.expect(found_digit);
}

test "BarChart.render with bar gap" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    const chart = BarChart.init(&bars).withBarGap(3);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    chart.render(&buf, area);

    // Should render with gap (verification by visual inspection in real use)
}

test "BarChart.render truncates long labels" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "VeryLongLabel", .value = 50 },
    };
    const chart = BarChart.init(&bars).withBarWidth(3);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    chart.render(&buf, area);

    // Label should be truncated to bar width (3 chars)
    const label_y = 9;
    var label_len: usize = 0;
    for (0..20) |x| {
        const cell = buf.get(@intCast(x), label_y);
        if (cell.char != ' ') {
            label_len += 1;
        }
    }
    // Should have at most 3 chars for label (truncated)
    try testing.expect(label_len <= 3);
}

test "BarChart.render with insufficient height" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 2);
    defer buf.deinit();

    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
    };
    const chart = BarChart.init(&bars);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 };

    chart.render(&buf, area);
    // Should not crash (height < 3, renders nothing)
}
