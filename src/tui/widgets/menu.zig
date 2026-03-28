const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Menu widget - hierarchical dropdown/popup menus with keyboard navigation
pub const Menu = struct {
    /// Menu item structure
    pub const MenuItem = struct {
        label: []const u8,
        hotkey: ?u8 = null,
        submenu: ?[]const MenuItem = null,
        action: ?*const fn () void = null,
    };

    items: []const MenuItem,
    selected: usize = 0,
    submenu_open: ?usize = null,
    block: ?Block = null,
    item_style: Style = .{},
    selected_style: Style = .{},
    hotkey_style: Style = .{},
    submenu_indicator: []const u8 = " >",

    /// Create a menu with items
    pub fn init(items: []const MenuItem) Menu {
        return .{ .items = items };
    }

    /// Set the selected item index
    pub fn withSelected(self: Menu, index: usize) Menu {
        var result = self;
        result.selected = index;
        return result;
    }

    /// Set the block (border) for this menu
    pub fn withBlock(self: Menu, new_block: Block) Menu {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Set the style for unselected items
    pub fn withItemStyle(self: Menu, new_style: Style) Menu {
        var result = self;
        result.item_style = new_style;
        return result;
    }

    /// Set the style for the selected item
    pub fn withSelectedStyle(self: Menu, new_style: Style) Menu {
        var result = self;
        result.selected_style = new_style;
        return result;
    }

    /// Set the style for hotkey characters
    pub fn withHotkeyStyle(self: Menu, new_style: Style) Menu {
        var result = self;
        result.hotkey_style = new_style;
        return result;
    }

    /// Set the submenu indicator string
    pub fn withSubmenuIndicator(self: Menu, indicator: []const u8) Menu {
        var result = self;
        result.submenu_indicator = indicator;
        return result;
    }

    /// Move selection down (wraps around)
    pub fn moveDown(self: *Menu) void {
        if (self.items.len == 0) return;
        self.selected = (self.selected + 1) % self.items.len;
    }

    /// Move selection up (wraps around)
    pub fn moveUp(self: *Menu) void {
        if (self.items.len == 0) return;
        if (self.selected == 0) {
            self.selected = self.items.len - 1;
        } else {
            self.selected -= 1;
        }
    }

    /// Open submenu of selected item (if it has one)
    pub fn openSubmenu(self: *Menu) void {
        if (self.items.len == 0) return;
        if (self.selected >= self.items.len) return;

        const item = &self.items[self.selected];
        if (item.submenu != null) {
            self.submenu_open = self.selected;
        }
    }

    /// Close currently open submenu
    pub fn closeSubmenu(self: *Menu) void {
        self.submenu_open = null;
    }

    /// Check if a submenu is currently open
    pub fn isSubmenuOpen(self: Menu) bool {
        return self.submenu_open != null;
    }

    /// Check if selected item has a submenu
    pub fn hasSubmenu(self: Menu) bool {
        if (self.items.len == 0) return false;
        if (self.selected >= self.items.len) return false;
        return self.items[self.selected].submenu != null;
    }

    /// Get the currently selected item
    pub fn getSelectedItem(self: Menu) ?*const MenuItem {
        if (self.items.len == 0) return null;
        if (self.selected >= self.items.len) return null;
        return &self.items[self.selected];
    }

    /// Render the menu widget
    pub fn render(self: Menu, buf: *Buffer, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        // Render block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Render main menu items
        try self.renderItems(buf, inner_area, self.items, self.selected);

        // Render submenu if open
        if (self.submenu_open) |submenu_idx| {
            if (submenu_idx < self.items.len) {
                if (self.items[submenu_idx].submenu) |submenu_items| {
                    // Calculate submenu position (to the right of main menu)
                    // Find the length needed for main menu items
                    var max_len: u16 = 0;
                    for (self.items) |item| {
                        const item_len = @as(u16, @intCast(item.label.len));
                        const has_submenu = item.submenu != null;
                        const total_len = item_len + if (has_submenu) @as(u16, @intCast(self.submenu_indicator.len)) else 0;
                        max_len = @max(max_len, total_len);
                    }

                    // Position submenu to the right
                    const submenu_x = inner_area.x + max_len + 1; // +1 for spacing
                    if (submenu_x < inner_area.x + inner_area.width) {
                        const submenu_area = Rect{
                            .x = submenu_x,
                            .y = inner_area.y + @as(u16, @intCast(submenu_idx)),
                            .width = inner_area.width -| (submenu_x - inner_area.x),
                            .height = inner_area.height -| @as(u16, @intCast(submenu_idx)),
                        };
                        // Render submenu items (none selected in submenu for now)
                        try self.renderItems(buf, submenu_area, submenu_items, std.math.maxInt(usize));
                    }
                }
            }
        }
    }

    /// Render menu items (helper function)
    fn renderItems(self: Menu, buf: *Buffer, area: Rect, items: []const MenuItem, selected_idx: usize) !void {
        var y = area.y;
        for (items, 0..) |item, i| {
            if (y >= area.y + area.height) break;

            const is_selected = i == selected_idx;
            const base_style = if (is_selected) self.selected_style else self.item_style;

            var x = area.x;

            // Render item label with hotkey highlighting
            const hotkey_lower = if (item.hotkey) |hk| toLower(hk) else null;

            var label_idx: usize = 0;
            while (label_idx < item.label.len) : (label_idx += 1) {
                if (x >= area.x + area.width) break;

                const char = item.label[label_idx];
                var char_style = base_style;

                // Check if this character matches the hotkey (case-insensitive)
                if (hotkey_lower != null and toLower(char) == hotkey_lower.?) {
                    // Apply hotkey style on top of base style
                    char_style = mergeStyles(base_style, self.hotkey_style);
                }

                buf.setChar(x, y, char, char_style);
                x += 1;
            }

            // Append submenu indicator if item has submenu
            if (item.submenu != null) {
                var it = (try std.unicode.Utf8View.init(self.submenu_indicator)).iterator();
                while (it.nextCodepoint()) |codepoint| {
                    if (x >= area.x + area.width) break;
                    buf.setChar(x, y, codepoint, base_style);
                    x += 1;
                }
            }

            // Fill remaining width with spaces if selected (full-width highlight)
            if (is_selected) {
                while (x < area.x + area.width) : (x += 1) {
                    buf.setChar(x, y, ' ', base_style);
                }
            }

            y += 1;
        }
    }

    /// Convert ASCII character to lowercase
    fn toLower(c: u8) u8 {
        if (c >= 'A' and c <= 'Z') {
            return c + ('a' - 'A');
        }
        return c;
    }

    /// Merge two styles (overlay applies on top of base)
    fn mergeStyles(base: Style, overlay: Style) Style {
        return Style{
            .fg = overlay.fg orelse base.fg,
            .bg = overlay.bg orelse base.bg,
            .bold = overlay.bold or base.bold,
            .dim = overlay.dim or base.dim,
            .italic = overlay.italic or base.italic,
            .underline = overlay.underline or base.underline,
            .blink = overlay.blink or base.blink,
            .reverse = overlay.reverse or base.reverse,
            .strikethrough = overlay.strikethrough or base.strikethrough,
        };
    }
};

// ================================ TESTS ================================

test "menu init with items" {
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
        .{ .label = "View" },
    };

    const menu = Menu.init(&items);
    try std.testing.expectEqual(@as(usize, 3), menu.items.len);
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
    try std.testing.expect(menu.submenu_open == null);
}

