const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Line wrapping mode
pub const WrapMode = enum {
    none, // No wrapping, horizontal scroll
    soft, // Wrap at word boundaries (or char if no spaces)
    hard, // Wrap at exact width boundary
};

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
    wrap_mode: WrapMode = .none,
    selection_start_row: usize = 0,
    selection_start_col: usize = 0,
    selection_end_row: usize = 0,
    selection_end_col: usize = 0,
    selection_style: Style = .{ .reverse = true },
    highlighter: ?*const fn ([]const u8, usize) Style = null,

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

    /// Set wrap mode
    pub fn withWrapMode(self: TextArea, mode: WrapMode) TextArea {
        var result = self;
        result.wrap_mode = mode;
        return result;
    }

    /// Set selection range (start_row, start_col, end_row, end_col)
    pub fn withSelection(self: TextArea, start_row: usize, start_col: usize, end_row: usize, end_col: usize) TextArea {
        var result = self;
        result.selection_start_row = start_row;
        result.selection_start_col = start_col;
        result.selection_end_row = end_row;
        result.selection_end_col = end_col;
        return result;
    }

    /// Set selection style
    pub fn withSelectionStyle(self: TextArea, new_style: Style) TextArea {
        var result = self;
        result.selection_style = new_style;
        return result;
    }

    /// Set syntax highlighter callback
    pub fn withHighlighter(self: TextArea, new_highlighter: *const fn ([]const u8, usize) Style) TextArea {
        var result = self;
        result.highlighter = new_highlighter;
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

    /// Check if a position is within the selection range
    fn isInSelection(self: TextArea, row: usize, col: usize) bool {
        // Normalize selection to forward direction
        var start_row = self.selection_start_row;
        var start_col = self.selection_start_col;
        var end_row = self.selection_end_row;
        var end_col = self.selection_end_col;

        if (start_row > end_row or (start_row == end_row and start_col > end_col)) {
            const tmp_row = start_row;
            const tmp_col = start_col;
            start_row = end_row;
            start_col = end_col;
            end_row = tmp_row;
            end_col = tmp_col;
        }

        // Empty selection
        if (start_row == end_row and start_col == end_col) return false;

        // Check if position is in range
        if (row < start_row or row > end_row) return false;
        if (row == start_row and col < start_col) return false;
        if (row == end_row and col >= end_col) return false;

        return true;
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
                const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{line_num}) catch |err| {
                    // Fallback if line number is impossibly large (> 16 digits)
                    _ = err;
                    continue;
                };

                // Right-align line numbers
                const num_x = inner_area.x + gutter_w - num_str.len - 2;
                buf.setString(num_x, screen_y, num_str, self.line_number_style);

                // Separator
                buf.setString(inner_area.x + gutter_w - 1, screen_y, " ", self.line_number_style);
            }

            // Handle wrapping
            if (self.wrap_mode != .none and line.len > text_width) {
                screen_y = self.renderWrappedLine(buf, inner_area, line, line_idx, screen_y, text_x, text_width);
                continue;
            }

            // Calculate visible column range for horizontal scrolling (no wrap mode)
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

            // Render text with style precedence: text_style < highlighter < selection_style < cursor_style
            var text_x_pos = text_x;
            for (visible_text, col_start..) |ch, col_idx| {
                if (text_x_pos >= inner_area.x + inner_area.width) break;

                const is_cursor = self.show_cursor and
                    line_idx == self.cursor_row and
                    col_idx == self.cursor_col;

                // Style precedence order
                var cell_style = self.text_style;

                // Apply highlighter if present
                if (self.highlighter) |h| {
                    cell_style = h(line, col_idx);
                }

                // Apply selection style
                if (self.isInSelection(line_idx, col_idx)) {
                    cell_style = self.selection_style;
                }

                // Cursor always wins
                if (is_cursor) {
                    cell_style = self.cursor_style;
                }

                buf.set(text_x_pos, screen_y, .{ .char = ch, .style = cell_style });
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
                    buf.set(cursor_x, screen_y, .{ .char = ' ', .style = self.cursor_style });
                }
            }

            screen_y += 1;
        }
    }

    /// Render a wrapped line (soft or hard wrap)
    fn renderWrappedLine(self: TextArea, buf: *Buffer, inner_area: Rect, line: []const u8, line_idx: usize, start_y: u16, text_x: u16, text_width: u16) u16 {
        var screen_y = start_y;
        var col_offset: usize = 0;

        while (col_offset < line.len) {
            if (screen_y >= inner_area.y + inner_area.height) break;

            // Determine wrap point
            const remaining = line[col_offset..];
            const chunk_len = if (remaining.len <= text_width)
                remaining.len
            else switch (self.wrap_mode) {
                .none => unreachable, // Should not be called with .none
                .hard => text_width,
                .soft => blk: {
                    // Find last space within text_width
                    var last_space: ?usize = null;
                    var i: usize = 0;
                    while (i < text_width and i < remaining.len) : (i += 1) {
                        if (remaining[i] == ' ') {
                            last_space = i;
                        }
                    }
                    // If we found a space, wrap there; otherwise wrap at width
                    break :blk if (last_space) |sp| sp + 1 else text_width;
                },
            };

            const chunk = remaining[0..chunk_len];

            // Render chunk
            var text_x_pos = text_x;
            for (chunk, col_offset..) |ch, col_idx| {
                if (text_x_pos >= inner_area.x + inner_area.width) break;

                const is_cursor = self.show_cursor and
                    line_idx == self.cursor_row and
                    col_idx == self.cursor_col;

                // Style precedence order
                var cell_style = self.text_style;

                // Apply highlighter if present
                if (self.highlighter) |h| {
                    cell_style = h(line, col_idx);
                }

                // Apply selection style
                if (self.isInSelection(line_idx, col_idx)) {
                    cell_style = self.selection_style;
                }

                // Cursor always wins
                if (is_cursor) {
                    cell_style = self.cursor_style;
                }

                buf.set(text_x_pos, screen_y, .{ .char = ch, .style = cell_style });
                text_x_pos += 1;
            }

            col_offset += chunk_len;
            screen_y += 1;
        }

        return screen_y;
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
    const blk = (Block{});
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
    const blk = (Block{});
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

// ====================================
// Line Wrapping Tests (11 tests)
// ====================================

test "TextArea: WrapMode enum exists with .none variant" {
    const lines = [_][]const u8{"text"};
    const textarea = TextArea.init(&lines).withWrapMode(.none);
    try std.testing.expectEqual(WrapMode.none, textarea.wrap_mode);
}

test "TextArea: WrapMode enum exists with .soft variant" {
    const lines = [_][]const u8{"text"};
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    try std.testing.expectEqual(WrapMode.soft, textarea.wrap_mode);
}

test "TextArea: WrapMode enum exists with .hard variant" {
    const lines = [_][]const u8{"text"};
    const textarea = TextArea.init(&lines).withWrapMode(.hard);
    try std.testing.expectEqual(WrapMode.hard, textarea.wrap_mode);
}

test "TextArea: soft wrap splits at word boundaries" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World Test"};
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, Rect.init(0, 0, 10, 5));

    // Should wrap "Hello World" on line 0, "Test" on line 1
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 1).char);
}

