const std = @import("std");
const sailor = @import("sailor");
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;

// Forward declaration - will be implemented in src/tui/widgets/menu.zig
const Menu = sailor.tui.widgets.Menu;
const MenuItem = Menu.MenuItem;

// ============================================================================
// MenuItem Tests
// ============================================================================

test "MenuItem basic creation" {
    const item = MenuItem{
        .label = "File",
    };

    try std.testing.expectEqualStrings("File", item.label);
    try std.testing.expectEqual(@as(?u8, null), item.hotkey);
    try std.testing.expectEqual(@as(?[]const MenuItem, null), item.submenu);
}

test "MenuItem with hotkey" {
    const item = MenuItem{
        .label = "Open",
        .hotkey = 'O',
    };

    try std.testing.expectEqualStrings("Open", item.label);
    try std.testing.expectEqual(@as(?u8, 'O'), item.hotkey);
}

test "MenuItem with submenu" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "New File" },
        .{ .label = "New Window" },
    };

    const item = MenuItem{
        .label = "New",
        .hotkey = 'N',
        .submenu = submenu_items,
    };

    try std.testing.expectEqualStrings("New", item.label);
    try std.testing.expectEqual(@as(?u8, 'N'), item.hotkey);
    try std.testing.expect(item.submenu != null);
    try std.testing.expectEqual(@as(usize, 2), item.submenu.?.len);
}

// ============================================================================
// Menu Creation Tests
// ============================================================================

test "Menu.init creates menu with items" {
    const items = &[_]MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
        .{ .label = "View" },
    };

    const menu = Menu.init(items);

    try std.testing.expectEqual(@as(usize, 3), menu.items.len);
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
    try std.testing.expectEqual(@as(?usize, null), menu.submenu_open);
}

test "Menu.init with empty items" {
    const items = &[_]MenuItem{};
    const menu = Menu.init(items);

    try std.testing.expectEqual(@as(usize, 0), menu.items.len);
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

// ============================================================================
// Menu Builder API Tests
// ============================================================================

test "Menu.withSelected sets selected index" {
    const items = &[_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
        .{ .label = "Three" },
    };

    const menu = Menu.init(items).withSelected(1);

    try std.testing.expectEqual(@as(usize, 1), menu.selected);
}

test "Menu.withBlock sets block" {
    const items = &[_]MenuItem{.{ .label = "Item" }};
    const block = Block.init();
    const menu = Menu.init(items).withBlock(block);

    try std.testing.expect(menu.block != null);
}

test "Menu.withItemStyle sets item style" {
    const items = &[_]MenuItem{.{ .label = "Item" }};
    const style = Style{ .fg = .white };
    const menu = Menu.init(items).withItemStyle(style);

    try std.testing.expectEqual(Color.white, menu.item_style.fg.?);
}

test "Menu.withSelectedStyle sets selected style" {
    const items = &[_]MenuItem{.{ .label = "Item" }};
    const style = Style{ .bg = .blue, .bold = true };
    const menu = Menu.init(items).withSelectedStyle(style);

    try std.testing.expectEqual(Color.blue, menu.selected_style.bg.?);
    try std.testing.expectEqual(true, menu.selected_style.bold);
}

test "Menu.withHotkeyStyle sets hotkey style" {
    const items = &[_]MenuItem{.{ .label = "Item" }};
    const style = Style{ .fg = .yellow, .underline = true };
    const menu = Menu.init(items).withHotkeyStyle(style);

    try std.testing.expectEqual(Color.yellow, menu.hotkey_style.fg.?);
    try std.testing.expectEqual(true, menu.hotkey_style.underline);
}

test "Menu.withSubmenuIndicator sets indicator" {
    const items = &[_]MenuItem{.{ .label = "Item" }};
    const menu = Menu.init(items).withSubmenuIndicator(" \u{25B6}");

    try std.testing.expectEqualStrings(" \u{25B6}", menu.submenu_indicator);
}

// ============================================================================
// Basic Rendering Tests
// ============================================================================

test "Menu.render empty area does nothing" {
    const items = &[_]MenuItem{.{ .label = "File" }};
    const menu = Menu.init(items);

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    menu.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
    // Should not crash
}

test "Menu.render single item" {
    const items = &[_]MenuItem{.{ .label = "File" }};
    const menu = Menu.init(items).withSelected(0);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // Check item is rendered
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
}

test "Menu.render multiple items vertically" {
    const items = &[_]MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
        .{ .label = "View" },
    };
    const menu = Menu.init(items);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // Check each item is on its own line
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(0, 0).?.char); // File
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(0, 1).?.char); // Edit
    try std.testing.expectEqual(@as(u21, 'V'), buf.get(0, 2).?.char); // View
}