test "menu withSelected sets selected index" {
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };

    const menu = Menu.init(&items).withSelected(1);
    try std.testing.expectEqual(@as(usize, 1), menu.selected);
}

test "menu withBlock sets block" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const blk = Block.init().withTitle("Menu");

    const menu = Menu.init(&items).withBlock(blk);
    try std.testing.expect(menu.block != null);
}

test "menu withItemStyle sets item style" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const style = Style{ .fg = .{ .index = 1 } };

    const menu = Menu.init(&items).withItemStyle(style);
    try std.testing.expect(menu.item_style.fg != null);
}

test "menu withSelectedStyle sets selected style" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const style = Style{ .bg = .{ .index = 4 } };

    const menu = Menu.init(&items).withSelectedStyle(style);
    try std.testing.expect(menu.selected_style.bg != null);
}

test "menu withHotkeyStyle sets hotkey style" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const style = Style{ .bold = true };

    const menu = Menu.init(&items).withHotkeyStyle(style);
    try std.testing.expect(menu.hotkey_style.bold);
}

test "menu withSubmenuIndicator sets submenu indicator" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items).withSubmenuIndicator(" →");

    try std.testing.expectEqualStrings(" →", menu.submenu_indicator);
}

test "menu moveDown wraps around to first item" {
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
        .{ .label = "View" },
    };

    var menu = Menu.init(&items).withSelected(2);
    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "menu moveDown advances to next item" {
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };

    var menu = Menu.init(&items);
    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 1), menu.selected);
}

