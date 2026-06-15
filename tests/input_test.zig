const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Input = sailor.tui.widgets.Input;
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const Color = sailor.tui.Color;

test "Input initialization with value" {
    const input = Input.init("hello");

    try testing.expectEqualStrings("hello", input.value);
    try testing.expectEqual(@as(usize, 0), input.cursor);
    try testing.expect(input.placeholder == null);
    try testing.expect(input.block == null);
}

test "Input initialization with empty value" {
    const input = Input.init("");

    try testing.expectEqualStrings("", input.value);
    try testing.expectEqual(@as(usize, 0), input.cursor);
}

test "Input.withCursor sets cursor position" {
    const input = Input.init("hello").withCursor(3);

    try testing.expectEqual(@as(usize, 3), input.cursor);
}

test "Input.withCursor preserves immutability" {
    const original = Input.init("test");
    const modified = original.withCursor(2);

    try testing.expectEqual(@as(usize, 0), original.cursor);
    try testing.expectEqual(@as(usize, 2), modified.cursor);
}

test "Input.withPlaceholder sets placeholder text" {
    const input = Input.init("").withPlaceholder("Enter text...");

    try testing.expectEqualStrings("Enter text...", input.placeholder.?);
}

test "Input.withStyle sets input style" {
    const style = Style{ .fg = Color.cyan };
    const input = Input.init("test").withStyle(style);

    try testing.expectEqual(Color.cyan, input.style.fg);
}

test "Input.withCursorStyle sets cursor style" {
    const style = Style{ .reverse = true };
    const input = Input.init("test").withCursorStyle(style);

    try testing.expect(input.cursor_style.reverse);
}

test "Input.withPlaceholderStyle sets placeholder style" {
    const style = Style{ .fg = Color.bright_black };
    const input = Input.init("").withPlaceholderStyle(style);

    try testing.expectEqual(Color.bright_black, input.placeholder_style.fg);
}

test "Input.withBlock sets block border" {
    const blk = Block{};
    const input = Input.init("test").withBlock(blk);

    try testing.expect(input.block != null);
}

test "Input render empty with placeholder" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("").withPlaceholder("Type here...");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Should show placeholder text
    try testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'y'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'p'), buf.get(2, 0).?.char);
}

test "Input render with text" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Should show text
    try testing.expectEqual(@as(u21, 'h'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).?.char);
}

test "Input render with cursor at start" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello").withCursor(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Cursor should be on first character with reverse style
    const cell = buf.get(0, 0).?;
    try testing.expect(cell.style.reverse);
}

test "Input render with cursor in middle" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello").withCursor(2);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Cursor should be on third character
    const cell = buf.get(2, 0).?;
    try testing.expect(cell.style.reverse);
}

test "Input render with cursor at end" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello").withCursor(5);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Cursor should be after last character with reverse style
    const cell = buf.get(5, 0).?;
    try testing.expect(cell.style.reverse);
}

test "Input render with custom cursor style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const cursor_style = Style{ .bold = true };
    const input = Input.init("hello")
        .withCursor(0)
        .withCursorStyle(cursor_style);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    input.render(&buf, area);

    const cell = buf.get(0, 0).?;
    try testing.expect(cell.style.bold);
}

test "Input render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const blk = Block{};
    const input = Input.init("hello").withBlock(blk);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };

    input.render(&buf, area);

    // Should have border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Text should be inside block (at y=1, x=1)
    try testing.expectEqual(@as(u21, 'h'), buf.get(1, 1).?.char);
}

test "Input render with narrow width truncates" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const input = Input.init("hello world");
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    input.render(&buf, area);

    // Should only show first 5 characters
    try testing.expectEqual(@as(u21, 'h'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).?.char);
}

test "Input render with horizontal scroll when cursor beyond visible" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const input = Input.init("hello world").withCursor(10);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    input.render(&buf, area);

    // Should scroll to show cursor
    // With cursor at position 10 and width 5, should show characters 6-10
    try testing.expectEqual(@as(u21, 'w'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'r'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'd'), buf.get(4, 0).?.char);
}

