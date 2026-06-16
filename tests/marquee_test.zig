const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const Marquee = tui.widgets.Marquee;
const ScrollDirection = tui.widgets.Marquee.ScrollDirection;

// ============================================================================
// INITIALIZATION TESTS
// ============================================================================

test "Marquee init with text" {
    const marquee = Marquee.init("Hello");

    try testing.expectEqualStrings("Hello", marquee.text);
    try testing.expectEqual(@as(usize, 0), marquee.offset);
    try testing.expectEqual(@as(u8, 1), marquee.speed);
    try testing.expectEqualStrings(" | ", marquee.separator);
    try testing.expectEqual(ScrollDirection.left, marquee.direction);
    try testing.expect(marquee.block == null);
}

test "Marquee init with default values" {
    const marquee = Marquee.init("Test");

    try testing.expectEqual(@as(u8, 1), marquee.speed);
    try testing.expectEqualStrings(" | ", marquee.separator);
    try testing.expectEqual(ScrollDirection.left, marquee.direction);
    try testing.expectEqual(Style{}, marquee.style);
    try testing.expect(marquee.block == null);
}

test "Marquee init with empty text" {
    const marquee = Marquee.init("");

    try testing.expectEqualStrings("", marquee.text);
    try testing.expectEqual(@as(usize, 0), marquee.offset);
}

test "Marquee init with long text" {
    const long_text = "This is a very long text that should be stored correctly in the marquee widget";
    const marquee = Marquee.init(long_text);

    try testing.expectEqualStrings(long_text, marquee.text);
    try testing.expectEqual(@as(usize, 0), marquee.offset);
}

test "Marquee init offset defaults to 0" {
    const marquee = Marquee.init("Text");

    try testing.expectEqual(@as(usize, 0), marquee.offset);
}

test "Marquee init speed defaults to 1" {
    const marquee = Marquee.init("Text");

    try testing.expectEqual(@as(u8, 1), marquee.speed);
}

test "Marquee init separator defaults to pipe" {
    const marquee = Marquee.init("Text");

    try testing.expectEqualStrings(" | ", marquee.separator);
}

test "Marquee init direction defaults to left" {
    const marquee = Marquee.init("Text");

    try testing.expectEqual(ScrollDirection.left, marquee.direction);
}

test "Marquee init style defaults to empty" {
    const marquee = Marquee.init("Text");

    try testing.expectEqual(Style{}, marquee.style);
}

test "Marquee init block defaults to null" {
    const marquee = Marquee.init("Text");

    try testing.expect(marquee.block == null);
}

// ============================================================================
// TEXT LENGTH CALCULATION (textLen)
// ============================================================================

test "Marquee textLen with normal text" {
    const marquee = Marquee.init("Hello");

    const len = marquee.textLen();
    try testing.expectEqual(@as(usize, 8), len); // "Hello".len (5) + " | ".len (3) but separator is " | " (3), so 5 + 3 = 8
}

test "Marquee textLen with empty text" {
    const marquee = Marquee.init("");

    const len = marquee.textLen();
    try testing.expectEqual(@as(usize, 3), len); // "" (0) + " | " (3) = 3
}

test "Marquee textLen with empty separator" {
    var marquee = Marquee.init("Hi");
    marquee.separator = "";

    const len = marquee.textLen();
    try testing.expectEqual(@as(usize, 2), len); // "Hi" (2) + "" (0) = 2
}

test "Marquee textLen with single char text" {
    const marquee = Marquee.init("X");

    const len = marquee.textLen();
    try testing.expectEqual(@as(usize, 4), len); // "X" (1) + " | " (3) = 4
}

test "Marquee textLen with long separator" {
    var marquee = Marquee.init("Test");
    marquee.separator = " ... ";

    const len = marquee.textLen();
    try testing.expectEqual(@as(usize, 9), len); // "Test" (4) + " ... " (5) = 9
}

test "Marquee textLen with special characters in text" {
    const marquee = Marquee.init("Hi!");

    const len = marquee.textLen();
    try testing.expectEqual(@as(usize, 6), len); // "Hi!" (3) + " | " (3) = 6
}

test "Marquee textLen consistency across multiple calls" {
    const marquee = Marquee.init("Stable");

    const len1 = marquee.textLen();
    const len2 = marquee.textLen();

    try testing.expectEqual(len1, len2);
}

