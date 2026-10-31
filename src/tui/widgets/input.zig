//! Input widget — single-line text input with cursor and placeholder.
//!
//! Input provides a basic text entry field with cursor rendering, placeholder
//! text, and horizontal scrolling for long text. It's the foundation for forms,
//! search boxes, and command input.
//!
//! ## Features
//! - Cursor positioning and rendering
//! - Placeholder text when empty
//! - Horizontal scrolling for text exceeding width
//! - Optional Block wrapper for borders and title
//! - Password mode (planned)
//! - Input validation hooks (via parent form)
//!
//! ## Usage
//! ```zig
//! var input = Input{
//!     .value = "Initial text",
//!     .cursor = 12, // Cursor at end
//!     .placeholder = "Enter something...",
//!     .style = .{ .fg = .{ .basic = .white } },
//! };
//! input.render(buf, area);
//! ```

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
    cursor_style: Style = .{ .reverse = true },

    /// Placeholder style
    placeholder_style: Style = .{ .fg = .bright_black },

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

    // ========================================================================
    // State Persistence
    // ========================================================================

    /// Input state for persistence (includes undo/redo history)
    pub const State = struct {
        value: []const u8,
        cursor: usize,
        placeholder: ?[]const u8,
        history: []const HistoryEntry = &[_]HistoryEntry{},
        history_index: usize = 0,
    };

    /// History entry for undo/redo
    pub const HistoryEntry = struct {
        value: []const u8,
        cursor: usize,
    };

    /// Save current input state (does not allocate - returns slice references)
    pub fn saveState(self: Input) State {
        return State{
            .value = self.value,
            .cursor = self.cursor,
            .placeholder = self.placeholder,
            .history = &[_]HistoryEntry{},
            .history_index = 0,
        };
    }

    /// Restore input state from saved state
    pub fn restoreState(self: Input, state: State) Input {
        var result = self;
        result.value = state.value;
        result.cursor = state.cursor;
        result.placeholder = state.placeholder;
        return result;
    }

    /// Render the input widget on the first line of its (block-inner) area.
    ///
    /// A cursor past the end of `value` is clamped to the end. Invalid or truncated UTF-8 in
    /// `value` never panics: a truncated trailing sequence is drawn as one blank cell.
    pub fn render(self: Input, buf: *Buffer, area: Rect) void {
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }
        if (inner_area.width == 0 or inner_area.height == 0) return;

        const y = inner_area.y;
        const x_end = inner_area.x +| inner_area.width;

        const display_text = if (self.value.len > 0) self.value else (self.placeholder orelse "");
        const display_style = if (self.value.len > 0) self.style else self.placeholder_style;

        // The cursor never leaves the value; scroll so that it stays inside the window.
        const cursor = @min(self.cursor, countChars(self.value));
        const scroll_offset: usize = if (cursor >= inner_area.width)
            cursor - inner_area.width + 1
        else
            0;

        var byte_idx = skipChars(display_text, scroll_offset);
        var char_idx = scroll_offset;
        var x = inner_area.x;
        while (x < x_end and byte_idx < display_text.len) {
            const char_len = charLen(display_text, byte_idx);
            const bytes = display_text[byte_idx..][0..char_len];
            // A lone byte >= 0x80 is invalid UTF-8 (utf8Decode would echo it as Latin-1).
            const invalid = char_len == 1 and bytes[0] >= 0x80;
            const codepoint = if (invalid) ' ' else std.unicode.utf8Decode(bytes) catch ' ';
            const char_style = if (char_idx == cursor and self.value.len > 0)
                self.cursor_style
            else
                display_style;
            buf.set(x, y, .{ .char = codepoint, .style = char_style });
            x += 1;
            byte_idx += char_len;
            char_idx += 1;
        }

        // Cursor after the last character of an empty or fully shown value.
        if (cursor == char_idx and x < x_end) {
            buf.set(x, y, .{ .char = ' ', .style = self.cursor_style });
            x += 1;
        }

        while (x < x_end) : (x += 1) {
            buf.set(x, y, .{ .char = ' ', .style = self.style });
        }
    }

    /// Byte length of the UTF-8 sequence starting at `idx`, clamped to the text end so a
    /// truncated trailing sequence cannot index out of bounds. Invalid lead bytes count as 1.
    fn charLen(text: []const u8, idx: usize) usize {
        std.debug.assert(idx < text.len);
        const len = std.unicode.utf8ByteSequenceLength(text[idx]) catch 1;
        const clamped = @min(len, text.len - idx);
        std.debug.assert(clamped >= 1);
        return clamped;
    }

    /// Number of characters (as the renderer counts them) in `text`.
    fn countChars(text: []const u8) usize {
        var count: usize = 0;
        var idx: usize = 0;
        while (idx < text.len) : (count += 1) idx += charLen(text, idx);
        return count;
    }

    /// Byte offset after skipping up to `n` characters (stops at the text end).
    fn skipChars(text: []const u8, n: usize) usize {
        var idx: usize = 0;
        var skipped: usize = 0;
        while (idx < text.len and skipped < n) : (skipped += 1) idx += charLen(text, idx);
        return idx;
    }
};

