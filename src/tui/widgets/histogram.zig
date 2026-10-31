//! Histogram widget — frequency distribution bars
//!
//! Example usage:
//!
//! ```zig
//! const bins = [_]Histogram.Bin{
//!     .{ .label = "0-10", .count = 5 },
//!     .{ .label = "10-20", .count = 12 },
//!     .{ .label = "20-30", .count = 8 },
//!     .{ .label = "30-40", .count = 3 },
//! };
//!
//! const hist = Histogram.init(&bins)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Distribution"))
//!     .withBarStyle(.{ .fg = .{ .indexed = 2 } })
//!     .withOrientation(.vertical);
//!
//! hist.render(&buffer, area);
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

/// Histogram widget - frequency distribution bars
pub const Histogram = struct {
    pub const Bin = struct {
        label: []const u8,
        count: u64,
        style: ?Style = null, // Optional per-bin style
    };

    pub const Orientation = enum {
        vertical, // Bars grow upward
        horizontal, // Bars grow rightward
    };

    bins: []const Bin,
    block: ?Block = null,
    bar_style: Style = .{ .fg = .{ .indexed = 2 } }, // Default green
    label_style: Style = .{},
    orientation: Orientation = .vertical,
    bar_char: u21 = '█',
    show_values: bool = true,
    max_bar_height: ?u16 = null, // For vertical orientation
    max_bar_width: ?u16 = null, // For horizontal orientation

    /// Create a histogram with bins
    pub fn init(bins: []const Bin) Histogram {
        return .{ .bins = bins };
    }

    /// Set the block (border) for this histogram
    pub fn withBlock(self: Histogram, new_block: Block) Histogram {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set bar style
    pub fn withBarStyle(self: Histogram, new_style: Style) Histogram {
        var result = self;
        result.bar_style = new_style;
        return result;
    }

    /// Set label style
    pub fn withLabelStyle(self: Histogram, new_style: Style) Histogram {
        var result = self;
        result.label_style = new_style;
        return result;
    }

    /// Set orientation
    pub fn withOrientation(self: Histogram, orientation: Orientation) Histogram {
        var result = self;
        result.orientation = orientation;
        return result;
    }

    /// Set bar character
    pub fn withBarChar(self: Histogram, char: u21) Histogram {
        var result = self;
        result.bar_char = char;
        return result;
    }

    /// Show or hide count values
    pub fn withShowValues(self: Histogram, show: bool) Histogram {
        var result = self;
        result.show_values = show;
        return result;
    }

    /// Set maximum bar height (for vertical orientation)
    pub fn withMaxBarHeight(self: Histogram, height: u16) Histogram {
        var result = self;
        result.max_bar_height = height;
        return result;
    }

    /// Set maximum bar width (for horizontal orientation)
    pub fn withMaxBarWidth(self: Histogram, width: u16) Histogram {
        var result = self;
        result.max_bar_width = width;
        return result;
    }

    /// Find maximum count across all bins
    fn maxCount(bins: []const Bin) u64 {
        var max: u64 = 0;
        for (bins) |bin| {
            if (bin.count > max) max = bin.count;
        }
        return max;
    }

    /// Scale `count` into `0..extent` relative to `max`. Wide arithmetic keeps counts near
    /// `maxInt(u64)` from overflowing the multiplication.
    fn scaled(count: u64, extent: u16, max: u64) u16 {
        std.debug.assert(max > 0);
        std.debug.assert(count <= max);
        const result = (@as(u128, count) * @as(u128, extent)) / @as(u128, max);
        std.debug.assert(result <= extent);
        return @intCast(result);
    }

    /// Number of decimal digits needed to print `n`.
    fn digitCount(n: u64) u16 {
        var digits: u16 = 1;
        var rest = n / 10;
        while (rest > 0) : (rest /= 10) digits += 1;
        return digits;
    }

    /// Render the histogram
    pub fn render(self: Histogram, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.width == 0 or render_area.height == 0) return;
        if (self.bins.len == 0) return;

        switch (self.orientation) {
            .vertical => self.renderVertical(buf, render_area),
            .horizontal => self.renderHorizontal(buf, render_area),
        }
    }

    fn renderVertical(self: Histogram, buf: *Buffer, area: Rect) void {
        const max = maxCount(self.bins);
        if (max == 0) return;

        // Reserve space for labels and values
        const label_height: u16 = 1;
        const value_height: u16 = if (self.show_values) 1 else 0;
        const bar_area_height = if (area.height > label_height + value_height)
            area.height - label_height - value_height
        else
            0;

        if (bar_area_height == 0) return;

        const max_height = self.max_bar_height orelse bar_area_height;
        const effective_max_height = @min(max_height, bar_area_height);

        // Calculate bar width
        const bin_count: u16 = @intCast(@min(self.bins.len, area.width));
        const bar_width = if (bin_count > 0) area.width / bin_count else 0;
        if (bar_width == 0) return;

        for (self.bins, 0..) |bin, i| {
            const idx: u16 = @intCast(i);
            if (idx >= bin_count) break;

            const x_start = area.x + idx * bar_width;
            const bin_style = bin.style orelse self.bar_style;

            // Calculate bar height (clamp to prevent overflow)
            const bar_height = scaled(bin.count, effective_max_height, max);

            // Draw bar (from bottom to top)
            const bar_bottom = area.y + area.height - label_height - 1;
            var y: u16 = 0;
            while (y < bar_height) : (y += 1) {
                const bar_y = bar_bottom - y;
                var x: u16 = 0;
                while (x < bar_width and x_start + x < area.x + area.width) : (x += 1) {
                    buf.set(x_start + x, bar_y, .{ .char = self.bar_char, .style = bin_style });
                }
            }

            // Draw value on top of bar
            if (self.show_values and bar_height > 0) {
                var value_buf: [32]u8 = undefined;
                const value_str = std.fmt.bufPrint(&value_buf, "{d}", .{bin.count}) catch "";
                const value_y = bar_bottom - bar_height;
                const value_half: u16 = @intCast(@min(value_str.len / 2, bar_width / 2));
                const value_x = x_start + (bar_width / 2) - value_half;
                if (value_x + value_str.len <= area.x + area.width) {
                    buf.setString(value_x, value_y, value_str, self.label_style);
                }
            }

            // Draw label
            const label_y = area.y + area.height - 1;
            const label_half: u16 = @intCast(@min(bin.label.len / 2, bar_width / 2));
            const label_x = x_start + (bar_width / 2) - label_half;
            const truncated_label = if (bin.label.len > bar_width)
                bin.label[0..bar_width]
            else
                bin.label;
            if (label_x + truncated_label.len <= area.x + area.width) {
                buf.setString(label_x, label_y, truncated_label, self.label_style);
            }
        }
    }

    fn renderHorizontal(self: Histogram, buf: *Buffer, area: Rect) void {
        const max = maxCount(self.bins);
        if (max == 0) return;

        // Calculate max label width
        var max_label_len: u16 = 0;
        for (self.bins) |bin| {
            const len: u16 = @intCast(@min(bin.label.len, 20));
            if (len > max_label_len) max_label_len = len;
        }

        const label_width = max_label_len + 2; // +2 for spacing
        // Reserve room after the longest bar for " <count>" so the maximum bin keeps its value.
        const value_reserve: u16 = if (self.show_values) 1 + digitCount(max) else 0;
        const fixed_width = label_width +| value_reserve;
        const bar_area_width = if (area.width > fixed_width) area.width - fixed_width else 0;
        if (bar_area_width == 0) return;

        const max_width = self.max_bar_width orelse bar_area_width;
        const effective_max_width = @min(max_width, bar_area_width);

        // Calculate space per bin
        const bin_count: u16 = @intCast(@min(self.bins.len, area.height));
        const row_height: u16 = 1;

        for (self.bins, 0..) |bin, i| {
            const idx: u16 = @intCast(i);
            if (idx >= bin_count) break;

            const y = area.y + idx * row_height;
            if (y >= area.y + area.height) break;

            const bin_style = bin.style orelse self.bar_style;

            // Draw label
            const truncated_label = if (bin.label.len > max_label_len)
                bin.label[0..max_label_len]
            else
                bin.label;
            buf.setString(area.x, y, truncated_label, self.label_style);

            // Calculate bar width (clamp to prevent overflow)
            const bar_width = scaled(bin.count, effective_max_width, max);

            // Draw bar
            const bar_x_start = area.x + label_width;
            var x: u16 = 0;
            while (x < bar_width and bar_x_start + x < area.x + area.width) : (x += 1) {
                buf.set(bar_x_start + x, y, .{ .char = self.bar_char, .style = bin_style });
            }

            // Draw value at end of bar
            if (self.show_values and bar_width > 0) {
                var value_buf: [32]u8 = undefined;
                const value_str = std.fmt.bufPrint(&value_buf, " {d}", .{bin.count}) catch "";
                const value_x = bar_x_start + bar_width;
                if (value_x + value_str.len <= area.x + area.width) {
                    buf.setString(value_x, y, value_str, self.label_style);
                }
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const TBin = Histogram.Bin;

/// Assert that every buffer row equals the expected text, one codepoint per cell.
fn expectRows(buf: Buffer, rows: []const []const u8) !void {
    try testing.expectEqual(@as(usize, buf.height), rows.len);
    for (rows, 0..) |expected, y| {
        const line = buf.getLine(@intCast(y), 0, buf.width);
        defer buf.allocator.free(line);
        try testing.expectEqualStrings(expected, line);
    }
}

fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

test "histogram: init uses documented defaults" {
    const bins = [_]TBin{ .{ .label = "A", .count = 5 }, .{ .label = "B", .count = 10 } };
    const hist = Histogram.init(&bins);

    try testing.expectEqual(@as(usize, 2), hist.bins.len);
    try testing.expect(hist.block == null);
    try testing.expectEqual(Histogram.Orientation.vertical, hist.orientation);
    try testing.expectEqual(@as(u21, '█'), hist.bar_char);
    try testing.expect(hist.show_values);
    try testing.expectEqual(Style{ .fg = .{ .indexed = 2 } }, hist.bar_style);
    try testing.expectEqual(Style{}, hist.label_style);
    try testing.expectEqual(@as(?u16, null), hist.max_bar_height);
    try testing.expectEqual(@as(?u16, null), hist.max_bar_width);
}

test "histogram: with-builders replace only their own field" {
    const bins = [_]TBin{.{ .label = "A", .count = 1 }};
    const base = Histogram.init(&bins);
    const bar = Style{ .fg = .{ .indexed = 5 } };
    const label = Style{ .fg = .red };
    const hist = base.withBlock(Block{}).withBarStyle(bar).withLabelStyle(label)
        .withOrientation(.horizontal).withBarChar('▓').withShowValues(false)
        .withMaxBarHeight(4).withMaxBarWidth(7);

    try testing.expect(hist.block != null);
    try testing.expectEqual(bar, hist.bar_style);
    try testing.expectEqual(label, hist.label_style);
    try testing.expectEqual(Histogram.Orientation.horizontal, hist.orientation);
    try testing.expectEqual(@as(u21, '▓'), hist.bar_char);
    try testing.expect(!hist.show_values);
    try testing.expectEqual(@as(?u16, 4), hist.max_bar_height);
    try testing.expectEqual(@as(?u16, 7), hist.max_bar_width);
    try testing.expectEqual(base.bins.ptr, hist.bins.ptr);
}

test "histogram: maxCount returns the largest count, zero when empty" {
    const bins = [_]TBin{
        .{ .label = "A", .count = 5 },
        .{ .label = "B", .count = 12 },
        .{ .label = "C", .count = 7 },
    };
    try testing.expectEqual(@as(u64, 12), Histogram.maxCount(&bins));
    try testing.expectEqual(@as(u64, 0), Histogram.maxCount(&[_]TBin{}));
}

test "histogram: scaled floors, hits both ends and survives u64 extremes" {
    const top = std.math.maxInt(u64);
    try testing.expectEqual(@as(u16, 0), Histogram.scaled(0, 13, 10));
    try testing.expectEqual(@as(u16, 6), Histogram.scaled(5, 13, 10));
    try testing.expectEqual(@as(u16, 13), Histogram.scaled(10, 13, 10));
    try testing.expectEqual(@as(u16, 13), Histogram.scaled(top, 13, top));
    try testing.expectEqual(@as(u16, 1), Histogram.scaled(top / 2, 3, top));
}

test "histogram: digitCount counts decimal digits" {
    try testing.expectEqual(@as(u16, 1), Histogram.digitCount(0));
    try testing.expectEqual(@as(u16, 1), Histogram.digitCount(9));
    try testing.expectEqual(@as(u16, 2), Histogram.digitCount(10));
    try testing.expectEqual(@as(u16, 20), Histogram.digitCount(std.math.maxInt(u64)));
}

test "histogram: vertical bars, values and labels land on exact cells" {
    const bins = [_]TBin{
        .{ .label = "A", .count = 5 },
        .{ .label = "B", .count = 10 },
        .{ .label = "C", .count = 7 },
    };
    var buf = try Buffer.init(testing.allocator, 30, 15);
    defer buf.deinit();

    Histogram.init(&bins).render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 15 });

    try expectRows(buf, &.{
        (" " ** 14) ++ "10" ++ (" " ** 14),
        (" " ** 10) ++ ("█" ** 10) ++ (" " ** 10),
        (" " ** 10) ++ ("█" ** 10) ++ (" " ** 10),
        (" " ** 10) ++ ("█" ** 10) ++ (" " ** 10),
        (" " ** 10) ++ ("█" ** 10) ++ (" " ** 5) ++ "7" ++ (" " ** 4),
        (" " ** 10) ++ ("█" ** 20),
        (" " ** 10) ++ ("█" ** 20),
        (" " ** 5) ++ "5" ++ (" " ** 4) ++ ("█" ** 20),
        ("█" ** 30),
        ("█" ** 30),
        ("█" ** 30),
        ("█" ** 30),
        ("█" ** 30),
        ("█" ** 30),
        (" " ** 5) ++ "A" ++ (" " ** 9) ++ "B" ++ (" " ** 9) ++ "C" ++ (" " ** 4),
    });
}

test "histogram: bar, per-bin and label styles reach the right cells" {
    const bins = [_]TBin{
        .{ .label = "A", .count = 2 },
        .{ .label = "B", .count = 2, .style = .{ .fg = .red } },
    };
    const bar = Style{ .fg = .{ .indexed = 4 } };
    const label = Style{ .fg = .yellow, .bold = true };
    var buf = try Buffer.init(testing.allocator, 4, 4);
    defer buf.deinit();

    Histogram.init(&bins).withBarStyle(bar).withLabelStyle(label)
        .render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 4 });

    try testing.expectEqual(bar, buf.getStyle(0, 2));
    try testing.expectEqual(bar, buf.getStyle(1, 1));
    try testing.expectEqual(Style{ .fg = .red }, buf.getStyle(2, 2));
    try testing.expectEqual(Style{ .fg = .red }, buf.getStyle(3, 1));
    try testing.expectEqual(label, buf.getStyle(1, 0)); // value "2"
    try testing.expectEqual(label, buf.getStyle(1, 3)); // label "A"
    try testing.expectEqual(Style{}, buf.getStyle(0, 3)); // blank cell keeps default
}

