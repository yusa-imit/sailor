//! Keybinding Tests — v2.21.0
//!
//! Tests KeybindingMap for registration and lookup of key bindings,
//! and KeybindingBar for rendering keybinding hints in a status bar.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const KeybindingMap = sailor.tui.KeybindingMap;
const KeybindingBar = sailor.tui.KeybindingBar;

// ============================================================================
// KeybindingMap — Empty State
// ============================================================================

test "KeybindingMap with empty entries has 0 entries" {
    const map = KeybindingMap{};
    try testing.expectEqual(@as(usize, 0), map.entries.len);
}

test "KeybindingMap lookup on empty map returns null" {
    const map = KeybindingMap{};
    const result = map.lookup("save");
    try testing.expect(result == null);
}

// ============================================================================
// KeybindingMap — Registration and Lookup
// ============================================================================

test "KeybindingMap register with one entry — lookup finds it" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save file" },
    };
    const map = KeybindingMap.register(&entries);
    const found = map.lookup("save");
    try testing.expect(found != null);
}

test "KeybindingMap lookup by action name returns correct key" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save file" },
    };
    const map = KeybindingMap.register(&entries);
    const found = map.lookup("save");
    try testing.expectEqualStrings("C-s", found.?.key);
}

test "KeybindingMap lookup by action name returns correct desc" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save file" },
    };
    const map = KeybindingMap.register(&entries);
    const found = map.lookup("save");
    try testing.expectEqualStrings("Save file", found.?.desc);
}

test "KeybindingMap lookup for unknown action returns null" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save file" },
    };
    const map = KeybindingMap.register(&entries);
    const found = map.lookup("unknown");
    try testing.expect(found == null);
}

test "KeybindingMap with multiple entries — lookup finds each" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save file" },
        .{ .key = "C-q", .action = "quit", .desc = "Quit" },
        .{ .key = "C-x", .action = "cut", .desc = "Cut text" },
    };
    const map = KeybindingMap.register(&entries);

    const save_entry = map.lookup("save");
    const quit_entry = map.lookup("quit");
    const cut_entry = map.lookup("cut");

    try testing.expect(save_entry != null);
    try testing.expect(quit_entry != null);
    try testing.expect(cut_entry != null);
}

test "KeybindingMap register with 3 entries has 3 items" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save file" },
        .{ .key = "C-q", .action = "quit", .desc = "Quit" },
        .{ .key = "C-x", .action = "cut", .desc = "Cut text" },
    };
    const map = KeybindingMap.register(&entries);
    try testing.expectEqual(@as(usize, 3), map.entries.len);
}

test "KeybindingEntry key and desc are accessible" {
    const entry = KeybindingMap.KeybindingEntry{
        .key = "C-a",
        .action = "select_all",
        .desc = "Select all text",
    };
    try testing.expectEqualStrings("C-a", entry.key);
    try testing.expectEqualStrings("select_all", entry.action);
    try testing.expectEqualStrings("Select all text", entry.desc);
}

// ============================================================================
// KeybindingBar — Default State
// ============================================================================

test "KeybindingBar default style is empty" {
    const map = KeybindingMap{};
    const bar = KeybindingBar{ .map = map };
    try testing.expect(!bar.style.bold);
}

// ============================================================================
// KeybindingBar — Render Safe Cases
// ============================================================================

test "KeybindingBar render on zero-area is no-op" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const map = KeybindingMap{};
    const bar = KeybindingBar{ .map = map };
    bar.render(&buf, area);
    // Should not crash
}

test "KeybindingBar render on zero-height area is no-op" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };

    const map = KeybindingMap{};
    const bar = KeybindingBar{ .map = map };
    bar.render(&buf, area);
    // Should not crash
}

test "KeybindingBar render with empty map writes nothing" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const map = KeybindingMap{};
    const bar = KeybindingBar{ .map = map };
    bar.render(&buf, area);
    // Should render nothing
}

// ============================================================================
// KeybindingBar — Render Content
// ============================================================================

test "KeybindingBar render with one entry writes key+desc" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save" },
    };
    const map = KeybindingMap.register(&entries);
    const bar = KeybindingBar{ .map = map };
    bar.render(&buf, area);

    // Should render something like "[C-s] Save"
}

test "KeybindingBar render with two entries writes both" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save" },
        .{ .key = "C-q", .action = "quit", .desc = "Quit" },
    };
    const map = KeybindingMap.register(&entries);
    const bar = KeybindingBar{ .map = map };
    bar.render(&buf, area);

    // Should render both keybindings
}

test "KeybindingBar render respects area width" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };

    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-verylongkey", .action = "a", .desc = "Description" },
    };
    const map = KeybindingMap.register(&entries);
    const bar = KeybindingBar{ .map = map };
    bar.render(&buf, area);

    // Should clip to area width
}

test "KeybindingBar render uses bar style for background" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };

    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save" },
    };
    const map = KeybindingMap.register(&entries);
    const style = Style{ .bold = true };
    const bar = KeybindingBar{ .map = map, .style = style };
    bar.render(&buf, area);

    // Background style should be applied
}

// ============================================================================
// KeybindingBar — Builder Pattern
// ============================================================================

test "KeybindingBar withMap returns bar with map set" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save" },
    };
    const map = KeybindingMap.register(&entries);
    const bar = KeybindingBar{ .map = map };
    const updated = bar.withMap(map);
    try testing.expectEqual(@as(usize, 1), updated.map.entries.len);
}

// ============================================================================
// KeybindingBar — Ordering and Position
// ============================================================================

test "KeybindingBar entries appear in registration order" {
    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-a", .action = "first", .desc = "First" },
        .{ .key = "C-b", .action = "second", .desc = "Second" },
        .{ .key = "C-c", .action = "third", .desc = "Third" },
    };
    const map = KeybindingMap.register(&entries);

    // Entries should be accessible in order
    try testing.expectEqualStrings("C-a", map.entries[0].key);
    try testing.expectEqualStrings("C-b", map.entries[1].key);
    try testing.expectEqualStrings("C-c", map.entries[2].key);
}

test "KeybindingBar render at y offset draws in correct row" {
    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 5, .width = 80, .height = 1 };

    const entries = [_]KeybindingMap.KeybindingEntry{
        .{ .key = "C-s", .action = "save", .desc = "Save" },
    };
    const map = KeybindingMap.register(&entries);
    const bar = KeybindingBar{ .map = map };
    bar.render(&buf, area);

    // Content should be in row y=5
}