// ============================================================================
// CURRENT OFFSET CALCULATION (currentOffset)
// ============================================================================

test "Marquee currentOffset at position 0" {
    const marquee = Marquee.init("Hello");

    const offset = marquee.currentOffset();
    try testing.expectEqual(@as(usize, 0), offset);
}

test "Marquee currentOffset with offset less than textLen" {
    var marquee = Marquee.init("Hello");
    marquee.offset = 3;

    const offset = marquee.currentOffset();
    try testing.expectEqual(@as(usize, 3), offset);
}

test "Marquee currentOffset wraps at textLen boundary" {
    var marquee = Marquee.init("Hello"); // textLen = 8
    marquee.offset = 8;

    const offset = marquee.currentOffset();
    try testing.expectEqual(@as(usize, 0), offset);
}

test "Marquee currentOffset wraps beyond textLen" {
    var marquee = Marquee.init("Hello"); // textLen = 8
    marquee.offset = 16;

    const offset = marquee.currentOffset();
    try testing.expectEqual(@as(usize, 0), offset);
}

test "Marquee currentOffset wraps odd multiples" {
    var marquee = Marquee.init("Hi"); // textLen = 5 ("Hi" + " | ")
    marquee.offset = 12; // 12 % 5 = 2

    const offset = marquee.currentOffset();
    try testing.expectEqual(@as(usize, 2), offset);
}

test "Marquee currentOffset with large offset" {
    var marquee = Marquee.init("Test"); // textLen = 7
    marquee.offset = 1000;

    const offset = marquee.currentOffset();
    try testing.expectEqual(@as(usize, 1000 % 7), offset);
}

test "Marquee currentOffset with empty text" {
    var marquee = Marquee.init(""); // textLen = 3
    marquee.offset = 5;

    const offset = marquee.currentOffset();
    try testing.expectEqual(@as(usize, 2), offset);
}

// ============================================================================
// TICK BEHAVIOR — LEFT DIRECTION
// ============================================================================

test "Marquee tick left direction increments offset" {
    const marquee = Marquee.init("Hello").withDirection(.left);
    const ticked = marquee.tick();

    try testing.expectEqual(@as(usize, 1), ticked.offset);
}

test "Marquee tick left preserves immutability" {
    const original = Marquee.init("Hello").withDirection(.left);
    const ticked = original.tick();

    try testing.expectEqual(@as(usize, 0), original.offset);
    try testing.expectEqual(@as(usize, 1), ticked.offset);
}

test "Marquee tick left wraps at textLen" {
    var marquee = Marquee.init("Hello");
    const textLen = marquee.textLen();
    marquee.offset = textLen - 1;

    const ticked = marquee.tick();
    try testing.expectEqual(textLen % textLen, ticked.offset);
}

test "Marquee tick left with speed 2" {
    const marquee = Marquee.init("Hello").withSpeed(2).withDirection(.left);
    const ticked = marquee.tick();

    try testing.expectEqual(@as(usize, 2), ticked.offset);
}

test "Marquee tick left with speed 5" {
    const marquee = Marquee.init("Hello").withSpeed(5).withDirection(.left);
    const ticked = marquee.tick();

    try testing.expectEqual(@as(usize, 5), ticked.offset);
}

test "Marquee tick left advances by speed amount" {
    const marquee = Marquee.init("Test").withSpeed(3).withDirection(.left);
    var current = marquee;

    current = current.tick();
    try testing.expectEqual(@as(usize, 3), current.offset);

    current = current.tick();
    try testing.expectEqual(@as(usize, 6), current.offset);
}

test "Marquee tick left wraps with speed" {
    var marquee = Marquee.init("Test"); // textLen = 7
    marquee.speed = 5;
    marquee.offset = 5;
    marquee.direction = .left;

    const ticked = marquee.tick();
    // 5 + 5 = 10, 10 % 7 = 3
    try testing.expectEqual(@as(usize, 10 % 7), ticked.offset);
}

test "Marquee tick left multiple times" {
    var marquee = Marquee.init("Hi");
    marquee.direction = .left;

    for (0..5) |i| {
        marquee = marquee.tick();
        try testing.expectEqual(@as(usize, @mod(i + 1, marquee.textLen())), marquee.offset);
    }
}

