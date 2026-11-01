//! EditableTable — interactive table with inline cell editing (v2.17.0)
//!
//! Renders a table with row/column selection and inline edit mode.
//! Users can navigate with arrow keys, enter edit mode to modify cell text,
//! and confirm/cancel edits.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

/// Cell state (used for visual indication)
pub const CellState = enum {
    normal,
    selected,
    editing,
};

/// EditableTable widget — table with cell-level editing
pub const EditableTable = struct {
    /// Header row strings
    headers: []const []const u8,

    /// Data rows: each row is a slice of cell values
    rows: []const []const []const u8,

    /// Column widths in pixels (optional; if empty, distribute equally)
    col_widths: []const u16 = &.{},

    /// Currently selected row index (relative to data rows, not header)
    selected_row: usize = 0,

    /// Currently selected column index
    selected_col: usize = 0,

    /// Edit buffer for inline editing
    edit_buffer: []u8 = &.{},

    /// Number of valid characters in edit_buffer
    edit_len: usize = 0,

    /// Whether we are in edit mode
    is_editing: bool = false,

    /// Vertical scroll offset (first visible data row index)
    scroll_top: usize = 0,

    /// Style for header row
    header_style: Style = .{ .bold = true },

    /// Style for selected cell
    selected_style: Style = .{ .reverse = true },

    /// Style for cell in edit mode
    editing_style: Style = .{ .fg = .yellow },

    /// Optional block for borders
    block: ?Block = null,

    // ========================================================================
    // Navigation
    // ========================================================================

    /// Move cursor down one row (clamped)
    pub fn moveDown(self: *EditableTable) void {
        if (self.rows.len == 0) return;
        if (self.selected_row < self.rows.len - 1) {
            self.selected_row += 1;
        }
    }

    /// Move cursor up one row (clamped)
    pub fn moveUp(self: *EditableTable) void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
        }
    }

    /// Move cursor right one column (clamped)
    pub fn moveRight(self: *EditableTable) void {
        if (self.headers.len == 0) return;
        if (self.selected_col < self.headers.len - 1) {
            self.selected_col += 1;
        }
    }

    /// Move cursor left one column (clamped)
    pub fn moveLeft(self: *EditableTable) void {
        if (self.selected_col > 0) {
            self.selected_col -= 1;
        }
    }

    // ========================================================================
    // Edit Mode
    // ========================================================================

    /// Enter edit mode and copy current cell text to buffer. Text longer than the buffer is
    /// cut at a character boundary. No-op without an edit buffer.
    pub fn startEdit(self: *EditableTable) void {
        if (self.edit_buffer.len == 0) return;

        // Clear buffer
        self.edit_len = 0;

        // Copy current cell text to buffer
        if (self.currentCell()) |cell_text| {
            const copy_len = utf8Prefix(cell_text, self.edit_buffer.len);
            @memcpy(self.edit_buffer[0..copy_len], cell_text[0..copy_len]);
            self.edit_len = copy_len;
        }

        self.is_editing = true;
    }

    /// Exit edit mode (preserving buffer content)
    pub fn confirmEdit(self: *EditableTable) void {
        self.is_editing = false;
    }

    /// Exit edit mode without saving
    pub fn cancelEdit(self: *EditableTable) void {
        self.is_editing = false;
    }

    /// Insert a byte at the end of the edit buffer; no-op when not editing or the buffer is full
    pub fn insertChar(self: *EditableTable, ch: u8) void {
        if (!self.is_editing) return;
        if (self.edit_len < self.edit_buffer.len) {
            self.edit_buffer[self.edit_len] = ch;
            self.edit_len += 1;
        }
    }

    /// Delete the last character (a whole UTF-8 sequence) from the edit buffer; no-op when not
    /// editing or empty
    pub fn deleteChar(self: *EditableTable) void {
        if (!self.is_editing) return;
        if (self.edit_len == 0) return;
        var pos = self.edit_len - 1;
        var back: u8 = 0;
        while (pos > 0 and back < 3 and isContinuation(self.edit_buffer[pos])) : (back += 1) {
            pos -= 1;
        }
        self.edit_len = pos;
    }

    // ========================================================================
    // Query
    // ========================================================================

    /// Get the current cell text, or null if out of bounds
    pub fn currentCell(self: EditableTable) ?[]const u8 {
        if (self.selected_row >= self.rows.len) return null;
        const row = self.rows[self.selected_row];
        if (self.selected_col >= row.len) return null;
        return row[self.selected_col];
    }

    /// Get the current edit buffer content
    pub fn editText(self: EditableTable) []const u8 {
        if (!self.is_editing) return "";
        return self.edit_buffer[0..self.edit_len];
    }

    // ========================================================================
    // Builder Methods
    // ========================================================================

    /// Set block (border/title)
    pub fn withBlock(self: EditableTable, new_block: Block) EditableTable {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set vertical scroll position
    pub fn withScroll(self: EditableTable, top: usize) EditableTable {
        var result = self;
        result.scroll_top = top;
        return result;
    }

    // ========================================================================
    // Rendering
    // ========================================================================

    /// Render the table to buffer
    pub fn render(self: EditableTable, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        // Rows stop at the inner bottom (so a bottom border survives) and at the buffer edge.
        const bottom: u32 = @min(@as(u32, inner.y) + inner.height, buf.height);
        var y: u32 = inner.y;

        if (self.headers.len > 0 and y < bottom) {
            self.drawRow(buf, inner, @intCast(y), self.headers, .{ .header = true });
            y += 1;
        }

        var row_idx = self.scroll_top;
        while (row_idx < self.rows.len and y < bottom) : ({
            row_idx += 1;
            y += 1;
        }) {
            // y < bottom <= buf.height <= maxInt(u16).
            self.drawRow(buf, inner, @intCast(y), self.rows[row_idx], .{
                .header = false,
                .selected = row_idx == self.selected_row,
            });
        }
    }

    const RowKind = struct {
        header: bool,
        selected: bool = false,
    };

    /// Draw one row of `self.headers.len` cells, each clipped to the inner right edge.
    fn drawRow(
        self: EditableTable,
        buf: *Buffer,
        inner: Rect,
        y: u16,
        cells: []const []const u8,
        kind: RowKind,
    ) void {
        const right: u32 = @as(u32, inner.x) + inner.width;
        var x: u32 = inner.x;

        for (0..self.headers.len) |col_idx| {
            if (x >= right or x >= buf.width) break;
            const wanted = self.getColumnWidth(col_idx, inner.width, self.headers.len);
            const width: u16 = @intCast(@min(@as(u32, wanted), right - x));
            const is_cell_selected = kind.selected and col_idx == self.selected_col;
            const style = if (kind.header)
                self.header_style
            else if (is_cell_selected and self.is_editing)
                self.editing_style
            else if (is_cell_selected)
                self.selected_style
            else
                Style{};
            const text = if (is_cell_selected and self.is_editing)
                self.editText()
            else if (col_idx < cells.len)
                cells[col_idx]
            else
                "";
            // x < buf.width <= maxInt(u16), so the narrowing cannot truncate.
            drawCell(buf, @intCast(x), y, width, text, style);
            x += wanted;
        }
    }

    fn getColumnWidth(self: EditableTable, col_idx: usize, total_width: u16, num_cols: usize) u16 {
        if (num_cols == 0 or total_width == 0) return 0;

        // If col_widths provided, use them; otherwise distribute equally
        if (col_idx < self.col_widths.len) {
            return self.col_widths[col_idx];
        }

        // total_width / num_cols <= total_width, so it fits u16.
        return @intCast(total_width / num_cols);
    }
};