test "TextArea: soft wrap respects char boundaries when no spaces" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"HelloWorld"};
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, Rect.init(0, 0, 5, 5));

    // Should wrap at char 5: "Hello" then "World"
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'W'), buf.get(0, 1).char);
}

test "TextArea: hard wrap inserts line breaks at width boundary" {
    var buf = try Buffer.init(std.testing.allocator, 8, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines).withWrapMode(.hard);
    textarea.render(&buf, Rect.init(0, 0, 8, 5));

    // Hard wrap should split at width 8: "Hello Wo" then "rld"
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(4, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(5, 0).char);
    try std.testing.expectEqual(@as(u21, 'W'), buf.get(6, 0).char);
    try std.testing.expectEqual(@as(u21, 'r'), buf.get(0, 1).char);
}

test "TextArea: cursor navigation respects wrapped lines" {
    const lines = [_][]const u8{"Hello World Test"};
    const textarea = TextArea.init(&lines)
        .withWrapMode(.soft)
        .withCursor(0, 12); // Cursor on "Test" word
    try std.testing.expectEqual(@as(usize, 0), textarea.cursor_row);
    try std.testing.expectEqual(@as(usize, 12), textarea.cursor_col);
}

test "TextArea: wrapped lines count correctly for scrolling" {
    var buf = try Buffer.init(std.testing.allocator, 5, 2);
    defer buf.deinit();

    const lines = [_][]const u8{"Short", "Very long line that wraps"};
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, Rect.init(0, 0, 5, 2));

    // Should render "Short" on line 0
    try std.testing.expectEqual(@as(u21, 'S'), buf.get(0, 0).char);
}

test "TextArea: wrap mode none disables wrapping" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines).withWrapMode(.none);
    textarea.render(&buf, Rect.init(0, 0, 5, 5));

    // Should truncate at width 5, no wrapping
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(4, 0).char); // Last visible char
}

test "TextArea: wrap handles empty lines correctly" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const lines = [_][]const u8{ "Hello", "", "World" };
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, Rect.init(0, 0, 10, 5));

    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 1).char); // Empty line
    try std.testing.expectEqual(@as(u21, 'W'), buf.get(0, 2).char);
}

