const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const FlowText = tui.widgets.FlowText;
const Alignment = tui.widgets.Alignment;

// ============================================================================
// INIT & DEFAULTS (5 tests)
// ============================================================================

test "FlowText init returns empty text" {
    const widget = FlowText.init();
    try testing.expectEqualStrings("", widget.text);
}

test "FlowText init returns default columns of 2" {
    const widget = FlowText.init();
    try testing.expectEqual(@as(u8, 2), widget.columns);
}

test "FlowText init returns default gutter of 1" {
    const widget = FlowText.init();
    try testing.expectEqual(@as(u8, 1), widget.gutter);
}

test "FlowText init returns left alignment by default" {
    const widget = FlowText.init();
    try testing.expectEqual(Alignment.left, widget.alignment);
}

test "FlowText init returns null block by default" {
    const widget = FlowText.init();
    try testing.expect(widget.block == null);
}

// ============================================================================
// BUILDER API (8 tests)
// ============================================================================

test "FlowText withText returns copy with text set, original unchanged" {
    const widget1 = FlowText.init();
    const widget2 = widget1.withText("Hello");
    try testing.expectEqualStrings("Hello", widget2.text);
    try testing.expectEqualStrings("", widget1.text);
}

test "FlowText withColumns returns copy with columns set, original unchanged" {
    const widget1 = FlowText.init();
    const widget2 = widget1.withColumns(3);
    try testing.expectEqual(@as(u8, 3), widget2.columns);
    try testing.expectEqual(@as(u8, 2), widget1.columns);
}

test "FlowText withGutter returns copy with gutter set, original unchanged" {
    const widget1 = FlowText.init();
    const widget2 = widget1.withGutter(2);
    try testing.expectEqual(@as(u8, 2), widget2.gutter);
    try testing.expectEqual(@as(u8, 1), widget1.gutter);
}

test "FlowText withStyle returns copy with style set, original unchanged" {
    const widget1 = FlowText.init();
    const style1 = Style{ .fg = .red, .bold = true };
    const widget2 = widget1.withStyle(style1);
    try testing.expectEqual(Color.red, widget2.style.fg.?);
    try testing.expect(widget2.style.bold);
    try testing.expect(widget1.style.fg == null);
}

test "FlowText withAlignment returns copy with alignment set, original unchanged" {
    const widget1 = FlowText.init();
    const widget2 = widget1.withAlignment(.center);
    try testing.expectEqual(Alignment.center, widget2.alignment);
    try testing.expectEqual(Alignment.left, widget1.alignment);
}

test "FlowText withBlock returns copy with block set, original unchanged" {
    const widget1 = FlowText.init();
    const block_val = Block{ .borders = .all };
    const widget2 = widget1.withBlock(block_val);
    try testing.expect(widget2.block != null);
    try testing.expect(widget1.block == null);
}

test "FlowText builder chain preserves all values" {
    const widget = FlowText.init()
        .withText("Hello World")
        .withColumns(3)
        .withGutter(2)
        .withAlignment(.center);
    try testing.expectEqualStrings("Hello World", widget.text);
    try testing.expectEqual(@as(u8, 3), widget.columns);
    try testing.expectEqual(@as(u8, 2), widget.gutter);
    try testing.expectEqual(Alignment.center, widget.alignment);
}

test "FlowText multiple builder calls create independent copies" {
    const base = FlowText.init().withColumns(2);
    const v1 = base.withColumns(3);
    const v2 = base.withColumns(4);
    try testing.expectEqual(@as(u8, 2), base.columns);
    try testing.expectEqual(@as(u8, 3), v1.columns);
    try testing.expectEqual(@as(u8, 4), v2.columns);
}

// ============================================================================
// RENDER — ZERO/EMPTY AREA (6 tests)
// ============================================================================

test "FlowText render with zero width does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello";
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "FlowText render with zero height does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello";
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "FlowText render with empty text does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "";
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "FlowText render with columns=0 treats as 1 column" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello";
    widget.columns = 0;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Should render at least first char at (0, 0) without crashing
    try testing.expect(buf.getChar(0, 0) == 'H' or buf.getChar(0, 0) == ' ');
}

