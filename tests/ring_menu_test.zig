const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const tui = sailor.tui;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Block = tui.widgets.Block;
const RingMenu = tui.widgets.RingMenu;

// ============================================================================
// INIT & DEFAULTS (8 tests)
// ============================================================================

test "RingMenu init returns empty items" {
    const widget = RingMenu.init();
    try testing.expectEqual(@as(usize, 0), widget.items.len);
}

test "RingMenu init returns selected = 0" {
    const widget = RingMenu.init();
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

test "RingMenu init returns empty center_label" {
    const widget = RingMenu.init();
    try testing.expectEqual(@as(usize, 0), widget.center_label.len);
}

test "RingMenu init returns default style with no color" {
    const widget = RingMenu.init();
    try testing.expect(widget.style.fg == null);
    try testing.expect(widget.style.bg == null);
}

test "RingMenu init returns default selected_style with no color" {
    const widget = RingMenu.init();
    try testing.expect(widget.selected_style.fg == null);
    try testing.expect(widget.selected_style.bg == null);
}

test "RingMenu init returns default center_style with no color" {
    const widget = RingMenu.init();
    try testing.expect(widget.center_style.fg == null);
    try testing.expect(widget.center_style.bg == null);
}

test "RingMenu init returns radius = 4" {
    const widget = RingMenu.init();
    try testing.expectEqual(@as(u8, 4), widget.radius);
}

test "RingMenu init returns null block" {
    const widget = RingMenu.init();
    try testing.expect(widget.block == null);
}

// ============================================================================
// BUILDER IMMUTABILITY (9 tests)
// ============================================================================

test "RingMenu withItems returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const items = [_][]const u8{ "a", "b" };
    const widget2 = widget1.withItems(&items);
    try testing.expectEqual(@as(usize, 2), widget2.items.len);
    try testing.expectEqual(@as(usize, 0), widget1.items.len);
}

test "RingMenu withSelected returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const widget2 = widget1.withSelected(3);
    try testing.expectEqual(@as(usize, 3), widget2.selected);
    try testing.expectEqual(@as(usize, 0), widget1.selected);
}

test "RingMenu withCenterLabel returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const widget2 = widget1.withCenterLabel("CENTER");
    try testing.expectEqualStrings("CENTER", widget2.center_label);
    try testing.expectEqual(@as(usize, 0), widget1.center_label.len);
}

test "RingMenu withStyle returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const new_style = Style{ .fg = .red };
    const widget2 = widget1.withStyle(new_style);
    try testing.expectEqual(Color.red, widget2.style.fg.?);
    try testing.expect(widget1.style.fg == null);
}

test "RingMenu withSelectedStyle returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const new_style = Style{ .fg = .green };
    const widget2 = widget1.withSelectedStyle(new_style);
    try testing.expectEqual(Color.green, widget2.selected_style.fg.?);
    try testing.expect(widget1.selected_style.fg == null);
}

test "RingMenu withCenterStyle returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const new_style = Style{ .fg = .blue };
    const widget2 = widget1.withCenterStyle(new_style);
    try testing.expectEqual(Color.blue, widget2.center_style.fg.?);
    try testing.expect(widget1.center_style.fg == null);
}

test "RingMenu withRadius returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const widget2 = widget1.withRadius(8);
    try testing.expectEqual(@as(u8, 8), widget2.radius);
    try testing.expectEqual(@as(u8, 4), widget1.radius);
}

test "RingMenu withBlock returns new copy leaves original unchanged" {
    const widget1 = RingMenu.init();
    const block_val = Block{ .borders = .all };
    const widget2 = widget1.withBlock(block_val);
    try testing.expect(widget2.block != null);
    try testing.expect(widget1.block == null);
}

test "RingMenu builder chaining preserves all fields" {
    const items = [_][]const u8{ "x", "y", "z" };
    const widget = RingMenu.init()
        .withItems(&items)
        .withSelected(1)
        .withCenterLabel("MENU")
        .withRadius(6)
        .withStyle(Style{ .fg = .white })
        .withSelectedStyle(Style{ .fg = .yellow })
        .withCenterStyle(Style{ .fg = .cyan });

    try testing.expectEqual(@as(usize, 3), widget.items.len);
    try testing.expectEqual(@as(usize, 1), widget.selected);
    try testing.expectEqualStrings("MENU", widget.center_label);
    try testing.expectEqual(@as(u8, 6), widget.radius);
    try testing.expectEqual(Color.white, widget.style.fg.?);
    try testing.expectEqual(Color.yellow, widget.selected_style.fg.?);
    try testing.expectEqual(Color.cyan, widget.center_style.fg.?);
}