/// A byte that continues (does not start) a UTF-8 sequence.
fn isContinuation(byte: u8) bool {
    return byte & 0xC0 == 0x80;
}

/// Longest prefix length of `text` that is at most `max` bytes and ends on a character boundary.
fn utf8Prefix(text: []const u8, max: usize) usize {
    if (text.len <= max) return text.len;
    var n = max;
    var back: u8 = 0;
    while (n > 0 and back < 3 and isContinuation(text[n])) : (back += 1) n -= 1;
    return n;
}

/// Fill `width` cells at (x, y) with `style`, then draw `text` clipped to those cells by width.
fn drawCell(buf: *Buffer, x: u16, y: u16, width: u16, text: []const u8, style: Style) void {
    if (width == 0) return;
    buf.fill(.{ .x = x, .y = y, .width = width, .height = 1 }, ' ', style);
    const bytes = UnicodeWidth.truncate(text, width);
    buf.setString(x, y, text[0..bytes], style);
}

// Tests

const testing = std.testing;
const Cell = buffer_mod.Cell;

const header_bold: Style = .{ .bold = true };
const reverse: Style = .{ .reverse = true };
const yellow: Style = .{ .fg = .yellow };

fn full(w: u16, h: u16) Rect {
    return .{ .x = 0, .y = 0, .width = w, .height = h };
}

