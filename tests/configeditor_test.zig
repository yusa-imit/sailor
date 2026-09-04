const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;

// Forces analysis of src/tui/widgets/configeditor.zig so its inline `test`
// blocks (including the scalar-value editing suite) actually run under
// `zig build test` instead of being silently skipped as unreachable code.
const ConfigEditor = sailor.tui.widgets.ConfigEditor;
const ConfigNode = sailor.tui.widgets.ConfigNode;

test "ConfigEditor (via sailor module): full edit-confirm workflow" {
    const nodes = [_]ConfigNode{
        .{
            .key = "greeting",
            .value_type = .string,
            .value = .{ .string = "hi" },
        },
    };
    var editor = ConfigEditor.init(&nodes).withSelected(0);

    var edit_buf = [_]u8{0} ** 32;
    editor.edit_buffer = &edit_buf;

    editor.startEdit();
    try std.testing.expectEqualStrings("hi", editor.editText());

    editor.insertChar('!');
    try std.testing.expectEqualStrings("hi!", editor.editText());

    editor.deleteChar();
    try std.testing.expectEqualStrings("hi", editor.editText());

    editor.confirmEdit();
    try std.testing.expect(!editor.is_editing);
}

test "ConfigEditor (via sailor module): render after cancelled edit does not crash" {
    const nodes = [_]ConfigNode{
        .{
            .key = "port",
            .value_type = .number,
            .value = .{ .number = 8080.0 },
        },
    };
    var editor = ConfigEditor.init(&nodes).withSelected(0);

    var edit_buf = [_]u8{0} ** 32;
    editor.edit_buffer = &edit_buf;

    editor.startEdit();
    editor.insertChar('9');
    editor.cancelEdit();

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();
    editor.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });

    // Source value must be untouched by the cancelled edit
    try std.testing.expectEqual(@as(f64, 8080.0), editor.nodes[0].value.number);
}
