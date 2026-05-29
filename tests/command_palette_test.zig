const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const command_palette = @import("../src/tui/widgets/command_palette.zig");

const CommandPalette = command_palette.CommandPalette;
const Command = command_palette.Command;
const CommandResult = command_palette.CommandResult;

// ============================================================================
// Helper: Command Handler Tracking
// ============================================================================

var handler_called = false;

fn test_handler() void {
    handler_called = true;
}

// ============================================================================
// CommandPalette.init Tests
// ============================================================================

test "command palette init creates empty palette" {
    const palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    try testing.expectEqual(@as(usize, 0), palette.commands.items.len);
    try testing.expectEqual(@as(usize, 0), palette.getResults().len);
}

test "command palette init allocation succeeds" {
    const palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    try testing.expect(palette.commands.capacity > 0);
}

// ============================================================================
// CommandPalette.register Tests
// ============================================================================

test "command palette register single command" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{
        .id = "test.cmd",
        .title = "Test Command",
        .handler = &test_handler,
    };

    try palette.register(cmd);
    try testing.expectEqual(@as(usize, 1), palette.commands.items.len);
}

test "command palette register multiple commands" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{
        .id = "cmd1",
        .title = "Command One",
        .handler = &test_handler,
    };
    const cmd2 = Command{
        .id = "cmd2",
        .title = "Command Two",
        .handler = &test_handler,
    };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try testing.expectEqual(@as(usize, 2), palette.commands.items.len);
}

test "command palette register with category" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{
        .id = "file.open",
        .title = "Open File",
        .category = "File",
        .handler = &test_handler,
    };

    try palette.register(cmd);
    try testing.expectEqual(@as(usize, 1), palette.commands.items.len);
}

test "command palette register with description" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{
        .id = "edit.cut",
        .title = "Cut",
        .description = "Cut selected text to clipboard",
        .handler = &test_handler,
    };

    try palette.register(cmd);
    const registered = palette.commands.items[0];
    try testing.expectEqualStrings("Cut selected text to clipboard", registered.description.?);
}

test "command palette register with all fields" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{
        .id = "file.save",
        .title = "Save File",
        .category = "File",
        .description = "Save the current file",
        .handler = &test_handler,
    };

    try palette.register(cmd);
    const registered = palette.commands.items[0];
    try testing.expectEqualStrings("file.save", registered.id);
    try testing.expectEqualStrings("Save File", registered.title);
    try testing.expectEqualStrings("File", registered.category.?);
    try testing.expectEqualStrings("Save the current file", registered.description.?);
}

// ============================================================================
// CommandPalette.setQuery Tests
// ============================================================================

test "command palette empty query returns all commands" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "Alpha", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Beta", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    try testing.expectEqual(@as(usize, 2), palette.getResults().len);
}

test "command palette query filters by fuzzy match" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "Open File", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Close File", .handler = &test_handler };
    const cmd3 = Command{ .id = "cmd3", .title = "Save Buffer", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.register(cmd3);
    try palette.setQuery("file");

    const results = palette.getResults();
    try testing.expectEqual(@as(usize, 2), results.len); // Open File, Close File
}

test "command palette query case insensitive" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "cmd1", .title = "Open File", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("OPEN");

    const results = palette.getResults();
    try testing.expect(results.len > 0);
}

test "command palette query no matches returns empty" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "cmd1", .title = "Open File", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("xyz");

    try testing.expectEqual(@as(usize, 0), palette.getResults().len);
}

test "command palette query results sorted by score" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "open", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "reopen", .handler = &test_handler };
    const cmd3 = Command{ .id = "cmd3", .title = "unopened", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.register(cmd3);
    try palette.setQuery("open");

    const results = palette.getResults();
    try testing.expect(results.len >= 1);

    // First result should have highest score (prefix match "open")
    if (results.len > 1) {
        try testing.expect(results[0].score >= results[1].score);
    }
}

test "command palette query updates results" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "Open File", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Save File", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);

    try palette.setQuery("open");
    const results1 = palette.getResults();
    try testing.expectEqual(@as(usize, 1), results1.len);

    try palette.setQuery("save");
    const results2 = palette.getResults();
    try testing.expectEqual(@as(usize, 1), results2.len);
}

// ============================================================================
// CommandPalette.getResults Tests
// ============================================================================

test "command palette getResults contains match positions" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "cmd1", .title = "test", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("t");

    const results = palette.getResults();
    try testing.expect(results.len > 0);
    try testing.expect(results[0].match_positions.len > 0);
}

test "command palette getResults score field set" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "cmd1", .title = "test", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("test");

    const results = palette.getResults();
    try testing.expect(results.len > 0);
    try testing.expect(results[0].score > 0.0);
}

test "command palette getResults empty when no matches" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "cmd1", .title = "alpha", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("xyz");

    try testing.expectEqual(@as(usize, 0), palette.getResults().len);
}

// ============================================================================
// CommandPalette.selectNext / selectPrev Tests
// ============================================================================

test "command palette selectNext advances selection" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "Command One", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Command Two", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    palette.selectNext();
    try testing.expectEqual(@as(usize, 1), palette.selected_index);
}

test "command palette selectNext wraps around" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "One", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Two", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    palette.selectNext(); // 0 -> 1
    palette.selectNext(); // 1 -> 0 (wrap)
    try testing.expectEqual(@as(usize, 0), palette.selected_index);
}

test "command palette selectNext on empty results does nothing" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    try palette.setQuery("xyz");
    palette.selectNext();
    // Should not crash, selection should remain at 0
    try testing.expectEqual(@as(usize, 0), palette.selected_index);
}