test "Menu.render with selection highlight" {
    const items = &[_]MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
        .{ .label = "View" },
    };
    const selected_style = Style{ .bg = .blue, .bold = true };
    const menu = Menu.init(items)
        .withSelected(1)
        .withSelectedStyle(selected_style);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // Selected item (Edit) should have blue background and bold
    const selected_cell = buf.get(0, 1).?;
    try std.testing.expectEqual(@as(u21, 'E'), selected_cell.char);
    try std.testing.expectEqual(Color.blue, selected_cell.style.bg.?);
    try std.testing.expectEqual(true, selected_cell.style.bold);

    // Non-selected items should not have blue background
    const unselected = buf.get(0, 0).?;
    try std.testing.expect(unselected.style.bg == null or
        !std.meta.eql(unselected.style.bg.?, Color.blue));
}

test "Menu.render with borders" {
    const items = &[_]MenuItem{.{ .label = "File" }};
    const block = Block.init();
    const menu = Menu.init(items).withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    menu.render(&buf, area);

    // Check border is rendered
    try std.testing.expectEqual(@as(u21, '\u{250C}'), buf.get(0, 0).?.char); // ┌

    // Check item is inside border
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(1, 1).?.char);
}

// ============================================================================
// Hotkey Display Tests
// ============================================================================

test "Menu.render item with hotkey underlined" {
    const items = &[_]MenuItem{
        .{ .label = "File", .hotkey = 'F' },
        .{ .label = "Open", .hotkey = 'O' },
    };
    const hotkey_style = Style{ .fg = .yellow, .underline = true };
    const menu = Menu.init(items).withHotkeyStyle(hotkey_style);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // Hotkey character 'F' should be underlined and yellow
    const hotkey_cell = buf.get(0, 0).?;
    try std.testing.expectEqual(@as(u21, 'F'), hotkey_cell.char);
    try std.testing.expectEqual(Color.yellow, hotkey_cell.style.fg.?);
    try std.testing.expectEqual(true, hotkey_cell.style.underline);

    // Non-hotkey characters should not be underlined
    const regular_cell = buf.get(1, 0).?;
    try std.testing.expectEqual(@as(u21, 'i'), regular_cell.char);
    try std.testing.expectEqual(false, regular_cell.style.underline);
}

test "Menu.render hotkey in middle of label" {
    const items = &[_]MenuItem{
        .{ .label = "Open", .hotkey = 'p' },
    };
    const hotkey_style = Style{ .fg = .red };
    const menu = Menu.init(items).withHotkeyStyle(hotkey_style);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // 'O' should be normal
    try std.testing.expect(buf.get(0, 0).?.style.fg == null or
        !std.meta.eql(buf.get(0, 0).?.style.fg.?, Color.red));

    // 'p' should be highlighted
    const hotkey_cell = buf.get(1, 0).?;
    try std.testing.expectEqual(@as(u21, 'p'), hotkey_cell.char);
    try std.testing.expectEqual(Color.red, hotkey_cell.style.fg.?);

    // 'e' and 'n' should be normal
    try std.testing.expect(buf.get(2, 0).?.style.fg == null or
        !std.meta.eql(buf.get(2, 0).?.style.fg.?, Color.red));
}

test "Menu.render hotkey case insensitive match" {
    const items = &[_]MenuItem{
        .{ .label = "File", .hotkey = 'f' }, // lowercase hotkey
    };
    const hotkey_style = Style{ .fg = .green };
    const menu = Menu.init(items).withHotkeyStyle(hotkey_style);

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // 'F' should match lowercase 'f' hotkey
    const hotkey_cell = buf.get(0, 0).?;
    try std.testing.expectEqual(@as(u21, 'F'), hotkey_cell.char);
    try std.testing.expectEqual(Color.green, hotkey_cell.style.fg.?);
}

// ============================================================================
// Submenu Indicator Tests
// ============================================================================

test "Menu.render item with submenu shows indicator" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "New File" },
    };
    const items = &[_]MenuItem{
        .{ .label = "File", .submenu = submenu_items },
        .{ .label = "Edit" },
    };
    const menu = Menu.init(items).withSubmenuIndicator(" >");

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // "File" should have submenu indicator " >"
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, '>'), buf.get(5, 0).?.char);

    // "Edit" should not have indicator
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(0, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(1, 1).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(2, 1).?.char);
    try std.testing.expectEqual(@as(u21, 't'), buf.get(3, 1).?.char);
    // Should not have '>' indicator
    try std.testing.expect(buf.get(4, 1).?.char != '>');
}

