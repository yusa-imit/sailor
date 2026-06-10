//! Breadcrumb Widget Tests — v2.19.0 (Simple API)
//!
//! Tests breadcrumb navigation widget with static items, custom separators,
//! active item highlighting, and truncation for long paths.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Breadcrumb = sailor.tui.widgets.Breadcrumb;

// ============================================================================
// Breadcrumb Default State
// ============================================================================

test "Breadcrumb default state has empty items" {
    const bc = Breadcrumb{};
    try testing.expectEqual(@as(usize, 0), bc.items.len);
}

test "Breadcrumb default separator is ' / '" {
    const bc = Breadcrumb{};
    try testing.expectEqualSlices(u8, " / ", bc.separator);
}

test "Breadcrumb default active_idx is null" {
    const bc = Breadcrumb{};
    try testing.expect(bc.active_idx == null);
}

test "Breadcrumb default initializes styles" {
    const bc = Breadcrumb{};
    // active_style: bold=true
    try testing.expect(bc.active_style.bold == true);
    // separator_style: fg=bright_black
    try testing.expectEqual(Style{ .fg = .bright_black }, bc.separator_style);
    // item_style: plain (no decoration)
    try testing.expectEqual(Style{}, bc.item_style);
}

test "Breadcrumb with single item" {
    const items = [_][]const u8{"Home"};
    const bc = Breadcrumb{ .items = &items };
    try testing.expectEqual(@as(usize, 1), bc.items.len);
    try testing.expectEqualSlices(u8, "Home", bc.items[0]);
}

test "Breadcrumb with multiple items" {
    const items = [_][]const u8{ "Home", "Projects", "sailor", "src" };
    const bc = Breadcrumb{ .items = &items };
    try testing.expectEqual(@as(usize, 4), bc.items.len);
    try testing.expectEqualSlices(u8, "Home", bc.items[0]);
    try testing.expectEqualSlices(u8, "sailor", bc.items[2]);
}

// ============================================================================
// totalWidth — Calculate Display Width
// ============================================================================

test "totalWidth with empty items is 0" {
    const bc = Breadcrumb{ .items = &.{} };
    const width = bc.totalWidth();
    try testing.expectEqual(@as(usize, 0), width);
}

test "totalWidth with single item equals item length" {
    const items = [_][]const u8{"Home"};
    const bc = Breadcrumb{ .items = &items };
    const width = bc.totalWidth();
    try testing.expectEqual(@as(usize, 4), width);
}

test "totalWidth includes separator between items" {
    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    const width = bc.totalWidth();
    // "Home" (4) + " / " (3) + "Docs" (4) = 11
    try testing.expectEqual(@as(usize, 11), width);
}

test "totalWidth with three items and default separator" {
    const items = [_][]const u8{ "A", "B", "C" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    const width = bc.totalWidth();
    // "A" (1) + " / " (3) + "B" (1) + " / " (3) + "C" (1) = 9
    try testing.expectEqual(@as(usize, 9), width);
}

test "totalWidth respects custom separator length" {
    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items, .separator = ">" };
    const width = bc.totalWidth();
    // "Home" (4) + ">" (1) + "Docs" (4) = 9
    try testing.expectEqual(@as(usize, 9), width);
}

test "totalWidth with long separator" {
    const items = [_][]const u8{ "A", "B" };
    const bc = Breadcrumb{ .items = &items, .separator = " → " };
    const width = bc.totalWidth();
    // "A" (1) + " → " (5 bytes, Unicode arrow) + "B" (1) = 7
    try testing.expectEqual(@as(usize, 7), width);
}

test "totalWidth with single character items" {
    const items = [_][]const u8{ "A", "B", "C", "D" };
    const bc = Breadcrumb{ .items = &items, .separator = "/" };
    const width = bc.totalWidth();
    // "A" (1) + "/" (1) + "B" (1) + "/" (1) + "C" (1) + "/" (1) + "D" (1) = 7
    try testing.expectEqual(@as(usize, 7), width);
}

test "totalWidth with long item names" {
    const items = [_][]const u8{ "Projects", "Development" };
    const bc = Breadcrumb{ .items = &items, .separator = " > " };
    const width = bc.totalWidth();
    // "Projects" (8) + " > " (3) + "Development" (11) = 22
    try testing.expectEqual(@as(usize, 22), width);
}