/// Assert `width` cells at (x, y) hold `text` (one codepoint per cell) padded with spaces,
/// every cell carrying `want`.
fn expectSpan(buf: Buffer, x: u16, y: u16, width: u16, text: []const u8, want: Style) !void {
    var view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    var col: u16 = 0;
    while (col < width) : (col += 1) {
        const ch: u21 = it.nextCodepoint() orelse ' ';
        const cell = buf.getConst(x + col, y) orelse return error.TestUnexpectedResult;
        try testing.expectEqual(ch, cell.char);
        try testing.expectEqual(want, cell.style);
    }
}

fn expectBlankFrom(buf: Buffer, x: u16, y: u16) !void {
    var col = x;
    while (col < buf.width) : (col += 1) try testing.expectEqual(Cell{}, buf.getConst(col, y).?);
}

fn expectAllBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expectEqual(Cell{}, cell);
}

const two_headers = [_][]const u8{ "Name", "Age" };
const people = [_][]const []const u8{
    &[_][]const u8{ "Alice", "30" },
    &[_][]const u8{ "Bob", "25" },
    &[_][]const u8{ "Carol", "41" },
};

fn tableWith(edit_buf: []u8) EditableTable {
    return .{ .headers = &two_headers, .rows = &people, .edit_buffer = edit_buf };
}

test "EditableTable: default state selects the first cell and is not editing" {
    const table = EditableTable{ .headers = &two_headers, .rows = &people };
    try testing.expectEqual(@as(usize, 0), table.selected_row);
    try testing.expectEqual(@as(usize, 0), table.selected_col);
    try testing.expectEqual(@as(usize, 0), table.scroll_top);
    try testing.expectEqual(@as(usize, 0), table.edit_len);
    try testing.expect(!table.is_editing);
    try testing.expect(table.block == null);
    try testing.expectEqual(@as(usize, 0), table.col_widths.len);
    try testing.expect(table.header_style.bold);
    try testing.expect(table.selected_style.reverse);
    try testing.expectEqual(yellow, table.editing_style);
}

test "EditableTable: cursor movement clamps at every edge" {
    var table = EditableTable{ .headers = &two_headers, .rows = &people };

    table.moveUp();
    table.moveLeft();
    try testing.expectEqual(@as(usize, 0), table.selected_row);
    try testing.expectEqual(@as(usize, 0), table.selected_col);

    for (0..6) |_| table.moveDown();
    for (0..6) |_| table.moveRight();
    try testing.expectEqual(@as(usize, 2), table.selected_row);
    try testing.expectEqual(@as(usize, 1), table.selected_col);

    table.moveUp();
    table.moveLeft();
    try testing.expectEqual(@as(usize, 1), table.selected_row);
    try testing.expectEqual(@as(usize, 0), table.selected_col);
}

test "EditableTable: movement on an empty table is a no-op" {
    var table = EditableTable{ .headers = &.{}, .rows = &.{} };
    table.moveDown();
    table.moveRight();
    table.moveUp();
    table.moveLeft();
    try testing.expectEqual(@as(usize, 0), table.selected_row);
    try testing.expectEqual(@as(usize, 0), table.selected_col);
}

test "EditableTable: currentCell follows the cursor and is null out of range" {
    var table = EditableTable{ .headers = &two_headers, .rows = &people };
    try testing.expectEqualStrings("Alice", table.currentCell().?);
    table.moveDown();
    table.moveRight();
    try testing.expectEqualStrings("25", table.currentCell().?);

    table.selected_row = 99;
    try testing.expect(table.currentCell() == null);
    table.selected_row = 0;
    table.selected_col = 99;
    try testing.expect(table.currentCell() == null);
    const empty = EditableTable{ .headers = &two_headers, .rows = &.{} };
    try testing.expect(empty.currentCell() == null);
}

test "EditableTable: startEdit copies the cell text and enters edit mode" {
    var edit_buf = [_]u8{0} ** 32;
    var table = tableWith(&edit_buf);
    try testing.expectEqualStrings("", table.editText());

    table.startEdit();

    try testing.expect(table.is_editing);
    try testing.expectEqualStrings("Alice", table.editText());
    try testing.expectEqual(@as(usize, 5), table.edit_len);
}

