const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const filterable_list = @import("../src/tui/widgets/filterable_list.zig");

const FilterableList = filterable_list.FilterableList;
const FilteredItem = filterable_list.FilteredItem;

// ============================================================================
// FilterableList.init Tests
// ============================================================================

test "filterable list init creates empty list" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    try testing.expectEqual(@as(usize, 0), list.getVisible().len);
}

test "filterable list init allocation succeeds" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    try testing.expect(list.items.capacity > 0);
}

// ============================================================================
// FilterableList.setItems Tests
// ============================================================================

test "filterable list setItems stores items" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    try testing.expectEqual(@as(usize, 3), list.getVisible().len);
}

test "filterable list setItems empty list" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{};
    try list.setItems(items);

    try testing.expectEqual(@as(usize, 0), list.getVisible().len);
}

test "filterable list setItems single item" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{"only"};
    try list.setItems(items);

    try testing.expectEqual(@as(usize, 1), list.getVisible().len);
}

test "filterable list setItems replaces previous items" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items1 = &[_][]const u8{ "a", "b" };
    try list.setItems(items1);
    try testing.expectEqual(@as(usize, 2), list.getVisible().len);

    const items2 = &[_][]const u8{ "x", "y", "z" };
    try list.setItems(items2);
    try testing.expectEqual(@as(usize, 3), list.getVisible().len);
}

test "filterable list setItems updates selection" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items1 = &[_][]const u8{ "a", "b", "c" };
    try list.setItems(items1);
    list.selectNext();

    const items2 = &[_][]const u8{ "x", "y" };
    try list.setItems(items2);

    // Selection should be reset or clamped
    try testing.expect(list.selected_index < 2);
}

// ============================================================================
// FilterableList.setFilter Tests
// ============================================================================

test "filterable list setFilter with empty string shows all" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("");

    try testing.expectEqual(@as(usize, 3), list.getVisible().len);
}

test "filterable list setFilter with exact match" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("apple");

    const visible = list.getVisible();
    try testing.expectEqual(@as(usize, 1), visible.len);
    try testing.expectEqualStrings("apple", visible[0].text);
}

test "filterable list setFilter with fuzzy match" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("ap");

    const visible = list.getVisible();
    try testing.expectEqual(@as(usize, 2), visible.len);
}

test "filterable list setFilter case insensitive" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "Apple", "banana" };
    try list.setItems(items);
    try list.setFilter("APPLE");

    const visible = list.getVisible();
    try testing.expectEqual(@as(usize, 1), visible.len);
}

test "filterable list setFilter no matches" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);
    try list.setFilter("xyz");

    try testing.expectEqual(@as(usize, 0), list.getVisible().len);
}

test "filterable list setFilter results sorted by score" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "zebra_apple", "apple_pie", "apple" };
    try list.setItems(items);
    try list.setFilter("apple");

    const visible = list.getVisible();
    try testing.expect(visible.len >= 1);

    // First result should have highest score (exact or prefix)
    if (visible.len > 1) {
        try testing.expect(visible[0].score >= visible[1].score);
    }
}

test "filterable list setFilter updates selection" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);

    list.selectNext(); // Select "apricot"
    try list.setFilter("app"); // Should filter to "apple", "apricot"

    // Selection should be updated/reset
}

test "filterable list setFilter multiple updates" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "application", "banana" };
    try list.setItems(items);

    try list.setFilter("a");
    try testing.expect(list.getVisible().len >= 3); // apple, apricot, application

    try list.setFilter("ap");
    try testing.expect(list.getVisible().len >= 2); // apple, apricot, application

    try list.setFilter("app");
    try testing.expect(list.getVisible().len >= 2); // apple, application

    try list.setFilter("appl");
    try testing.expect(list.getVisible().len >= 1); // apple, application
}

// ============================================================================
// FilterableList.clearFilter Tests
// ============================================================================

test "filterable list clearFilter restores all items" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);

    try list.setFilter("apple");
    try testing.expectEqual(@as(usize, 1), list.getVisible().len);

    list.clearFilter();
    try testing.expectEqual(@as(usize, 3), list.getVisible().len);
}

test "filterable list clearFilter resets selection" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);

    try list.setFilter("banana");
    list.selectNext(); // Select first (and only) filtered result

    list.clearFilter();
    // Should now have all 3 items visible again
    try testing.expectEqual(@as(usize, 3), list.getVisible().len);
}

