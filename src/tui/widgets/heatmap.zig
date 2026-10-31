//! Heatmap widget: 2D data grid visualization with color gradients.
//!
//! Each data value occupies exactly one terminal cell: column `c` of row `r` is drawn at
//! `(data_area.x + c, data_area.y + r)`, with the gradient color as background and a density
//! glyph chosen by `cell_mode`. Rows may be ragged; missing cells are left untouched.
const std = @import("std");
const tui = @import("../tui.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Heatmap widget — 2D data visualization with color gradients
pub const Heatmap = struct {
    /// 2D data grid (row-major order: [y][x])
    data: []const []const f64,
    /// Optional row labels
    row_labels: ?[]const []const u8 = null,
    /// Optional column labels
    col_labels: ?[]const []const u8 = null,
    /// Optional block border/title
    block: ?Block = null,
    /// Color gradient (low value → high value)
    gradient: Gradient = .rainbow,
    /// Value range for color mapping (null = auto-detect min/max)
    value_range: ?ValueRange = null,
    /// Cell display mode
    cell_mode: CellMode = .unicode,

    pub const Gradient = enum {
        rainbow, // blue → cyan → green → yellow → red
        monochrome, // white → gray → black
        heat, // black → red → orange → yellow → white
        cool, // blue → cyan → green
        grayscale, // black → white
    };

    pub const ValueRange = struct {
        min: f64,
        max: f64,
    };

    pub const CellMode = enum {
        unicode, // Use block elements (▁▂▃▄▅▆▇█) for 9 density levels
        ascii, // Use ASCII chars (' ', '.', '+', '*', '#', '@') for 6 levels
        numeric, // Color only: cells are blank (a cell is too narrow to show a number)
    };

    /// Longest row label that is drawn; longer labels are truncated.
    const max_row_label: usize = 20;

    /// Render the heatmap
    pub fn render(self: Heatmap, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.width == 0 or render_area.height == 0) return;
        if (self.data.len == 0) return;

        // Reserve space for labels
        const row_label_width: u16 = if (self.row_labels) |labels| blk: {
            var max_len: usize = 0;
            for (labels) |label| max_len = @max(max_len, @min(label.len, max_row_label));
            break :blk @as(u16, @intCast(max_len)) + 1; // +1 for spacing
        } else 0;
        const col_label_height: u16 = if (self.col_labels != null) 1 else 0;

        const data_area = Rect{
            .x = render_area.x +| row_label_width,
            .y = render_area.y +| col_label_height,
            .width = render_area.width -| row_label_width,
            .height = render_area.height -| col_label_height,
        };
        if (data_area.width == 0 or data_area.height == 0) return;

        self.renderLabels(buf, render_area, data_area);
        self.renderCells(buf, data_area);
    }

    /// Draw column labels above the data (one cell per column, clipped to it) and row labels
    /// left of it (truncated to the label gutter).
    fn renderLabels(self: Heatmap, buf: *Buffer, render_area: Rect, data_area: Rect) void {
        if (self.col_labels) |labels| {
            const cols = @min(@min(labels.len, self.maxCols()), data_area.width);
            for (labels[0..cols], 0..) |label, i| {
                if (label.len == 0) continue;
                const x = data_area.x + @as(u16, @intCast(i));
                buf.setString(x, render_area.y, label[0..1], Style{});
            }
        }

        if (self.row_labels) |labels| {
            const gutter = data_area.x - render_area.x - 1; // width without the spacing cell
            const rows = @min(labels.len, @min(self.data.len, data_area.height));
            for (labels[0..rows], 0..) |label, i| {
                const y = data_area.y + @as(u16, @intCast(i));
                buf.setString(render_area.x, y, label[0..@min(label.len, gutter)], Style{});
            }
        }
    }

    /// Draw the colored cells, clipped to `data_area`; each row is clipped by its own length.
    fn renderCells(self: Heatmap, buf: *Buffer, data_area: Rect) void {
        const range = self.value_range orelse self.computeRange();
        const rows = @min(self.data.len, data_area.height);
        for (self.data[0..rows], 0..) |row, row_idx| {
            const y = data_area.y + @as(u16, @intCast(row_idx));
            const cols = @min(row.len, data_area.width);
            for (row[0..cols], 0..) |value, col| {
                const x = data_area.x + @as(u16, @intCast(col));
                const color = self.valueToColor(value, range);
                const char = self.valueToChar(value, range);
                buf.set(x, y, .{ .char = char, .style = Style{ .bg = color } });
            }
        }
    }

    /// Compute min/max values from data
    fn computeRange(self: Heatmap) ValueRange {
        var min: f64 = std.math.floatMax(f64);
        var max: f64 = -std.math.floatMax(f64);
        for (self.data) |row| {
            for (row) |value| {
                min = @min(min, value);
                max = @max(max, value);
            }
        }
        return .{ .min = min, .max = max };
    }

    /// Normalize `value` into [0, 1] against `range`; a degenerate range maps to 0.5.
    fn normalize(value: f64, range: ValueRange) f64 {
        const normalized = if (range.max > range.min)
            (value - range.min) / (range.max - range.min)
        else
            0.5;
        return @max(0.0, @min(1.0, normalized));
    }

    /// `limit * t` as a byte; `t` is in [0, 1] and `limit` at most 255.
    fn channel(limit: f64, t: f64) u8 {
        std.debug.assert(limit >= 0 and limit <= 255);
        return @intFromFloat(@max(0.0, @min(limit, limit * t)));
    }

    fn rgb(r: u8, g: u8, b: u8) Color {
        return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
    }

    /// Map value to color based on gradient
    fn valueToColor(self: Heatmap, value: f64, range: ValueRange) Color {
        const c = normalize(value, range);
        return switch (self.gradient) {
            .rainbow => if (c < 0.25)
                rgb(0, channel(255, c * 4), 255) // blue → cyan
            else if (c < 0.5)
                rgb(0, 255, channel(255, 1 - (c - 0.25) * 4)) // cyan → green
            else if (c < 0.75)
                rgb(channel(255, (c - 0.5) * 4), 255, 0) // green → yellow
            else
                rgb(255, channel(255, 1 - (c - 0.75) * 4), 0), // yellow → red
            .monochrome => rgb(channel(255, 1 - c), channel(255, 1 - c), channel(255, 1 - c)),
            .heat => if (c < 0.25)
                rgb(channel(255, c * 4), 0, 0) // black → red
            else if (c < 0.5)
                rgb(255, channel(128, (c - 0.25) * 4), 0) // red → orange
            else if (c < 0.75)
                rgb(255, 128 + channel(127, (c - 0.5) * 4), 0) // orange → yellow
            else
                rgb(255, 255, channel(255, (c - 0.75) * 4)), // yellow → white
            .cool => if (c < 0.5)
                rgb(0, channel(255, c * 2), 255) // blue → cyan
            else
                rgb(0, 255, channel(255, 1 - (c - 0.5) * 2)), // cyan → green
            .grayscale => rgb(channel(255, c), channel(255, c), channel(255, c)),
        };
    }

    /// Map value to character based on cell mode
    fn valueToChar(self: Heatmap, value: f64, range: ValueRange) u21 {
        const t = normalize(value, range);
        return switch (self.cell_mode) {
            // Blank plus eight block elements of increasing height.
            .unicode => level(&[_]u21{ ' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' }, t),
            .ascii => level(&[_]u21{ ' ', '.', '+', '*', '#', '@' }, t),
            .numeric => ' ',
        };
    }

    /// Pick the glyph for `t` in [0, 1]: `t == 1` selects the last level.
    fn level(levels: []const u21, t: f64) u21 {
        std.debug.assert(levels.len >= 2);
        const idx: usize = @intFromFloat(t * @as(f64, @floatFromInt(levels.len - 1)));
        return levels[@min(idx, levels.len - 1)];
    }

    /// Length of the longest data row.
    fn maxCols(self: Heatmap) usize {
        var widest: usize = 0;
        for (self.data) |row| widest = @max(widest, row.len);
        return widest;
    }
};