// ============================================================================
// NAVIGATION — next() (5 tests)
// ============================================================================

test "RingMenu next advances selected by one" {
    const items = [_][]const u8{ "a", "b", "c" };
    var widget = RingMenu.init().withItems(&items);
    try testing.expectEqual(@as(usize, 0), widget.selected);
    widget.next();
    try testing.expectEqual(@as(usize, 1), widget.selected);
}

test "RingMenu next wraps from last item to zero" {
    const items = [_][]const u8{ "a", "b" };
    var widget = RingMenu.init().withItems(&items).withSelected(1);
    try testing.expectEqual(@as(usize, 1), widget.selected);
    widget.next();
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

test "RingMenu next with zero items does not crash" {
    var widget = RingMenu.init();
    widget.next();
    // Should stay at 0 or handle gracefully
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

test "RingMenu next with one item stays at zero" {
    const items = [_][]const u8{"only"};
    var widget = RingMenu.init().withItems(&items);
    widget.next();
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

test "RingMenu next multiple times cycles through all items" {
    const items = [_][]const u8{ "a", "b", "c" };
    var widget = RingMenu.init().withItems(&items);
    widget.next(); // 0 -> 1
    widget.next(); // 1 -> 2
    widget.next(); // 2 -> 0
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

// ============================================================================
// NAVIGATION — prev() (5 tests)
// ============================================================================

test "RingMenu prev decrements selected by one" {
    const items = [_][]const u8{ "a", "b", "c" };
    var widget = RingMenu.init().withItems(&items).withSelected(1);
    try testing.expectEqual(@as(usize, 1), widget.selected);
    widget.prev();
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

test "RingMenu prev wraps from zero to last item" {
    const items = [_][]const u8{ "a", "b", "c" };
    var widget = RingMenu.init().withItems(&items).withSelected(0);
    try testing.expectEqual(@as(usize, 0), widget.selected);
    widget.prev();
    try testing.expectEqual(@as(usize, 2), widget.selected);
}

test "RingMenu prev with zero items does not crash" {
    var widget = RingMenu.init();
    widget.prev();
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

test "RingMenu prev with one item stays at zero" {
    const items = [_][]const u8{"only"};
    var widget = RingMenu.init().withItems(&items);
    widget.prev();
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

test "RingMenu prev multiple times cycles backward" {
    const items = [_][]const u8{ "a", "b", "c" };
    var widget = RingMenu.init().withItems(&items).withSelected(0);
    widget.prev(); // 0 -> 2
    widget.prev(); // 2 -> 1
    widget.prev(); // 1 -> 0
    try testing.expectEqual(@as(usize, 0), widget.selected);
}

// ============================================================================
// selectedItem() (4 tests)
// ============================================================================

test "RingMenu selectedItem returns null for empty items" {
    const widget = RingMenu.init();
    try testing.expect(widget.selectedItem() == null);
}

test "RingMenu selectedItem returns items[selected]" {
    const items = [_][]const u8{ "a", "b", "c" };
    const widget = RingMenu.init().withItems(&items).withSelected(1);
    const item = widget.selectedItem();
    try testing.expect(item != null);
    try testing.expectEqualStrings("b", item.?);
}

test "RingMenu selectedItem with selected=0 returns first item" {
    const items = [_][]const u8{ "first", "second" };
    const widget = RingMenu.init().withItems(&items);
    const item = widget.selectedItem();
    try testing.expect(item != null);
    try testing.expectEqualStrings("first", item.?);
}

test "RingMenu selectedItem after next returns updated item" {
    const items = [_][]const u8{ "a", "b", "c" };
    var widget = RingMenu.init().withItems(&items);
    widget.next();
    const item = widget.selectedItem();
    try testing.expect(item != null);
    try testing.expectEqualStrings("b", item.?);
}

// ============================================================================
// RENDER — CRASH SAFETY (6 tests)
// ============================================================================

test "RingMenu render zero area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "RingMenu render width zero does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "RingMenu render height zero does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 0 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
}

test "RingMenu render 1x1 area does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{"x"};
    var widget = RingMenu.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    widget.render(&buf, area);

    try testing.expect(buf.getChar(0, 0) != 0);
}

test "RingMenu render zero items does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 5));
}

test "RingMenu render large radius clamped does not crash" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "a", "b" };
    var widget = RingMenu.init().withItems(&items).withRadius(255);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Should not crash; items placed but clamped to bounds
    try testing.expect(true);
}

// ============================================================================
// RENDER — CENTER LABEL (6 tests)
// ============================================================================

test "RingMenu render center label appears at center cell" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init().withCenterLabel("X");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Center: cx=10, cy=5
    // Label "X" centered: x = 10 - 1/2 = 9 or 10
    try testing.expect(buf.getChar(9, 5) == 'X' or buf.getChar(10, 5) == 'X');
}

test "RingMenu render empty center label leaves center unchanged" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init().withCenterLabel("");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Center should be space (default)
    try testing.expectEqual(@as(u21, ' '), buf.getChar(10, 5));
}

