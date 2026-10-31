//! PieChart widget — circular percentage display with legend
//!
//! Example usage:
//!
//! ```zig
//! const slices = [_]PieChart.Slice{
//!     .{ .label = "CPU", .value = 35, .style = .{ .fg = .{ .indexed = 1 } } },
//!     .{ .label = "Memory", .value = 25, .style = .{ .fg = .{ .indexed = 2 } } },
//!     .{ .label = "Disk", .value = 40, .style = .{ .fg = .{ .indexed = 3 } } },
//! };
//!
//! const chart = PieChart.init(&slices)
//!     .withBlock((Block{}).withBorders(.all).withTitle("Resources"))
//!     .withLegendPosition(.right);
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
const unicode_mod = @import("../../unicode.zig");
const UnicodeWidth = unicode_mod.UnicodeWidth;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// PieChart widget — circular percentage display with legend
pub const PieChart = struct {
    pub const Slice = struct {
        label: []const u8,
        value: u64,
        style: Style = .{},
    };

    pub const LegendPosition = enum {
        none,
        right,
        bottom,
    };

    slices: []const Slice,
    block: ?Block = null,
    legend_position: LegendPosition = .right,
    show_percentages: bool = true,

    /// Create a pie chart with slices
    pub fn init(slices: []const Slice) PieChart {
        return .{ .slices = slices };
    }

    /// Set the block (border) for this pie chart
    pub fn withBlock(self: PieChart, new_block: Block) PieChart {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set legend position (default: right)
    pub fn withLegendPosition(self: PieChart, pos: LegendPosition) PieChart {
        var result = self;
        result.legend_position = pos;
        return result;
    }

    /// Show percentages in legend (default: true)
    pub fn withPercentages(self: PieChart, show: bool) PieChart {
        var result = self;
        result.show_percentages = show;
        return result;
    }

    /// Narrowest legend column that still shows a marker and a few characters.
    const min_legend_width: u16 = 5;

    /// Longest label (bytes) copied into a legend entry; longer labels are clipped.
    const max_label_bytes: usize = 96;

    /// Calculate total value of all slices. Wide so that u64 values cannot overflow the sum.
    fn calcTotal(slices: []const Slice) u128 {
        var total: u128 = 0;
        for (slices) |slice| {
            total += slice.value;
        }
        return total;
    }

    /// Longest prefix of `text` that fits `max_bytes` bytes and ends on a codepoint boundary.
    fn clipUtf8(text: []const u8, max_bytes: usize) []const u8 {
        if (text.len <= max_bytes) return text;
        var end = max_bytes;
        while (end > 0 and (text[end] & 0xC0) == 0x80) end -= 1;
        std.debug.assert(end <= max_bytes);
        return text[0..end];
    }

    /// Longest prefix of `text` that occupies at most `max_cells` terminal columns.
    fn clipCells(text: []const u8, max_cells: usize) []const u8 {
        var cells: usize = 0;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            if (i + len > text.len) break;
            const cp = if (len == 1) @as(u21, text[i]) else std.unicode.utf8Decode(
                text[i .. i + len],
            ) catch @as(u21, text[i]);
            const width = UnicodeWidth.charWidth(cp);
            if (cells + width > max_cells) break;
            cells += width;
            i += len;
        }
        return text[0..i];
    }

    /// Render the pie chart
    pub fn render(self: PieChart, buf: *Buffer, area: Rect) void {
        // Render block border first
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (inner.width == 0 or inner.height == 0 or self.slices.len == 0) return;

        const total = calcTotal(self.slices);
        if (total == 0) return;

        // Calculate chart and legend areas
        const chart_area, const legend_area = self.splitAreas(inner);

        // Render pie chart using circle drawing
        self.renderPie(buf, chart_area, total);

        // Render legend if not .none
        if (self.legend_position != .none) {
            self.renderLegend(buf, legend_area, total);
        }
    }

    /// Split area into chart and legend
    fn splitAreas(self: PieChart, area: Rect) struct { Rect, Rect } {
        return switch (self.legend_position) {
            .none => .{ area, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 } },
            .right => blk: {
                // Reserve ~30% width for legend on right
                const legend_width = @min(area.width / 3, 20);
                if (legend_width < min_legend_width) {
                    break :blk .{ area, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 } };
                }
                const chart_area = Rect{
                    .x = area.x,
                    .y = area.y,
                    .width = area.width - legend_width,
                    .height = area.height,
                };
                const legend_area = Rect{
                    .x = area.x + chart_area.width,
                    .y = area.y,
                    .width = legend_width,
                    .height = area.height,
                };
                break :blk .{ chart_area, legend_area };
            },
            .bottom => blk: {
                // Reserve rows for legend at bottom
                const legend_height = @min(area.height / 3, self.slices.len + 1);
                if (area.height < legend_height + 2) {
                    break :blk .{ area, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 } };
                }
                const chart_area = Rect{
                    .x = area.x,
                    .y = area.y,
                    .width = area.width,
                    .height = area.height - legend_height,
                };
                const legend_area = Rect{
                    .x = area.x,
                    .y = area.y + chart_area.height,
                    .width = area.width,
                    .height = legend_height,
                };
                break :blk .{ chart_area, legend_area };
            },
        };
    }

    /// Render the pie chart circle
    fn renderPie(self: PieChart, buf: *Buffer, area: Rect, total: u128) void {
        if (area.width < 3 or area.height < 3) return;

        // Calculate circle center and radius
        const center_x = area.x + area.width / 2;
        const center_y = area.y + area.height / 2;
        const radius = @min(area.width / 2, area.height / 2);

        // Draw circle using characters
        var angle: f64 = 0.0; // Start at top (0 degrees)

        for (self.slices) |slice| {
            const share = @as(f64, @floatFromInt(slice.value)) / @as(f64, @floatFromInt(total));
            const slice_angle = share * 360.0;
            const center = [2]u16{ center_x, center_y };
            const span = [2]f64{ angle, angle + slice_angle };
            self.renderSlice(buf, area, center, radius, span, slice.style);
            angle += slice_angle;
        }
    }

    /// Render a single pie slice as radial rays. Cells outside `area` are never written.
    fn renderSlice(
        self: PieChart,
        buf: *Buffer,
        area: Rect,
        center: [2]u16,
        radius: u16,
        angles: [2]f64,
        slice_style: Style,
    ) void {
        _ = self;
        std.debug.assert(angles[0] <= angles[1]);
        var a = angles[0];
        while (a < angles[1]) : (a += 5.0) {
            const rad = a * std.math.pi / 180.0;
            var r: u16 = 0;
            while (r < radius) : (r += 1) {
                const dx: i32 = @intFromFloat(@as(f64, @floatFromInt(r)) * @sin(rad));
                const dy: i32 = @intFromFloat(@as(f64, @floatFromInt(r)) * @cos(rad));
                const abs_x = @as(i32, center[0]) + dx;
                const abs_y = @as(i32, center[1]) - dy;

                if (abs_x < area.x or abs_y < area.y) continue;
                if (abs_x >= @as(i32, area.x) + area.width) continue;
                if (abs_y >= @as(i32, area.y) + area.height) continue;
                buf.set(@intCast(abs_x), @intCast(abs_y), .{ .char = '█', .style = slice_style });
            }
        }
    }

    /// Render the legend
    fn renderLegend(self: PieChart, buf: *Buffer, area: Rect, total: u128) void {
        if (area.width < min_legend_width or area.height < 1) return;

        var y = area.y;
        for (self.slices) |slice| {
            if (y >= area.y + area.height) break;

            // Entry: "■ Label: 35 (25.0%)"; the label is clipped so the entry always fits.
            var legend_buf: [192]u8 = undefined;
            const percentage = @as(f64, @floatFromInt(slice.value)) * 100.0 /
                @as(f64, @floatFromInt(total));
            const label = clipUtf8(slice.label, max_label_bytes);

            // The entry is at most 96 + 60 bytes, so the 192-byte buffer never overflows; the
            // empty fallback only keeps the error path total.
            const legend_text = if (self.show_percentages)
                std.fmt.bufPrint(&legend_buf, "■ {s}: {d} ({d:.1}%)", .{
                    label, slice.value, percentage,
                }) catch legend_buf[0..0]
            else
                std.fmt.bufPrint(&legend_buf, "■ {s}: {d}", .{ label, slice.value }) catch
                    legend_buf[0..0];

            buf.setString(area.x, y, clipCells(legend_text, area.width), slice.style);
            y += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const TSlice = PieChart.Slice;

fn expectLine(buf: Buffer, y: u16, x0: u16, x1: u16, expected: []const u8) !void {
    const line = buf.getLine(y, x0, x1);
    defer buf.allocator.free(line);
    try testing.expectEqualStrings(expected, line);
}

fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

fn inkedCount(buf: Buffer) usize {
    var n: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == '█') n += 1;
    }
    return n;
}

