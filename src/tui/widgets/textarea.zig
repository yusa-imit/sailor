//! Multi-line text area widget with configurable line wrapping.
//!
//! Columns (`cursor_col`, `col_offset`, the selection columns and the highlighter column) are
//! byte offsets into a line. Drawing, wrapping and scrolling work in terminal cells, so
//! multibyte and wide characters are never split.
const std = @import("std");
const assert = std.debug.assert;
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

/// A UTF-8 sequence is at most 4 bytes, so at most 3 continuation bytes precede a boundary.
const utf8_continuation_max: usize = 3;

/// The largest `u64` has 20 decimal digits: the widest line number the gutter can print.
const line_number_digits_max: usize = 20;

/// Line wrapping mode
pub const WrapMode = enum {
    none, // No wrapping, horizontal scroll
    soft, // Wrap at word boundaries (or char if no spaces)
    hard, // Wrap at exact width boundary
};

/// One decoded character: its codepoint and the number of bytes it occupies.
const Char = struct { cp: u21, len: usize };

/// Result of drawing a span of a line: cells used and the byte index where drawing stopped.
const Span = struct { used: u16, next: usize };

/// Per-render geometry. `text_x + text_width` and `x_end`/`y_end` all fit in `u16`.
const Frame = struct {
    buf: *Buffer,
    text_x: u16,
    text_width: u16,
    x_end: u16, // exclusive; clipped to the buffer
    y_end: u16, // exclusive; clipped to the buffer
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
    pub fn withSelection(
        self: TextArea,
        start_row: usize,
        start_col: usize,
        end_row: usize,
        end_col: usize,
    ) TextArea {
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
    pub fn withHighlighter(
        self: TextArea,
        new_highlighter: *const fn ([]const u8, usize) Style,
    ) TextArea {
        var result = self;
        result.highlighter = new_highlighter;
        return result;
    }

    /// Calculate line number gutter width (if enabled)
    fn gutterWidth(self: TextArea) u16 {
        if (!self.show_line_numbers) return 0;

        // Calculate width needed for line numbers
        var width: u16 = 1; // At least 1 digit
        var n = self.lines.len;
        while (n >= 10) : (n = @divTrunc(n, 10)) {
            width += 1;
        }
        assert(width <= line_number_digits_max);
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

    /// Render the textarea widget. The area is clamped so `x + width` and `y + height` fit in
    /// `u16`, and all drawing is clipped to the buffer. In wrap modes `col_offset` is ignored:
    /// wrapped text never scrolls horizontally.
    pub fn render(self: TextArea, buf: *Buffer, area_raw: Rect) void {
        if (area_raw.width == 0 or area_raw.height == 0) return;

        var area = area_raw;
        area.width = @min(area.width, std.math.maxInt(u16) - area.x);
        area.height = @min(area.height, std.math.maxInt(u16) - area.y);
        assert(@as(u32, area.x) + area.width <= std.math.maxInt(u16));
        assert(@as(u32, area.y) + area.height <= std.math.maxInt(u16));

        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;
        if (inner.x >= buf.width or inner.y >= buf.height) return;
        if (self.lines.len == 0) return;

        const gutter_w = self.gutterWidth();
        if (gutter_w >= inner.width) return;

        const frame = Frame{
            .buf = buf,
            .text_x = inner.x + gutter_w,
            .text_width = inner.width - gutter_w,
            .x_end = @intCast(@min(@as(u32, inner.x) + inner.width, buf.width)),
            .y_end = @intCast(@min(@as(u32, inner.y) + inner.height, buf.height)),
        };
        assert(frame.text_x < frame.x_end or frame.text_x >= buf.width);
        self.renderLines(frame, inner, gutter_w);
    }

    /// Draw the visible lines, top to bottom, until the rows run out.
    fn renderLines(self: TextArea, frame: Frame, inner: Rect, gutter_w: u16) void {
        assert(self.lines.len > 0);
        assert(inner.height > 0);

        const row_start = self.rowStart(inner.height);
        const rows = @min(self.lines.len - row_start, inner.height);
        var y = inner.y;
        for (self.lines[row_start..][0..rows], row_start..) |line, line_idx| {
            if (y >= frame.y_end) break;
            if (self.show_line_numbers) {
                self.drawGutter(frame.buf, inner.x, gutter_w, y, line_idx);
            }
            y = switch (self.wrap_mode) {
                .none => self.renderUnwrapped(frame, line, line_idx, y),
                .soft, .hard => self.renderWrapped(frame, line, line_idx, y),
            };
        }
    }

    /// First visible line index: honors `row_offset`, then scrolls to keep the cursor row
    /// (clamped to the last line) inside the window.
    fn rowStart(self: TextArea, height: u16) usize {
        assert(self.lines.len > 0);
        assert(height > 0);

        const visible = @min(self.lines.len, height);
        const cursor = @min(self.cursor_row, self.lines.len - 1);
        var start = @min(self.row_offset, self.lines.len);
        if (cursor >= start + visible) {
            start = cursor - visible + 1;
        } else if (cursor < start) {
            start = cursor;
        }
        assert(start <= cursor);
        return start;
    }

    /// Draw the right-aligned line number and separator of one row.
    fn drawGutter(
        self: TextArea,
        buf: *Buffer,
        inner_x: u16,
        gutter_w: u16,
        y: u16,
        line_idx: usize,
    ) void {
        assert(gutter_w >= 3);
        assert(line_idx < self.lines.len);

        var num_buf: [line_number_digits_max]u8 = undefined;
        // A usize has at most 20 decimal digits, so the 20 byte buffer never fills; if it ever
        // did, skipping the number is the safe fallback.
        const line_num = line_idx + 1;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{line_num}) catch |err| switch (err) {
            error.NoSpaceLeft => return,
        };
        const digits_w: u16 = gutter_w - 2;
        assert(num_str.len <= digits_w); // the gutter is sized for the largest line number

        const num_x = inner_x + digits_w - @as(u16, @intCast(num_str.len));
        buf.setString(num_x, y, num_str, self.line_number_style);
        buf.setString(inner_x + gutter_w - 1, y, " ", self.line_number_style);
    }

    /// Render one unwrapped line with horizontal scrolling; returns the next free row.
    fn renderUnwrapped(
        self: TextArea,
        frame: Frame,
        line: []const u8,
        line_idx: usize,
        y: u16,
    ) u16 {
        assert(y < frame.y_end);
        assert(frame.text_width > 0);

        const start = self.columnStart(line, line_idx, frame.text_width);
        const span = self.drawSpan(frame, line, line_idx, start, line.len, y);
        self.drawEndCursor(frame, line, line_idx, span, y);
        return y + 1;
    }

    /// Render one wrapped line (soft or hard); returns the next free row.
    fn renderWrapped(
        self: TextArea,
        frame: Frame,
        line: []const u8,
        line_idx: usize,
        start_y: u16,
    ) u16 {
        assert(self.wrap_mode != .none);
        assert(start_y < frame.y_end);

        var y = start_y;
        var pos: usize = 0;
        // Bounded by the rows left (`y_end`) and by one row per byte of the line.
        while (y < frame.y_end) {
            const rest = line[pos..];
            const chunk_len = if (rest.len == 0)
                0
            else
                wrapChunkLen(rest, frame.text_width, self.wrap_mode);
            const span = self.drawSpan(frame, line, line_idx, pos, pos + chunk_len, y);
            pos += chunk_len;
            y += 1;
            if (pos >= line.len) {
                self.drawEndCursor(frame, line, line_idx, span, y - 1);
                break;
            }
        }
        assert(y > start_y);
        return y;
    }

    /// First byte shown in an unwrapped line: `col_offset`, moved so the cursor cell stays
    /// inside `text_width` cells when the cursor is on this line.
    fn columnStart(self: TextArea, line: []const u8, line_idx: usize, text_width: u16) usize {
        assert(text_width > 0);
        var start = snapBoundary(line, @min(self.col_offset, line.len));
        if (line_idx != self.cursor_row) return start;

        const cursor = snapBoundary(line, @min(self.cursor_col, line.len));
        if (cursor < start) return cursor;

        const cursor_w: usize = if (cursor < line.len)
            @max(1, UnicodeWidth.charWidth(decodeAt(line, cursor).cp))
        else
            1;
        var shown_w = UnicodeWidth.stringWidth(line[start..cursor]);
        // Each step drops one character from the left; at most one step per byte.
        while (start < cursor and shown_w + cursor_w > text_width) {
            const ch = decodeAt(line, start);
            shown_w -= UnicodeWidth.charWidth(ch.cp);
            start += ch.len;
        }
        assert(start <= cursor);
        return start;
    }

    /// Draw `line[start..end]` from the left of the text area on row `y`, one character per
    /// call of `cellStyle`. Stops at the first character that does not fit `text_width`.
    fn drawSpan(
        self: TextArea,
        frame: Frame,
        line: []const u8,
        line_idx: usize,
        start: usize,
        end: usize,
        y: u16,
    ) Span {
        assert(start <= end);
        assert(end <= line.len);

        var i = start;
        var used: u16 = 0;
        while (i < end) {
            const ch = decodeAt(line, i);
            const w = UnicodeWidth.charWidth(ch.cp);
            if (w == 0) { // zero-width characters take no cell, as in Buffer.setString
                i += ch.len;
                continue;
            }
            if (@as(u32, used) + w > frame.text_width) break;

            const x = frame.text_x + used; // used + w <= text_width, so this fits u16
            if (x < frame.x_end) {
                const cell_style = self.cellStyle(line, line_idx, i, ch.len);
                frame.buf.set(x, y, .{ .char = ch.cp, .style = cell_style });
            }
            used += w;
            i += ch.len;
        }
        assert(used <= frame.text_width);
        return .{ .used = used, .next = i };
    }

    /// Style for the character at byte `byte_idx`:
    /// text_style < highlighter < selection_style < cursor_style.
    fn cellStyle(
        self: TextArea,
        line: []const u8,
        line_idx: usize,
        byte_idx: usize,
        char_len: usize,
    ) Style {
        assert(byte_idx < line.len);
        assert(char_len >= 1);

        var cell_style = self.text_style;
        if (self.highlighter) |h| cell_style = h(line, byte_idx);
        if (self.isInSelection(line_idx, byte_idx)) cell_style = self.selection_style;

        const on_cursor = self.show_cursor and line_idx == self.cursor_row and
            self.cursor_col >= byte_idx and self.cursor_col < byte_idx + char_len;
        if (on_cursor) cell_style = self.cursor_style;
        return cell_style;
    }

    /// Draw the cursor as a blank cell after the last character when it sits at (or past)
    /// the end of its line and a cell is free there.
    fn drawEndCursor(
        self: TextArea,
        frame: Frame,
        line: []const u8,
        line_idx: usize,
        span: Span,
        y: u16,
    ) void {
        assert(span.next <= line.len);
        assert(span.used <= frame.text_width);
        if (!self.show_cursor or line_idx != self.cursor_row) return;
        if (self.cursor_col < line.len or span.next != line.len) return;
        if (span.used >= frame.text_width) return;

        const x = frame.text_x + span.used; // used < text_width, so this fits u16
        if (x < frame.x_end) {
            frame.buf.set(x, y, .{ .char = ' ', .style = self.cursor_style });
        }
    }
};

/// Decode the character starting at byte `i`. Invalid or truncated sequences decode as one
/// byte, matching `Buffer.setString`.
fn decodeAt(text: []const u8, i: usize) Char {
    assert(i < text.len);
    const byte = text[i];
    const seq_len: usize = std.unicode.utf8ByteSequenceLength(byte) catch
        return .{ .cp = byte, .len = 1 };
    if (i + seq_len > text.len) return .{ .cp = byte, .len = 1 };
    const cp = std.unicode.utf8Decode(text[i .. i + seq_len]) catch
        return .{ .cp = byte, .len = 1 };
    assert(seq_len >= 1);
    return .{ .cp = cp, .len = seq_len };
}

/// Move `index` back to the start of the UTF-8 sequence containing it.
fn snapBoundary(text: []const u8, index: usize) usize {
    assert(index <= text.len);
    var i = index;
    var steps: usize = 0;
    while (steps < utf8_continuation_max and i > 0 and i < text.len and
        (text[i] & 0xC0) == 0x80) : (steps += 1)
    {
        i -= 1;
    }
    assert(i <= index);
    return i;
}

/// Byte length of the next wrapped row of `rest`. Always at least one character, so the
/// caller makes progress even when a character is wider than `text_width`. Soft wrap breaks
/// after the last space that keeps the row within `text_width` (a space just past the row
/// counts), never after a leading space alone, and falls back to a hard break.
fn wrapChunkLen(rest: []const u8, text_width: u16, mode: WrapMode) usize {
    assert(rest.len > 0);
    assert(text_width > 0);
    assert(mode != .none);

    const fit = UnicodeWidth.truncate(rest, text_width);
    if (fit == rest.len) return fit;

    var chunk = if (fit == 0) decodeAt(rest, 0).len else fit;
    if (mode == .soft) {
        // Scan back from the byte just past the row to byte 1; bounded by `fit`.
        var i = fit;
        while (i >= 1) : (i -= 1) {
            if (rest[i] == ' ') {
                chunk = i + 1;
                break;
            }
        }
    }
    assert(chunk >= 1);
    assert(chunk <= rest.len);
    return chunk;
}

// Tests

fn rect(x: u16, y: u16, width: u16, height: u16) Rect {
    return .{ .x = x, .y = y, .width = width, .height = height };
}

/// Cell at (x, y); the test fails loudly when the position is outside the buffer.
fn cellAt(buf: *const Buffer, x: u16, y: u16) buffer_mod.Cell {
    return buf.getConst(x, y).?;
}

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
    textarea.render(&buf, rect(0, 0, 10, 5));

    // Nothing to draw: not even a cursor cell appears.
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 0).char);
    try std.testing.expect(!cellAt(&buf, 0, 0).style.reverse);
}

