const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// TextArea widget - multi-line text editor with scroll
pub const TextArea = struct {
    lines: []const []const u8,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    row_offset: usize = 0,
    col_offset: usize = 0,
    block: ?Block = null,
    text_style: Style = .{},
    cursor_style: Style = .{ .reverse = true },
    show_cursor: bool = true,
    show_line_numbers: bool = false,
    line_number_style: Style = .{ .dim = true },

    /// Create a textarea with lines
    pub fn init(lines: []const []const u8) TextArea {
        return .{ .lines = lines };
    }

    /// Set cursor position (row, col)
    pub fn withCursor(self: TextArea, row: usize, col: usize) TextArea {
        var result = self;
        result.cursor_row = row;
        result.cursor_col = col;
        return result;
    }

    /// Set scroll offsets
    pub fn withOffset(self: TextArea, row_offset: usize, col_offset: usize) TextArea {
        var result = self;
        result.row_offset = row_offset;
        result.col_offset = col_offset;
        return result;
    }

    /// Set the block (border) for this textarea
    pub fn withBlock(self: TextArea, new_block: Block) TextArea {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set the style for text
    pub fn withTextStyle(self: TextArea, new_style: Style) TextArea {
        var result = self;
        result.text_style = new_style;
        return result;
    }

    /// Set the style for cursor
    pub fn withCursorStyle(self: TextArea, new_style: Style) TextArea {
        var result = self;
        result.cursor_style = new_style;
        return result;
    }

    /// Show or hide cursor
    pub fn withShowCursor(self: TextArea, show: bool) TextArea {
        var result = self;
        result.show_cursor = show;
        return result;
    }

    /// Show or hide line numbers
    pub fn withShowLineNumbers(self: TextArea, show: bool) TextArea {
        var result = self;
        result.show_line_numbers = show;
        return result;
    }

    /// Set line number style
    pub fn withLineNumberStyle(self: TextArea, new_style: Style) TextArea {
        var result = self;
        result.line_number_style = new_style;
        return result;
    }

    /// Calculate line number gutter width (if enabled)
    fn gutterWidth(self: TextArea) u16 {
        if (!self.show_line_numbers) return 0;

        // Calculate width needed for line numbers
        const max_line = self.lines.len;
        var width: u16 = 1; // At least 1 digit
        var n = max_line;
        while (n >= 10) : (n /= 10) {
            width += 1;
        }
        return width + 2; // +1 for space, +1 for separator
    }

    /// Render the textarea widget
    pub fn render(self: TextArea, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Calculate gutter
        const gutter_w = self.gutterWidth();
        if (gutter_w >= inner_area.width) return;

        // Text area starts after gutter
        const text_x = inner_area.x + gutter_w;
        const text_width = inner_area.width - gutter_w;

        // Calculate visible line range
        const visible_lines = @min(self.lines.len, inner_area.height);
        var row_start = @min(self.row_offset, self.lines.len);

        // Auto-scroll to keep cursor visible
        if (self.cursor_row >= row_start + visible_lines) {
            row_start = self.cursor_row - visible_lines + 1;
        } else if (self.cursor_row < row_start) {
            row_start = self.cursor_row;
        }

        const row_end = @min(row_start + visible_lines, self.lines.len);

        // Render visible lines
        var screen_y = inner_area.y;
        for (self.lines[row_start..row_end], row_start..) |line, line_idx| {
            if (screen_y >= inner_area.y + inner_area.height) break;

            // Render line number gutter
            if (self.show_line_numbers) {
                const line_num = line_idx + 1;
                var num_buf: [16]u8 = undefined;
                const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{line_num}) catch unreachable;

                // Right-align line numbers
                const num_x = inner_area.x + gutter_w - num_str.len - 2;
                buf.setString(num_x, screen_y, num_str, self.line_number_style);

                // Separator
                buf.setString(inner_area.x + gutter_w - 1, screen_y, " ", self.line_number_style);
            }

            // Calculate visible column range for horizontal scrolling
            var col_start = @min(self.col_offset, line.len);

            // Auto-scroll horizontally to keep cursor visible
            if (line_idx == self.cursor_row) {
                if (self.cursor_col >= col_start + text_width) {
                    col_start = self.cursor_col - text_width + 1;
                } else if (self.cursor_col < col_start) {
                    col_start = self.cursor_col;
                }
            }

            const col_end = @min(col_start + text_width, line.len);
            const visible_text = line[col_start..col_end];

            // Render text
            var text_x_pos = text_x;
            for (visible_text, col_start..) |ch, col_idx| {
                if (text_x_pos >= inner_area.x + inner_area.width) break;

                const is_cursor = self.show_cursor and
                    line_idx == self.cursor_row and
                    col_idx == self.cursor_col;

                const cell_style = if (is_cursor) self.cursor_style else self.text_style;
                buf.set(text_x_pos, screen_y, ch, cell_style);
                text_x_pos += 1;
            }

            // Render cursor at end of line if needed
            if (self.show_cursor and
                line_idx == self.cursor_row and
                self.cursor_col == line.len and
                self.cursor_col >= col_start and
                self.cursor_col < col_start + text_width)
            {
                const cursor_x = text_x + (self.cursor_col - col_start);
                if (cursor_x < inner_area.x + inner_area.width) {
                    buf.set(cursor_x, screen_y, ' ', self.cursor_style);
                }
            }

            screen_y += 1;
        }
    }
};