test "piechart: init uses documented defaults" {
    const slices = [_]TSlice{ .{ .label = "A", .value = 50 }, .{ .label = "B", .value = 30 } };
    const chart = PieChart.init(&slices);

    try testing.expectEqual(@as(usize, 2), chart.slices.len);
    try testing.expectEqual(PieChart.LegendPosition.right, chart.legend_position);
    try testing.expect(chart.show_percentages);
    try testing.expect(chart.block == null);
}

test "piechart: with-builders replace only their own field" {
    const slices = [_]TSlice{.{ .label = "A", .value = 50 }};
    const base = PieChart.init(&slices);
    const chart = base.withBlock(Block{}).withLegendPosition(.bottom).withPercentages(false);

    try testing.expect(chart.block != null);
    try testing.expectEqual(PieChart.LegendPosition.bottom, chart.legend_position);
    try testing.expect(!chart.show_percentages);
    try testing.expectEqual(base.slices.ptr, chart.slices.ptr);
}

test "piechart: calcTotal sums values and does not overflow near maxInt(u64)" {
    const top = std.math.maxInt(u64);
    const slices = [_]TSlice{
        .{ .label = "A", .value = 50 },
        .{ .label = "B", .value = 30 },
        .{ .label = "C", .value = 20 },
    };
    const zeros = [_]TSlice{ .{ .label = "A", .value = 0 }, .{ .label = "B", .value = 0 } };
    const huge = [_]TSlice{ .{ .label = "A", .value = top }, .{ .label = "B", .value = top } };

    try testing.expectEqual(@as(u128, 100), PieChart.calcTotal(&slices));
    try testing.expectEqual(@as(u128, 0), PieChart.calcTotal(&zeros));
    try testing.expectEqual(@as(u128, top) * 2, PieChart.calcTotal(&huge));
    try testing.expectEqual(@as(u128, 0), PieChart.calcTotal(&[_]TSlice{}));
}