test "menu moveUp wraps around to last item" {
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
        .{ .label = "View" },
    };

    var menu = Menu.init(&items);
    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 2), menu.selected);
}

test "menu moveUp goes to previous item" {
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };

    var menu = Menu.init(&items).withSelected(1);
    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "menu moveDown on empty items does nothing" {
    const items = [_]Menu.MenuItem{};
    var menu = Menu.init(&items);
    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "menu moveUp on empty items does nothing" {
    const items = [_]Menu.MenuItem{};
    var menu = Menu.init(&items);
    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "menu moveDown on single item stays at index 0" {
    const items = [_]Menu.MenuItem{.{ .label = "Only" }};
    var menu = Menu.init(&items);
    menu.moveDown();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "menu moveUp on single item stays at index 0" {
    const items = [_]Menu.MenuItem{.{ .label = "Only" }};
    var menu = Menu.init(&items);
    menu.moveUp();
    try std.testing.expectEqual(@as(usize, 0), menu.selected);
}

test "menu openSubmenu sets submenu_open when item has submenu" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    var menu = Menu.init(&items);
    menu.openSubmenu();
    try std.testing.expect(menu.submenu_open != null);
    try std.testing.expectEqual(@as(usize, 0), menu.submenu_open.?);
}

test "menu openSubmenu does nothing when item has no submenu" {
    const items = [_]Menu.MenuItem{.{ .label = "Exit" }};

    var menu = Menu.init(&items);
    menu.openSubmenu();
    try std.testing.expect(menu.submenu_open == null);
}

test "menu openSubmenu on empty items does nothing" {
    const items = [_]Menu.MenuItem{};
    var menu = Menu.init(&items);
    menu.openSubmenu();
    try std.testing.expect(menu.submenu_open == null);
}

test "menu openSubmenu when selected out of bounds does nothing" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    var menu = Menu.init(&items).withSelected(10);
    menu.openSubmenu();
    try std.testing.expect(menu.submenu_open == null);
}

test "menu openSubmenu is idempotent" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    var menu = Menu.init(&items);
    menu.openSubmenu();
    const first_open = menu.submenu_open;
    menu.openSubmenu();
    try std.testing.expectEqual(first_open, menu.submenu_open);
}

test "menu closeSubmenu clears submenu_open" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    var menu = Menu.init(&items);
    menu.openSubmenu();
    menu.closeSubmenu();
    try std.testing.expect(menu.submenu_open == null);
}

test "menu closeSubmenu is idempotent" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    var menu = Menu.init(&items);
    menu.closeSubmenu();
    menu.closeSubmenu();
    try std.testing.expect(menu.submenu_open == null);
}

test "menu isSubmenuOpen returns true when submenu is open" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    var menu = Menu.init(&items);
    menu.openSubmenu();
    try std.testing.expect(menu.isSubmenuOpen());
}

test "menu isSubmenuOpen returns false when no submenu is open" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items);
    try std.testing.expect(!menu.isSubmenuOpen());
}

test "menu hasSubmenu returns true when selected item has submenu" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    const menu = Menu.init(&items);
    try std.testing.expect(menu.hasSubmenu());
}

test "menu hasSubmenu returns false when selected item has no submenu" {
    const items = [_]Menu.MenuItem{.{ .label = "Exit" }};
    const menu = Menu.init(&items);
    try std.testing.expect(!menu.hasSubmenu());
}

test "menu hasSubmenu returns false when items is empty" {
    const items = [_]Menu.MenuItem{};
    const menu = Menu.init(&items);
    try std.testing.expect(!menu.hasSubmenu());
}

test "menu hasSubmenu returns false when selected out of bounds" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items).withSelected(10);
    try std.testing.expect(!menu.hasSubmenu());
}

test "menu getSelectedItem returns selected item" {
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };

    const menu = Menu.init(&items).withSelected(1);
    const item = menu.getSelectedItem();
    try std.testing.expect(item != null);
    try std.testing.expectEqualStrings("Edit", item.?.label);
}

