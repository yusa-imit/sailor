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
//!     .withBlock((Block{}).withBorders(.all).withTitle("Sales", .top_left))
//!     .withBarStyle(.{ .fg = .{ .indexed = 2 } })
//!     .withBarWidth(5)
//!     .withBarGap(2);
//!
//! chart.render(&buffer, area);
//! ```

const std = @import("std");
const assert = std.debug.assert;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
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

    /// Render the bar chart. Layout inside the (block-reduced) area: row 0 shows each bar's value,
    /// the middle rows hold the bars growing upward, the last row shows the labels. Areas shorter
    /// than 3 rows draw nothing but the block. A value that does not fit inside the area is hidden;
    /// bars and labels are clipped at the right edge.
    pub fn render(self: BarChart, buf: *Buffer, area: Rect) void {
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (inner.width == 0 or inner.height < 3 or self.bars.len == 0) return;

        const max = self.max_value orelse calcMaxValue(self.bars);
        if (max == 0) return;
        assert(inner.height >= 3);

        // Sizes are usize and the sums saturate: huge bar counts or widths cannot wrap a u16.
        const unit: usize = self.bar_width +| self.bar_gap;
        const total_width_needed = self.bars.len *| unit;
        const x_offset: usize = if (total_width_needed < inner.width)
            (inner.width - total_width_needed) / 2
        else
            0;
        const right: usize = @as(usize, inner.x) + inner.width;

        for (self.bars, 0..) |bar, i| {
            const bar_x_wide = @as(usize, inner.x) + x_offset + i *| unit;
            if (bar_x_wide >= right) break; // This and every later bar is out of bounds.
            const bar_x = std.math.cast(u16, bar_x_wide) orelse break;
            self.renderBar(buf, inner, bar, bar_x, max);
        }
    }

    fn renderBar(self: BarChart, buf: *Buffer, inner: Rect, bar: Bar, bar_x: u16, max: u64) void {
        assert(inner.height >= 3);
        assert(max > 0);
        const bar_height: u16 = inner.height - 2;
        const right: u16 = inner.x +| inner.width;
        const bar_w: u16 = std.math.lossyCast(u16, self.bar_width);
        assert(bar_x < right);

        // u128 holds value * bar_height for any u64 value, so the product cannot overflow.
        const scaled: u16 = @intCast(@min(@as(u128, bar.value) * bar_height / max, bar_height));
        const bar_s = if (bar.style.fg != null or bar.style.bg != null)
            bar.style
        else
            self.bar_style;

        // Bar cells fill rows (inner.y + 1 + bar_height - scaled) .. (inner.y + bar_height].
        var y: u16 = inner.y +| 1 +| (bar_height - scaled);
        const y_end: u16 = inner.y +| 1 +| bar_height;
        while (y < y_end) : (y += 1) {
            var dx: u16 = 0;
            while (dx < bar_w and bar_x +| dx < right) : (dx += 1) {
                buf.set(bar_x + dx, y, .{ .char = '█', .style = bar_s });
            }
        }

        // u64 has at most 20 decimal digits, so the format below cannot run out of space.
        var digits: [20]u8 = undefined;
        const value_str = std.fmt.bufPrint(&digits, "{d}", .{bar.value}) catch return;
        const value_x: u16 = bar_x +| (bar_w / 2);
        if (@as(usize, value_x) + value_str.len <= right) {
            buf.setString(value_x, inner.y, value_str, self.value_style);
        }

        // Truncate the label by terminal cells to the bar width and the room left on the right.
        const label_cells: usize = @min(bar_w, right - bar_x);
        const label_len = UnicodeWidth.truncate(bar.label, label_cells);
        const label_y = inner.y +| (inner.height - 1);
        buf.setString(bar_x, label_y, bar.label[0..label_len], self.label_style);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Assert every buffer row equals the expected text, one codepoint per cell.
fn expectRows(buf: Buffer, rows: []const []const u8) !void {
    try testing.expectEqual(@as(usize, buf.height), rows.len);
    for (rows, 0..) |row, y| {
        var view = try std.unicode.Utf8View.init(row);
        var it = view.iterator();
        var x: u16 = 0;
        while (it.nextCodepoint()) |cp| : (x += 1) {
            try testing.expectEqual(cp, buf.getChar(x, @intCast(y)));
        }
        try testing.expectEqual(buf.width, x);
    }
}

/// Count '█' cells in column x.
fn countBarsInColumn(buf: Buffer, x: u16) usize {
    var n: usize = 0;
    for (0..buf.height) |y| {
        if (buf.getChar(x, @intCast(y)) == '█') n += 1;
    }
    return n;
}

fn fullArea(buf: Buffer) Rect {
    return .{ .x = 0, .y = 0, .width = buf.width, .height = buf.height };
}

test "barchart: init keeps the bars and defaults" {
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
        .{ .label = "B", .value = 20 },
    };
    const chart = BarChart.init(&bars);
    try testing.expectEqual(@as(usize, 2), chart.bars.len);
    try testing.expectEqualStrings("A", chart.bars[0].label);
    try testing.expectEqual(@as(u64, 20), chart.bars[1].value);
    try testing.expectEqual(@as(?u64, null), chart.max_value);
    try testing.expectEqual(@as(usize, 3), chart.bar_width);
    try testing.expectEqual(@as(usize, 1), chart.bar_gap);
    try testing.expect(chart.block == null);
}

