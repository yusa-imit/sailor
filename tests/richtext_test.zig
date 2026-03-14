const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

// Test type alias for RichText widget (will be implemented in src/tui/widgets/richtext.zig)
const RichText = sailor.tui.widgets.RichText;
const FormatSpan = RichText.FormatSpan;

// ============================================================================
// Initialization Tests
// ============================================================================

test "richtext: init empty" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try testing.expectEqual(@as(usize, 0), rt.text.items.len);
    try testing.expectEqual(@as(usize, 0), rt.cursor);
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

test "richtext: init with plain text" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try testing.expectEqualStrings("Hello world", rt.text.items);
    try testing.expectEqual(@as(usize, 0), rt.cursor);
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len); // No formatting
}

test "richtext: deinit cleans up allocations" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);

    try rt.setText("Test");
    try rt.addSpan(0, 4, .{ .bold = true });

    rt.deinit();
    // Should not leak - testing.allocator will catch leaks
}

// ============================================================================
// Formatting Span Tests
// ============================================================================

test "richtext: add single formatting span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
    try testing.expect(rt.spans.items[0].style.bold);
}

test "richtext: add multiple non-overlapping spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });
    try rt.addSpan(6, 5, .{ .italic = true });

    try testing.expectEqual(@as(usize, 2), rt.spans.items.len);
    try testing.expect(rt.spans.items[0].style.bold);
    try testing.expect(rt.spans.items[1].style.italic);
}

test "richtext: add overlapping spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 7, .{ .bold = true });
    try rt.addSpan(3, 5, .{ .italic = true }); // Overlaps with bold

    try testing.expectEqual(@as(usize, 2), rt.spans.items.len);
    // Both spans should coexist - rendering will apply both styles to overlapping region
}

test "richtext: span with color formatting" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Colored text");
    try rt.addSpan(0, 7, .{ .fg = Color.red });

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(Color.red, rt.spans.items[0].style.fg.?);
}

test "richtext: span with background color" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Highlighted");
    try rt.addSpan(0, 11, .{ .bg = Color.yellow });

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(Color.yellow, rt.spans.items[0].style.bg.?);
}

test "richtext: span with multiple style attributes" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Formatted");
    const style = Style{
        .bold = true,
        .italic = true,
        .fg = Color.blue,
        .bg = Color.white,
    };
    try rt.addSpan(0, 9, style);

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expect(rt.spans.items[0].style.bold);
    try testing.expect(rt.spans.items[0].style.italic);
}

// ============================================================================
// Text Insertion with Formatting Preservation
// ============================================================================

test "richtext: insertChar before span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("world");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.cursor = 0;
    try rt.insertChar('H');

    try testing.expectEqualStrings("Hworld", rt.text.items);
    // Span should shift: start=1, length=5
    try testing.expectEqual(@as(usize, 1), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

test "richtext: insertChar inside span extends span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.cursor = 3;
    try rt.insertChar('X');

    try testing.expectEqualStrings("HelXlo", rt.text.items);
    // Span should extend: start=0, length=6
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 6), rt.spans.items[0].length);
}

test "richtext: insertChar after span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.cursor = 5;
    try rt.insertChar('!');

    try testing.expectEqualStrings("Hello!", rt.text.items);
    // Span should NOT extend: start=0, length=5
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

test "richtext: insertChar with multiple spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("AB CD");
    try rt.addSpan(0, 2, .{ .bold = true }); // "AB"
    try rt.addSpan(3, 2, .{ .italic = true }); // "CD"

    rt.cursor = 2;
    try rt.insertChar('X');

    try testing.expectEqualStrings("ABX CD", rt.text.items);
    // First span extends: start=0, length=3
    // Second span shifts: start=4, length=2
    try testing.expectEqual(@as(usize, 3), rt.spans.items[0].length);
    try testing.expectEqual(@as(usize, 4), rt.spans.items[1].start);
}

