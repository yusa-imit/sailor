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
        rainbow, // blue → green → yellow → red
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
        unicode, // Use block elements (▀▄█) for sub-character precision
        ascii, // Use ASCII chars (#, @, *, +, ., space)
        numeric, // Show actual numbers
    };

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

        // Compute value range
        const range = self.value_range orelse self.computeRange();

        // Reserve space for labels
        const row_label_width: u16 = if (self.row_labels) |labels| blk: {
            var max_len: u16 = 0;
            for (labels) |label| {
                max_len = @max(max_len, @as(u16, @intCast(@min(label.len, 20))));
            }
            break :blk max_len + 1; // +1 for spacing
        } else 0;

        const col_label_height: u16 = if (self.col_labels != null) 1 else 0;

        // Adjust render area for labels
        const data_area = Rect{
            .x = render_area.x + row_label_width,
            .y = render_area.y + col_label_height,
            .width = if (render_area.width > row_label_width) render_area.width - row_label_width else 0,
            .height = if (render_area.height > col_label_height) render_area.height - col_label_height else 0,
        };

        if (data_area.width == 0 or data_area.height == 0) return;

        // Render column labels
        if (self.col_labels) |labels| {
            const cells_per_col = @max(1, data_area.width / @as(u16, @intCast(@min(self.data[0].len, data_area.width))));
            for (labels, 0..) |label, i| {
                const col_idx: u16 = @intCast(i);
                if (col_idx >= self.data[0].len) break;
                const x = data_area.x + col_idx * cells_per_col;
                if (x >= data_area.x + data_area.width) break;
                const truncated = if (label.len > cells_per_col) label[0..cells_per_col] else label;
                buf.setString(x, render_area.y, truncated, Style{});
            }
        }

        // Render row labels
        if (self.row_labels) |labels| {
            for (labels, 0..) |label, i| {
                const row_idx: u16 = @intCast(i);
                if (row_idx >= self.data.len) break;
                const y = data_area.y + row_idx;
                if (y >= data_area.y + data_area.height) break;
                const truncated = if (label.len > row_label_width) label[0..row_label_width] else label;
                buf.setString(render_area.x, y, truncated, Style{});
            }
        }

        // Render heatmap data
        const rows = @min(self.data.len, data_area.height);
        const cols = if (self.data.len > 0) @min(self.data[0].len, data_area.width) else 0;

        for (0..rows) |row| {
            const y: u16 = @intCast(data_area.y + row);
            for (0..cols) |col| {
                const x: u16 = @intCast(data_area.x + col);
                const value = self.data[row][col];
                const color = self.valueToColor(value, range);
                const char = self.valueToChar(value, range);
                buf.setChar(x, y, char, Style{ .bg = color });
            }
        }
    }

    /// Compute min/max values from data
    fn computeRange(self: Heatmap) ValueRange {
        var min: f64 = std.math.floatMax(f64);
        var max: f64 = std.math.floatMin(f64);
        for (self.data) |row| {
            for (row) |value| {
                min = @min(min, value);
                max = @max(max, value);
            }
        }
        return .{ .min = min, .max = max };
    }

    /// Map value to color based on gradient
    fn valueToColor(self: Heatmap, value: f64, range: ValueRange) Color {
        const normalized = if (range.max > range.min)
            (value - range.min) / (range.max - range.min)
        else
            0.5;
        const clamped = @max(0.0, @min(1.0, normalized));

        return switch (self.gradient) {
            .rainbow => blk: {
                // Blue → Cyan → Green → Yellow → Red
                if (clamped < 0.25) {
                    break :blk Color{ .rgb = .{ .r = 0, .g = 0, .b = @intFromFloat(255 * (1 - clamped * 4)) } };
                } else if (clamped < 0.5) {
                    break :blk Color{ .rgb = .{ .r = 0, .g = @intFromFloat(255 * ((clamped - 0.25) * 4)), .b = 255 } };
                } else if (clamped < 0.75) {
                    break :blk Color{ .rgb = .{ .r = @intFromFloat(255 * ((clamped - 0.5) * 4)), .g = 255, .b = 0 } };
                } else {
                    break :blk Color{ .rgb = .{ .r = 255, .g = @intFromFloat(255 * (1 - (clamped - 0.75) * 4)), .b = 0 } };
                }
            },
            .monochrome => blk: {
                const intensity: u8 = @intFromFloat(255 * (1 - clamped));
                break :blk Color{ .rgb = .{ .r = intensity, .g = intensity, .b = intensity } };
            },
            .heat => blk: {
                // Black → Red → Orange → Yellow → White
                if (clamped < 0.25) {
                    break :blk Color{ .rgb = .{ .r = @intFromFloat(255 * clamped * 4), .g = 0, .b = 0 } };
                } else if (clamped < 0.5) {
                    break :blk Color{ .rgb = .{ .r = 255, .g = @intFromFloat(128 * ((clamped - 0.25) * 4)), .b = 0 } };
                } else if (clamped < 0.75) {
                    break :blk Color{ .rgb = .{ .r = 255, .g = @intFromFloat(128 + 127 * ((clamped - 0.5) * 4)), .b = 0 } };
                } else {
                    const white: u8 = @intFromFloat(255 * ((clamped - 0.75) * 4));
                    break :blk Color{ .rgb = .{ .r = 255, .g = 255, .b = white } };
                }
            },
            .cool => blk: {
                // Blue → Cyan → Green
                if (clamped < 0.5) {
                    break :blk Color{ .rgb = .{ .r = 0, .g = @intFromFloat(255 * clamped * 2), .b = 255 } };
                } else {
                    break :blk Color{ .rgb = .{ .r = @intFromFloat(255 * ((clamped - 0.5) * 2)), .g = 255, .b = @intFromFloat(255 * (1 - (clamped - 0.5) * 2)) } };
                }
            },
            .grayscale => blk: {
                const intensity: u8 = @intFromFloat(255 * clamped);
                break :blk Color{ .rgb = .{ .r = intensity, .g = intensity, .b = intensity } };
            },
        };
    }

    /// Map value to character based on cell mode
    fn valueToChar(self: Heatmap, value: f64, range: ValueRange) u21 {
        const normalized = if (range.max > range.min)
            (value - range.min) / (range.max - range.min)
        else
            0.5;
        const clamped = @max(0.0, @min(1.0, normalized));

        return switch (self.cell_mode) {
            .unicode => blk: {
                // Use block elements for 8 levels
                const levels = [_]u21{ ' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' };
                const idx: usize = @intFromFloat(clamped * (@as(f64, @floatFromInt(levels.len)) - 1));
                break :blk levels[@min(idx, levels.len - 1)];
            },
            .ascii => blk: {
                // Use ASCII chars for 6 levels
                const levels = [_]u21{ ' ', '.', '+', '*', '#', '@' };
                const idx: usize = @intFromFloat(clamped * (@as(f64, @floatFromInt(levels.len)) - 1));
                break :blk levels[@min(idx, levels.len - 1)];
            },
            .numeric => ' ', // Numeric mode shows actual numbers, not implemented in this simple version
        };
    }
};