test "TextArea: render single line" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Check first line
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), cellAt(&buf, 1, 0).char);
}

test "TextArea: render multiple lines" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const lines = [_][]const u8{ "Line 1", "Line 2", "Line 3" };
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, rect(0, 0, 20, 10));

    try std.testing.expectEqual(@as(u21, 'L'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'L'), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, 'L'), cellAt(&buf, 0, 2).char);
}

test "TextArea: render with cursor" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withCursor(0, 2)
        .withCursorStyle(Style{ .reverse = true });

    textarea.render(&buf, rect(0, 0, 20, 5));

    // Cursor should be at position 2
    try std.testing.expect(cellAt(&buf, 2, 0).style.reverse);
}

test "TextArea: render with cursor at end of line" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hi"};
    const textarea = TextArea.init(&lines)
        .withCursor(0, 2) // After last char
        .withCursorStyle(Style{ .reverse = true });

    textarea.render(&buf, rect(0, 0, 20, 5));

    // Cursor should be at position 2 (space)
    try std.testing.expect(cellAt(&buf, 2, 0).style.reverse);
}

test "TextArea: render without cursor" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withCursor(0, 2)
        .withShowCursor(false);

    textarea.render(&buf, rect(0, 0, 20, 5));

    // No cell should have reverse style
    try std.testing.expect(!cellAt(&buf, 2, 0).style.reverse);
}

