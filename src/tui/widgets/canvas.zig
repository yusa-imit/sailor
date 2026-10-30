//! Canvas widget for freeform drawing at sub-cell resolution using Braille dots (2x4 per cell).
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const symbols = @import("../symbols.zig");
const line_iter_mod = @import("../line_iter.zig");

/// Canvas widget for freeform drawing using Braille dots (2x4 per cell)
/// Provides pixel-like precision for custom visualizations
///
/// Example: Drawing a simple plot
/// ```zig
/// var canvas = try Canvas.init(allocator, area);
/// defer canvas.deinit();
///
/// // Draw axes
/// canvas.drawLine(0, 20, 40, 20); // X-axis
/// canvas.drawLine(5, 0, 5, 40);   // Y-axis
///
/// // Plot data points
/// const data = [_]struct{ x: u16, y: u16 }{
///     .{ .x = 10, .y = 15 },
///     .{ .x = 20, .y = 10 },
///     .{ .x = 30, .y = 25 },
/// };
/// for (data) |pt| canvas.setDot(pt.x, pt.y);
///
/// try canvas.render(&buf, area);
/// ```
///
/// Example: Drawing shapes with Block integration
/// ```zig
/// // Create canvas with border
/// var block = Block{
///     .title = "Canvas Demo",
///     .borders = Borders.all,
/// };
/// block.render(&buf, area);
///
/// const inner = block.inner(area);
/// var canvas = try Canvas.init(allocator, inner);
/// defer canvas.deinit();
///
/// // Draw a smiley face
/// canvas.drawCircle(20, 20, 15);           // Face outline
/// canvas.fillRect(12, 14, 3, 3);           // Left eye
/// canvas.fillRect(24, 14, 3, 3);           // Right eye
/// canvas.drawLine(14, 26, 26, 26);         // Smile
///
/// try canvas.render(&buf, inner);
/// ```
pub const Canvas = struct {
    /// Braille dot buffer (width * height in dots, not cells)
    dots: []bool,
    /// Width in dots (cells * 2)
    dot_width: u16,
    /// Height in dots (cells * 4)
    dot_height: u16,
    /// Style for drawn elements
    style: Style,
    allocator: std.mem.Allocator,

    /// Initialize a canvas for the given area
    /// Area dimensions are in terminal cells; canvas uses 2x4 dots per cell
    pub fn init(allocator: std.mem.Allocator, area: Rect) !Canvas {
        const dot_width = area.width * 2;
        const dot_height = area.height * 4;
        const total_dots = @as(usize, dot_width) * @as(usize, dot_height);

        const dots = try allocator.alloc(bool, total_dots);
        @memset(dots, false);

        return Canvas{
            .dots = dots,
            .dot_width = dot_width,
            .dot_height = dot_height,
            .style = Style{},
            .allocator = allocator,
        };
    }

    /// Free canvas dot buffer.
    pub fn deinit(self: *Canvas) void {
        self.allocator.free(self.dots);
    }

    /// Set a single dot at (x, y) coordinates
    pub fn setDot(self: *Canvas, x: u16, y: u16) void {
        if (x >= self.dot_width or y >= self.dot_height) return;
        const idx = @as(usize, y) * @as(usize, self.dot_width) + @as(usize, x);
        self.dots[idx] = true;
    }

    /// Clear a single dot at (x, y) coordinates
    pub fn clearDot(self: *Canvas, x: u16, y: u16) void {
        if (x >= self.dot_width or y >= self.dot_height) return;
        const idx = @as(usize, y) * @as(usize, self.dot_width) + @as(usize, x);
        self.dots[idx] = false;
    }

    /// Get dot state at (x, y)
    pub fn getDot(self: Canvas, x: u16, y: u16) bool {
        if (x >= self.dot_width or y >= self.dot_height) return false;
        const idx = @as(usize, y) * @as(usize, self.dot_width) + @as(usize, x);
        return self.dots[idx];
    }

    /// Clear all dots
    pub fn clear(self: *Canvas) void {
        @memset(self.dots, false);
    }

    /// Draw a line from (x0, y0) to (x1, y1) using Bresenham's algorithm
    pub fn drawLine(self: *Canvas, x0: u16, y0: u16, x1: u16, y1: u16) void {
        var line = line_iter_mod.LineIter.init(x0, y0, x1, y1);
        while (line.next()) |point| {
            if (point.x >= 0 and point.y >= 0) {
                self.setDot(@intCast(point.x), @intCast(point.y));
            }
        }
    }

    /// Draw a rectangle outline
    pub fn drawRect(self: *Canvas, x: u16, y: u16, width: u16, height: u16) void {
        if (width == 0 or height == 0) return;

        // Top and bottom edges
        for (0..width) |i| {
            const xi: u16 = @intCast(i);
            self.setDot(x + xi, y);
            if (height > 1) {
                self.setDot(x + xi, y + height - 1);
            }
        }

        // Left and right edges
        for (0..height) |i| {
            const yi: u16 = @intCast(i);
            self.setDot(x, y + yi);
            if (width > 1) {
                self.setDot(x + width - 1, y + yi);
            }
        }
    }

    /// Draw a filled rectangle
    pub fn fillRect(self: *Canvas, x: u16, y: u16, width: u16, height: u16) void {
        for (0..height) |dy| {
            for (0..width) |dx| {
                self.setDot(x + @as(u16, @intCast(dx)), y + @as(u16, @intCast(dy)));
            }
        }
    }

    /// Draw a circle outline using midpoint circle algorithm
    pub fn drawCircle(self: *Canvas, cx: u16, cy: u16, radius: u16) void {
        if (radius == 0) {
            self.setDot(cx, cy);
            return;
        }

        var x: i32 = 0;
        var y: i32 = @intCast(radius);
        var d: i32 = 3 - 2 * @as(i32, radius);

        while (x <= y) {
            self.setCirclePoints(cx, cy, x, y);
            x += 1;
            if (d > 0) {
                y -= 1;
                d = d + 4 * (x - y) + 10;
            } else {
                d = d + 4 * x + 6;
            }
        }
    }

    fn setCirclePoints(self: *Canvas, cx: u16, cy: u16, x: i32, y: i32) void {
        const points = [_][2]i32{
            .{ @as(i32, cx) + x, @as(i32, cy) + y },
            .{ @as(i32, cx) - x, @as(i32, cy) + y },
            .{ @as(i32, cx) + x, @as(i32, cy) - y },
            .{ @as(i32, cx) - x, @as(i32, cy) - y },
            .{ @as(i32, cx) + y, @as(i32, cy) + x },
            .{ @as(i32, cx) - y, @as(i32, cy) + x },
            .{ @as(i32, cx) + y, @as(i32, cy) - x },
            .{ @as(i32, cx) - y, @as(i32, cy) - x },
        };

        for (points) |pt| {
            if (pt[0] >= 0 and pt[1] >= 0) {
                self.setDot(@intCast(pt[0]), @intCast(pt[1]));
            }
        }
    }

    /// Render the canvas to the buffer
    pub fn render(self: Canvas, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Each cell contains 2x4 Braille dots
        // Braille dot pattern:
        // 1 4
        // 2 5
        // 3 6
        // 7 8
        for (0..area.height) |row| {
            for (0..area.width) |col| {
                const x = area.x + @as(u16, @intCast(col));
                const y = area.y + @as(u16, @intCast(row));

                // Calculate which dots in our canvas map to this cell
                const dot_x = @as(u16, @intCast(col)) * 2;
                const dot_y = @as(u16, @intCast(row)) * 4;

                // Build Braille pattern byte
                var pattern: u8 = 0;

                // Dot 1 (top-left)
                if (self.getDot(dot_x, dot_y)) pattern |= 0x01;
                // Dot 2
                if (dot_y + 1 < self.dot_height and self.getDot(dot_x, dot_y + 1)) pattern |= 0x02;
                // Dot 3
                if (dot_y + 2 < self.dot_height and self.getDot(dot_x, dot_y + 2)) pattern |= 0x04;
                // Dot 7
                if (dot_y + 3 < self.dot_height and self.getDot(dot_x, dot_y + 3)) pattern |= 0x40;

                // Dot 4 (top-right)
                if (dot_x + 1 < self.dot_width and self.getDot(dot_x + 1, dot_y)) pattern |= 0x08;
                // Dot 5
                if (dot_x + 1 < self.dot_width and dot_y + 1 < self.dot_height and
                    self.getDot(dot_x + 1, dot_y + 1)) pattern |= 0x10;
                // Dot 6
                if (dot_x + 1 < self.dot_width and dot_y + 2 < self.dot_height and
                    self.getDot(dot_x + 1, dot_y + 2)) pattern |= 0x20;
                // Dot 8
                if (dot_x + 1 < self.dot_width and dot_y + 3 < self.dot_height and
                    self.getDot(dot_x + 1, dot_y + 3)) pattern |= 0x80;

                const char = symbols.Braille.pattern(pattern);
                buf.set(x, y, .{ .char = char, .style = self.style });
            }
        }
    }
};

