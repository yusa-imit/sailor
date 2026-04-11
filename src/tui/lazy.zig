const std = @import("std");
const Allocator = std.mem.Allocator;
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("style.zig");
const Style = style_mod.Style;

/// Lazy rendering system that tracks dirty regions to minimize computation.
/// Only cells marked as dirty will be processed during rendering.
pub const LazyBuffer = struct {
    buffer: Buffer,
    /// Dirty flags for each cell (true = needs redraw)
    dirty: []bool,
    /// Bounding rectangle of all dirty cells (for quick iteration)
    dirty_rect: ?Rect,
    allocator: Allocator,

    /// Create a new lazy buffer with given dimensions
    pub fn init(allocator: Allocator, width: u16, height: u16) !LazyBuffer {
        var buf = try Buffer.init(allocator, width, height);
        errdefer buf.deinit();

        const size = @as(usize, width) * @as(usize, height);
        const dirty = try allocator.alloc(bool, size);
        @memset(dirty, true); // Initially all dirty

        return LazyBuffer{
            .buffer = buf,
            .dirty = dirty,
            .dirty_rect = Rect{ .x = 0, .y = 0, .width = width, .height = height },
            .allocator = allocator,
        };
    }

    /// Free lazy buffer resources
    pub fn deinit(self: *LazyBuffer) void {
        self.buffer.deinit();
        self.allocator.free(self.dirty);
    }

    /// Mark cell at position as dirty
    pub fn markDirty(self: *LazyBuffer, x: u16, y: u16) void {
        if (x >= self.buffer.width or y >= self.buffer.height) return;

        const index = @as(usize, y) * @as(usize, self.buffer.width) + @as(usize, x);
        self.dirty[index] = true;

        // Update bounding rect
        if (self.dirty_rect) |*rect| {
            const min_x = @min(rect.x, x);
            const min_y = @min(rect.y, y);
            const max_x = @max(rect.x + rect.width, x + 1);
            const max_y = @max(rect.y + rect.height, y + 1);
            rect.x = min_x;
            rect.y = min_y;
            rect.width = max_x - min_x;
            rect.height = max_y - min_y;
        } else {
            self.dirty_rect = Rect{ .x = x, .y = y, .width = 1, .height = 1 };
        }
    }

    /// Mark rectangle as dirty
    pub fn markDirtyRect(self: *LazyBuffer, area: Rect) void {
        const max_y = @min(area.y + area.height, self.buffer.height);
        const max_x = @min(area.x + area.width, self.buffer.width);

        var row = area.y;
        while (row < max_y) : (row += 1) {
            var col = area.x;
            while (col < max_x) : (col += 1) {
                self.markDirty(col, row);
            }
        }
    }

    /// Clear all dirty flags
    pub fn clearDirty(self: *LazyBuffer) void {
        @memset(self.dirty, false);
        self.dirty_rect = null;
    }

    /// Check if cell is dirty
    pub fn isDirty(self: LazyBuffer, x: u16, y: u16) bool {
        if (x >= self.buffer.width or y >= self.buffer.height) return false;
        const index = @as(usize, y) * @as(usize, self.buffer.width) + @as(usize, x);
        return self.dirty[index];
    }

    /// Get bounding rectangle of all dirty cells
    pub fn getDirtyRect(self: LazyBuffer) ?Rect {
        return self.dirty_rect;
    }

    /// Set cell and mark as dirty
    pub fn setCell(self: *LazyBuffer, x: u16, y: u16, cell: Cell) void {
        self.buffer.set(x, y, cell);
        self.markDirty(x, y);
    }

    /// Set character and mark as dirty
    /// @deprecated Use set() with Cell instead (will be removed in v2.0.0)
    pub fn setChar(self: *LazyBuffer, x: u16, y: u16, char: u21, style: Style) void {
        self.buffer.set(x, y, .{ .char = char, .style = style });
        self.markDirty(x, y);
    }

    /// Write string and mark affected cells as dirty
    pub fn setString(self: *LazyBuffer, x: u16, y: u16, str: []const u8, style: Style) void {
        // Mark all potentially affected cells as dirty
        const max_len = @min(str.len, @as(usize, self.buffer.width) - @as(usize, x));
        const end_x = x + @as(u16, @intCast(max_len));
        var col = x;
        while (col < end_x and col < self.buffer.width) : (col += 1) {
            self.markDirty(col, y);
        }

        self.buffer.setString(x, y, str, style);
    }

    /// Fill area and mark as dirty
    pub fn fill(self: *LazyBuffer, area: Rect, char: u21, style: Style) void {
        self.buffer.fill(area, char, style);
        self.markDirtyRect(area);
    }

    /// Clear buffer and mark all as dirty
    pub fn clear(self: *LazyBuffer) void {
        self.buffer.clear();
        @memset(self.dirty, true);
        self.dirty_rect = Rect{ .x = 0, .y = 0, .width = self.buffer.width, .height = self.buffer.height };
    }

    /// Reset buffer to specific area and mark as dirty
    pub fn reset(self: *LazyBuffer, area: Rect) void {
        self.buffer.reset(area);
        self.markDirtyRect(area);
    }

    /// Render only dirty cells using a callback
    /// Callback receives (x, y, cell) for each dirty cell
    pub fn renderDirty(self: *LazyBuffer, callback: *const fn (u16, u16, Cell) void) void {
        const rect = self.dirty_rect orelse return; // No dirty cells

        var row = rect.y;
        while (row < rect.y + rect.height and row < self.buffer.height) : (row += 1) {
            var col = rect.x;
            while (col < rect.x + rect.width and col < self.buffer.width) : (col += 1) {
                if (self.isDirty(col, row)) {
                    if (self.buffer.getConst(col, row)) |cell| {
                        callback(col, row, cell);
                    }
                }
            }
        }
    }

    /// Count number of dirty cells (useful for metrics)
    pub fn countDirty(self: LazyBuffer) usize {
        var count: usize = 0;
        for (self.dirty) |is_dirty| {
            if (is_dirty) count += 1;
        }
        return count;
    }

    /// Resize buffer (invalidates all cells)
    pub fn resize(self: *LazyBuffer, width: u16, height: u16) !void {
        // Free old resources
        self.buffer.deinit();
        self.allocator.free(self.dirty);

        // Create new buffer
        self.buffer = try Buffer.init(self.allocator, width, height);
        const size = @as(usize, width) * @as(usize, height);
        self.dirty = try self.allocator.alloc(bool, size);
        @memset(self.dirty, true);
        self.dirty_rect = Rect{ .x = 0, .y = 0, .width = width, .height = height };
    }
};