test "histogram: custom bar char replaces the block glyph and values can be hidden" {
    const bins = [_]TBin{.{ .label = "A", .count = 5 }};
    var buf = try Buffer.init(testing.allocator, 3, 3);
    defer buf.deinit();

    Histogram.init(&bins).withBarChar('▓').withShowValues(false)
        .render(&buf, .{ .x = 0, .y = 0, .width = 3, .height = 3 });

    try expectRows(buf, &.{ "▓▓▓", "▓▓▓", " A " });
}

test "histogram: max_bar_height caps the tallest bar" {
    const bins = [_]TBin{ .{ .label = "A", .count = 10 }, .{ .label = "B", .count = 5 } };
    var buf = try Buffer.init(testing.allocator, 6, 8);
    defer buf.deinit();

    Histogram.init(&bins).withMaxBarHeight(4)
        .render(&buf, .{ .x = 0, .y = 0, .width = 6, .height = 8 });

    try expectRows(buf, &.{
        (" " ** 6),
        (" " ** 6),
        "10" ++ (" " ** 4),
        "███" ++ (" " ** 3),
        "███ 5 ",
        ("█" ** 6),
        ("█" ** 6),
        " A  B ",
    });
}

test "histogram: max_bar_height beyond the room is clamped to the room" {
    const bins = [_]TBin{.{ .label = "A", .count = 1 }};
    var buf = try Buffer.init(testing.allocator, 3, 4);
    defer buf.deinit();

    Histogram.init(&bins).withShowValues(false).withMaxBarHeight(100)
        .render(&buf, .{ .x = 0, .y = 0, .width = 3, .height = 4 });

    try expectRows(buf, &.{ ("█" ** 3), ("█" ** 3), ("█" ** 3), " A " });
}

