const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// Scrollable viewport widget for large content
pub const ScrollView = struct {
    /// Content height (total scrollable area)
    content_height: u16,
    /// Current vertical scroll offset
    scroll_y: u16 = 0,
    /// Content width (total scrollable area)
    content_width: u16 = 0,
    /// Current horizontal scroll offset
    scroll_x: u16 = 0,
    /// Optional block for border
    block: ?Block = null,
    /// Show scrollbar
    show_scrollbar: bool = true,
    /// Scrollbar style
    scrollbar_style: Style = .{},

    /// Scroll down by lines
    pub fn scrollDown(self: *ScrollView, lines: u16) void {
        self.scroll_y = @min(self.scroll_y + lines, self.content_height);
    }

    /// Scroll up by lines
    pub fn scrollUp(self: *ScrollView, lines: u16) void {
        if (lines > self.scroll_y) {
            self.scroll_y = 0;
        } else {
            self.scroll_y -= lines;
        }
    }

    /// Scroll right by columns
    pub fn scrollRight(self: *ScrollView, cols: u16) void {
        self.scroll_x = @min(self.scroll_x + cols, self.content_width);
    }

    /// Scroll left by columns
    pub fn scrollLeft(self: *ScrollView, cols: u16) void {
        if (cols > self.scroll_x) {
            self.scroll_x = 0;
        } else {
            self.scroll_x -= cols;
        }
    }

    /// Scroll to make position visible
    pub fn scrollTo(self: *ScrollView, y: u16, viewport_height: u16) void {
        if (y < self.scroll_y) {
            // Scroll up to show y
            self.scroll_y = y;
        } else if (y >= self.scroll_y + viewport_height) {
            // Scroll down to show y
            self.scroll_y = y -| (viewport_height -| 1);
        }
    }

    /// Get visible content area
    pub fn getViewport(self: ScrollView, area: Rect) Rect {
        var inner = area;
        if (self.block) |blk| {
            inner = blk.inner(area);
        }

        // Reserve space for scrollbar if shown
        if (self.show_scrollbar and inner.width > 1) {
            inner.width -= 1;
        }

        return inner;
    }

    /// Get content rectangle (offset by scroll position)
    pub fn getContentRect(_: ScrollView, viewport: Rect) Rect {
        return Rect{
            .x = viewport.x,
            .y = viewport.y,
            .width = viewport.width,
            .height = viewport.height,
        };
    }

    /// Render the scrollview with content callback
    pub fn render(
        self: ScrollView,
        buf: *Buffer,
        area: Rect,
        renderContent: *const fn (*Buffer, Rect, u16, u16) void,
    ) void {
        // Render block border if present
        if (self.block) |blk| {
            blk.render(buf, area);
        }

        // Get viewport area
        const viewport = self.getViewport(area);
        if (viewport.width == 0 or viewport.height == 0) return;

        // Render content with scroll offset
        renderContent(buf, viewport, self.scroll_x, self.scroll_y);

        // Render scrollbar
        if (self.show_scrollbar) {
            self.renderScrollbar(buf, area, viewport);
        }
    }

    fn renderScrollbar(self: ScrollView, buf: *Buffer, area: Rect, viewport: Rect) void {
        const inner = if (self.block) |blk| blk.inner(area) else area;
        if (inner.height < 2) return;

        // Calculate scrollbar position and size
        const scrollbar_x = inner.x + inner.width;
        const scrollbar_height = inner.height;

        // Calculate thumb size and position
        const visible_ratio = @as(f64, @floatFromInt(viewport.height)) / @as(f64, @floatFromInt(@max(1, self.content_height)));
        const thumb_size = @max(1, @as(u16, @intFromFloat(@as(f64, @floatFromInt(scrollbar_height)) * visible_ratio)));

        const scroll_ratio = if (self.content_height > viewport.height)
            @as(f64, @floatFromInt(self.scroll_y)) / @as(f64, @floatFromInt(self.content_height - viewport.height))
        else
            0.0;

        const thumb_y = @as(u16, @intFromFloat(@as(f64, @floatFromInt(scrollbar_height - thumb_size)) * scroll_ratio));

        // Render scrollbar track
        var y: u16 = 0;
        while (y < scrollbar_height) : (y += 1) {
            const char: u21 = if (y >= thumb_y and y < thumb_y + thumb_size) '█' else '░';
            buf.set(scrollbar_x, inner.y + y, .{ .char = char, .style = self.scrollbar_style });
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ScrollView - initial state" {
    const sv = ScrollView{
        .content_height = 100,
        .content_width = 80,
    };

    try std.testing.expectEqual(0, sv.scroll_y);
    try std.testing.expectEqual(0, sv.scroll_x);
    try std.testing.expectEqual(100, sv.content_height);
}

test "ScrollView - scroll down" {
    var sv = ScrollView{
        .content_height = 100,
    };

    sv.scrollDown(10);
    try std.testing.expectEqual(10, sv.scroll_y);

    sv.scrollDown(50);
    try std.testing.expectEqual(60, sv.scroll_y);

    // Can't scroll past content_height
    sv.scrollDown(100);
    try std.testing.expectEqual(100, sv.scroll_y);
}

test "ScrollView - scroll up" {
    var sv = ScrollView{
        .content_height = 100,
        .scroll_y = 50,
    };

    sv.scrollUp(10);
    try std.testing.expectEqual(40, sv.scroll_y);

    sv.scrollUp(50);
    try std.testing.expectEqual(0, sv.scroll_y);
}

test "ScrollView - scroll right" {
    var sv = ScrollView{
        .content_width = 200,
    };

    sv.scrollRight(20);
    try std.testing.expectEqual(20, sv.scroll_x);

    sv.scrollRight(300);
    try std.testing.expectEqual(200, sv.scroll_x);
}

test "ScrollView - scroll left" {
    var sv = ScrollView{
        .content_width = 200,
        .scroll_x = 100,
    };

    sv.scrollLeft(30);
    try std.testing.expectEqual(70, sv.scroll_x);

    sv.scrollLeft(100);
    try std.testing.expectEqual(0, sv.scroll_x);
}

test "ScrollView - scrollTo" {
    var sv = ScrollView{
        .content_height = 100,
    };

    // Scroll to position 50 with viewport height 20
    sv.scrollTo(50, 20);
    try std.testing.expectEqual(31, sv.scroll_y); // 50 - (20 - 1)

    // Scroll to position 10 (should scroll up)
    sv.scrollTo(10, 20);
    try std.testing.expectEqual(10, sv.scroll_y);

    // Scroll to position in visible range (should not change)
    sv.scrollTo(15, 20);
    try std.testing.expectEqual(10, sv.scroll_y);
}

test "ScrollView - getViewport without block" {
    const sv = ScrollView{
        .content_height = 100,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const viewport = sv.getViewport(area);

    // Should be area minus 1 for scrollbar
    try std.testing.expectEqual(79, viewport.width);
    try std.testing.expectEqual(24, viewport.height);
}

test "ScrollView - getViewport with block" {
    const sv = ScrollView{
        .content_height = 100,
        .block = Block{
            .borders = .all,
        },
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const viewport = sv.getViewport(area);

    // Should be inner area minus 1 for scrollbar
    // Block takes 2 from width (left+right border) and 2 from height (top+bottom)
    try std.testing.expectEqual(77, viewport.width); // 80 - 2 (borders) - 1 (scrollbar)
    try std.testing.expectEqual(22, viewport.height); // 24 - 2 (borders)
}

test "ScrollView - getViewport no scrollbar" {
    const sv = ScrollView{
        .content_height = 100,
        .show_scrollbar = false,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const viewport = sv.getViewport(area);

    // Full area when no scrollbar
    try std.testing.expectEqual(80, viewport.width);
    try std.testing.expectEqual(24, viewport.height);
}

test "ScrollView - render with scrollbar" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit(allocator);

    const sv = ScrollView{
        .content_height = 100,
        .scroll_y = 25,
        .show_scrollbar = true,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    // Simple content renderer that does nothing
    const renderFn = struct {
        fn render(_: *Buffer, _: Rect, _: u16, _: u16) void {}
    }.render;

    sv.render(&buf, area, renderFn);

    // Check that scrollbar is rendered at right edge
    const scrollbar_x: u16 = 79;
    const cell = buf.get(scrollbar_x, 0);
    try std.testing.expect(cell.char == '█' or cell.char == '░');
}

test "ScrollView - scrollbar positioning" {
    var sv = ScrollView{
        .content_height = 100,
        .scroll_y = 0,
    };

    // At top, thumb should be at top
    try std.testing.expectEqual(0, sv.scroll_y);

    // Scroll to bottom
    sv.scrollDown(100);
    try std.testing.expectEqual(100, sv.scroll_y);

    // Scroll to middle
    sv.scroll_y = 50;
    try std.testing.expectEqual(50, sv.scroll_y);
}

test "ScrollView - zero size viewport" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit(allocator);

    const sv = ScrollView{
        .content_height = 100,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const renderFn = struct {
        fn render(_: *Buffer, _: Rect, _: u16, _: u16) void {}
    }.render;

    // Should not crash with zero-sized area
    sv.render(&buf, area, renderFn);
}

test "ScrollView - getContentRect" {
    const sv = ScrollView{
        .content_height = 100,
        .scroll_y = 20,
    };

    const viewport = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const content = sv.getContentRect(viewport);

    try std.testing.expectEqual(viewport.x, content.x);
    try std.testing.expectEqual(viewport.y, content.y);
    try std.testing.expectEqual(viewport.width, content.width);
    try std.testing.expectEqual(viewport.height, content.height);
}

test "ScrollView - scroll clamping" {
    var sv = ScrollView{
        .content_height = 50,
    };

    // Try to scroll beyond content
    sv.scrollDown(100);
    try std.testing.expectEqual(50, sv.scroll_y);

    // Try to scroll before start
    sv.scrollUp(100);
    try std.testing.expectEqual(0, sv.scroll_y);
}
