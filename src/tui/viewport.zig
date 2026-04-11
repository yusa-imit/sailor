//! Viewport clipping — render only visible region for huge buffers
//!
//! Example usage:
//!
//! ```zig
//! const viewport = Viewport.init(0, 0, 80, 24); // Terminal size
//! const huge_buffer = try Buffer.init(allocator, 1000, 1000); // Huge buffer
//!
//! const visible_rect = viewport.clipRect(Rect{ .x = 100, .y = 100, .width = 200, .height = 200 });
//! // visible_rect contains only the intersection with viewport
//!
//! // Render only visible cells
//! viewport.renderClipped(huge_buffer, visible_buffer);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;

/// Viewport represents a visible window into a larger virtual buffer
pub const Viewport = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    /// Initialize viewport with position and size
    pub fn init(x: u16, y: u16, width: u16, height: u16) Viewport {
        return .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }

    /// Get viewport as a Rect
    pub fn asRect(self: Viewport) Rect {
        return Rect{
            .x = self.x,
            .y = self.y,
            .width = self.width,
            .height = self.height,
        };
    }

    /// Clip a rectangle to the visible viewport area
    /// Returns the intersection of the rect with the viewport
    pub fn clipRect(self: Viewport, rect: Rect) Rect {
        const vp = self.asRect();
        return vp.intersection(rect) orelse Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    }

    /// Check if a point is visible in the viewport
    pub fn isVisible(self: Viewport, x: u16, y: u16) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    /// Check if a rectangle intersects with the viewport
    pub fn intersects(self: Viewport, rect: Rect) bool {
        const vp = self.asRect();
        return vp.intersects(rect);
    }

    /// Render only the visible portion of a large buffer to a smaller target buffer
    /// This optimizes rendering by skipping cells outside the viewport
    pub fn renderClipped(self: Viewport, source: *const Buffer, target: *Buffer) void {
        const src_rect = Rect{ .x = 0, .y = 0, .width = source.width, .height = source.height };
        const visible = self.clipRect(src_rect);

        // Calculate offsets
        const src_offset_x = if (visible.x >= self.x) visible.x - self.x else 0;
        const src_offset_y = if (visible.y >= self.y) visible.y - self.y else 0;

        // Copy only visible cells
        var y: u16 = 0;
        while (y < visible.height) : (y += 1) {
            const src_y = visible.y + y;
            const dst_y = src_offset_y + y;

            if (dst_y >= target.height) break;

            var x: u16 = 0;
            while (x < visible.width) : (x += 1) {
                const src_x = visible.x + x;
                const dst_x = src_offset_x + x;

                if (dst_x >= target.width) break;

                const src_idx = @as(usize, src_y) * @as(usize, source.width) + @as(usize, src_x);
                const dst_idx = @as(usize, dst_y) * @as(usize, target.width) + @as(usize, dst_x);

                if (src_idx < source.cells.len and dst_idx < target.cells.len) {
                    target.cells[dst_idx] = source.cells[src_idx];
                }
            }
        }
    }

    /// Scroll the viewport by dx, dy offsets
    /// Returns the new viewport position
    pub fn scroll(self: *Viewport, dx: i32, dy: i32) void {
        // Calculate new position
        const new_x = @as(i32, self.x) + dx;
        const new_y = @as(i32, self.y) + dy;

        // Clamp to prevent overflow
        self.x = if (new_x < 0) 0 else @as(u16, @intCast(@min(new_x, std.math.maxInt(u16))));
        self.y = if (new_y < 0) 0 else @as(u16, @intCast(@min(new_y, std.math.maxInt(u16))));
    }

    /// Scroll to make a specific point visible
    /// Centers the point if possible
    pub fn scrollToPoint(self: *Viewport, x: u16, y: u16) void {
        // Calculate centered position
        const target_x = if (x >= self.width / 2) x - self.width / 2 else 0;
        const target_y = if (y >= self.height / 2) y - self.height / 2 else 0;

        self.x = target_x;
        self.y = target_y;
    }

    /// Scroll to make a rectangle visible
    /// Minimal scroll to bring rect into view
    pub fn scrollToRect(self: *Viewport, rect: Rect) void {
        // Scroll horizontally
        if (rect.x < self.x) {
            self.x = rect.x;
        } else if (rect.x + rect.width > self.x + self.width) {
            self.x = rect.x + rect.width - self.width;
        }

        // Scroll vertically
        if (rect.y < self.y) {
            self.y = rect.y;
        } else if (rect.y + rect.height > self.y + self.height) {
            self.y = rect.y + rect.height - self.height;
        }
    }
};