test "TextArea: render with line numbers" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{ "Line 1", "Line 2" };
    const textarea = TextArea.init(&lines).withShowLineNumbers(true);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Line numbers should be rendered (1 and 2)
    try std.testing.expectEqual(@as(u21, '1'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, '2'), cellAt(&buf, 0, 1).char);
}

test "TextArea: render with row offset" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4" };
    const textarea = TextArea.init(&lines).withOffset(2, 0).withCursor(2, 0);
    textarea.render(&buf, rect(0, 0, 20, 3));

    // Should show L3, L4 (skipping L1, L2)
    try std.testing.expectEqual(@as(u21, 'L'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, '3'), cellAt(&buf, 1, 0).char);
}

test "TextArea: render with col offset" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines).withOffset(0, 6).withCursor(0, 8);
    textarea.render(&buf, rect(0, 0, 10, 3));

    // Should show "World" (skipping "Hello ")
    try std.testing.expectEqual(@as(u21, 'W'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'd'), cellAt(&buf, 4, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 5, 0).char);
}

test "TextArea: render with block" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Text"};
    const blk = (Block{});
    const textarea = TextArea.init(&lines).withBlock(blk);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Border on the edge, content inside it.
    try std.testing.expectEqual(@as(u21, 0x250C), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'T'), cellAt(&buf, 1, 1).char);
    try std.testing.expectEqual(@as(u21, 'e'), cellAt(&buf, 2, 1).char);
}

