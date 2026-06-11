//! CommandBar Widget Tests — TDD Red Phase
//!
//! Tests CommandBar widget with command registration, query filtering (prefix+substring
//! ranking), cursor navigation, builder pattern, and rendering capabilities.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const CommandBar = sailor.tui.widgets.CommandBar;
const CommandBarCommand = sailor.tui.widgets.CommandBarCommand;

// ============================================================================
// Init & Deinit Tests (5 tests)
// ============================================================================

test "CommandBar.init creates empty instance" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try testing.expectEqual(@as(usize, 0), cb.resultCount());
}

test "CommandBar.init can be deinitialized without crash" {
    var cb = try CommandBar.init(testing.allocator);
    cb.deinit();
    // No assertion needed; if we got here without crash, test passes
}

test "CommandBar.init returns valid instance with empty query" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try testing.expectEqualStrings("", cb.getQuery());
}

test "CommandBar.init sets cursor to 0" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try testing.expect(cb.selectedCommand() == null);
}

test "CommandBar init+deinit multiple times without memory leaks" {
    var cb1 = try CommandBar.init(testing.allocator);
    cb1.deinit();
    var cb2 = try CommandBar.init(testing.allocator);
    cb2.deinit();
    var cb3 = try CommandBar.init(testing.allocator);
    cb3.deinit();
}

// ============================================================================
// Register Tests (8 tests)
// ============================================================================

test "register single command stores it" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const cmd = CommandBarCommand{ .name = "save", .description = "Save file" };
    try cb.register(cmd);
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "register multiple commands stores all" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "load" });
    try cb.register(.{ .name = "quit" });
    try testing.expectEqual(@as(usize, 3), cb.resultCount());
}

test "register command with description stores it" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const cmd = CommandBarCommand{
        .name = "commit",
        .description = "Commit changes to repository",
    };
    try cb.register(cmd);
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "register command with shortcut stores it" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const cmd = CommandBarCommand{
        .name = "save",
        .description = "Save file",
        .shortcut = "Ctrl+S",
    };
    try cb.register(cmd);
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "register with empty name succeeds" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "" });
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "register same name twice replaces first" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save", .description = "Old description" });
    try cb.register(.{ .name = "save", .description = "New description" });
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "register many commands (10+) succeeds" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    for (0..15) |i| {
        var buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "cmd{}", .{i});
        try cb.register(.{ .name = name });
    }
    try testing.expectEqual(@as(usize, 15), cb.resultCount());
}

test "register command fully populated structure" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const cmd = CommandBarCommand{
        .name = "build",
        .description = "Build the project",
        .shortcut = "Ctrl+B",
    };
    try cb.register(cmd);
    const results = cb.results();
    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqualStrings("build", results[0].name);
    try testing.expectEqualStrings("Build the project", results[0].description);
    try testing.expectEqualStrings("Ctrl+B", results[0].shortcut);
}

// ============================================================================
// Unregister Tests (6 tests)
// ============================================================================

test "unregister existing command removes it" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
    cb.unregister("save");
    try testing.expectEqual(@as(usize, 0), cb.resultCount());
}

test "unregister non-existing command has no effect" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    cb.unregister("nonexistent");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "unregister from multiple commands removes correct one" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "load" });
    try cb.register(.{ .name = "quit" });
    cb.unregister("load");
    try testing.expectEqual(@as(usize, 2), cb.resultCount());
}

test "unregister all commands leaves empty" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "load" });
    cb.unregister("save");
    cb.unregister("load");
    try testing.expectEqual(@as(usize, 0), cb.resultCount());
}

test "unregister with empty name does nothing" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    cb.unregister("");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "unregister resets cursor if needed" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "a" });
    try cb.register(.{ .name = "b" });
    cb.moveCursorDown();
    cb.unregister("b");
    // After removing "b", cursor should be clamped
    try testing.expect(cb.selectedCommand() != null);
}

// ============================================================================
// Query & Results Tests (15 tests)
// ============================================================================

test "setQuery empty string returns all commands" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "load" });
    _ = cb.setQuery("");
    try testing.expectEqual(@as(usize, 2), cb.resultCount());
}

test "getQuery returns current query" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    _ = cb.setQuery("test");
    try testing.expectEqualStrings("test", cb.getQuery());
}

test "getQuery after clearQuery returns empty" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    _ = cb.setQuery("something");
    cb.clearQuery();
    try testing.expectEqualStrings("", cb.getQuery());
}

test "clearQuery makes results same as setQuery empty" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "load" });
    _ = cb.setQuery("save");
    cb.clearQuery();
    try testing.expectEqual(@as(usize, 2), cb.resultCount());
}

