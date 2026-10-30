//! Sparkline widget — inline mini-chart for compact data visualization
//!
//! Example usage:
//!
//! ```zig
//! const data = [_]u64{ 10, 20, 15, 30, 25, 40, 35 };
//!
//! const chart = Sparkline.init(&data)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Trend"))
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

    /// Get bar character for a value (scaled 0-max to bar levels).
    /// 0 maps to the first bar and `max` (or anything above it) to the last bar.
    fn getBarChar(self: Sparkline, value: u64, max: u64) u21 {
        // Count unicode chars in bars string
        var bar_count: usize = 0;
        var iter = std.unicode.Utf8View.initUnchecked(self.bars).iterator();
        while (iter.nextCodepoint()) |_| {
            bar_count += 1;
        }

        if (bar_count == 0) return ' ';

        // Scale value to bar level (widen to u128 to avoid overflow on extreme values)
        const scaled: usize = if (max == 0) 0 else blk: {
            const scaled_wide: u128 = @as(u128, value) * @as(u128, bar_count - 1) / @as(u128, max);
            break :blk @intCast(@min(scaled_wide, bar_count - 1));
        };

        // Get the nth unicode char
        var char_iter = std.unicode.Utf8View.initUnchecked(self.bars).iterator();
        var idx: usize = 0;
        while (char_iter.nextCodepoint()) |cp| {
            if (idx == scaled) return cp;
            idx += 1;
        }

        unreachable; // scaled < bar_count and the iterator yields exactly bar_count codepoints
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

const testing = std.testing;
const Cell = buffer_mod.Cell;

fn rect(x: u16, y: u16, width: u16, height: u16) Rect {
    return Rect{ .x = x, .y = y, .width = width, .height = height };
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
    for (buf.cells) |cell| try testing.expect(cell.eql(Cell{}));
}

test "Sparkline: init has documented defaults" {
    const data = [_]u64{ 1, 2, 3, 4, 5 };
    const sparkline = Sparkline.init(&data);

    try testing.expectEqual(@as(usize, 5), sparkline.data.len);
    try testing.expectEqual(@as(u64, 1), sparkline.data[0]);
    try testing.expectEqual(@as(?u64, null), sparkline.max_value);
    try testing.expect(sparkline.block == null);
    try testing.expect(std.meta.eql(Style{}, sparkline.style));
    try testing.expectEqualStrings("▁▂▃▄▅▆▇█", sparkline.bars);
    try testing.expectEqual(@as(usize, 0), Sparkline.init(&.{}).data.len);
}

test "Sparkline: builders set one field and keep the others" {
    const data = [_]u64{ 1, 2, 3 };
    const base = Sparkline.init(&data);

    const with_max = base.withMaxValue(10);
    try testing.expectEqual(@as(?u64, 10), with_max.max_value);
    try testing.expect(with_max.block == null);

    const with_block = base.withBlock(Block{});
    try testing.expect(with_block.block != null);
    try testing.expectEqual(@as(?u64, null), with_block.max_value);

    const with_style = base.withStyle(Style{ .bold = true });
    try testing.expect(with_style.style.bold);
    try testing.expect(!base.style.bold); // builders copy, they do not mutate the receiver

    const with_bars = base.withBars("-=#");
    try testing.expectEqualStrings("-=#", with_bars.bars);
    try testing.expectEqual(@as(usize, 3), with_bars.data.len);
}

test "Sparkline: calcMaxValue handles empty, single, and multiple values" {
    try testing.expectEqual(@as(u64, 0), Sparkline.calcMaxValue(&.{}));
    try testing.expectEqual(@as(u64, 42), Sparkline.calcMaxValue(&[_]u64{42}));
    try testing.expectEqual(@as(u64, 20), Sparkline.calcMaxValue(&[_]u64{ 1, 10, 5, 20, 3 }));
    try testing.expectEqual(@as(u64, 9), Sparkline.calcMaxValue(&[_]u64{ 9, 1, 2 }));
}

test "Sparkline: getBarChar with zero max yields the lowest bar" {
    const sparkline = Sparkline.init(&.{});
    try testing.expectEqual(@as(u21, '▁'), sparkline.getBarChar(5, 0));
    try testing.expectEqual(@as(u21, '▁'), sparkline.getBarChar(0, 0));
}

test "Sparkline: getBarChar maps 0 to the lowest and max to the highest bar" {
    const sparkline = Sparkline.init(&.{});
    try testing.expectEqual(@as(u21, '▁'), sparkline.getBarChar(0, 100));
    try testing.expectEqual(@as(u21, '█'), sparkline.getBarChar(100, 100));
    try testing.expectEqual(@as(u21, '█'), sparkline.getBarChar(5, 5));
    try testing.expectEqual(@as(u21, '█'), sparkline.getBarChar(1, 1));
}

test "Sparkline: getBarChar scales intermediate values by floor" {
    const sparkline = Sparkline.init(&.{});
    try testing.expectEqual(@as(u21, '▄'), sparkline.getBarChar(50, 100)); // 50*7/100 = 3
    try testing.expectEqual(@as(u21, '▃'), sparkline.getBarChar(1, 3)); // 1*7/3 = 2
    try testing.expectEqual(@as(u21, '▅'), sparkline.getBarChar(2, 3)); // 2*7/3 = 4
    try testing.expectEqual(@as(u21, '▁'), sparkline.getBarChar(14, 100)); // 98/100 = 0
    try testing.expectEqual(@as(u21, '▂'), sparkline.getBarChar(15, 100)); // 105/100 = 1
}

test "Sparkline: getBarChar clamps values above max to the highest bar" {
    const sparkline = Sparkline.init(&.{});
    try testing.expectEqual(@as(u21, '█'), sparkline.getBarChar(1000, 20));
    try testing.expectEqual(@as(u21, '█'), sparkline.getBarChar(std.math.maxInt(u64), 1));
}

test "Sparkline: getBarChar does not overflow at the u64 extremes" {
    const sparkline = Sparkline.init(&.{});
    const max = std.math.maxInt(u64);
    try testing.expectEqual(@as(u21, '█'), sparkline.getBarChar(max, max));
    try testing.expectEqual(@as(u21, '▁'), sparkline.getBarChar(0, max));
    try testing.expectEqual(@as(u21, '▄'), sparkline.getBarChar(max / 2, max)); // 7/2 = 3
}

test "Sparkline: getBarChar honours custom bars and an empty bar set" {
    const custom = Sparkline.init(&.{}).withBars("-=#");
    try testing.expectEqual(@as(u21, '-'), custom.getBarChar(0, 10));
    try testing.expectEqual(@as(u21, '='), custom.getBarChar(5, 10));
    try testing.expectEqual(@as(u21, '#'), custom.getBarChar(10, 10));

    const empty = Sparkline.init(&.{}).withBars("");
    try testing.expectEqual(@as(u21, ' '), empty.getBarChar(5, 10));
    try testing.expectEqual(@as(u21, ' '), empty.getBarChar(5, 0));
}

test "Sparkline: render empty data leaves the buffer untouched" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    Sparkline.init(&.{}).render(&buf, rect(0, 0, 10, 3));

    try expectBlank(buf);
}

