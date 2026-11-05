//! Form widget: composes labeled input fields with per-field validation.
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Span = @import("../style.zig").Span;
const Line = @import("../style.zig").Line;
const Block = @import("block.zig").Block;
const Input = @import("input.zig").Input;
const symbols = @import("../symbols.zig");
const assert = std.debug.assert;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
const validators = @import("../validators.zig");

/// Re-export validator types for convenience
pub const ValidationResult = validators.ValidationResult;
pub const Validator = validators.Validator;

/// Form field definition
pub const Field = struct {
    label: []const u8,
    value: []const u8,
    validator: ?Validator = null,
    is_password: bool = false,
    max_length: ?usize = null,
    cursor: usize = 0,
    validation_error: ?[]const u8 = null,
    /// Allocator used for value (null if value is static/not owned)
    value_allocator: ?std.mem.Allocator = null,

    /// Creates a new form field with the given label.
    pub fn init(label: []const u8) Field {
        return .{
            .label = label,
            .value = "",
        };
    }

    /// Free allocated value memory
    pub fn deinit(self: *Field) void {
        if (self.value_allocator) |allocator| {
            allocator.free(self.value);
            self.value_allocator = null;
        }
    }

    /// Returns a new field with the specified validator attached.
    pub fn withValidator(self: Field, validator: Validator) Field {
        var result = self;
        result.validator = validator;
        return result;
    }

    /// Returns a new field marked as a password field (value will be masked).
    pub fn withPassword(self: Field) Field {
        var result = self;
        result.is_password = true;
        return result;
    }

    /// Returns a new field with the specified maximum length constraint.
    pub fn withMaxLength(self: Field, max_length: usize) Field {
        var result = self;
        result.max_length = max_length;
        return result;
    }

    /// Validates the field value using the attached validator. Returns true if valid.
    pub fn validate(self: *Field) bool {
        if (self.validator) |validator| {
            const result = validator(self.value);
            switch (result) {
                .valid => {
                    self.validation_error = null;
                    return true;
                },
                .invalid => |msg| {
                    self.validation_error = msg;
                    return false;
                },
            }
        }
        self.validation_error = null;
        return true;
    }
};

/// Form submit action
pub const SubmitAction = enum {
    submit,
    cancel,
};

