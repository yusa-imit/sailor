//! RecordEditor — inline record (key-value) field editing widget (v2.17.0)
//!
//! Renders a list of key-value pairs with navigation, inline editing,
//! and optional validation.

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

/// Validation result enum
pub const ValidationResult = enum {
    ok,
    invalid,
};

/// Validation callback function type
pub const ValidateFn = *const fn (key: []const u8, value: []const u8) ValidationResult;

/// A single field in the record
pub const Field = struct {
    /// Field key/name
    key: []const u8,

    /// Field value
    value: []const u8,

    /// Whether this field can be edited
    is_editable: bool = true,
};

/// RecordEditor widget — editable record with field navigation and validation
pub const RecordEditor = struct {
    /// List of fields
    fields: []Field,

    /// Currently selected field index
    selected: usize = 0,

    /// Edit buffer for inline editing
    edit_buffer: []u8 = &.{},

    /// Number of valid characters in edit_buffer
    edit_len: usize = 0,

    /// Whether we are in edit mode
    is_editing: bool = false,

    /// Optional validation function
    validate: ?ValidateFn = null,

    /// Width allocated for keys (rest goes to values)
    key_width: u16 = 20,

    /// Style for normal field
    normal_style: Style = .{},

    /// Style for selected field
    selected_style: Style = .{ .reverse = true },

    /// Style for field in edit mode
    editing_style: Style = .{ .fg = .yellow },

    /// Style for invalid field
    error_style: Style = .{ .fg = .red },

    /// Style for read-only field
    readonly_style: Style = .{ .fg = .bright_black },

    /// Optional block for borders
    block: ?Block = null,

    // ========================================================================
    // Navigation
    // ========================================================================

    /// Move cursor down one field (clamped)
    pub fn moveDown(self: *RecordEditor) void {
        if (self.fields.len == 0) return;
        if (self.selected < self.fields.len - 1) {
            self.selected += 1;
        }
    }

    /// Move cursor up one field (clamped)
    pub fn moveUp(self: *RecordEditor) void {
        if (self.selected > 0) {
            self.selected -= 1;
        }
    }

    // ========================================================================
    // Edit Mode
    // ========================================================================

    /// Enter edit mode for current field and copy value to buffer
    pub fn startEdit(self: *RecordEditor) void {
        if (self.edit_buffer.len == 0) return;

        const field = self.currentField() orelse return;
        if (!field.is_editable) return;

        // Clear buffer
        self.edit_len = 0;

        // Copy field value to buffer
        const copy_len = utf8Boundary(field.value, self.edit_buffer.len);
        @memcpy(self.edit_buffer[0..copy_len], field.value[0..copy_len]);
        self.edit_len = copy_len;

        self.is_editing = true;
    }

    /// Exit edit mode (preserving buffer content)
    pub fn confirmEdit(self: *RecordEditor) void {
        self.is_editing = false;
    }

    /// Exit edit mode without saving
    pub fn cancelEdit(self: *RecordEditor) void {
        self.is_editing = false;
    }

    /// Insert character at end of edit buffer
    pub fn insertChar(self: *RecordEditor, ch: u8) void {
        if (self.edit_len < self.edit_buffer.len) {
            self.edit_buffer[self.edit_len] = ch;
            self.edit_len += 1;
        }
    }

    /// Delete last character from edit buffer
    pub fn deleteChar(self: *RecordEditor) void {
        assert(self.edit_len <= self.edit_buffer.len);
        if (self.edit_len == 0) return;

        // Remove a whole UTF-8 sequence, not a single byte of it.
        self.edit_len -= 1;
        var steps: usize = 0;
        while (steps < utf8_continuation_max and self.edit_len > 0 and
            (self.edit_buffer[self.edit_len] & 0xC0) == 0x80) : (steps += 1)
        {
            self.edit_len -= 1;
        }
        assert(self.edit_len < self.edit_buffer.len);
    }

    // ========================================================================
    // Query
    // ========================================================================

    /// Get the current field, or null if out of bounds
    pub fn currentField(self: RecordEditor) ?*Field {
        if (self.selected >= self.fields.len) return null;
        return &self.fields[self.selected];
    }

    /// Get the current edit buffer content
    pub fn editText(self: RecordEditor) []const u8 {
        if (!self.is_editing) return "";
        return self.edit_buffer[0..self.edit_len];
    }

    /// Check if current edit is valid
    pub fn isValid(self: RecordEditor) bool {
        const field = self.currentField() orelse return true;
        const validate = self.validate orelse return true;

        const result = validate(field.key, self.editText());
        return result == .ok;
    }

    // ========================================================================
    // Builder Methods
    // ========================================================================

    /// Set block (border/title)
    pub fn withBlock(self: RecordEditor, new_block: Block) RecordEditor {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set validation function
    pub fn withValidate(self: RecordEditor, validate_fn: ValidateFn) RecordEditor {
        var result = self;
        result.validate = validate_fn;
        return result;
    }

    // ========================================================================
    // Rendering
    // ========================================================================

    /// Render the record editor to buffer. The area is clamped so `x + width` and `y + height`
    /// fit in `u16`; the selected field is scrolled into view when rows are scarce.
    pub fn render(self: RecordEditor, buf: *Buffer, area_raw: Rect) void {
        if (area_raw.width == 0 or area_raw.height == 0) return;

        var area = area_raw;
        area.width = @min(area.width, std.math.maxInt(u16) - area.x);
        area.height = @min(area.height, std.math.maxInt(u16) - area.y);
        assert(@as(u32, area.x) + area.width <= std.math.maxInt(u16));
        assert(@as(u32, area.y) + area.height <= std.math.maxInt(u16));

        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;
        if (self.fields.len == 0) return;

        const first = scrollStart(self.selected, self.fields.len, inner.height);
        const rows: usize = @min(self.fields.len - first, inner.height);
        assert(rows > 0);
        assert(first + rows <= self.fields.len);

        var row: u16 = 0;
        while (row < rows) : (row += 1) {
            const idx = first + row;
            const field = self.fields[idx];
            const is_selected = (idx == self.selected);
            const styles = self.fieldStyles(field, is_selected);
            const y = inner.y + row; // row < inner.height and inner.y + inner.height fits u16
            self.renderField(buf, inner, y, field, styles, is_selected and self.is_editing);
        }
    }

    /// Index of the first visible field so that `selected` is inside a window of `height` rows.
    fn scrollStart(selected: usize, fields_len: usize, height: u16) usize {
        assert(height > 0);
        assert(fields_len > 0);
        const clamped = @min(selected, fields_len - 1);
        const start = if (clamped >= height) clamped - height + 1 else 0;
        assert(start <= clamped);
        return start;
    }

    const FieldStyles = struct { key: Style, value: Style };

    /// Resolve key and value styles for one field (normal, read-only, selected, editing, error).
    fn fieldStyles(self: RecordEditor, field: Field, is_selected: bool) FieldStyles {
        var styles = FieldStyles{ .key = self.normal_style, .value = self.normal_style };
        if (!field.is_editable) styles.value = self.readonly_style;

        if (is_selected) {
            styles = .{ .key = self.selected_style, .value = self.selected_style };
        }

        if (self.is_editing and is_selected) {
            const edit_style = if (self.isValid()) self.editing_style else self.error_style;
            styles = .{ .key = edit_style, .value = edit_style };
        }
        return styles;
    }

    fn renderField(
        self: RecordEditor,
        buf: *Buffer,
        area: Rect,
        y: u16,
        field: Field,
        styles: FieldStyles,
        is_editing: bool,
    ) void {
        assert(area.width > 0);
        assert(@as(u32, area.x) + area.width <= std.math.maxInt(u16));

        const key_width = @min(self.key_width, area.width);
        drawCell(buf, area.x, y, key_width, field.key, styles.key);

        const value_text = if (is_editing) self.editText() else field.value;
        const value_width = area.width - key_width;
        drawCell(buf, area.x + key_width, y, value_width, value_text, styles.value);
    }

    /// Draw `text` clipped to `width` terminal cells at (`x`, `y`), then pad with spaces up to
    /// `width`. Clipping and padding are by display width, never by byte count.
    fn drawCell(buf: *Buffer, x: u16, y: u16, width: u16, text: []const u8, style: Style) void {
        assert(@as(u32, x) + width <= std.math.maxInt(u16));
        if (width == 0) return;

        const cut = UnicodeWidth.truncate(text, width);
        const shown = text[0..cut];
        buf.setString(x, y, shown, style);

        const used: u16 = @intCast(@min(UnicodeWidth.stringWidth(shown), width));
        var col: u16 = used;
        while (col < width) : (col += 1) {
            buf.set(x + col, y, .{ .char = ' ', .style = style });
        }
        assert(col == width);
    }

    /// Largest prefix length of `text` that is at most `max_len` bytes and ends on a UTF-8
    /// boundary.
    fn utf8Boundary(text: []const u8, max_len: usize) usize {
        if (text.len <= max_len) return text.len;
        var len = max_len;
        var steps: usize = 0;
        while (steps < utf8_continuation_max and len > 0 and
            (text[len] & 0xC0) == 0x80) : (steps += 1)
        {
            len -= 1;
        }
        assert(len <= max_len);
        assert(len < text.len);
        return len;
    }
};

test "RecordEditor default state" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    const editor = RecordEditor{
        .fields = &fields,
    };
    try std.testing.expectEqual(@as(usize, 0), editor.selected);
    try std.testing.expect(!editor.is_editing);
    try std.testing.expectEqual(@as(usize, 0), editor.edit_len);
}

