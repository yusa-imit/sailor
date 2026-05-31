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

    /// Enter edit mode and copy current cell text to buffer
    pub fn startEdit(self: *EditableTable) void {
        if (self.edit_buffer.len == 0) return;

        // Clear buffer
        self.edit_len = 0;

        // Copy current cell text to buffer
        if (self.currentCell()) |cell_text| {
            const copy_len = @min(cell_text.len, self.edit_buffer.len);
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

    /// Insert character at end of edit buffer
    pub fn insertChar(self: *EditableTable, ch: u8) void {
        if (self.edit_len < self.edit_buffer.len) {
            self.edit_buffer[self.edit_len] = ch;
            self.edit_len += 1;
        }
    }

    /// Delete last character from edit buffer
    pub fn deleteChar(self: *EditableTable) void {
        if (self.edit_len > 0) {
            self.edit_len -= 1;
        }
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

        var y_pos: u16 = inner.y;

        // Render header row if there are headers
        if (self.headers.len > 0 and y_pos < area.y + area.height) {
            self.renderHeaderRow(buf, inner, y_pos);
            y_pos += 1;
        }

        // Render data rows
        const num_data_rows = self.rows.len;
        if (num_data_rows == 0) return;

        var visible_rows: usize = 0;
        var row_idx = self.scroll_top;

        while (row_idx < num_data_rows and y_pos < area.y + area.height) : ({
            row_idx += 1;
            y_pos += 1;
        }) {
            self.renderDataRow(buf, inner, y_pos, row_idx);
            visible_rows += 1;
        }
    }

    fn renderHeaderRow(self: EditableTable, buf: *Buffer, area: Rect, y: u16) void {
        var x_pos = area.x;

        for (self.headers, 0..) |header, col_idx| {
            const col_width = self.getColumnWidth(col_idx, area.width, self.headers.len);
            if (col_width == 0) continue;

            // Render header text in header_style
            const render_len = @min(header.len, col_width);
            buf.setString(x_pos, y, header[0..render_len], self.header_style);

            // Pad remainder
            if (render_len < col_width) {
                for (render_len..col_width) |i| {
                    buf.set(x_pos + @as(u16, @intCast(i)), y, .{
                        .char = ' ',
                        .style = self.header_style,
                    });
                }
            }

            x_pos +|= col_width;
        }
    }

    fn renderDataRow(self: EditableTable, buf: *Buffer, area: Rect, y: u16, row_idx: usize) void {
        if (row_idx >= self.rows.len) return;

        const row = self.rows[row_idx];
        var x_pos = area.x;
        const is_selected_row = (row_idx == self.selected_row);

        for (self.headers, 0..) |_, col_idx| {
            const col_width = self.getColumnWidth(col_idx, area.width, self.headers.len);
            if (col_width == 0) {
                x_pos +|= col_width;
                continue;
            }

            const cell_text = if (col_idx < row.len) row[col_idx] else "";
            const is_selected_cell = is_selected_row and col_idx == self.selected_col;

            if (self.is_editing and is_selected_cell) {
                // Render edit buffer
                const edit_text = self.editText();
                const render_len = @min(edit_text.len, col_width);
                buf.setString(x_pos, y, edit_text[0..render_len], self.editing_style);

                // Pad remainder
                if (render_len < col_width) {
                    for (render_len..col_width) |i| {
                        buf.set(x_pos + @as(u16, @intCast(i)), y, .{
                            .char = ' ',
                            .style = self.editing_style,
                        });
                    }
                }
            } else if (is_selected_cell) {
                // Render selected cell
                const render_len = @min(cell_text.len, col_width);
                buf.setString(x_pos, y, cell_text[0..render_len], self.selected_style);

                // Pad remainder
                if (render_len < col_width) {
                    for (render_len..col_width) |i| {
                        buf.set(x_pos + @as(u16, @intCast(i)), y, .{
                            .char = ' ',
                            .style = self.selected_style,
                        });
                    }
                }
            } else {
                // Render normal cell
                const render_len = @min(cell_text.len, col_width);
                buf.setString(x_pos, y, cell_text[0..render_len], .{});

                // Pad remainder
                if (render_len < col_width) {
                    for (render_len..col_width) |i| {
                        buf.set(x_pos + @as(u16, @intCast(i)), y, .{
                            .char = ' ',
                            .style = .{},
                        });
                    }
                }
            }

            x_pos +|= col_width;
        }
    }

    fn getColumnWidth(self: EditableTable, col_idx: usize, total_width: u16, num_cols: usize) u16 {
        if (num_cols == 0 or total_width == 0) return 0;

        // If col_widths provided, use them; otherwise distribute equally
        if (col_idx < self.col_widths.len) {
            return self.col_widths[col_idx];
        }

        return total_width / @as(u16, @intCast(num_cols));
    }
};

test "EditableTable default state" {
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
    };
    const table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    try std.testing.expectEqual(@as(usize, 0), table.selected_row);
    try std.testing.expectEqual(@as(usize, 0), table.selected_col);
    try std.testing.expect(!table.is_editing);
    try std.testing.expectEqual(@as(usize, 0), table.scroll_top);
}