test "EditableTable: startEdit without an edit buffer does nothing" {
    var table = EditableTable{ .headers = &two_headers, .rows = &people };
    table.startEdit();
    try testing.expect(!table.is_editing);
    try testing.expectEqual(@as(usize, 0), table.edit_len);
}

test "EditableTable: startEdit cuts long text on a character boundary" {
    const rows = [_][]const []const u8{&[_][]const u8{ "aé", "世界" }};
    var edit_buf = [_]u8{0} ** 4;
    var table = EditableTable{ .headers = &two_headers, .rows = &rows, .edit_buffer = &edit_buf };

    // "aé" is 3 bytes: a 2-byte buffer would split the 2-byte é.
    table.edit_buffer = edit_buf[0..2];
    table.startEdit();
    try testing.expectEqualStrings("a", table.editText());

    table.moveRight(); // "世界" is 6 bytes; 4 bytes would split 界.
    table.edit_buffer = edit_buf[0..4];
    table.startEdit();
    try testing.expectEqualStrings("世", table.editText());
}

test "EditableTable: startEdit again restarts from the cell, discarding typed text" {
    var edit_buf = [_]u8{0} ** 32;
    var table = tableWith(&edit_buf);
    table.startEdit();
    table.insertChar('!');

    table.moveDown();
    table.startEdit();

    try testing.expectEqualStrings("Bob", table.editText());
}

test "EditableTable: insertChar appends and ignores input once the buffer is full" {
    const rows = [_][]const []const u8{&[_][]const u8{ "", "" }};
    var edit_buf = [_]u8{0} ** 3;
    var table = EditableTable{ .headers = &two_headers, .rows = &rows, .edit_buffer = &edit_buf };
    table.startEdit();

    for ("ABCDE") |ch| table.insertChar(ch);

    try testing.expectEqualStrings("ABC", table.editText());
    try testing.expectEqual(@as(usize, 3), table.edit_len);
}

test "EditableTable: insertChar and deleteChar are ignored when not editing" {
    var edit_buf = [_]u8{0} ** 8;
    var table = tableWith(&edit_buf);

    table.insertChar('X');
    table.deleteChar();

    try testing.expectEqual(@as(usize, 0), table.edit_len);
    try testing.expect(!table.is_editing);
    try testing.expectEqualStrings("", table.editText());
}

test "EditableTable: deleteChar removes one character and stops at empty" {
    var edit_buf = [_]u8{0} ** 32;
    var table = tableWith(&edit_buf);
    table.startEdit();

    table.deleteChar();
    try testing.expectEqualStrings("Alic", table.editText());
    for (0..9) |_| table.deleteChar();
    try testing.expectEqualStrings("", table.editText());
    try testing.expectEqual(@as(usize, 0), table.edit_len);
    try testing.expect(table.is_editing);
}

test "EditableTable: deleteChar removes a whole multibyte character" {
    const rows = [_][]const []const u8{&[_][]const u8{ "aé世", "😀" }};
    var edit_buf = [_]u8{0} ** 16;
    var table = EditableTable{ .headers = &two_headers, .rows = &rows, .edit_buffer = &edit_buf };
    table.startEdit();

    table.deleteChar();
    try testing.expectEqualStrings("aé", table.editText());
    table.deleteChar();
    try testing.expectEqualStrings("a", table.editText());

    table.moveRight();
    table.startEdit();
    table.deleteChar();
    try testing.expectEqualStrings("", table.editText());
}

test "EditableTable: confirmEdit and cancelEdit both leave edit mode, rows stay untouched" {
    var edit_buf = [_]u8{0} ** 32;
    var table = tableWith(&edit_buf);

    table.startEdit();
    table.insertChar('!');
    table.confirmEdit();
    try testing.expect(!table.is_editing);
    try testing.expectEqualStrings("Alice!", edit_buf[0..table.edit_len]);
    try testing.expectEqualStrings("", table.editText());

    table.startEdit();
    table.insertChar('?');
    table.cancelEdit();
    try testing.expect(!table.is_editing);
    try testing.expectEqualStrings("", table.editText());
    try testing.expectEqualStrings("Alice", people[0][0]);

    table.confirmEdit(); // Not editing: still a harmless no-op.
    table.cancelEdit();
    try testing.expect(!table.is_editing);
}

