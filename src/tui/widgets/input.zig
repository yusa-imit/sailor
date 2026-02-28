const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Single-line text input widget with cursor
pub const Input = struct {
    /// Current text content
    value: []const u8 = "",

    /// Cursor position (character index, not byte index)
    cursor: usize = 0,

    /// Placeholder text when empty
    placeholder: ?[]const u8 = null,

    /// Input style
    style: Style = .{},

    /// Cursor style
    cursor_style: Style = .{ .attrs = .{ .reverse = true } },

    /// Placeholder style
    placeholder_style: Style = .{ .fg = .{ .basic = .dark_gray } },

    /// Optional block for borders/title
    block: ?Block = null,

    /// Create a new input widget
    pub fn init(value: []const u8) Input {
        return .{ .value = value };
    }

    /// Set cursor position
    pub fn withCursor(self: Input, pos: usize) Input {
        var result = self;
        result.cursor = pos;
        return result;
    }

    /// Set placeholder text
    pub fn withPlaceholder(self: Input, text: []const u8) Input {
        var result = self;
        result.placeholder = text;
        return result;
    }

    /// Set input style
    pub fn withStyle(self: Input, new_style: Style) Input {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Set cursor style
    pub fn withCursorStyle(self: Input, new_style: Style) Input {
        var result = self;
        result.cursor_style = new_style;
        return result;
    }

    /// Set placeholder style
    pub fn withPlaceholderStyle(self: Input, new_style: Style) Input {
        var result = self;
        result.placeholder_style = new_style;
        return result;
    }

    /// Set block for borders/title
    pub fn withBlock(self: Input, new_block: Block) Input {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Render the input widget
    pub fn render(self: Input, buf: *Buffer, area: Rect) void {
        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.innerArea(area);
        }

        // Nothing to render if area too small
        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Only render on first line
        const y = inner_area.y;
        const x_start = inner_area.x;
        const width = inner_area.width;

        // Determine what to display
        const display_text = if (self.value.len > 0) self.value else (self.placeholder orelse "");
        const display_style = if (self.value.len > 0) self.style else self.placeholder_style;

        // Convert cursor position from character index to byte index
        var cursor_byte_pos: usize = 0;
        var char_count: usize = 0;
        var byte_idx: usize = 0;
        while (byte_idx < self.value.len and char_count < self.cursor) : (char_count += 1) {
            const char_len = std.unicode.utf8ByteSequenceLength(self.value[byte_idx]) catch 1;
            cursor_byte_pos = byte_idx + char_len;
            byte_idx += char_len;
        }

        // Calculate visible window (scroll if cursor is outside visible area)
        var scroll_offset: usize = 0;
        var visible_chars: usize = 0;
        var visible_byte_len: usize = 0;

        // First pass: determine how many characters fit in width
        byte_idx = 0;
        while (byte_idx < display_text.len and visible_chars < width) {
            const char_len = std.unicode.utf8ByteSequenceLength(display_text[byte_idx]) catch 1;
            visible_byte_len = byte_idx + char_len;
            visible_chars += 1;
            byte_idx += char_len;
        }

        // Scroll if cursor is beyond visible area
        if (self.cursor >= visible_chars) {
            scroll_offset = self.cursor - visible_chars + 1;
        }

        // Skip scroll_offset characters
        byte_idx = 0;
        char_count = 0;
        while (byte_idx < display_text.len and char_count < scroll_offset) : (char_count += 1) {
            const char_len = std.unicode.utf8ByteSequenceLength(display_text[byte_idx]) catch 1;
            byte_idx += char_len;
        }
        const start_byte = byte_idx;

        // Determine visible slice
        visible_chars = 0;
        while (byte_idx < display_text.len and visible_chars < width) {
            const char_len = std.unicode.utf8ByteSequenceLength(display_text[byte_idx]) catch 1;
            visible_byte_len = byte_idx + char_len;
            visible_chars += 1;
            byte_idx += char_len;
        }
        const visible_text = display_text[start_byte..visible_byte_len];

        // Render visible text
        var x = x_start;
        var text_byte_idx: usize = 0;
        char_count = scroll_offset;

        while (x < x_start + width and text_byte_idx < visible_text.len) {
            const char_len = std.unicode.utf8ByteSequenceLength(visible_text[text_byte_idx]) catch 1;
            const char_bytes = visible_text[text_byte_idx..][0..char_len];
            const codepoint = std.unicode.utf8Decode(char_bytes) catch ' ';

            // Use cursor style if this is the cursor position
            const char_style = if (char_count == self.cursor and self.value.len > 0)
                self.cursor_style
            else
                display_style;

            buf.setCell(x, y, codepoint, char_style);
            x += 1;
            text_byte_idx += char_len;
            char_count += 1;
        }

        // If cursor is at end or input is empty, show cursor after last character
        if (self.cursor == char_count and x < x_start + width) {
            buf.setCell(x, y, ' ', self.cursor_style);
            x += 1;
        }

        // Fill remaining space
        while (x < x_start + width) {
            buf.setCell(x, y, ' ', self.style);
            x += 1;
        }
    }
};

// Tests

test "Input.init" {
    const input = Input.init("hello");

    try std.testing.expectEqualStrings("hello", input.value);
    try std.testing.expectEqual(0, input.cursor);
    try std.testing.expect(input.placeholder == null);
}

test "Input.withCursor" {
    const input = Input.init("hello").withCursor(3);

    try std.testing.expectEqual(3, input.cursor);
}

test "Input.withPlaceholder" {
    const input = Input.init("").withPlaceholder("Enter text...");

    try std.testing.expectEqualStrings("Enter text...", input.placeholder.?);
}

test "Input.withStyle" {
    const input_style = Style{ .fg = .{ .basic = .cyan } };
    const input = Input.init("test").withStyle(input_style);

    try std.testing.expectEqual(Color{ .basic = .cyan }, input.style.fg.?);
}

test "Input.withCursorStyle" {
    const cursor_style = Style{ .attrs = .{ .bold = true } };
    const input = Input.init("test").withCursorStyle(cursor_style);

    try std.testing.expect(input.cursor_style.attrs.bold);
}

test "Input.withPlaceholderStyle" {
    const placeholder_style = Style{ .fg = .{ .basic = .dark_gray } };
    const input = Input.init("").withPlaceholderStyle(placeholder_style);

    try std.testing.expectEqual(Color{ .basic = .dark_gray }, input.placeholder_style.fg.?);
}

test "Input.withBlock" {
    const blk = Block.init().withBorders(block_mod.Borders.all);
    const input = Input.init("test").withBlock(blk);

    try std.testing.expect(input.block != null);
}

test "Input.render empty with placeholder" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("").withPlaceholder("Type here...");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Should show placeholder
    const cell = buf.getCell(0, 0);
    try std.testing.expectEqual('T', cell.char);
}