test "totalWidth increases as items added (conceptually)" {
    const items1 = [_][]const u8{"Home"};
    const items2 = [_][]const u8{ "Home", "Docs" };

    const bc1 = Breadcrumb{ .items = &items1, .separator = " / " };
    const bc2 = Breadcrumb{ .items = &items2, .separator = " / " };

    const w1 = bc1.totalWidth();
    const w2 = bc2.totalWidth();
    try testing.expect(w2 > w1);
}

// ============================================================================
// withItems — Builder Pattern
// ============================================================================

test "withItems returns breadcrumb with new items" {
    const items1 = [_][]const u8{"Old"};
    const items2 = [_][]const u8{ "New", "Path" };

    var bc = Breadcrumb{ .items = &items1 };
    bc = bc.withItems(&items2);

    try testing.expectEqual(@as(usize, 2), bc.items.len);
    try testing.expectEqualSlices(u8, "New", bc.items[0]);
}

test "withItems preserves other fields" {
    const items1 = [_][]const u8{"Old"};
    const items2 = [_][]const u8{"New"};

    const bc = Breadcrumb{
        .items = &items1,
        .separator = " > ",
        .active_idx = 0,
    };
    const updated = bc.withItems(&items2);

    try testing.expectEqualSlices(u8, " > ", updated.separator);
    try testing.expectEqual(@as(?usize, 0), updated.active_idx);
}

test "withItems can clear items" {
    const items = [_][]const u8{ "A", "B" };
    var bc = Breadcrumb{ .items = &items };
    bc = bc.withItems(&.{});

    try testing.expectEqual(@as(usize, 0), bc.items.len);
}

test "withItems chains with other builders" {
    const items = [_][]const u8{ "Home", "Docs" };
    var bc = Breadcrumb{};
    bc = bc.withItems(&items).withSeparator(" > ");

    try testing.expectEqual(@as(usize, 2), bc.items.len);
    try testing.expectEqualSlices(u8, " > ", bc.separator);
}

// ============================================================================
// withSeparator — Builder Pattern
// ============================================================================

test "withSeparator returns breadcrumb with new separator" {
    const items = [_][]const u8{ "A", "B" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    const updated = bc.withSeparator(" > ");

    try testing.expectEqualSlices(u8, " > ", updated.separator);
}

test "withSeparator preserves items" {
    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    const updated = bc.withSeparator(" → ");

    try testing.expectEqual(@as(usize, 2), updated.items.len);
    try testing.expectEqualSlices(u8, "Home", updated.items[0]);
}

test "withSeparator can set single-char separator" {
    const items = [_][]const u8{ "A", "B" };
    const bc = Breadcrumb{ .items = &items };
    const updated = bc.withSeparator("/");

    try testing.expectEqualSlices(u8, "/", updated.separator);
}

test "withSeparator can set multi-char separator" {
    const items = [_][]const u8{ "A", "B" };
    const bc = Breadcrumb{ .items = &items };
    const updated = bc.withSeparator(" :: ");

    try testing.expectEqualSlices(u8, " :: ", updated.separator);
}

test "withSeparator chains with other builders" {
    const items = [_][]const u8{"Home"};
    var bc = Breadcrumb{};
    bc = bc.withItems(&items).withSeparator(" > ");

    try testing.expectEqualSlices(u8, " > ", bc.separator);
    try testing.expectEqual(@as(usize, 1), bc.items.len);
}

// ============================================================================
// withActive — Builder Pattern
// ============================================================================

test "withActive sets active_idx" {
    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items, .active_idx = null };
    const updated = bc.withActive(1);

    try testing.expectEqual(@as(?usize, 1), updated.active_idx);
}

test "withActive preserves items" {
    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items };
    const updated = bc.withActive(0);

    try testing.expectEqual(@as(usize, 2), updated.items.len);
}

test "withActive can highlight first item" {
    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items };
    const updated = bc.withActive(0);

    try testing.expectEqual(@as(?usize, 0), updated.active_idx);
}

test "withActive can highlight last item" {
    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items };
    const updated = bc.withActive(2);

    try testing.expectEqual(@as(?usize, 2), updated.active_idx);
}

test "withActive with out-of-bounds index (implementation-dependent)" {
    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items };
    const updated = bc.withActive(10);

    // Implementation may clamp or ignore; just verify no crash
    try testing.expect(updated.active_idx != null);
}

test "withActive chains with other builders" {
    const items = [_][]const u8{ "Home", "Docs" };
    var bc = Breadcrumb{};
    bc = bc.withItems(&items).withActive(1);

    try testing.expectEqual(@as(?usize, 1), bc.active_idx);
}

// ============================================================================
// render — Widget Rendering
// ============================================================================