// Tests

/// Reference Braille bit for the dot at (dx, dy) inside one 2x4 cell.
fn brailleBit(dx: usize, dy: usize) u8 {
    const table = [2][4]u8{
        .{ 0x01, 0x02, 0x04, 0x40 },
        .{ 0x08, 0x10, 0x20, 0x80 },
    };
    return table[dx][dy];
}

/// Reference model: the Braille pattern a cell must show, computed from `getDot` alone.
fn expectedPattern(canvas: Canvas, col: u16, row: u16) u8 {
    var pattern: u8 = 0;
    for (0..2) |dx| {
        for (0..4) |dy| {
            const x: u16 = col * 2 + @as(u16, @intCast(dx));
            const y: u16 = row * 4 + @as(u16, @intCast(dy));
            if (canvas.getDot(x, y)) pattern |= brailleBit(dx, dy);
        }
    }
    return pattern;
}

fn countSet(canvas: Canvas) usize {
    var n: usize = 0;
    for (canvas.dots) |d| {
        if (d) n += 1;
    }
    return n;
}

test "canvas: init allocates 2x4 dots per cell, all clear" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    try std.testing.expectEqual(@as(u16, 20), canvas.dot_width);
    try std.testing.expectEqual(@as(u16, 20), canvas.dot_height);
    try std.testing.expectEqual(@as(usize, 400), canvas.dots.len);
    try std.testing.expectEqual(@as(usize, 0), countSet(canvas));
}