// Tests
const testing = std.testing;

fn expectRow(buf: Buffer, y: u16, x0: u16, expected: []const u21) !void {
    for (expected, 0..) |ch, i| {
        const cell = buf.getConst(x0 + @as(u16, @intCast(i)), y).?;
        try testing.expectEqual(ch, cell.char);
    }
}

fn expectCursorAt(buf: Buffer, y: u16, width: u16, cx: u16) !void {
    var x: u16 = 0;
    while (x < width) : (x += 1) {
        const cell = buf.getConst(x, y).?;
        try testing.expectEqual(x == cx, cell.style.reverse);
    }
}

fn renderInput(input: Input, width: u16, height: u16) !Buffer {
    var buf = try Buffer.init(testing.allocator, width, height);
    errdefer buf.deinit();
    input.render(&buf, .{ .x = 0, .y = 0, .width = width, .height = height });
    buf.check_invariants();
    return buf;
}

test "input: init stores value with documented defaults" {
    const input = Input.init("hello");

    try testing.expectEqualStrings("hello", input.value);
    try testing.expectEqual(@as(usize, 0), input.cursor);
    try testing.expect(input.placeholder == null);
    try testing.expect(input.block == null);
    try testing.expectEqual(Style{ .reverse = true }, input.cursor_style);
    try testing.expectEqual(Style{ .fg = .bright_black }, input.placeholder_style);
    try testing.expectEqual(Style{}, input.style);
}

test "input: with-builders replace only their own field" {
    const base = Input.init("hello");
    const sty = Style{ .fg = .cyan };
    const csty = Style{ .bold = true };
    const psty = Style{ .fg = .gray };
    const input = base.withCursor(3).withPlaceholder("ph").withStyle(sty)
        .withCursorStyle(csty).withPlaceholderStyle(psty).withBlock(Block{});

    try testing.expectEqual(@as(usize, 3), input.cursor);
    try testing.expectEqualStrings("ph", input.placeholder.?);
    try testing.expectEqual(sty, input.style);
    try testing.expectEqual(csty, input.cursor_style);
    try testing.expectEqual(psty, input.placeholder_style);
    try testing.expect(input.block != null);
    try testing.expectEqualStrings("hello", input.value);
    try testing.expectEqual(@as(usize, 0), base.cursor);
}

test "input: empty value shows placeholder text in placeholder style" {
    const input = Input.init("").withPlaceholder("Type");
    var buf = try renderInput(input, 8, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'T', 'y', 'p', 'e', ' ', ' ', ' ', ' ' });
    try testing.expectEqual(input.placeholder_style, buf.getConst(0, 0).?.style);
    try testing.expectEqual(input.placeholder_style, buf.getConst(3, 0).?.style);
    try testing.expectEqual(input.style, buf.getConst(4, 0).?.style);
}

test "input: non-empty value hides the placeholder" {
    const input = Input.init("ab").withPlaceholder("Type").withCursor(2);
    var buf = try renderInput(input, 6, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'a', 'b', ' ', ' ', ' ', ' ' });
    try testing.expectEqual(input.style, buf.getConst(0, 0).?.style);
}

test "input: placeholder longer than the area is clipped to the area width" {
    const input = Input.init("").withPlaceholder("abcdefgh");
    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();
    input.render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 1 });

    try expectRow(buf, 0, 0, &.{ 'a', 'b', 'c', 'd', ' ' });
}

test "input: text renders with the input style and fills the rest with blanks" {
    const sty = Style{ .fg = .green };
    const input = Input.init("hello").withStyle(sty).withCursor(99);
    var buf = try renderInput(input, 8, 1);
    defer buf.deinit();

    // Cursor 99 is clamped to the end (index 5), so the blank cursor cell is at x = 5.
    try expectRow(buf, 0, 0, &.{ 'h', 'e', 'l', 'l', 'o', ' ', ' ', ' ' });
    try testing.expectEqual(sty, buf.getConst(1, 0).?.style);
    try testing.expectEqual(sty, buf.getConst(7, 0).?.style);
}