test "richtext: insertText preserves formatting" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.cursor = 5;
    try rt.insertText(" world");

    try testing.expectEqualStrings("Hello world", rt.text.items);
    // Bold span should remain: start=0, length=5
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

// ============================================================================
// Text Deletion with Formatting Preservation
// ============================================================================

test "richtext: deleteChar before span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("X Hello");
    try rt.addSpan(2, 5, .{ .bold = true });

    rt.cursor = 1;
    rt.deleteChar();

    try testing.expectEqualStrings(" Hello", rt.text.items);
    // Span should shift: start=1, length=5
    try testing.expectEqual(@as(usize, 1), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

test "richtext: deleteChar inside span shrinks span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.cursor = 3;
    rt.deleteChar();

    try testing.expectEqualStrings("Helo", rt.text.items);
    // Span should shrink: start=0, length=4
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 4), rt.spans.items[0].length);
}

test "richtext: deleteChar removes empty span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("X");
    try rt.addSpan(0, 1, .{ .bold = true });

    rt.cursor = 1;
    rt.deleteChar();

    try testing.expectEqualStrings("", rt.text.items);
    // Span should be removed (length=0)
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

test "richtext: deleteChar after span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello!");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.cursor = 6;
    rt.deleteChar();

    try testing.expectEqualStrings("Hello", rt.text.items);
    // Span unchanged: start=0, length=5
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

test "richtext: delete range removes affected spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("ABCDEF");
    try rt.addSpan(1, 2, .{ .bold = true }); // "BC"
    try rt.addSpan(3, 2, .{ .italic = true }); // "DE"

    try rt.deleteRange(2, 4); // Delete "CD"

    try testing.expectEqualStrings("ABEF", rt.text.items);
    // First span partially deleted: start=1, length=1 ("B")
    // Second span partially deleted and shifted: start=2, length=1 ("E")
    try testing.expectEqual(@as(usize, 1), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 1), rt.spans.items[0].length);
    try testing.expectEqual(@as(usize, 2), rt.spans.items[1].start);
    try testing.expectEqual(@as(usize, 1), rt.spans.items[1].length);
}

// ============================================================================
// Cursor Navigation
// ============================================================================

test "richtext: moveCursor forward" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.cursor = 0;

    rt.moveCursor(3);
    try testing.expectEqual(@as(usize, 3), rt.cursor);
}

test "richtext: moveCursor backward" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.cursor = 5;

    rt.moveCursor(-2);
    try testing.expectEqual(@as(usize, 3), rt.cursor);
}

test "richtext: moveCursor clamps at boundaries" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");

    rt.cursor = 0;
    rt.moveCursor(-10);
    try testing.expectEqual(@as(usize, 0), rt.cursor);

    rt.moveCursor(100);
    try testing.expectEqual(@as(usize, 5), rt.cursor);
}

test "richtext: setCursor" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    rt.setCursor(7);

    try testing.expectEqual(@as(usize, 7), rt.cursor);
}

test "richtext: setCursor clamps to text length" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.setCursor(100);

    try testing.expectEqual(@as(usize, 5), rt.cursor);
}

// ============================================================================
// Toggle Formatting
// ============================================================================

test "richtext: toggleBold creates span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.setSelection(0, 5);
    try rt.toggleBold();

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expect(rt.spans.items[0].style.bold);
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

test "richtext: toggleBold removes existing bold span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.setSelection(0, 5);
    try rt.toggleBold();

    // Bold span should be removed
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

test "richtext: toggleItalic creates span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("world");
    rt.setSelection(0, 5);
    try rt.toggleItalic();

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expect(rt.spans.items[0].style.italic);
}

test "richtext: toggleUnderline creates span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("text");
    rt.setSelection(0, 4);
    try rt.toggleUnderline();

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expect(rt.spans.items[0].style.underline);
}

test "richtext: toggleStrikethrough creates span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("removed");
    rt.setSelection(0, 7);
    try rt.toggleStrikethrough();

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expect(rt.spans.items[0].style.strikethrough);
}