test "TextArea: render zero size area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Text"};
    const textarea = TextArea.init(&lines);

    // Should not crash
    textarea.render(&buf, rect(0, 0, 0, 5));
    textarea.render(&buf, rect(0, 0, 10, 0));
}

test "TextArea: auto-scroll vertical" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4", "L5" };
    // Cursor on line 4, should auto-scroll
    const textarea = TextArea.init(&lines).withCursor(4, 0);
    textarea.render(&buf, rect(0, 0, 20, 3));

    // Should show L3, L4, L5 to keep cursor visible
    try std.testing.expectEqual(@as(u21, '3'), cellAt(&buf, 1, 0).char);
    try std.testing.expectEqual(@as(u21, '5'), cellAt(&buf, 1, 2).char);
    try std.testing.expect(cellAt(&buf, 0, 2).style.reverse);
}

test "TextArea: auto-scroll horizontal" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"This is a very long line"};
    // Cursor at column 20, should auto-scroll
    const textarea = TextArea.init(&lines).withCursor(0, 20);
    textarea.render(&buf, rect(0, 0, 10, 3));

    // Cursor column 20 lands on the last of 10 cells, so columns 11..20 ("ery long l") show.
    try std.testing.expectEqual(@as(u21, 'e'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), cellAt(&buf, 9, 0).char);
    try std.testing.expect(cellAt(&buf, 9, 0).style.reverse);
    try std.testing.expect(!cellAt(&buf, 8, 0).style.reverse);
}