test "piechart: clipUtf8 never splits a codepoint" {
    try testing.expectEqualStrings("abc", PieChart.clipUtf8("abc", 3));
    try testing.expectEqualStrings("ab", PieChart.clipUtf8("abcd", 2));
    try testing.expectEqualStrings("é", PieChart.clipUtf8("éé", 3)); // byte 3 is mid-"é"
    try testing.expectEqualStrings("", PieChart.clipUtf8("é", 1));
    try testing.expectEqualStrings("", PieChart.clipUtf8("abc", 0));
}

test "piechart: clipCells counts columns, not bytes" {
    try testing.expectEqualStrings("■ ab", PieChart.clipCells("■ abcd", 4));
    // The third wide character would reach column 6.
    try testing.expectEqualStrings("日本", PieChart.clipCells("日本語", 5));
    try testing.expectEqualStrings("日", PieChart.clipCells("日本語", 3));
    try testing.expectEqualStrings("", PieChart.clipCells("abc", 0));
    try testing.expectEqualStrings("abc", PieChart.clipCells("abc", 10));
}

test "piechart: empty area, no slices and zero total draw nothing" {
    const some = [_]TSlice{.{ .label = "A", .value = 50 }};
    const none = [_]TSlice{};
    const zeros = [_]TSlice{ .{ .label = "A", .value = 0 }, .{ .label = "B", .value = 0 } };
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    PieChart.init(&some).render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 10 });
    PieChart.init(&some).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    PieChart.init(&none).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    PieChart.init(&zeros).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    try expectBlank(buf);
}