test "richtext: toggleBold without selection does nothing" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.cursor = 3;
    try rt.toggleBold(); // No selection

    // Should not create span for zero-length range
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

test "richtext: toggleBold on partial span splits span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.setSelection(2, 3); // Toggle bold on "l"
    try rt.toggleBold();

    // Should split into two spans: "He" (bold) and "lo" (bold)
    // "l" should not be bold
    // Result: 2 spans
    try testing.expect(rt.spans.items.len == 2);
}

// ============================================================================
// Color Formatting
// ============================================================================

test "richtext: setColor creates foreground color span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Colored");
    rt.setSelection(0, 7);
    try rt.setColor(Color.red, null);

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(Color.red, rt.spans.items[0].style.fg.?);
}

test "richtext: setColor creates background color span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Highlighted");
    rt.setSelection(0, 11);
    try rt.setColor(null, Color.yellow);

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(Color.yellow, rt.spans.items[0].style.bg.?);
}

test "richtext: setColor creates both fg and bg" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Text");
    rt.setSelection(0, 4);
    try rt.setColor(Color.blue, Color.white);

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(Color.blue, rt.spans.items[0].style.fg.?);
    try testing.expectEqual(Color.white, rt.spans.items[0].style.bg.?);
}

// ============================================================================
// Clear Formatting
// ============================================================================

test "richtext: clearFormatting removes all spans in range" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });
    try rt.addSpan(6, 5, .{ .italic = true });

    rt.setSelection(0, 11);
    try rt.clearFormatting();

    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

test "richtext: clearFormatting partial range" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("ABCDEF");
    try rt.addSpan(0, 6, .{ .bold = true });

    rt.setSelection(2, 4); // Clear "CD"
    try rt.clearFormatting();

    // Should split span: "AB" (bold) and "EF" (bold)
    try testing.expectEqual(@as(usize, 2), rt.spans.items.len);
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 2), rt.spans.items[0].length);
    try testing.expectEqual(@as(usize, 4), rt.spans.items[1].start);
    try testing.expectEqual(@as(usize, 2), rt.spans.items[1].length);
}

test "richtext: clearFormatting with no selection clears all" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Formatted");
    try rt.addSpan(0, 9, .{ .bold = true });

    try rt.clearFormatting();

    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

// ============================================================================
// Merge Adjacent Identical Spans
// ============================================================================

test "richtext: mergeSpans combines adjacent identical spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });
    try rt.addSpan(5, 6, .{ .bold = true });

    try rt.mergeSpans();

    // Should merge into single span: start=0, length=11
    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 11), rt.spans.items[0].length);
}

test "richtext: mergeSpans does not merge different styles" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });
    try rt.addSpan(5, 6, .{ .italic = true });

    try rt.mergeSpans();

    // Should NOT merge (different styles)
    try testing.expectEqual(@as(usize, 2), rt.spans.items.len);
}

test "richtext: mergeSpans handles non-adjacent spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("AB CD EF");
    try rt.addSpan(0, 2, .{ .bold = true }); // "AB"
    try rt.addSpan(6, 2, .{ .bold = true }); // "EF"

    try rt.mergeSpans();

    // Should NOT merge (not adjacent)
    try testing.expectEqual(@as(usize, 2), rt.spans.items.len);
}

test "richtext: mergeSpans with identical fg color" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("RedText");
    try rt.addSpan(0, 3, .{ .fg = Color.red });
    try rt.addSpan(3, 4, .{ .fg = Color.red });

    try rt.mergeSpans();

    // Should merge
    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(@as(usize, 7), rt.spans.items[0].length);
}

// ============================================================================
// Export to Plain Text
// ============================================================================

test "richtext: toPlainText strips formatting" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });
    try rt.addSpan(6, 5, .{ .italic = true });

    const plain = try rt.toPlainText(allocator);
    defer allocator.free(plain);

    try testing.expectEqualStrings("Hello world", plain);
}