// Tests
const testing = std.testing;

const full = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };

fn charAt(buf: Buffer, x: u16, y: u16) u21 {
    return buf.getConst(x, y).?.char;
}

fn bgAt(buf: Buffer, x: u16, y: u16) ?Color {
    return buf.getConst(x, y).?.style.bg;
}

fn expectUntouched(buf: Buffer, x: u16, y: u16) !void {
    const cell = buf.getConst(x, y).?;
    try testing.expectEqual(@as(u21, ' '), cell.char);
    try testing.expectEqual(@as(?Color, null), cell.style.bg);
}

fn expectRgb(color: ?Color, r: u8, g: u8, b: u8) !void {
    try testing.expectEqual(@as(?Color, Color{ .rgb = .{ .r = r, .g = g, .b = b } }), color);
}

fn expectAllUntouched(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

test "heatmap: render maps each value to its own cell, glyph and color" {
    const data = [_][]const f64{
        &[_]f64{ 0.0, 0.5, 1.0 },
        &[_]f64{ 0.25, 0.75, 0.5 },
    };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    (Heatmap{ .data = &data }).render(&buf, full);

    // Auto range is 0..1; unicode glyph index is floor(v * 8); rainbow endpoints are known.
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, '▄'), charAt(buf, 1, 0));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 2, 0));
    try testing.expectEqual(@as(u21, '▂'), charAt(buf, 0, 1));
    try testing.expectEqual(@as(u21, '▆'), charAt(buf, 1, 1));
    try testing.expectEqual(@as(u21, '▄'), charAt(buf, 2, 1));
    try expectRgb(bgAt(buf, 0, 0), 0, 0, 255);
    try expectRgb(bgAt(buf, 1, 0), 0, 255, 0);
    try expectRgb(bgAt(buf, 2, 0), 255, 0, 0);
    try expectUntouched(buf, 3, 0);
    try expectUntouched(buf, 0, 2);
}