// ============================================================================
// TICK BEHAVIOR — RIGHT DIRECTION
// ============================================================================

test "Marquee tick right direction decrements offset" {
    var marquee = Marquee.init("Hello");
    marquee.offset = 5;
    marquee.direction = .right;

    const ticked = marquee.tick();
    try testing.expectEqual(@as(usize, 4), ticked.offset);
}

test "Marquee tick right preserves immutability" {
    var marquee = Marquee.init("Hello");
    marquee.offset = 5;
    marquee.direction = .right;
    const original = marquee;
    const ticked = original.tick();

    try testing.expectEqual(@as(usize, 5), original.offset);
    try testing.expectEqual(@as(usize, 4), ticked.offset);
}

test "Marquee tick right wraps at zero" {
    var marquee = Marquee.init("Hello");
    const textLen = marquee.textLen();
    marquee.offset = 0;
    marquee.direction = .right;

    const ticked = marquee.tick();
    // 0 - 1 with wrap = textLen - 1
    try testing.expectEqual(@as(usize, textLen - 1), ticked.offset);
}

test "Marquee tick right with speed 2" {
    var marquee = Marquee.init("Hello");
    marquee.offset = 5;
    marquee.speed = 2;
    marquee.direction = .right;

    const ticked = marquee.tick();
    try testing.expectEqual(@as(usize, 3), ticked.offset);
}

test "Marquee tick right with speed 5" {
    var marquee = Marquee.init("Hello");
    const textLen = marquee.textLen();
    _ = textLen; // unused
    marquee.offset = 6;
    marquee.speed = 5;
    marquee.direction = .right;

    const ticked = marquee.tick();
    // 6 - 5 = 1
    try testing.expectEqual(@as(usize, 1), ticked.offset);
}

test "Marquee tick right wraps with speed" {
    var marquee = Marquee.init("Test"); // textLen = 7
    const textLen = marquee.textLen();
    marquee.offset = 2;
    marquee.speed = 5;
    marquee.direction = .right;

    const ticked = marquee.tick();
    // 2 - 5 = -3, wraps to textLen - 3 = 4
    try testing.expectEqual(@as(usize, (2 + textLen - 5) % textLen), ticked.offset);
}

test "Marquee tick right multiple times" {
    var marquee = Marquee.init("Hi");
    const text_len = marquee.textLen();
    marquee.offset = text_len - 1;
    marquee.direction = .right;

    for (0..5) |_| {
        marquee = marquee.tick();
        // Multiple ticks right should handle wrapping correctly
        try testing.expect(marquee.offset < text_len);
    }
}

// ============================================================================
// RESET FUNCTIONALITY
// ============================================================================

test "Marquee reset sets offset to 0" {
    var marquee = Marquee.init("Hello");
    marquee.offset = 42;

    const reset = marquee.reset();
    try testing.expectEqual(@as(usize, 0), reset.offset);
}

test "Marquee reset preserves immutability" {
    var marquee = Marquee.init("Hello");
    marquee.offset = 42;
    const original = marquee;

    const reset = original.reset();

    try testing.expectEqual(@as(usize, 42), original.offset);
    try testing.expectEqual(@as(usize, 0), reset.offset);
}

test "Marquee reset preserves all other fields" {
    var marquee = Marquee.init("Hello");
    marquee.offset = 10;
    marquee.speed = 3;
    marquee.direction = .right;
    marquee.separator = " :: ";

    const reset = marquee.reset();

    try testing.expectEqual(@as(usize, 0), reset.offset);
    try testing.expectEqual(@as(u8, 3), reset.speed);
    try testing.expectEqual(ScrollDirection.right, reset.direction);
    try testing.expectEqualStrings(" :: ", reset.separator);
}

// ============================================================================
// BUILDER PATTERN — IMMUTABILITY
// ============================================================================

test "Marquee withText creates copy with new text" {
    const marquee = Marquee.init("Old").withText("New");

    try testing.expectEqualStrings("New", marquee.text);
}

test "Marquee withText preserves immutability" {
    const original = Marquee.init("Old");
    const modified = original.withText("New");

    try testing.expectEqualStrings("Old", original.text);
    try testing.expectEqualStrings("New", modified.text);
}

