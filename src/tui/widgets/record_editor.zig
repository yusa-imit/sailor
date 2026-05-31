//! RecordEditor — inline record (key-value) field editing widget (v2.17.0)
//!
//! Renders a list of key-value pairs with navigation, inline editing,
//! and optional validation.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

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
        const copy_len = @min(field.value.len, self.edit_buffer.len);
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
        if (self.edit_len > 0) {
            self.edit_len -= 1;
        }
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

    /// Render the record editor to buffer
    pub fn render(self: RecordEditor, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        if (self.fields.len == 0) return;

        var y_pos = inner.y;

        for (self.fields, 0..) |field, idx| {
            if (y_pos >= area.y + area.height) break;

            const is_selected = (idx == self.selected);

            // Determine style
            var field_style = self.normal_style;
            var value_style = self.normal_style;

            if (!field.is_editable) {
                value_style = self.readonly_style;
            }

            if (is_selected) {
                field_style = self.selected_style;
                value_style = self.selected_style;
            }

            if (self.is_editing and is_selected) {
                if (self.isValid()) {
                    field_style = self.editing_style;
                    value_style = self.editing_style;
                } else {
                    field_style = self.error_style;
                    value_style = self.error_style;
                }
            }

            self.renderField(buf, inner, y_pos, field, field_style, value_style, is_selected and self.is_editing);
            y_pos += 1;
        }
    }

    fn renderField(self: RecordEditor, buf: *Buffer, area: Rect, y: u16, field: Field, key_style: Style, value_style: Style, is_editing: bool) void {
        var x_pos = area.x;

        // Render key
        const key_width = @min(self.key_width, area.width);
        const key_len = @min(field.key.len, key_width);
        buf.setString(x_pos, y, field.key[0..key_len], key_style);

        // Pad key area
        if (key_len < key_width) {
            for (key_len..key_width) |i| {
                buf.set(x_pos + @as(u16, @intCast(i)), y, .{
                    .char = ' ',
                    .style = key_style,
                });
            }
        }

        x_pos +|= key_width;

        // Render value
        var value_text: []const u8 = undefined;
        if (is_editing) {
            value_text = self.editText();
        } else {
            value_text = field.value;
        }

        const value_width = if (area.width > key_width) area.width - key_width else 0;
        if (value_width > 0) {
            const value_len = @min(value_text.len, value_width);
            buf.setString(x_pos, y, value_text[0..value_len], value_style);

            // Pad value area
            if (value_len < value_width) {
                for (value_len..value_width) |i| {
                    buf.set(x_pos + @as(u16, @intCast(i)), y, .{
                        .char = ' ',
                        .style = value_style,
                    });
                }
            }
        }
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
            return if (std.mem.indexOf(u8, value, "@") != null) .ok else .invalid;
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
            return if (std.mem.indexOf(u8, value, "@") != null) .ok else .invalid;
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
    try std.testing.expectEqualStrings("Editor", editor.block.?.title);
}

test "withValidate — sets validation function" {
    var fields = [_]Field{
        .{ .key = "email", .value = "test@example.com" },
    };
    var edit_buf = [_]u8{0} ** 256;

    const validator = struct {
        fn validate(_: []const u8, value: []const u8) ValidationResult {
            return if (std.mem.indexOf(u8, value, "@") != null) .ok else .invalid;
        }
    }.validate;

    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor = editor.withValidate(&validator);
    try std.testing.expect(editor.validate != null);
}
