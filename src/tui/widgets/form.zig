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

    pub fn init(label: []const u8) Field {
        return .{
            .label = label,
            .value = "",
        };
    }

    pub fn withValidator(self: Field, validator: Validator) Field {
        var result = self;
        result.validator = validator;
        return result;
    }

    pub fn withPassword(self: Field) Field {
        var result = self;
        result.is_password = true;
        return result;
    }

    pub fn withMaxLength(self: Field, max_length: usize) Field {
        var result = self;
        result.max_length = max_length;
        return result;
    }

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

    pub fn init(fields: []Field) Form {
        return .{ .fields = fields };
    }

    pub fn withBlock(self: Form, block: Block) Form {
        var result = self;
        result.block = block;
        return result;
    }

    pub fn withStyle(self: Form, style: Style) Form {
        var result = self;
        result.style = style;
        return result;
    }

    pub fn withFocusedStyle(self: Form, style: Style) Form {
        var result = self;
        result.focused_style = style;
        return result;
    }

    pub fn withErrorStyle(self: Form, style: Style) Form {
        var result = self;
        result.error_style = style;
        return result;
    }

    pub fn withLabelWidth(self: Form, width: usize) Form {
        var result = self;
        result.label_width = width;
        return result;
    }

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

    /// Insert character at cursor position in focused field
    pub fn insertChar(self: *Form, allocator: std.mem.Allocator, ch: u8) !void {
        if (self.focusedField()) |field| {
            // Check max length
            if (field.max_length) |max| {
                if (field.value.len >= max) return;
            }

            // Create new value with inserted character
            var new_value = try allocator.alloc(u8, field.value.len + 1);
            if (field.cursor > 0) {
                @memcpy(new_value[0..field.cursor], field.value[0..field.cursor]);
            }
            new_value[field.cursor] = ch;
            if (field.cursor < field.value.len) {
                @memcpy(new_value[field.cursor + 1 ..], field.value[field.cursor..]);
            }

            field.value = new_value;
            field.cursor += 1;
        }
    }

    /// Delete character before cursor in focused field
    pub fn deleteChar(self: *Form, allocator: std.mem.Allocator) !void {
        if (self.focusedField()) |field| {
            if (field.cursor == 0 or field.value.len == 0) return;

            // Create new value with deleted character
            var new_value = try allocator.alloc(u8, field.value.len - 1);
            if (field.cursor > 1) {
                @memcpy(new_value[0 .. field.cursor - 1], field.value[0 .. field.cursor - 1]);
            }
            if (field.cursor < field.value.len) {
                @memcpy(new_value[field.cursor - 1 ..], field.value[field.cursor..]);
            }

            field.value = new_value;
            field.cursor -= 1;
        }
    }

    /// Move cursor left in focused field
    pub fn cursorLeft(self: *Form) void {
        if (self.focusedField()) |field| {
            if (field.cursor > 0) {
                field.cursor -= 1;
            }
        }
    }

    /// Move cursor right in focused field
    pub fn cursorRight(self: *Form) void {
        if (self.focusedField()) |field| {
            if (field.cursor < field.value.len) {
                field.cursor += 1;
            }
        }
    }

    pub fn render(self: Form, buf: *Buffer, area: Rect) void {
        // Clear area with style
        for (0..area.height) |y| {
            for (0..area.width) |x| {
                buf.set(@intCast(area.x + x), @intCast(area.y + y), .{
                    .char = ' ',
                    .style = self.style,
                });
            }
        }

        var render_area = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        // Reserve space for help text at bottom
        const help_height: u16 = if (self.show_help) 1 else 0;
        const fields_height = if (render_area.height > help_height)
            render_area.height - help_height
        else
            0;

        // Render fields
        var y: u16 = 0;
        for (self.fields, 0..) |field, i| {
            if (y >= fields_height) break;

            const is_focused = (i == self.focused_field);
            const field_style = if (is_focused) self.focused_style else self.style;

            // Render label
            const label_x = render_area.x;
            const label_y = render_area.y + y;
            for (field.label, 0..) |ch, x| {
                if (x >= self.label_width) break;
                buf.set(@intCast(label_x + x), label_y, .{
                    .char = @intCast(ch),
                    .style = field_style,
                });
            }

            // Render separator
            if (self.label_width < render_area.width) {
                buf.set(@intCast(label_x + self.label_width), label_y, .{
                    .char = ':',
                    .style = field_style,
                });
            }

            // Render value
            const value_x = label_x + self.label_width + 2;
            if (value_x < label_x + render_area.width) {
                const value_width = render_area.width -| (self.label_width + 2);

                for (field.value, 0..) |ch, x| {
                    if (x >= value_width) break;
                    const display_char = if (field.is_password) '*' else ch;
                    buf.set(@intCast(value_x + x), label_y, .{
                        .char = @intCast(display_char),
                        .style = field_style,
                    });
                }

                // Render cursor if focused
                if (is_focused and field.cursor <= value_width) {
                    const cursor_char = if (field.cursor < field.value.len)
                        if (field.is_password) '*' else @as(u21, @intCast(field.value[field.cursor]))
                    else
                        ' ';
                    var cursor_style = field_style;
                    cursor_style.reverse = true;
                    buf.set(@intCast(value_x + field.cursor), label_y, .{
                        .char = cursor_char,
                        .style = cursor_style,
                    });
                }
            }

            y += 1;

            // Render validation error if present
            if (field.validation_error) |err| {
                if (y < fields_height) {
                    const err_x = value_x;
                    const err_y = render_area.y + y;
                    for (err, 0..) |ch, x| {
                        if (x >= render_area.width -| (self.label_width + 2)) break;
                        buf.set(@intCast(err_x + x), err_y, .{
                            .char = @intCast(ch),
                            .style = self.error_style,
                        });
                    }
                    y += 1;
                }
            }
        }

        // Render help text
        if (self.show_help and render_area.height > 0) {
            const help_y = render_area.y + render_area.height - 1;
            const help_text = "Tab: Next | Shift+Tab: Prev | Enter: Submit | Esc: Cancel";
            const help_style = Style{ .fg = .bright_black };
            for (help_text, 0..) |ch, x| {
                if (x >= render_area.width) break;
                buf.set(@intCast(render_area.x + x), help_y, .{
                    .char = @intCast(ch),
                    .style = help_style,
                });
            }
        }
    }
};

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
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    form.render(&buf, area);

    // Check that labels are rendered
    const name_cell = buf.get(0, 0);
    try std.testing.expectEqual('N', name_cell.char);

    const email_cell = buf.get(0, 1);
    try std.testing.expectEqual('E', email_cell.char);
}

test "Form: render with block" {
    var fields = [_]Field{
        Field.init("Username"),
    };

    const block = Block.init().withTitle("Login");
    const form = Form.init(&fields).withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    form.render(&buf, area);

    // Check block border
    const top_left = buf.get(0, 0);
    try std.testing.expectEqual(symbols.border.plain.top_left, top_left.char);
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