test "input: cursor at start highlights the first character only" {
    var buf = try renderInput(Input.init("hello").withCursor(0), 20, 1);
    defer buf.deinit();

    try expectCursorAt(buf, 0, 20, 0);
    try testing.expectEqual(@as(u21, 'h'), buf.getConst(0, 0).?.char);
}

test "input: cursor in the middle highlights exactly that character" {
    var buf = try renderInput(Input.init("hello").withCursor(2), 20, 1);
    defer buf.deinit();

    try expectCursorAt(buf, 0, 20, 2);
    try testing.expectEqual(@as(u21, 'l'), buf.getConst(2, 0).?.char);
}

test "input: cursor at end draws a blank cursor cell after the text" {
    var buf = try renderInput(Input.init("hello").withCursor(5), 20, 1);
    defer buf.deinit();

    try expectCursorAt(buf, 0, 20, 5);
    try testing.expectEqual(@as(u21, ' '), buf.getConst(5, 0).?.char);
}

test "input: cursor past the end is clamped to the end" {
    var buf = try renderInput(Input.init("hello").withCursor(500), 20, 1);
    defer buf.deinit();

    try expectCursorAt(buf, 0, 20, 5);
    try expectRow(buf, 0, 0, &.{ 'h', 'e', 'l', 'l', 'o' });
}

test "input: empty value without placeholder shows a blank cursor at the start" {
    var buf = try renderInput(Input.init("").withCursor(0), 10, 1);
    defer buf.deinit();

    try expectCursorAt(buf, 0, 10, 0);
    try testing.expectEqual(@as(u21, ' '), buf.getConst(0, 0).?.char);
}

test "input: custom cursor style is applied to the cursor cell" {
    const csty = Style{ .bg = .red, .bold = true };
    var buf = try renderInput(Input.init("ab").withCursor(1).withCursorStyle(csty), 4, 1);
    defer buf.deinit();

    try testing.expectEqual(csty, buf.getConst(1, 0).?.style);
    try testing.expectEqual(Style{}, buf.getConst(0, 0).?.style);
}

test "input: block draws borders and the text sits inside them" {
    const input = Input.init("hello").withBlock(Block{});
    var buf = try renderInput(input, 10, 3);
    defer buf.deinit();

    try testing.expectEqual(@as(u21, '┌'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '┐'), buf.getConst(9, 0).?.char);
    try testing.expectEqual(@as(u21, '└'), buf.getConst(0, 2).?.char);
    try expectRow(buf, 1, 1, &.{ 'h', 'e', 'l', 'l', 'o', ' ', ' ', ' ' });
    try testing.expectEqual(@as(u21, '│'), buf.getConst(0, 1).?.char);
    try testing.expectEqual(@as(u21, '│'), buf.getConst(9, 1).?.char);
}

test "input: block scrolls within the inner width, not the outer width" {
    const input = Input.init("abcdefgh").withBlock(Block{}).withCursor(8);
    var buf = try renderInput(input, 7, 3);
    defer buf.deinit();

    // Inner width 5, cursor 8 -> scroll 4 -> "efgh" + cursor cell.
    try expectRow(buf, 1, 1, &.{ 'e', 'f', 'g', 'h', ' ' });
    try testing.expect(buf.getConst(5, 1).?.style.reverse);
    try testing.expectEqual(@as(u21, '│'), buf.getConst(6, 1).?.char);
}

test "input: only the first inner line is drawn" {
    var buf = try renderInput(Input.init("hi"), 6, 3);
    defer buf.deinit();

    try testing.expectEqual(@as(u21, 'h'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.getConst(0, 1).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.getConst(0, 2).?.char);
}

test "input: area offset is respected and cells outside stay untouched" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();
    buf.fill(.{ .x = 0, .y = 0, .width = 10, .height = 3 }, '.', .{});
    Input.init("ab").render(&buf, .{ .x = 3, .y = 1, .width = 4, .height = 1 });

    try expectRow(buf, 1, 0, &.{ '.', '.', '.', 'a', 'b', ' ', ' ', '.', '.', '.' });
    try expectRow(buf, 0, 0, &.{ '.', '.', '.', '.', '.', '.', '.', '.', '.', '.' });
    try expectRow(buf, 2, 0, &.{ '.', '.', '.', '.', '.', '.', '.', '.', '.', '.' });
}