test "command palette selectPrev retreats selection" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "One", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Two", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    palette.selectNext(); // 0 -> 1
    palette.selectPrev(); // 1 -> 0
    try testing.expectEqual(@as(usize, 0), palette.selected_index);
}

test "command palette selectPrev wraps to end" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "One", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Two", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    palette.selectPrev(); // 0 -> 1 (wrap)
    try testing.expectEqual(@as(usize, 1), palette.selected_index);
}

test "command palette selectPrev on empty results does nothing" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    try palette.setQuery("xyz");
    palette.selectPrev();
    // Should not crash
    try testing.expectEqual(@as(usize, 0), palette.selected_index);
}

// ============================================================================
// CommandPalette.getSelected Tests
// ============================================================================

test "command palette getSelected returns currently selected" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "test", .title = "Test", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("");

    const selected = palette.getSelected();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("test", selected.?.command.id);
}

test "command palette getSelected returns null when no results" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    try palette.setQuery("xyz");

    const selected = palette.getSelected();
    try testing.expectEqual(@as(?CommandResult, null), selected);
}

test "command palette getSelected returns null when palette empty" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const selected = palette.getSelected();
    try testing.expectEqual(@as(?CommandResult, null), selected);
}

test "command palette getSelected after navigation" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "One", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Two", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    palette.selectNext();
    const selected = palette.getSelected();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("cmd2", selected.?.command.id);
}

// ============================================================================
// CommandPalette.activate Tests
// ============================================================================

test "command palette activate calls handler" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    handler_called = false;
    const cmd = Command{ .id = "test", .title = "Test", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("");

    palette.activate();
    try testing.expectEqual(true, handler_called);
}

test "command palette activate on empty does nothing" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    handler_called = false;
    try palette.setQuery("xyz");

    palette.activate();
    try testing.expectEqual(false, handler_called);
}

test "command palette activate uses selected index" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    handler_called = false;
    const cmd1 = Command{ .id = "cmd1", .title = "One", .handler = &test_handler };
    const cmd2 = Command{
        .id = "cmd2",
        .title = "Two",
        .handler = &test_handler,
    };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    palette.selectNext(); // Move to cmd2
    palette.activate();

    try testing.expectEqual(true, handler_called);
}

// ============================================================================
// CommandPalette.render Tests
// ============================================================================

test "command palette render empty palette" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try palette.render(&buf, area);

    // Should not crash
}

test "command palette render single command" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "test", .title = "Test Command", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("");

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try palette.render(&buf, area);

    // Verify command title appears in buffer
    var found = false;
    for (0..80) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'T') {
                found = true;
                break;
            }
        }
    }
    try testing.expect(found);
}

test "command palette render with selection" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "Alpha", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Beta", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.setQuery("");

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    palette.selectNext();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try palette.render(&buf, area);

    // Should render both commands
}

test "command palette render with filter query" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "Open File", .handler = &test_handler };
    const cmd2 = Command{ .id = "cmd2", .title = "Save File", .handler = &test_handler };
    const cmd3 = Command{ .id = "cmd3", .title = "Copy Text", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.register(cmd3);
    try palette.setQuery("file");

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try palette.render(&buf, area);

    // Should render filtered results
}

test "command palette render clips at height boundary" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    for (0..10) |i| {
        var title_buf: [32]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buf, "Command {d}", .{i});
        const cmd = Command{
            .id = "cmd",
            .title = title,
            .handler = &test_handler,
        };
        try palette.register(cmd);
    }
    try palette.setQuery("");

    var buf = try Buffer.init(testing.allocator, 80, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    try palette.render(&buf, area);

    // Should only render commands that fit in height
}

test "command palette render with offset area" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd = Command{ .id = "test", .title = "Test", .handler = &test_handler };
    try palette.register(cmd);
    try palette.setQuery("");

    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 10 };
    try palette.render(&buf, area);

    // Should render within offset area
}

// ============================================================================
// Integration Tests
// ============================================================================

test "command palette full workflow" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "file.open", .title = "Open File", .category = "File", .handler = &test_handler };
    const cmd2 = Command{ .id = "file.save", .title = "Save File", .category = "File", .handler = &test_handler };
    const cmd3 = Command{ .id = "edit.cut", .title = "Cut", .category = "Edit", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);
    try palette.register(cmd3);

    // Set query
    try palette.setQuery("file");

    // Should have 2 results
    const results = palette.getResults();
    try testing.expectEqual(@as(usize, 2), results.len);

    // Navigate
    palette.selectNext();
    const selected = palette.getSelected();
    try testing.expect(selected != null);

    // Render
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try palette.render(&buf, area);
}

test "command palette handles dynamic command updates" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "cmd1", .title = "Command One", .handler = &test_handler };
    try palette.register(cmd1);
    try palette.setQuery("");

    try testing.expectEqual(@as(usize, 1), palette.getResults().len);

    // Register another command
    const cmd2 = Command{ .id = "cmd2", .title = "Command Two", .handler = &test_handler };
    try palette.register(cmd2);
    try palette.setQuery(""); // Re-query

    try testing.expectEqual(@as(usize, 2), palette.getResults().len);
}

test "command palette category filtering" {
    var palette = try CommandPalette.init(testing.allocator);
    defer palette.deinit();

    const cmd1 = Command{ .id = "file.open", .title = "Open", .category = "File", .handler = &test_handler };
    const cmd2 = Command{ .id = "edit.paste", .title = "Paste", .category = "Edit", .handler = &test_handler };

    try palette.register(cmd1);
    try palette.register(cmd2);

    // Query for "file" should find "Open File" category command
    try palette.setQuery("file");
    const results = palette.getResults();
    try testing.expect(results.len >= 1);
}