test "EditableTable: builders replace only their own field" {
    const base = EditableTable{ .headers = &two_headers, .rows = &people };

    const scrolled = base.withScroll(2);
    try testing.expectEqual(@as(usize, 2), scrolled.scroll_top);
    try testing.expect(scrolled.block == null);

    const blocked = base.withBlock(.{ .title = "Table" });
    try testing.expectEqualStrings("Table", blocked.block.?.title.?);
    try testing.expectEqual(@as(usize, 0), blocked.scroll_top);
}

test "EditableTable: render draws header, rows and the selected cell exactly" {
    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();
    var edit_buf = [_]u8{0} ** 8;

    tableWith(&edit_buf).render(&buf, full(20, 5));

    buf.check_invariants();
    try expectSpan(buf, 0, 0, 10, "Name", header_bold);
    try expectSpan(buf, 10, 0, 10, "Age", header_bold);
    try expectSpan(buf, 0, 1, 10, "Alice", reverse);
    try expectSpan(buf, 10, 1, 10, "30", .{});
    try expectSpan(buf, 0, 2, 10, "Bob", .{});
    try expectSpan(buf, 10, 2, 10, "25", .{});
    try expectSpan(buf, 0, 3, 10, "Carol", .{});
    try expectSpan(buf, 10, 3, 10, "41", .{});
    try expectBlankFrom(buf, 0, 4);
}

test "EditableTable: selection moves the highlight to the new cell only" {
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    var table = EditableTable{ .headers = &two_headers, .rows = &people };
    table.moveDown();
    table.moveRight();

    table.render(&buf, full(20, 4));

    try expectSpan(buf, 0, 1, 10, "Alice", .{});
    try expectSpan(buf, 10, 1, 10, "30", .{});
    try expectSpan(buf, 0, 2, 10, "Bob", .{});
    try expectSpan(buf, 10, 2, 10, "25", reverse);
}

test "EditableTable: selection outside the rows highlights nothing" {
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    var table = EditableTable{ .headers = &two_headers, .rows = &people };
    table.selected_row = 99;

    table.render(&buf, full(20, 4));

    for (1..4) |y| {
        try expectSpan(buf, 0, @intCast(y), 10, people[y - 1][0], .{});
    }
}

test "EditableTable: the editing cell shows the edit text in editing_style" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    var edit_buf = [_]u8{0} ** 8;
    var table = tableWith(&edit_buf);
    table.startEdit();
    table.insertChar('!');
    table.deleteChar();
    table.insertChar('?');

    table.render(&buf, full(20, 3));

    try expectSpan(buf, 0, 1, 10, "Alice?", yellow);
    try expectSpan(buf, 10, 1, 10, "30", .{});
}

test "EditableTable: after confirm the cell shows the stored text and selected style again" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    var edit_buf = [_]u8{0} ** 8;
    var table = tableWith(&edit_buf);
    table.startEdit();
    table.insertChar('!');
    table.confirmEdit();

    table.render(&buf, full(20, 3));

    try expectSpan(buf, 0, 1, 10, "Alice", reverse);
}

test "EditableTable: fixed col_widths are used and text is cut to its column" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const rows = [_][]const []const u8{&[_][]const u8{ "Alexander", "7" }};
    const widths = [_]u16{ 6, 4 };
    var table = EditableTable{ .headers = &two_headers, .rows = &rows, .col_widths = &widths };
    table.selected_row = 1; // Nothing highlighted: keep styles plain.

    table.render(&buf, full(20, 3));

    try expectSpan(buf, 0, 0, 6, "Name", header_bold);
    try expectSpan(buf, 6, 0, 4, "Age", header_bold);
    try expectSpan(buf, 0, 1, 6, "Alexan", .{});
    try expectSpan(buf, 6, 1, 4, "7", .{});
    try expectBlankFrom(buf, 10, 0);
    try expectBlankFrom(buf, 10, 1);
}