test "heatmap: block border is drawn and data is rendered inside it" {
    const data = [_][]const f64{&[_]f64{ 1.0, 2.0, 3.0 }};
    const heatmap = Heatmap{ .data = &data, .block = Block{ .title = "Heat" } };
    var buf = try Buffer.init(testing.allocator, 15, 5);
    defer buf.deinit();
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 15, .height = 5 });

    try testing.expectEqual(@as(u21, '┌'), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, '┐'), charAt(buf, 14, 0));
    try testing.expectEqual(@as(u21, '└'), charAt(buf, 0, 4));
    try testing.expectEqual(@as(u21, 'H'), charAt(buf, 2, 0));
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 1, 1));
    try testing.expectEqual(@as(u21, '▄'), charAt(buf, 2, 1));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 3, 1));
    try expectUntouched(buf, 4, 1);
    // Border cells never receive a heat color.
    try testing.expectEqual(@as(?Color, null), bgAt(buf, 0, 1));
}

test "heatmap: row labels sit in a gutter and push the data right" {
    const data = [_][]const f64{ &[_]f64{ 1.0, 4.0 }, &[_]f64{ 4.0, 1.0 } };
    const row_labels = [_][]const u8{ "A", "B" };
    const heatmap = Heatmap{ .data = &data, .row_labels = &row_labels };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    heatmap.render(&buf, full);

    try testing.expectEqual(@as(u21, 'A'), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, 'B'), charAt(buf, 0, 1));
    try expectUntouched(buf, 1, 0);
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 2, 0));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 3, 0));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 2, 1));
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 3, 1));
}

test "heatmap: column labels occupy the first row and data starts below" {
    const data = [_][]const f64{&[_]f64{ 1.0, 2.0, 3.0 }};
    const col_labels = [_][]const u8{ "X", "Y", "Z" };
    const heatmap = Heatmap{ .data = &data, .col_labels = &col_labels };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    heatmap.render(&buf, full);

    try testing.expectEqual(@as(u21, 'X'), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, 'Y'), charAt(buf, 1, 0));
    try testing.expectEqual(@as(u21, 'Z'), charAt(buf, 2, 0));
    try testing.expectEqual(@as(?Color, null), bgAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 1));
    try testing.expectEqual(@as(u21, '▄'), charAt(buf, 1, 1));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 2, 1));
}

test "heatmap: column labels align with their data columns (regression)" {
    // Regression: labels were spread by width / columns while data cells are one cell wide,
    // so labels drifted away from the column they name.
    const data = [_][]const f64{&[_]f64{ 1.0, 2.0, 3.0, 4.0 }};
    const col_labels = [_][]const u8{ "a", "b", "c", "d" };
    const heatmap = Heatmap{ .data = &data, .col_labels = &col_labels };
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 3 });

    try testing.expectEqual(@as(u21, 'a'), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, 'b'), charAt(buf, 1, 0));
    try testing.expectEqual(@as(u21, 'c'), charAt(buf, 2, 0));
    try testing.expectEqual(@as(u21, 'd'), charAt(buf, 3, 0));
    try expectUntouched(buf, 4, 0);
}

