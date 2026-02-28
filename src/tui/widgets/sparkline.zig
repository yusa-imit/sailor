//! Sparkline widget — inline mini-chart for compact data visualization
//!
//! Example usage:
//!
//! ```zig
//! const data = [_]u64{ 10, 20, 15, 30, 25, 40, 35 };
//!
//! const chart = Sparkline.init(&data)
//!     .withBlock(Block.init().withBorders(.all).withTitle("Trend"))
//!     .withStyle(.{ .fg = .{ .indexed = 3 } });
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
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Sparkline widget - inline mini-chart from data series
pub const Sparkline = struct {
    data: []const u64,
    max_value: ?u64 = null,
    block: ?Block = null,
    style: Style = .{},
    bars: []const u8 = "▁▂▃▄▅▆▇█", // Unicode block chars for 8 levels

    /// Create a sparkline with data
    pub fn init(data: []const u64) Sparkline {
        return .{ .data = data };
    }

    /// Set maximum value (for scaling). If null, uses max(data)
    pub fn withMaxValue(self: Sparkline, max: u64) Sparkline {
        var result = self;
        result.max_value = max;
        return result;
    }

    /// Set the block (border) for this sparkline
    pub fn withBlock(self: Sparkline, new_block: Block) Sparkline {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set the style for bars
    pub fn withStyle(self: Sparkline, new_style: Style) Sparkline {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Set custom bar characters (must have at least 2 levels)
    pub fn withBars(self: Sparkline, new_bars: []const u8) Sparkline {
        var result = self;
        result.bars = new_bars;
        return result;
    }

    /// Calculate the maximum value in data
    fn calcMaxValue(data: []const u64) u64 {
        if (data.len == 0) return 0;
        var max: u64 = data[0];
        for (data[1..]) |val| {
            if (val > max) max = val;
        }
        return max;
    }

    /// Get bar character for a value (scaled 0-max to bar levels)
    fn getBarChar(self: Sparkline, value: u64, max: u64) u21 {
        if (max == 0) return self.bars[0];

        // Count unicode chars in bars string
        var bar_count: usize = 0;
        var iter = std.unicode.Utf8View.initUnchecked(self.bars).iterator();
        while (iter.nextCodepoint()) |_| {
            bar_count += 1;
        }

        if (bar_count == 0) return ' ';

        // Scale value to bar level
        const scaled = @min(value * bar_count / (max + 1), bar_count - 1);

        // Get the nth unicode char
        var char_iter = std.unicode.Utf8View.initUnchecked(self.bars).iterator();
        var idx: usize = 0;
        while (char_iter.nextCodepoint()) |cp| {
            if (idx == scaled) return cp;
            idx += 1;
        }

        return self.bars[0];
    }

    /// Render the sparkline widget
    pub fn render(self: Sparkline, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0 or self.data.len == 0) return;

        // Calculate max value
        const max = self.max_value orelse calcMaxValue(self.data);

        // Render sparkline bars
        const available_width = @min(self.data.len, inner_area.width);
        const x_start = inner_area.x;
        const y = inner_area.y + inner_area.height - 1; // Bottom row

        for (self.data[0..available_width], 0..) |value, i| {
            const x = x_start + @as(u16, @intCast(i));
            const bar_char = self.getBarChar(value, max);
            const cell = buffer_mod.Cell.init(bar_char, self.style);
            buf.set(x, y, cell);
        }
    }
};

// Tests
test "Sparkline: create empty" {
    const sparkline = Sparkline.init(&.{});
    try std.testing.expectEqual(@as(usize, 0), sparkline.data.len);
}

test "Sparkline: create with data" {
    const data = [_]u64{ 1, 2, 3, 4, 5 };
    const sparkline = Sparkline.init(&data);
    try std.testing.expectEqual(@as(usize, 5), sparkline.data.len);
    try std.testing.expectEqual(@as(u64, 1), sparkline.data[0]);
}

test "Sparkline: with max value" {
    const data = [_]u64{ 1, 2, 3 };
    const sparkline = Sparkline.init(&data).withMaxValue(10);
    try std.testing.expectEqual(@as(?u64, 10), sparkline.max_value);
}

test "Sparkline: with block" {
    const data = [_]u64{1};
    const blk = Block.init();
    const sparkline = Sparkline.init(&data).withBlock(blk);
    try std.testing.expect(sparkline.block != null);
}

test "Sparkline: with style" {
    const data = [_]u64{1};
    const style = Style{ .bold = true };
    const sparkline = Sparkline.init(&data).withStyle(style);
    try std.testing.expect(sparkline.style.bold);
}

test "Sparkline: with custom bars" {
    const data = [_]u64{1};
    const sparkline = Sparkline.init(&data).withBars(" ▪︎▪︎▪︎");
    try std.testing.expectEqualStrings(" ▪︎▪︎▪︎", sparkline.bars);
}

test "Sparkline: calc max value empty" {
    try std.testing.expectEqual(@as(u64, 0), Sparkline.calcMaxValue(&.{}));
}

test "Sparkline: calc max value single" {
    const data = [_]u64{42};
    try std.testing.expectEqual(@as(u64, 42), Sparkline.calcMaxValue(&data));
}

test "Sparkline: calc max value multiple" {
    const data = [_]u64{ 1, 10, 5, 20, 3 };
    try std.testing.expectEqual(@as(u64, 20), Sparkline.calcMaxValue(&data));
}

test "Sparkline: get bar char zero max" {
    const data = [_]u64{0};
    const sparkline = Sparkline.init(&data);
    const char = sparkline.getBarChar(5, 0);
    try std.testing.expectEqual(@as(u21, '▁'), char);
}

test "Sparkline: get bar char min value" {
    const data = [_]u64{0};
    const sparkline = Sparkline.init(&data);
    const char = sparkline.getBarChar(0, 100);
    try std.testing.expectEqual(@as(u21, '▁'), char);
}

test "Sparkline: get bar char max value" {
    const data = [_]u64{100};
    const sparkline = Sparkline.init(&data);
    const char = sparkline.getBarChar(100, 100);
    // Should be highest bar
    try std.testing.expectEqual(@as(u21, '█'), char);
}

test "Sparkline: get bar char mid value" {
    const data = [_]u64{50};
    const sparkline = Sparkline.init(&data);
    const char = sparkline.getBarChar(50, 100);
    // Should be approximately middle bar
    try std.testing.expect(char != '▁' and char != '█');
}

test "Sparkline: render empty data" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const sparkline = Sparkline.init(&.{});
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // Should not crash
}

