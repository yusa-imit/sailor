//! Form Widget — Multi-field input with validation and navigation
//!
//! Manages a collection of input fields with:
//! - Tab-based focus navigation (skip non-focusable fields)
//! - Custom validation callbacks
//! - Rendering with labels, values, and error messages
//! - No allocation required from caller (uses provided state arrays)

const std = @import("std");
const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;
const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const style_mod = @import("style.zig");
const Style = style_mod.Style;

/// Validation function type: takes field value, returns error message or null
pub const ValidateFn = *const fn ([]const u8) ?[]const u8;

/// Field state: value and validation error
pub const FieldState = struct {
    value: []const u8 = "",
    error_msg: ?[]const u8 = null,
};

/// Field definition: configuration and metadata
pub const FormField = struct {
    id: []const u8,
    label: []const u8,
    placeholder: []const u8 = "",
    required: bool = false,
    focusable: bool = true,
    validate: ?ValidateFn = null,
};

/// Form widget: manages field collection, focus, and rendering
pub const Form = struct {
    fields: []const FormField,
    states: []FieldState,
    focused_idx: usize = 0,
    label_width: u16 = 12,
    show_errors: bool = true,

    /// Advance focus to next focusable field (wrap around)
    pub fn focusNext(self: *Form) void {
        if (self.fields.len == 0) return;

        var attempts: usize = 0;
        const max_attempts = self.fields.len * 2;

        while (attempts < max_attempts) {
            self.focused_idx = (self.focused_idx + 1) % self.fields.len;
            if (self.fields[self.focused_idx].focusable) return;
            attempts += 1;
        }

        // All fields non-focusable or exhausted attempts: leave focused_idx in valid range
    }

    /// Retreat focus to previous focusable field (wrap around)
    pub fn focusPrev(self: *Form) void {
        if (self.fields.len == 0) return;

        var attempts: usize = 0;
        const max_attempts = self.fields.len * 2;

        while (attempts < max_attempts) {
            if (self.focused_idx == 0) {
                self.focused_idx = self.fields.len - 1;
            } else {
                self.focused_idx -= 1;
            }
            if (self.fields[self.focused_idx].focusable) return;
            attempts += 1;
        }

        // All fields non-focusable or exhausted attempts: leave focused_idx in valid range
    }

    /// Set focus to field with given id. Returns true if found, false otherwise
    pub fn focusField(self: *Form, id: []const u8) bool {
        for (self.fields, 0..) |field, i| {
            if (std.mem.eql(u8, field.id, id)) {
                self.focused_idx = i;
                return true;
            }
        }
        return false;
    }

    /// Get the ID of currently focused field
    pub fn getFocusedId(self: Form) ?[]const u8 {
        if (self.fields.len > 0) {
            return self.fields[self.focused_idx].id;
        }
        return null;
    }

    /// Check if a field is currently focused
    pub fn isFocused(self: Form, id: []const u8) bool {
        if (self.fields.len > 0) {
            return std.mem.eql(u8, self.fields[self.focused_idx].id, id);
        }
        return false;
    }

    /// Run validation on all fields. Returns true if all pass
    pub fn validateAll(self: *Form) bool {
        var all_valid = true;

        for (self.fields, 0..) |field, i| {
            if (field.required and self.states[i].value.len == 0) {
                // Required field is empty
                self.states[i].error_msg = "Field is required";
                all_valid = false;
            } else if (field.validate) |validator| {
                // Run custom validator
                self.states[i].error_msg = validator(self.states[i].value);
                if (self.states[i].error_msg != null) {
                    all_valid = false;
                }
            } else {
                // No validation for this field
                self.states[i].error_msg = null;
            }
        }

        return all_valid;
    }

    /// Check if all fields are currently valid (no error messages)
    pub fn isValid(self: Form) bool {
        for (self.states) |state| {
            if (state.error_msg != null) {
                return false;
            }
        }
        return true;
    }

    /// Render form to buffer within area
    pub fn render(self: Form, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var current_y = area.y;

        for (self.fields, 0..) |field, i| {
            if (current_y >= area.y + area.height) break;

            // Render label and value on same row
            var label_x: u16 = 0;
            for (field.label) |ch| {
                if (label_x >= area.x + area.width) break;
                if (label_x < self.label_width) {
                    buf.setString(area.x + label_x, current_y, &[_]u8{ch}, .{});
                    label_x += 1;
                }
            }

            // Render colon and space after label
            const colon_x = area.x + self.label_width;
            if (colon_x < area.x + area.width) {
                buf.setString(colon_x, current_y, ":", .{});
            }

            // Render value starting after ": "
            const value_x = area.x + self.label_width + 2;
            if (value_x < area.x + area.width) {
                const state = self.states[i];
                const display_value = if (state.value.len > 0) state.value else field.placeholder;
                const max_width = area.x + area.width - value_x;
                const width_to_write = @min(display_value.len, max_width);
                if (width_to_write > 0) {
                    buf.setString(value_x, current_y, display_value[0..width_to_write], .{});
                }
            }

            current_y += 1;

            // Render error message if present and show_errors is true
            if (self.show_errors and self.states[i].error_msg != null) {
                if (current_y >= area.y + area.height) break;

                const error_msg = self.states[i].error_msg.?;
                if (value_x < area.x + area.width) {
                    const max_width = area.x + area.width - value_x;
                    const width_to_write = @min(error_msg.len, max_width);
                    if (width_to_write > 0) {
                        buf.setString(value_x, current_y, error_msg[0..width_to_write], .{});
                    }
                }
                current_y += 1;
            }
        }
    }
};

// Tests
test "Form with single field initializes correctly" {
    var states = [_]FieldState{FieldState{}};
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .placeholder = "" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try std.testing.expectEqual(@as(usize, 1), form.fields.len);
    try std.testing.expectEqual(@as(usize, 1), form.states.len);
}

test "Form default focused_idx is zero" {
    var states = [_]FieldState{FieldState{}};
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try std.testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "Form default label_width is 12" {
    var states = [_]FieldState{FieldState{}};
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try std.testing.expectEqual(@as(u16, 12), form.label_width);
}

test "Form default show_errors is true" {
    var states = [_]FieldState{FieldState{}};
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try std.testing.expect(form.show_errors);
}

test "FieldState default value is empty string" {
    const state = FieldState{};
    try std.testing.expectEqual(@as(usize, 0), state.value.len);
}