test "TextArea: wrap handles trailing spaces" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hi   "};
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, Rect.init(0, 0, 5, 5));

    // "Hi   " fits in width 5, no wrap needed
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).char);
}

// ====================================
// Selection Support Tests (13 tests)
// ====================================

test "TextArea: selection with start and end on same line" {
    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines)
        .withSelection(0, 0, 0, 5); // Select "Hello"
    try std.testing.expectEqual(@as(usize, 0), textarea.selection_start_row);
    try std.testing.expectEqual(@as(usize, 0), textarea.selection_start_col);
    try std.testing.expectEqual(@as(usize, 0), textarea.selection_end_row);
    try std.testing.expectEqual(@as(usize, 5), textarea.selection_end_col);
}

test "TextArea: selection across multiple lines" {
    const lines = [_][]const u8{ "Line 1", "Line 2", "Line 3" };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 3, 2, 4); // From "e 1" to "e 3"
    try std.testing.expectEqual(@as(usize, 0), textarea.selection_start_row);
    try std.testing.expectEqual(@as(usize, 3), textarea.selection_start_col);
    try std.testing.expectEqual(@as(usize, 2), textarea.selection_end_row);
    try std.testing.expectEqual(@as(usize, 4), textarea.selection_end_col);
}

test "TextArea: forward selection renders with selection style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 1, 0, 4) // Select "ell"
        .withSelectionStyle(sel_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Chars 1-3 should have selection style
    try std.testing.expect(buf.get(1, 0).style.reverse);
    try std.testing.expect(buf.get(2, 0).style.reverse);
    try std.testing.expect(buf.get(3, 0).style.reverse);
}

test "TextArea: backward selection renders correctly" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 4, 0, 1) // Backward selection
        .withSelectionStyle(sel_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Should normalize to forward selection (1-3)
    try std.testing.expect(buf.get(1, 0).style.reverse);
}

test "TextArea: empty selection does not render" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 2, 0, 2) // Empty selection
        .withSelectionStyle(sel_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // No cell should have reverse style
    try std.testing.expect(!buf.get(2, 0).style.reverse);
}

test "TextArea: selection style does not override cursor style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const sel_style = Style{ .reverse = true };
    const cursor_style = Style{ .bold = true, .reverse = true };
    const textarea = TextArea.init(&lines)
        .withCursor(0, 2)
        .withSelection(0, 1, 0, 4)
        .withSelectionStyle(sel_style)
        .withCursorStyle(cursor_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Cursor at position 2 should have cursor_style (bold + reverse)
    try std.testing.expect(buf.get(2, 0).style.bold);
}

test "TextArea: selection style overrides text style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const text_style = Style{ .italic = true };
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withTextStyle(text_style)
        .withSelection(0, 1, 0, 3)
        .withSelectionStyle(sel_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Selection region should have reverse, not italic
    try std.testing.expect(buf.get(1, 0).style.reverse);
    try std.testing.expect(!buf.get(1, 0).style.italic);
}

test "TextArea: style precedence order is text < selection < cursor" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const text_style = Style{ .italic = true };
    const sel_style = Style{ .reverse = true };
    const cursor_style = Style{ .bold = true };
    const textarea = TextArea.init(&lines)
        .withTextStyle(text_style)
        .withSelection(0, 0, 0, 5)
        .withSelectionStyle(sel_style)
        .withCursor(0, 2)
        .withCursorStyle(cursor_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Position 0: selection style
    try std.testing.expect(buf.get(0, 0).style.reverse);
    // Position 2 (cursor): cursor style
    try std.testing.expect(buf.get(2, 0).style.bold);
}

test "TextArea: selection scrolls horizontally when needed" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World Test"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 6, 0, 11) // Select "World"
        .withSelectionStyle(sel_style)
        .withOffset(0, 6); // Scroll to show selection
    textarea.render(&buf, Rect.init(0, 0, 5, 3));

    // At offset 6, we see "World", chars 0-4 should have selection style
    try std.testing.expect(buf.get(0, 0).style.reverse); // 'W'
}

test "TextArea: selection scrolls vertically when needed" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4" };
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(2, 0, 3, 2) // Select L3 and L4
        .withSelectionStyle(sel_style)
        .withOffset(2, 0); // Scroll to show selection
    textarea.render(&buf, Rect.init(0, 0, 20, 2));

    // Should show L3 and L4 (rows 2-3), both with selection
    try std.testing.expect(buf.get(0, 0).style.reverse); // L3
}

test "TextArea: selection handles boundary clamping at line start" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withSelection(0, 0, 0, 0); // At line start (empty selection)
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Empty selection should not render any selection style
    try std.testing.expect(!buf.get(0, 0).style.reverse);
}