/// Form widget configuration
pub const Form = struct {
    fields: []Field,
    focused_field: usize = 0,
    block: ?Block = null,
    style: Style = .{},
    focused_style: Style = .{ .bold = true },
    error_style: Style = .{ .fg = .red },
    label_width: usize = 15,
    show_help: bool = true,

    /// Creates a new form with the given fields.
    pub fn init(fields: []Field) Form {
        return .{ .fields = fields };
    }

    /// Free all allocated field values
    pub fn deinit(self: *Form) void {
        for (self.fields) |*field| {
            field.deinit();
        }
    }

    /// Returns a new form with the specified border block.
    pub fn withBlock(self: Form, block: Block) Form {
        var result = self;
        result.block = block;
        return result;
    }

    /// Returns a new form with the specified normal field style.
    pub fn withStyle(self: Form, style: Style) Form {
        var result = self;
        result.style = style;
        return result;
    }

    /// Returns a new form with the specified focused field style.
    pub fn withFocusedStyle(self: Form, style: Style) Form {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Returns a new form with the specified error message style.
    pub fn withErrorStyle(self: Form, style: Style) Form {
        var result = self;
        result.error_style = style;
        return result;
    }

    /// Returns a new form with the specified label column width.
    pub fn withLabelWidth(self: Form, width: usize) Form {
        var result = self;
        result.label_width = width;
        return result;
    }

    /// Returns a new form with help text visibility set.
    pub fn withHelp(self: Form, show: bool) Form {
        var result = self;
        result.show_help = show;
        return result;
    }

    /// Get the current focused field
    pub fn focusedField(self: Form) ?*Field {
        if (self.focused_field < self.fields.len) {
            return &self.fields[self.focused_field];
        }
        return null;
    }

    /// Move focus to next field
    pub fn focusNext(self: *Form) void {
        if (self.fields.len == 0) return;
        self.focused_field = (self.focused_field + 1) % self.fields.len;
    }

    /// Move focus to previous field
    pub fn focusPrev(self: *Form) void {
        if (self.fields.len == 0) return;
        if (self.focused_field == 0) {
            self.focused_field = self.fields.len - 1;
        } else {
            self.focused_field -= 1;
        }
    }

    /// Validate all fields
    pub fn validate(self: *Form) bool {
        var all_valid = true;
        for (self.fields) |*field| {
            if (!field.validate()) {
                all_valid = false;
            }
        }
        return all_valid;
    }

    /// Insert a byte at the cursor position in the focused field. A cursor past the end of the
    /// value is clamped to the end first.
    pub fn insertChar(self: *Form, allocator: std.mem.Allocator, ch: u8) !void {
        const field = self.focusedField() orelse return;
        field.cursor = @min(field.cursor, field.value.len);
        assert(field.cursor <= field.value.len);

        if (field.max_length) |max| {
            if (field.value.len >= max) return;
        }

        const cursor = field.cursor;
        const old_len = field.value.len;
        const new_value = try allocator.alloc(u8, old_len + 1);
        @memcpy(new_value[0..cursor], field.value[0..cursor]);
        new_value[cursor] = ch;
        @memcpy(new_value[cursor + 1 ..], field.value[cursor..]);

        // Free old value if it was allocated
        if (field.value_allocator) |old_allocator| {
            old_allocator.free(field.value);
        }

        field.value = new_value;
        field.value_allocator = allocator;
        field.cursor = cursor + 1;
        assert(field.value.len == old_len + 1);
        assert(field.cursor <= field.value.len);
    }

    /// Delete the character before the cursor in the focused field. A multibyte UTF-8
    /// sequence is removed whole. A cursor past the end of the value is clamped first.
    pub fn deleteChar(self: *Form, allocator: std.mem.Allocator) !void {
        const field = self.focusedField() orelse return;
        field.cursor = @min(field.cursor, field.value.len);
        assert(field.cursor <= field.value.len);
        if (field.cursor == 0) return;

        const end = field.cursor;
        const start = prevBoundary(field.value, end);
        assert(start < end);
        const old_len = field.value.len;
        const new_value = try allocator.alloc(u8, old_len - (end - start));
        @memcpy(new_value[0..start], field.value[0..start]);
        @memcpy(new_value[start..], field.value[end..]);

        // Free old value if it was allocated
        if (field.value_allocator) |old_allocator| {
            old_allocator.free(field.value);
        }

        field.value = new_value;
        field.value_allocator = allocator;
        field.cursor = start;
        assert(field.value.len < old_len);
        assert(field.cursor <= field.value.len);
    }

    /// Move cursor left by one character in focused field
    pub fn cursorLeft(self: *Form) void {
        const field = self.focusedField() orelse return;
        field.cursor = @min(field.cursor, field.value.len);
        if (field.cursor == 0) return;
        field.cursor = prevBoundary(field.value, field.cursor);
        assert(field.cursor < field.value.len);
    }

    /// Move cursor right by one character in focused field
    pub fn cursorRight(self: *Form) void {
        const field = self.focusedField() orelse return;
        field.cursor = @min(field.cursor, field.value.len);
        if (field.cursor == field.value.len) return;
        field.cursor = nextBoundary(field.value, field.cursor);
        assert(field.cursor <= field.value.len);
    }

    /// Renders the form to the buffer in the given area.
    pub fn render(self: Form, buf: *Buffer, area: Rect) void {
        buf.fill(area, ' ', self.style);

        var render_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        // Reserve space for help text at bottom
        const help_height: u16 = if (self.show_help) 1 else 0;
        const fields_height: u32 = render_area.height -| help_height;
        assert(fields_height <= render_area.height);
        assert(help_height <= 1);

        var row: u32 = 0;
        for (self.fields, 0..) |field, i| {
            if (row >= fields_height) break;
            const is_focused = (i == self.focused_field);
            row += self.renderField(buf, render_area, row, fields_height, field, is_focused);
        }

        if (self.show_help) renderHelp(buf, render_area);
    }

    /// Renders one field at `row` inside `area`. Returns the number of rows consumed (1, or 2
    /// when a validation error line follows).
    fn renderField(
        self: Form,
        buf: *Buffer,
        area: Rect,
        row: u32,
        fields_height: u32,
        field: Field,
        is_focused: bool,
    ) u32 {
        assert(row < fields_height);
        assert(fields_height <= area.height);
        const field_style = if (is_focused) self.focused_style else self.style;
        const y: u32 = @as(u32, area.y) + row;
        const width: u32 = area.width;
        const label_w: u32 = @intCast(@min(self.label_width, std.math.maxInt(u16)));
        const value_x: u32 = @as(u32, area.x) + label_w + 2;
        const value_w: u32 = width -| (label_w + 2);

        _ = putText(buf, area.x, y, field.label, @min(label_w, width), field_style, false);
        if (label_w < width) setCell(buf, @as(u32, area.x) + label_w, y, ':', field_style);

        _ = putText(buf, value_x, y, field.value, value_w, field_style, field.is_password);
        if (is_focused) {
            const at = cursorCell(field.value, field.cursor, field.is_password);
            if (at.col < value_w) {
                var cursor_style = field_style;
                cursor_style.reverse = true;
                setCell(buf, value_x + at.col, y, at.ch, cursor_style);
            }
        }

        const err = field.validation_error orelse return 1;
        if (row + 1 >= fields_height) return 1;
        _ = putText(buf, value_x, y + 1, err, value_w, self.error_style, false);
        return 2;
    }
};

const help_text = "Tab: Next | Shift+Tab: Prev | Enter: Submit | Esc: Cancel";

/// Renders the help line on the last row of `area`.
fn renderHelp(buf: *Buffer, area: Rect) void {
    if (area.height == 0) return;
    const help_y: u32 = @as(u32, area.y) + area.height - 1;
    assert(help_y >= area.y);
    assert(help_text.len > 0);
    _ = putText(buf, area.x, help_y, help_text, area.width, .{ .fg = .bright_black }, false);
}

/// One decoded character: code point and its encoded byte length.
const Decoded = struct { cp: u21, len: usize };

/// Decodes the character at `text[i]`. Invalid or truncated sequences decode as one byte.
fn decodeAt(text: []const u8, i: usize) Decoded {
    assert(i < text.len);
    const byte = text[i];
    const seq_len: usize = std.unicode.utf8ByteSequenceLength(byte) catch return .{
        .cp = byte,
        .len = 1,
    };
    if (i + seq_len > text.len) return .{ .cp = byte, .len = 1 };
    const cp = std.unicode.utf8Decode(text[i .. i + seq_len]) catch return .{
        .cp = byte,
        .len = 1,
    };
    assert(seq_len >= 1);
    return .{ .cp = cp, .len = seq_len };
}

/// Display width in cells; masked (password) characters are always one cell.
fn cellWidth(cp: u21, masked: bool) u32 {
    if (masked) return 1;
    return UnicodeWidth.charWidth(cp);
}

/// Writes one cell, ignoring coordinates outside the u16 grid.
fn setCell(buf: *Buffer, x: u32, y: u32, cp: u21, style: Style) void {
    if (x > std.math.maxInt(u16) or y > std.math.maxInt(u16)) return;
    buf.set(@intCast(x), @intCast(y), .{ .char = cp, .style = style });
}

/// Writes `text` starting at (`x`, `y`), clipped to `max_cells` cells. Wide characters that do
/// not fit are dropped. Returns the number of cells used.
fn putText(
    buf: *Buffer,
    x: u32,
    y: u32,
    text: []const u8,
    max_cells: u32,
    style: Style,
    masked: bool,
) u32 {
    var col: u32 = 0;
    var i: usize = 0;
    // Bounded by text.len: every iteration advances `i` by at least one byte.
    while (i < text.len and col < max_cells) {
        const d = decodeAt(text, i);
        i += d.len;
        const w = cellWidth(d.cp, masked);
        if (w == 0) continue;
        if (col + w > max_cells) break;
        setCell(buf, x + col, y, if (masked) '*' else d.cp, style);
        col += w;
    }
    assert(col <= max_cells);
    assert(i <= text.len);
    return col;
}

/// Cell column and glyph under a byte-offset cursor.
const CursorCell = struct { col: u32, ch: u21 };

/// Locates the cell for byte offset `cursor` in `value`; at or past the end it is a blank.
fn cursorCell(value: []const u8, cursor: usize, masked: bool) CursorCell {
    var col: u32 = 0;
    var i: usize = 0;
    while (i < value.len) {
        const d = decodeAt(value, i);
        const w = cellWidth(d.cp, masked);
        if (cursor < i + d.len and w > 0) {
            return .{ .col = col, .ch = if (masked) '*' else d.cp };
        }
        col +|= w;
        i += d.len;
    }
    assert(i == value.len);
    return .{ .col = col, .ch = ' ' };
}

/// Start of the character that ends at byte offset `end` (`0 < end <= value.len`).
fn prevBoundary(value: []const u8, end: usize) usize {
    assert(end > 0);
    assert(end <= value.len);
    var start = end - 1;
    var steps: u8 = 0;
    const steps_max = 3;
    while (start > 0 and steps < steps_max and (value[start] & 0xC0) == 0x80) {
        start -= 1;
        steps += 1;
    }
    const seq_len = std.unicode.utf8ByteSequenceLength(value[start]) catch return end - 1;
    if (start + seq_len != end) return end - 1;
    return start;
}

/// End of the character that starts at byte offset `start` (`start < value.len`).
fn nextBoundary(value: []const u8, start: usize) usize {
    assert(start < value.len);
    const d = decodeAt(value, start);
    assert(d.len >= 1);
    return start + d.len;
}

// Tests

test "Form: init" {
    var fields = [_]Field{
        Field.init("Name"),
        Field.init("Email"),
    };

    const form = Form.init(&fields);
    try std.testing.expectEqual(2, form.fields.len);
    try std.testing.expectEqual(0, form.focused_field);
}

test "Form: focus navigation" {
    var fields = [_]Field{
        Field.init("Field 1"),
        Field.init("Field 2"),
        Field.init("Field 3"),
    };

    var form = Form.init(&fields);

    try std.testing.expectEqual(0, form.focused_field);

    form.focusNext();
    try std.testing.expectEqual(1, form.focused_field);

    form.focusNext();
    try std.testing.expectEqual(2, form.focused_field);

    form.focusNext(); // wraps around
    try std.testing.expectEqual(0, form.focused_field);

    form.focusPrev();
    try std.testing.expectEqual(2, form.focused_field);

    form.focusPrev();
    try std.testing.expectEqual(1, form.focused_field);
}

test "Form: focusedField" {
    var fields = [_]Field{
        Field.init("Field 1"),
        Field.init("Field 2"),
    };

    var form = Form.init(&fields);

    const field1 = form.focusedField();
    try std.testing.expect(field1 != null);
    try std.testing.expectEqualStrings("Field 1", field1.?.label);

    form.focusNext();
    const field2 = form.focusedField();
    try std.testing.expect(field2 != null);
    try std.testing.expectEqualStrings("Field 2", field2.?.label);
}

test "Form: validation" {
    var fields = [_]Field{
        Field.init("Name").withValidator(validators.notEmpty),
        Field.init("Email").withValidator(validators.email),
    };

    var form = Form.init(&fields);

    // Initially invalid (empty)
    try std.testing.expect(!form.validate());

    // Set valid values
    fields[0].value = "John";
    fields[1].value = "john@example.com";

    try std.testing.expect(form.validate());
    try std.testing.expect(fields[0].validation_error == null);
    try std.testing.expect(fields[1].validation_error == null);
}

test "Form: render basic" {
    var fields = [_]Field{
        Field.init("Name"),
        Field.init("Email"),
    };

    const form = Form.init(&fields);

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    form.render(&buf, area);

    // Check that labels are rendered
    const name_cell = buf.getConst(0, 0).?;
    try std.testing.expectEqual('N', name_cell.char);

    const email_cell = buf.getConst(0, 1).?;
    try std.testing.expectEqual('E', email_cell.char);
}

test "Form: render with block" {
    var fields = [_]Field{
        Field.init("Username"),
    };

    const block = (Block{}).withTitle("Login", .top_left);
    const form = Form.init(&fields).withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    form.render(&buf, area);

    // Check block border
    const top_left = buf.getConst(0, 0).?;
    try std.testing.expectEqual(@as(u21, '┌'), top_left.char);
}

test "Field: withValidator" {
    var field = Field.init("Email").withValidator(validators.email);

    field.value = "invalid";
    try std.testing.expect(!field.validate());
    try std.testing.expect(field.validation_error != null);

    field.value = "valid@example.com";
    try std.testing.expect(field.validate());
    try std.testing.expect(field.validation_error == null);
}

test "Field: withPassword" {
    const field = Field.init("Password").withPassword();
    try std.testing.expect(field.is_password);
}

test "Field: withMaxLength" {
    const field = Field.init("Code").withMaxLength(6);
    try std.testing.expectEqual(6, field.max_length.?);
}

// Edge Case Tests

test "Form: focusNext on empty form" {
    var fields = [_]Field{};
    var form = Form.init(&fields);

    // Should not crash or change focused_field
    const initial_focus = form.focused_field;
    form.focusNext();
    try std.testing.expectEqual(initial_focus, form.focused_field);
}

test "Form: focusPrev on empty form" {
    var fields = [_]Field{};
    var form = Form.init(&fields);

    const initial_focus = form.focused_field;
    form.focusPrev();
    try std.testing.expectEqual(initial_focus, form.focused_field);
}

test "Form: focusedField on empty form" {
    var fields = [_]Field{};
    const form = Form.init(&fields);

    const field = form.focusedField();
    try std.testing.expect(field == null);
}

test "Form: validate on empty form" {
    var fields = [_]Field{};
    var form = Form.init(&fields);

    // Empty form should be considered valid
    try std.testing.expect(form.validate());
}

test "Form: focusNext on single field stays at index 0" {
    var fields = [_]Field{Field.init("Only")};
    var form = Form.init(&fields);

    try std.testing.expectEqual(0, form.focused_field);
    form.focusNext();
    try std.testing.expectEqual(0, form.focused_field);
}

test "Form: focusPrev on single field stays at index 0" {
    var fields = [_]Field{Field.init("Only")};
    var form = Form.init(&fields);

    try std.testing.expectEqual(0, form.focused_field);
    form.focusPrev();
    try std.testing.expectEqual(0, form.focused_field);
}

test "Form: insertChar at start of value" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    defer form.deinit();

    fields[0].value = "ohn";
    fields[0].cursor = 0;

    try form.insertChar(std.testing.allocator, 'J');
    try std.testing.expectEqualStrings("John", fields[0].value);
    try std.testing.expectEqual(1, fields[0].cursor);
}