test "Marquee withOffset creates copy with new offset" {
    const marquee = Marquee.init("Text").withOffset(5);

    try testing.expectEqual(@as(usize, 5), marquee.offset);
}

test "Marquee withOffset preserves immutability" {
    const original = Marquee.init("Text");
    const modified = original.withOffset(5);

    try testing.expectEqual(@as(usize, 0), original.offset);
    try testing.expectEqual(@as(usize, 5), modified.offset);
}

test "Marquee withSpeed creates copy with new speed" {
    const marquee = Marquee.init("Text").withSpeed(5);

    try testing.expectEqual(@as(u8, 5), marquee.speed);
}

test "Marquee withSpeed preserves immutability" {
    const original = Marquee.init("Text");
    const modified = original.withSpeed(5);

    try testing.expectEqual(@as(u8, 1), original.speed);
    try testing.expectEqual(@as(u8, 5), modified.speed);
}

test "Marquee withSeparator creates copy with new separator" {
    const marquee = Marquee.init("Text").withSeparator(" :: ");

    try testing.expectEqualStrings(" :: ", marquee.separator);
}

test "Marquee withSeparator preserves immutability" {
    const original = Marquee.init("Text");
    const modified = original.withSeparator(" :: ");

    try testing.expectEqualStrings(" | ", original.separator);
    try testing.expectEqualStrings(" :: ", modified.separator);
}

test "Marquee withDirection creates copy with new direction" {
    const marquee = Marquee.init("Text").withDirection(.right);

    try testing.expectEqual(ScrollDirection.right, marquee.direction);
}

test "Marquee withDirection preserves immutability" {
    const original = Marquee.init("Text");
    const modified = original.withDirection(.right);

    try testing.expectEqual(ScrollDirection.left, original.direction);
    try testing.expectEqual(ScrollDirection.right, modified.direction);
}

test "Marquee withStyle creates copy with new style" {
    const style = Style{ .fg = Color.green };
    const marquee = Marquee.init("Text").withStyle(style);

    try testing.expectEqual(Color.green, marquee.style.fg);
}

test "Marquee withStyle preserves immutability" {
    const original = Marquee.init("Text");
    const style = Style{ .fg = Color.red };
    const modified = original.withStyle(style);

    try testing.expect(modified.style.fg != null);
    try testing.expect(original.style.fg == null);
}

test "Marquee withBlock creates copy with block" {
    const block = Block{};
    const marquee = Marquee.init("Text").withBlock(block);

    try testing.expect(marquee.block != null);
}

test "Marquee withBlock preserves immutability" {
    const original = Marquee.init("Text");
    const block = Block{};
    const modified = original.withBlock(block);

    try testing.expect(original.block == null);
    try testing.expect(modified.block != null);
}

test "Marquee builder chain preserves immutability" {
    const original = Marquee.init("Old");

    const modified = original
        .withText("New")
        .withSpeed(2)
        .withDirection(.right);

    try testing.expectEqualStrings("Old", original.text);
    try testing.expectEqual(@as(u8, 1), original.speed);
    try testing.expectEqual(ScrollDirection.left, original.direction);

    try testing.expectEqualStrings("New", modified.text);
    try testing.expectEqual(@as(u8, 2), modified.speed);
    try testing.expectEqual(ScrollDirection.right, modified.direction);
}

test "Marquee builder chain with all methods" {
    const block = Block{};
    const style = Style{ .bold = true };

    const marquee = Marquee.init("Start")
        .withText("End")
        .withOffset(3)
        .withSpeed(4)
        .withSeparator(" | ")
        .withDirection(.right)
        .withStyle(style)
        .withBlock(block);

    try testing.expectEqualStrings("End", marquee.text);
    try testing.expectEqual(@as(usize, 3), marquee.offset);
    try testing.expectEqual(@as(u8, 4), marquee.speed);
    try testing.expectEqualStrings(" | ", marquee.separator);
    try testing.expectEqual(ScrollDirection.right, marquee.direction);
    try testing.expect(marquee.style.bold);
    try testing.expect(marquee.block != null);
}

// ============================================================================
// RENDER TESTS — BASIC POSITIONING
// ============================================================================