test "Sparkline: render single value fills the bottom row cell with the top bar" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{50};
    Sparkline.init(&data).render(&buf, rect(0, 0, 10, 3));

    try testing.expectEqual(@as(u21, '█'), buf.getChar(0, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(1, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "Sparkline: render multiple values scales to the data maximum" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3, 4, 5 };
    Sparkline.init(&data).render(&buf, rect(0, 0, 10, 3));

    try expectRow(buf, 0, 2, "▂▃▅▆█"); // v*7/5 = 1, 2, 4, 5, 7
    try testing.expectEqual(@as(u21, ' '), buf.getChar(5, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
}

test "Sparkline: render with explicit max scales against it, not the data" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 5, 10, 20, 40 };
    Sparkline.init(&data).withMaxValue(20).render(&buf, rect(0, 0, 10, 3));

    // 5*7/20 = 1, 10*7/20 = 3, 20 -> top, 40 above max clamps to top
    try expectRow(buf, 0, 2, "▂▄██");
}

test "Sparkline: render with block draws the border and keeps bars in the inner area" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3 };
    Sparkline.init(&data).withBlock(Block{}).render(&buf, rect(0, 0, 10, 5));

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(9, 0));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(0, 4));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(9, 4));
    // Inner area is (1, 1, 8, 3): bottom inner row is y = 3.
    try expectRow(buf, 1, 3, "▃▅█");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(4, 3));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(0, 3));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(1, 4));
}

test "Sparkline: render with block and empty data still draws the border" {
    var buf = try Buffer.init(testing.allocator, 6, 4);
    defer buf.deinit();

    Sparkline.init(&.{}).withBlock(Block{}).render(&buf, rect(0, 0, 6, 4));

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(5, 3));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(1, 2));
}