test "richtext: toPlainText empty text" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    const plain = try rt.toPlainText(allocator);
    defer allocator.free(plain);

    try testing.expectEqualStrings("", plain);
}

// ============================================================================
// Export to Markdown
// ============================================================================

test "richtext: toMarkdown exports bold" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);

    try testing.expectEqualStrings("**Hello** world", md);
}

test "richtext: toMarkdown exports italic" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(6, 5, .{ .italic = true });

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);

    try testing.expectEqualStrings("Hello *world*", md);
}

test "richtext: toMarkdown exports strikethrough" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("removed text");
    try rt.addSpan(0, 7, .{ .strikethrough = true });

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);

    try testing.expectEqualStrings("~~removed~~ text", md);
}

test "richtext: toMarkdown exports nested formatting" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });
    try rt.addSpan(0, 5, .{ .italic = true });

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);

    // Should export as ***Hello*** (bold + italic)
    try testing.expectEqualStrings("***Hello***", md);
}

test "richtext: toMarkdown ignores color formatting" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Colored");
    try rt.addSpan(0, 7, .{ .fg = Color.red });

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);

    // Colors are not markdown - should export plain
    try testing.expectEqualStrings("Colored", md);
}

test "richtext: toMarkdown empty text" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);

    try testing.expectEqualStrings("", md);
}

test "richtext: toMarkdown multiple separate spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });
    try rt.addSpan(6, 5, .{ .italic = true });

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);

    try testing.expectEqualStrings("**Hello** *world*", md);
}

// ============================================================================
// Copy/Paste with Formatting
// ============================================================================

test "richtext: copyFormatted includes spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 5, .{ .bold = true });

    rt.setSelection(0, 5);
    const clipboard = try rt.copyFormatted(allocator);
    defer clipboard.deinit(allocator);

    try testing.expectEqualStrings("Hello", clipboard.text);
    try testing.expectEqual(@as(usize, 1), clipboard.spans.len);
    try testing.expect(clipboard.spans[0].style.bold);
    // Span should be relative to copied text: start=0, length=5
    try testing.expectEqual(@as(usize, 0), clipboard.spans[0].start);
    try testing.expectEqual(@as(usize, 5), clipboard.spans[0].length);
}

test "richtext: copyFormatted partial span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try rt.addSpan(0, 11, .{ .bold = true });

    rt.setSelection(3, 8); // "lo wo"
    const clipboard = try rt.copyFormatted(allocator);
    defer clipboard.deinit(allocator);

    try testing.expectEqualStrings("lo wo", clipboard.text);
    try testing.expectEqual(@as(usize, 1), clipboard.spans.len);
    // Span should be adjusted: start=0, length=5 (entire copied range)
    try testing.expectEqual(@as(usize, 0), clipboard.spans[0].start);
    try testing.expectEqual(@as(usize, 5), clipboard.spans[0].length);
}

test "richtext: pasteFormatted applies spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("world");

    const clipboard = RichText.Clipboard{
        .text = "Hello ",
        .spans = &[_]FormatSpan{
            .{ .start = 0, .length = 5, .style = .{ .bold = true } },
        },
    };

    rt.cursor = 0;
    try rt.pasteFormatted(clipboard);

    try testing.expectEqualStrings("Hello world", rt.text.items);
    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expect(rt.spans.items[0].style.bold);
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

test "richtext: pasteFormatted shifts existing spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("world");
    try rt.addSpan(0, 5, .{ .italic = true });

    const clipboard = RichText.Clipboard{
        .text = "Hello ",
        .spans = &[_]FormatSpan{
            .{ .start = 0, .length = 5, .style = .{ .bold = true } },
        },
    };

    rt.cursor = 0;
    try rt.pasteFormatted(clipboard);

    try testing.expectEqualStrings("Hello world", rt.text.items);
    try testing.expectEqual(@as(usize, 2), rt.spans.items.len);
    // Bold span: start=0, length=5
    // Italic span shifted: start=6, length=5
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 6), rt.spans.items[1].start);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "richtext: empty text operations" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    // Operations on empty text should not crash
    rt.deleteChar();
    rt.moveCursor(5);
    try rt.toggleBold();

    try testing.expectEqual(@as(usize, 0), rt.text.items.len);
}

