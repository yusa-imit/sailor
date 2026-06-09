//! Form Widget Tests — v2.23.0
//!
//! Tests Form widget for multi-field input with navigation, validation, and rendering.
//! Form manages field state, handles focus navigation between fields, and renders labels
//! with input areas and validation errors.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;

// Import the form module which will be implemented at src/tui/form.zig
const form_module = sailor.tui.form;
const Form = form_module.Form;
const FormField = form_module.FormField;
const FieldState = form_module.FieldState;
const ValidateFn = form_module.ValidateFn;

// ============================================================================
// Validator Functions for Testing
// ============================================================================

fn validateNotEmpty(value: []const u8) ?[]const u8 {
    if (value.len == 0) {
        return "Field is required";
    }
    return null;
}

fn validateEmail(value: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, value, '@') == null) {
        return "Invalid email format";
    }
    return null;
}

fn validateMinLength3(value: []const u8) ?[]const u8 {
    if (value.len < 3) {
        return "Must be at least 3 characters";
    }
    return null;
}

// ============================================================================
// Test Suite: Initialization and Default State
// ============================================================================

test "Form with single field initializes correctly" {
    var states = [_]FieldState{FieldState{}};
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .placeholder = "" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try testing.expectEqual(@as(usize, 1), form.fields.len);
    try testing.expectEqual(@as(usize, 1), form.states.len);
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
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
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
    try testing.expectEqual(@as(u16, 12), form.label_width);
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
    try testing.expect(form.show_errors);
}

test "FieldState default value is empty string" {
    const state = FieldState{};
    try testing.expectEqual(@as(usize, 0), state.value.len);
}

// ============================================================================
// Test Suite: Focus Navigation
// ============================================================================

test "focusNext advances from field 0 to 1" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "first", .label = "First" },
        .{ .id = "second", .label = "Second" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    form.focusNext();
    try testing.expectEqual(@as(usize, 1), form.focused_idx);
}

test "focusNext wraps from last field to first" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "first", .label = "First" },
        .{ .id = "second", .label = "Second" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 1,
    };
    form.focusNext();
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "focusPrev moves from field 1 to 0" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "first", .label = "First" },
        .{ .id = "second", .label = "Second" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 1,
    };
    form.focusPrev();
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "focusPrev wraps from first field to last" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "first", .label = "First" },
        .{ .id = "second", .label = "Second" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };
    form.focusPrev();
    try testing.expectEqual(@as(usize, 1), form.focused_idx);
}

test "focusField sets focus to named field" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "email", .label = "Email" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const found = form.focusField("email");
    try testing.expect(found);
    try testing.expectEqual(@as(usize, 1), form.focused_idx);
}

test "focusField returns false for unknown field id" {
    var states = [_]FieldState{ FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const found = form.focusField("unknown");
    try testing.expect(!found);
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "getFocusedId returns current focused field id" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "email", .label = "Email" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 1,
    };
    const id = form.getFocusedId();
    try testing.expect(id != null);
    try testing.expectEqualStrings("email", id.?);
}

test "isFocused returns true for focused field" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "email", .label = "Email" },
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 1,
    };
    try testing.expect(form.isFocused("email"));
}

test "isFocused returns false for unfocused field" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "email", .label = "Email" },
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };
    try testing.expect(!form.isFocused("email"));
}

test "focusNext skips non-focusable fields" {
    var states = [_]FieldState{ FieldState{}, FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "first", .label = "First", .focusable = true },
        .{ .id = "disabled", .label = "Disabled", .focusable = false },
        .{ .id = "third", .label = "Third", .focusable = true },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };
    form.focusNext();
    try testing.expectEqual(@as(usize, 2), form.focused_idx);
}

test "focusPrev skips non-focusable fields" {
    var states = [_]FieldState{ FieldState{}, FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "first", .label = "First", .focusable = true },
        .{ .id = "disabled", .label = "Disabled", .focusable = false },
        .{ .id = "third", .label = "Third", .focusable = true },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 2,
    };
    form.focusPrev();
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

// ============================================================================
// Test Suite: Validation
// ============================================================================

test "validateAll sets error_msg for required empty field" {
    var states = [_]FieldState{ FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .required = true }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const valid = form.validateAll();
    try testing.expect(!valid);
    try testing.expect(form.states[0].error_msg != null);
}

test "validateAll clears error for required non-empty field" {
    var states = [_]FieldState{
        .{ .value = "John", .error_msg = "Previous error" }
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .required = true }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const valid = form.validateAll();
    try testing.expect(valid);
    try testing.expect(form.states[0].error_msg == null);
}