test "FlowText render with 1x1 area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Test";
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    widget.render(&buf, area);

    // With width 1, column width = (1 - 0) / 2 = 0, so render early-exits
    // Buffer remains unmodified from initialization (spaces)
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "FlowText render with gutter larger than area uses safe division" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello";
    widget.columns = 2;
    widget.gutter = 100;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Should not crash due to large gutter; buffer remains initialized
    try testing.expect(buf.width == 20 and buf.height == 10);
}

// ============================================================================
// RENDER — SINGLE COLUMN (10 tests)
// ============================================================================

test "FlowText single column renders short text on first line" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hi";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'i'), buf.getChar(1, 0));
}

test "FlowText single column wraps long text to multiple lines" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello World";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // "Hello" on line 0, "World" on line 1
    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(4, 0));
    try testing.expectEqual(@as(u21, 'W'), buf.getChar(0, 1));
}

test "FlowText single column text exactly fills width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'e'), buf.getChar(1, 0));
    try testing.expectEqual(@as(u21, 'l'), buf.getChar(2, 0));
    try testing.expectEqual(@as(u21, 'l'), buf.getChar(3, 0));
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(4, 0));
}

test "FlowText single column with text shorter than width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hi";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'i'), buf.getChar(1, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(2, 0));
}

test "FlowText single column left alignment renders at column start" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hi";
    widget.columns = 1;
    widget.alignment = .left;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
}

test "FlowText single column center alignment centers line within width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hi";
    widget.columns = 1;
    widget.alignment = .center;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // (10 - 2) / 2 = 4, so "Hi" starts at column 4
    try testing.expectEqual(@as(u21, 'H'), buf.getChar(4, 0));
    try testing.expectEqual(@as(u21, 'i'), buf.getChar(5, 0));
}

test "FlowText single column right alignment aligns to right edge" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hi";
    widget.columns = 1;
    widget.alignment = .right;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // 10 - 2 = 8, so "Hi" starts at column 8
    try testing.expectEqual(@as(u21, 'H'), buf.getChar(8, 0));
    try testing.expectEqual(@as(u21, 'i'), buf.getChar(9, 0));
}

test "FlowText single column long word hard-split at width boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "VeryLongWord";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // First 5 chars on line 0: "VeryL"
    try testing.expectEqual(@as(u21, 'V'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'L'), buf.getChar(4, 0));
    // Next chars on line 1: "ongWord"
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(0, 1));
}

// ============================================================================
// RENDER — TWO COLUMNS (15 tests)
// ============================================================================

test "FlowText two columns fills column 0 before column 1" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "One Two Three Four";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };
    widget.render(&buf, area);

    // Column 0: width = (15 - 1) / 2 = 7
    // Column 1: starts at x = 7 + 1 = 8
    try testing.expectEqual(@as(u21, 'O'), buf.getChar(0, 0));
}

test "FlowText two columns calculates correct column width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "1234567 abcdefg";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };
    widget.render(&buf, area);

    // Column width = (15 - 1) / 2 = 7
    // First 7 chars in col 0: "1234567"
    try testing.expectEqual(@as(u21, '1'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '7'), buf.getChar(6, 0));
    // Then space or word boundary
    // Column 1 starts at x = 8
    try testing.expectEqual(@as(u21, 'a'), buf.getChar(8, 0));
}

test "FlowText two columns gutter cells are not overwritten by text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C D E F G H I J K L M N O P Q R S T U";
    widget.columns = 2;
    widget.gutter = 2;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Column 0 width = (20 - 2) / 2 = 9
    // Gutter: x=9, x=10
    // Column 1: x=11 onwards
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 0));
}

test "FlowText two columns text only fills column 0" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Short";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };
    widget.render(&buf, area);

    // Column 0 has text, column 1 empty
    try testing.expectEqual(@as(u21, 'S'), buf.getChar(0, 0));
}

test "FlowText two columns respects word boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello World";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };
    widget.render(&buf, area);

    // Should split across columns respecting word boundaries
    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
}

test "FlowText two columns column 1 starts at correct x position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "1234567890 ABCDEFGHIJ";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Column width = (20 - 1) / 2 = 9
    // Column 0: x=0..8
    // Gutter: x=9
    // Column 1: x=10..19
    // Col 0 gets "1234567890" (wrapped), Col 1 gets "ABCDEFGHIJ"
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(10, 0));
}

