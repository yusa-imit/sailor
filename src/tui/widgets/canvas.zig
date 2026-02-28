const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const symbols = @import("../symbols.zig");

/// Canvas widget for freeform drawing using Braille dots (2x4 per cell)
/// Provides pixel-like precision for custom visualizations
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
        const dx = if (x1 > x0) x1 - x0 else x0 - x1;
        const dy = if (y1 > y0) y1 - y0 else y0 - y1;
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;

        var err: i32 = @as(i32, dx) - @as(i32, dy);
        var x: i32 = @intCast(x0);
        var y: i32 = @intCast(y0);
        const x1_i: i32 = @intCast(x1);
        const y1_i: i32 = @intCast(y1);

        while (true) {
            if (x >= 0 and y >= 0) {
                self.setDot(@intCast(x), @intCast(y));
            }

            if (x == x1_i and y == y1_i) break;

            const e2 = err * 2;
            if (e2 > -@as(i32, dy)) {
                err -= @as(i32, dy);
                x += sx;
            }
            if (e2 < @as(i32, dx)) {
                err += @as(i32, dx);
                y += sy;
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
                try buf.setCell(x, y, char, self.style);
            }
        }
    }
};

// Tests
test "Canvas.init and deinit" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    try std.testing.expectEqual(20, canvas.dot_width); // 10 * 2
    try std.testing.expectEqual(20, canvas.dot_height); // 5 * 4
    try std.testing.expectEqual(400, canvas.dots.len); // 20 * 20
}

test "Canvas.setDot and getDot" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    try std.testing.expectEqual(false, canvas.getDot(0, 0));
    canvas.setDot(0, 0);
    try std.testing.expectEqual(true, canvas.getDot(0, 0));

    canvas.setDot(5, 5);
    try std.testing.expectEqual(true, canvas.getDot(5, 5));
}

test "Canvas.clear" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    canvas.setDot(0, 0);
    canvas.setDot(1, 1);
    canvas.setDot(2, 2);
    try std.testing.expectEqual(true, canvas.getDot(1, 1));

    canvas.clear();
    try std.testing.expectEqual(false, canvas.getDot(0, 0));
    try std.testing.expectEqual(false, canvas.getDot(1, 1));
    try std.testing.expectEqual(false, canvas.getDot(2, 2));
}

test "Canvas.drawLine horizontal" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    canvas.drawLine(0, 0, 5, 0);

    try std.testing.expectEqual(true, canvas.getDot(0, 0));
    try std.testing.expectEqual(true, canvas.getDot(2, 0));
    try std.testing.expectEqual(true, canvas.getDot(5, 0));
    try std.testing.expectEqual(false, canvas.getDot(0, 1));
}

test "Canvas.drawLine vertical" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    canvas.drawLine(0, 0, 0, 5);

    try std.testing.expectEqual(true, canvas.getDot(0, 0));
    try std.testing.expectEqual(true, canvas.getDot(0, 2));
    try std.testing.expectEqual(true, canvas.getDot(0, 5));
    try std.testing.expectEqual(false, canvas.getDot(1, 0));
}

test "Canvas.drawLine diagonal" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    canvas.drawLine(0, 0, 5, 5);

    try std.testing.expectEqual(true, canvas.getDot(0, 0));
    try std.testing.expectEqual(true, canvas.getDot(2, 2));
    try std.testing.expectEqual(true, canvas.getDot(5, 5));
}

test "Canvas.drawRect" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    canvas.drawRect(2, 2, 5, 4);

    // Top edge
    try std.testing.expectEqual(true, canvas.getDot(2, 2));
    try std.testing.expectEqual(true, canvas.getDot(6, 2));

    // Bottom edge
    try std.testing.expectEqual(true, canvas.getDot(2, 5));
    try std.testing.expectEqual(true, canvas.getDot(6, 5));

    // Left edge
    try std.testing.expectEqual(true, canvas.getDot(2, 3));

    // Right edge
    try std.testing.expectEqual(true, canvas.getDot(6, 3));

    // Interior should be empty
    try std.testing.expectEqual(false, canvas.getDot(3, 3));
}

test "Canvas.fillRect" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    canvas.fillRect(2, 2, 3, 3);

    // All interior points should be set
    try std.testing.expectEqual(true, canvas.getDot(2, 2));
    try std.testing.expectEqual(true, canvas.getDot(3, 3));
    try std.testing.expectEqual(true, canvas.getDot(4, 4));

    // Outside should not be set
    try std.testing.expectEqual(false, canvas.getDot(1, 2));
    try std.testing.expectEqual(false, canvas.getDot(5, 2));
}

test "Canvas.drawCircle" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    canvas.drawCircle(20, 20, 10);

    // Check some points on the circle
    try std.testing.expectEqual(true, canvas.getDot(20, 10)); // top
    try std.testing.expectEqual(true, canvas.getDot(20, 30)); // bottom
    try std.testing.expectEqual(true, canvas.getDot(10, 20)); // left
    try std.testing.expectEqual(true, canvas.getDot(30, 20)); // right

    // Center should not be set (outline only)
    try std.testing.expectEqual(false, canvas.getDot(20, 20));
}

test "Canvas.render" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 3 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    // Draw some dots
    canvas.setDot(0, 0); // Top-left of cell (0,0) - Braille dot 1
    canvas.setDot(1, 0); // Top-right of cell (0,0) - Braille dot 4

    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try canvas.render(&buf, area);

    // Cell (0,0) should have Braille pattern with dots 1 and 4 set
    // Pattern: 0x01 | 0x08 = 0x09
    const cell = buf.getCell(0, 0);
    try std.testing.expectEqual(symbols.Braille.pattern(0x09), cell.char);
}

test "Canvas.render complex pattern" {
    const allocator = std.testing.allocator;
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 2 };

    var canvas = try Canvas.init(allocator, area);
    defer canvas.deinit();

    // Draw a diagonal line
    canvas.drawLine(0, 0, 5, 7);

    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try canvas.render(&buf, area);

    // At least the start and end points should be visible
    const cell_start = buf.getCell(0, 0);
    const cell_end = buf.getCell(2, 1);

    // Both cells should have non-empty Braille patterns
    try std.testing.expect(cell_start.char != symbols.Braille.pattern(0));
    try std.testing.expect(cell_end.char != symbols.Braille.pattern(0));
}