test "RecordEditor with custom key_width" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    const editor = RecordEditor{
        .fields = &fields,
        .key_width = 30,
    };
    try std.testing.expectEqual(@as(u16, 30), editor.key_width);
}

test "moveDown — cursor moves to next field" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var editor = RecordEditor{
        .fields = &fields,
    };
    editor.moveDown();
    try std.testing.expectEqual(@as(usize, 1), editor.selected);
}

test "moveDown — cursor stays at last field" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var editor = RecordEditor{
        .fields = &fields,
        .selected = 1,
    };
    editor.moveDown();
    try std.testing.expectEqual(@as(usize, 1), editor.selected);
}

test "moveDown — on empty fields is safe" {
    var editor = RecordEditor{
        .fields = &.{},
    };
    editor.moveDown();
    try std.testing.expectEqual(@as(usize, 0), editor.selected);
}

test "moveUp — cursor moves to previous field" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var editor = RecordEditor{
        .fields = &fields,
        .selected = 1,
    };
    editor.moveUp();
    try std.testing.expectEqual(@as(usize, 0), editor.selected);
}

test "moveUp — cursor stays at first field" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var editor = RecordEditor{
        .fields = &fields,
        .selected = 0,
    };
    editor.moveUp();
    try std.testing.expectEqual(@as(usize, 0), editor.selected);
}