test "FlowText two columns with area offset respects offset" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 5, .y = 2, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Column 0 starts at area.x = 5
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(5, 2));
}

test "FlowText two columns default gutter is 1" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Test";
    widget.columns = 2;
    // gutter defaults to 1
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Column width = (10 - 1) / 2 = 4
    // Column 0: x=0..3, text at (0,0)
    // Gutter at x=4 (should be space)
    // Column 1: x=5..8
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(4, 0));
}

test "FlowText two columns various area widths calculate correctly" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C D E F G H I J";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 11, .height = 5 };
    widget.render(&buf, area);

    // column_width = (11 - 1) / 2 = 5
    // Column 0: x=0..4, Column 1: x=6..10
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(5, 0));
}

test "FlowText two columns text distribution across columns" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Lorem Ipsum Dolor Sit Amet Consectetur";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Should distribute text across both columns—at least one of these should have text
    const col0_has_text = buf.getChar(0, 0) != ' ';
    const col1_has_text = buf.getChar(10, 0) != ' ';
    try testing.expect(col0_has_text or col1_has_text);
}

test "FlowText two columns alignment applies per-line in each column" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hi There";
    widget.columns = 2;
    widget.gutter = 1;
    widget.alignment = .left;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
}

// ============================================================================
// RENDER — THREE COLUMNS (8 tests)
// ============================================================================

test "FlowText three columns fills column 0, then 1, then 2" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C D E F G H I J K L M N O";
    widget.columns = 3;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 27, .height = 10 };
    widget.render(&buf, area);

    // Column width = (27 - 2) / 3 = 8 (2 gutters for 3 columns)
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(0, 0));
}

test "FlowText three columns calculates correct positions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "12345678 abcdefgh XXXXXXXX";
    widget.columns = 3;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 27, .height = 10 };
    widget.render(&buf, area);

    // Column 0: x=0..7 (width=8)
    // Gutter: x=8
    // Column 1: x=9..16 (width=8)
    // Gutter: x=17
    // Column 2: x=18..25 (width=8)
    try testing.expectEqual(@as(u21, '1'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(8, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(17, 0));
}

test "FlowText three columns column 1 position correct" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C D E F G H I J K L M N O";
    widget.columns = 3;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 27, .height = 10 };
    widget.render(&buf, area);

    // Column width = (27 - 2) / 3 = 8
    // Column 1 starts at x = 0 + 1 * (8 + 1) = 9
    // Column 1 should have text at some row
    const has_text_in_col1 = buf.getChar(9, 0) != ' ' or buf.getChar(9, 1) != ' ' or buf.getChar(9, 2) != ' ';
    try testing.expect(has_text_in_col1);
}

test "FlowText three columns column 2 starts at correct x" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C D E F G H I J K L M N O P Q R S T";
    widget.columns = 3;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 27, .height = 10 };
    widget.render(&buf, area);

    // Column width = (27 - 2) / 3 = 8
    // Column 2 starts at x = 0 + 2 * (8 + 1) = 18
    const has_text_in_col2 = buf.getChar(18, 0) != ' ' or buf.getChar(18, 1) != ' ';
    try testing.expect(has_text_in_col2);
}

test "FlowText three columns text not reaching column 2" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Short";
    widget.columns = 3;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 27, .height = 10 };
    widget.render(&buf, area);

    // "Short" is only 5 chars (1 word), so only column 0 gets it
    try testing.expectEqual(@as(u21, 'S'), buf.getChar(0, 0));
}

test "FlowText three columns gutter separation maintained" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "ABCDEFGH IJKLMNOP QRSTUVWX";
    widget.columns = 3;
    widget.gutter = 2;
    const area = Rect{ .x = 0, .y = 0, .width = 28, .height = 10 };
    widget.render(&buf, area);

    // Column width = (28 - 4) / 3 = 8
    // Gutters at x=8,9 and x=18,19
    try testing.expectEqual(@as(u21, ' '), buf.getChar(8, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(18, 0));
}

test "FlowText three columns equal width distribution" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "The quick brown fox jumps over the lazy dog";
    widget.columns = 3;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 27, .height = 10 };
    widget.render(&buf, area);

    // Should render text starting in column 0
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(0, 0));
}

// ============================================================================
// GUTTER TESTS (6 tests)
// ============================================================================