test "histogram: long labels truncate to the bar width" {
    const bins = [_]TBin{ .{ .label = "Alpha", .count = 4 }, .{ .label = "Beta", .count = 2 } };
    var buf = try Buffer.init(testing.allocator, 4, 4);
    defer buf.deinit();

    Histogram.init(&bins).render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 4 });

    try expectRows(buf, &.{ " 4  ", "██ 2", "████", "AlBe" });
}

test "histogram: bins beyond the width are dropped" {
    const bins = [_]TBin{
        .{ .label = "A", .count = 1 },
        .{ .label = "B", .count = 1 },
        .{ .label = "C", .count = 1 },
    };
    var buf = try Buffer.init(testing.allocator, 2, 3);
    defer buf.deinit();

    Histogram.init(&bins).render(&buf, .{ .x = 0, .y = 0, .width = 2, .height = 3 });

    try expectRows(buf, &.{ "11", "██", "AB" });
}

test "histogram: zero-count bin among others draws its label but no bar or value" {
    const bins = [_]TBin{ .{ .label = "A", .count = 0 }, .{ .label = "B", .count = 4 } };
    var buf = try Buffer.init(testing.allocator, 4, 3);
    defer buf.deinit();

    Histogram.init(&bins).render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 3 });

    try expectRows(buf, &.{ "   4", "  ██", " A B" });
}