test "piechart: right legend lists clipped entries in the right third" {
    const slices = [_]TSlice{
        .{ .label = "CPU", .value = 35, .style = .{ .fg = .{ .indexed = 1 } } },
        .{ .label = "Mem", .value = 25, .style = .{ .fg = .{ .indexed = 2 } } },
    };
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();

    PieChart.init(&slices).render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 10 });

    // legend_width = min(40 / 3, 20) = 13 -> legend starts at x = 27; entries clip to 13 cells.
    try expectLine(buf, 0, 27, 40, "■ CPU: 35 (58");
    try expectLine(buf, 1, 27, 40, "■ Mem: 25 (41");
    try expectLine(buf, 2, 27, 40, " " ** 13);
    try testing.expectEqual(Style{ .fg = .{ .indexed = 1 } }, buf.getStyle(27, 0));
    try testing.expectEqual(Style{ .fg = .{ .indexed = 2 } }, buf.getStyle(27, 1));
}

test "piechart: wide legend shows the full entry with one-decimal percentage" {
    const slices = [_]TSlice{ .{ .label = "CPU", .value = 35 }, .{ .label = "Mem", .value = 25 } };
    var buf = try Buffer.init(testing.allocator, 60, 6);
    defer buf.deinit();

    PieChart.init(&slices).render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 6 });

    try expectLine(buf, 0, 40, 60, "■ CPU: 35 (58.3%)   ");
    try expectLine(buf, 1, 40, 60, "■ Mem: 25 (41.7%)   ");
}

test "piechart: percentages disabled drops the percent column" {
    const slices = [_]TSlice{.{ .label = "Test", .value = 75 }};
    var buf = try Buffer.init(testing.allocator, 30, 5);
    defer buf.deinit();

    PieChart.init(&slices).withPercentages(false)
        .render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 5 });

    try expectLine(buf, 0, 20, 30, "■ Test: 75");
    for (buf.cells) |cell| try testing.expect(cell.char != '%' and cell.char != '(');
}

test "piechart: bottom legend sits under the pie, one row per slice" {
    const slices = [_]TSlice{ .{ .label = "A", .value = 50 }, .{ .label = "B", .value = 50 } };
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    PieChart.init(&slices).withLegendPosition(.bottom)
        .render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // legend_height = min(10 / 3, 2 + 1) = 3 -> legend rows 7..9, chart rows 0..6.
    try expectLine(buf, 7, 0, 20, "■ A: 50 (50.0%)     ");
    try expectLine(buf, 8, 0, 20, "■ B: 50 (50.0%)     ");
    try expectLine(buf, 9, 0, 20, " " ** 20);
    try testing.expect(inkedCount(buf) > 0);
    for (7..10) |y| {
        for (0..20) |x| try testing.expect(buf.getChar(@intCast(x), @intCast(y)) != '█');
    }
}

test "piechart: no legend draws no marker and gives the pie the whole area" {
    const slices = [_]TSlice{.{ .label = "A", .value = 100 }};
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    PieChart.init(&slices).withLegendPosition(.none)
        .render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });

    for (buf.cells) |cell| try testing.expect(cell.char == ' ' or cell.char == '█');
    // Centre (5, 5), radius min(5, 5): the cell right of the centre is inked, so the pie
    // extends beyond what a legend-shrunk chart area (width 7) would allow only on the left.
    try testing.expectEqual(@as(u21, '█'), buf.getChar(5, 5));
    try testing.expectEqual(@as(u21, '█'), buf.getChar(9, 5));
    try testing.expectEqual(@as(u21, '█'), buf.getChar(1, 5));
}

