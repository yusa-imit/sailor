const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Line = style_mod.Line;
const Span = style_mod.Span;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Text alignment options
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Text wrapping behavior
pub const Wrap = enum {
    /// Don't wrap, truncate lines that are too long
    none,
    /// Wrap at word boundaries
    word,
    /// Wrap at any character
    char,
};

/// Paragraph widget - displays text with wrapping and alignment
pub const Paragraph = struct {
    /// Lines of text to display (each line can contain multiple styled spans)
    lines: []const Line = &[_]Line{},
    /// Optional block wrapper for borders and padding
    block: ?Block = null,
    /// Text alignment
    alignment: Alignment = .left,
    /// Text wrapping mode
    wrap: Wrap = .word,
    /// Scroll offset (number of lines scrolled down)
    scroll: u16 = 0,

    /// Create a paragraph with no lines (empty)
    pub fn init() Paragraph {
        return .{};
    }

    /// Create a paragraph from multiple lines
    pub fn fromLines(lines: []const Line) Paragraph {
        return .{ .lines = lines };
    }

    /// Set block wrapper
    pub fn withBlock(self: Paragraph, new_block: Block) Paragraph {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set text alignment
    pub fn withAlignment(self: Paragraph, new_alignment: Alignment) Paragraph {
        var result = self;
        result.alignment = new_alignment;
        return result;
    }

    /// Set text wrapping mode
    pub fn withWrap(self: Paragraph, new_wrap: Wrap) Paragraph {
        var result = self;
        result.wrap = new_wrap;
        return result;
    }

    /// Set scroll offset
    pub fn withScroll(self: Paragraph, new_scroll: u16) Paragraph {
        var result = self;
        result.scroll = new_scroll;
        return result;
    }

    /// Render the paragraph
    pub fn render(self: Paragraph, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block first if present
        var render_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            render_area = blk.inner(area);
            if (render_area.width == 0 or render_area.height == 0) return;
        }

        // Render lines
        self.renderLines(buf, render_area);
    }

    /// Render text lines within the area
    fn renderLines(self: Paragraph, buf: *Buffer, area: Rect) void {
        var y_offset: u16 = 0;
        var lines_skipped: u16 = 0;

        for (self.lines) |line| {
            if (y_offset >= area.height) break;

            // Apply scroll offset
            if (lines_skipped < self.scroll) {
                lines_skipped += 1;
                continue;
            }

            // Calculate line width for alignment
            const line_width = self.calculateLineWidth(line);

            // Determine x offset based on alignment
            const x_offset = switch (self.alignment) {
                .left => @as(u16, 0),
                .center => if (line_width < area.width) @divTrunc(area.width - @as(u16, @intCast(line_width)), 2) else 0,
                .right => if (line_width < area.width) area.width - @as(u16, @intCast(line_width)) else 0,
            };

            // Render the line
            var x_pos: u16 = 0;
            for (line.spans) |span| {
                for (span.content) |char| {
                    const char_x = area.x + x_offset + x_pos;
                    const char_y = area.y + y_offset;

                    // Check if we're still within bounds
                    if (x_pos >= area.width) break;
                    if (char_y >= area.y + area.height) break;

                    // Handle wrapping
                    if (self.wrap == .none and x_pos >= area.width) {
                        break;
                    }

                    // Set character in buffer
                    if (char_x < area.x + area.width and char_y < area.y + area.height) {
                        buf.setChar(char_x, char_y, char, span.style);
                    }

                    x_pos += 1;
                }
            }

            y_offset += 1;
        }
    }

    /// Calculate the display width of a line
    fn calculateLineWidth(self: Paragraph, line: Line) usize {
        _ = self;
        var width: usize = 0;
        for (line.spans) |span| {
            width += span.content.len;
        }
        return width;
    }
};

// Tests
test "Paragraph.init creates empty paragraph" {
    const para = Paragraph.init();
    try std.testing.expectEqual(@as(usize, 0), para.lines.len);
}

test "Paragraph.fromLines creates paragraph from single span line" {
    const spans = [_]Span{Span.raw("Hello, World!")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    try std.testing.expectEqual(@as(usize, 1), para.lines.len);
    try std.testing.expectEqualStrings("Hello, World!", para.lines[0].spans[0].content);
}

test "Paragraph.fromLines creates paragraph from multi-span line" {
    const spans = [_]Span{
        Span.raw("Hello "),
        Span.styled("World", Style{ .bold = true }),
    };
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    try std.testing.expectEqual(@as(usize, 1), para.lines.len);
    try std.testing.expectEqual(@as(usize, 2), para.lines[0].spans.len);
}

test "Paragraph.fromLines creates paragraph from multiple lines" {
    const spans1 = [_]Span{Span.raw("Line 1")};
    const spans2 = [_]Span{Span.raw("Line 2")};
    const line1 = Line{ .spans = &spans1 };
    const line2 = Line{ .spans = &spans2 };
    const lines = [_]Line{ line1, line2 };
    const para = Paragraph.fromLines(&lines);

    try std.testing.expectEqual(@as(usize, 2), para.lines.len);
}

test "Paragraph.withAlignment sets alignment" {
    const para = Paragraph.init()
        .withAlignment(.center);
    try std.testing.expectEqual(Alignment.center, para.alignment);
}

test "Paragraph.withWrap sets wrap mode" {
    const para = Paragraph.init()
        .withWrap(.word);
    try std.testing.expectEqual(Wrap.word, para.wrap);
}

test "Paragraph.render with left alignment" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Hello")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines)
        .withAlignment(.left);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Check text is rendered at left
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).?.char);
}

test "Paragraph.render with center alignment" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Hi")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines)
        .withAlignment(.center);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // "Hi" (2 chars) centered in 20 chars: (20 - 2) / 2 = 9
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(9, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(10, 0).?.char);
}

test "Paragraph.render with right alignment" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("End")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines)
        .withAlignment(.right);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // "End" (3 chars) at right: 20 - 3 = 17
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(17, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(18, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(19, 0).?.char);
}

test "Paragraph.render with multiple lines" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("Line 1")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Line 2")} };
    const lines = [_]Line{ line1, line2 };
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Check first line
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);

    // Check second line
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(2, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 1).?.char);
}

test "Paragraph.render with block wrapper" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Test")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const block = Block.init();
    const para = Paragraph.fromLines(&lines)
        .withBlock(block);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Check border exists
    try std.testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Check text is inside border (at x=1, y=1 due to border)
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(1, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(2, 1).?.char);
}

test "Paragraph.render with scroll offset" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("Line 1")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Line 2")} };
    const line3 = Line{ .spans = &[_]Span{Span.raw("Line 3")} };
    const lines = [_]Line{ line1, line2, line3 };
    const para = Paragraph.fromLines(&lines).withScroll(1);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // With scroll=1, first line should be "Line 2"
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(5, 0).?.char);
}

test "Paragraph.render handles empty area" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Test")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    para.render(&buf, area); // Should not crash

    // All cells should remain as default
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Paragraph.render with styled spans" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const bold_style = Style{ .bold = true };
    const spans = [_]Span{
        Span.raw("Hello "),
        Span.styled("World", bold_style),
    };
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Check plain text
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try std.testing.expect(!buf.get(0, 0).?.style.bold);

    // Check styled text
    try std.testing.expectEqual(@as(u21, 'W'), buf.get(6, 0).?.char);
    try std.testing.expect(buf.get(6, 0).?.style.bold);
}