test "TextArea: long lines truncate" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, rect(0, 0, 5, 3));

    // Should only show "Hello"
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), cellAt(&buf, 1, 0).char);
}

test "TextArea: many lines overflow" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4" };
    const textarea = TextArea.init(&lines);
    textarea.render(&buf, rect(0, 0, 20, 2));

    // Should only show first 2 lines
    try std.testing.expectEqual(@as(u21, 'L'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), cellAt(&buf, 1, 0).char);
    try std.testing.expectEqual(@as(u21, 'L'), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, '2'), cellAt(&buf, 1, 1).char);
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
    textarea.render(&buf, rect(0, 0, 10, 5));

    // "Hello World" is 11 cells, so the row breaks after "Hello ".
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 5, 0).char);
    try std.testing.expectEqual(@as(u21, 'W'), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, 'T'), cellAt(&buf, 6, 1).char);
}

test "TextArea: soft wrap respects char boundaries when no spaces" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"HelloWorld"};
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, rect(0, 0, 5, 5));

    // Should wrap at char 5: "Hello" then "World"
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'W'), cellAt(&buf, 0, 1).char);
}

test "TextArea: hard wrap inserts line breaks at width boundary" {
    var buf = try Buffer.init(std.testing.allocator, 8, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines).withWrapMode(.hard);
    textarea.render(&buf, rect(0, 0, 8, 5));

    // Hard wrap should split at width 8: "Hello Wo" then "rld"
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), cellAt(&buf, 4, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 5, 0).char);
    try std.testing.expectEqual(@as(u21, 'W'), cellAt(&buf, 6, 0).char);
    try std.testing.expectEqual(@as(u21, 'r'), cellAt(&buf, 0, 1).char);
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

    const lines = [_][]const u8{ "Short", "Very long line that wraps" };
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, rect(0, 0, 5, 2));

    // Should render "Short" on line 0
    try std.testing.expectEqual(@as(u21, 'S'), cellAt(&buf, 0, 0).char);
}

test "TextArea: wrap mode none disables wrapping" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines).withWrapMode(.none);
    textarea.render(&buf, rect(0, 0, 5, 5));

    // Should truncate at width 5, no wrapping
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), cellAt(&buf, 4, 0).char); // Last visible char
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 1).char); // nothing wrapped
}

test "TextArea: wrap handles empty lines correctly" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const lines = [_][]const u8{ "Hello", "", "World" };
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, rect(0, 0, 10, 5));

    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 1).char); // Empty line
    try std.testing.expectEqual(@as(u21, 'W'), cellAt(&buf, 0, 2).char);
}

test "TextArea: wrap handles trailing spaces" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hi   "};
    const textarea = TextArea.init(&lines).withWrapMode(.soft);
    textarea.render(&buf, rect(0, 0, 5, 5));

    // "Hi   " fits in width 5, no wrap needed
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), cellAt(&buf, 1, 0).char);
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
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Chars 1-3 should have selection style
    try std.testing.expect(cellAt(&buf, 1, 0).style.reverse);
    try std.testing.expect(cellAt(&buf, 2, 0).style.reverse);
    try std.testing.expect(cellAt(&buf, 3, 0).style.reverse);
}

test "TextArea: backward selection renders correctly" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 4, 0, 1) // Backward selection
        .withSelectionStyle(sel_style);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Should normalize to forward selection (1-3)
    try std.testing.expect(cellAt(&buf, 1, 0).style.reverse);
}

test "TextArea: empty selection does not render" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 2, 0, 2) // Empty selection
        .withSelectionStyle(sel_style);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // No cell should have reverse style
    try std.testing.expect(!cellAt(&buf, 2, 0).style.reverse);
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
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Cursor at position 2 should have cursor_style (bold + reverse)
    try std.testing.expect(cellAt(&buf, 2, 0).style.bold);
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
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Selection region should have reverse, not italic
    try std.testing.expect(cellAt(&buf, 1, 0).style.reverse);
    try std.testing.expect(!cellAt(&buf, 1, 0).style.italic);
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
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Position 0: selection style
    try std.testing.expect(cellAt(&buf, 0, 0).style.reverse);
    // Position 2 (cursor): cursor style
    try std.testing.expect(cellAt(&buf, 2, 0).style.bold);
}