// Tests

test "Viewport.init" {
    const vp = Viewport.init(10, 20, 80, 24);
    try std.testing.expectEqual(@as(u16, 10), vp.x);
    try std.testing.expectEqual(@as(u16, 20), vp.y);
    try std.testing.expectEqual(@as(u16, 80), vp.width);
    try std.testing.expectEqual(@as(u16, 24), vp.height);
}

test "Viewport.asRect" {
    const vp = Viewport.init(5, 10, 40, 20);
    const rect = vp.asRect();
    try std.testing.expectEqual(@as(u16, 5), rect.x);
    try std.testing.expectEqual(@as(u16, 10), rect.y);
    try std.testing.expectEqual(@as(u16, 40), rect.width);
    try std.testing.expectEqual(@as(u16, 20), rect.height);
}

test "Viewport.isVisible" {
    const vp = Viewport.init(10, 10, 20, 20);

    // Inside viewport
    try std.testing.expect(vp.isVisible(15, 15));
    try std.testing.expect(vp.isVisible(10, 10));
    try std.testing.expect(vp.isVisible(29, 29));

    // Outside viewport
    try std.testing.expect(!vp.isVisible(5, 15));
    try std.testing.expect(!vp.isVisible(15, 5));
    try std.testing.expect(!vp.isVisible(30, 15));
    try std.testing.expect(!vp.isVisible(15, 30));
}

test "Viewport.clipRect - fully inside" {
    const vp = Viewport.init(0, 0, 80, 24);
    const rect = Rect{ .x = 10, .y = 5, .width = 20, .height = 10 };
    const clipped = vp.clipRect(rect);

    try std.testing.expectEqual(rect.x, clipped.x);
    try std.testing.expectEqual(rect.y, clipped.y);
    try std.testing.expectEqual(rect.width, clipped.width);
    try std.testing.expectEqual(rect.height, clipped.height);
}

test "Viewport.clipRect - partially outside" {
    const vp = Viewport.init(0, 0, 80, 24);
    const rect = Rect{ .x = 70, .y = 20, .width = 20, .height = 10 };
    const clipped = vp.clipRect(rect);

    try std.testing.expectEqual(@as(u16, 70), clipped.x);
    try std.testing.expectEqual(@as(u16, 20), clipped.y);
    try std.testing.expectEqual(@as(u16, 10), clipped.width); // Clipped from 20 to 10
    try std.testing.expectEqual(@as(u16, 4), clipped.height); // Clipped from 10 to 4
}

test "Viewport.clipRect - fully outside" {
    const vp = Viewport.init(0, 0, 80, 24);
    const rect = Rect{ .x = 100, .y = 100, .width = 20, .height = 10 };
    const clipped = vp.clipRect(rect);

    try std.testing.expectEqual(@as(u16, 0), clipped.width);
    try std.testing.expectEqual(@as(u16, 0), clipped.height);
}

test "Viewport.intersects" {
    const vp = Viewport.init(10, 10, 20, 20);

    // Intersecting
    try std.testing.expect(vp.intersects(Rect{ .x = 15, .y = 15, .width = 10, .height = 10 }));
    try std.testing.expect(vp.intersects(Rect{ .x = 5, .y = 5, .width = 10, .height = 10 }));

    // Not intersecting
    try std.testing.expect(!vp.intersects(Rect{ .x = 0, .y = 0, .width = 5, .height = 5 }));
    try std.testing.expect(!vp.intersects(Rect{ .x = 50, .y = 50, .width = 10, .height = 10 }));
}