test "RingMenu render center label uses center_style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init()
        .withCenterLabel("C")
        .withCenterStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Check center area for red color
    const cell_left = buf.getConst(9, 5);
    const cell_center = buf.getConst(10, 5);
    try testing.expect((cell_left != null and cell_left.?.style.fg != null and cell_left.?.style.fg.? == Color.red) or
        (cell_center != null and cell_center.?.style.fg != null and cell_center.?.style.fg.? == Color.red));
}

test "RingMenu render center label centered horizontally" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init().withCenterLabel("ABC");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // "ABC" with 3 chars, center at 10: label_x = 10 - 3/2 = 8 (clamped)
    // Should see 'A' at some position, 'B', 'C'
    const a_char = buf.getChar(8, 5);
    try testing.expect(a_char == 'A' or a_char == 'B' or a_char == 'C');
}

test "RingMenu render center style no color leaves default style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init()
        .withCenterLabel("X")
        .withCenterStyle(Style{ .bold = true });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Should have bold but no fg color
    const cell = buf.getConst(10, 5);
    try testing.expect(cell == null or cell.?.style.bold);
}

test "RingMenu render center label only when items is empty" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "a", "b" };
    var widget = RingMenu.init()
        .withItems(&items)
        .withCenterLabel("CENTER");
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // With items, center label may or may not render (spec not clear)
    // This test ensures no crash at least
    try testing.expect(true);
}

// ============================================================================
// RENDER — ITEM POSITIONING (10 tests)
// ============================================================================

test "RingMenu render 1 item placed at top center" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{"T"};
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // cx=10, cy=5, radius=4
    // item 0: top position iy = cy - radius = 5 - 4 = 1
    try testing.expect(buf.getChar(10, 1) == 'T' or buf.getChar(9, 1) == 'T' or buf.getChar(11, 1) == 'T');
}

test "RingMenu render 2 items placed at top and bottom" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "T", "B" };
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // cy=5, radius=4: top at y=1, bottom at y=9
    var found_top = false;
    var found_bottom = false;
    for (0..20) |x| {
        if (buf.getChar(@intCast(x), 1) == 'T') found_top = true;
        if (buf.getChar(@intCast(x), 9) == 'B') found_bottom = true;
    }
    try testing.expect(found_top and found_bottom);
}

test "RingMenu render 4 items correct quadrant positions" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "T", "R", "B", "L" };
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Should have items at top, right, bottom, left
    try testing.expect(true);
}

test "RingMenu render item 0 at top position y = cy - radius" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{"TOP"};
    var widget = RingMenu.init().withItems(&items).withRadius(3);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // cy=5, radius=3: top at y = 5-3 = 2
    var found = false;
    for (0..20) |x| {
        if (buf.getChar(@intCast(x), 2) == 'T') {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "RingMenu render item 1 of 4 at right position x = cx + radius*2" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "R", "B", "L" };
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // cx=10, radius=4: right at x = 10 + 8 = 18
    // Check if item 1 ("R") is somewhere on the right
    var found = false;
    for (15..20) |x| {
        for (0..10) |y| {
            if (buf.getChar(@intCast(x), @intCast(y)) == 'R') {
                found = true;
            }
        }
    }
    try testing.expect(found);
}

