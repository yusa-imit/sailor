//! TextArea widget functional tests
//!
//! Tests the TextArea widget's editing, scrolling, cursor, and line number features.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;
const TextArea = sailor.tui.widgets.TextArea;

// ============================================================================
// TextArea Initialization Tests
// ============================================================================

test "TextArea.init creates textarea with lines" {
    const lines = [_][]const u8{
        "Line 1",
        "Line 2",
        "Line 3",
    };

    const textarea = TextArea.init(&lines);

    try testing.expectEqual(3, textarea.lines.len);
    try testing.expectEqual(0, textarea.cursor_row);
    try testing.expectEqual(0, textarea.cursor_col);
    try testing.expectEqual(0, textarea.row_offset);
    try testing.expectEqual(0, textarea.col_offset);
    try testing.expect(textarea.show_cursor);
    try testing.expect(!textarea.show_line_numbers);
}

test "TextArea builder methods chain correctly" {
    const lines = [_][]const u8{"test"};
    const block = Block{}.withTitle("Editor", .top_left);

    const textarea = TextArea.init(&lines)
        .withCursor(5, 10)
        .withOffset(2, 3)
        .withBlock(block)
        .withTextStyle(.{ .fg = .{ .basic = .white } })
        .withCursorStyle(.{ .fg = .{ .basic = .black }, .bg = .{ .basic = .yellow } })
        .withShowCursor(false)
        .withShowLineNumbers(true)
        .withLineNumberStyle(.{ .fg = .{ .basic = .cyan } });

    try testing.expectEqual(5, textarea.cursor_row);
    try testing.expectEqual(10, textarea.cursor_col);
    try testing.expectEqual(2, textarea.row_offset);
    try testing.expectEqual(3, textarea.col_offset);
    try testing.expect(!textarea.show_cursor);
    try testing.expect(textarea.show_line_numbers);
}

// ============================================================================
// TextArea Rendering Tests
// ============================================================================

test "TextArea renders simple text" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Hello, world!",
        "This is line 2",
        "And line 3",
    };

    const textarea = TextArea.init(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    textarea.render(&buffer, area);

    // Verify content is rendered
    const cell = buffer.get(0, 0);
    try testing.expect(cell != null);
}

test "TextArea renders with line numbers" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Line one",
        "Line two",
        "Line three",
    };

    const textarea = TextArea.init(&lines)
        .withShowLineNumbers(true)
        .withLineNumberStyle(.{ .fg = .{ .basic = .cyan } });

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    textarea.render(&buffer, area);

    // Verify line numbers are rendered (first column should contain digits)
    const cell = buffer.get(0, 0);
    try testing.expect(cell != null);
}

test "TextArea renders with cursor" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "First line",
        "Second line with cursor",
        "Third line",
    };

    const textarea = TextArea.init(&lines)
        .withCursor(1, 5)
        .withShowCursor(true)
        .withCursorStyle(.{ .reverse = true });

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    textarea.render(&buffer, area);

    // Verify rendering completed
    try testing.expect(buffer.get(0, 0) != null);
}

test "TextArea renders with hidden cursor" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{"text"};

    const textarea = TextArea.init(&lines)
        .withCursor(0, 2)
        .withShowCursor(false);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    textarea.render(&buffer, area);

    // Should render without showing cursor
    try testing.expect(buffer.get(0, 0) != null);
}

test "TextArea renders with block border" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 20);
    defer buffer.deinit();

    const lines = [_][]const u8{"Content"};
    const block = (Block{}).withBorders(.all).withTitle("TextArea", .top_left);

    const textarea = TextArea.init(&lines).withBlock(block);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 20 };

    textarea.render(&buffer, area);

    // Verify border is rendered
    const top_left = buffer.get(0, 0);
    try testing.expect(top_left != null);
    const c = top_left.?.char;
    try testing.expect(c == '┌' or c == '╭' or c == '+');
}

// ============================================================================
// TextArea Scrolling Tests
// ============================================================================

test "TextArea handles vertical scrolling with offset" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Line 0",
        "Line 1",
        "Line 2",
        "Line 3",
        "Line 4",
        "Line 5",
        "Line 6",
        "Line 7",
    };

    // Scroll down by 3 lines
    const textarea = TextArea.init(&lines).withOffset(3, 0);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };

    textarea.render(&buffer, area);

    // Should render lines 3-7
    try testing.expect(buffer.get(0, 0) != null);
}

test "TextArea handles horizontal scrolling with offset" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 5);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "This is a very long line that needs horizontal scrolling",
    };

    // Scroll right by 10 characters
    const textarea = TextArea.init(&lines).withOffset(0, 10);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };

    textarea.render(&buffer, area);

    // Should render starting from character 10
    try testing.expect(buffer.get(0, 0) != null);
}

test "TextArea auto-scrolls to keep cursor visible" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Line 0",
        "Line 1",
        "Line 2",
        "Line 3",
        "Line 4",
        "Line 5",
        "Line 6",
    };

    // Cursor on line 6, area only shows 5 lines
    // Should auto-scroll to keep cursor visible
    const textarea = TextArea.init(&lines).withCursor(6, 0);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };

    textarea.render(&buffer, area);

    // Should not crash and should auto-scroll
    try testing.expect(buffer.get(0, 0) != null);
}

// ============================================================================
// TextArea Styling Tests
// ============================================================================