test "input: zero-sized area or fully consumed inner area draws no text" {
    var buf = try Buffer.init(testing.allocator, 4, 2);
    defer buf.deinit();
    const input = Input.init("abc").withCursor(1);
    input.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 1 });
    input.render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 0 });
    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));

    // A bordered block over 2x2 leaves no inner space: only the corners are drawn.
    input.withBlock(Block{}).render(&buf, .{ .x = 0, .y = 0, .width = 2, .height = 2 });
    try testing.expectEqual(@as(u21, '┌'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '┐'), buf.getConst(1, 0).?.char);
    try testing.expectEqual(@as(u21, '└'), buf.getConst(0, 1).?.char);
    try testing.expectEqual(@as(u21, '┘'), buf.getConst(1, 1).?.char);
    try testing.expect(buf.getConst(2, 0).?.eql(.{}));
}

test "input: text wider than the area is clipped without scrolling" {
    var buf = try renderInput(Input.init("hello world").withCursor(0), 5, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'h', 'e', 'l', 'l', 'o' });
    try expectCursorAt(buf, 0, 5, 0);
}

test "input: cursor beyond the window scrolls the text to keep it visible" {
    var buf = try renderInput(Input.init("hello world").withCursor(10), 5, 1);
    defer buf.deinit();

    // 11 chars, cursor on 'd' (index 10), width 5 -> window shows indices 6..10.
    try expectRow(buf, 0, 0, &.{ 'w', 'o', 'r', 'l', 'd' });
    try expectCursorAt(buf, 0, 5, 4);
}

test "input: cursor at end of overlong text scrolls so the cursor cell stays visible" {
    var buf = try renderInput(Input.init("hello world").withCursor(11), 5, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'o', 'r', 'l', 'd', ' ' });
    try expectCursorAt(buf, 0, 5, 4);
}

test "input: cursor exactly at the width boundary scrolls by one" {
    var buf = try renderInput(Input.init("abcdefgh").withCursor(5), 5, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'b', 'c', 'd', 'e', 'f' });
    try expectCursorAt(buf, 0, 5, 4);
}

test "input: cursor just inside the width does not scroll" {
    var buf = try renderInput(Input.init("abcdefgh").withCursor(4), 5, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'a', 'b', 'c', 'd', 'e' });
    try expectCursorAt(buf, 0, 5, 4);
}

test "input: huge cursor on short text over a narrow area does not panic" {
    // Regression: scroll offset beyond the text made the visible slice start after its end.
    var buf = try renderInput(Input.init("abcdefg").withCursor(100), 5, 1);
    defer buf.deinit();

    // Cursor clamped to 7 -> scroll 3 -> window "defg" plus the cursor cell.
    try expectRow(buf, 0, 0, &.{ 'd', 'e', 'f', 'g', ' ' });
    try expectCursorAt(buf, 0, 5, 4);
}

test "input: multibyte characters are counted by character, one cell each" {
    var buf = try renderInput(Input.init("héllo").withCursor(1), 8, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'h', 'é', 'l', 'l', 'o', ' ' });
    try expectCursorAt(buf, 0, 8, 1);
}

test "input: scrolling skips whole multibyte characters" {
    var buf = try renderInput(Input.init("αβγδε").withCursor(5), 3, 1);
    defer buf.deinit();

    // cursor 5, width 3 -> scroll 3 -> "δε" then cursor cell.
    try expectRow(buf, 0, 0, &.{ 'δ', 'ε', ' ' });
    try expectCursorAt(buf, 0, 3, 2);
}

test "input: truncated trailing UTF-8 sequence renders as a blank cell" {
    // Regression: a lead byte whose continuation bytes are missing indexed past the end.
    var buf = try renderInput(Input.init("a\xE4").withCursor(0), 4, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'a', ' ', ' ', ' ' });
    try expectCursorAt(buf, 0, 4, 0);
}

test "input: invalid lead byte renders as a blank cell and rendering continues" {
    var buf = try renderInput(Input.init("a\xFFb").withCursor(3), 5, 1);
    defer buf.deinit();

    try expectRow(buf, 0, 0, &.{ 'a', ' ', 'b', ' ', ' ' });
    try expectCursorAt(buf, 0, 5, 3);
}

test "input: saveState captures value, cursor and placeholder with empty history" {
    const input = Input.init("hello").withCursor(3).withPlaceholder("enter text");
    const state = input.saveState();

    try testing.expectEqualStrings("hello", state.value);
    try testing.expectEqual(@as(usize, 3), state.cursor);
    try testing.expectEqualStrings("enter text", state.placeholder.?);
    try testing.expectEqual(@as(usize, 0), state.history.len);
    try testing.expectEqual(@as(usize, 0), state.history_index);
}