test "Form: insertChar at end of value" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    defer form.deinit();

    fields[0].value = "Joh";
    fields[0].cursor = 3;

    try form.insertChar(std.testing.allocator, 'n');
    try std.testing.expectEqualStrings("John", fields[0].value);
    try std.testing.expectEqual(4, fields[0].cursor);
}

test "Form: insertChar in middle of value" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    defer form.deinit();

    fields[0].value = "Jon";
    fields[0].cursor = 2;

    try form.insertChar(std.testing.allocator, 'h');
    try std.testing.expectEqualStrings("John", fields[0].value);
    try std.testing.expectEqual(3, fields[0].cursor);
}

test "Form: insertChar when max_length reached" {
    var fields = [_]Field{Field.init("Code").withMaxLength(4)};
    var form = Form.init(&fields);
    fields[0].value = "1234";
    fields[0].cursor = 4;

    try form.insertChar(std.testing.allocator, '5');
    // Should not insert
    try std.testing.expectEqualStrings("1234", fields[0].value);
    try std.testing.expectEqual(4, fields[0].cursor);
}

test "Form: insertChar when max_length exactly at limit" {
    var fields = [_]Field{Field.init("Code").withMaxLength(3)};
    var form = Form.init(&fields);
    fields[0].value = "123";
    fields[0].cursor = 3;

    try form.insertChar(std.testing.allocator, '4');
    // Should not insert
    try std.testing.expectEqualStrings("123", fields[0].value);
}

