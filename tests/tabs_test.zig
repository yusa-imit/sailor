const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Tabs = sailor.tui.widgets.Tabs;
const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const Color = sailor.tui.Color;

test "Tabs initialization with titles" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles);

    try testing.expectEqual(@as(usize, 3), tabs.titles.len);
    try testing.expectEqual(@as(usize, 0), tabs.selected);
    try testing.expectEqualStrings(" │ ", tabs.divider);
}

test "Tabs initialization with empty titles" {
    const titles = [_][]const u8{};
    const tabs = Tabs.init(&titles);

    try testing.expectEqual(@as(usize, 0), tabs.titles.len);
    try testing.expectEqual(@as(usize, 0), tabs.selected);
}

test "Tabs.withSelected sets selected index" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles).withSelected(1);

    try testing.expectEqual(@as(usize, 1), tabs.selected);
}

test "Tabs.withSelected clamps to valid range" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs.init(&titles).withSelected(10);

    // Should clamp to last index
    try testing.expectEqual(@as(usize, 2), tabs.selected);
}

test "Tabs.withSelected clamps to zero for empty titles" {
    const titles = [_][]const u8{};
    const tabs = Tabs.init(&titles).withSelected(5);

    try testing.expectEqual(@as(usize, 0), tabs.selected);
}

test "Tabs.withSelected preserves immutability" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const original = Tabs.init(&titles);
    const modified = original.withSelected(1);

    try testing.expectEqual(@as(usize, 0), original.selected);
    try testing.expectEqual(@as(usize, 1), modified.selected);
}

test "Tabs.withDivider sets divider string" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles).withDivider(" | ");

    try testing.expectEqualStrings(" | ", tabs.divider);
}

test "Tabs.withSelectedStyle sets selected tab style" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const style = Style{ .fg = Color.red };
    const tabs = Tabs.init(&titles).withSelectedStyle(style);

    try testing.expectEqual(Color.red, tabs.selected_style.fg);
}

test "Tabs.withNormalStyle sets normal tab style" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const style = Style{ .fg = Color.green };
    const tabs = Tabs.init(&titles).withNormalStyle(style);

    try testing.expectEqual(Color.green, tabs.normal_style.fg);
}

test "Tabs.withBlock sets block border" {
    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const blk = Block{};
    const tabs = Tabs.init(&titles).withBlock(blk);

    try testing.expect(tabs.block != null);
}

test "Tabs render single tab" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 3);
    defer buf.deinit();

    const titles = [_][]const u8{"Home"};
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    tabs.render(&buf, area);

    // Should render tab title
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'm'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
}

test "Tabs render multiple tabs with divider" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "Home", "Edit", "View" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 3 };
    tabs.render(&buf, area);

    // Check first tab
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'o'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'm'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);

    // Check divider (default is " │ ")
    try testing.expectEqual(@as(u21, ' '), buf.get(4, 0).?.char);
    try testing.expectEqual(@as(u21, '│'), buf.get(5, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(6, 0).?.char);

    // Check second tab (at position 9: "Home"=4 + divider_bytes=5 = 9)
    try testing.expectEqual(@as(u21, 'E'), buf.get(9, 0).?.char);
    try testing.expectEqual(@as(u21, 'd'), buf.get(10, 0).?.char);
    try testing.expectEqual(@as(u21, 'i'), buf.get(11, 0).?.char);
    try testing.expectEqual(@as(u21, 't'), buf.get(12, 0).?.char);
}

test "Tabs render with custom divider" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B", "C" };
    const tabs = Tabs.init(&titles).withDivider(" / ");

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    tabs.render(&buf, area);

    try testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, '/'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, 'B'), buf.get(4, 0).?.char);
}

test "Tabs render selected tab highlighted" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const selected_style = Style{ .fg = Color.red, .bold = true };
    const normal_style = Style{ .fg = Color.white };

    const tabs = Tabs.init(&titles)
        .withSelected(1)
        .withSelectedStyle(selected_style)
        .withNormalStyle(normal_style);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 1 };
    tabs.render(&buf, area);

    // First tab (normal style)
    try testing.expectEqual(Color.white, buf.get(0, 0).?.style.fg);

    // Second tab (selected, should have different style)
    // Position after "Tab1" (4) + divider bytes (5) = 9
    try testing.expectEqual(Color.red, buf.get(9, 0).?.style.fg);
    try testing.expect(buf.get(9, 0).?.style.bold);
}

test "Tabs render with block border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const blk = (Block{}).withBorders(.all).withTitle("Navigation", .top_left);
    const tabs = Tabs.init(&titles).withBlock(blk);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    tabs.render(&buf, area);

    // Block should be rendered
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Tabs should be inside block (at y=1, x=1)
    try testing.expectEqual(@as(u21, 'T'), buf.get(1, 1).?.char);
}