test "richtext: single character with formatting" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("X");
    try rt.addSpan(0, 1, .{ .bold = true });

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);

    const md = try rt.toMarkdown(allocator);
    defer allocator.free(md);
    try testing.expectEqualStrings("**X**", md);
}

test "richtext: cursor at boundary positions" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");

    rt.setCursor(0);
    try testing.expectEqual(@as(usize, 0), rt.cursor);

    rt.setCursor(5);
    try testing.expectEqual(@as(usize, 5), rt.cursor);
}

test "richtext: zero-length selection" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.setSelection(3, 3);

    try rt.toggleBold();

    // Should not create span for zero-length selection
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

test "richtext: span exactly at text boundaries" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true }); // Entire text

    try testing.expectEqual(@as(usize, 1), rt.spans.items.len);
    try testing.expectEqual(@as(usize, 0), rt.spans.items[0].start);
    try testing.expectEqual(@as(usize, 5), rt.spans.items[0].length);
}

test "richtext: overlapping spans different attributes" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 3, .{ .bold = true });
    try rt.addSpan(2, 3, .{ .italic = true });

    try testing.expectEqual(@as(usize, 2), rt.spans.items.len);
    // Overlapping region (position 2) should have both bold and italic when rendered
}

test "richtext: insert at end with no spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.cursor = 5;
    try rt.insertChar('!');

    try testing.expectEqualStrings("Hello!", rt.text.items);
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

test "richtext: delete entire text with spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    try rt.deleteRange(0, 5);

    try testing.expectEqualStrings("", rt.text.items);
    try testing.expectEqual(@as(usize, 0), rt.spans.items.len);
}

// ============================================================================
// Rendering Tests
// ============================================================================

test "richtext: render basic text" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    // Check first character is rendered
    const ch = buffer.getChar(0, 0);
    try testing.expectEqual(@as(u21, 'H'), ch);
}

test "richtext: render with bold span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 5, .{ .bold = true });

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    // Check that style is applied
    const style = buffer.getStyle(0, 0);
    try testing.expect(style.bold);
}

test "richtext: render with color span" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Colored");
    try rt.addSpan(0, 7, .{ .fg = Color.red });

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    const style = buffer.getStyle(0, 0);
    try testing.expectEqual(Color.red, style.fg.?);
}

test "richtext: render with overlapping spans" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    try rt.addSpan(0, 3, .{ .bold = true });
    try rt.addSpan(2, 3, .{ .italic = true });

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    // Position 2 should have both bold and italic
    const style = buffer.getStyle(2, 0);
    try testing.expect(style.bold);
    try testing.expect(style.italic);
}

test "richtext: render cursor" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");
    rt.cursor = 2;

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    // Cursor position should have cursor style
    const style = buffer.getStyle(2, 0);
    try testing.expect(style.reverse); // Default cursor style
}

test "richtext: render selection" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    rt.setSelection(0, 5);

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    // Selection should have selection style
    const style = buffer.getStyle(2, 0);
    try testing.expect(style.bg != null); // Selection background
}

test "richtext: render empty text shows cursor" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    // Should render cursor at position 0
    const style = buffer.getStyle(0, 0);
    try testing.expect(style.reverse);
}

test "richtext: render truncates to area width" {
    const allocator = testing.allocator;
    var rt = RichText.init(allocator);
    defer rt.deinit();

    try rt.setText("This is a very long text that exceeds the area width");

    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    rt.render(&buffer, area);

    // Should not crash, should truncate
    const ch = buffer.getChar(9, 0);
    try testing.expect(ch != 0);
}