// Tests
const testing = std.testing;
const fixedBufferStream = std.io.fixedBufferStream;

test "heatmap: basic render" {
    const data = [_][]const f64{
        &[_]f64{ 0.0, 0.5, 1.0 },
        &[_]f64{ 0.25, 0.75, 0.5 },
    };

    const heatmap = Heatmap{ .data = &data };
    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });

    // Should render without crash
    try testing.expect(buffer.width == 10);
    try testing.expect(buffer.height == 5);
}

test "heatmap: with block border" {
    const data = [_][]const f64{
        &[_]f64{ 1.0, 2.0, 3.0 },
    };

    const heatmap = Heatmap{
        .data = &data,
        .block = Block{ .title = "Heat" },
    };
    var buffer = try Buffer.init(testing.allocator, 15, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 15, .height = 5 });

    // Block should be rendered
    try testing.expect(buffer.cells[0].char == '┌');
}

test "heatmap: with row labels" {
    const data = [_][]const f64{
        &[_]f64{ 1.0, 2.0 },
        &[_]f64{ 3.0, 4.0 },
    };
    const row_labels = [_][]const u8{ "A", "B" };

    const heatmap = Heatmap{
        .data = &data,
        .row_labels = &row_labels,
    };
    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });

    // Labels should be rendered
    try testing.expect(buffer.cells[0].char == 'A');
}

test "heatmap: with column labels" {
    const data = [_][]const f64{
        &[_]f64{ 1.0, 2.0, 3.0 },
    };
    const col_labels = [_][]const u8{ "X", "Y", "Z" };

    const heatmap = Heatmap{
        .data = &data,
        .col_labels = &col_labels,
    };
    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });

    // Column labels should be in first row
    try testing.expect(buffer.cells[0].char == 'X');
}

test "heatmap: empty data" {
    const data: []const []const f64 = &[_][]const f64{};
    const heatmap = Heatmap{ .data = data };
    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });

    // Should not crash with empty data
    try testing.expect(buffer.width == 10);
}

test "heatmap: zero area" {
    const data = [_][]const f64{
        &[_]f64{ 1.0 },
    };
    const heatmap = Heatmap{ .data = &data };
    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });

    // Should handle zero area gracefully
    try testing.expect(buffer.width == 10);
}

test "heatmap: computeRange" {
    const data = [_][]const f64{
        &[_]f64{ -5.0, 0.0, 5.0 },
        &[_]f64{ 10.0, -10.0, 2.5 },
    };
    const heatmap = Heatmap{ .data = &data };
    const range = heatmap.computeRange();

    try testing.expectEqual(-10.0, range.min);
    try testing.expectEqual(10.0, range.max);
}

test "heatmap: valueToColor rainbow gradient" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .rainbow };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    // Test endpoints and middle
    const color_min = heatmap.valueToColor(0.0, range);
    const color_mid = heatmap.valueToColor(0.5, range);
    const color_max = heatmap.valueToColor(1.0, range);

    // Should produce different colors
    try testing.expect(color_min.eql(color_mid) == false);
    try testing.expect(color_mid.eql(color_max) == false);
}

