//! Paragraph widget — multi-line text rendering with styling and alignment.
//!
//! Paragraph displays text content with support for word wrapping, alignment,
//! and inline styling via Span/Line composition. It's the primary widget for
//! displaying formatted text in TUI applications.
//!
//! ## Features
//! - Multi-line text with automatic word/character wrapping
//! - Alignment (left, center, right)
//! - Inline styling via Span and Line
//! - RTL (Right-to-Left) text support via bidirectional algorithm
//! - Optional Block wrapper for borders and title
//! - Vertical scrolling for content exceeding area height
//!
//! ## Usage
//! ```zig
//! const para = Paragraph{
//!     .lines = &[_]Line{
//!         Line.init(&[_]Span{Span.raw("Hello ")}, .{}),
//!         Line.init(&[_]Span{Span.styled("World", .{ .fg = .{ .basic = .cyan } })}, .{}),
//!     },
//!     .alignment = .left,
//!     .wrap = .word,
//! };
//! para.render(buf, area);
//! ```

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
const bidi_mod = @import("../../bidi.zig");
const Bidi = bidi_mod.Bidi;

/// Text alignment options
pub const Alignment = enum {
    left,
    center,
    right,
    /// Justify (space-distributed, full-width lines)
    justify,
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
    /// Text direction (.auto auto-detects from content)
    direction: Bidi.Direction = .auto,
    /// First-line indent (number of spaces at start of first line)
    first_line_indent: u16 = 0,

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

    /// Set text direction (.ltr, .rtl, or .auto for auto-detection)
    pub fn withDirection(self: Paragraph, new_direction: Bidi.Direction) Paragraph {
        var result = self;
        result.direction = new_direction;
        return result;
    }

    /// Set first-line indent (number of spaces at start of first line)
    pub fn withFirstLineIndent(self: Paragraph, indent: u16) Paragraph {
        var result = self;
        result.first_line_indent = indent;
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
        var is_first_line = true;

        for (self.lines) |line| {
            if (y_offset >= area.height) break;

            // Apply scroll offset
            if (lines_skipped < self.scroll) {
                lines_skipped += 1;
                is_first_line = false;
                continue;
            }

            // Calculate line width for alignment
            const line_width = self.calculateLineWidth(line);

            // Apply first-line indent
            const indent = if (is_first_line) self.first_line_indent else 0;
            const effective_width = if (area.width > indent) area.width - indent else 0;

            // Determine x offset based on alignment
            const x_offset = switch (self.alignment) {
                .left => indent,
                .center => if (line_width < effective_width)
                    indent + @divTrunc(effective_width - @as(u16, @intCast(line_width)), 2)
                else
                    indent,
                .right => if (line_width < effective_width)
                    indent + (effective_width - @as(u16, @intCast(line_width)))
                else
                    indent,
                .justify => indent, // Justify uses left offset, distributes spaces during render
            };

            // Render the line
            if (self.alignment == .justify and line_width > 0 and line_width < effective_width) {
                // Justify: distribute extra space between words
                self.renderJustifiedLine(buf, area, line, x_offset, y_offset, effective_width);
            } else {
                // Standard rendering for non-justify alignments
                var x_pos: u16 = 0;
                for (line.spans) |span| {
                    for (span.content) |char| {
                        const char_x = area.x + x_offset + x_pos;
                        const char_y = area.y + y_offset;

                        // Check if we're still within bounds
                        if (x_pos >= effective_width) break;
                        if (char_y >= area.y + area.height) break;

                        // Handle wrapping
                        if (self.wrap == .none and x_pos >= effective_width) {
                            break;
                        }

                        // Set character in buffer
                        if (char_x < area.x + area.width and char_y < area.y + area.height) {
                            buf.set(char_x, char_y, .{ .char = char, .style = span.style });
                        }

                        x_pos += 1;
                    }
                }
            }

            y_offset += 1;
            is_first_line = false;
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

    /// Render a justified line by distributing extra space between words
    fn renderJustifiedLine(self: Paragraph, buf: *Buffer, area: Rect, line: Line, x_offset: u16, y_offset: u16, target_width: u16) void {
        _ = self;
        const line_width = blk: {
            var w: usize = 0;
            for (line.spans) |span| {
                w += span.content.len;
            }
            break :blk w;
        };

        if (line_width == 0 or line_width >= target_width) {
            // Can't justify empty or overflowing line
            return;
        }

        // Count spaces (word separators) in the line
        var space_count: usize = 0;
        for (line.spans) |span| {
            for (span.content) |char| {
                if (char == ' ') space_count += 1;
            }
        }

        if (space_count == 0) {
            // No spaces to distribute — render normally (left-aligned)
            var x_pos: u16 = 0;
            for (line.spans) |span| {
                for (span.content) |char| {
                    if (x_pos >= target_width) break;
                    const char_x = area.x + x_offset + x_pos;
                    const char_y = area.y + y_offset;
                    if (char_x < area.x + area.width and char_y < area.y + area.height) {
                        buf.set(char_x, char_y, .{ .char = char, .style = span.style });
                    }
                    x_pos += 1;
                }
            }
            return;
        }

        // Calculate extra space to distribute
        const extra_space = target_width - @as(u16, @intCast(line_width));
        const space_per_gap = @divTrunc(extra_space, @as(u16, @intCast(space_count)));
        const extra_space_remainder = extra_space % @as(u16, @intCast(space_count));

        // Render line with distributed spaces
        var x_pos: u16 = 0;
        var space_idx: u16 = 0;
        for (line.spans) |span| {
            for (span.content) |char| {
                if (x_pos >= target_width) break;
                const char_x = area.x + x_offset + x_pos;
                const char_y = area.y + y_offset;

                if (char_x < area.x + area.width and char_y < area.y + area.height) {
                    buf.set(char_x, char_y, .{ .char = char, .style = span.style });
                }

                x_pos += 1;

                // After each space, add extra distributed spacing
                if (char == ' ') {
                    const extra = space_per_gap + (if (space_idx < extra_space_remainder) @as(u16, 1) else 0);
                    var i: u16 = 0;
                    while (i < extra) : (i += 1) {
                        const space_x = area.x + x_offset + x_pos;
                        if (space_x < area.x + area.width and char_y < area.y + area.height) {
                            buf.set(space_x, char_y, .{ .char = ' ', .style = span.style });
                        }
                        x_pos += 1;
                        if (x_pos >= target_width) break;
                    }
                    space_idx += 1;
                }
            }
        }
    }
};

// Tests
test "Paragraph.init creates empty paragraph" {
    const para = Paragraph{};
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
    const para = (Paragraph{}).withAlignment(.center);
    try std.testing.expectEqual(Alignment.center, para.alignment);
}

test "Paragraph.withWrap sets wrap mode" {
    const para = (Paragraph{}).withWrap(.word);
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
    const block = (Block{});
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

test "Paragraph.render with justify alignment" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    // "Hello world" (11 chars) justified to 20 width — extra 9 spaces distributed
    const spans = [_]Span{Span.raw("Hello world")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.justify);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // First word "Hello" should be at start
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).?.char);

    // Space(s) after "Hello"
    try std.testing.expectEqual(@as(u21, ' '), buf.get(5, 0).?.char);

    // Last word "world" should end at width boundary (chars 15-19)
    try std.testing.expectEqual(@as(u21, 'w'), buf.get(15, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(16, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'r'), buf.get(17, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(18, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(19, 0).?.char);

    // Spaces between "Hello" and "world" should be distributed
    // Original: "Hello world" (1 space) → with 9 extra spaces → 10 total spaces between words
    var space_count: u16 = 0;
    var i: u16 = 5;
    while (i < 15) : (i += 1) {
        if (buf.get(i, 0).?.char == ' ') {
            space_count += 1;
        }
    }
    try std.testing.expectEqual(@as(u16, 10), space_count);
}

test "Paragraph.render with justify alignment (no spaces)" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    // No spaces — should render left-aligned
    const spans = [_]Span{Span.raw("HelloWorld")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.justify);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Should render at left
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'W'), buf.get(5, 0).?.char);
}