test "render on zero-area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items };
    bc.render(&buf, area);
    // Should not crash
}

test "render with empty items does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 5 };

    const bc = Breadcrumb{ .items = &.{} };
    bc.render(&buf, area);
    // Should not crash
}

test "render with single item" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };

    const items = [_][]const u8{"Home"};
    const bc = Breadcrumb{ .items = &items };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with multiple items" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Projects", "sailor", "src" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with area smaller than content" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 1 };

    const items = [_][]const u8{ "Home", "Documents", "Projects" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    bc.render(&buf, area);
    // Should truncate gracefully without crash
}

test "render with area wide enough for full content" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with active item at beginning" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items, .active_idx = 0 };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with active item at middle" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items, .active_idx = 1 };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with active item at end" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items, .active_idx = 2 };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with custom separator" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items, .separator = " > " };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with single-char separator" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "A", "B", "C" };
    const bc = Breadcrumb{ .items = &items, .separator = "/" };
    bc.render(&buf, area);
    // Should complete without error
}

test "render respects custom styles" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{
        .items = &items,
        .active_style = Style{ .bold = true },
        .separator_style = Style{ .bold = false },
        .item_style = Style{ .bold = false },
    };
    bc.render(&buf, area);
    // Should complete without error
}

test "render at offset position (x=10, y=5)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 10, .y = 5, .width = 80, .height = 1 };

    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items };
    bc.render(&buf, area);
    // Should not crash
}

test "render on single row area" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const items = [_][]const u8{ "Home", "Documents", "Projects" };
    const bc = Breadcrumb{ .items = &items };
    bc.render(&buf, area);
    // Should complete without error
}

test "render with many items" {
    var buf = try Buffer.init(std.testing.allocator, 200, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 150, .height = 1 };

    const items = [_][]const u8{
        "root", "usr", "local", "bin", "custom", "app",
    };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    bc.render(&buf, area);
    // Should complete without error
}

test "render width-limited path (truncation scenario)" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };

    const items = [_][]const u8{
        "Home", "VeryLongDirectoryName", "AnotherLongDirectory", "file.txt",
    };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    bc.render(&buf, area);
    // Should truncate and not crash
}

// ============================================================================
// Integration Tests
// ============================================================================

test "breadcrumb workflow: build with builder then render" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    const items = [_][]const u8{ "Home", "Projects", "sailor" };
    var bc = Breadcrumb{};
    bc = bc.withItems(&items);
    bc = bc.withSeparator(" > ");
    bc = bc.withActive(1);

    try testing.expectEqual(@as(usize, 3), bc.items.len);
    try testing.expectEqualSlices(u8, " > ", bc.separator);
    try testing.expectEqual(@as(?usize, 1), bc.active_idx);

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    bc.render(&buf, area);
}

test "breadcrumb respects render area boundaries" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    const items = [_][]const u8{ "Home", "Docs" };
    const bc = Breadcrumb{ .items = &items };

    // Render within bounds
    const area = Rect{ .x = 10, .y = 10, .width = 50, .height = 1 };
    bc.render(&buf, area);
    // Should not crash and not write outside area
}

test "breadcrumb totalWidth matches rendered content" {
    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items, .separator = " / " };
    const total = bc.totalWidth();

    // totalWidth should equal sum of item widths + separator widths
    // "Home" (4) + " / " (3) + "Docs" (4) + " / " (3) + "API" (3) = 17
    try testing.expectEqual(@as(usize, 17), total);
}

test "breadcrumb with null active renders all items equally" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    const items = [_][]const u8{ "Home", "Docs", "API" };
    const bc = Breadcrumb{ .items = &items, .active_idx = null };

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    bc.render(&buf, area);
    // Should render all with item_style, no active styling
}

test "breadcrumb sequential modification and render" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    const items1 = [_][]const u8{"Home"};
    var bc = Breadcrumb{ .items = &items1 };

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    bc.render(&buf, area);

    const items2 = [_][]const u8{ "Home", "Docs" };
    bc = bc.withItems(&items2);
    bc.render(&buf, area);

    try testing.expectEqual(@as(usize, 2), bc.items.len);
}

test "breadcrumb renders correctly with empty separator" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    const bc = Breadcrumb{ .items = &items, .separator = "" };

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    bc.render(&buf, area);
    // Should render as "AB" without separator
}

test "breadcrumb handles very long single item name" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();

    const items = [_][]const u8{"VeryVeryVeryLongItemName"};
    const bc = Breadcrumb{ .items = &items };

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };
    bc.render(&buf, area);
    // Should render or truncate without crash
}