test "Form: insertChar on empty form" {
    var fields = [_]Field{};
    var form = Form.init(&fields);

    // Should not crash
    try form.insertChar(std.testing.allocator, 'x');
}

test "Form: deleteChar at start does nothing" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    fields[0].value = "John";
    fields[0].cursor = 0;

    try form.deleteChar(std.testing.allocator);
    try std.testing.expectEqualStrings("John", fields[0].value);
    try std.testing.expectEqual(0, fields[0].cursor);
}

test "Form: deleteChar at end" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    defer form.deinit();

    fields[0].value = "John";
    fields[0].cursor = 4;

    try form.deleteChar(std.testing.allocator);
    try std.testing.expectEqualStrings("Joh", fields[0].value);
    try std.testing.expectEqual(3, fields[0].cursor);
}

test "Form: deleteChar from empty string" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    fields[0].value = "";
    fields[0].cursor = 0;

    try form.deleteChar(std.testing.allocator);
    try std.testing.expectEqualStrings("", fields[0].value);
}

test "Form: deleteChar on empty form" {
    var fields = [_]Field{};
    var form = Form.init(&fields);

    // Should not crash
    try form.deleteChar(std.testing.allocator);
}

test "Form: cursorLeft at start stays at 0" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    fields[0].value = "John";
    fields[0].cursor = 0;

    form.cursorLeft();
    try std.testing.expectEqual(0, fields[0].cursor);
}