test "heatmap: labels beyond the data extent are not drawn" {
    const data = [_][]const f64{&[_]f64{ 1.0, 2.0 }};
    const col_labels = [_][]const u8{ "a", "b", "c" };
    const row_labels = [_][]const u8{ "r0", "r1" };
    const heatmap = Heatmap{ .data = &data, .col_labels = &col_labels, .row_labels = &row_labels };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    heatmap.render(&buf, full);

    // Gutter is 3 wide ("r0" + spacing), so data and col labels start at x = 3.
    try testing.expectEqual(@as(u21, 'a'), charAt(buf, 3, 0));
    try testing.expectEqual(@as(u21, 'b'), charAt(buf, 4, 0));
    try expectUntouched(buf, 5, 0);
    try testing.expectEqual(@as(u21, 'r'), charAt(buf, 0, 1));
    try expectUntouched(buf, 0, 2);
}

test "heatmap: both label kinds offset the data by gutter and header" {
    const data = [_][]const f64{ &[_]f64{ 1.0, 2.0 }, &[_]f64{ 3.0, 4.0 } };
    const row_labels = [_][]const u8{ "Row1", "Row2" };
    const col_labels = [_][]const u8{ "Col1", "Col2" };
    const heatmap = Heatmap{ .data = &data, .row_labels = &row_labels, .col_labels = &col_labels };
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    try testing.expectEqual(@as(u21, 'R'), charAt(buf, 0, 1));
    try testing.expectEqual(@as(u21, '1'), charAt(buf, 3, 1));
    try testing.expectEqual(@as(u21, '2'), charAt(buf, 3, 2));
    try expectUntouched(buf, 4, 1);
    // Column labels are clipped to their one-cell column.
    try testing.expectEqual(@as(u21, 'C'), charAt(buf, 5, 0));
    try testing.expectEqual(@as(u21, 'C'), charAt(buf, 6, 0));
    try expectUntouched(buf, 7, 0);
    // Data: 1..4 -> floor(((v - 1) / 3) * 8).
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 5, 1));
    try testing.expectEqual(@as(u21, '▂'), charAt(buf, 6, 1));
    try testing.expectEqual(@as(u21, '▅'), charAt(buf, 5, 2));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 6, 2));
}

test "heatmap: overlong row label is truncated to 20 cells, data stays intact (regression)" {
    // Regression: the label was cut to the gutter width including the spacing cell, so a
    // long label overwrote the first data column.
    const data = [_][]const f64{&[_]f64{ 1.0, 2.0 }};
    const long = "abcdefghijklmnopqrstuvwxyz";
    const row_labels = [_][]const u8{long};
    const heatmap = Heatmap{ .data = &data, .row_labels = &row_labels };
    var buf = try Buffer.init(testing.allocator, 30, 2);
    defer buf.deinit();
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 2 });

    try testing.expectEqual(@as(u21, 't'), charAt(buf, 19, 0));
    try expectUntouched(buf, 20, 0);
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 21, 0));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 22, 0));
    try expectRgb(bgAt(buf, 21, 0), 0, 0, 255);
}

test "heatmap: empty data draws nothing, not even a border-less label" {
    const data: []const []const f64 = &[_][]const f64{};
    const labels = [_][]const u8{"A"};
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    (Heatmap{ .data = data, .row_labels = &labels }).render(&buf, full);

    try expectAllUntouched(buf);
}

test "heatmap: zero-sized area draws nothing" {
    const data = [_][]const f64{&[_]f64{1.0}};
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    const heatmap = Heatmap{ .data = &data };
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 0 });
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 5 });

    try expectAllUntouched(buf);
}

test "heatmap: labels that fill the whole area leave no room for data" {
    const data = [_][]const f64{&[_]f64{1.0}};
    const row_labels = [_][]const u8{"wide"};
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    const heatmap = Heatmap{ .data = &data, .row_labels = &row_labels };
    heatmap.render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 3 });

    try expectAllUntouched(buf);
}