test "Input render empty with cursor shows cursor position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const input = Input.init("").withCursor(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };

    input.render(&buf, area);

    // Should show cursor at start
    const cell = buf.get(0, 0).?;
    try testing.expect(cell.style.reverse);
    try testing.expectEqual(@as(u21, ' '), cell.char);
}

test "Input render fills remaining space" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const input = Input.init("hi");
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };

    input.render(&buf, area);

    // First 2 chars should be text
    try testing.expectEqual(@as(u21, 'h'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).?.char);

    // Remaining should be filled with spaces
    for (2..10) |x| {
        try testing.expectEqual(@as(u21, ' '), buf.get(@intCast(x), 0).?.char);
    }
}

test "Input render with offset area position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const input = Input.init("test");
    const area = Rect{ .x = 5, .y = 3, .width = 10, .height = 1 };

    input.render(&buf, area);

    // Should render at offset position
    try testing.expectEqual(@as(u21, 't'), buf.get(5, 3).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(6, 3).?.char);
}

test "Input render zero width does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const input = Input.init("test");
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };

    input.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Input render zero height does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const input = Input.init("test");
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };

    input.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Input saveState captures value and cursor" {
    const input = Input.init("hello")
        .withCursor(3)
        .withPlaceholder("enter text");

    const state = input.saveState();

    try testing.expectEqualStrings("hello", state.value);
    try testing.expectEqual(@as(usize, 3), state.cursor);
    try testing.expectEqualStrings("enter text", state.placeholder.?);
}

test "Input restoreState restores all fields" {
    const original = Input.init("world")
        .withCursor(5)
        .withPlaceholder("type");

    const state = original.saveState();

    const fresh = Input.init("");
    const restored = fresh.restoreState(state);

    try testing.expectEqualStrings("world", restored.value);
    try testing.expectEqual(@as(usize, 5), restored.cursor);
    try testing.expectEqualStrings("type", restored.placeholder.?);
}

test "Input builder chain preserves immutability" {
    const original = Input.init("test");

    const modified = original
        .withCursor(2)
        .withPlaceholder("placeholder")
        .withStyle(.{ .bold = true });

    try testing.expectEqualStrings("test", original.value);
    try testing.expectEqual(@as(usize, 0), original.cursor);
    try testing.expect(original.placeholder == null);

    try testing.expectEqualStrings("test", modified.value);
    try testing.expectEqual(@as(usize, 2), modified.cursor);
    try testing.expectEqualStrings("placeholder", modified.placeholder.?);
}

test "Input render placeholder when empty overrides style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const input_style = Style{ .fg = Color.cyan };
    const placeholder_style = Style{ .fg = Color.bright_black };

    const input = Input.init("")
        .withPlaceholder("Text")
        .withStyle(input_style)
        .withPlaceholderStyle(placeholder_style);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    input.render(&buf, area);

    // Should use placeholder style since value is empty
    try testing.expectEqual(Color.bright_black, buf.get(0, 0).?.style.fg);
}

test "Input render uses input style when value present" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const input_style = Style{ .fg = Color.cyan };
    const placeholder_style = Style{ .fg = Color.bright_black };

    const input = Input.init("hello")
        .withPlaceholder("Text")
        .withStyle(input_style)
        .withPlaceholderStyle(placeholder_style);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    input.render(&buf, area);

    // Should use input style since value is present (position 1 since cursor=0 is at position 0)
    try testing.expectEqual(Color.cyan, buf.get(1, 0).?.style.fg);
}

test "Input render long text with cursor at end scrolls properly" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const input = Input.init("0123456789").withCursor(10);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    input.render(&buf, area);

    // Cursor is at position 10, with width 5, should show positions 6-10
    try testing.expectEqual(@as(u21, '6'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, '7'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, '8'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, '9'), buf.get(3, 0).?.char);
}

test "Input render placeholder only renders when text empty" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const input = Input.init("").withPlaceholder("Placeholder");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    try testing.expectEqual(@as(u21, 'P'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'l'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'a'), buf.get(2, 0).?.char);
}

test "Input render with block reduces inner area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const blk = Block{};
    const input = Input.init("hi").withBlock(blk);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };

    input.render(&buf, area);

    // Border at (0,0), text should be at (1,1)
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'h'), buf.get(1, 1).?.char);
}