test "TextArea: selection scrolls horizontally when needed" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World Test"};
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 6, 0, 11) // Select "World"
        .withSelectionStyle(sel_style)
        .withShowCursor(false)
        .withCursor(0, 8) // The (hidden) cursor still drives scrolling; keep it in view
        .withOffset(0, 6); // Scroll to show selection
    textarea.render(&buf, rect(0, 0, 5, 3));

    // At offset 6, we see "World", chars 0-4 should have selection style
    try std.testing.expectEqual(@as(u21, 'W'), cellAt(&buf, 0, 0).char);
    try std.testing.expect(cellAt(&buf, 0, 0).style.reverse); // 'W'
    try std.testing.expect(cellAt(&buf, 4, 0).style.reverse); // 'd'
}

test "TextArea: selection scrolls vertically when needed" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2", "L3", "L4" };
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(2, 0, 3, 2) // Select L3 and L4
        .withSelectionStyle(sel_style)
        .withShowCursor(false)
        .withCursor(2, 0)
        .withOffset(2, 0); // Scroll to show selection
    textarea.render(&buf, rect(0, 0, 20, 2));

    // Should show L3 and L4 (rows 2-3), both with selection
    try std.testing.expectEqual(@as(u21, '3'), cellAt(&buf, 1, 0).char);
    try std.testing.expect(cellAt(&buf, 0, 0).style.reverse); // L3
    try std.testing.expect(cellAt(&buf, 1, 1).style.reverse); // L4, before the end column
    try std.testing.expect(!cellAt(&buf, 2, 1).style.reverse); // end column is exclusive
}

test "TextArea: selection handles boundary clamping at line start" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withShowCursor(false)
        .withSelection(0, 0, 0, 0); // At line start (empty selection)
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Empty selection should not render any selection style
    try std.testing.expect(!cellAt(&buf, 0, 0).style.reverse);
}

test "TextArea: selection handles boundary clamping at line end" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello"};
    const textarea = TextArea.init(&lines)
        .withSelection(0, 5, 0, 5); // At line end (empty selection)
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Empty selection should not render
    try std.testing.expect(!cellAt(&buf, 4, 0).style.reverse);
}

test "TextArea: selection clamps to valid line indices" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2" };
    const sel_style = Style{ .reverse = true };
    const textarea = TextArea.init(&lines)
        .withSelection(0, 0, 10, 0) // Row 10 doesn't exist
        .withSelectionStyle(sel_style)
        .withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Should select from row 0 to row 1 (clamped)
    try std.testing.expect(cellAt(&buf, 0, 0).style.reverse);
    try std.testing.expect(cellAt(&buf, 1, 1).style.reverse);
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
    const textarea = TextArea.init(&lines).withHighlighter(highlighter).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // First 5 chars should be bold
    try std.testing.expect(cellAt(&buf, 0, 0).style.bold);
    try std.testing.expect(cellAt(&buf, 4, 0).style.bold);
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
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Selection should override highlighter
    try std.testing.expect(cellAt(&buf, 0, 0).style.reverse);
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
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Cursor should override highlighter
    try std.testing.expect(cellAt(&buf, 2, 0).style.reverse);
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
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Position 0: selection style (overrides highlighter, text)
    try std.testing.expect(cellAt(&buf, 0, 0).style.reverse);
    // Position 1 (cursor): cursor style (overrides all)
    try std.testing.expect(cellAt(&buf, 1, 0).style.bold);
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
    const textarea = TextArea.init(&lines).withHighlighter(highlighter).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 20, 5));

    // Both lines should have bold applied
    try std.testing.expect(cellAt(&buf, 0, 0).style.bold); // "const x" line 0
    try std.testing.expect(cellAt(&buf, 0, 1).style.bold); // "var y" line 1
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
        .withShowCursor(false)
        .withCursor(2, 0)
        .withOffset(2, 0); // Scroll to show "const x"
    textarea.render(&buf, rect(0, 0, 10, 2));

    // After scrolling, "const x" should be visible and highlighted
    try std.testing.expect(cellAt(&buf, 0, 0).style.bold); // 'c' of "const"
}

// ====================================
// Regression tests (#75 batch 7)
// ====================================

test "TextArea: multibyte characters are drawn whole" {
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();

    const lines = [_][]const u8{"a\u{e9}b"}; // 'e' acute is two bytes
    const textarea = TextArea.init(&lines).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 10, 2));

    try std.testing.expectEqual(@as(u21, 'a'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 0xE9), cellAt(&buf, 1, 0).char);
    try std.testing.expectEqual(@as(u21, 'b'), cellAt(&buf, 2, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 3, 0).char);
}