test "heatmap: row with no cells and column labels does not divide by zero (regression)" {
    // Regression: the column label stride divided by min(data[0].len, width) == 0.
    const data = [_][]const f64{ &[_]f64{}, &[_]f64{ 1.0, 2.0 } };
    const col_labels = [_][]const u8{ "a", "b" };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    (Heatmap{ .data = &data, .col_labels = &col_labels }).render(&buf, full);

    try testing.expectEqual(@as(u21, 'a'), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, 'b'), charAt(buf, 1, 0));
    try expectUntouched(buf, 0, 1);
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 2));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 1, 2));
}

test "heatmap: ragged rows are clipped by their own length (regression)" {
    // Regression: the column count came from row 0, so a shorter later row read out of bounds.
    const data = [_][]const f64{ &[_]f64{ 1.0, 2.0, 3.0 }, &[_]f64{4.0}, &[_]f64{ 1.0, 4.0 } };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    (Heatmap{ .data = &data, .cell_mode = .ascii }).render(&buf, full);

    // Auto range 1..4, ascii glyph index floor(((v - 1) / 3) * 5).
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, '.'), charAt(buf, 1, 0));
    try testing.expectEqual(@as(u21, '*'), charAt(buf, 2, 0));
    try testing.expectEqual(@as(u21, '@'), charAt(buf, 0, 1));
    try expectUntouched(buf, 1, 1);
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 2));
    try testing.expectEqual(@as(u21, '@'), charAt(buf, 1, 2));
    try expectUntouched(buf, 2, 2);
}

test "heatmap: computeRange spans negative and positive values" {
    const data = [_][]const f64{ &[_]f64{ -5.0, 0.0, 5.0 }, &[_]f64{ 10.0, -10.0, 2.5 } };
    const range = (Heatmap{ .data = &data }).computeRange();

    try testing.expectEqual(@as(f64, -10.0), range.min);
    try testing.expectEqual(@as(f64, 10.0), range.max);
}

test "heatmap: computeRange of all-negative data has a negative maximum (regression)" {
    // Regression: the maximum was seeded with floatMin (smallest positive), not -floatMax.
    const data = [_][]const f64{&[_]f64{ -3.0, -2.0, -1.0 }};
    const range = (Heatmap{ .data = &data }).computeRange();

    try testing.expectEqual(@as(f64, -3.0), range.min);
    try testing.expectEqual(@as(f64, -1.0), range.max);
}

test "heatmap: all-negative data renders across the full glyph scale (regression)" {
    const data = [_][]const f64{&[_]f64{ -3.0, -2.0, -1.0 }};
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    (Heatmap{ .data = &data }).render(&buf, full);

    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, '▄'), charAt(buf, 1, 0));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 2, 0));
}

test "heatmap: NaN values do not poison the auto range" {
    const nan = std.math.nan(f64);
    const data = [_][]const f64{&[_]f64{ nan, 1.0, 0.0 }};
    const heatmap = Heatmap{ .data = &data };
    const range = heatmap.computeRange();
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    heatmap.render(&buf, full);

    try testing.expectEqual(@as(f64, 0.0), range.min);
    try testing.expectEqual(@as(f64, 1.0), range.max);
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 1, 0));
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 2, 0));
}

test "heatmap: constant data maps to the middle of the scale" {
    const data = [_][]const f64{&[_]f64{ 7.0, 7.0 }};
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    (Heatmap{ .data = &data }).render(&buf, full);

    try testing.expectEqual(@as(u21, '▄'), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, '▄'), charAt(buf, 1, 0));
    try expectRgb(bgAt(buf, 0, 0), 0, 255, 0);
}

test "heatmap: explicit value range overrides the data extent and clamps outliers" {
    const data = [_][]const f64{&[_]f64{ 100.0, 200.0, 300.0, 1000.0, -50.0 }};
    const heatmap = Heatmap{
        .data = &data,
        .value_range = .{ .min = 0.0, .max = 400.0 },
        .cell_mode = .ascii,
    };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    heatmap.render(&buf, full);

    // Ascii glyph index is floor((v / 400) * 5): 1.25, 2.5, 3.75, clamp high, clamp low.
    try testing.expectEqual(@as(u21, '.'), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, '+'), charAt(buf, 1, 0));
    try testing.expectEqual(@as(u21, '*'), charAt(buf, 2, 0));
    try testing.expectEqual(@as(u21, '@'), charAt(buf, 3, 0));
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 4, 0));
}