test "Form: cursorRight at end stays at value.len" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    fields[0].value = "John";
    fields[0].cursor = 4;

    form.cursorRight();
    try std.testing.expectEqual(4, fields[0].cursor);
}

test "Form: cursor movement on empty form" {
    var fields = [_]Field{};
    var form = Form.init(&fields);

    // Should not crash
    form.cursorLeft();
    form.cursorRight();
}

test "Field: validate without validator returns true" {
    var field = Field.init("Optional");
    field.value = "anything";

    try std.testing.expect(field.validate());
    try std.testing.expect(field.validation_error == null);
}

test "Form: validate with mixed valid and invalid fields" {
    var fields = [_]Field{
        Field.init("Name").withValidator(validators.notEmpty),
        Field.init("Email").withValidator(validators.email),
    };
    var form = Form.init(&fields);

    fields[0].value = "John"; // valid
    fields[1].value = "invalid-email"; // invalid

    try std.testing.expect(!form.validate());
    try std.testing.expect(fields[0].validation_error == null);
    try std.testing.expect(fields[1].validation_error != null);
}

test "Form: re-validate after fixing error" {
    var field = Field.init("Email").withValidator(validators.email);

    field.value = "invalid";
    try std.testing.expect(!field.validate());
    try std.testing.expect(field.validation_error != null);

    field.value = "valid@example.com";
    try std.testing.expect(field.validate());
    try std.testing.expect(field.validation_error == null);
}