test "TextArea: cursor inside a multibyte character marks the whole character" {
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();

    const lines = [_][]const u8{"a\u{e9}b"};
    const at_start = TextArea.init(&lines).withCursor(0, 1);
    at_start.render(&buf, rect(0, 0, 10, 2));
    try std.testing.expect(cellAt(&buf, 1, 0).style.reverse);
    try std.testing.expect(!cellAt(&buf, 2, 0).style.reverse);

    var buf2 = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf2.deinit();
    const mid = TextArea.init(&lines).withCursor(0, 2); // second byte of the character
    mid.render(&buf2, rect(0, 0, 10, 2));
    try std.testing.expect(cellAt(&buf2, 1, 0).style.reverse);
    try std.testing.expect(!cellAt(&buf2, 2, 0).style.reverse);
}

test "TextArea: wide characters take two cells" {
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();

    const lines = [_][]const u8{"a\u{597d}b"}; // CJK ideograph, width 2
    const textarea = TextArea.init(&lines).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 10, 2));

    try std.testing.expectEqual(@as(u21, 0x597D), cellAt(&buf, 1, 0).char);
    try std.testing.expectEqual(@as(u21, 'b'), cellAt(&buf, 3, 0).char);
}

test "TextArea: horizontal scroll counts cells for wide characters" {
    var buf = try Buffer.init(std.testing.allocator, 6, 2);
    defer buf.deinit();

    // Five ideographs are 10 cells; the cursor sits after the last one (byte 15).
    const lines = [_][]const u8{"\u{597d}\u{597d}\u{597d}\u{597d}\u{597d}"};
    const textarea = TextArea.init(&lines).withCursor(0, 15);
    textarea.render(&buf, rect(0, 0, 6, 2));

    // Two ideographs (4 cells) plus the cursor cell fit in 6 cells.
    try std.testing.expectEqual(@as(u21, 0x597D), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 0x597D), cellAt(&buf, 2, 0).char);
    try std.testing.expect(cellAt(&buf, 4, 0).style.reverse);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 4, 0).char);
}

test "TextArea: far or oversized areas do not overflow" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const lines = [_][]const u8{ "alpha", "beta" };
    const textarea = TextArea.init(&lines).withShowLineNumbers(true);
    textarea.render(&buf, rect(65530, 0, 100, 3));
    textarea.render(&buf, rect(65535, 65535, 5, 5));
    textarea.render(&buf, rect(0, 65534, 10, 100));
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 4, 1).char);

    // A huge area from the origin still draws, clipped to the buffer.
    textarea.render(&buf, rect(0, 0, 65535, 65535));
    try std.testing.expectEqual(@as(u21, '1'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'a'), cellAt(&buf, 3, 0).char);
    try std.testing.expectEqual(@as(u21, 'b'), cellAt(&buf, 3, 1).char);
}

test "TextArea: line numbers are right-aligned in the gutter" {
    var buf = try Buffer.init(std.testing.allocator, 12, 10);
    defer buf.deinit();

    const lines = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" };
    const textarea = TextArea.init(&lines).withShowLineNumbers(true).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 12, 10));

    // Ten lines: two digits, a space, a separator, then the text at column 4.
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), cellAt(&buf, 1, 0).char);
    try std.testing.expectEqual(@as(u21, '1'), cellAt(&buf, 0, 9).char);
    try std.testing.expectEqual(@as(u21, '0'), cellAt(&buf, 1, 9).char);
    try std.testing.expectEqual(@as(u21, 'a'), cellAt(&buf, 4, 0).char);
    try std.testing.expectEqual(@as(u21, 'j'), cellAt(&buf, 4, 9).char);
}

test "TextArea: soft wrap breaks a word that ends exactly at the width" {
    var buf = try Buffer.init(std.testing.allocator, 5, 4);
    defer buf.deinit();

    const lines = [_][]const u8{"Hello World"};
    const textarea = TextArea.init(&lines).withWrapMode(.soft).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 5, 4));

    // No blank row between the two words.
    try std.testing.expectEqual(@as(u21, 'o'), cellAt(&buf, 4, 0).char);
    try std.testing.expectEqual(@as(u21, 'W'), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, 'd'), cellAt(&buf, 4, 1).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 2).char);
}

test "TextArea: soft wrap does not strand a leading space on its own row" {
    var buf = try Buffer.init(std.testing.allocator, 5, 4);
    defer buf.deinit();

    const lines = [_][]const u8{" abcdefgh"};
    const textarea = TextArea.init(&lines).withWrapMode(.soft).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 5, 4));

    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'd'), cellAt(&buf, 4, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, 'h'), cellAt(&buf, 3, 1).char);
}