test "menu getSelectedItem returns null when items is empty" {
    const items = [_]Menu.MenuItem{};
    const menu = Menu.init(&items);
    try std.testing.expect(menu.getSelectedItem() == null);
}

test "menu getSelectedItem returns null when selected out of bounds" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items).withSelected(10);
    try std.testing.expect(menu.getSelectedItem() == null);
}

test "menu render with zero width area returns early" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items);

    var buf = try Buffer.init(allocator, .{ .width = 0, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    try menu.render(&buf, area);
    // Should return early without error
}

test "menu render with zero height area returns early" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items);

    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 0 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    try menu.render(&buf, area);
    // Should return early without error
}

test "menu render items without selection styling" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };

    const menu = Menu.init(&items).withSelected(0);
    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try menu.render(&buf, area);

    // Check first item is rendered
    try std.testing.expectEqual('F', buf.getChar(0, 0));
    try std.testing.expectEqual('i', buf.getChar(1, 0));
    try std.testing.expectEqual('l', buf.getChar(2, 0));
    try std.testing.expectEqual('e', buf.getChar(3, 0));

    // Check second item is rendered
    try std.testing.expectEqual('E', buf.getChar(0, 1));
    try std.testing.expectEqual('d', buf.getChar(1, 1));
    try std.testing.expectEqual('i', buf.getChar(2, 1));
    try std.testing.expectEqual('t', buf.getChar(3, 1));
}

test "menu render with selected item styling" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };

    const selected_style = Style{ .bg = .{ .index = 4 } };
    const menu = Menu.init(&items).withSelected(0).withSelectedStyle(selected_style);

    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try menu.render(&buf, area);

    // Check selected item has background color
    const style = buf.getStyle(0, 0);
    try std.testing.expect(style.bg != null);
    try std.testing.expectEqual(@as(u8, 4), style.bg.?.index);

    // Check full-width highlight (should fill with spaces)
    try std.testing.expectEqual(' ', buf.getChar(9, 0));
    const end_style = buf.getStyle(9, 0);
    try std.testing.expect(end_style.bg != null);
}

test "menu render with submenu indicator" {
    const allocator = std.testing.allocator;
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    const menu = Menu.init(&items).withSelected(0);
    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try menu.render(&buf, area);

    // Check submenu indicator " >" is rendered after "File"
    try std.testing.expectEqual('F', buf.getChar(0, 0));
    try std.testing.expectEqual('i', buf.getChar(1, 0));
    try std.testing.expectEqual('l', buf.getChar(2, 0));
    try std.testing.expectEqual('e', buf.getChar(3, 0));
    try std.testing.expectEqual(' ', buf.getChar(4, 0));
    try std.testing.expectEqual('>', buf.getChar(5, 0));
}

test "menu render with custom submenu indicator" {
    const allocator = std.testing.allocator;
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    const menu = Menu.init(&items).withSubmenuIndicator(" →");
    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try menu.render(&buf, area);

    // Check custom indicator is rendered
    try std.testing.expectEqual('e', buf.getChar(3, 0));
    try std.testing.expectEqual(' ', buf.getChar(4, 0));
    try std.testing.expectEqual('→', buf.getChar(5, 0));
}

test "menu render with hotkey highlighting" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .hotkey = 'F' },
    };

    const hotkey_style = Style{ .bold = true };
    const menu = Menu.init(&items).withHotkeyStyle(hotkey_style).withSelected(1);

    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try menu.render(&buf, area);

    // Check first character 'F' has bold style
    const f_style = buf.getStyle(0, 0);
    try std.testing.expect(f_style.bold);

    // Check other characters don't have bold
    const i_style = buf.getStyle(1, 0);
    try std.testing.expect(!i_style.bold);
}

test "menu render hotkey matching is case insensitive" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{
        .{ .label = "file", .hotkey = 'F' },
    };

    const hotkey_style = Style{ .bold = true };
    const menu = Menu.init(&items).withHotkeyStyle(hotkey_style).withSelected(1);

    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try menu.render(&buf, area);

    // Check lowercase 'f' matches uppercase 'F' hotkey
    const f_style = buf.getStyle(0, 0);
    try std.testing.expect(f_style.bold);
}

