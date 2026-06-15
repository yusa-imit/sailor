const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Paragraph = sailor.tui.widgets.Paragraph;
const Alignment = sailor.tui.widgets.Alignment;
const Wrap = sailor.tui.widgets.Wrap;
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Span = sailor.tui.Span;
const Line = sailor.tui.Line;
const Block = sailor.tui.widgets.Block;
const Color = sailor.tui.Color;

test "Paragraph initialization with defaults" {
    const para = Paragraph{};
    try testing.expectEqual(@as(usize, 0), para.lines.len);
    try testing.expectEqual(Alignment.left, para.alignment);
    try testing.expectEqual(Wrap.word, para.wrap);
    try testing.expectEqual(@as(u16, 0), para.scroll);
    try testing.expectEqual(@as(u16, 0), para.first_line_indent);
    try testing.expect(para.block == null);
}

test "Paragraph.fromLines creates paragraph from single line" {
    const spans = [_]Span{Span.raw("Hello, World!")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    try testing.expectEqual(@as(usize, 1), para.lines.len);
    try testing.expectEqualStrings("Hello, World!", para.lines[0].spans[0].content);
}

test "Paragraph.fromLines creates paragraph from multiple lines" {
    const spans1 = [_]Span{Span.raw("Line 1")};
    const spans2 = [_]Span{Span.raw("Line 2")};
    const spans3 = [_]Span{Span.raw("Line 3")};
    const line1 = Line{ .spans = &spans1 };
    const line2 = Line{ .spans = &spans2 };
    const line3 = Line{ .spans = &spans3 };
    const lines = [_]Line{ line1, line2, line3 };
    const para = Paragraph.fromLines(&lines);

    try testing.expectEqual(@as(usize, 3), para.lines.len);
}

test "Paragraph.withAlignment changes alignment without mutating original" {
    const original = Paragraph{};
    const centered = original.withAlignment(.center);

    try testing.expectEqual(Alignment.left, original.alignment);
    try testing.expectEqual(Alignment.center, centered.alignment);
}

test "Paragraph.withWrap sets wrap mode without mutation" {
    const original = Paragraph{};
    const wrapped = original.withWrap(.char);

    try testing.expectEqual(Wrap.word, original.wrap);
    try testing.expectEqual(Wrap.char, wrapped.wrap);
}

test "Paragraph.withScroll sets scroll offset" {
    const original = Paragraph{};
    const scrolled = original.withScroll(5);

    try testing.expectEqual(@as(u16, 0), original.scroll);
    try testing.expectEqual(@as(u16, 5), scrolled.scroll);
}

test "Paragraph.withFirstLineIndent sets indentation" {
    const original = Paragraph{};
    const indented = original.withFirstLineIndent(4);

    try testing.expectEqual(@as(u16, 0), original.first_line_indent);
    try testing.expectEqual(@as(u16, 4), indented.first_line_indent);
}

test "Paragraph.withBlock sets block border" {
    const original = Paragraph{};
    const blk = Block{};
    const with_block = original.withBlock(blk);

    try testing.expect(original.block == null);
    try testing.expect(with_block.block != null);
}

test "Paragraph render simple text left-aligned" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Hello")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.left);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).?.char);
}

test "Paragraph render center-aligned text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Hi")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.center);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // "Hi" (2 chars) centered in 20: (20 - 2) / 2 = 9
    try testing.expectEqual(@as(u21, 'H'), buf.get(9, 0).?.char);
    try testing.expectEqual(@as(u21, 'i'), buf.get(10, 0).?.char);
}

test "Paragraph render right-aligned text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("End")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.right);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // "End" (3 chars) right-aligned: 20 - 3 = 17
    try testing.expectEqual(@as(u21, 'E'), buf.get(17, 0).?.char);
    try testing.expectEqual(@as(u21, 'n'), buf.get(18, 0).?.char);
    try testing.expectEqual(@as(u21, 'd'), buf.get(19, 0).?.char);
}

test "Paragraph render multiple lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("First")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Second")} };
    const line3 = Line{ .spans = &[_]Span{Span.raw("Third")} };
    const lines = [_]Line{ line1, line2, line3 };
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Check first line
    try testing.expectEqual(@as(u21, 'F'), buf.get(0, 0).?.char);
    // Check second line
    try testing.expectEqual(@as(u21, 'S'), buf.get(0, 1).?.char);
    // Check third line
    try testing.expectEqual(@as(u21, 'T'), buf.get(0, 2).?.char);
}

test "Paragraph render with styled spans" {
    const allocator = testing.allocator;
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

    // Plain text at start should not have bold
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try testing.expect(!buf.get(0, 0).?.style.bold);

    // Styled text should have bold
    try testing.expectEqual(@as(u21, 'W'), buf.get(6, 0).?.char);
    try testing.expect(buf.get(6, 0).?.style.bold);
}

test "Paragraph render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Text")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const blk = Block{};
    const para = Paragraph.fromLines(&lines).withBlock(blk);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Border should be at position (0,0)
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Text should be inside border (at x=1, y=1)
    try testing.expectEqual(@as(u21, 'T'), buf.get(1, 1).?.char);
}