test "validateAll calls custom validator" {
    var states = [_]FieldState{ .{ .value = "invalid.email" } };
    const fields = [_]FormField{
        .{ .id = "email", .label = "Email", .validate = validateEmail }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const valid = form.validateAll();
    try testing.expect(!valid);
    try testing.expect(form.states[0].error_msg != null);
}

test "validateAll returns error message from validator" {
    var states = [_]FieldState{ .{ .value = "ab" } };
    const fields = [_]FormField{
        .{ .id = "code", .label = "Code", .validate = validateMinLength3 }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const valid = form.validateAll();
    try testing.expect(!valid);
    try testing.expect(form.states[0].error_msg != null);
    if (form.states[0].error_msg) |msg| {
        try testing.expect(std.mem.indexOf(u8, msg, "3") != null);
    }
}

test "validateAll clears error when validator returns null" {
    var states = [_]FieldState{
        .{ .value = "john@example.com", .error_msg = "Previous error" }
    };
    const fields = [_]FormField{
        .{ .id = "email", .label = "Email", .validate = validateEmail }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const valid = form.validateAll();
    try testing.expect(valid);
    try testing.expect(form.states[0].error_msg == null);
}

test "validateAll returns false when any field has error" {
    var states = [_]FieldState{
        .{ .value = "John" },
        .{ .value = "invalid.email" },
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .required = true },
        .{ .id = "email", .label = "Email", .validate = validateEmail },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const valid = form.validateAll();
    try testing.expect(!valid);
}

test "validateAll returns true when all fields valid" {
    var states = [_]FieldState{
        .{ .value = "John" },
        .{ .value = "john@example.com" },
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .required = true },
        .{ .id = "email", .label = "Email", .validate = validateEmail },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    const valid = form.validateAll();
    try testing.expect(valid);
}

// ============================================================================
// Test Suite: isValid
// ============================================================================

test "isValid returns true when all error_msg are null" {
    var states = [_]FieldState{
        .{ .value = "John", .error_msg = null },
        .{ .value = "john@example.com", .error_msg = null },
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "email", .label = "Email" },
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try testing.expect(form.isValid());
}

test "isValid returns false when any error_msg is set" {
    var states = [_]FieldState{
        .{ .value = "John", .error_msg = null },
        .{ .value = "invalid", .error_msg = "Invalid email" },
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "email", .label = "Email" },
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try testing.expect(!form.isValid());
}

test "isValid returns true for empty form" {
    var states: [0]FieldState = undefined;
    var fields: [0]FormField = undefined;
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try testing.expect(form.isValid());
}

test "isValid returns true after validateAll clears errors" {
    var states = [_]FieldState{
        .{ .value = "John", .error_msg = null }
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .required = true }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };
    _ = form.validateAll();
    try testing.expect(form.isValid());
}

// ============================================================================
// Test Suite: render
// ============================================================================

test "render on zero-area does not crash" {
    var states = [_]FieldState{ FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    form.render(&buf, area);
    // Should not crash or panic
}

test "render on zero-height area does not crash" {
    var states = [_]FieldState{ FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    form.render(&buf, area);
    // Should not crash or panic
}

test "render single field writes label text to buffer" {
    var states = [_]FieldState{ FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    form.render(&buf, area);

    // First character of label should be 'N'
    const cell = buf.get(0, 0);
    try testing.expectEqual('N', cell.?.char);
}

test "render sets value text in buffer" {
    var states = [_]FieldState{ .{ .value = "John" } };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .placeholder = "" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
        .label_width = 6,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    form.render(&buf, area);

    // Value should start after label_width + colon + space
    const value_start_x = 8; // 6 + 1 (colon) + 1 (space)
    const cell = buf.get(@intCast(value_start_x), 0);
    try testing.expectEqual('J', cell.?.char);
}

test "render focused field is at focused_idx position" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "email", .label = "Email" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 1,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    form.render(&buf, area);

    // Email label should be on second row
    const cell = buf.get(0, 1);
    try testing.expectEqual('E', cell.?.char);
}

test "render error message when show_errors true and error_msg set" {
    var states = [_]FieldState{
        .{ .value = "invalid", .error_msg = "Bad value" }
    };
    const fields = [_]FormField{
        .{ .id = "email", .label = "Email" }
    };
    const form = Form{
        .fields = &fields,
        .states = &states,
        .show_errors = true,
        .label_width = 6,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    form.render(&buf, area);

    // Error message should appear on second row
    const error_cell = buf.get(8, 1); // Same x position as value
    try testing.expectEqual('B', error_cell.?.char);
}

// ============================================================================
// Test Suite: Edge Cases
// ============================================================================

test "focusNext on single focusable field stays at 0" {
    var states = [_]FieldState{ FieldState{} };
    const fields = [_]FormField{
        .{ .id = "only", .label = "Only", .focusable = true }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };
    form.focusNext();
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "focusPrev on single focusable field stays at 0" {
    var states = [_]FieldState{ FieldState{} };
    const fields = [_]FormField{
        .{ .id = "only", .label = "Only", .focusable = true }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };
    form.focusPrev();
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "focusNext with all non-focusable fields does not infinite loop" {
    var states = [_]FieldState{ FieldState{}, FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "a", .label = "A", .focusable = false },
        .{ .id = "b", .label = "B", .focusable = false },
        .{ .id = "c", .label = "C", .focusable = false },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };
    form.focusNext();
    // Should not hang; focus_idx should be valid
    try testing.expect(form.focused_idx < form.fields.len);
}

test "focusPrev with all non-focusable fields does not infinite loop" {
    var states = [_]FieldState{ FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "a", .label = "A", .focusable = false },
        .{ .id = "b", .label = "B", .focusable = false },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 1,
    };
    form.focusPrev();
    try testing.expect(form.focused_idx < form.fields.len);
}

test "form with zero fields isValid returns true" {
    var states: [0]FieldState = undefined;
    var fields: [0]FormField = undefined;
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    try testing.expect(form.isValid());
}

test "form with zero fields render is no-op" {
    var states: [0]FieldState = undefined;
    var fields: [0]FormField = undefined;
    const form = Form{
        .fields = &fields,
        .states = &states,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    form.render(&buf, area);
    // Should complete without crash
}

// ============================================================================
// Test Suite: Complex Scenarios
// ============================================================================

test "focus cycle through three fields" {
    var states = [_]FieldState{ FieldState{}, FieldState{}, FieldState{} };
    const fields = [_]FormField{
        .{ .id = "a", .label = "Field A" },
        .{ .id = "b", .label = "Field B" },
        .{ .id = "c", .label = "Field C" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };

    form.focusNext();
    try testing.expectEqual(@as(usize, 1), form.focused_idx);

    form.focusNext();
    try testing.expectEqual(@as(usize, 2), form.focused_idx);

    form.focusNext();
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "validateAll on form with mixed validators" {
    var states = [_]FieldState{
        .{ .value = "John" },
        .{ .value = "" },
        .{ .value = "ab" },
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name", .required = true },
        .{ .id = "email", .label = "Email", .validate = validateEmail },
        .{ .id = "code", .label = "Code", .validate = validateMinLength3 },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };

    const valid = form.validateAll();
    try testing.expect(!valid);
    // First field: valid (non-empty)
    try testing.expect(form.states[0].error_msg == null);
    // Second field: invalid (empty and must be email)
    try testing.expect(form.states[1].error_msg != null);
    // Third field: invalid (too short)
    try testing.expect(form.states[2].error_msg != null);
}

test "render multiline form with error messages" {
    var states = [_]FieldState{
        .{ .value = "John", .error_msg = null },
        .{ .value = "bad", .error_msg = "Too short" },
    };
    const fields = [_]FormField{
        .{ .id = "name", .label = "Name" },
        .{ .id = "code", .label = "Code" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .show_errors = true,
        .label_width = 6,
    };
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    form.render(&buf, area);

    // First field on row 0 should have "Name"
    try testing.expectEqual('N', buf.get(0, 0).?.char);
    // Second field on row 1 should have "Code"
    try testing.expectEqual('C', buf.get(0, 1).?.char);
    // Error message on row 2 (below code field)
    try testing.expectEqual('T', buf.get(8, 2).?.char);
}

test "focusField returns true and updates focus correctly" {
    var states = [_]FieldState{
        FieldState{},
        FieldState{},
        FieldState{},
    };
    const fields = [_]FormField{
        .{ .id = "first", .label = "First" },
        .{ .id = "second", .label = "Second" },
        .{ .id = "third", .label = "Third" },
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
        .focused_idx = 0,
    };

    var found = form.focusField("third");
    try testing.expect(found);
    try testing.expectEqual(@as(usize, 2), form.focused_idx);

    found = form.focusField("first");
    try testing.expect(found);
    try testing.expectEqual(@as(usize, 0), form.focused_idx);

    found = form.focusField("nonexistent");
    try testing.expect(!found);
    try testing.expectEqual(@as(usize, 0), form.focused_idx);
}

test "validateAll with required field and custom validator" {
    // Value is non-empty (passes required check) but has no '@' (fails validateEmail)
    // This verifies that when both constraints are set, the custom validator still runs
    var states = [_]FieldState{ .{ .value = "noemail" } };
    const fields = [_]FormField{
        .{ .id = "email", .label = "Email", .required = true, .validate = validateEmail }
    };
    var form = Form{
        .fields = &fields,
        .states = &states,
    };

    const valid = form.validateAll();
    try testing.expect(!valid);
    try testing.expect(form.states[0].error_msg != null);
}