test "heatmap: large data is clipped to the area and leaves the rest untouched" {
    var rows: [100][100]f64 = undefined;
    for (&rows, 0..) |*row, i| {
        for (row, 0..) |*cell, j| cell.* = @floatFromInt(i + j);
    }
    var ptrs: [100][]const f64 = undefined;
    for (&ptrs, 0..) |*ptr, i| ptr.* = &rows[i];

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    (Heatmap{ .data = &ptrs }).render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 4 });

    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            if (x < 8 and y < 4) {
                try testing.expect(bgAt(buf, x, y) != null);
            } else {
                try expectUntouched(buf, x, y);
            }
        }
    }
    // Auto range 0..198: the top-left cell is the minimum, the clipped far corner is not.
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 0));
    try expectRgb(bgAt(buf, 0, 0), 0, 0, 255);
}

test "heatmap: area offset moves data and leaves surrounding cells untouched" {
    const data = [_][]const f64{&[_]f64{ 0.0, 1.0 }};
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    (Heatmap{ .data = &data }).render(&buf, .{ .x = 4, .y = 2, .width = 3, .height = 2 });

    try testing.expectEqual(@as(u21, ' '), charAt(buf, 4, 2));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 5, 2));
    try expectRgb(bgAt(buf, 5, 2), 255, 0, 0);
    try expectUntouched(buf, 3, 2);
    try expectUntouched(buf, 6, 2);
    try expectUntouched(buf, 4, 3);
}

test "heatmap: area larger than the buffer is clipped without panicking" {
    const data = [_][]const f64{&[_]f64{ 0.0, 1.0, 0.5 }};
    var buf = try Buffer.init(testing.allocator, 2, 1);
    defer buf.deinit();
    (Heatmap{ .data = &data }).render(&buf, .{ .x = 0, .y = 0, .width = 50, .height = 50 });

    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, '█'), charAt(buf, 1, 0));
}

test "heatmap: rainbow gradient hits blue, cyan, green, yellow and red" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .rainbow };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try expectRgb(heatmap.valueToColor(0.0, range), 0, 0, 255);
    try expectRgb(heatmap.valueToColor(0.25, range), 0, 255, 255);
    try expectRgb(heatmap.valueToColor(0.5, range), 0, 255, 0);
    try expectRgb(heatmap.valueToColor(0.75, range), 255, 255, 0);
    try expectRgb(heatmap.valueToColor(1.0, range), 255, 0, 0);
}

test "heatmap: rainbow gradient is continuous across its segment boundaries (regression)" {
    // Regression: the first segment faded blue to black and the next one jumped back to blue.
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .rainbow };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };
    const boundaries = [_]f64{ 0.25, 0.5, 0.75 };

    for (boundaries) |b| {
        const below = heatmap.valueToColor(b - 0.001, range).rgb;
        const above = heatmap.valueToColor(b, range).rgb;
        try testing.expect(@abs(@as(i32, below.r) - above.r) <= 8);
        try testing.expect(@abs(@as(i32, below.g) - above.g) <= 8);
        try testing.expect(@abs(@as(i32, below.b) - above.b) <= 8);
    }
}

test "heatmap: rainbow mid-segment values interpolate linearly" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .rainbow };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try expectRgb(heatmap.valueToColor(0.125, range), 0, 127, 255);
    try expectRgb(heatmap.valueToColor(0.375, range), 0, 255, 127);
    try expectRgb(heatmap.valueToColor(0.625, range), 127, 255, 0);
    try expectRgb(heatmap.valueToColor(0.875, range), 255, 127, 0);
}

test "heatmap: monochrome gradient runs white to black through equal channels" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .monochrome };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try expectRgb(heatmap.valueToColor(0.0, range), 255, 255, 255);
    try expectRgb(heatmap.valueToColor(0.5, range), 127, 127, 127);
    try expectRgb(heatmap.valueToColor(1.0, range), 0, 0, 0);
}

test "heatmap: grayscale gradient runs black to white through equal channels" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .grayscale };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try expectRgb(heatmap.valueToColor(0.0, range), 0, 0, 0);
    try expectRgb(heatmap.valueToColor(0.5, range), 127, 127, 127);
    try expectRgb(heatmap.valueToColor(1.0, range), 255, 255, 255);
}