test "histogram: empty bins and all-zero counts leave the buffer untouched" {
    const empty = [_]TBin{};
    const zeros = [_]TBin{ .{ .label = "A", .count = 0 }, .{ .label = "B", .count = 0 } };
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };

    Histogram.init(&empty).render(&buf, area);
    try expectBlank(buf);
    Histogram.init(&zeros).render(&buf, area);
    try expectBlank(buf);
    Histogram.init(&zeros).withOrientation(.horizontal).render(&buf, area);
    try expectBlank(buf);
}

test "histogram: zero-size and too-small areas draw nothing" {
    const bins = [_]TBin{.{ .label = "A", .count = 5 }};
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    const hist = Histogram.init(&bins);

    hist.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    hist.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    hist.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 10 });
    // Height 2 holds only the label and value rows: no room for a bar.
    hist.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 2 });
    // Horizontal needs label (1) + spacing (2) + value reserve (2): width 5 leaves no bar.
    hist.withOrientation(.horizontal).render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 4 });
    try expectBlank(buf);
}

test "histogram: vertical render stays inside an offset area" {
    const bins = [_]TBin{.{ .label = "A", .count = 3 }};
    var buf = try Buffer.init(testing.allocator, 7, 6);
    defer buf.deinit();

    Histogram.init(&bins).withShowValues(false)
        .render(&buf, .{ .x = 2, .y = 1, .width = 3, .height = 3 });

    try expectRows(buf, &.{
        (" " ** 7),
        (" " ** 2) ++ ("█" ** 3) ++ (" " ** 2),
        (" " ** 2) ++ ("█" ** 3) ++ (" " ** 2),
        (" " ** 2) ++ " A " ++ (" " ** 2),
        (" " ** 7),
        (" " ** 7),
    });
}