test "Form: render with zero-width area" {
    var fields = [_]Field{Field.init("Name")};
    const form = Form.init(&fields);

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    form.render(&buf, area);
    // Should not crash
}

test "Form: render with zero-height area" {
    var fields = [_]Field{Field.init("Name")};
    const form = Form.init(&fields);

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 0 };
    form.render(&buf, area);
    // Should not crash
}

test "Form: render with label longer than label_width" {
    var fields = [_]Field{Field.init("Very Long Label Name")};
    const form = Form.init(&fields).withLabelWidth(5);

    var buf = try Buffer.init(std.testing.allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    form.render(&buf, area);

    // Only first 5 characters should be visible
    try std.testing.expectEqual('V', buf.getConst(0, 0).?.char);
    try std.testing.expectEqual('e', buf.getConst(1, 0).?.char);
    try std.testing.expectEqual('r', buf.getConst(2, 0).?.char);
    try std.testing.expectEqual('y', buf.getConst(3, 0).?.char);
    try std.testing.expectEqual(' ', buf.getConst(4, 0).?.char);
    try std.testing.expectEqual(':', buf.getConst(5, 0).?.char);
}

test "Form: render with value longer than available width" {
    var fields = [_]Field{Field.init("Name")};
    fields[0].value = "Very Long Value That Should Be Truncated";
    const form = Form.init(&fields).withLabelWidth(5);

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    form.render(&buf, area);

    // Value should be truncated to fit
    const value_start_x = 7; // label_width + 2
    const visible_width = 20 - 7;

    for (0..visible_width) |i| {
        const cell = buf.getConst(@intCast(value_start_x + i), 0).?;
        try std.testing.expect(cell.char != 0);
    }
}

test "Form: render with error message longer than available width" {
    var fields = [_]Field{Field.init("Email").withValidator(validators.email)};
    fields[0].value = "invalid";
    var form = Form.init(&fields).withLabelWidth(5);

    _ = form.validate(); // Generate error

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    form.render(&buf, area);

    // Error should be rendered on second line, truncated if needed
    try std.testing.expect(fields[0].validation_error != null);
}

test "Form: render password field with masked characters" {
    var fields = [_]Field{Field.init("Password").withPassword()};
    fields[0].value = "secret123";
    const form = Form.init(&fields).withLabelWidth(10);

    var buf = try Buffer.init(std.testing.allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    form.render(&buf, area);

    // All password characters should be masked as '*'
    const value_start_x = 12; // label_width + 2
    for (0..9) |i| {
        const cell = buf.getConst(@intCast(value_start_x + i), 0).?;
        try std.testing.expectEqual('*', cell.char);
    }
}

test "Form: render password field with cursor shows masked character" {
    var fields = [_]Field{Field.init("Pass").withPassword()};
    fields[0].value = "secret";
    fields[0].cursor = 3;
    var form = Form.init(&fields).withLabelWidth(5);

    var buf = try Buffer.init(std.testing.allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    form.render(&buf, area);

    // Cursor position should show '*' not actual character
    const cursor_x = 7 + 3; // label_width + 2 + cursor
    const cursor_cell = buf.getConst(@intCast(cursor_x), 0).?;
    try std.testing.expectEqual('*', cursor_cell.char);
    try std.testing.expect(cursor_cell.style.reverse);
}

// Memory Leak Tests

test "Form: insertChar frees old value" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);

    // Insert multiple characters - each should free the previous allocation
    try form.insertChar(std.testing.allocator, 'J');
    try form.insertChar(std.testing.allocator, 'o');
    try form.insertChar(std.testing.allocator, 'h');
    try form.insertChar(std.testing.allocator, 'n');

    try std.testing.expectEqualStrings("John", fields[0].value);

    // Clean up
    form.deinit();
}

test "Form: deleteChar frees old value" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);

    // Build up a value
    try form.insertChar(std.testing.allocator, 'J');
    try form.insertChar(std.testing.allocator, 'o');
    try form.insertChar(std.testing.allocator, 'h');
    try form.insertChar(std.testing.allocator, 'n');

    // Delete characters - each should free the previous allocation
    try form.deleteChar(std.testing.allocator);
    try form.deleteChar(std.testing.allocator);

    try std.testing.expectEqualStrings("Jo", fields[0].value);

    // Clean up
    form.deinit();
}