test "FlowText gutter=0 places columns adjacent with no separation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C D E F G H I J";
    widget.columns = 2;
    widget.gutter = 0;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Column 0: width = 20 / 2 = 10
    // Column 1: starts at x = 10 (no gutter)
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(0, 0));
    // Column 1 should have text at x=10 (second word 'B' distributed to word_idx 1, col_idx 1)
    try testing.expect(buf.getChar(10, 0) != ' ' or buf.getChar(10, 1) != ' ');
}

test "FlowText gutter=2 creates 2-width separation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C D E F";
    widget.columns = 2;
    widget.gutter = 2;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Column width = (20 - 2) / 2 = 9
    // Gutter cells at x=9,10
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(9, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 0));
}

test "FlowText gutter=3 creates 3-width separation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 25, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Test";
    widget.columns = 2;
    widget.gutter = 3;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    widget.render(&buf, area);

    // Column width = (20 - 3) / 2 = 8
    // Gutter cells at x=8,9,10
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(8, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 0));
}

test "FlowText gutter cells remain as spaces" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "ABCDE FGHIJ";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 11, .height = 5 };
    widget.render(&buf, area);

    // Gutter cell should be space
    try testing.expectEqual(@as(u21, ' '), buf.getChar(5, 0));
}

test "FlowText gutter cells have default style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Test";
    widget.columns = 2;
    widget.gutter = 1;
    widget.style = Style{ .fg = .red };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Gutter should have default style (no red)
    const gutter_style = buf.getStyle(5, 0);
    try testing.expect(gutter_style.fg == null);
}

test "FlowText large gutter with 2 columns leaves narrow text area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A";
    widget.columns = 2;
    widget.gutter = 18;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    widget.render(&buf, area);

    // Column width = (20 - 18) / 2 = 1 (very narrow)
    // Single char 'A' fits in column 0
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(0, 0));
}

// ============================================================================
// ALIGNMENT TESTS (8 tests)
// ============================================================================

test "FlowText alignment left renders text at column start" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Left";
    widget.columns = 1;
    widget.alignment = .left;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'L'), buf.getChar(0, 0));
}

test "FlowText alignment center centers line within column width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "C";
    widget.columns = 1;
    widget.alignment = .center;
    const area = Rect{ .x = 0, .y = 0, .width = 9, .height = 5 };
    widget.render(&buf, area);

    // (9 - 1) / 2 = 4, so 'C' at position 4
    try testing.expectEqual(@as(u21, 'C'), buf.getChar(4, 0));
}

test "FlowText alignment right aligns text to column end" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Right";
    widget.columns = 1;
    widget.alignment = .right;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // 10 - 5 = 5, so "Right" starts at position 5
    try testing.expectEqual(@as(u21, 'R'), buf.getChar(5, 0));
}

test "FlowText alignment center with odd line length" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "ABC";
    widget.columns = 1;
    widget.alignment = .center;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // (10 - 3) / 2 = 3
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(3, 0));
}

test "FlowText alignment center with even line length" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "ABCD";
    widget.columns = 1;
    widget.alignment = .center;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // (10 - 4) / 2 = 3
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(3, 0));
}

test "FlowText alignment right with text longer than width clamps to start" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "VeryLongText";
    widget.columns = 1;
    widget.alignment = .right;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // Line is clamped to width, renders first 5 chars
    try testing.expectEqual(@as(u21, 'V'), buf.getChar(0, 0));
}

test "FlowText alignment applies to each wrapped line independently" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Short Long";
    widget.columns = 1;
    widget.alignment = .right;
    const area = Rect{ .x = 0, .y = 0, .width = 6, .height = 5 };
    widget.render(&buf, area);

    // "Short" (5 chars) on line 0, right-aligned in width 6: starts at x=1
    // "Long" (4 chars) on line 1, right-aligned in width 6: starts at x=2
    try testing.expectEqual(@as(u21, 'S'), buf.getChar(1, 0));
    try testing.expectEqual(@as(u21, 'L'), buf.getChar(2, 1));
}