// Tests
test "TextArea: create empty" {
    const textarea = TextArea.init(&.{});
    try std.testing.expectEqual(@as(usize, 0), textarea.lines.len);
    try std.testing.expectEqual(@as(usize, 0), textarea.cursor_row);
    try std.testing.expectEqual(@as(usize, 0), textarea.cursor_col);
}

test "TextArea: create with lines" {
    const lines = [_][]const u8{ "Line 1", "Line 2", "Line 3" };
    const textarea = TextArea.init(&lines);
    try std.testing.expectEqual(@as(usize, 3), textarea.lines.len);
    try std.testing.expectEqualStrings("Line 1", textarea.lines[0]);
}

test "TextArea: with cursor" {
    const lines = [_][]const u8{"Line"};
    const textarea = TextArea.init(&lines).withCursor(1, 5);
    try std.testing.expectEqual(@as(usize, 1), textarea.cursor_row);
    try std.testing.expectEqual(@as(usize, 5), textarea.cursor_col);
}

test "TextArea: with offset" {
    const lines = [_][]const u8{"Line"};
    const textarea = TextArea.init(&lines).withOffset(2, 3);
    try std.testing.expectEqual(@as(usize, 2), textarea.row_offset);
    try std.testing.expectEqual(@as(usize, 3), textarea.col_offset);
}

test "TextArea: with block" {
    const lines = [_][]const u8{"Line"};
    const blk = Block.init();
    const textarea = TextArea.init(&lines).withBlock(blk);
    try std.testing.expect(textarea.block != null);
}

test "TextArea: with text style" {
    const lines = [_][]const u8{"Line"};
    const style = Style{ .bold = true };
    const textarea = TextArea.init(&lines).withTextStyle(style);
    try std.testing.expect(textarea.text_style.bold);
}

test "TextArea: with cursor style" {
    const lines = [_][]const u8{"Line"};
    const style = Style{ .underline = true };
    const textarea = TextArea.init(&lines).withCursorStyle(style);
    try std.testing.expect(textarea.cursor_style.underline);
}

test "TextArea: with show cursor" {
    const lines = [_][]const u8{"Line"};
    const textarea = TextArea.init(&lines).withShowCursor(false);
    try std.testing.expect(!textarea.show_cursor);
}

test "TextArea: with show line numbers" {
    const lines = [_][]const u8{"Line"};
    const textarea = TextArea.init(&lines).withShowLineNumbers(true);
    try std.testing.expect(textarea.show_line_numbers);
}

test "TextArea: with line number style" {
    const lines = [_][]const u8{"Line"};
    const style = Style{ .italic = true };
    const textarea = TextArea.init(&lines).withLineNumberStyle(style);
    try std.testing.expect(textarea.line_number_style.italic);
}

test "TextArea: gutter width without line numbers" {
    const lines = [_][]const u8{"Line"};
    const textarea = TextArea.init(&lines);
    try std.testing.expectEqual(@as(u16, 0), textarea.gutterWidth());
}