test "histogram: block draws border and title and bars use the inner area" {
    const bins = [_]TBin{.{ .label = "A", .count = 5 }};
    const block = (Block{}).withTitle("T", .top_left);
    var buf = try Buffer.init(testing.allocator, 12, 6);
    defer buf.deinit();

    Histogram.init(&bins).withBlock(block)
        .render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 6 });

    try expectRows(buf, &.{
        "┌─T────────┐",
        "│" ++ (" " ** 5) ++ "5" ++ (" " ** 4) ++ "│",
        "│" ++ ("█" ** 10) ++ "│",
        "│" ++ ("█" ** 10) ++ "│",
        "│" ++ (" " ** 5) ++ "A" ++ (" " ** 4) ++ "│",
        "└──────────┘",
    });
}

test "histogram: horizontal bars, labels and trailing values land on exact cells" {
    const bins = [_]TBin{
        .{ .label = "First", .count = 5 },
        .{ .label = "Second", .count = 10 },
        .{ .label = "Third", .count = 7 },
    };
    var buf = try Buffer.init(testing.allocator, 40, 4);
    defer buf.deinit();

    Histogram.init(&bins).withOrientation(.horizontal)
        .render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 4 });

    try expectRows(buf, &.{
        "First" ++ (" " ** 3) ++ ("█" ** 14) ++ " 5" ++ (" " ** 16),
        "Second" ++ (" " ** 2) ++ ("█" ** 29) ++ " 10",
        "Third" ++ (" " ** 3) ++ ("█" ** 20) ++ " 7" ++ (" " ** 10),
        (" " ** 40),
    });
}