test "EditableTable: columns wider than the area are clipped at the area edge" {
    var buf = try Buffer.init(testing.allocator, 30, 2);
    defer buf.deinit();
    const widths = [_]u16{ 10, 10 };
    const table = EditableTable{ .headers = &two_headers, .rows = &people, .col_widths = &widths };

    table.render(&buf, full(15, 2));

    try expectSpan(buf, 0, 0, 10, "Name", header_bold);
    try expectSpan(buf, 10, 0, 5, "Age", header_bold);
    try expectBlankFrom(buf, 15, 0);
    try expectBlankFrom(buf, 15, 1);
}

test "EditableTable: more rows than height are cut at the area bottom" {
    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    (EditableTable{ .headers = &two_headers, .rows = &people }).render(&buf, full(20, 3));

    try expectSpan(buf, 0, 1, 10, "Alice", reverse);
    try expectSpan(buf, 0, 2, 10, "Bob", .{});
    try expectBlankFrom(buf, 0, 3);
    try expectBlankFrom(buf, 0, 4);
}

test "EditableTable: scroll_top hides leading rows and scrolling past the end shows the header" {
    var buf = try Buffer.init(testing.allocator, 20, 4);
    defer buf.deinit();
    const base = EditableTable{ .headers = &two_headers, .rows = &people, .selected_row = 9 };

    base.withScroll(1).render(&buf, full(20, 4));
    try expectSpan(buf, 0, 0, 10, "Name", header_bold);
    try expectSpan(buf, 0, 1, 10, "Bob", .{});
    try expectSpan(buf, 0, 2, 10, "Carol", .{});
    try expectBlankFrom(buf, 0, 3);

    var past = try Buffer.init(testing.allocator, 20, 4);
    defer past.deinit();
    base.withScroll(3).render(&past, full(20, 4));
    try expectSpan(past, 0, 0, 10, "Name", header_bold);
    try expectBlankFrom(past, 0, 1);
}

test "EditableTable: short rows draw empty padded cells" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const rows = [_][]const []const u8{&[_][]const u8{"solo"}};
    const table = EditableTable{ .headers = &two_headers, .rows = &rows, .selected_row = 9 };

    table.render(&buf, full(20, 3));

    try expectSpan(buf, 0, 1, 10, "solo", .{});
    try expectSpan(buf, 10, 1, 10, "", .{});
}

test "EditableTable: wide and accented cells are clipped by cells and fully padded" {
    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    const rows = [_][]const []const u8{&[_][]const u8{ "éé", "世界" }};
    const widths = [_]u16{ 3, 3 };
    const table = EditableTable{ .headers = &two_headers, .rows = &rows, .col_widths = &widths };

    table.render(&buf, full(20, 3));

    // Regression: clipping by bytes cut "éé" mid-character and left the pad cell unstyled.
    try expectSpan(buf, 0, 1, 3, "éé", reverse);
    // A wide character is never split: 世 fits in 3 cells, 界 does not.
    try testing.expectEqual(@as(u21, '世'), buf.getConst(3, 1).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.getConst(5, 1).?.char);
    try testing.expectEqual(Style{}, buf.getConst(5, 1).?.style);
    try expectBlankFrom(buf, 6, 1);
}

test "EditableTable: block keeps its borders and the table stays inside" {
    var buf = try Buffer.init(testing.allocator, 12, 4);
    defer buf.deinit();
    const widths = [_]u16{ 20, 20 };
    const table = EditableTable{ .headers = &two_headers, .rows = &people, .col_widths = &widths };

    table.withBlock(.{}).render(&buf, full(12, 4));

    try testing.expectEqual(@as(u21, '┌'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '┐'), buf.getConst(11, 0).?.char);
    // Rows land on lines 1-2; the bottom border on line 3 is not overwritten by a data row.
    try expectSpan(buf, 1, 1, 4, "Name", header_bold);
    try expectSpan(buf, 1, 2, 4, "Alic", reverse);
    try testing.expectEqual(@as(u21, '│'), buf.getConst(0, 1).?.char);
    try testing.expectEqual(@as(u21, '│'), buf.getConst(11, 1).?.char);
    try testing.expectEqual(@as(u21, '│'), buf.getConst(11, 2).?.char);
    try testing.expectEqual(@as(u21, '└'), buf.getConst(0, 3).?.char);
    try testing.expectEqual(@as(u21, '─'), buf.getConst(5, 3).?.char);
    try testing.expectEqual(@as(u21, '┘'), buf.getConst(11, 3).?.char);
}