test "piechart: two half slices fill opposite sides of the centre in their own styles" {
    const red = Style{ .fg = .red };
    const green = Style{ .fg = .green };
    const slices = [_]TSlice{
        .{ .label = "R", .value = 50, .style = red },
        .{ .label = "G", .value = 50, .style = green },
    };
    var buf = try Buffer.init(testing.allocator, 24, 14);
    defer buf.deinit();
    const area = Rect{ .x = 2, .y = 2, .width = 20, .height = 10 };

    PieChart.init(&slices).withLegendPosition(.none).render(&buf, area);

    const cx: u16 = 12;
    const cy: u16 = 7;
    for (1..5) |k_us| {
        const k: u16 = @intCast(k_us);
        try testing.expectEqual(red, buf.getStyle(cx + k, cy)); // 90 degrees
        try testing.expectEqual(green, buf.getStyle(cx - k, cy)); // 270 degrees
        try testing.expectEqual(green, buf.getStyle(cx, cy + k)); // 180 degrees
    }
    // The 355-degree ray of the second slice truncates onto the 0-degree column and overdraws
    // it, so only the tip of the 0-degree ray stays red.
    try testing.expectEqual(red, buf.getStyle(cx, cy - 4));
    try testing.expectEqual(red, buf.getStyle(cx + 2, cy - 2)); // 45 degrees
    try testing.expectEqual(green, buf.getStyle(cx - 2, cy + 2)); // 225 degrees
    try testing.expectEqual(green, buf.getStyle(cx, cy)); // later slice overdraws the hub
    // Radius is min(20 / 2, 10 / 2) = 5: nothing past four cells from the centre.
    try testing.expectEqual(@as(u21, ' '), buf.getChar(cx + 5, cy));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(cx, cy - 5));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(cx, cy + 5));
}

test "piechart: pie stays inside its area and never touches the surrounding border" {
    const slices = [_]TSlice{.{ .label = "A", .value = 100 }};
    const block = Block{};
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    PieChart.init(&slices).withBlock(block).withLegendPosition(.none)
        .render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    try expectLine(buf, 0, 0, 20, "┌" ++ "─" ** 18 ++ "┐");
    try expectLine(buf, 9, 0, 20, "└" ++ "─" ** 18 ++ "┘");
    for (1..9) |y| {
        try testing.expectEqual(@as(u21, '│'), buf.getChar(0, @intCast(y)));
        try testing.expectEqual(@as(u21, '│'), buf.getChar(19, @intCast(y)));
    }
    try testing.expect(inkedCount(buf) > 0);
}

test "piechart: pie does not spill into the bottom legend region" {
    const slices = [_]TSlice{.{ .label = "A", .value = 100 }};
    var buf = try Buffer.init(testing.allocator, 20, 12);
    defer buf.deinit();

    PieChart.init(&slices).withLegendPosition(.bottom)
        .render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 12 });

    // legend_height = min(12 / 3, 1 + 1) = 2 -> chart rows 0..9, legend rows 10..11.
    try expectLine(buf, 10, 0, 20, "■ A: 100 (100.0%)   ");
    try expectLine(buf, 11, 0, 20, " " ** 20);
    for (10..12) |y| {
        for (0..20) |x| try testing.expect(buf.getChar(@intCast(x), @intCast(y)) != '█');
    }
}

test "piechart: a zero-value slice draws no wedge but keeps its legend entry" {
    const slices = [_]TSlice{
        .{ .label = "A", .value = 100, .style = .{ .fg = .red } },
        .{ .label = "B", .value = 0, .style = .{ .fg = .blue } },
    };
    var buf = try Buffer.init(testing.allocator, 60, 8);
    defer buf.deinit();

    PieChart.init(&slices).render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 8 });

    try expectLine(buf, 1, 40, 60, "■ B: 0 (0.0%)       ");
    for (buf.cells) |cell| {
        if (cell.char == '█') try testing.expectEqual(Style{ .fg = .red }, cell.style);
    }
}