test "canvas: zero-sized area yields an empty canvas that ignores every dot" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 0, .height = 3 });
    defer canvas.deinit();

    try std.testing.expectEqual(@as(usize, 0), canvas.dots.len);
    canvas.setDot(0, 0);
    try std.testing.expect(!canvas.getDot(0, 0));
}

test "canvas: setDot sets exactly one dot and out-of-bounds writes are ignored" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });
    defer canvas.deinit();

    try std.testing.expect(!canvas.getDot(3, 7));
    canvas.setDot(3, 7);
    try std.testing.expect(canvas.getDot(3, 7));
    try std.testing.expect(!canvas.getDot(2, 7));
    try std.testing.expect(!canvas.getDot(3, 6));

    // Valid range is x < 10, y < 20.
    canvas.setDot(10, 0);
    canvas.setDot(0, 20);
    canvas.setDot(std.math.maxInt(u16), std.math.maxInt(u16));
    try std.testing.expect(!canvas.getDot(10, 0));
    try std.testing.expect(!canvas.getDot(0, 20));
    try std.testing.expectEqual(@as(usize, 1), countSet(canvas));
}

test "canvas: clear resets every dot" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });
    defer canvas.deinit();

    canvas.setDot(0, 0);
    canvas.setDot(1, 1);
    canvas.setDot(9, 19);
    try std.testing.expectEqual(@as(usize, 3), countSet(canvas));
    canvas.clear();

    try std.testing.expectEqual(@as(usize, 0), countSet(canvas));
}