test "barchart: builders set exactly their own field" {
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 10 }};
    const bold_blue = Style{ .fg = Color.blue, .bold = true };
    const chart = BarChart.init(&bars)
        .withMaxValue(100)
        .withBarWidth(5)
        .withBarGap(2)
        .withBarStyle(bold_blue)
        .withValueStyle(.{ .fg = Color.green })
        .withLabelStyle(.{ .fg = Color.yellow })
        .withBlock((Block{}).withTitle("Chart", .top_left));
    try testing.expectEqual(@as(?u64, 100), chart.max_value);
    try testing.expectEqual(@as(usize, 5), chart.bar_width);
    try testing.expectEqual(@as(usize, 2), chart.bar_gap);
    try testing.expectEqual(bold_blue, chart.bar_style);
    try testing.expectEqual(Style{ .fg = Color.green }, chart.value_style);
    try testing.expectEqual(Style{ .fg = Color.yellow }, chart.label_style);
    try testing.expectEqualStrings("Chart", chart.block.?.title.?);
    // The source chart is a value: builders do not mutate it.
    try testing.expectEqual(@as(?u64, null), BarChart.init(&bars).max_value);
}

test "barchart: calcMaxValue is 0 for no bars and the maximum otherwise" {
    const none: []const BarChart.Bar = &.{};
    try testing.expectEqual(@as(u64, 0), BarChart.calcMaxValue(none));
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10 },
        .{ .label = "B", .value = 25 },
        .{ .label = "C", .value = 15 },
    };
    try testing.expectEqual(@as(u64, 25), BarChart.calcMaxValue(&bars));
}

test "barchart: empty chart leaves the buffer blank" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();
    const none: []const BarChart.Bar = &.{};
    BarChart.init(none).render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "          ", "          ", "          " });
}

test "barchart: empty chart still draws its block" {
    var buf = try Buffer.init(testing.allocator, 6, 3);
    defer buf.deinit();
    const none: []const BarChart.Bar = &.{};
    BarChart.init(none).withBlock(Block{}).render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "┌────┐", "│    │", "└────┘" });
}

test "barchart: single full bar is centered with value above and label below" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "    50    ",
        "   ███    ",
        "   ███    ",
        "   ███    ",
        "   ███    ",
        "   ███    ",
        "   ███    ",
        "   ███    ",
        "   ███    ",
        "   A      ",
    });
}

test "barchart: three bars scale to the maximum with floored heights" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 30 }, // 30 * 8 / 50 = 4
        .{ .label = "B", .value = 50 }, // 8
        .{ .label = "C", .value = 20 }, // 20 * 8 / 50 = 3
    };
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "     30  50  20     ",
        "        ███         ",
        "        ███         ",
        "        ███         ",
        "        ███         ",
        "    ███ ███         ",
        "    ███ ███ ███     ",
        "    ███ ███ ███     ",
        "    ███ ███ ███     ",
        "    A   B   C       ",
    });
}