test "Menu.render with custom unicode submenu indicator" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "Item" },
    };
    const items = &[_]MenuItem{
        .{ .label = "Menu", .submenu = submenu_items },
    };
    const menu = Menu.init(items).withSubmenuIndicator(" \u{25B6}"); // ▶

    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

    // Should render unicode indicator
    try std.testing.expectEqual(@as(u21, ' '), buf.get(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, '\u{25B6}'), buf.get(5, 0).?.char);
}

// ============================================================================
// Navigation Tests
// ============================================================================

test "Menu.moveDown advances selection" {
    const items = &[_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
        .{ .label = "Three" },
    };
    var menu = Menu.init(items); // selected = 0

    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 1), menu.selected);

    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 2), menu.selected);
}

test "Menu.moveDown wraps to start" {
    const items = &[_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
    };
    var menu = Menu.init(items).withSelected(1); // Last item

    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 0), menu.selected); // Wrap to first
}

test "Menu.moveDown on empty menu does nothing" {
    const items = &[_]MenuItem{};
    var menu = Menu.init(items);

    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 0), menu.selected); // No change
}

test "Menu.moveUp retreats selection" {
    const items = &[_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
        .{ .label = "Three" },
    };
    var menu = Menu.init(items).withSelected(2);

    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 1), menu.selected);

    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "Menu.moveUp wraps to end" {
    const items = &[_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
    };
    var menu = Menu.init(items); // selected = 0

    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 1), menu.selected); // Wrap to last
}

test "Menu.moveUp on empty menu does nothing" {
    const items = &[_]MenuItem{};
    var menu = Menu.init(items);

    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

// ============================================================================
// Submenu Tests
// ============================================================================

test "Menu.openSubmenu opens submenu of selected item" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "New File" },
        .{ .label = "New Window" },
    };
    const items = &[_]MenuItem{
        .{ .label = "File", .submenu = submenu_items },
        .{ .label = "Edit" },
    };
    var menu = Menu.init(items); // selected = 0 (File)

    menu.openSubmenu();
    try std.testing.expectEqual(@as(?usize, 0), menu.submenu_open);
}

test "Menu.openSubmenu on item without submenu does nothing" {
    const items = &[_]MenuItem{
        .{ .label = "File" }, // No submenu
        .{ .label = "Edit" },
    };
    var menu = Menu.init(items); // selected = 0

    menu.openSubmenu();
    try std.testing.expectEqual(@as(?usize, null), menu.submenu_open);
}

test "Menu.openSubmenu on empty menu does nothing" {
    const items = &[_]MenuItem{};
    var menu = Menu.init(items);

    menu.openSubmenu();
    try std.testing.expectEqual(@as(?usize, null), menu.submenu_open);
}

test "Menu.closeSubmenu closes open submenu" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "Item" },
    };
    const items = &[_]MenuItem{
        .{ .label = "File", .submenu = submenu_items },
    };
    var menu = Menu.init(items);
    menu.openSubmenu(); // Open it first

    menu.closeSubmenu();
    try std.testing.expectEqual(@as(?usize, null), menu.submenu_open);
}

test "Menu.closeSubmenu when no submenu open does nothing" {
    const items = &[_]MenuItem{
        .{ .label = "File" },
    };
    var menu = Menu.init(items);

    menu.closeSubmenu();
    try std.testing.expectEqual(@as(?usize, null), menu.submenu_open);
}

test "Menu.isSubmenuOpen returns correct state" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "Item" },
    };
    const items = &[_]MenuItem{
        .{ .label = "File", .submenu = submenu_items },
    };
    var menu = Menu.init(items);

    try std.testing.expectEqual(false, menu.isSubmenuOpen());

    menu.openSubmenu();
    try std.testing.expectEqual(true, menu.isSubmenuOpen());

    menu.closeSubmenu();
    try std.testing.expectEqual(false, menu.isSubmenuOpen());
}

// ============================================================================
// Submenu Rendering Tests
// ============================================================================