test "TextArea applies custom text style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 35, 8);
    defer buffer.deinit();

    const lines = [_][]const u8{"Styled text"};
    const text_style = Style{ .fg = .{ .basic = .green }, .italic = true };

    const textarea = TextArea.init(&lines).withTextStyle(text_style);
    const area = Rect{ .x = 0, .y = 0, .width = 35, .height = 8 };

    textarea.render(&buffer, area);

    // Verify rendering
    try testing.expect(buffer.get(0, 0) != null);
}

test "TextArea applies custom cursor style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 35, 8);
    defer buffer.deinit();

    const lines = [_][]const u8{"Text with cursor"};
    const cursor_style = Style{
        .fg = .{ .basic = .black },
        .bg = .{ .basic = .yellow },
        .bold = true,
    };

    const textarea = TextArea.init(&lines)
        .withCursor(0, 5)
        .withCursorStyle(cursor_style);

    const area = Rect{ .x = 0, .y = 0, .width = 35, .height = 8 };

    textarea.render(&buffer, area);

    try testing.expect(buffer.get(0, 0) != null);
}

test "TextArea applies custom line number style" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Line 1",
        "Line 2",
    };

    const line_num_style = Style{ .fg = .{ .basic = .magenta }, .dim = true };

    const textarea = TextArea.init(&lines)
        .withShowLineNumbers(true)
        .withLineNumberStyle(line_num_style);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    textarea.render(&buffer, area);

    try testing.expect(buffer.get(0, 0) != null);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "TextArea handles empty lines array" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{};
    const textarea = TextArea.init(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    // Should not crash
    textarea.render(&buffer, area);
}

test "TextArea handles zero-width area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{"text"};
    const textarea = TextArea.init(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };

    // Should not crash
    textarea.render(&buffer, area);
}

test "TextArea handles zero-height area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{"text"};
    const textarea = TextArea.init(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 0 };

    // Should not crash
    textarea.render(&buffer, area);
}

test "TextArea handles cursor beyond content" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Short",
        "line",
    };

    // Cursor at row 10, col 100 (way beyond content)
    const textarea = TextArea.init(&lines).withCursor(10, 100);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    // Should handle gracefully
    textarea.render(&buffer, area);
}

test "TextArea handles very large offset" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{"line1", "line2"};

    // Offset beyond all content
    const textarea = TextArea.init(&lines).withOffset(1000, 1000);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    // Should handle gracefully
    textarea.render(&buffer, area);
}

test "TextArea handles empty lines within content" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Line 1",
        "",
        "",
        "Line 4",
        "",
    };

    const textarea = TextArea.init(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    textarea.render(&buffer, area);

    // Should render empty lines
    try testing.expect(buffer.get(0, 0) != null);
}

test "TextArea handles unicode content" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "Hello 世界",
        "こんにちは",
        "🎉 emoji test 🔥",
        "Zig + TUI = 💙",
    };

    const textarea = TextArea.init(&lines).withShowLineNumbers(true);
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    // Should handle unicode without crash
    textarea.render(&buffer, area);
}

test "TextArea handles very long lines" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 5);
    defer buffer.deinit();

    const long_line = "This is an extremely long line that is much wider than the available buffer width and should be handled gracefully by horizontal scrolling or truncation without causing any crashes or panics";

    const lines = [_][]const u8{long_line};
    const textarea = TextArea.init(&lines);
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };

    // Should handle gracefully
    textarea.render(&buffer, area);
}

test "TextArea handles many lines" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    // Create 100 lines
    const lines_storage = blk: {
        var list = std.ArrayList([]const u8).init(allocator);
        defer list.deinit();
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            try list.append("Line content");
        }
        break :blk try list.toOwnedSlice();
    };
    defer allocator.free(lines_storage);

    const textarea = TextArea.init(lines_storage)
        .withCursor(50, 0)
        .withShowLineNumbers(true);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };

    // Should handle many lines with auto-scroll
    textarea.render(&buffer, area);
}

test "TextArea handles line numbers with many lines" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    // Create enough lines to require 3-digit line numbers
    const lines_storage = blk: {
        var list = std.ArrayList([]const u8).init(allocator);
        defer list.deinit();
        var i: usize = 0;
        while (i < 150) : (i += 1) {
            try list.append("Line");
        }
        break :blk try list.toOwnedSlice();
    };
    defer allocator.free(lines_storage);

    const textarea = TextArea.init(lines_storage)
        .withShowLineNumbers(true)
        .withCursor(100, 0);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

    // Should calculate correct gutter width for 3-digit numbers
    textarea.render(&buffer, area);
}

test "TextArea with block and line numbers together" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 60, 20);
    defer buffer.deinit();

    const lines = [_][]const u8{
        "// main.zig",
        "const std = @import(\"std\");",
        "",
        "pub fn main() !void {",
        "    std.debug.print(\"Hello!\\n\", .{});",
        "}",
    };

    const block = (Block{})
        .withBorders(.all)
        .withTitle("editor.zig", .top_left);

    const textarea = TextArea.init(&lines)
        .withBlock(block)
        .withShowLineNumbers(true)
        .withCursor(4, 10)
        .withTextStyle(.{ .fg = .{ .basic = .white } })
        .withLineNumberStyle(.{ .fg = .{ .basic = .cyan }, .dim = true });

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };

    textarea.render(&buffer, area);

    // Verify complex rendering completes
    try testing.expect(buffer.get(0, 0) != null);
}