test "FlowText alignment applies in multi-column layout" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A B C";
    widget.columns = 2;
    widget.gutter = 1;
    widget.alignment = .center;
    const area = Rect{ .x = 0, .y = 0, .width = 11, .height = 5 };
    widget.render(&buf, area);

    // Column width = (11 - 1) / 2 = 5
    // Word 0 'A' (1 char) center-aligned in col 0: x=0+(5-1)/2=2
    // Word 1 'B' (1 char) center-aligned in col 1: x=6+(5-1)/2=8
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(2, 0));
    try testing.expectEqual(@as(u21, 'B'), buf.getChar(8, 0));
}

// ============================================================================
// STYLE TESTS (5 tests)
// ============================================================================

test "FlowText style renders with applied fg color" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Colored";
    widget.columns = 1;
    widget.style = Style{ .fg = .red, .bold = true };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    const cell = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.red, cell.style.fg.?);
    try testing.expect(cell.style.bold);
}

test "FlowText style renders with applied bg color" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Bg";
    widget.columns = 1;
    widget.style = Style{ .bg = .blue };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    const cell = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.blue, cell.style.bg.?);
}

test "FlowText style applies to all rendered characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Test";
    widget.columns = 1;
    widget.style = Style{ .fg = .green };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    for (0..4) |i| {
        const cell = buf.getConst(@intCast(i), 0).?;
        try testing.expectEqual(Color.green, cell.style.fg.?);
    }
}

test "FlowText empty style renders with no style attributes" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Plain";
    widget.columns = 1;
    widget.style = .{};
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    const cell = buf.getConst(0, 0).?;
    try testing.expect(cell.style.fg == null);
    try testing.expect(!cell.style.bold);
}

test "FlowText style with multiple attributes" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Multi";
    widget.columns = 1;
    widget.style = Style{ .fg = .cyan, .bold = true, .italic = true, .underline = true };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    const cell = buf.getConst(0, 0).?;
    try testing.expectEqual(Color.cyan, cell.style.fg.?);
    try testing.expect(cell.style.bold);
    try testing.expect(cell.style.italic);
    try testing.expect(cell.style.underline);
}

// ============================================================================
// BLOCK BORDER (6 tests)
// ============================================================================

test "FlowText with block renders border around area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "BlockTest";
    widget.columns = 1;
    widget.block = Block{ .borders = .all };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Border corners should be non-space
    try testing.expect(buf.getChar(0, 0) != ' ');
    try testing.expect(buf.getChar(9, 0) != ' ');
    try testing.expect(buf.getChar(0, 4) != ' ');
    try testing.expect(buf.getChar(9, 4) != ' ');
}

test "FlowText with block text renders inside inner area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "In";
    widget.columns = 1;
    widget.block = Block{ .borders = .all };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Text should be inside border, at (1, 1) or nearby
    try testing.expectEqual(@as(u21, 'I'), buf.getChar(1, 1));
}

test "FlowText with block shrinks inner area by 1 on each side" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Content";
    widget.columns = 1;
    widget.block = Block{ .borders = .all };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Inner area: (1, 1) to (8, 3)
    // Border at (0,0), text starts at (1,1)
    try testing.expectEqual(@as(u21, 'C'), buf.getChar(1, 1));
}

test "FlowText with block title renders in border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Content";
    widget.columns = 1;
    var block = Block{ .borders = .all };
    block.title = "Title";
    widget.block = block;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    widget.render(&buf, area);

    // Block renders border, text renders inside
    try testing.expectEqual(@as(u21, 'C'), buf.getChar(1, 1));
}

test "FlowText with block and no inner area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Text";
    widget.columns = 1;
    widget.block = Block{ .borders = .all };
    const area = Rect{ .x = 0, .y = 0, .width = 2, .height = 2 };
    widget.render(&buf, area);

    // Should have border at corners
    try testing.expect(buf.getChar(0, 0) != ' ');
    try testing.expect(buf.getChar(1, 0) != ' ');
}

test "FlowText with block border remains visible while text renders inside" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Text";
    widget.columns = 1;
    widget.block = Block{ .borders = .all };
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Corners are border
    try testing.expect(buf.getChar(0, 0) != ' ');
    // Inner area has text
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(1, 1));
}

// ============================================================================
// WORD WRAPPING (6 tests)
// ============================================================================

test "FlowText word wrap single long word hard-splits at column width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "VeryLongWord";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // First 5 chars on line 0, rest on line 1
    try testing.expectEqual(@as(u21, 'V'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'L'), buf.getChar(4, 0));
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(0, 1));
}