test "canvas: clearDot erases one dot and leaves the others" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });
    defer canvas.deinit();

    canvas.setDot(2, 3);
    canvas.setDot(4, 4);
    canvas.clearDot(2, 3);

    try std.testing.expect(!canvas.getDot(2, 3));
    try std.testing.expect(canvas.getDot(4, 4));

    // Out-of-bounds clear is a no-op.
    canvas.clearDot(100, 100);
    try std.testing.expect(canvas.getDot(4, 4));
    try std.testing.expectEqual(@as(usize, 1), countSet(canvas));
}

test "canvas: drawLine horizontal sets exactly the inclusive span" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    defer canvas.deinit();

    canvas.drawLine(0, 0, 5, 0);

    var x: u16 = 0;
    while (x < canvas.dot_width) : (x += 1) {
        try std.testing.expectEqual(x <= 5, canvas.getDot(x, 0));
        try std.testing.expect(!canvas.getDot(x, 1));
    }
}

test "canvas: drawLine vertical sets exactly the inclusive span" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    defer canvas.deinit();

    canvas.drawLine(0, 0, 0, 5);

    var y: u16 = 0;
    while (y < canvas.dot_height) : (y += 1) {
        try std.testing.expectEqual(y <= 5, canvas.getDot(0, y));
        try std.testing.expect(!canvas.getDot(1, y));
    }
}

test "canvas: drawLine diagonal sets exactly the diagonal dots" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 10 });
    defer canvas.deinit();

    canvas.drawLine(0, 0, 5, 5);

    var y: u16 = 0;
    while (y < 8) : (y += 1) {
        var x: u16 = 0;
        while (x < 8) : (x += 1) {
            try std.testing.expectEqual(x == y and x <= 5, canvas.getDot(x, y));
        }
    }
}

test "canvas: drawLine reversed direction draws the same dots" {
    const allocator = std.testing.allocator;
    var fwd = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 6, .height = 4 });
    defer fwd.deinit();
    var rev = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 6, .height = 4 });
    defer rev.deinit();

    fwd.drawLine(0, 0, 9, 0);
    rev.drawLine(9, 0, 0, 0);

    try std.testing.expectEqualSlices(bool, fwd.dots, rev.dots);
    try std.testing.expect(fwd.getDot(0, 0));
    try std.testing.expect(fwd.getDot(9, 0));
    try std.testing.expectEqual(@as(usize, 10), countSet(fwd));
}

test "canvas: drawLine partly off canvas clips without wrapping" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 2, .height = 2 });
    defer canvas.deinit();

    // Canvas is 4x8 dots; the line runs far past the right edge.
    canvas.drawLine(0, 0, 30, 0);

    var x: u16 = 0;
    while (x < 4) : (x += 1) try std.testing.expect(canvas.getDot(x, 0));
    try std.testing.expectEqual(@as(usize, 4), countSet(canvas));
}

test "canvas: drawRect draws only the outline" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 10 });
    defer canvas.deinit();

    canvas.drawRect(2, 2, 5, 4);

    var y: u16 = 0;
    while (y < 12) : (y += 1) {
        var x: u16 = 0;
        while (x < 12) : (x += 1) {
            const in_box = x >= 2 and x <= 6 and y >= 2 and y <= 5;
            const on_edge = in_box and (x == 2 or x == 6 or y == 2 or y == 5);
            try std.testing.expectEqual(on_edge, canvas.getDot(x, y));
        }
    }
}

test "canvas: drawRect with zero width or height draws nothing" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });
    defer canvas.deinit();

    canvas.drawRect(1, 1, 0, 3);
    canvas.drawRect(1, 1, 3, 0);

    try std.testing.expectEqual(@as(usize, 0), countSet(canvas));
}

test "canvas: drawRect of width 1 is a vertical line" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });
    defer canvas.deinit();

    canvas.drawRect(3, 2, 1, 4);

    var y: u16 = 0;
    while (y < 10) : (y += 1) {
        try std.testing.expectEqual(y >= 2 and y <= 5, canvas.getDot(3, y));
        try std.testing.expect(!canvas.getDot(2, y));
        try std.testing.expect(!canvas.getDot(4, y));
    }
}