test "Paragraph render with scroll offset" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("Line 1")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Line 2")} };
    const line3 = Line{ .spans = &[_]Span{Span.raw("Line 3")} };
    const lines = [_]Line{ line1, line2, line3 };
    const para = Paragraph.fromLines(&lines).withScroll(1);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // With scroll=1, first visible line should be "Line 2"
    try testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'n'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(4, 0).?.char);
    try testing.expectEqual(@as(u21, '2'), buf.get(5, 0).?.char);
}

test "Paragraph render with first-line indent" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("First")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Second")} };
    const lines = [_]Line{ line1, line2 };
    const para = Paragraph.fromLines(&lines).withFirstLineIndent(4);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // First line should start at x=4
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'F'), buf.get(4, 0).?.char);

    // Second line should start at x=0 (no indent)
    try testing.expectEqual(@as(u21, 'S'), buf.get(0, 1).?.char);
}

test "Paragraph render empty area does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Test")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    para.render(&buf, area);

    // All cells should remain default (space character)
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Paragraph render with zero width preserves data" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Test")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 5 };
    para.render(&buf, area);

    // Should not crash - early return when width is zero
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Paragraph render with zero height preserves data" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Test")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    para.render(&buf, area);

    // Should not crash - early return when height is zero
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Paragraph render with offset area position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Offset")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 5, .y = 3, .width = 15, .height = 5 };
    para.render(&buf, area);

    // Text should be rendered at offset position
    try testing.expectEqual(@as(u21, 'O'), buf.get(5, 3).?.char);
    try testing.expectEqual(@as(u21, 'f'), buf.get(6, 3).?.char);
}

test "Paragraph render justify alignment distributes spaces" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Hello world")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.justify);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    para.render(&buf, area);

    // First word at start
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);

    // Last word at end (positions 15-19: "world")
    try testing.expectEqual(@as(u21, 'w'), buf.get(15, 0).?.char);
    try testing.expectEqual(@as(u21, 'd'), buf.get(19, 0).?.char);
}

test "Paragraph render justify without spaces renders left-aligned" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("NoSpaces")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines).withAlignment(.justify);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    para.render(&buf, area);

    // Should render left-aligned
    try testing.expectEqual(@as(u21, 'N'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.get(1, 0).?.char);
}

test "Paragraph render center with first-line indent adjusts center point" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const spans = [_]Span{Span.raw("Hi")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines)
        .withAlignment(.center)
        .withFirstLineIndent(4);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // With 4-space indent, effective width is 16
    // Center offset: (16 - 2) / 2 = 7, plus indent = 11
    try testing.expectEqual(@as(u21, 'H'), buf.get(11, 0).?.char);
    try testing.expectEqual(@as(u21, 'i'), buf.get(12, 0).?.char);
}

test "Paragraph render multi-span line" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 5);
    defer buf.deinit();

    const spans = [_]Span{
        Span.raw("Part1 "),
        Span.styled("Part2 ", .{ .bold = true }),
        Span.raw("Part3"),
    };
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const para = Paragraph.fromLines(&lines);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    para.render(&buf, area);

    // Check all parts are rendered
    try testing.expectEqual(@as(u21, 'P'), buf.get(0, 0).?.char); // Part1
    try testing.expectEqual(@as(u21, 'P'), buf.get(6, 0).?.char); // Part2 (with bold)
    try testing.expectEqual(@as(u21, 'P'), buf.get(12, 0).?.char); // Part3
}

test "Paragraph render with scroll exceeding line count" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const line1 = Line{ .spans = &[_]Span{Span.raw("Line 1")} };
    const line2 = Line{ .spans = &[_]Span{Span.raw("Line 2")} };
    const lines = [_]Line{ line1, line2 };
    const para = Paragraph.fromLines(&lines).withScroll(10); // Scroll beyond available

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    para.render(&buf, area);

    // Should render nothing (all lines scrolled past)
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Paragraph render preserves buffer state on zero-width inner area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    // Mark a cell to verify it's not overwritten
    buf.set(5, 5, .{ .char = 'X', .style = .{} });

    const spans = [_]Span{Span.raw("Text")};
    const line = Line{ .spans = &spans };
    const lines = [_]Line{line};
    const blk = (Block{}).withBorders(.all);
    const para = Paragraph.fromLines(&lines).withBlock(blk);

    // Very small area - block border takes all space
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    para.render(&buf, area);

    // Cell at (5,5) should still be 'X'
    try testing.expectEqual(@as(u21, 'X'), buf.get(5, 5).?.char);
}

test "Paragraph builder chain immutability" {
    const original = Paragraph{};
    const modified = original
        .withAlignment(.right)
        .withWrap(.char)
        .withScroll(2)
        .withFirstLineIndent(3);

    // Original should remain unchanged
    try testing.expectEqual(Alignment.left, original.alignment);
    try testing.expectEqual(Wrap.word, original.wrap);
    try testing.expectEqual(@as(u16, 0), original.scroll);
    try testing.expectEqual(@as(u16, 0), original.first_line_indent);

    // Modified should have new values
    try testing.expectEqual(Alignment.right, modified.alignment);
    try testing.expectEqual(Wrap.char, modified.wrap);
    try testing.expectEqual(@as(u16, 2), modified.scroll);
    try testing.expectEqual(@as(u16, 3), modified.first_line_indent);
}