test "Form: deinit frees all field values" {
    var fields = [_]Field{
        Field.init("Name"),
        Field.init("Email"),
        Field.init("Phone"),
    };
    var form = Form.init(&fields);

    // Modify all fields
    try form.insertChar(std.testing.allocator, 'A');
    form.focusNext();
    try form.insertChar(std.testing.allocator, 'B');
    form.focusNext();
    try form.insertChar(std.testing.allocator, 'C');

    // Deinit should free all allocated values
    form.deinit();
}

test "Form: multiple insert/delete cycles do not leak" {
    var fields = [_]Field{Field.init("Test")};
    var form = Form.init(&fields);

    // Simulate typing and deleting multiple times
    for (0..100) |_| {
        try form.insertChar(std.testing.allocator, 'x');
        try form.deleteChar(std.testing.allocator);
    }

    // Should have no leaks
    form.deinit();
}

test "Form: mixed insertChar and deleteChar do not leak" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);

    // Type a word
    try form.insertChar(std.testing.allocator, 'H');
    try form.insertChar(std.testing.allocator, 'e');
    try form.insertChar(std.testing.allocator, 'l');
    try form.insertChar(std.testing.allocator, 'l');
    try form.insertChar(std.testing.allocator, 'o');

    // Delete some
    try form.deleteChar(std.testing.allocator);
    try form.deleteChar(std.testing.allocator);

    // Type more
    try form.insertChar(std.testing.allocator, 'p');

    try std.testing.expectEqualStrings("Help", fields[0].value);

    form.deinit();
}

test "Form: insertChar at max_length does not leak" {
    var fields = [_]Field{Field.init("Code").withMaxLength(4)};
    var form = Form.init(&fields);

    // Fill to max
    try form.insertChar(std.testing.allocator, '1');
    try form.insertChar(std.testing.allocator, '2');
    try form.insertChar(std.testing.allocator, '3');
    try form.insertChar(std.testing.allocator, '4');

    // Try to exceed max - should not allocate or leak
    try form.insertChar(std.testing.allocator, '5');
    try form.insertChar(std.testing.allocator, '6');

    try std.testing.expectEqualStrings("1234", fields[0].value);

    form.deinit();
}

test "Field: deinit on static value does nothing" {
    var field = Field.init("Name");
    field.value = "static"; // Static string, no allocator

    // Should not crash
    field.deinit();
}

// Regression tests (#75)

test "Form: render multibyte label and value advance by cells" {
    var fields = [_]Field{Field.init("日本")};
    fields[0].value = "é世x";
    fields[0].cursor = 0;
    const form = Form.init(&fields).withLabelWidth(6).withHelp(false);

    var buf = try Buffer.init(std.testing.allocator, 30, 3);
    defer buf.deinit();

    form.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 3 });
    try std.testing.expectEqual(@as(u21, '日'), buf.getConst(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, '本'), buf.getConst(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, ':'), buf.getConst(6, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'é'), buf.getConst(8, 0).?.char);
    try std.testing.expectEqual(@as(u21, '世'), buf.getConst(9, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'x'), buf.getConst(11, 0).?.char);
}