test "piechart: smallest drawable chart inks only the centre cell" {
    const slices = [_]TSlice{.{ .label = "A", .value = 1 }};
    var buf = try Buffer.init(testing.allocator, 4, 3);
    defer buf.deinit();

    PieChart.init(&slices).withLegendPosition(.none)
        .render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 3 });

    // radius = min(4 / 2, 3 / 2) = 1 -> only r = 0, the centre (2, 1).
    try testing.expectEqual(@as(usize, 1), inkedCount(buf));
    try testing.expectEqual(@as(u21, '█'), buf.getChar(2, 1));
}

test "piechart: charts below 3 cells in either direction draw nothing" {
    const slices = [_]TSlice{.{ .label = "A", .value = 50 }};
    var buf = try Buffer.init(testing.allocator, 5, 5);
    defer buf.deinit();

    PieChart.init(&slices).render(&buf, .{ .x = 0, .y = 0, .width = 3, .height = 2 });
    PieChart.init(&slices).withLegendPosition(.none)
        .render(&buf, .{ .x = 0, .y = 0, .width = 2, .height = 5 });
    try expectBlank(buf);
}

test "piechart: splitAreas right gives a third to the legend, capped at 20" {
    const slices = [_]TSlice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices);

    const c1, const l1 = chart.splitAreas(.{ .x = 0, .y = 0, .width = 30, .height = 10 });
    try testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 20, .height = 10 }, c1);
    try testing.expectEqual(Rect{ .x = 20, .y = 0, .width = 10, .height = 10 }, l1);

    const c2, const l2 = chart.splitAreas(.{ .x = 3, .y = 1, .width = 90, .height = 4 });
    try testing.expectEqual(Rect{ .x = 3, .y = 1, .width = 70, .height = 4 }, c2);
    try testing.expectEqual(Rect{ .x = 73, .y = 1, .width = 20, .height = 4 }, l2);
}

test "piechart: splitAreas right drops a legend narrower than the renderable minimum" {
    const slices = [_]TSlice{.{ .label = "A", .value = 50 }};
    const chart = PieChart.init(&slices);
    const empty = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const narrow = Rect{ .x = 0, .y = 0, .width = 14, .height = 10 }; // 14 / 3 = 4 < 5
    const c1, const l1 = chart.splitAreas(narrow);
    try testing.expectEqual(narrow, c1);
    try testing.expectEqual(empty, l1);

    const c2, const l2 = chart.splitAreas(.{ .x = 0, .y = 0, .width = 15, .height = 10 });
    try testing.expectEqual(@as(u16, 10), c2.width);
    try testing.expectEqual(@as(u16, 5), l2.width);
}

test "piechart: splitAreas bottom reserves a row per slice up to a third of the height" {
    const one = [_]TSlice{.{ .label = "A", .value = 50 }};
    const nine = [_]TSlice{.{ .label = "A", .value = 1 }} ** 9;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 12 };

    const c1, const l1 = PieChart.init(&one).withLegendPosition(.bottom).splitAreas(area);
    try testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 20, .height = 10 }, c1);
    try testing.expectEqual(Rect{ .x = 0, .y = 10, .width = 20, .height = 2 }, l1);

    const c2, const l2 = PieChart.init(&nine).withLegendPosition(.bottom).splitAreas(area);
    try testing.expectEqual(@as(u16, 8), c2.height);
    try testing.expectEqual(Rect{ .x = 0, .y = 8, .width = 20, .height = 4 }, l2);
}