test "EditableTable: degenerate areas and tables draw nothing" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();
    var edit_buf = [_]u8{0} ** 8;
    const table = tableWith(&edit_buf);

    table.render(&buf, full(0, 5));
    table.render(&buf, full(10, 0));
    (EditableTable{ .headers = &.{}, .rows = &people }).render(&buf, full(10, 5));
    table.withBlock(.{}).render(&buf, .{ .x = 0, .y = 0, .width = 2, .height = 2 });
    try testing.expectEqual(@as(u21, '┌'), buf.getConst(0, 0).?.char); // block only, no content

    var blank = try Buffer.init(testing.allocator, 10, 5);
    defer blank.deinit();
    table.render(&blank, full(0, 5));
    table.render(&blank, full(10, 0));
    (EditableTable{ .headers = &.{}, .rows = &people }).render(&blank, full(10, 5));
    try expectAllBlank(blank);
}

test "EditableTable: empty rows draw only the header" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    (EditableTable{ .headers = &two_headers, .rows = &.{} }).render(&buf, full(10, 3));

    try expectSpan(buf, 0, 0, 5, "Name", header_bold);
    try expectSpan(buf, 5, 0, 5, "Age", header_bold);
    try expectBlankFrom(buf, 0, 1);
    try expectBlankFrom(buf, 0, 2);
}

test "EditableTable: areas past the u16 range clip instead of overflowing" {
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();
    const table = EditableTable{ .headers = &two_headers, .rows = &people };

    table.render(&buf, .{ .x = 65530, .y = 0, .width = 65535, .height = 3 });
    table.render(&buf, .{ .x = 0, .y = 65534, .width = 65535, .height = 65535 });
    try expectAllBlank(buf);

    const wide = [_]u16{ 65535, 65535, 65535 };
    const three = [_][]const u8{ "a", "b", "c" };
    const many = EditableTable{ .headers = &three, .rows = &.{}, .col_widths = &wide };
    many.render(&buf, full(10, 3));
    try expectSpan(buf, 0, 0, 10, "a", header_bold);
}

test "EditableTable: seeded model - random tables render like a reference grid" {
    var prng = std.Random.DefaultPrng.init(0xED17_AB1E);
    const rand = prng.random();
    const words = [_][]const u8{ "a", "bc", "def", "ghijk", "", "lmnopqrs" };

    for (0..200) |_| {
        const ncols = rand.intRangeAtMost(usize, 1, 4);
        const nrows = rand.uintAtMost(usize, 5);
        var headers: [4][]const u8 = undefined;
        var cells: [5][4][]const u8 = undefined;
        var rows: [5][]const []const u8 = undefined;
        for (0..ncols) |c| headers[c] = words[rand.uintLessThan(usize, words.len)];
        for (0..nrows) |r| {
            for (0..ncols) |c| cells[r][c] = words[rand.uintLessThan(usize, words.len)];
            rows[r] = cells[r][0..ncols];
        }
        const width = rand.intRangeAtMost(u16, 1, 24);
        const height = rand.intRangeAtMost(u16, 1, 7);
        var table = EditableTable{ .headers = headers[0..ncols], .rows = rows[0..nrows] };
        table.selected_row = rand.uintAtMost(usize, nrows);
        table.selected_col = rand.uintLessThan(usize, ncols);
        table.scroll_top = rand.uintAtMost(usize, nrows);

        var buf = try Buffer.init(testing.allocator, width, height);
        defer buf.deinit();
        table.render(&buf, full(width, height));
        buf.check_invariants();

        const col_w = width / ncols;
        for (0..height) |y| {
            const text_row: ?[]const []const u8 = if (y == 0)
                headers[0..ncols]
            else if (table.scroll_top + y - 1 < nrows) rows[table.scroll_top + y - 1] else null;
            const row_idx = table.scroll_top + y -| 1;
            for (0..width) |x| {
                const col = x / @max(col_w, 1);
                const in_col = col_w > 0 and col < ncols;
                var want = Cell{};
                if (text_row) |tr| if (in_col) {
                    const off = x - col * col_w;
                    const word = tr[col];
                    want.char = if (off < word.len) word[off] else ' ';
                    if (y == 0) {
                        want.style = header_bold;
                    } else if (row_idx == table.selected_row and col == table.selected_col) {
                        want.style = reverse;
                    }
                };
                try testing.expectEqual(want, buf.getConst(@intCast(x), @intCast(y)).?);
            }
        }
    }
}