test "currentField — returns selected field" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    const editor = RecordEditor{
        .fields = &fields,
    };
    const field = editor.currentField();
    try std.testing.expect(field != null);
    try std.testing.expectEqualStrings("name", field.?.key);
    try std.testing.expectEqualStrings("Alice", field.?.value);
}

test "currentField — null when no fields" {
    var editor = RecordEditor{
        .fields = &.{},
    };
    const field = editor.currentField();
    try std.testing.expect(field == null);
}

test "startEdit — enters edit mode" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    try std.testing.expect(!editor.is_editing);
    editor.startEdit();
    try std.testing.expect(editor.is_editing);
}

test "startEdit — copies field value to edit buffer" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    const text = editor.editText();
    try std.testing.expectEqualStrings("Alice", text);
}

test "startEdit — on read-only field is no-op" {
    var fields = [_]Field{
        .{ .key = "id", .value = "12345", .is_editable = false },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    try std.testing.expect(!editor.is_editing);
}

test "insertChar — appends character to edit buffer" {
    var fields = [_]Field{
        .{ .key = "name", .value = "" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.insertChar('A');
    try std.testing.expectEqualStrings("A", editor.editText());
}

test "deleteChar — removes last character from edit buffer" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.deleteChar();
    try std.testing.expectEqualStrings("Alic", editor.editText());
}

test "confirmEdit — exits edit mode" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    try std.testing.expect(editor.is_editing);
    editor.confirmEdit();
    try std.testing.expect(!editor.is_editing);
}

test "cancelEdit — exits edit mode" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.cancelEdit();
    try std.testing.expect(!editor.is_editing);
}

test "editText — returns empty string when not editing" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    const text = editor.editText();
    try std.testing.expectEqualStrings("", text);
}

test "isValid — returns true when validate is null" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .validate = null,
    };
    editor.startEdit();
    const valid = editor.isValid();
    try std.testing.expect(valid);
}

test "isValid — calls validate function" {
    var fields = [_]Field{
        .{ .key = "email", .value = "test@example.com" },
    };
    var edit_buf = [_]u8{0} ** 256;

    const validator = struct {
        fn validate(_: []const u8, value: []const u8) ValidationResult {
            return if (std.mem.find(u8, value, "@") != null) .ok else .invalid;
        }
    }.validate;

    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .validate = &validator,
    };
    editor.startEdit();
    const valid = editor.isValid();
    try std.testing.expect(valid);
}