test "menu render with block consumes space" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{.{ .label = "File" }};

    const blk = Block.init().withBorders(.{ .top = true, .left = true });
    const menu = Menu.init(&items).withBlock(blk);

    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    try menu.render(&buf, area);

    // Block renders border, content starts at (1, 1)
    try std.testing.expectEqual('F', buf.getChar(1, 1));
}

test "menu render truncates items when exceeding area height" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{
        .{ .label = "Item1" },
        .{ .label = "Item2" },
        .{ .label = "Item3" },
        .{ .label = "Item4" },
        .{ .label = "Item5" },
    };

    const menu = Menu.init(&items);
    var buf = try Buffer.init(allocator, .{ .width = 10, .height = 3 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 3 };
    try menu.render(&buf, area);

    // Only first 3 items should render
    try std.testing.expectEqual('I', buf.getChar(0, 0));
    try std.testing.expectEqual('I', buf.getChar(0, 1));
    try std.testing.expectEqual('I', buf.getChar(0, 2));
}

test "menu render submenu when open" {
    const allocator = std.testing.allocator;
    const subitems = [_]Menu.MenuItem{
        .{ .label = "New" },
        .{ .label = "Open" },
    };
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    var menu = Menu.init(&items);
    menu.openSubmenu();

    var buf = try Buffer.init(allocator, .{ .width = 20, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try menu.render(&buf, area);

    // Main menu at x=0
    try std.testing.expectEqual('F', buf.getChar(0, 0));

    // Submenu should be positioned to the right (after "File >")
    // max_len = 4 (File) + 2 ( >) = 6, submenu_x = 0 + 6 + 1 = 7
    try std.testing.expectEqual('N', buf.getChar(7, 0));
    try std.testing.expectEqual('e', buf.getChar(8, 0));
    try std.testing.expectEqual('w', buf.getChar(9, 0));

    try std.testing.expectEqual('O', buf.getChar(7, 1));
    try std.testing.expectEqual('p', buf.getChar(8, 1));
}

test "menu render submenu skipped when insufficient width" {
    const allocator = std.testing.allocator;
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
    };

    var menu = Menu.init(&items);
    menu.openSubmenu();

    var buf = try Buffer.init(allocator, .{ .width = 5, .height = 10 });
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    try menu.render(&buf, area);

    // Submenu won't fit, should be skipped
    // Only main menu rendered
    try std.testing.expectEqual('F', buf.getChar(0, 0));
}

test "menu toLower converts uppercase to lowercase" {
    try std.testing.expectEqual('a', Menu.toLower('A'));
    try std.testing.expectEqual('z', Menu.toLower('Z'));
    try std.testing.expectEqual('m', Menu.toLower('M'));
}

test "menu toLower leaves lowercase unchanged" {
    try std.testing.expectEqual('a', Menu.toLower('a'));
    try std.testing.expectEqual('z', Menu.toLower('z'));
}

test "menu toLower leaves non-alpha unchanged" {
    try std.testing.expectEqual('1', Menu.toLower('1'));
    try std.testing.expectEqual(' ', Menu.toLower(' '));
    try std.testing.expectEqual('!', Menu.toLower('!'));
}

test "menu mergeStyles overlays fg color" {
    const base = Style{ .fg = .{ .index = 1 } };
    const overlay = Style{ .fg = .{ .index = 2 } };
    const result = Menu.mergeStyles(base, overlay);
    try std.testing.expectEqual(@as(u8, 2), result.fg.?.index);
}

test "menu mergeStyles keeps base fg when overlay fg is null" {
    const base = Style{ .fg = .{ .index = 1 } };
    const overlay = Style{ .bg = .{ .index = 2 } };
    const result = Menu.mergeStyles(base, overlay);
    try std.testing.expectEqual(@as(u8, 1), result.fg.?.index);
}

test "menu mergeStyles combines boolean attributes" {
    const base = Style{ .bold = true };
    const overlay = Style{ .italic = true };
    const result = Menu.mergeStyles(base, overlay);
    try std.testing.expect(result.bold);
    try std.testing.expect(result.italic);
}

test "menu mergeStyles overlay boolean attributes take precedence" {
    const base = Style{ .bold = false };
    const overlay = Style{ .bold = true };
    const result = Menu.mergeStyles(base, overlay);
    try std.testing.expect(result.bold);
}
