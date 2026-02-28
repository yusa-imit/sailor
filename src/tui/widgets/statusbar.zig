const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const Span = style_mod.Span;
const Line = style_mod.Line;

/// Status bar widget typically shown at bottom of screen
pub const StatusBar = struct {
    /// Left-aligned items
    left: []const Span = &.{},

    /// Center-aligned items
    center: []const Span = &.{},

    /// Right-aligned items
    right: []const Span = &.{},

    /// Background style for entire bar
    style: Style = .{ .bg = .{ .basic = .bright_black } },

    /// Create a new status bar
    pub fn init() StatusBar {
        return .{};
    }

    /// Set left items
    pub fn withLeft(self: StatusBar, items: []const Span) StatusBar {
        var result = self;
        result.left = items;
        return result;
    }

    /// Set center items
    pub fn withCenter(self: StatusBar, items: []const Span) StatusBar {
        var result = self;
        result.center = items;
        return result;
    }

    /// Set right items
    pub fn withRight(self: StatusBar, items: []const Span) StatusBar {
        var result = self;
        result.right = items;
        return result;
    }

    /// Set background style
    pub fn withStyle(self: StatusBar, new_style: Style) StatusBar {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Calculate total display width of spans
    fn spansWidth(spans: []const Span) usize {
        var total: usize = 0;
        for (spans) |span| {
            total += span.content.len;
        }
        return total;
    }

    /// Render spans starting at x position
    fn renderSpans(buf: *Buffer, spans: []const Span, x_start: usize, y: usize, max_x: usize, bg_style: Style) usize {
        var x = x_start;
        for (spans) |span| {
            if (x >= max_x) break;

            const remaining = max_x - x;
            const width = @min(span.content.len, remaining);

            // Merge span style with background
            var merged_style = span.style;
            if (merged_style.bg == .default) {
                merged_style.bg = bg_style.bg;
            }

            for (span.content[0..width], 0..) |c, offset| {
                buf.setCell(x + offset, y, c, merged_style);
            }
            x += width;
        }
        return x;
    }

    /// Render the status bar widget
    pub fn render(self: StatusBar, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render on first line only
        const y = area.y;
        const x_start = area.x;
        const max_x = area.x + area.width;

        // Fill background
        for (0..area.width) |offset| {
            buf.setCell(x_start + offset, y, ' ', self.style);
        }

        // Calculate widths
        const left_width = spansWidth(self.left);
        const center_width = spansWidth(self.center);
        const right_width = spansWidth(self.right);

        // Render left items
        var x = x_start;
        if (left_width > 0) {
            x = renderSpans(buf, self.left, x, y, max_x, self.style);
        }

        // Render right items (from right edge)
        if (right_width > 0 and right_width < area.width) {
            const right_x = x_start + area.width - right_width;
            _ = renderSpans(buf, self.right, right_x, y, max_x, self.style);
        }

        // Render center items (in remaining space)
        if (center_width > 0) {
            const available = area.width -| (left_width + right_width);
            if (center_width <= available) {
                const padding = (available - center_width) / 2;
                const center_x = x_start + left_width + padding;
                _ = renderSpans(buf, self.center, center_x, y, max_x, self.style);
            }
        }
    }
};

// Tests

test "StatusBar.init" {
    const bar = StatusBar.init();

    try std.testing.expectEqual(0, bar.left.len);
    try std.testing.expectEqual(0, bar.center.len);
    try std.testing.expectEqual(0, bar.right.len);
    try std.testing.expectEqual(Color{ .basic = .bright_black }, bar.style.bg);
}

test "StatusBar.withLeft" {
    const spans = [_]Span{
        Span{ .content = "Left", .style = .{} },
    };
    const bar = StatusBar.init().withLeft(&spans);

    try std.testing.expectEqual(1, bar.left.len);
    try std.testing.expectEqualStrings("Left", bar.left[0].content);
}

test "StatusBar.withCenter" {
    const spans = [_]Span{
        Span{ .content = "Center", .style = .{} },
    };
    const bar = StatusBar.init().withCenter(&spans);

    try std.testing.expectEqual(1, bar.center.len);
    try std.testing.expectEqualStrings("Center", bar.center[0].content);
}

test "StatusBar.withRight" {
    const spans = [_]Span{
        Span{ .content = "Right", .style = .{} },
    };
    const bar = StatusBar.init().withRight(&spans);

    try std.testing.expectEqual(1, bar.right.len);
    try std.testing.expectEqualStrings("Right", bar.right[0].content);
}

test "StatusBar.withStyle" {
    const custom_style = Style{ .bg = .{ .basic = .blue } };
    const bar = StatusBar.init().withStyle(custom_style);

    try std.testing.expectEqual(Color{ .basic = .blue }, bar.style.bg);
}

test "StatusBar.spansWidth" {
    const spans = [_]Span{
        Span{ .content = "Hello", .style = .{} },
        Span{ .content = " ", .style = .{} },
        Span{ .content = "World", .style = .{} },
    };

    const width = StatusBar.spansWidth(&spans);
    try std.testing.expectEqual(11, width); // 5 + 1 + 5
}

test "StatusBar.spansWidth empty" {
    const spans = [_]Span{};
    const width = StatusBar.spansWidth(&spans);
    try std.testing.expectEqual(0, width);
}

test "StatusBar.render basic" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const left_spans = [_]Span{Span{ .content = "Left", .style = .{} }};
    const bar = StatusBar.init().withLeft(&left_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    bar.render(&buf, area);

    // Check left content
    try std.testing.expectEqual('L', buf.get(0, 0).char);
    try std.testing.expectEqual('e', buf.get(1, 0).char);
    try std.testing.expectEqual('f', buf.get(2, 0).char);
    try std.testing.expectEqual('t', buf.get(3, 0).char);

    // Check background is filled
    try std.testing.expectEqual(' ', buf.get(4, 0).char);
    try std.testing.expectEqual(Color{ .basic = .bright_black }, buf.get(4, 0).style.bg);
}

test "StatusBar.render with left and right" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const left_spans = [_]Span{Span{ .content = "Left", .style = .{} }};
    const right_spans = [_]Span{Span{ .content = "Right", .style = .{} }};
    const bar = StatusBar.init().withLeft(&left_spans).withRight(&right_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    bar.render(&buf, area);

    // Check left
    try std.testing.expectEqual('L', buf.get(0, 0).char);

    // Check right (30 - 5 = 25)
    try std.testing.expectEqual('R', buf.get(25, 0).char);
    try std.testing.expectEqual('i', buf.get(26, 0).char);
    try std.testing.expectEqual('g', buf.get(27, 0).char);
    try std.testing.expectEqual('h', buf.get(28, 0).char);
    try std.testing.expectEqual('t', buf.get(29, 0).char);
}

test "StatusBar.render with center" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const center_spans = [_]Span{Span{ .content = "Center", .style = .{} }};
    const bar = StatusBar.init().withCenter(&center_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    bar.render(&buf, area);

    // Center should be at (30 - 6) / 2 = 12
    try std.testing.expectEqual('C', buf.get(12, 0).char);
    try std.testing.expectEqual('e', buf.get(13, 0).char);
    try std.testing.expectEqual('n', buf.get(14, 0).char);
    try std.testing.expectEqual('t', buf.get(15, 0).char);
    try std.testing.expectEqual('e', buf.get(16, 0).char);
    try std.testing.expectEqual('r', buf.get(17, 0).char);
}

test "StatusBar.render all three sections" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const left_spans = [_]Span{Span{ .content = "L", .style = .{} }};
    const center_spans = [_]Span{Span{ .content = "C", .style = .{} }};
    const right_spans = [_]Span{Span{ .content = "R", .style = .{} }};

    const bar = StatusBar.init()
        .withLeft(&left_spans)
        .withCenter(&center_spans)
        .withRight(&right_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    bar.render(&buf, area);

    // Left at 0
    try std.testing.expectEqual('L', buf.get(0, 0).char);

    // Center should be roughly in middle
    // Available = 50 - (1 + 1) = 48, padding = (48 - 1) / 2 = 23, center_x = 1 + 23 = 24
    try std.testing.expectEqual('C', buf.get(24, 0).char);

    // Right at 49
    try std.testing.expectEqual('R', buf.get(49, 0).char);
}

test "StatusBar.render with styled spans" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const red_style = Style{ .fg = .{ .basic = .red } };
    const left_spans = [_]Span{Span{ .content = "Error", .style = red_style }};
    const bar = StatusBar.init().withLeft(&left_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    bar.render(&buf, area);

    // Check style is applied
    try std.testing.expectEqual('E', buf.get(0, 0).char);
    try std.testing.expectEqual(Color{ .basic = .red }, buf.get(0, 0).style.fg);
    try std.testing.expectEqual(Color{ .basic = .bright_black }, buf.get(0, 0).style.bg);
}

test "StatusBar.render zero width" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const left_spans = [_]Span{Span{ .content = "Left", .style = .{} }};
    const bar = StatusBar.init().withLeft(&left_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    bar.render(&buf, area);

    // Should not crash
}

test "StatusBar.render truncates when too narrow" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const left_spans = [_]Span{Span{ .content = "VeryLongText", .style = .{} }};
    const bar = StatusBar.init().withLeft(&left_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    bar.render(&buf, area);

    // Should render truncated
    try std.testing.expectEqual('V', buf.get(0, 0).char);
    try std.testing.expectEqual('e', buf.get(1, 0).char);
    try std.testing.expectEqual('r', buf.get(2, 0).char);
    try std.testing.expectEqual('y', buf.get(3, 0).char);
    try std.testing.expectEqual('L', buf.get(4, 0).char);
}

test "StatusBar.render multiple spans in section" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const left_spans = [_]Span{
        Span{ .content = "Part1", .style = .{} },
        Span{ .content = " ", .style = .{} },
        Span{ .content = "Part2", .style = .{} },
    };
    const bar = StatusBar.init().withLeft(&left_spans);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    bar.render(&buf, area);

    // Check all parts rendered
    try std.testing.expectEqual('P', buf.get(0, 0).char);
    try std.testing.expectEqual('a', buf.get(1, 0).char);
    try std.testing.expectEqual('r', buf.get(2, 0).char);
    try std.testing.expectEqual('t', buf.get(3, 0).char);
    try std.testing.expectEqual('1', buf.get(4, 0).char);
    try std.testing.expectEqual(' ', buf.get(5, 0).char);
    try std.testing.expectEqual('P', buf.get(6, 0).char);
    try std.testing.expectEqual('a', buf.get(7, 0).char);
    try std.testing.expectEqual('r', buf.get(8, 0).char);
    try std.testing.expectEqual('t', buf.get(9, 0).char);
    try std.testing.expectEqual('2', buf.get(10, 0).char);
}