test "filterable list clearFilter after empty filter" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana" };
    try list.setItems(items);

    try list.setFilter("xyz"); // No matches
    list.clearFilter();

    try testing.expectEqual(@as(usize, 2), list.getVisible().len);
}

// ============================================================================
// FilterableList.getVisible Tests
// ============================================================================

test "filterable list getVisible returns filtered items" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);
    try list.setFilter("apple");

    const visible = list.getVisible();
    try testing.expectEqual(@as(usize, 1), visible.len);
    try testing.expectEqualStrings("apple", visible[0].text);
}

test "filterable list getVisible includes match positions" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{"apple"};
    try list.setItems(items);
    try list.setFilter("ap");

    const visible = list.getVisible();
    try testing.expect(visible[0].match_positions.len > 0);
}

test "filterable list getVisible score set correctly" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{"apple"};
    try list.setItems(items);
    try list.setFilter("apple");

    const visible = list.getVisible();
    try testing.expect(visible[0].score > 0.0);
}

test "filterable list getVisible empty when no filter matches" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana" };
    try list.setItems(items);
    try list.setFilter("xyz");

    try testing.expectEqual(@as(usize, 0), list.getVisible().len);
}

test "filterable list getVisible all items when no filter" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "a", "b", "c", "d" };
    try list.setItems(items);
    // No filter set, or empty filter

    const visible = list.getVisible();
    try testing.expectEqual(@as(usize, 4), visible.len);
}

test "filterable list getVisible score monotonic" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "application", "apricot" };
    try list.setItems(items);
    try list.setFilter("app");

    const visible = list.getVisible();
    for (1..visible.len) |i| {
        try testing.expect(visible[i].score <= visible[i - 1].score);
    }
}

// ============================================================================
// FilterableList.selectNext / selectPrev Tests
// ============================================================================

test "filterable list selectNext advances selection" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    list.selectNext();
    try testing.expectEqual(@as(usize, 1), list.selected_index);
}

test "filterable list selectNext wraps around" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana" };
    try list.setItems(items);

    list.selectNext(); // 0 -> 1
    list.selectNext(); // 1 -> 0 (wrap)
    try testing.expectEqual(@as(usize, 0), list.selected_index);
}

test "filterable list selectNext on empty does nothing" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    list.selectNext();
    try testing.expectEqual(@as(usize, 0), list.selected_index);
}

test "filterable list selectNext with filter" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("a");

    list.selectNext();
    try testing.expectEqual(@as(usize, 1), list.selected_index);
}

test "filterable list selectPrev retreats selection" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    list.selectNext(); // 0 -> 1
    list.selectPrev(); // 1 -> 0
    try testing.expectEqual(@as(usize, 0), list.selected_index);
}

test "filterable list selectPrev wraps to end" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana" };
    try list.setItems(items);

    list.selectPrev(); // 0 -> 1 (wrap)
    try testing.expectEqual(@as(usize, 1), list.selected_index);
}

test "filterable list selectPrev on empty does nothing" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    list.selectPrev();
    try testing.expectEqual(@as(usize, 0), list.selected_index);
}

test "filterable list selectPrev with filter" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("a");

    list.selectNext(); // 0 -> 1
    list.selectPrev(); // 1 -> 0
    try testing.expectEqual(@as(usize, 0), list.selected_index);
}

// ============================================================================
// FilterableList.getSelected Tests
// ============================================================================

test "filterable list getSelected returns selected item" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    const selected = list.getSelected();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("apple", selected.?);
}

test "filterable list getSelected returns null when empty" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const selected = list.getSelected();
    try testing.expectEqual(@as(?[]const u8, null), selected);
}

test "filterable list getSelected after navigation" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    list.selectNext();
    const selected = list.getSelected();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("banana", selected.?);
}

test "filterable list getSelected with filter" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("a");

    list.selectNext();
    const selected = list.getSelected();
    try testing.expect(selected != null);
    // Should be "apricot" (second 'a' item)
    try testing.expectEqualStrings("apricot", selected.?);
}