test "isValid — returns false for invalid values" {
    var fields = [_]Field{
        .{ .key = "email", .value = "invalid" },
    };
    var edit_buf = [_]u8{0} ** 256;

    const validator = struct {
        fn validate(_: []const u8, value: []const u8) ValidationResult {
            return if (std.mem.find(u8, value, "@") != null) .ok else .invalid;
        }
    }.validate;

    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .validate = &validator,
    };
    editor.startEdit();
    const valid = editor.isValid();
    try std.testing.expect(!valid);
}

test "read-only field — startEdit is no-op" {
    var fields = [_]Field{
        .{ .key = "id", .value = "12345", .is_editable = false },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    try std.testing.expect(!editor.is_editing);
}

test "read-only field — currentField shows is_editable flag" {
    var fields = [_]Field{
        .{ .key = "id", .value = "12345", .is_editable = false },
    };
    const editor = RecordEditor{
        .fields = &fields,
    };
    const field = editor.currentField();
    try std.testing.expect(field != null);
    try std.testing.expect(!field.?.is_editable);
}

test "render — zero area is safe" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 5 });
    try expectBlank(buf);
}

test "render — zero height is safe" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 0 });
    try expectBlank(buf);
}

test "render — empty fields is safe" {
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &.{},
        .edit_buffer = &edit_buf,
    };
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
    try expectBlank(buf);
}

test "withBlock — sets block wrapper" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    const block = Block{ .borders = .all, .title = "Editor" };
    var editor = RecordEditor{
        .fields = &fields,
    };
    editor = editor.withBlock(block);
    try std.testing.expect(editor.block != null);
    try std.testing.expectEqualStrings("Editor", editor.block.?.title.?);
}

test "withValidate — sets validation function" {
    var fields = [_]Field{
        .{ .key = "email", .value = "test@example.com" },
    };
    var edit_buf = [_]u8{0} ** 256;

    const validator = struct {
        fn validate(_: []const u8, value: []const u8) ValidationResult {
            return if (std.mem.find(u8, value, "@") != null) .ok else .invalid;
        }
    }.validate;

    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor = editor.withValidate(&validator);
    try std.testing.expect(editor.validate != null);
}

fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| {
        try std.testing.expectEqual(@as(u21, ' '), cell.char);
    }
}

fn expectRow(buf: Buffer, x: u16, y: u16, text: []const u8) !void {
    var iter = (try std.unicode.Utf8View.init(text)).iterator();
    var i: u16 = 0;
    while (iter.nextCodepoint()) |cp| : (i += 1) {
        try std.testing.expectEqual(cp, buf.getChar(x + i, y));
    }
}

test "render — exact key and value cells with padding and selection style" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30", .is_editable = false },
    };
    const editor = RecordEditor{ .fields = &fields, .key_width = 6 };
    var buf = try Buffer.init(std.testing.allocator, 12, 3);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 12, .height = 3 });

    try expectRow(buf, 0, 0, "name  Alice ");
    try expectRow(buf, 0, 1, "age   30    ");
    try expectRow(buf, 0, 2, "            ");
    try std.testing.expect(buf.getStyle(0, 0).reverse);
    try std.testing.expect(buf.getStyle(11, 0).reverse);
    try std.testing.expect(!buf.getStyle(0, 1).reverse);
    try std.testing.expectEqual(editor.readonly_style, buf.getStyle(8, 1));
}

test "render — wide-character key is clipped and padded by cells, not bytes" {
    var fields = [_]Field{
        .{ .key = "名前名", .value = "x" },
    };
    const editor = RecordEditor{ .fields = &fields, .key_width = 5 };
    var buf = try Buffer.init(std.testing.allocator, 8, 1);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 8, .height = 1 });

    // Two wide glyphs take cells 0 and 2 (the trailing cells stay untouched), cell 4 is padding.
    try std.testing.expectEqual(@as(u21, '名'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, '前'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, 'x'), buf.getChar(5, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(6, 0));
}

test "render — wide-character value fills its column without shifting" {
    var fields = [_]Field{
        .{ .key = "k", .value = "日本語" },
    };
    const editor = RecordEditor{ .fields = &fields, .key_width = 2 };
    var buf = try Buffer.init(std.testing.allocator, 6, 1);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 6, .height = 1 });

    try std.testing.expectEqual(@as(u21, 'k'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, '日'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, '本'), buf.getChar(4, 0));
}

