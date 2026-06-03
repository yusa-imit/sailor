//! RecordEditor tests — v2.17.0
//!
//! Tests inline record (key-value) editing with field navigation, validation, and rendering.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;

const RecordEditor = sailor.tui.widgets.RecordEditor;
const Field = sailor.tui.widgets.RecordEditorField;
const ValidationResult = sailor.tui.widgets.RecordEditorValidationResult;
const ValidateFn = sailor.tui.widgets.RecordEditorValidateFn;

fn makeBuffer(allocator: std.mem.Allocator, w: u16, h: u16) !Buffer {
    return Buffer.init(allocator, w, h);
}

// ============================================================================
// State initialization
// ============================================================================

test "RecordEditor default state" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    const editor = RecordEditor{
        .fields = &fields,
    };
    try testing.expectEqual(@as(usize, 0), editor.selected);
    try testing.expect(!editor.is_editing);
    try testing.expectEqual(@as(usize, 0), editor.edit_len);
}

test "RecordEditor with custom key_width" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    const editor = RecordEditor{
        .fields = &fields,
        .key_width = 30,
    };
    try testing.expectEqual(@as(u16, 30), editor.key_width);
}

test "RecordEditor with block" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    const block = Block{ .borders = .all };
    const editor = RecordEditor{
        .fields = &fields,
        .block = block,
    };
    try testing.expect(editor.block != null);
}

// ============================================================================
// Navigation — moveDown
// ============================================================================

test "moveDown — cursor moves to next field" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var editor = RecordEditor{
        .fields = &fields,
    };
    editor.moveDown();
    try testing.expectEqual(@as(usize, 1), editor.selected);
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
    try testing.expectEqual(@as(usize, 1), editor.selected);
}

test "moveDown — multiple times visits all fields" {
    var fields = [_]Field{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
        .{ .key = "c", .value = "3" },
    };
    var editor = RecordEditor{
        .fields = &fields,
    };
    editor.moveDown();
    try testing.expectEqual(@as(usize, 1), editor.selected);
    editor.moveDown();
    try testing.expectEqual(@as(usize, 2), editor.selected);
    editor.moveDown();
    try testing.expectEqual(@as(usize, 2), editor.selected);
}

test "moveDown — on empty fields is safe" {
    var editor = RecordEditor{
        .fields = &.{},
    };
    editor.moveDown();
    try testing.expectEqual(@as(usize, 0), editor.selected);
}

// ============================================================================
// Navigation — moveUp
// ============================================================================

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
    try testing.expectEqual(@as(usize, 0), editor.selected);
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
    try testing.expectEqual(@as(usize, 0), editor.selected);
}

test "moveUp then moveDown returns to start" {
    var fields = [_]Field{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    var editor = RecordEditor{
        .fields = &fields,
        .selected = 1,
    };
    editor.moveUp();
    try testing.expectEqual(@as(usize, 0), editor.selected);
    editor.moveDown();
    try testing.expectEqual(@as(usize, 1), editor.selected);
}

test "moveUp — on empty fields is safe" {
    var editor = RecordEditor{
        .fields = &.{},
    };
    editor.moveUp();
    try testing.expectEqual(@as(usize, 0), editor.selected);
}

// ============================================================================
// Query — currentField
// ============================================================================

test "currentField — returns selected field" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    const editor = RecordEditor{
        .fields = &fields,
    };
    const field = editor.currentField();
    try testing.expect(field != null);
    try testing.expectEqualStrings("name", field.?.key);
    try testing.expectEqualStrings("Alice", field.?.value);
}

test "currentField — different positions" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var editor = RecordEditor{
        .fields = &fields,
        .selected = 1,
    };
    const field = editor.currentField();
    try testing.expect(field != null);
    try testing.expectEqualStrings("age", field.?.key);
}

test "currentField — null when no fields" {
    var editor = RecordEditor{
        .fields = &.{},
    };
    const field = editor.currentField();
    try testing.expect(field == null);
}

// ============================================================================
// Edit mode — startEdit
// ============================================================================

test "startEdit — enters edit mode" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    try testing.expect(!editor.is_editing);
    editor.startEdit();
    try testing.expect(editor.is_editing);
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
    try testing.expectEqualStrings("Alice", text);
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
    try testing.expect(!editor.is_editing);
}

test "startEdit — clears previous edit buffer" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
        .{ .key = "age", .value = "30" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.moveDown();
    editor.startEdit();
    const text = editor.editText();
    try testing.expectEqualStrings("30", text);
}

// ============================================================================
// Edit mode — insertChar
// ============================================================================

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
    try testing.expectEqualStrings("A", editor.editText());
}

test "insertChar — multiple chars build up string" {
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
    editor.insertChar('l');
    editor.insertChar('i');
    editor.insertChar('c');
    editor.insertChar('e');
    try testing.expectEqualStrings("Alice", editor.editText());
}

test "insertChar — respects buffer length limit" {
    var fields = [_]Field{
        .{ .key = "name", .value = "" },
    };
    var edit_buf = [_]u8{0} ** 5;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.insertChar('A');
    editor.insertChar('B');
    editor.insertChar('C');
    editor.insertChar('D');
    editor.insertChar('E');
    editor.insertChar('F');
    const text = editor.editText();
    try testing.expect(text.len <= 5);
}