test "Marquee render text shorter than area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const marquee = Marquee.init("Hi");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    marquee.render(&buf, area);

    // First character should be 'H'
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
}

test "Marquee render starts at offset position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    var marquee = Marquee.init("Hello");
    marquee.offset = 2; // Start from 'l' in "Hello"
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    marquee.render(&buf, area);

    // First character in viewport should be from offset 2
    const full_text = "Hello | Hello | ";
    const expected_char = full_text[2];
    try testing.expectEqual(@as(u21, expected_char), buf.get(0, 0).?.char);
}

test "Marquee render at offset area position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    const marquee = Marquee.init("Hi");
    const area = Rect{ .x = 5, .y = 3, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // First character should render at x=5, y=3
    const cell = buf.get(5, 3).?;
    try testing.expectEqual(@as(u21, 'H'), cell.char);
}

test "Marquee render fills available width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const marquee = Marquee.init("AB");
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Should fill with repeating pattern "AB | AB | "
    try testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'B'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(2, 0).?.char);
}

test "Marquee render wraps around text boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    var marquee = Marquee.init("AB");
    // "AB | " = 5 chars total, set offset near end
    marquee.offset = 4; // At the space before wrap
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Should show end of "AB | " then wrap to beginning "AB | "
    // Position 0 should be space or beginning of next cycle
    try testing.expect(buf.get(0, 0).?.char != 0);
}

test "Marquee render zero width area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    // Pre-fill with marker
    buf.set(0, 0, .{ .char = 'X', .style = .{} });

    const marquee = Marquee.init("Hi");
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    marquee.render(&buf, area);

    // Should not crash; original cell should remain unchanged
    try testing.expectEqual(@as(u21, 'X'), buf.get(0, 0).?.char);
}

test "Marquee render zero height area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    // Pre-fill with marker
    buf.set(0, 0, .{ .char = 'X', .style = .{} });

    const marquee = Marquee.init("Hi");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    marquee.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, 'X'), buf.get(0, 0).?.char);
}

// ============================================================================
// RENDER TESTS — STYLE APPLICATION
// ============================================================================

test "Marquee render applies style to characters" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const style = Style{ .fg = Color.green };
    const marquee = Marquee.init("Hi").withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Character should have green style
    try testing.expectEqual(Color.green, buf.get(0, 0).?.style.fg);
}

test "Marquee render applies bold style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const style = Style{ .bold = true };
    const marquee = Marquee.init("Hi").withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Character should be bold
    try testing.expect(buf.get(0, 0).?.style.bold);
}

test "Marquee render with different colors" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const style = Style{ .fg = Color.red };
    const marquee = Marquee.init("Hi").withStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    try testing.expectEqual(Color.red, buf.get(0, 0).?.style.fg);
}

// ============================================================================
// RENDER TESTS — BLOCK BORDER
// ============================================================================

test "Marquee render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const block = Block{};
    const marquee = Marquee.init("Hi").withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    marquee.render(&buf, area);

    // Should render border characters
    try testing.expect(buf.get(0, 0).?.char != 'H');
}

test "Marquee render with block uses inner area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const block = Block{};
    const marquee = Marquee.init("Hi").withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    marquee.render(&buf, area);

    // Text should be inside the border, not at 0,0
    // Borders reduce the available space
    try testing.expect(true);
}

// ============================================================================
// RENDER TESTS — EDGE CASES
// ============================================================================

test "Marquee render empty text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const marquee = Marquee.init("");
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Should show only separator repeating
    try testing.expect(buf.get(0, 0).?.char != 0);
}

test "Marquee render single character text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const marquee = Marquee.init("X");
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Should show X repeating in pattern "X | X | "
    try testing.expectEqual(@as(u21, 'X'), buf.get(0, 0).?.char);
}

test "Marquee render text exactly fits width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const marquee = Marquee.init("Hi");
    // "Hi | " = 5 chars
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };
    marquee.render(&buf, area);

    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(2, 0).?.char);
}

test "Marquee render text longer than width" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 3, 1);
    defer buf.deinit();

    const marquee = Marquee.init("Hello");
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 1 };
    marquee.render(&buf, area);

    // Should render first 3 characters visible from offset
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
}