test "Menu.render with open submenu shows both levels" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "New File" },
        .{ .label = "New Window" },
    };
    const items = &[_]MenuItem{
        .{ .label = "File", .submenu = submenu_items },
        .{ .label = "Edit" },
    };
    var menu = Menu.init(items);
    menu.openSubmenu(); // Open File submenu

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    menu.render(&buf, area);

    // Main menu should be visible
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(0, 0).?.char); // File
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(0, 1).?.char); // Edit

    // Submenu should be rendered to the right
    // Expected position: after "File >" plus some spacing
    // This test verifies submenu appears somewhere in the buffer
    var found_new_file = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'N') {
                // Check if "New File" follows
                if (buf.get(@intCast(x + 1), 0)) |c1| {
                    if (c1.char == 'e') {
                        if (buf.get(@intCast(x + 2), 0)) |c2| {
                            if (c2.char == 'w') {
                                found_new_file = true;
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
    try std.testing.expect(found_new_file);
}

test "Menu.render closed submenu only shows main menu" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "New File" },
    };
    const items = &[_]MenuItem{
        .{ .label = "File", .submenu = submenu_items },
    };
    const menu = Menu.init(items); // submenu_open = null

    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    menu.render(&buf, area);

    // Main menu should be visible
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(0, 0).?.char);

    // Submenu should NOT be rendered
    var found_new = false;
    for (0..40) |x| {
        if (buf.get(@intCast(x), 0)) |cell| {
            if (cell.char == 'N') {
                if (buf.get(@intCast(x + 1), 0)) |c1| {
                    if (c1.char == 'e') {
                        if (buf.get(@intCast(x + 2), 0)) |c2| {
                            if (c2.char == 'w') {
                                found_new = true;
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
    try std.testing.expect(!found_new); // Should NOT find "New"
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Menu.render clips at area width boundary" {
    const items = &[_]MenuItem{
        .{ .label = "Very Long Menu Item Name" },
    };
    const menu = Menu.init(items);

    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    menu.render(&buf, area);

    // Should only render up to width boundary
    try std.testing.expectEqual(@as(u21, 'V'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).?.char);
    // Should clip after width 10
}

test "Menu.render clips at area height boundary" {
    const items = &[_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
        .{ .label = "Three" },
        .{ .label = "Four" },
        .{ .label = "Five" },
    };
    const menu = Menu.init(items);

    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 3 };
    menu.render(&buf, area);

    // Should only render first 3 items
    try std.testing.expectEqual(@as(u21, 'O'), buf.get(0, 0).?.char); // One
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 1).?.char); // Two
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 2).?.char); // Three
    // Four and Five should not be rendered (height limit)
}

test "Menu.render with offset area" {
    const items = &[_]MenuItem{
        .{ .label = "Item" },
    };
    const menu = Menu.init(items);

    var buf = try Buffer.init(std.testing.allocator, 30, 20);
    defer buf.deinit();

    const area = Rect{ .x = 10, .y = 5, .width = 15, .height = 8 };
    menu.render(&buf, area);

    // Should render at offset position
    try std.testing.expectEqual(@as(u21, 'I'), buf.get(10, 5).?.char);
    try std.testing.expectEqual(@as(u21, 't'), buf.get(11, 5).?.char);

    // Should not render outside area
    try std.testing.expect(buf.get(9, 5) == null or buf.get(9, 5).?.char == ' ');
}

test "Menu.render selection fills width with background" {
    const items = &[_]MenuItem{
        .{ .label = "Short" },
    };
    const selected_style = Style{ .bg = .cyan };
    const menu = Menu.init(items)
        .withSelected(0)
        .withSelectedStyle(selected_style);

    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    menu.render(&buf, area);

    // All cells in selected row should have cyan background
    for (0..20) |x| {
        const cell = buf.get(@intCast(x), 0).?;
        try std.testing.expectEqual(Color.cyan, cell.style.bg.?);
    }
}

// ============================================================================
// Selection State Tests
// ============================================================================

test "Menu.getSelectedItem returns selected item" {
    const items = &[_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
        .{ .label = "Three" },
    };
    const menu = Menu.init(items).withSelected(1);

    const selected = menu.getSelectedItem();
    try std.testing.expect(selected != null);
    try std.testing.expectEqualStrings("Two", selected.?.label);
}

test "Menu.getSelectedItem on empty menu returns null" {
    const items = &[_]MenuItem{};
    const menu = Menu.init(items);

    const selected = menu.getSelectedItem();
    try std.testing.expect(selected == null);
}

test "Menu.hasSubmenu returns true when selected item has submenu" {
    const submenu_items = &[_]MenuItem{
        .{ .label = "Item" },
    };
    const items = &[_]MenuItem{
        .{ .label = "File", .submenu = submenu_items },
        .{ .label = "Edit" },
    };
    const menu = Menu.init(items); // selected = 0 (File)

    try std.testing.expectEqual(true, menu.hasSubmenu());
}

test "Menu.hasSubmenu returns false when selected item has no submenu" {
    const items = &[_]MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };
    const menu = Menu.init(items).withSelected(1); // Edit has no submenu

    try std.testing.expectEqual(false, menu.hasSubmenu());
}

test "Menu.hasSubmenu returns false on empty menu" {
    const items = &[_]MenuItem{};
    const menu = Menu.init(items);

    try std.testing.expectEqual(false, menu.hasSubmenu());
}