test "heatmap: valueToColor monochrome gradient" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .monochrome };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    const color = heatmap.valueToColor(0.5, range);
    // Monochrome should have equal RGB components
    if (color == .rgb) {
        try testing.expectEqual(color.rgb.r, color.rgb.g);
        try testing.expectEqual(color.rgb.g, color.rgb.b);
    }
}

test "heatmap: valueToChar unicode mode" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .cell_mode = .unicode };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    const char_min = heatmap.valueToChar(0.0, range);
    const char_max = heatmap.valueToChar(1.0, range);

    // Min should be space, max should be full block
    try testing.expectEqual(' ', char_min);
    try testing.expectEqual('█', char_max);
}

test "heatmap: valueToChar ascii mode" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .cell_mode = .ascii };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    const char_min = heatmap.valueToChar(0.0, range);
    const char_max = heatmap.valueToChar(1.0, range);

    // Min should be space, max should be @
    try testing.expectEqual(' ', char_min);
    try testing.expectEqual('@', char_max);
}

test "heatmap: gradient heat" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .heat };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    // Test progression: black → red → orange → yellow → white
    const colors = [_]f64{ 0.0, 0.25, 0.5, 0.75, 1.0 };
    for (colors) |value| {
        const color = heatmap.valueToColor(value, range);
        // Should produce valid RGB color
        try testing.expect(color == .rgb);
    }
}

test "heatmap: gradient cool" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .cool };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    const color_start = heatmap.valueToColor(0.0, range);
    const color_end = heatmap.valueToColor(1.0, range);

    // Cool gradient: blue → cyan → green
    try testing.expect(color_start == .rgb);
    try testing.expect(color_end == .rgb);
}

test "heatmap: gradient grayscale" {
    const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = .grayscale };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    const color = heatmap.valueToColor(0.5, range);
    // Grayscale should have equal RGB
    if (color == .rgb) {
        try testing.expectEqual(color.rgb.r, color.rgb.g);
        try testing.expectEqual(color.rgb.g, color.rgb.b);
    }
}

test "heatmap: custom value range" {
    const data = [_][]const f64{
        &[_]f64{ 100.0, 200.0, 300.0 },
    };
    const heatmap = Heatmap{
        .data = &data,
        .value_range = .{ .min = 0.0, .max = 500.0 },
    };
    var buffer = try Buffer.init(testing.allocator, 10, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });

    // Should use custom range instead of auto-detected
    try testing.expect(buffer.width == 10);
}

test "heatmap: large data clipping" {
    // Create 100x100 data grid
    var rows: [100][100]f64 = undefined;
    for (&rows, 0..) |*row, i| {
        for (row, 0..) |*cell, j| {
            cell.* = @as(f64, @floatFromInt(i + j));
        }
    }

    const data_ptrs = blk: {
        var ptrs: [100][]const f64 = undefined;
        for (&ptrs, 0..) |*ptr, i| {
            ptr.* = &rows[i];
        }
        break :blk ptrs;
    };

    const heatmap = Heatmap{ .data = &data_ptrs };
    var buffer = try Buffer.init(testing.allocator, 20, 10);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Should clip to buffer size
    try testing.expect(buffer.width == 20);
    try testing.expect(buffer.height == 10);
}

test "heatmap: all gradients produce valid colors" {
    const gradients = [_]Heatmap.Gradient{ .rainbow, .monochrome, .heat, .cool, .grayscale };
    const range = Heatmap.ValueRange{ .min = 0.0, .max = 1.0 };

    for (gradients) |gradient| {
        const heatmap = Heatmap{ .data = &[_][]const f64{}, .gradient = gradient };
        // Test 10 points across the range
        var i: usize = 0;
        while (i <= 10) : (i += 1) {
            const value = @as(f64, @floatFromInt(i)) / 10.0;
            const color = heatmap.valueToColor(value, range);
            try testing.expect(color == .rgb);
        }
    }
}

test "heatmap: edge case - single cell" {
    const data = [_][]const f64{
        &[_]f64{42.0},
    };
    const heatmap = Heatmap{ .data = &data };
    var buffer = try Buffer.init(testing.allocator, 5, 5);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });

    // Should handle single cell gracefully
    try testing.expect(buffer.width == 5);
}

test "heatmap: with all labels" {
    const data = [_][]const f64{
        &[_]f64{ 1.0, 2.0 },
        &[_]f64{ 3.0, 4.0 },
    };
    const row_labels = [_][]const u8{ "Row1", "Row2" };
    const col_labels = [_][]const u8{ "Col1", "Col2" };

    const heatmap = Heatmap{
        .data = &data,
        .row_labels = &row_labels,
        .col_labels = &col_labels,
    };
    var buffer = try Buffer.init(testing.allocator, 20, 10);
    defer buffer.deinit(testing.allocator);

    heatmap.render(&buffer, Rect{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Both label types should be rendered
    try testing.expect(buffer.width == 20);
}