test "EditableTable with fixed col_widths" {
    var col_widths = [_]u16{ 10, 5 };
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
    };
    const table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .col_widths = &col_widths,
    };
    try std.testing.expectEqual(@as(usize, 2), table.col_widths.len);
    try std.testing.expectEqual(@as(u16, 10), table.col_widths[0]);
}

test "moveDown — cursor moves to next row" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
        &[_][]const u8{ "B1", "B2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table.moveDown();
    try std.testing.expectEqual(@as(usize, 1), table.selected_row);
}

test "moveDown — cursor stays at last row" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
        &[_][]const u8{ "B1" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_row = 1,
    };
    table.moveDown();
    try std.testing.expectEqual(@as(usize, 1), table.selected_row);
}

test "moveUp — cursor moves to previous row" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A" },
        &[_][]const u8{ "B" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_row = 1,
    };
    table.moveUp();
    try std.testing.expectEqual(@as(usize, 0), table.selected_row);
}

test "moveRight — cursor moves to next column" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table.moveRight();
    try std.testing.expectEqual(@as(usize, 1), table.selected_col);
}

test "moveLeft — cursor moves to previous column" {
    var headers = [_][]const u8{ "Col1", "Col2" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1", "A2" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .selected_col = 1,
    };
    table.moveLeft();
    try std.testing.expectEqual(@as(usize, 0), table.selected_col);
}

test "startEdit — enters edit mode" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    try std.testing.expect(!table.is_editing);
    table.startEdit();
    try std.testing.expect(table.is_editing);
}

test "startEdit — copies cell text to edit buffer" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    const text = table.editText();
    try std.testing.expectEqualStrings("Alice", text);
}

test "insertChar — appends character to edit buffer" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.insertChar('A');
    try std.testing.expectEqualStrings("A", table.editText());
}

test "deleteChar — removes last character from edit buffer" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.deleteChar();
    try std.testing.expectEqualStrings("Alic", table.editText());
}

test "confirmEdit — exits edit mode" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    try std.testing.expect(table.is_editing);
    table.confirmEdit();
    try std.testing.expect(!table.is_editing);
}

test "cancelEdit — exits edit mode" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    table.startEdit();
    table.cancelEdit();
    try std.testing.expect(!table.is_editing);
}

test "currentCell — returns selected cell text" {
    var headers = [_][]const u8{ "Name", "Age" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice", "30" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    const cell = table.currentCell();
    try std.testing.expect(cell != null);
    try std.testing.expectEqualStrings("Alice", cell.?);
}

test "currentCell — null when no rows" {
    var headers = [_][]const u8{ "Name" };
    var table = EditableTable{
        .headers = &headers,
        .rows = &.{},
    };
    const cell = table.currentCell();
    try std.testing.expect(cell == null);
}

test "editText — returns empty string when not editing" {
    var headers = [_][]const u8{ "Name" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    const text = table.editText();
    try std.testing.expectEqualStrings("", text);
}

test "render — zero area is safe" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
        .edit_buffer = &edit_buf,
    };
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 5 });
}

test "render — empty rows is safe" {
    var headers = [_][]const u8{ "Col1" };
    var edit_buf = [_]u8{0} ** 256;
    var table = EditableTable{
        .headers = &headers,
        .rows = &.{},
        .edit_buffer = &edit_buf,
    };
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    table.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
}

test "withBlock — sets block wrapper" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    const block = Block{ .borders = .all, .title = "Table" };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table = table.withBlock(block);
    try std.testing.expect(table.block != null);
    try std.testing.expectEqualStrings("Table", table.block.?.title);
}

test "withScroll — sets scroll position" {
    var headers = [_][]const u8{ "Col1" };
    var rows = [_][]const []const u8{
        &[_][]const u8{ "A1" },
    };
    var table = EditableTable{
        .headers = &headers,
        .rows = &rows,
    };
    table = table.withScroll(5);
    try std.testing.expectEqual(@as(usize, 5), table.scroll_top);
}