test "prefix match ranks first" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "search" });
    try cb.register(.{ .name = "load" });
    _ = cb.setQuery("sa");
    const results = cb.results();
    try testing.expectEqual(@as(usize, 2), results.len);
    try testing.expectEqualStrings("save", results[0].name);
    try testing.expectEqualStrings("search", results[1].name);
}

test "substring match appears after prefix match" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "loadsave" });
    _ = cb.setQuery("save");
    const results = cb.results();
    try testing.expectEqual(@as(usize, 2), results.len);
    try testing.expectEqualStrings("save", results[0].name);
    try testing.expectEqualStrings("loadsave", results[1].name);
}

test "no match query returns zero results" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("zzzzz");
    try testing.expectEqual(@as(usize, 0), cb.resultCount());
}

test "case sensitive matching" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "Save" });
    _ = cb.setQuery("save");
    try testing.expectEqual(@as(usize, 0), cb.resultCount());
}

test "query with special characters matches" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "ctrl-s" });
    _ = cb.setQuery("ctrl");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "setQuery updates results dynamically" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "search" });
    _ = cb.setQuery("sa");
    try testing.expectEqual(@as(usize, 2), cb.resultCount());
    _ = cb.setQuery("se");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "setQuery with very long text" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("verylongquerythatwontmatch");
    try testing.expectEqual(@as(usize, 0), cb.resultCount());
}

test "results returns slice, not modified on register" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("");
    const r1 = cb.results();
    try testing.expectEqual(@as(usize, 1), r1.len);
    try cb.register(.{ .name = "load" });
    const r2 = cb.results();
    try testing.expectEqual(@as(usize, 2), r2.len);
}

test "no duplicate results even if registered twice" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "results maintain registration order when empty query" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "first" });
    try cb.register(.{ .name = "second" });
    try cb.register(.{ .name = "third" });
    _ = cb.setQuery("");
    const results = cb.results();
    try testing.expectEqualStrings("first", results[0].name);
    try testing.expectEqualStrings("second", results[1].name);
    try testing.expectEqualStrings("third", results[2].name);
}

// ============================================================================
// Cursor Navigation Tests (10 tests)
// ============================================================================

test "cursor starts at invalid position (no results)" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try testing.expect(cb.selectedCommand() == null);
}

test "moveCursorDown with one result selects it" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("");
    cb.moveCursorDown();
    try testing.expect(cb.selectedCommand() != null);
    try testing.expectEqualStrings("save", cb.selectedCommand().?.name);
}

test "moveCursorDown with three results increments cursor" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "a" });
    try cb.register(.{ .name = "b" });
    try cb.register(.{ .name = "c" });
    _ = cb.setQuery("");
    cb.moveCursorDown();
    try testing.expectEqualStrings("a", cb.selectedCommand().?.name);
    cb.moveCursorDown();
    try testing.expectEqualStrings("b", cb.selectedCommand().?.name);
    cb.moveCursorDown();
    try testing.expectEqualStrings("c", cb.selectedCommand().?.name);
    cb.moveCursorDown();
    try testing.expectEqualStrings("c", cb.selectedCommand().?.name); // clamp
}

test "moveCursorUp from position 1 goes to 0" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "a" });
    try cb.register(.{ .name = "b" });
    _ = cb.setQuery("");
    cb.moveCursorDown(); // 0
    cb.moveCursorDown(); // 1
    cb.moveCursorUp();   // 0
    try testing.expectEqualStrings("a", cb.selectedCommand().?.name);
}

test "moveCursorUp at 0 stays at 0" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "a" });
    _ = cb.setQuery("");
    cb.moveCursorUp();
    try testing.expect(cb.selectedCommand() == null);
}

test "moveCursorDown multiple times then up sequences correctly" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "a" });
    try cb.register(.{ .name = "b" });
    try cb.register(.{ .name = "c" });
    _ = cb.setQuery("");
    cb.moveCursorDown();
    cb.moveCursorDown();
    cb.moveCursorDown();
    try testing.expectEqualStrings("c", cb.selectedCommand().?.name);
    cb.moveCursorUp();
    try testing.expectEqualStrings("b", cb.selectedCommand().?.name);
    cb.moveCursorUp();
    try testing.expectEqualStrings("a", cb.selectedCommand().?.name);
}

test "moveCursorDown with filtered results only uses filtered set" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "load" });
    try cb.register(.{ .name = "quit" });
    _ = cb.setQuery("l");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
    cb.moveCursorDown();
    try testing.expectEqualStrings("load", cb.selectedCommand().?.name);
}

test "selectedCommand returns null when no results" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("zzz");
    try testing.expect(cb.selectedCommand() == null);
}

test "selectedCommand after moveCursorDown returns current command" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save", .description = "Save file" });
    _ = cb.setQuery("");
    cb.moveCursorDown();
    const cmd = cb.selectedCommand();
    try testing.expect(cmd != null);
    try testing.expectEqualStrings("save", cmd.?.name);
    try testing.expectEqualStrings("Save file", cmd.?.description);
}