test "barchart: block border shrinks the drawing area" {
    var buf = try Buffer.init(testing.allocator, 15, 10);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    BarChart.init(&bars).withBlock(Block{}).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "┌─────────────┐",
        "│     50      │",
        "│    ███      │",
        "│    ███      │",
        "│    ███      │",
        "│    ███      │",
        "│    ███      │",
        "│    ███      │",
        "│    A        │",
        "└─────────────┘",
    });
}

test "barchart: custom bar width widens the bar and recenters value and label" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "ABCDEFG", .value = 50 }};
    BarChart.init(&bars).withBarWidth(5).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "         50         ",
        "       █████        ",
        "       █████        ",
        "       █████        ",
        "       █████        ",
        "       █████        ",
        "       █████        ",
        "       █████        ",
        "       █████        ",
        "       ABCDE        ",
    });
}

test "barchart: bar gap separates two bars into two column groups" {
    var buf = try Buffer.init(testing.allocator, 30, 4);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 50 },
    };
    // unit = 3 + 3 = 6, total = 12, offset = 9: bars at x = 9..11 and 15..17.
    BarChart.init(&bars).withBarGap(3).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "          50    50            ",
        "         ███   ███            ",
        "         ███   ███            ",
        "         A     B              ",
    });
}

test "barchart: styles reach bar, value and label cells and nothing else" {
    var buf = try Buffer.init(testing.allocator, 10, 4);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 7 }};
    const bar_s = Style{ .fg = Color.blue, .bold = true };
    const val_s = Style{ .fg = Color.green };
    const lab_s = Style{ .fg = Color.yellow };
    BarChart.init(&bars).withBarStyle(bar_s).withValueStyle(val_s).withLabelStyle(lab_s)
        .render(&buf, fullArea(buf));
    // Bar at x = 3..5 rows 1..2, value "7" at (4, 0), label "A" at (3, 3).
    try testing.expectEqual(val_s, buf.getStyle(4, 0));
    try testing.expectEqual(@as(u21, '7'), buf.getChar(4, 0));
    for (3..6) |x| {
        try testing.expectEqual(bar_s, buf.getStyle(@intCast(x), 1));
        try testing.expectEqual(bar_s, buf.getStyle(@intCast(x), 2));
    }
    try testing.expectEqual(lab_s, buf.getStyle(3, 3));
    try testing.expectEqual(Style{}, buf.getStyle(0, 1));
    try testing.expectEqual(Style{}, buf.getStyle(6, 2));
    try testing.expectEqual(Style{}, buf.getStyle(5, 3));
}

test "barchart: per-bar style overrides the chart bar style, unstyled bars inherit it" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 10, .style = .{ .fg = Color.red } },
        .{ .label = "B", .value = 10, .style = .{ .bg = Color.green } },
        .{ .label = "C", .value = 10 },
    };
    const base = Style{ .fg = Color.blue };
    BarChart.init(&bars).withBarStyle(base).render(&buf, fullArea(buf));
    // unit = 4, total = 12, offset = 4: bars start at x = 4, 8, 12 on the single bar row.
    try testing.expectEqual(Style{ .fg = Color.red }, buf.getStyle(4, 1));
    try testing.expectEqual(Style{ .fg = Color.red }, buf.getStyle(6, 1));
    try testing.expectEqual(Style{ .bg = Color.green }, buf.getStyle(8, 1));
    try testing.expectEqual(base, buf.getStyle(12, 1));
    try testing.expectEqual(@as(u21, '█'), buf.getChar(12, 1));
}

test "barchart: explicit max value scales bars and clamps larger values" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 50 }, // 50 * 8 / 100 = 4
        .{ .label = "B", .value = 500 }, // clamped to the full 8
    };
    BarChart.init(&bars).withMaxValue(100).render(&buf, fullArea(buf));
    // unit 4, total 8, offset 6: bars at x = 6 and 10.
    try testing.expectEqual(@as(usize, 4), countBarsInColumn(buf, 6));
    try testing.expectEqual(@as(usize, 8), countBarsInColumn(buf, 10));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(6, 4));
    try testing.expectEqual(@as(u21, '█'), buf.getChar(6, 5));
    try testing.expectEqual(@as(u21, '█'), buf.getChar(6, 8));
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(6, 9)); // label row holds no bar
}