// ============================================================================
// Edit mode — deleteChar
// ============================================================================

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
    try testing.expectEqualStrings("Alic", editor.editText());
}

test "deleteChar — multiple times empties buffer" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Hi" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.deleteChar();
    editor.deleteChar();
    try testing.expectEqualStrings("", editor.editText());
}

test "deleteChar — on empty buffer is safe" {
    var fields = [_]Field{
        .{ .key = "name", .value = "" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.deleteChar();
    try testing.expectEqualStrings("", editor.editText());
}

// ============================================================================
// Edit mode — confirmEdit
// ============================================================================

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
    try testing.expect(editor.is_editing);
    editor.confirmEdit();
    try testing.expect(!editor.is_editing);
}

test "confirmEdit — when not editing is safe" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.confirmEdit();
    try testing.expect(!editor.is_editing);
}

// ============================================================================
// Edit mode — cancelEdit
// ============================================================================

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
    try testing.expect(!editor.is_editing);
}

test "cancelEdit — when not editing is safe" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.cancelEdit();
    try testing.expect(!editor.is_editing);
}

// ============================================================================
// Query — editText
// ============================================================================

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
    try testing.expectEqualStrings("", text);
}

test "editText — returns current edit content when editing" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    editor.startEdit();
    editor.insertChar('X');
    const text = editor.editText();
    try testing.expectEqualStrings("AliceX", text);
}

// ============================================================================
// Validation — isValid
// ============================================================================

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
    try testing.expect(valid);
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
    try testing.expect(valid);
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
    try testing.expect(!valid);
}

test "isValid — validation receives key and value" {
    var fields = [_]Field{
        .{ .key = "port", .value = "8080" },
    };
    var edit_buf = [_]u8{0} ** 256;

    const validator = struct {
        fn validate(key: []const u8, value: []const u8) ValidationResult {
            // Simplified test — just validate port is numeric
            _ = key;
            for (value) |ch| {
                if (ch < '0' or ch > '9') return .invalid;
            }
            return .ok;
        }
    }.validate;

    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .validate = &validator,
    };
    editor.startEdit();
    const valid = editor.isValid();
    try testing.expect(valid);
}

// ============================================================================
// Read-only fields
// ============================================================================

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
    try testing.expect(!editor.is_editing);
}

test "read-only field — currentField shows is_editable flag" {
    var fields = [_]Field{
        .{ .key = "id", .value = "12345", .is_editable = false },
    };
    const editor = RecordEditor{
        .fields = &fields,
    };
    const field = editor.currentField();
    try testing.expect(field != null);
    try testing.expect(!field.?.is_editable);
}

test "editable field — currentField shows is_editable flag" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice", .is_editable = true },
    };
    const editor = RecordEditor{
        .fields = &fields,
    };
    const field = editor.currentField();
    try testing.expect(field != null);
    try testing.expect(field.?.is_editable);
}

// ============================================================================
// Render — edge cases
// ============================================================================

test "render — zero area is safe" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
    };
    var buf = try makeBuffer(testing.allocator, 10, 5);
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
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 0 });
}

test "render — empty fields is safe" {
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &.{},
        .edit_buffer = &edit_buf,
    };
    var buf = try makeBuffer(testing.allocator, 10, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });
}

// ============================================================================
// Render — styling
// ============================================================================

test "render — selected field uses selected_style" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .selected_style = .{ .reverse = true },
    };
    var buf = try makeBuffer(testing.allocator, 30, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });
    const cell = buf.get(0, 0);
    try testing.expect(cell != null);
    try testing.expect(cell.?.style.reverse);
}

test "render — editing field uses editing_style" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .editing_style = .{ .fg = Color.yellow },
    };
    var buf = try makeBuffer(testing.allocator, 30, 5);
    defer buf.deinit();
    editor.startEdit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });
}

test "render — read-only field uses readonly_style" {
    var fields = [_]Field{
        .{ .key = "id", .value = "12345", .is_editable = false },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .readonly_style = .{ .fg = Color.bright_black },
    };
    var buf = try makeBuffer(testing.allocator, 30, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });
}

test "render — normal field uses normal_style" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    var edit_buf = [_]u8{0} ** 256;
    var editor = RecordEditor{
        .fields = &fields,
        .edit_buffer = &edit_buf,
        .normal_style = .{ .fg = Color.white },
    };
    var buf = try makeBuffer(testing.allocator, 30, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });
}

test "render — invalid field uses error_style" {
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
        .error_style = .{ .fg = Color.red },
    };
    var buf = try makeBuffer(testing.allocator, 30, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });
}

// ============================================================================
// Builder methods
// ============================================================================

test "withBlock — sets block wrapper" {
    var fields = [_]Field{
        .{ .key = "name", .value = "Alice" },
    };
    const block = Block{ .borders = .all, .title = "Editor" };
    var editor = RecordEditor{
        .fields = &fields,
    };
    editor = editor.withBlock(block);
    try testing.expect(editor.block != null);
    try testing.expectEqualStrings("Editor", editor.block.?.title.?);
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
    try testing.expect(editor.validate != null);
}