test "histogram: horizontal without values uses the whole bar area" {
    const bins = [_]TBin{ .{ .label = "A", .count = 2 }, .{ .label = "B", .count = 1 } };
    var buf = try Buffer.init(testing.allocator, 12, 2);
    defer buf.deinit();

    Histogram.init(&bins).withOrientation(.horizontal).withShowValues(false)
        .render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 2 });

    try expectRows(buf, &.{ "A  " ++ ("█" ** 9), "B  " ++ ("█" ** 4) ++ (" " ** 5) });
}

test "histogram: horizontal max_bar_width, per-bin style and bins beyond the height" {
    const bins = [_]TBin{
        .{ .label = "A", .count = 4, .style = .{ .fg = .red } },
        .{ .label = "B", .count = 2 },
        .{ .label = "C", .count = 1 },
    };
    var buf = try Buffer.init(testing.allocator, 20, 2);
    defer buf.deinit();

    Histogram.init(&bins).withOrientation(.horizontal).withMaxBarWidth(8)
        .render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 2 });

    try expectRows(buf, &.{
        "A  " ++ ("█" ** 8) ++ " 4" ++ (" " ** 7),
        "B  " ++ ("█" ** 4) ++ " 2" ++ (" " ** 11),
    });
    try testing.expectEqual(Style{ .fg = .red }, buf.getStyle(3, 0));
    try testing.expectEqual(Style{ .fg = .{ .indexed = 2 } }, buf.getStyle(3, 1));
}

test "histogram: horizontal labels longer than 20 truncate to 20" {
    const bins = [_]TBin{.{ .label = "abcdefghijklmnopqrstuvwxy", .count = 3 }};
    var buf = try Buffer.init(testing.allocator, 40, 1);
    defer buf.deinit();

    Histogram.init(&bins).withOrientation(.horizontal).withShowValues(false)
        .render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 1 });

    try expectRows(buf, &.{"abcdefghijklmnopqrst" ++ (" " ** 2) ++ ("█" ** 18)});
}

test "histogram: counts near maxInt(u64) scale without overflow (vertical)" {
    const top = std.math.maxInt(u64);
    const bins = [_]TBin{ .{ .label = "A", .count = top }, .{ .label = "B", .count = top / 2 } };
    var buf = try Buffer.init(testing.allocator, 4, 4);
    defer buf.deinit();

    Histogram.init(&bins).withShowValues(false)
        .render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 4 });

    try expectRows(buf, &.{ "██  ", "██  ", "████", " A B" });
}

test "histogram: counts near maxInt(u64) scale without overflow (horizontal)" {
    const top = std.math.maxInt(u64);
    const bins = [_]TBin{ .{ .label = "A", .count = top }, .{ .label = "B", .count = top / 2 } };
    var buf = try Buffer.init(testing.allocator, 12, 2);
    defer buf.deinit();

    Histogram.init(&bins).withOrientation(.horizontal).withShowValues(false)
        .render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 2 });

    try expectRows(buf, &.{ "A  " ++ ("█" ** 9), "B  " ++ ("█" ** 4) ++ (" " ** 5) });
}

test "histogram: render over many seeded shapes never writes outside the area" {
    var prng = std.Random.DefaultPrng.init(0x4157);
    const random = prng.random();
    var counts: [6]TBin = undefined;
    for (0..64) |_| {
        for (&counts, 0..) |*bin, i| {
            bin.* = .{ .label = "lbl", .count = random.uintLessThan(u64, 40) * (i + 1) };
        }
        const area = Rect{
            .x = random.uintLessThan(u16, 4),
            .y = random.uintLessThan(u16, 4),
            .width = random.uintLessThan(u16, 14),
            .height = random.uintLessThan(u16, 10),
        };
        var buf = try Buffer.init(testing.allocator, 20, 16);
        defer buf.deinit();
        const orientation: Histogram.Orientation = if (random.boolean()) .vertical else .horizontal;

        Histogram.init(counts[0..random.uintAtMost(usize, 6)]).withOrientation(orientation)
            .withShowValues(random.boolean()).render(&buf, area);

        buf.check_invariants();
        for (0..buf.height) |y| {
            for (0..buf.width) |x| {
                const inside = x >= area.x and x < area.x + area.width and
                    y >= area.y and y < area.y + area.height;
                if (!inside) try testing.expect(buf.getConst(@intCast(x), @intCast(y)).?.eql(.{}));
            }
        }
    }
}