test "input: saveState without placeholder yields null placeholder" {
    const state = Input.init("test").withCursor(0).saveState();

    try testing.expectEqualStrings("test", state.value);
    try testing.expectEqual(@as(usize, 0), state.cursor);
    try testing.expectEqual(@as(?[]const u8, null), state.placeholder);
}

test "input: restoreState replaces value, cursor and placeholder but keeps styling" {
    const sty = Style{ .fg = .magenta };
    const different = Input.init("xyz").withCursor(0).withPlaceholder("other").withStyle(sty);
    const state = Input.init("abc123").withCursor(6).withPlaceholder("type").saveState();
    const restored = different.restoreState(state);

    try testing.expectEqualStrings("abc123", restored.value);
    try testing.expectEqual(@as(usize, 6), restored.cursor);
    try testing.expectEqualStrings("type", restored.placeholder.?);
    try testing.expectEqual(sty, restored.style);
}

test "input: restoreState clears a placeholder the saved state did not have" {
    const state = Input.init("w").saveState();
    const restored = Input.init("").withPlaceholder("old").restoreState(state);

    try testing.expect(restored.placeholder == null);
    try testing.expectEqualStrings("w", restored.value);
}

test "input: save then restore then render reproduces the original cells" {
    const original = Input.init("round trip").withCursor(4).withPlaceholder("p");
    const restored = Input.init("").restoreState(original.saveState());
    var a = try renderInput(original, 12, 1);
    defer a.deinit();
    var b = try renderInput(restored, 12, 1);
    defer b.deinit();

    try testing.expectEqual(a.cells.len, b.cells.len);
    for (a.cells, b.cells) |ca, cb| try testing.expect(ca.eql(cb));
}

test "input: model check - cursor cell is unique and text matches a reference window" {
    var prng = std.Random.DefaultPrng.init(0x1234_5678);
    const rng = prng.random();
    const alphabet = "abcdef";
    var text: [16]u8 = undefined;

    for (0..300) |_| {
        const len = rng.uintAtMost(usize, text.len);
        for (text[0..len]) |*c| c.* = alphabet[rng.uintLessThan(usize, alphabet.len)];
        const width = rng.intRangeAtMost(u16, 1, 10);
        const cursor = rng.uintAtMost(usize, len + 3);
        const input = Input.init(text[0..len]).withCursor(cursor);
        var buf = try renderInput(input, width, 1);
        defer buf.deinit();

        // Reference model: clamp cursor, scroll just enough, then copy the window.
        const cur = @min(cursor, len);
        const scroll = if (cur >= width) cur - width + 1 else 0;
        var cursor_cells: usize = 0;
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const idx = scroll + x;
            const expected: u21 = if (idx < len) text[idx] else ' ';
            const cell = buf.getConst(x, 0).?;
            try testing.expectEqual(expected, cell.char);
            // len == 0 and cursor cell at idx 0 also reverses, consistent with idx == cur.
            try testing.expectEqual(idx == cur, cell.style.reverse);
            if (cell.style.reverse) cursor_cells += 1;
        }
        try testing.expectEqual(@as(usize, 1), cursor_cells);
    }
}

fn fuzzRender(_: void, smith: *testing.Smith) anyerror!void {
    var bytes: [48]u8 = undefined;
    const len: usize = smith.valueRangeAtMost(u8, 0, bytes.len);
    smith.bytes(bytes[0..len]);
    const width = smith.valueRangeAtMost(u16, 1, 12);
    const cursor: usize = smith.valueRangeAtMost(u8, 0, 64);
    var buf = try Buffer.init(testing.allocator, width, 1);
    defer buf.deinit();
    const input = Input.init(bytes[0..len]).withCursor(cursor).withPlaceholder(bytes[0..len]);

    input.render(&buf, .{ .x = 0, .y = 0, .width = width, .height = 1 });
    buf.check_invariants();
    // Postcondition: rendering never touches style outside the three known styles.
    for (buf.cells) |cell| {
        const known = std.meta.eql(cell.style, input.style) or
            std.meta.eql(cell.style, input.cursor_style) or
            std.meta.eql(cell.style, input.placeholder_style);
        try testing.expect(known);
    }
}

test "input: fuzz render with arbitrary bytes never panics and only uses known styles" {
    try testing.fuzz({}, fuzzRender, .{});
}