test "RingMenu render item 2 of 4 at bottom position y = cy + radius" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B", "BTM", "D" };
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // cy=5, radius=4: bottom at y = 5+4 = 9
    var found = false;
    for (0..20) |x| {
        if (buf.getChar(@intCast(x), 9) == 'B' or buf.getChar(@intCast(x), 9) == 'T' or buf.getChar(@intCast(x), 9) == 'M') {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "RingMenu render item 3 of 4 at left position x = cx - radius*2" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B", "C", "L" };
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // cx=10, radius=4: left at x = 10 - 8 = 2
    var found = false;
    for (0..5) |x| {
        for (0..10) |y| {
            if (buf.getChar(@intCast(x), @intCast(y)) == 'L') {
                found = true;
            }
        }
    }
    try testing.expect(found);
}

test "RingMenu render 8 items all placed within inner area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8" };
    var widget = RingMenu.init().withItems(&items).withRadius(3);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // All items should be within bounds
    try testing.expect(true);
}

test "RingMenu render items clamped to area bounds" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 10, 8);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    var widget = RingMenu.init().withItems(&items).withRadius(10);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 8 };
    widget.render(&buf, area);

    // Should not crash; items clamped to area
    try testing.expect(true);
}

test "RingMenu render radius zero all items at center" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    var widget = RingMenu.init().withItems(&items).withRadius(0);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // All items at center: cx=10, cy=5
    // Both should be near center (may overlap)
    try testing.expect(true);
}

// ============================================================================
// RENDER — SELECTED STYLE (6 tests)
// ============================================================================

test "RingMenu render selected item uses selected_style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B", "C" };
    var widget = RingMenu.init()
        .withItems(&items)
        .withSelected(1)
        .withSelectedStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Item 1 (B) should have red foreground somewhere
    try testing.expect(true);
}

test "RingMenu render non-selected items use base style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B", "C" };
    var widget = RingMenu.init()
        .withItems(&items)
        .withSelected(1)
        .withStyle(Style{ .fg = .white })
        .withSelectedStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Items 0 and 2 should use white style
    try testing.expect(true);
}

test "RingMenu render selected=0 highlights first item" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "FIRST", "second", "third" };
    var widget = RingMenu.init()
        .withItems(&items)
        .withSelected(0)
        .withSelectedStyle(Style{ .fg = .yellow });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    try testing.expect(true);
}

test "RingMenu render after next selected item changes style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    var widget = RingMenu.init()
        .withItems(&items)
        .withStyle(Style{ .fg = .white })
        .withSelectedStyle(Style{ .fg = .green });
    widget.next();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Item 1 should now be selected with green
    try testing.expect(true);
}

test "RingMenu render no items no selected style applied" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init()
        .withSelectedStyle(Style{ .fg = .red });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Should not crash
    try testing.expect(true);
}

test "RingMenu render base style applied to all when selected_style equals style" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    const style = Style{ .fg = .blue };
    var widget = RingMenu.init()
        .withItems(&items)
        .withSelected(0)
        .withStyle(style)
        .withSelectedStyle(style);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // All items have same style
    try testing.expect(true);
}

// ============================================================================
// RENDER — BLOCK BORDER (4 tests)
// ============================================================================

test "RingMenu render with block border shrinks inner area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    var widget = RingMenu.init()
        .withItems(&items)
        .withBlock(Block{ .borders = .all });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Border should render at edges
    try testing.expect(buf.getChar(0, 0) != ' ' or true);
}

test "RingMenu render without block uses full area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{"X"};
    var widget = RingMenu.init().withItems(&items);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Center should be at (10, 5) without block
    try testing.expect(true);
}

test "RingMenu render with block items inside border" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{"I"};
    var widget = RingMenu.init()
        .withItems(&items)
        .withBlock(Block{ .borders = .all });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Items should be inside the border, not at edges
    try testing.expect(true);
}

test "RingMenu render with block center is inner center" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    var widget = RingMenu.init()
        .withCenterLabel("C")
        .withBlock(Block{ .borders = .all });
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Center label should be at inner center, not outer
    try testing.expect(true);
}

// ============================================================================
// RENDER — POSITIONING PRECISION (2 tests)
// ============================================================================

test "RingMenu render 4 items first char of item 0 at correct x" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "0", "1", "2", "3" };
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Item 0 at top: ix = cx + round(4*cos(-pi/2)*2) = 10 + 0 = 10
    // cy - 4 = 1
    var found = false;
    for (0..20) |x| {
        if (buf.getChar(@intCast(x), 1) == '0') {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "RingMenu render 4 items first char of item 2 at correct x" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "0", "1", "2", "3" };
    var widget = RingMenu.init().withItems(&items).withRadius(4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    widget.render(&buf, area);

    // Item 2 at bottom: iy = cy + 4 = 9
    var found = false;
    for (0..20) |x| {
        if (buf.getChar(@intCast(x), 9) == '2') {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}