test "Input.render with text" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Should show text
    try std.testing.expectEqual('h', buf.getCell(0, 0).char);
    try std.testing.expectEqual('e', buf.getCell(1, 0).char);
    try std.testing.expectEqual('l', buf.getCell(2, 0).char);
    try std.testing.expectEqual('l', buf.getCell(3, 0).char);
    try std.testing.expectEqual('o', buf.getCell(4, 0).char);
}

test "Input.render with cursor at start" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello").withCursor(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Cursor should be on first character
    const cell = buf.getCell(0, 0);
    try std.testing.expect(cell.style.attrs.reverse);
}

test "Input.render with cursor in middle" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello").withCursor(2);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Cursor should be on third character
    const cell = buf.getCell(2, 0);
    try std.testing.expect(cell.style.attrs.reverse);
}

test "Input.render with cursor at end" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const input = Input.init("hello").withCursor(5);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    input.render(&buf, area);

    // Cursor should be after last character
    const cell = buf.getCell(5, 0);
    try std.testing.expect(cell.style.attrs.reverse);
}

test "Input.render with block" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const blk = Block.init().withBorders(block_mod.Borders.all);
    const input = Input.init("hello").withBlock(blk);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };

    input.render(&buf, area);

    // Should have border
    const corner = buf.getCell(0, 0);
    try std.testing.expectEqual('┌', corner.char);

    // Text should be inside block
    const text_cell = buf.getCell(1, 1);
    try std.testing.expectEqual('h', text_cell.char);
}

test "Input.render with narrow width" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const input = Input.init("hello world");
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    input.render(&buf, area);

    // Should only show first 5 characters
    try std.testing.expectEqual('h', buf.getCell(0, 0).char);
    try std.testing.expectEqual('e', buf.getCell(1, 0).char);
    try std.testing.expectEqual('l', buf.getCell(2, 0).char);
    try std.testing.expectEqual('l', buf.getCell(3, 0).char);
    try std.testing.expectEqual('o', buf.getCell(4, 0).char);
}

test "Input.render with scroll (cursor beyond visible)" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 5, 1);
    defer buf.deinit();

    const input = Input.init("hello world").withCursor(10);
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    input.render(&buf, area);

    // Should scroll to show cursor
    // With cursor at position 10 and width 5, should show characters 6-10
    try std.testing.expectEqual('w', buf.getCell(0, 0).char);
    try std.testing.expectEqual('o', buf.getCell(1, 0).char);
    try std.testing.expectEqual('r', buf.getCell(2, 0).char);
    try std.testing.expectEqual('l', buf.getCell(3, 0).char);
    try std.testing.expectEqual('d', buf.getCell(4, 0).char);
}

test "Input.render with Unicode characters" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const input = Input.init("你好世界");
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };

    input.render(&buf, area);

    // Should render CJK characters
    try std.testing.expectEqual('你', buf.getCell(0, 0).char);
    try std.testing.expectEqual('好', buf.getCell(1, 0).char);
    try std.testing.expectEqual('世', buf.getCell(2, 0).char);
    try std.testing.expectEqual('界', buf.getCell(3, 0).char);
}

test "Input.render empty with cursor" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const input = Input.init("").withCursor(0);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };

    input.render(&buf, area);

    // Should show cursor at start
    const cell = buf.getCell(0, 0);
    try std.testing.expect(cell.style.attrs.reverse);
    try std.testing.expectEqual(' ', cell.char);
}