test "Viewport.renderClipped" {
    const allocator = std.testing.allocator;

    // Create large source buffer
    var source = try Buffer.init(allocator, 100, 100);
    defer source.deinit();

    // Set some cells in the source
    source.set(50, 50, .{ .char = 'A', .style = .{} });
    source.set(51, 50, .{ .char = 'B', .style = .{} });
    source.set(50, 51, .{ .char = 'C', .style = .{} });

    // Create viewport at (45, 45, 10, 10)
    const vp = Viewport.init(45, 45, 10, 10);

    // Create target buffer (viewport size)
    var target = try Buffer.init(allocator, 10, 10);
    defer target.deinit();

    // Render clipped
    vp.renderClipped(&source, &target);

    // Verify visible cells were copied
    // (50, 50) in source → (5, 5) in target
    const cell_a = target.getConst(5, 5).?;
    const cell_b = target.getConst(6, 5).?;
    const cell_c = target.getConst(5, 6).?;
    try std.testing.expectEqual(@as(u21, 'A'), cell_a.char);
    try std.testing.expectEqual(@as(u21, 'B'), cell_b.char);
    try std.testing.expectEqual(@as(u21, 'C'), cell_c.char);

    // Cells outside original content should be empty
    const cell_empty = target.getConst(0, 0).?;
    try std.testing.expectEqual(@as(u21, ' '), cell_empty.char);
}

test "Viewport.scroll" {
    var vp = Viewport.init(10, 10, 20, 20);

    vp.scroll(5, 3);
    try std.testing.expectEqual(@as(u16, 15), vp.x);
    try std.testing.expectEqual(@as(u16, 13), vp.y);

    vp.scroll(-5, -3);
    try std.testing.expectEqual(@as(u16, 10), vp.x);
    try std.testing.expectEqual(@as(u16, 10), vp.y);

    // Scroll with negative overflow
    vp.scroll(-20, -20);
    try std.testing.expectEqual(@as(u16, 0), vp.x);
    try std.testing.expectEqual(@as(u16, 0), vp.y);
}

test "Viewport.scrollToPoint" {
    var vp = Viewport.init(0, 0, 20, 10);

    // Scroll to (50, 25) - should center it
    vp.scrollToPoint(50, 25);
    try std.testing.expectEqual(@as(u16, 40), vp.x); // 50 - 20/2
    try std.testing.expectEqual(@as(u16, 20), vp.y); // 25 - 10/2

    // Scroll to (5, 3) - too close to edge, should go to (0, 0)
    vp.scrollToPoint(5, 3);
    try std.testing.expectEqual(@as(u16, 0), vp.x);
    try std.testing.expectEqual(@as(u16, 0), vp.y);
}

test "Viewport.scrollToRect - rect to the right" {
    var vp = Viewport.init(0, 0, 80, 24);

    // Rect at (100, 10, 20, 5) - need to scroll right
    vp.scrollToRect(Rect{ .x = 100, .y = 10, .width = 20, .height = 5 });
    try std.testing.expectEqual(@as(u16, 40), vp.x); // 100 + 20 - 80
    try std.testing.expectEqual(@as(u16, 0), vp.y); // No vertical scroll needed
}

test "Viewport.scrollToRect - rect above" {
    var vp = Viewport.init(0, 50, 80, 24);

    // Rect at (10, 10, 20, 5) - need to scroll up
    vp.scrollToRect(Rect{ .x = 10, .y = 10, .width = 20, .height = 5 });
    try std.testing.expectEqual(@as(u16, 0), vp.x); // No horizontal scroll
    try std.testing.expectEqual(@as(u16, 10), vp.y); // Scroll to rect.y
}

test "Viewport.scrollToRect - already visible" {
    var vp = Viewport.init(10, 10, 80, 24);

    const initial_x = vp.x;
    const initial_y = vp.y;

    // Rect at (20, 15, 10, 5) - already visible
    vp.scrollToRect(Rect{ .x = 20, .y = 15, .width = 10, .height = 5 });

    // Should not scroll
    try std.testing.expectEqual(initial_x, vp.x);
    try std.testing.expectEqual(initial_y, vp.y);
}

test "Viewport.renderClipped - offset viewport" {
    const allocator = std.testing.allocator;

    var source = try Buffer.init(allocator, 50, 50);
    defer source.deinit();

    // Set marker at (20, 15)
    source.set(20, 15, .{ .char = 'X', .style = .{} });

    // Viewport at (15, 10, 10, 10)
    const vp = Viewport.init(15, 10, 10, 10);

    var target = try Buffer.init(allocator, 10, 10);
    defer target.deinit();

    vp.renderClipped(&source, &target);

    // (20, 15) in source → (5, 5) in target (20-15, 15-10)
    const cell_x = target.getConst(5, 5).?;
    try std.testing.expectEqual(@as(u21, 'X'), cell_x.char);
}