test "Sparkline: render single value" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{50};
    const sparkline = Sparkline.init(&data);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // Should render at bottom row
    const cell = buf.get(0, 2);
    try std.testing.expect(cell.char != ' ');
}

test "Sparkline: render multiple values" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3, 4, 5 };
    const sparkline = Sparkline.init(&data);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // Should render all values at bottom row
    for (0..5) |i| {
        const cell = buf.get(@intCast(i), 2);
        try std.testing.expect(cell.char != ' ');
    }
}

test "Sparkline: render with explicit max" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 5, 10 };
    const sparkline = Sparkline.init(&data).withMaxValue(20);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // Values should be scaled to max=20, not max=10
}

test "Sparkline: render with block" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3 };
    const blk = Block.init();
    const sparkline = Sparkline.init(&data).withBlock(blk);
    sparkline.render(&buf, Rect.init(0, 0, 10, 5));

    // Should render both block and sparkline
}

test "Sparkline: render with custom style" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{50};
    const style = Style{ .bold = true };
    const sparkline = Sparkline.init(&data).withStyle(style);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    const cell = buf.get(0, 2);
    try std.testing.expect(cell.style.bold);
}

test "Sparkline: render zero size area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{1};
    const sparkline = Sparkline.init(&data);

    // Should not crash
    sparkline.render(&buf, Rect.init(0, 0, 0, 3));
    sparkline.render(&buf, Rect.init(0, 0, 10, 0));
}

test "Sparkline: render truncates data to width" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const sparkline = Sparkline.init(&data);
    sparkline.render(&buf, Rect.init(0, 0, 5, 3));

    // Should only render first 5 values
    for (0..5) |i| {
        const cell = buf.get(@intCast(i), 2);
        try std.testing.expect(cell.char != ' ');
    }
}

test "Sparkline: all same values" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 5, 5, 5, 5 };
    const sparkline = Sparkline.init(&data);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // All bars should be max height since all values are equal
    for (0..4) |i| {
        const cell = buf.get(@intCast(i), 2);
        try std.testing.expectEqual(@as(u21, '█'), cell.char);
    }
}

test "Sparkline: ascending values" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const sparkline = Sparkline.init(&data);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // Each bar should be taller than the previous
    var prev_char: u21 = 0;
    for (0..8) |i| {
        const cell = buf.get(@intCast(i), 2);
        // Just verify we got valid chars
        try std.testing.expect(cell.char >= '▁' and cell.char <= '█');
        if (i > 0) {
            try std.testing.expect(cell.char >= prev_char);
        }
        prev_char = cell.char;
    }
}

test "Sparkline: descending values" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 8, 7, 6, 5, 4, 3, 2, 1 };
    const sparkline = Sparkline.init(&data);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // Each bar should be shorter than the previous
    var prev_char: u21 = 255;
    for (0..8) |i| {
        const cell = buf.get(@intCast(i), 2);
        try std.testing.expect(cell.char >= '▁' and cell.char <= '█');
        if (i > 0) {
            try std.testing.expect(cell.char <= prev_char);
        }
        prev_char = cell.char;
    }
}

test "Sparkline: zero values" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 0, 0, 0 };
    const sparkline = Sparkline.init(&data);
    sparkline.render(&buf, Rect.init(0, 0, 10, 3));

    // All should be minimum bar
    for (0..3) |i| {
        const cell = buf.get(@intCast(i), 2);
        try std.testing.expectEqual(@as(u21, '▁'), cell.char);
    }
}