test "LazyBuffer init" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    try std.testing.expectEqual(@as(u16, 10), lazy.buffer.width);
    try std.testing.expectEqual(@as(u16, 5), lazy.buffer.height);
    try std.testing.expectEqual(@as(usize, 50), lazy.countDirty());
}

test "LazyBuffer markDirty" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty();
    try std.testing.expectEqual(@as(usize, 0), lazy.countDirty());

    lazy.markDirty(3, 2);
    try std.testing.expect(lazy.isDirty(3, 2));
    try std.testing.expectEqual(@as(usize, 1), lazy.countDirty());
}

test "LazyBuffer markDirtyRect" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty();

    const area = Rect{ .x = 2, .y = 1, .width = 3, .height = 2 };
    lazy.markDirtyRect(area);

    try std.testing.expectEqual(@as(usize, 6), lazy.countDirty()); // 3x2 = 6
    try std.testing.expect(lazy.isDirty(2, 1));
    try std.testing.expect(lazy.isDirty(4, 2));
    try std.testing.expect(!lazy.isDirty(5, 2));
}

test "LazyBuffer getDirtyRect" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty();

    lazy.markDirty(2, 1);
    lazy.markDirty(5, 3);

    const rect = lazy.getDirtyRect().?;
    try std.testing.expectEqual(@as(u16, 2), rect.x);
    try std.testing.expectEqual(@as(u16, 1), rect.y);
    try std.testing.expectEqual(@as(u16, 4), rect.width); // 2 to 6
    try std.testing.expectEqual(@as(u16, 3), rect.height); // 1 to 4
}

test "LazyBuffer setChar marks dirty" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty();

    lazy.setChar(3, 2, 'X', .{});
    try std.testing.expect(lazy.isDirty(3, 2));
    try std.testing.expectEqual(@as(usize, 1), lazy.countDirty());

    if (lazy.buffer.getConst(3, 2)) |cell| {
        try std.testing.expectEqual(@as(u21, 'X'), cell.char);
    } else {
        try std.testing.expect(false);
    }
}

test "LazyBuffer setString marks dirty" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty();

    lazy.setString(2, 1, "hello", .{});

    // At least 5 cells should be dirty (might be more due to unicode width)
    const dirty_count = lazy.countDirty();
    try std.testing.expect(dirty_count >= 5);
    try std.testing.expect(lazy.isDirty(2, 1));
    try std.testing.expect(lazy.isDirty(6, 1));
}

test "LazyBuffer fill marks dirty" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty();

    const area = Rect{ .x = 1, .y = 1, .width = 3, .height = 2 };
    lazy.fill(area, '#', .{});

    try std.testing.expectEqual(@as(usize, 6), lazy.countDirty());
}

test "LazyBuffer clearDirty" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty(); // Clear initial dirty state
    lazy.markDirty(3, 2);
    try std.testing.expectEqual(@as(usize, 1), lazy.countDirty());

    lazy.clearDirty();
    try std.testing.expectEqual(@as(usize, 0), lazy.countDirty());
    try std.testing.expect(lazy.getDirtyRect() == null);
}

test "LazyBuffer resize" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    try lazy.resize(20, 10);

    try std.testing.expectEqual(@as(u16, 20), lazy.buffer.width);
    try std.testing.expectEqual(@as(u16, 10), lazy.buffer.height);
    try std.testing.expectEqual(@as(usize, 200), lazy.countDirty()); // All dirty after resize
}

test "LazyBuffer renderDirty callback" {
    const allocator = std.testing.allocator;
    var lazy = try LazyBuffer.init(allocator, 10, 5);
    defer lazy.deinit();

    lazy.clearDirty();
    lazy.set(2, 1, .{ .char = 'A', .style = .{} });
    lazy.set(3, 1, .{ .char = 'B', .style = .{} });

    const TestContext = struct {
        count: usize = 0,
        fn callback(x: u16, y: u16, cell: Cell) void {
            _ = x;
            _ = y;
            _ = cell;
            // Note: We can't access the context here without modifying the callback signature
            // This test just verifies the callback compiles and runs
        }
    };

    lazy.renderDirty(&TestContext.callback);
    // If we get here without crashing, the callback mechanism works
}