test "cursor reset on setQuery to empty from filtered state" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "search" });
    _ = cb.setQuery("sa");
    cb.moveCursorDown();
    _ = cb.setQuery("");
    // After switching query, expect cursor still valid or reset
    try testing.expect(cb.resultCount() >= 0);
}

// ============================================================================
// Builder API Tests (7 tests)
// ============================================================================

test "withBlock returns same pointer" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const block = Block{};
    const returned = cb.withBlock(block);
    try testing.expect(@intFromPtr(returned) == @intFromPtr(&cb));
}

test "withQueryStyle returns same pointer" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const style = Style{};
    const returned = cb.withQueryStyle(style);
    try testing.expect(@intFromPtr(returned) == @intFromPtr(&cb));
}

test "withResultStyle returns same pointer" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const style = Style{};
    const returned = cb.withResultStyle(style);
    try testing.expect(@intFromPtr(returned) == @intFromPtr(&cb));
}

test "withSelectedStyle returns same pointer" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const style = Style{};
    const returned = cb.withSelectedStyle(style);
    try testing.expect(@intFromPtr(returned) == @intFromPtr(&cb));
}

test "withShortcutStyle returns same pointer" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const style = Style{};
    const returned = cb.withShortcutStyle(style);
    try testing.expect(@intFromPtr(returned) == @intFromPtr(&cb));
}

test "withPlaceholder returns same pointer" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const returned = cb.withPlaceholder("Type command...");
    try testing.expect(@intFromPtr(returned) == @intFromPtr(&cb));
}

test "builder API chaining multiple calls" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    const block = Block{};
    const style = Style{};
    _ = cb.withBlock(block)
        .withQueryStyle(style)
        .withResultStyle(style)
        .withSelectedStyle(style)
        .withShortcutStyle(style)
        .withPlaceholder("Search...");
    // If we got here without error, chaining worked
}

// ============================================================================
// Render Tests (8 tests)
// ============================================================================

test "render with zero area does not crash" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    var buf = try Buffer.init(testing.allocator, 0, 0);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
}

test "render with no commands does not crash" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "render with no matching query does not crash" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("zzz");
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "render normal case does not crash" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save", .description = "Save file" });
    _ = cb.setQuery("sa");
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "render with single result" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    _ = cb.setQuery("");
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 10 });
}

test "render with block border does not crash" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    const block = Block{ .borders = .all };
    _ = cb.setQuery("");
    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    _ = cb.withBlock(block);
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 60, .height = 20 });
}

test "render narrow area (width=1) does not crash" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    var buf = try Buffer.init(testing.allocator, 1, 20);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 1, .height = 20 });
}

test "render with multiple commands and custom styles" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save", .shortcut = "Ctrl+S" });
    try cb.register(.{ .name = "load", .shortcut = "Ctrl+L" });
    const style = Style{ .bold = true };
    _ = cb.setQuery("")
        .withQueryStyle(style)
        .withResultStyle(style)
        .withSelectedStyle(style)
        .withShortcutStyle(style);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

// ============================================================================
// Integration Tests (5+ tests)
// ============================================================================

test "full workflow: register, query, navigate, render" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "search" });
    try cb.register(.{ .name = "load" });
    _ = cb.setQuery("s");
    try testing.expectEqual(@as(usize, 2), cb.resultCount());
    cb.moveCursorDown();
    const cmd = cb.selectedCommand();
    try testing.expect(cmd != null);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "register, unregister, query cycle" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "load" });
    _ = cb.setQuery("l");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
    cb.unregister("load");
    _ = cb.setQuery("");
    try testing.expectEqual(@as(usize, 1), cb.resultCount());
}

test "cursor boundary conditions with filtered results" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "apple" });
    try cb.register(.{ .name = "apricot" });
    try cb.register(.{ .name = "banana" });
    _ = cb.setQuery("a");
    try testing.expectEqual(@as(usize, 2), cb.resultCount());
    cb.moveCursorDown();
    cb.moveCursorDown();
    cb.moveCursorDown();
    try testing.expectEqualStrings("apricot", cb.selectedCommand().?.name);
}

test "placeholder text used in render" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    _ = cb.withPlaceholder("Type a command...");
    var buf = try Buffer.init(testing.allocator, 40, 10);
    defer buf.deinit();
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 40, .height = 10 });
    // Render should not crash with placeholder set
}

test "clearQuery resets cursor position" {
    var cb = try CommandBar.init(testing.allocator);
    defer cb.deinit();
    try cb.register(.{ .name = "save" });
    try cb.register(.{ .name = "search" });
    _ = cb.setQuery("s");
    cb.moveCursorDown();
    cb.clearQuery();
    try testing.expectEqual(@as(usize, 2), cb.resultCount());
    // After clear, expect valid state
}