test "heatmap: heat gradient runs black, red, orange, yellow, white" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .heat };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try expectRgb(heatmap.valueToColor(0.0, range), 0, 0, 0);
    try expectRgb(heatmap.valueToColor(0.25, range), 255, 0, 0);
    try expectRgb(heatmap.valueToColor(0.375, range), 255, 64, 0);
    try expectRgb(heatmap.valueToColor(0.5, range), 255, 128, 0);
    try expectRgb(heatmap.valueToColor(0.75, range), 255, 255, 0);
    try expectRgb(heatmap.valueToColor(1.0, range), 255, 255, 255);
}

test "heatmap: cool gradient runs blue, cyan, green (regression)" {
    // Regression: the second half ramped red up and ended on yellow instead of green.
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .cool };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try expectRgb(heatmap.valueToColor(0.0, range), 0, 0, 255);
    try expectRgb(heatmap.valueToColor(0.25, range), 0, 127, 255);
    try expectRgb(heatmap.valueToColor(0.5, range), 0, 255, 255);
    try expectRgb(heatmap.valueToColor(1.0, range), 0, 255, 0);
}

test "heatmap: color out-of-range values clamp to the gradient endpoints" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .grayscale };
    const range = Heatmap.ValueRange{ .min = 10.0, .max = 20.0 };

    try expectRgb(heatmap.valueToColor(-1000.0, range), 0, 0, 0);
    try expectRgb(heatmap.valueToColor(1000.0, range), 255, 255, 255);
    try expectRgb(heatmap.valueToColor(std.math.inf(f64), range), 255, 255, 255);
}

test "heatmap: every gradient yields an rgb color across a dense sweep" {
    const gradients = [_]Heatmap.Gradient{ .rainbow, .monochrome, .heat, .cool, .grayscale };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    for (gradients) |gradient| {
        const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = gradient };
        var i: usize = 0;
        while (i <= 1000) : (i += 1) {
            const value = @as(f64, @floatFromInt(i)) / 1000.0;
            const color = heatmap.valueToColor(value, range);
            try testing.expect(color == .rgb);
        }
    }
}

test "heatmap: unicode mode uses nine increasing levels" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .cell_mode = .unicode };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try testing.expectEqual(@as(u21, ' '), heatmap.valueToChar(0.0, range));
    try testing.expectEqual(@as(u21, '▁'), heatmap.valueToChar(0.125, range));
    try testing.expectEqual(@as(u21, '▄'), heatmap.valueToChar(0.5, range));
    try testing.expectEqual(@as(u21, '▇'), heatmap.valueToChar(0.99, range));
    try testing.expectEqual(@as(u21, '█'), heatmap.valueToChar(1.0, range));
}

test "heatmap: ascii mode uses six increasing levels" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .cell_mode = .ascii };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    try testing.expectEqual(@as(u21, ' '), heatmap.valueToChar(0.0, range));
    try testing.expectEqual(@as(u21, '.'), heatmap.valueToChar(0.3, range));
    try testing.expectEqual(@as(u21, '+'), heatmap.valueToChar(0.5, range));
    try testing.expectEqual(@as(u21, '*'), heatmap.valueToChar(0.7, range));
    try testing.expectEqual(@as(u21, '#'), heatmap.valueToChar(0.9, range));
    try testing.expectEqual(@as(u21, '@'), heatmap.valueToChar(1.0, range));
}

test "heatmap: numeric mode draws blank glyphs but keeps the heat color" {
    const data = [_][]const f64{&[_]f64{ 0.0, 1.0 }};
    const heatmap = Heatmap{ .data = &data, .cell_mode = .numeric, .gradient = .grayscale };
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    heatmap.render(&buf, full);

    try testing.expectEqual(@as(u21, ' '), charAt(buf, 0, 0));
    try testing.expectEqual(@as(u21, ' '), charAt(buf, 1, 0));
    try expectRgb(bgAt(buf, 0, 0), 0, 0, 0);
    try expectRgb(bgAt(buf, 1, 0), 255, 255, 255);
}