test "Sparkline: render with block leaving no inner area draws no bars" {
    var buf = try Buffer.init(testing.allocator, 4, 4);
    defer buf.deinit();

    const data = [_]u64{9};
    Sparkline.init(&data).withBlock(Block{}).render(&buf, rect(0, 0, 2, 2));

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(1, 1));
    for (buf.cells) |cell| try testing.expect(cell.char != '█');
}

test "Sparkline: render applies the style to every bar cell only" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const style = Style{ .bold = true, .fg = .{ .indexed = 3 } };
    const data = [_]u64{ 10, 50 };
    Sparkline.init(&data).withStyle(style).render(&buf, rect(0, 0, 10, 3));

    try testing.expect(std.meta.eql(style, buf.getStyle(0, 2)));
    try testing.expect(std.meta.eql(style, buf.getStyle(1, 2)));
    try testing.expect(!buf.getStyle(2, 2).bold);
    try testing.expect(!buf.getStyle(0, 1).bold);
}

test "Sparkline: render with zero-sized area leaves the buffer untouched" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{1};
    const sparkline = Sparkline.init(&data).withBlock(Block{});
    sparkline.render(&buf, rect(0, 0, 0, 3));
    sparkline.render(&buf, rect(0, 0, 10, 0));

    try expectBlank(buf);
}

test "Sparkline: render truncates data to the area width" {
    var buf = try Buffer.init(testing.allocator, 8, 3);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    Sparkline.init(&data).render(&buf, rect(0, 0, 5, 3));

    // Scale uses the full data maximum (10), not just the visible prefix:
    // v*7/10 = 0, 1, 2, 2, 3
    try expectRow(buf, 0, 2, "▁▂▃▃▄");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(5, 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(7, 2));
}

test "Sparkline: render honours the area offset" {
    var buf = try Buffer.init(testing.allocator, 10, 6);
    defer buf.deinit();

    const data = [_]u64{ 0, 8 };
    Sparkline.init(&data).render(&buf, rect(2, 1, 4, 3)); // bottom row is y = 3

    try expectRow(buf, 2, 3, "▁█");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(1, 3));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(4, 3));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(2, 5));
}

test "Sparkline: render clips silently when the area exceeds the buffer" {
    var buf = try Buffer.init(testing.allocator, 4, 2);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3 };
    // Bottom row y = 4 is outside the 2-row buffer: nothing is written.
    Sparkline.init(&data).render(&buf, rect(0, 0, 10, 5));
    buf.check_invariants();
    try expectBlank(buf);

    // Row in range but columns beyond the buffer width are clipped.
    const wide = [_]u64{ 0, 1, 0, 1, 0, 1 };
    Sparkline.init(&wide).render(&buf, rect(0, 0, 6, 2));
    try expectRow(buf, 0, 1, "▁█▁█");
}

test "Sparkline: all same non-zero values render as the top bar" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 5, 5, 5, 5 };
    Sparkline.init(&data).render(&buf, rect(0, 0, 10, 3));

    try expectRow(buf, 0, 2, "████");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(4, 2));
}

test "Sparkline: ascending 1..8 uses each bar level exactly once" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 1, 2, 3, 4, 5, 6, 7, 8 };
    Sparkline.init(&data).render(&buf, rect(0, 0, 10, 3));

    try expectRow(buf, 0, 2, "▁▂▃▄▅▆▇█");
}

test "Sparkline: descending 8..1 mirrors the ascending bars" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 8, 7, 6, 5, 4, 3, 2, 1 };
    Sparkline.init(&data).render(&buf, rect(0, 0, 10, 3));

    try expectRow(buf, 0, 2, "█▇▆▅▄▃▂▁");
}

test "Sparkline: all zero values render as the lowest bar" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]u64{ 0, 0, 0 };
    Sparkline.init(&data).render(&buf, rect(0, 0, 10, 3));

    try expectRow(buf, 0, 2, "▁▁▁");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(3, 2));
}

test "Sparkline: render with custom ASCII bars" {
    var buf = try Buffer.init(testing.allocator, 6, 2);
    defer buf.deinit();

    const data = [_]u64{ 0, 5, 10 };
    Sparkline.init(&data).withBars("-=#").render(&buf, rect(0, 0, 6, 2));

    try expectRow(buf, 0, 1, "-=#");
}

test "Sparkline: render handles u64 maximum values" {
    var buf = try Buffer.init(testing.allocator, 4, 1);
    defer buf.deinit();

    const data = [_]u64{ 0, std.math.maxInt(u64) };
    Sparkline.init(&data).render(&buf, rect(0, 0, 4, 1));

    try expectRow(buf, 0, 0, "▁█");
}