test "Form: password mask is one star per character not per byte" {
    var fields = [_]Field{Field.init("P").withPassword()};
    fields[0].value = "世é";
    fields[0].cursor = 5;
    const form = Form.init(&fields).withLabelWidth(2).withHelp(false);

    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    form.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 2 });
    try std.testing.expectEqual(@as(u21, '*'), buf.getConst(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, '*'), buf.getConst(5, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(6, 0).?.char);
    try std.testing.expect(buf.getConst(6, 0).?.style.reverse);
}

test "Form: cursor on multibyte value lands on its cell column" {
    var fields = [_]Field{Field.init("N")};
    fields[0].value = "世界";
    fields[0].cursor = 3;
    const form = Form.init(&fields).withLabelWidth(1).withHelp(false);

    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    form.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 2 });
    try std.testing.expectEqual(@as(u21, '界'), buf.getConst(5, 0).?.char);
    try std.testing.expect(buf.getConst(5, 0).?.style.reverse);
    try std.testing.expect(!buf.getConst(3, 0).?.style.reverse);
}

test "Form: cursor beyond value width stays inside the value column" {
    var fields = [_]Field{Field.init("N")};
    fields[0].value = "abcdefghij";
    fields[0].cursor = 10;
    const form = Form.init(&fields).withLabelWidth(1).withHelp(false);

    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    // Area is 8 wide: value column is x = 3..7; the cursor cell would be x = 13.
    form.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(13, 0).?.char);
    try std.testing.expect(!buf.getConst(13, 0).?.style.reverse);
    try std.testing.expectEqual(@as(u21, 'e'), buf.getConst(7, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(8, 0).?.char);
}

test "Form: render with far-away and oversized area does not overflow" {
    var fields = [_]Field{Field.init("Name").withValidator(validators.notEmpty)};
    var form = Form.init(&fields).withLabelWidth(std.math.maxInt(usize));
    _ = form.validate();

    var buf = try Buffer.init(std.testing.allocator, 10, 4);
    defer buf.deinit();

    const max = std.math.maxInt(u16);
    form.render(&buf, .{ .x = max - 3, .y = max - 3, .width = max, .height = max });
    form.render(&buf, .{ .x = 0, .y = 0, .width = max, .height = max });
    try std.testing.expectEqual(@as(u21, 'N'), buf.getConst(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(9, 0).?.char);
}

test "Form: insertChar and deleteChar clamp a cursor past the end" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    defer form.deinit();

    fields[0].value = "ab";
    fields[0].cursor = 99;
    try form.insertChar(std.testing.allocator, 'c');
    try std.testing.expectEqualStrings("abc", fields[0].value);
    try std.testing.expectEqual(3, fields[0].cursor);

    fields[0].cursor = 99;
    try form.deleteChar(std.testing.allocator);
    try std.testing.expectEqualStrings("ab", fields[0].value);
    try std.testing.expectEqual(2, fields[0].cursor);
}

test "Form: deleteChar removes a whole multibyte character" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    defer form.deinit();

    fields[0].value = "a世é";
    fields[0].cursor = 6;
    try form.deleteChar(std.testing.allocator);
    try std.testing.expectEqualStrings("a世", fields[0].value);
    try std.testing.expectEqual(4, fields[0].cursor);

    try form.deleteChar(std.testing.allocator);
    try std.testing.expectEqualStrings("a", fields[0].value);
    try std.testing.expectEqual(1, fields[0].cursor);
}

test "Form: cursorLeft and cursorRight step whole characters" {
    var fields = [_]Field{Field.init("Name")};
    var form = Form.init(&fields);
    fields[0].value = "a世b";
    fields[0].cursor = 0;

    form.cursorRight();
    try std.testing.expectEqual(1, fields[0].cursor);
    form.cursorRight();
    try std.testing.expectEqual(4, fields[0].cursor);
    form.cursorRight();
    form.cursorRight();
    try std.testing.expectEqual(5, fields[0].cursor);
    form.cursorLeft();
    form.cursorLeft();
    try std.testing.expectEqual(1, fields[0].cursor);
    form.cursorLeft();
    form.cursorLeft();
    try std.testing.expectEqual(0, fields[0].cursor);
}

test "Form: error line is clipped to the value column" {
    var fields = [_]Field{Field.init("E")};
    fields[0].validation_error = "bad-value-too-long";
    const form = Form.init(&fields).withLabelWidth(1).withHelp(false);

    var buf = try Buffer.init(std.testing.allocator, 12, 3);
    defer buf.deinit();

    form.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 3 });
    try std.testing.expectEqual(@as(u21, 'b'), buf.getConst(3, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'v'), buf.getConst(7, 1).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(8, 1).?.char);
}