test "piechart: splitAreas bottom on a one-row area leaves everything to the chart" {
    const slices = [_]TSlice{.{ .label = "A", .value = 50 }};
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 2 };
    const c, const l = PieChart.init(&slices).withLegendPosition(.bottom).splitAreas(area);

    try testing.expectEqual(area, c);
    try testing.expectEqual(@as(u16, 0), l.height);
}

test "piechart: splitAreas none returns the area and an empty legend" {
    const slices = [_]TSlice{.{ .label = "A", .value = 50 }};
    const area = Rect{ .x = 4, .y = 2, .width = 20, .height = 10 };
    const c, const l = PieChart.init(&slices).withLegendPosition(.none).splitAreas(area);

    try testing.expectEqual(area, c);
    try testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 0, .height = 0 }, l);
}

test "piechart: legend clips long ASCII and multibyte labels to the legend width" {
    const long = "x" ** 200;
    const wide = "é" ** 100;
    const slices = [_]TSlice{ .{ .label = long, .value = 1 }, .{ .label = wide, .value = 1 } };
    var buf = try Buffer.init(testing.allocator, 50, 6);
    defer buf.deinit();

    PieChart.init(&slices).render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 6 });

    // Legend spans x = 27..39 (13 cells); nothing may reach x >= 40.
    try expectLine(buf, 0, 27, 50, "■ xxxxxxxxxxx" ++ " " ** 10);
    try expectLine(buf, 1, 27, 50, "■ ééééééééééé" ++ " " ** 10);
}

test "piechart: legend places double-width labels on every second cell and clips at the edge" {
    const slices = [_]TSlice{.{ .label = "日本語", .value = 35 }};
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    PieChart.init(&slices).withLegendPosition(.bottom)
        .render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 3 });

    // 3 / 3 = 1 legend row at y = 2; entry is "■ 日本語: 35 (100.0%)".
    try testing.expectEqual(@as(u21, '■'), buf.getChar(0, 2));
    try testing.expectEqual(@as(u21, '日'), buf.getChar(2, 2));
    try testing.expectEqual(@as(u21, '本'), buf.getChar(4, 2));
    try testing.expectEqual(@as(u21, '語'), buf.getChar(6, 2));
    try testing.expectEqual(@as(u21, ':'), buf.getChar(8, 2));
    try testing.expectEqual(@as(u21, '3'), buf.getChar(10, 2));
    try testing.expectEqual(@as(u21, '5'), buf.getChar(11, 2));
}

test "piechart: u64-sized values render exact counts and percentages" {
    const top = std.math.maxInt(u64);
    const slices = [_]TSlice{ .{ .label = "A", .value = top }, .{ .label = "B", .value = top } };
    var buf = try Buffer.init(testing.allocator, 60, 12);
    defer buf.deinit();

    PieChart.init(&slices).withLegendPosition(.bottom)
        .render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 12 });

    // legend_height = min(12 / 3, 3) = 3 -> legend rows 9..11.
    try expectLine(buf, 9, 0, 60, "■ A: 18446744073709551615 (50.0%)" ++ " " ** 27);
    try expectLine(buf, 10, 0, 60, "■ B: 18446744073709551615 (50.0%)" ++ " " ** 27);
}

test "piechart: seeded random charts never write outside their area" {
    var prng = std.Random.DefaultPrng.init(0x91e);
    const random = prng.random();
    var slices: [5]TSlice = undefined;
    for (0..96) |_| {
        for (&slices) |*s| s.* = .{ .label = "lbl", .value = random.uintLessThan(u64, 50) };
        const area = Rect{
            .x = random.uintLessThan(u16, 4),
            .y = random.uintLessThan(u16, 4),
            .width = random.uintLessThan(u16, 30),
            .height = random.uintLessThan(u16, 14),
        };
        var buf = try Buffer.init(testing.allocator, 36, 20);
        defer buf.deinit();
        const legend = random.enumValue(PieChart.LegendPosition);

        PieChart.init(slices[0..random.uintAtMost(usize, 5)]).withLegendPosition(legend)
            .withPercentages(random.boolean()).render(&buf, area);

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