test "TextArea: gutter width with line numbers" {
    const lines = [_][]const u8{ "L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10" };
    const textarea = TextArea.init(&lines).withShowLineNumbers(true);
    // 10 lines = 2 digits + 2 (space + separator) = 4
    try std.testing.expectEqual(@as(u16, 4), textarea.gutterWidth());
}

test "TextArea: gutter width with 100+ lines" {
    var lines: [100][]const u8 = undefined;
    for (&lines) |*line| {
        line.* = "text";
    }
    const textarea = TextArea.init(&lines).withShowLineNumbers(true);
    // 100 lines = 3 digits + 2 = 5
    try std.testing.expectEqual(@as(u16, 5), textarea.gutterWidth());
}

test "TextArea: render empty" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const textarea = TextArea.init(&.{});
    textarea.render(&buf, Rect.init(0, 0, 10, 5));

    // Should not crash
}

test "TextArea: render single line" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Check first line
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
}

test "TextArea: render multiple lines" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const lines = [_][]const u8{ "Line 1", "Line 2", "Line 3" };
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, Rect.init(0, 0, 20, 10));

    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 2).char);
}

test "TextArea: render with cursor" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withCursor(0, 2)
        .withCursorStyle(Style{ .reverse = true });

    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Cursor should be at position 2
    try std.testing.expect(buf.get(2, 0).style.reverse);
}

test "TextArea: render with cursor at end of line" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hi"};
    const textarea = TextArea.init(&lines)
        .withCursor(0, 2) // After last char
        .withCursorStyle(Style{ .reverse = true });

    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Cursor should be at position 2 (space)
    try std.testing.expect(buf.get(2, 0).style.reverse);
}

test "TextArea: render without cursor" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withCursor(0, 2)
        .withShowCursor(false);

    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // No cell should have reverse style
    try std.testing.expect(!buf.get(2, 0).style.reverse);
}

test "TextArea: render with line numbers" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{ "Line 1", "Line 2" };
    const textarea = TextArea.init(&lines).withShowLineNumbers(true);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Line numbers should be rendered (1 and 2)
    try std.testing.expectEqual(@as(u21, '1'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(0, 1).char);
}

test "TextArea: render with row offset" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4" };
    const textarea = TextArea.init(&lines).withOffset(2, 0);
    textarea.render(&buf, Rect.init(0, 0, 20, 3));

    // Should show L3, L4 (skipping L1, L2)
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '3'), buf.get(1, 0).char);
}

test "TextArea: render with col offset" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines).withOffset(0, 6);
    textarea.render(&buf, Rect.init(0, 0, 10, 3));

    // Should show "World" (skipping "Hello ")
    try std.testing.expectEqual(@as(u21, 'W'), buf.get(0, 0).char);
}

test "TextArea: render with block" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Text"};
    const blk = Block.init();
    const textarea = TextArea.init(&lines).withBlock(blk);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Should render both block and content
}

test "TextArea: render zero size area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Text"};
    const textarea = TextArea.init(&lines);

    // Should not crash
    textarea.render(&buf, Rect.init(0, 0, 0, 5));
    textarea.render(&buf, Rect.init(0, 0, 10, 0));
}

test "TextArea: auto-scroll vertical" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4", "L5" };
    // Cursor on line 4, should auto-scroll
    const textarea = TextArea.init(&lines).withCursor(4, 0);
    textarea.render(&buf, Rect.init(0, 0, 20, 3));

    // Should show L3, L4, L5 to keep cursor visible
}

test "TextArea: auto-scroll horizontal" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"This is a very long line"};
    // Cursor at column 20, should auto-scroll
    const textarea = TextArea.init(&lines).withCursor(0, 20);
    textarea.render(&buf, Rect.init(0, 0, 10, 3));

    // Should scroll to show cursor position
}

test "TextArea: long lines truncate" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, Rect.init(0, 0, 5, 3));

    // Should only show "Hello"
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
}

test "TextArea: many lines overflow" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4" };
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, Rect.init(0, 0, 20, 2));

    // Should only show first 2 lines
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(1, 1).char);
}