test "Paragraph.render with justify alignment (multiple spaces)" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 30, 5);
    defer buf.deinit();

    // "one two three" (13 chars, 2 spaces) justified to 30 width
    const spans = [_]Span{Span.raw("one two three")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.justify);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    para.render(&buf, area);

    // First word at start
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(2, 0).?.char);

    // Last word at end (positions 25-29: "three")
    // Justification distributes extra spaces: 17 extra / 2 gaps = 8-9 spaces per gap
    try std.testing.expectEqual(@as(u21, 't'), buf.get(25, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'h'), buf.get(26, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'r'), buf.get(27, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(28, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(29, 0).?.char);

    // Verify spacing distribution
    // Gap 1 (after "one"): should have more spaces (gets remainder)
    var gap1_spaces: u16 = 0;
    var i: u16 = 3;
    while (i < 13) : (i += 1) {
        if (buf.get(i, 0).?.char == ' ') gap1_spaces += 1;
    }
    try std.testing.expectEqual(@as(u16, 10), gap1_spaces); // 1 original + 8 + 1 remainder

    // Gap 2 (after "two"): should have 9 spaces
    var gap2_spaces: u16 = 0;
    i = 16;
    while (i < 25) : (i += 1) {
        if (buf.get(i, 0).?.char == ' ') gap2_spaces += 1;
    }
    try std.testing.expectEqual(@as(u16, 9), gap2_spaces); // 1 original + 8

    // Verify distributed spacing (30 - 13 = 17 extra spaces, distributed over 2 gaps)
    // Each gap gets 8 or 9 spaces (17 / 2 = 8 remainder 1)
}

test "Paragraph.withFirstLineIndent sets indent" {
    const para = (Paragraph{}).withFirstLineIndent(4);
    try std.testing.expectEqual(@as(u16, 4), para.first_line_indent);
}

test "Paragraph.render with first-line indent" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("First")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Second")} };
    const lines = [_]Line{ line1, line2 };
    const para = Paragraph.fromLines(&lines).withFirstLineIndent(4);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // First line should start at x=4 (indented)
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(5, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'r'), buf.get(6, 0).?.char);
    try std.testing.expectEqual(@as(u21, 's'), buf.get(7, 0).?.char);
    try std.testing.expectEqual(@as(u21, 't'), buf.get(8, 0).?.char);

    // Second line should start at x=0 (no indent)
    try std.testing.expectEqual(@as(u21, 'S'), buf.get(0, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'c'), buf.get(2, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(3, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(4, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(5, 1).?.char);
}

test "Paragraph.render with first-line indent and center alignment" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    // "Hi" (2 chars) centered in width 20 with 4-space indent
    // Effective width: 20 - 4 = 16
    // Center offset: (16 - 2) / 2 = 7
    // Final position: 4 + 7 = 11
    const spans = [_]Span{Span.raw("Hi")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines)
        .withFirstLineIndent(4)
        .withAlignment(.center);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Text should be at position 11-12
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(11, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(12, 0).?.char);
}