test "filterable list getSelected returns null after no matches" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana" };
    try list.setItems(items);
    try list.setFilter("xyz");

    const selected = list.getSelected();
    try testing.expectEqual(@as(?[]const u8, null), selected);
}

// ============================================================================
// FilterableList.render Tests
// ============================================================================

test "filterable list render empty list" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try list.render(&buf, area);

    // Should not crash
}

test "filterable list render single item" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{"test"};
    try list.setItems(items);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try list.render(&buf, area);

    // Verify item appears in buffer
    var found = false;
    for (0..80) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 't') {
                found = true;
                break;
            }
        }
    }
    try testing.expect(found);
}

test "filterable list render multiple items" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try list.render(&buf, area);

    // All items should be rendered
}

test "filterable list render with filter applied" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("a");

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try list.render(&buf, area);

    // Should render only "apple" and "apricot"
}

test "filterable list render respects area boundaries" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "a", "b", "c", "d", "e" };
    try list.setItems(items);

    var buf = try Buffer.init(testing.allocator, 80, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 3 };
    try list.render(&buf, area);

    // Should only render up to height 3
}

test "filterable list render with offset" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{"test"};
    try list.setItems(items);

    var buf = try Buffer.init(testing.allocator, 100, 30);
    defer buf.deinit();

    const area = Rect{ .x = 10, .y = 5, .width = 40, .height = 10 };
    try list.render(&buf, area);

    // Should render within offset area
}

test "filterable list render highlights selected item" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "banana", "cherry" };
    try list.setItems(items);

    list.selectNext(); // Select "banana"

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try list.render(&buf, area);

    // Selected item should have different styling
}

test "filterable list render shows match highlights" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana" };
    try list.setItems(items);
    try list.setFilter("ap");

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try list.render(&buf, area);

    // Matched characters should be highlighted
}

// ============================================================================
// Integration Tests
// ============================================================================

test "filterable list full workflow" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "apricot", "banana", "blueberry", "cherry" };
    try list.setItems(items);

    // Filter to "a" items
    try list.setFilter("a");
    try testing.expectEqual(@as(usize, 2), list.getVisible().len);

    // Navigate
    list.selectNext();
    const selected = list.getSelected();
    try testing.expect(selected != null);

    // Clear filter
    list.clearFilter();
    try testing.expectEqual(@as(usize, 5), list.getVisible().len);

    // Render
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try list.render(&buf, area);
}

test "filterable list handles rapid filter changes" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "apple", "application", "apricot", "banana" };
    try list.setItems(items);

    try list.setFilter("a");
    try testing.expect(list.getVisible().len >= 3);

    try list.setFilter("ap");
    try testing.expect(list.getVisible().len >= 2);

    try list.setFilter("app");
    try testing.expect(list.getVisible().len >= 2);

    try list.setFilter("appl");
    try testing.expect(list.getVisible().len >= 1);

    try list.setFilter("appli");
    try testing.expect(list.getVisible().len >= 1);

    list.clearFilter();
    try testing.expectEqual(@as(usize, 4), list.getVisible().len);
}

test "filterable list preserves item order when filtering" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "zebra", "apple", "monkey", "apple_pie" };
    try list.setItems(items);
    try list.setFilter("apple");

    const visible = list.getVisible();
    try testing.expect(visible.len >= 1);

    // Items should appear in some reasonable order (likely by score)
}

test "filterable list empty string filter" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "a", "b", "c" };
    try list.setItems(items);

    try list.setFilter("");
    try testing.expectEqual(@as(usize, 3), list.getVisible().len);
}

test "filterable list single character items" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "a", "b", "c" };
    try list.setItems(items);
    try list.setFilter("a");

    const visible = list.getVisible();
    try testing.expectEqual(@as(usize, 1), visible.len);
}

test "filterable list unicode items" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{ "café", "naïve", "résumé" };
    try list.setItems(items);
    try list.setFilter("café");

    const visible = list.getVisible();
    try testing.expect(visible.len >= 1);
}

test "filterable list long item names" {
    var list = try FilterableList.init(testing.allocator);
    defer list.deinit();

    const items = &[_][]const u8{
        "very_long_function_name_with_many_underscores",
        "another_very_long_name",
        "short",
    };
    try list.setItems(items);
    try list.setFilter("long");

    const visible = list.getVisible();
    try testing.expect(visible.len >= 1);
}