test "render — far oversized area does not overflow u16" {
    var fields = [_]Field{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    const editor = (RecordEditor{ .fields = &fields }).withBlock(.{ .title = "T" });
    var buf = try Buffer.init(std.testing.allocator, 8, 4);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 65530, .y = 65530, .width = 65535, .height = 65535 });
    editor.render(&buf, Rect{ .x = 0, .y = 65534, .width = 8, .height = 65535 });
    editor.render(&buf, Rect{ .x = 65535, .y = 65535, .width = 1, .height = 1 });
    try expectBlank(buf);
}

test "render — fields do not overwrite the bottom border of a block" {
    var fields = [_]Field{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    const editor = (RecordEditor{ .fields = &fields, .key_width = 2 }).withBlock(.{});
    var buf = try Buffer.init(std.testing.allocator, 8, 3);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 8, .height = 3 });

    try std.testing.expectEqual(@as(u21, '└'), buf.getChar(0, 2));
    try std.testing.expectEqual(@as(u21, '┘'), buf.getChar(7, 2));
    try std.testing.expectEqual(@as(u21, 'a'), buf.getChar(1, 1));
    try std.testing.expectEqual(@as(u21, '1'), buf.getChar(3, 1));
}

test "render — selected field far below the viewport is scrolled into view" {
    var fields = [_]Field{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    const editor = RecordEditor{ .fields = &fields, .key_width = 2, .selected = 2 };
    var buf = try Buffer.init(std.testing.allocator, 6, 2);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 6, .height = 2 });

    try std.testing.expectEqual(@as(u21, 'b'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), buf.getChar(0, 1));
    try std.testing.expect(buf.getStyle(0, 1).reverse);
    try std.testing.expect(!buf.getStyle(0, 0).reverse);
}

test "render — selected index past the end does not panic" {
    var fields = [_]Field{
        .{ .key = "a", .value = "1" },
    };
    const editor = RecordEditor{ .fields = &fields, .selected = 99 };
    var buf = try Buffer.init(std.testing.allocator, 6, 2);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 6, .height = 2 });
    try std.testing.expectEqual(@as(u21, 'a'), buf.getChar(0, 0));
}

test "render — editing shows edit buffer in editing style, invalid in error style" {
    const Validator = struct {
        fn reject(_: []const u8, value: []const u8) ValidationResult {
            return if (value.len < 3) .invalid else .ok;
        }
    };
    var fields = [_]Field{
        .{ .key = "k", .value = "abcdef" },
    };
    var edit_buf = [_]u8{0} ** 16;
    var editor = RecordEditor{ .fields = &fields, .edit_buffer = &edit_buf, .key_width = 2 };
    editor.startEdit();
    editor.deleteChar();
    editor.deleteChar();
    editor.deleteChar();
    var buf = try Buffer.init(std.testing.allocator, 8, 1);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 8, .height = 1 });
    try expectRow(buf, 0, 0, "k abc   ");
    try std.testing.expectEqual(editor.editing_style, buf.getStyle(2, 0));

    editor.validate = Validator.reject;
    editor.deleteChar();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 8, .height = 1 });
    try expectRow(buf, 0, 0, "k ab    ");
    try std.testing.expectEqual(editor.error_style, buf.getStyle(2, 0));
}

test "deleteChar — removes a whole multibyte character" {
    var fields = [_]Field{
        .{ .key = "k", .value = "a日" },
    };
    var edit_buf = [_]u8{0} ** 16;
    var editor = RecordEditor{ .fields = &fields, .edit_buffer = &edit_buf };
    editor.startEdit();
    try std.testing.expectEqual(@as(usize, 4), editor.edit_len);
    editor.deleteChar();
    try std.testing.expectEqualStrings("a", editor.editText());
    editor.deleteChar();
    editor.deleteChar();
    try std.testing.expectEqual(@as(usize, 0), editor.edit_len);
}

test "startEdit — long multibyte value is cut on a character boundary" {
    var fields = [_]Field{
        .{ .key = "k", .value = "ab日本" },
    };
    var edit_buf = [_]u8{0} ** 4;
    var editor = RecordEditor{ .fields = &fields, .edit_buffer = &edit_buf };
    editor.startEdit();
    // Buffer holds 4 bytes: "ab" plus one byte of the 3-byte glyph; that partial glyph is dropped.
    try std.testing.expectEqualStrings("ab", editor.editText());
    try std.testing.expect(std.unicode.utf8ValidateSlice(editor.editText()));
}