test "Tabs render truncates when too wide" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "VeryLongTab1", "VeryLongTab2", "Tab3" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    tabs.render(&buf, area);

    // Should render first tab and truncate
    try testing.expectEqual(@as(u21, 'V'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'r'), buf.get(2, 0).?.char);
}

test "Tabs render empty area does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 1 };
    tabs.render(&buf, area);

    // Should not crash
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Tabs render zero height does nothing" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    tabs.render(&buf, area);

    // Should not crash
}

test "Tabs render empty titles" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{};
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    tabs.render(&buf, area);

    // Should not crash, buffer remains default
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Tabs render with offset area position" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 30, 10);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 5, .y = 3, .width = 15, .height = 1 };
    tabs.render(&buf, area);

    // Should render at offset position
    try testing.expectEqual(@as(u21, 'T'), buf.get(5, 3).?.char);
    try testing.expectEqual(@as(u21, 'a'), buf.get(6, 3).?.char);
}

test "Tabs render single character tabs" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B", "C" };
    const tabs = Tabs.init(&titles).withSelected(1);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 1 };
    tabs.render(&buf, area);

    try testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).?.char);
    // Divider is " │ " (5 bytes, advances x by 5): "A" (1) + divider (5) = 6
    try testing.expectEqual(@as(u21, 'B'), buf.get(6, 0).?.char);
}

test "Tabs render only renders first line" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    tabs.render(&buf, area);

    // Tabs should only be on first line (y=0)
    try testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).?.char);

    // Other lines should be empty
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 1).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 2).?.char);
}

test "Tabs builder chain preserves immutability" {
    const titles = [_][]const u8{ "A", "B", "C" };
    const original = Tabs.init(&titles);

    const modified = original
        .withSelected(2)
        .withDivider(" | ")
        .withSelectedStyle(.{ .fg = Color.blue });

    try testing.expectEqual(@as(usize, 0), original.selected);
    try testing.expectEqualStrings(" │ ", original.divider);

    try testing.expectEqual(@as(usize, 2), modified.selected);
    try testing.expectEqualStrings(" | ", modified.divider);
}

test "Tabs render all tabs fit in area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 50, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Home", "Settings", "About", "Help" };
    const tabs = Tabs.init(&titles).withSelected(2);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 1 };
    tabs.render(&buf, area);

    // All tabs should fit: divider is 5 bytes (advances x by 5)
    try testing.expectEqual(@as(u21, 'H'), buf.get(0, 0).?.char); // Home at 0
    // Settings after divider: "Home" (4) + divider (5) = 9
    try testing.expectEqual(@as(u21, 'S'), buf.get(9, 0).?.char);
    // About (selected) after another divider: 9 + "Settings" (8) + divider (5) = 22
    try testing.expectEqual(@as(u21, 'A'), buf.get(22, 0).?.char);
    // Help after another divider: 22 + "About" (5) + divider (5) = 32
    try testing.expectEqual(@as(u21, 'H'), buf.get(32, 0).?.char);
}

test "Tabs render divider not rendered after last tab" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B", "C" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    tabs.render(&buf, area);

    // Last tab should not have divider after it
    // divider " │ " is 5 bytes; renderer advances x by byte count (not cell count)
    // "A"(1) + divider(5) = 6, "B"(1) + divider(5) = 12, "C" at 12
    try testing.expectEqual(@as(u21, 'C'), buf.get(12, 0).?.char);
}

test "Tabs render with selected tab at different positions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B", "C" };
    const selected_style = Style{ .bold = true };

    const tabs = Tabs.init(&titles)
        .withSelected(2)
        .withSelectedStyle(selected_style);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    tabs.render(&buf, area);

    // Last tab ("C") should have selected style
    // A(0) + divider(5) → B(6) + divider(5) → C(12)
    try testing.expect(buf.get(12, 0).?.style.bold);
}

test "Tabs render empty tab title edge case" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "", "B" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    tabs.render(&buf, area);

    // First tab is empty, divider should follow immediately
    try testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, '│'), buf.get(1, 0).?.char);
}

test "Tabs render partial divider when truncated" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 8, 1);
    defer buf.deinit();

    const titles = [_][]const u8{ "Tab1", "Tab2" };
    const tabs = Tabs.init(&titles);

    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 1 };
    tabs.render(&buf, area);

    // "Tab1" (4) + divider " │ " (3) = 7 chars total
    try testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'a'), buf.get(1, 0).?.char);
    try testing.expectEqual(@as(u21, 'b'), buf.get(2, 0).?.char);
    try testing.expectEqual(@as(u21, '1'), buf.get(3, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buf.get(4, 0).?.char);
}