test "barchart: bar heights are proportional to values" {
    var buf = try Buffer.init(testing.allocator, 20, 12);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 100 },
        .{ .label = "B", .value = 50 },
    };
    BarChart.init(&bars).render(&buf, fullArea(buf));
    // unit = 4, total = 8, offset = 6: bars at x = 6 and 10; bar_height = 10.
    try testing.expectEqual(@as(usize, 10), countBarsInColumn(buf, 6));
    try testing.expectEqual(@as(usize, 5), countBarsInColumn(buf, 10));
}

test "barchart: zero value bar draws no cells but keeps value and label" {
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "Z", .value = 0 },
        .{ .label = "Y", .value = 9 },
    };
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "       0   9        ",
        "          ███       ",
        "          ███       ",
        "      Z   Y         ",
    });
}

test "barchart: bar_width zero draws no bar cells" {
    var buf = try Buffer.init(testing.allocator, 10, 4);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    BarChart.init(&bars).withBarWidth(0).render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "    50    ", "          ", "          ", "          " });
}

test "barchart: all-zero maximum draws nothing" {
    var buf = try Buffer.init(testing.allocator, 10, 4);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 0 }};
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{ "          ", "          ", "          ", "          " });
}

test "barchart: zero-sized areas write nothing" {
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    const chart = BarChart.init(&bars);
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    chart.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 10 });
    for (buf.cells) |cell| try testing.expect(cell.eql(Cell{}));
}

test "barchart: height below 3 draws nothing and height 3 is the minimum" {
    var small = try Buffer.init(testing.allocator, 10, 2);
    defer small.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    const chart = BarChart.init(&bars);
    chart.render(&small, fullArea(small));
    try expectRows(small, &.{ "          ", "          " });

    var min = try Buffer.init(testing.allocator, 10, 3);
    defer min.deinit();
    chart.render(&min, fullArea(min));
    try expectRows(min, &.{ "    50    ", "   ███    ", "   A      " });
}

test "barchart: block that leaves under 3 inner rows draws only the border" {
    var buf = try Buffer.init(testing.allocator, 6, 4);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    BarChart.init(&bars).withBlock(Block{}).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "┌────┐",
        "│    │",
        "│    │",
        "└────┘",
    });
}

test "barchart: long label is cut to the bar width" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "VeryLongLabel", .value = 50 }};
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "         50         ",
        "        ███         ",
        "        Ver         ",
    });
}

test "barchart: multibyte label is cut by cells, not bytes" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    // Each 'é' is two bytes; a byte cut at 3 would keep only one of them.
    const bars = [_]BarChart.Bar{.{ .label = "éééé", .value = 50 }};
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        "         50         ",
        "        ███         ",
        "        ééé         ",
    });
}

test "barchart: wide label never splits a double-width character" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "日本語", .value = 50 }};
    BarChart.init(&bars).render(&buf, fullArea(buf));
    // Width 3 fits one 2-cell character; the third cell stays blank.
    try expectRows(buf, &.{
        "         50         ",
        "        ███         ",
        "        日           ",
    });
}

test "barchart: bar cut by the right edge is clipped, its label clipped, its value hidden" {
    var buf = try Buffer.init(testing.allocator, 6, 5);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "AAA", .value = 10 },
        .{ .label = "BBB", .value = 10 },
    };
    // total 8 > width 6, so no centering: bar A at x = 0..2, bar B at x = 4..5 (clipped).
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        " 10   ",
        "███ ██",
        "███ ██",
        "███ ██",
        "AAA BB",
    });
}

test "barchart: bars starting beyond the area are skipped" {
    var buf = try Buffer.init(testing.allocator, 8, 4);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = 5 },
        .{ .label = "B", .value = 5 },
        .{ .label = "C", .value = 5 },
    };
    // unit 4: bars at x = 0, 4 and 8; the third starts at the right edge and is dropped.
    BarChart.init(&bars).render(&buf, fullArea(buf));
    try expectRows(buf, &.{
        " 5   5  ",
        "███ ███ ",
        "███ ███ ",
        "A   B   ",
    });
}