test "heatmap: model check - integer grids render the reference glyph and gray level" {
    var prng = std.Random.DefaultPrng.init(0xBEEF);
    const rng = prng.random();
    var storage: [6][8]f64 = undefined;
    var rows: [6][]const f64 = undefined;

    for (0..200) |_| {
        const nrows = rng.intRangeAtMost(usize, 1, rows.len);
        const ncols = rng.intRangeAtMost(usize, 1, 8);
        for (0..nrows) |r| {
            for (0..ncols) |c| storage[r][c] = @floatFromInt(rng.uintAtMost(u8, 10));
            rows[r] = storage[r][0..ncols];
        }
        const width = rng.intRangeAtMost(u16, 1, 10);
        const height = rng.intRangeAtMost(u16, 1, 8);
        const heatmap = Heatmap{
            .data = rows[0..nrows],
            .value_range = .{ .min = 0.0, .max = 10.0 },
            .gradient = .grayscale,
            .cell_mode = .ascii,
        };
        var buf = try Buffer.init(testing.allocator, 12, 9);
        defer buf.deinit();
        heatmap.render(&buf, .{ .x = 1, .y = 1, .width = width, .height = height });
        buf.check_invariants();

        var y: u16 = 0;
        while (y < 9) : (y += 1) {
            var x: u16 = 0;
            while (x < 12) : (x += 1) {
                const inside = x >= 1 and y >= 1 and x - 1 < @min(ncols, width) and
                    y - 1 < @min(nrows, height);
                if (!inside) {
                    try expectUntouched(buf, x, y);
                    continue;
                }
                const v: u8 = @intFromFloat(storage[y - 1][x - 1]);
                const glyphs = [_]u21{ ' ', '.', '+', '*', '#', '@' };
                try testing.expectEqual(glyphs[v / 2], charAt(buf, x, y));
                const gray: u8 = @intCast(@as(u16, v) * 255 / 10);
                try expectRgb(bgAt(buf, x, y), gray, gray, gray);
            }
        }
    }
}

fn fuzzRender(_: void, smith: *testing.Smith) anyerror!void {
    var storage: [4][6]f64 = undefined;
    var rows: [4][]const f64 = undefined;
    const inf = std.math.inf(f64);
    const specials = [_]f64{ 0.0, -0.0, 1.0, -1.0, 1e300, -1e300, inf, -inf, std.math.nan(f64) };
    const nrows: usize = smith.valueRangeAtMost(u8, 0, 4);
    for (0..nrows) |r| {
        const ncols: usize = smith.valueRangeAtMost(u8, 0, 6);
        for (0..ncols) |c| {
            const pick = smith.valueRangeAtMost(u8, 0, 12);
            storage[r][c] = if (pick < specials.len) specials[pick] else @floatFromInt(pick);
        }
        rows[r] = storage[r][0..ncols];
    }
    const labels = [_][]const u8{ "", "a", "label", "αβγ" };
    var heatmap = Heatmap{ .data = rows[0..nrows] };
    heatmap.gradient = @enumFromInt(smith.valueRangeAtMost(u8, 0, 4));
    heatmap.cell_mode = @enumFromInt(smith.valueRangeAtMost(u8, 0, 2));
    if (smith.valueRangeAtMost(u8, 0, 1) == 1) heatmap.row_labels = &labels;
    if (smith.valueRangeAtMost(u8, 0, 1) == 1) heatmap.col_labels = &labels;
    if (smith.valueRangeAtMost(u8, 0, 1) == 1) heatmap.block = Block{};
    if (smith.valueRangeAtMost(u8, 0, 1) == 1) heatmap.value_range = .{ .min = -1.0, .max = 1.0 };

    var buf = try Buffer.init(testing.allocator, 12, 8);
    defer buf.deinit();
    const area = Rect{
        .x = smith.valueRangeAtMost(u8, 0, 14),
        .y = smith.valueRangeAtMost(u8, 0, 9),
        .width = smith.valueRangeAtMost(u8, 0, 14),
        .height = smith.valueRangeAtMost(u8, 0, 9),
    };
    heatmap.render(&buf, area);
    buf.check_invariants();

    // Nothing is ever drawn left of or above the area.
    for (0..8) |y| {
        for (0..12) |x| {
            if (x < area.x or y < area.y) try expectUntouched(buf, @intCast(x), @intCast(y));
        }
    }
}

test "heatmap: fuzz render never panics and never draws outside the area's origin" {
    try testing.fuzz({}, fuzzRender, .{});
}