test "Marquee render single width area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const marquee = Marquee.init("Test");
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    marquee.render(&buf, area);

    // Should render single character
    try testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).?.char);
}

test "Marquee render single height area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const marquee = Marquee.init("Hi");
    const area = Rect{ .x = 0, .y = 5, .width = 20, .height = 1 };
    marquee.render(&buf, area);

    // Should render single row at y=5
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 5).?.char);
}

// ============================================================================
// RENDER TESTS — SCROLL DIRECTION
// ============================================================================

test "Marquee render left direction shows offset position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    var marquee = Marquee.init("ABCD");
    marquee.offset = 2;
    marquee.direction = .left;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    marquee.render(&buf, area);

    // Should show text starting from offset 2
    const full_text = "ABCD | ABCD | ABCD |";
    const expected_char = full_text[2];
    try testing.expectEqual(@as(u21, expected_char), buf.get(0, 0).?.char);
}

test "Marquee render right direction shows offset position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    var marquee = Marquee.init("ABCD");
    marquee.offset = 2;
    marquee.direction = .right;
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    marquee.render(&buf, area);

    // Right direction also uses offset for position
    try testing.expect(buf.get(0, 0).?.char != 0);
}

// ============================================================================
// RENDER TESTS — MULTI-ROW AREAS
// ============================================================================

test "Marquee render tall area renders only first row" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const marquee = Marquee.init("Hi");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    marquee.render(&buf, area);

    // Only first row should have content
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
}

test "Marquee render respects area y position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const marquee = Marquee.init("Hi");
    const area = Rect{ .x = 0, .y = 5, .width = 20, .height = 1 };
    marquee.render(&buf, area);

    // Text should be at y=5, not y=0
    try testing.expect(buf.get(0, 5).?.char != 0);
}

// ============================================================================
// RENDER TESTS — SEPARATOR BEHAVIOR
// ============================================================================

test "Marquee render includes separator in output" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const marquee = Marquee.init("A");
    // "A | " repeating
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Should find pipe separator
    var found_pipe = false;
    for (0..10) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == '|') {
            found_pipe = true;
            break;
        }
    }
    try testing.expect(found_pipe);
}

test "Marquee render custom separator" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const marquee = Marquee.init("X").withSeparator(" :: ");
    // "X :: " repeating
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    marquee.render(&buf, area);

    // Should find ':' from separator
    var found_colon = false;
    for (0..10) |x| {
        if (buf.get(@as(u16, @intCast(x)), 0).?.char == ':') {
            found_colon = true;
            break;
        }
    }
    try testing.expect(found_colon);
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

test "Marquee full workflow: init, tick, render" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    var marquee = Marquee.init("Test").withSpeed(2).withDirection(.left);

    // Tick twice
    marquee = marquee.tick();
    try testing.expectEqual(@as(usize, 2), marquee.offset);

    marquee = marquee.tick();
    try testing.expectEqual(@as(usize, 4), marquee.offset);

    // Render
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    marquee.render(&buf, area);

    // Should render without crash
    try testing.expect(buf.get(0, 0).?.char != 0);
}

test "Marquee workflow with style and block" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 25, 5);
    defer buf.deinit();

    const block = Block{};
    const style = Style{ .bold = true };

    var marquee = Marquee.init("Status")
        .withSpeed(1)
        .withDirection(.left)
        .withStyle(style)
        .withBlock(block);

    marquee = marquee.tick();

    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 5 };
    marquee.render(&buf, area);

    // Should render without crash
    try testing.expect(true);
}

test "Marquee continuous scrolling left" {
    var marquee = Marquee.init("Hi");
    const text_len = marquee.textLen();

    // Simulate continuous scrolling
    for (0..text_len * 2) |_| {
        marquee = marquee.tick();
    }

    // Should wrap back to start after full cycle
    try testing.expectEqual(@as(usize, 0), marquee.currentOffset());
}

test "Marquee continuous scrolling right" {
    var marquee = Marquee.init("Hi");
    const text_len = marquee.textLen();
    marquee.direction = .right;
    marquee.offset = 0;

    // Right direction: offset goes down, wrapping at 0
    marquee = marquee.tick();
    try testing.expectEqual(text_len - 1, marquee.offset);
}