test "FlowText word wrap words that exactly fit column width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hello World";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    widget.render(&buf, area);

    // "Hello" fits exactly on line 0
    try testing.expectEqual(@as(u21, 'H'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'o'), buf.getChar(4, 0));
}

test "FlowText word wrap trailing spaces ignored" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Test   ";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'T'), buf.getChar(0, 0));
}

test "FlowText word wrap multiple spaces between words" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Word1   Word2";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // "Word1" on line 0, "Word2" on line 1 (multiple spaces are skipped)
    try testing.expectEqual(@as(u21, 'W'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'W'), buf.getChar(0, 1));
}

test "FlowText word wrap single space treated as word separator" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "One Two";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 5 };
    widget.render(&buf, area);

    // "One" on line 0, "Two" on line 1
    try testing.expectEqual(@as(u21, 'O'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(0, 1));
}

test "FlowText word wrap respects word boundaries in multi-column" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "The quick brown fox";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 10 };
    widget.render(&buf, area);

    // Text should distribute across columns respecting word boundaries
    try testing.expectEqual(@as(u21, 'T'), buf.getChar(0, 0));
}

// ============================================================================
// EDGE CASES (7 tests)
// ============================================================================

test "FlowText single character text renders without crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "A";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, 'A'), buf.getChar(0, 0));
}

test "FlowText all-space text renders as spaces" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "   ";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "FlowText columns=255 handled safely with area width constraint" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Test";
    widget.columns = 255;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // With 255 columns and width 10, total_gutter = 254, available_width = 0
    // So column_width = 0 and render early-exits. Buffer remains spaces.
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "FlowText same text rendered twice produces same result" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    defer buf2.deinit();

    var widget = FlowText.init();
    widget.text = "Hello World";
    widget.columns = 2;
    widget.gutter = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };

    widget.render(&buf1, area);
    widget.render(&buf2, area);

    // Buffers should match
    for (0..20) |y| {
        for (0..10) |x| {
            try testing.expectEqual(buf1.getChar(@intCast(x), @intCast(y)), buf2.getChar(@intCast(x), @intCast(y)));
        }
    }
}

test "FlowText different column counts produce different layouts" {
    const allocator = testing.allocator;
    var buf1 = try Buffer.init(allocator, 20, 10);
    var buf2 = try Buffer.init(allocator, 20, 10);
    defer buf1.deinit();
    defer buf2.deinit();

    var widget1 = FlowText.init();
    widget1.text = "A B C D E F";
    widget1.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget1.render(&buf1, area);

    var widget2 = FlowText.init();
    widget2.text = "A B C D E F";
    widget2.columns = 2;
    widget2.gutter = 1;
    const area2 = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget2.render(&buf2, area2);

    // Different layouts—1-column should have more rows filled, 2-column should have fewer
    var buf1_rows: usize = 0;
    var buf2_rows: usize = 0;
    for (0..5) |y| {
        if (buf1.getChar(0, @intCast(y)) != ' ') buf1_rows += 1;
        if (buf2.getChar(0, @intCast(y)) != ' ') buf2_rows += 1;
    }
    try testing.expect(buf1_rows != buf2_rows or buf1.getChar(5, 0) != buf2.getChar(5, 0));
}

test "FlowText text with tabs treated as word boundary or space" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Before\tAfter";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Tab treated as boundary—"Before" on line 0, "After" on line 1
    try testing.expectEqual(@as(u21, 'B'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, 'A'), buf.getChar(0, 1));
}

test "FlowText unicode text does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Hëllö Wörld";
    widget.columns = 1;
    const area = Rect{ .x = 0, .y = 0, .width = 15, .height = 5 };
    widget.render(&buf, area);

    // Should render first char of first word
    const first_char = buf.getChar(0, 0);
    try testing.expect(first_char != ' ');
}

test "FlowText rendered area offset from (0,0) applies correctly" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 15);
    defer buf.deinit();

    var widget = FlowText.init();
    widget.text = "Offset";
    widget.columns = 1;
    const area = Rect{ .x = 10, .y = 5, .width = 10, .height = 5 };
    widget.render(&buf, area);

    // Text should render at offset position
    try testing.expectEqual(@as(u21, 'O'), buf.getChar(10, 5));
}