test "TextArea: selection handles boundary clamping at line end" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withSelection(0, 5, 0, 5); // At line end (empty selection)
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Empty selection should not render
    try std.testing.expect(!buf.get(4, 0).style.reverse);
}

test "TextArea: selection clamps to valid line indices" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"L1", "L2"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 0, 10, 0) // Row 10 doesn't exist
        .withSelectionStyle(sel_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Should select from row 0 to row 1 (clamped)
    try std.testing.expect(buf.get(0, 0).style.reverse);
}

// ====================================
// Syntax Highlighting Tests (7 tests)
// ====================================

test "TextArea: highlighter callback function pointer type exists" {
    const lines = [_][]const u8{"text"};
    const highlighter = struct {
        fn highlight(text: []const u8, col: usize) Style {
            _ = text;
            _ = col;
            return Style{ .bold = true };
        }
    }.highlight;
    const textarea = TextArea.init(&lines).withHighlighter(highlighter);
    try std.testing.expect(textarea.highlighter != null);
}

test "TextArea: highlighter applies styles to matched text" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"const x = 42;"};
    const highlighter = struct {
        fn highlight(text: []const u8, col: usize) Style {
            // Highlight "const" keyword
            if (col < 5 and std.mem.startsWith(u8, text, "const")) {
                return Style{ .bold = true };
            }
            return Style{};
        }
    }.highlight;
    const textarea = TextArea.init(&lines).withHighlighter(highlighter);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // First 5 chars should be bold
    try std.testing.expect(buf.get(0, 0).style.bold);
    try std.testing.expect(buf.get(4, 0).style.bold);
}

test "TextArea: highlighter does not override selection style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"const x"};
    const highlighter = struct {
        fn highlight(_: []const u8, _: usize) Style {
            return Style{ .bold = true };
        }
    }.highlight;
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withHighlighter(highlighter)
        .withSelection(0, 0, 0, 5)
        .withSelectionStyle(sel_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Selection should override highlighter
    try std.testing.expect(buf.get(0, 0).style.reverse);
}

test "TextArea: highlighter does not override cursor style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"const x"};
    const highlighter = struct {
        fn highlight(_: []const u8, _: usize) Style {
            return Style{ .bold = true };
        }
    }.highlight;
    const cursor_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withHighlighter(highlighter)
        .withCursor(0, 2)
        .withCursorStyle(cursor_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Cursor should override highlighter
    try std.testing.expect(buf.get(2, 0).style.reverse);
}

test "TextArea: style precedence is text < highlighter < selection < cursor" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"text"};
    const text_style = Style{ .dim = true };
    const highlighter = struct {
        fn highlight(_: []const u8, _: usize) Style {
            return Style{ .italic = true };
        }
    }.highlight;
    const sel_style = Style{ .reverse = true };
    const cursor_style = Style{ .bold = true };
    const textarea = TextArea.init(&lines)
        .withTextStyle(text_style)
        .withHighlighter(highlighter)
        .withSelection(0, 0, 0, 4)
        .withSelectionStyle(sel_style)
        .withCursor(0, 1)
        .withCursorStyle(cursor_style);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Position 0: selection style (overrides highlighter, text)
    try std.testing.expect(buf.get(0, 0).style.reverse);
    // Position 1 (cursor): cursor style (overrides all)
    try std.testing.expect(buf.get(1, 0).style.bold);
}

test "TextArea: highlighter works with multi-line content" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{ "const x", "var y" };
    const highlighter = struct {
        fn highlight(text: []const u8, col: usize) Style {
            _ = col;
            if (std.mem.startsWith(u8, text, "const") or std.mem.startsWith(u8, text, "var")) {
                return Style{ .bold = true };
            }
            return Style{};
        }
    }.highlight;
    const textarea = TextArea.init(&lines).withHighlighter(highlighter);
    textarea.render(&buf, Rect.init(0, 0, 20, 5));

    // Both lines should have bold applied
    try std.testing.expect(buf.get(0, 0).style.bold); // "const x" line 0
    try std.testing.expect(buf.get(0, 1).style.bold); // "var y" line 1
}

test "TextArea: highlighter scrolls with content" {
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "const x" };
    const highlighter = struct {
        fn highlight(text: []const u8, _: usize) Style {
            if (std.mem.startsWith(u8, text, "const")) {
                return Style{ .bold = true };
            }
            return Style{};
        }
    }.highlight;
    const textarea = TextArea.init(&lines)
        .withHighlighter(highlighter)
        .withOffset(2, 0); // Scroll to show "const x"
    textarea.render(&buf, Rect.init(0, 0, 10, 2));

    // After scrolling, "const x" should be visible and highlighted
    try std.testing.expect(buf.get(0, 0).style.bold); // 'c' of "const"
}