test "canvas: fillRect sets exactly the filled block" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 10 });
    defer canvas.deinit();

    canvas.fillRect(2, 2, 3, 3);

    var y: u16 = 0;
    while (y < 8) : (y += 1) {
        var x: u16 = 0;
        while (x < 8) : (x += 1) {
            const inside = x >= 2 and x <= 4 and y >= 2 and y <= 4;
            try std.testing.expectEqual(inside, canvas.getDot(x, y));
        }
    }
}

test "canvas: drawCircle radius 0 is a single dot" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });
    defer canvas.deinit();

    canvas.drawCircle(4, 6, 0);

    try std.testing.expectEqual(@as(usize, 1), countSet(canvas));
    try std.testing.expect(canvas.getDot(4, 6));
}

test "canvas: drawCircle is a symmetric outline with an empty center" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 20, .height = 20 });
    defer canvas.deinit();

    canvas.drawCircle(20, 20, 10);

    // Cardinal points at distance == radius.
    try std.testing.expect(canvas.getDot(20, 10));
    try std.testing.expect(canvas.getDot(20, 30));
    try std.testing.expect(canvas.getDot(10, 20));
    try std.testing.expect(canvas.getDot(30, 20));

    // Interior and exterior are empty.
    try std.testing.expect(!canvas.getDot(20, 20));
    try std.testing.expect(!canvas.getDot(20, 25));
    try std.testing.expect(!canvas.getDot(20, 9));

    // Every set dot sits within one dot of the radius and is mirrored about the center.
    try std.testing.expect(countSet(canvas) > 0);
    var y: u16 = 0;
    while (y < canvas.dot_height) : (y += 1) {
        var x: u16 = 0;
        while (x < canvas.dot_width) : (x += 1) {
            if (!canvas.getDot(x, y)) continue;
            const dx: f32 = @as(f32, @floatFromInt(x)) - 20.0;
            const dy: f32 = @as(f32, @floatFromInt(y)) - 20.0;
            const dist = @sqrt(dx * dx + dy * dy);
            try std.testing.expect(@abs(dist - 10.0) <= 1.0);
            try std.testing.expect(canvas.getDot(40 - x, y));
            try std.testing.expect(canvas.getDot(x, 40 - y));
        }
    }
}

test "canvas: drawCircle near the origin clips negative coordinates" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 5, .height = 5 });
    defer canvas.deinit();

    canvas.drawCircle(0, 0, 4);

    // Only the first quadrant survives: cardinal points on the axes.
    try std.testing.expect(canvas.getDot(4, 0));
    try std.testing.expect(canvas.getDot(0, 4));
    try std.testing.expect(!canvas.getDot(0, 0));
}

test "canvas: render maps dots 1 and 4 of a cell to Braille 0x2809" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();
    canvas.setDot(0, 0);
    canvas.setDot(1, 0);

    var buf = try Buffer.init(allocator, 5, 3);
    defer buf.deinit();
    try canvas.render(&buf, area);

    try std.testing.expectEqual(@as(u21, 0x2809), buf.getConst(0, 0).?.char);
    // Every other cell is the empty Braille glyph.
    for (0..3) |row| {
        for (0..5) |col| {
            if (row == 0 and col == 0) continue;
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            try std.testing.expectEqual(@as(u21, 0x2800), cell.char);
        }
    }
}

test "canvas: render maps each of the eight dots to its Braille bit" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };

    // Standard Braille numbering: dots 1-3 and 7 in the left column, 4-6 and 8 in the right.
    const cases = [_]struct { dx: u16, dy: u16, bit: u8 }{
        .{ .dx = 0, .dy = 0, .bit = 0x01 },
        .{ .dx = 0, .dy = 1, .bit = 0x02 },
        .{ .dx = 0, .dy = 2, .bit = 0x04 },
        .{ .dx = 1, .dy = 0, .bit = 0x08 },
        .{ .dx = 1, .dy = 1, .bit = 0x10 },
        .{ .dx = 1, .dy = 2, .bit = 0x20 },
        .{ .dx = 0, .dy = 3, .bit = 0x40 },
        .{ .dx = 1, .dy = 3, .bit = 0x80 },
    };
    for (cases) |c| {
        var canvas = try Canvas.init(allocator, area);
        defer canvas.deinit();
        canvas.setDot(c.dx, c.dy);

        var buf = try Buffer.init(allocator, 1, 1);
        defer buf.deinit();
        try canvas.render(&buf, area);

        try std.testing.expectEqual(@as(u21, 0x2800) + c.bit, buf.getConst(0, 0).?.char);
    }
}