test "TextArea: wrapping terminates when a character is wider than the area" {
    var buf = try Buffer.init(std.testing.allocator, 3, 4);
    defer buf.deinit();

    const lines = [_][]const u8{"\u{597d}\u{597d}"};
    const hard = TextArea.init(&lines).withWrapMode(.hard).withShowLineNumbers(true);
    hard.render(&buf, rect(0, 0, 4, 4)); // gutter 3, one text cell

    // Neither ideograph fits one cell; both rows stay blank and rendering ends.
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, '1'), cellAt(&buf, 0, 0).char);
}

test "TextArea: hard wrap breaks multibyte text by cells" {
    var buf = try Buffer.init(std.testing.allocator, 4, 4);
    defer buf.deinit();

    const lines = [_][]const u8{"ab\u{597d}\u{597d}c"};
    const textarea = TextArea.init(&lines).withWrapMode(.hard).withShowCursor(false);
    textarea.render(&buf, rect(0, 0, 4, 4));

    try std.testing.expectEqual(@as(u21, 0x597D), cellAt(&buf, 2, 0).char);
    try std.testing.expectEqual(@as(u21, 0x597D), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, 'c'), cellAt(&buf, 2, 1).char);
}

test "TextArea: wrap modes ignore col_offset" {
    var buf = try Buffer.init(std.testing.allocator, 5, 4);
    defer buf.deinit();

    const lines = [_][]const u8{ "Hello", "abcdefghij" };
    const textarea = TextArea.init(&lines)
        .withWrapMode(.hard)
        .withShowCursor(false)
        .withOffset(0, 3);
    textarea.render(&buf, rect(0, 0, 5, 4));

    // The short line fits and the long one wraps; neither is scrolled sideways.
    try std.testing.expectEqual(@as(u21, 'H'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, 'a'), cellAt(&buf, 0, 1).char);
    try std.testing.expectEqual(@as(u21, 'f'), cellAt(&buf, 0, 2).char);
}

test "TextArea: cursor at end of a wrapped line is drawn after the last character" {
    var buf = try Buffer.init(std.testing.allocator, 5, 4);
    defer buf.deinit();

    const lines = [_][]const u8{"abcdefg"};
    const textarea = TextArea.init(&lines).withWrapMode(.hard).withCursor(0, 7);
    textarea.render(&buf, rect(0, 0, 5, 4));

    try std.testing.expectEqual(@as(u21, 'g'), cellAt(&buf, 1, 1).char);
    try std.testing.expect(cellAt(&buf, 2, 1).style.reverse);
    try std.testing.expect(!cellAt(&buf, 1, 1).style.reverse);
}

test "TextArea: cursor row past the last line scrolls to the last line" {
    var buf = try Buffer.init(std.testing.allocator, 6, 1);
    defer buf.deinit();

    const lines = [_][]const u8{ "L1", "L2" };
    const textarea = TextArea.init(&lines).withCursor(5, 0);
    textarea.render(&buf, rect(0, 0, 6, 1));

    try std.testing.expectEqual(@as(u21, 'L'), cellAt(&buf, 0, 0).char);
    try std.testing.expectEqual(@as(u21, '2'), cellAt(&buf, 1, 0).char);
}

test "TextArea: cursor column past the line end sits after the last character" {
    var buf = try Buffer.init(std.testing.allocator, 8, 1);
    defer buf.deinit();

    const lines = [_][]const u8{"abc"};
    const textarea = TextArea.init(&lines).withCursor(0, 100);
    textarea.render(&buf, rect(0, 0, 8, 1));

    try std.testing.expectEqual(@as(u21, 'a'), cellAt(&buf, 0, 0).char);
    try std.testing.expect(cellAt(&buf, 3, 0).style.reverse);
    try std.testing.expect(!cellAt(&buf, 2, 0).style.reverse);
}

test "TextArea: render clips to the buffer" {
    var buf = try Buffer.init(std.testing.allocator, 4, 2);
    defer buf.deinit();

    const lines = [_][]const u8{ "abcdefgh", "ijklmnop", "qrstuvwx" };
    const textarea = TextArea.init(&lines).withShowCursor(false).withWrapMode(.soft);
    textarea.render(&buf, rect(2, 1, 20, 20));

    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 1, 1).char);
    try std.testing.expectEqual(@as(u21, 'a'), cellAt(&buf, 2, 1).char);
    try std.testing.expectEqual(@as(u21, 'b'), cellAt(&buf, 3, 1).char);
    try std.testing.expectEqual(@as(u21, ' '), cellAt(&buf, 0, 0).char);
}