test "barchart: area offset in a larger buffer keeps drawing inside the area" {
    var buf = try Buffer.init(testing.allocator, 14, 7);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    // Area x=2..11, y=1..5 (height 5): offset = (10 - 4) / 2 = 3, so the bar starts at x = 5.
    BarChart.init(&bars).render(&buf, .{ .x = 2, .y = 1, .width = 10, .height = 5 });
    try expectRows(buf, &.{
        "              ",
        "      50      ",
        "     ███      ",
        "     ███      ",
        "     ███      ",
        "     A        ",
        "              ",
    });
}

test "barchart: u64 values near the maximum do not overflow the scaling" {
    var buf = try Buffer.init(testing.allocator, 80, 10);
    defer buf.deinit();
    const big = std.math.maxInt(u64);
    const bars = [_]BarChart.Bar{
        .{ .label = "A", .value = big },
        .{ .label = "B", .value = big / 2 },
    };
    // Gap 30 keeps the 20-digit value of A clear of B's value: bars at x = 7 and 40.
    BarChart.init(&bars).withBarGap(30).render(&buf, fullArea(buf));
    try testing.expectEqual(@as(usize, 8), countBarsInColumn(buf, 7));
    try testing.expectEqual(@as(usize, 3), countBarsInColumn(buf, 40));
    var view = try std.unicode.Utf8View.init("18446744073709551615");
    var it = view.iterator();
    var x: u16 = 8;
    while (it.nextCodepoint()) |cp| : (x += 1) {
        try testing.expectEqual(cp, buf.getChar(x, 0));
    }
}

test "barchart: bar count beyond u16 positions does not wrap or panic" {
    const count = 16500;
    const bars = try testing.allocator.alloc(BarChart.Bar, count);
    defer testing.allocator.free(bars);
    @memset(bars, .{ .label = "x", .value = 1 });

    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();
    // The area is the widest possible; bar 16384 would sit at x = 65536.
    BarChart.init(bars).render(&buf, .{ .x = 0, .y = 0, .width = 65535, .height = 3 });
    try expectRows(buf, &.{ " 1   1   1", "███ ███ ██", "x   x   x " });
}

test "barchart: area whose extent exceeds u16 is clipped to the buffer" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();
    const bars = [_]BarChart.Bar{.{ .label = "A", .value = 50 }};
    // x + width = 65600 does not fit in u16; the bar lies far outside the 10-wide buffer.
    BarChart.init(&bars).render(&buf, .{ .x = 65500, .y = 0, .width = 100, .height = 3 });
    try expectRows(buf, &.{ "          ", "          ", "          " });
}

test "barchart: rendered bar height matches floor(value * rows / max) over random charts" {
    var prng = std.Random.DefaultPrng.init(0xBA2C_4A27);
    const rng = prng.random();
    const alloc = testing.allocator;
    for (0..200) |_| {
        const height: u16 = rng.intRangeAtMost(u16, 3, 14);
        const n = rng.intRangeAtMost(usize, 1, 5);
        var bars: [5]BarChart.Bar = undefined;
        var max: u64 = 0;
        for (bars[0..n]) |*bar| {
            bar.* = .{ .label = "L", .value = rng.intRangeAtMost(u64, 0, 1000) };
            max = @max(max, bar.value);
        }
        if (max == 0) continue;

        var buf = try Buffer.init(alloc, 40, height);
        defer buf.deinit();
        BarChart.init(bars[0..n]).render(&buf, fullArea(buf));

        const rows: u64 = height - 2;
        const offset: u16 = @intCast((40 - n * 4) / 2);
        for (bars[0..n], 0..) |bar, i| {
            const h: u64 = countBarsInColumn(buf, offset + @as(u16, @intCast(i)) * 4);
            // h is floor(value * rows / max) iff h * max <= value * rows < (h + 1) * max.
            try testing.expect(h * max <= bar.value * rows);
            try testing.expect(bar.value * rows < (h + 1) * max);
        }
    }
}