test "canvas: render of a fully filled canvas is the full Braille glyph" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();
    canvas.fillRect(0, 0, 4, 8);

    var buf = try Buffer.init(allocator, 2, 2);
    defer buf.deinit();
    try canvas.render(&buf, area);

    try std.testing.expectEqual(@as(usize, 4), buf.cells.len);
    for (buf.cells) |cell| try std.testing.expectEqual(@as(u21, 0x28FF), cell.char);
}

test "canvas: render of a diagonal line matches the reference per-cell pattern" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 2 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();
    canvas.drawLine(0, 0, 5, 7);

    var buf = try Buffer.init(allocator, 3, 2);
    defer buf.deinit();
    try canvas.render(&buf, area);

    var nonempty: usize = 0;
    for (0..2) |row| {
        for (0..3) |col| {
            const want = expectedPattern(canvas, @intCast(col), @intCast(row));
            const got = buf.getConst(@intCast(col), @intCast(row)).?.char;
            try std.testing.expectEqual(@as(u21, 0x2800) + want, got);
            if (want != 0) nonempty += 1;
        }
    }
    // The line starts in cell (0,0) with dot 1 and ends in cell (2,1) with dot 8.
    try std.testing.expect(buf.getConst(0, 0).?.char & 0x01 != 0);
    try std.testing.expect(buf.getConst(2, 1).?.char & 0x80 != 0);
    try std.testing.expect(nonempty >= 2);
}

test "canvas: render honors area offset, style, and clips to the buffer" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 2, .y = 1, .width = 2, .height = 1 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();
    canvas.style = .{ .fg = .red, .bold = true };
    canvas.setDot(0, 0);

    var buf = try Buffer.init(allocator, 6, 3);
    defer buf.deinit();
    try canvas.render(&buf, area);

    const hit = buf.getConst(2, 1).?;
    try std.testing.expectEqual(@as(u21, 0x2801), hit.char);
    try std.testing.expect(std.meta.eql(hit.style.fg, @as(?Color, .red)));
    try std.testing.expect(hit.style.bold);
    // Second cell of the area is empty Braille but still carries the style.
    const second = buf.getConst(3, 1).?;
    try std.testing.expectEqual(@as(u21, 0x2800), second.char);
    try std.testing.expect(std.meta.eql(second.style.fg, @as(?Color, .red)));
    // Cells outside the area are untouched.
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(1, 1).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(4, 1).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(2, 2).?.char);

    // A buffer smaller than the area clips silently.
    var small = try Buffer.init(allocator, 1, 1);
    defer small.deinit();
    try canvas.render(&small, area);
    try std.testing.expectEqual(@as(u21, ' '), small.getConst(0, 0).?.char);
}

test "canvas: render into a zero-sized area leaves the buffer untouched" {
    const allocator = std.testing.allocator;
    var canvas = try Canvas.init(allocator, Rect{ .x = 0, .y = 0, .width = 2, .height = 2 });
    defer canvas.deinit();
    canvas.fillRect(0, 0, 4, 8);

    var buf = try Buffer.init(allocator, 2, 2);
    defer buf.deinit();
    try canvas.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 2 });
    try canvas.render(&buf, Rect{ .x = 0, .y = 0, .width = 2, .height = 0 });

    for (buf.cells) |cell| try std.testing.expectEqual(@as(u21, ' '), cell.char);
}

test "canvas: render after clear returns every cell to empty Braille" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();
    canvas.fillRect(0, 0, 4, 8);
    canvas.clear();

    var buf = try Buffer.init(allocator, 2, 2);
    defer buf.deinit();
    try canvas.render(&buf, area);

    for (buf.cells) |cell| try std.testing.expectEqual(@as(u21, 0x2800), cell.char);
}
