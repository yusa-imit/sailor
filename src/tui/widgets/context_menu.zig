//! ContextMenu Widget — A popup menu for contextual actions
//!
//! Displays a list of actions, separators, and submenus. Supports keyboard navigation
//! with wrapping, configurable styling for selected/disabled items.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const symbols_mod = @import("../symbols.zig");
const BoxSet = symbols_mod.BoxSet;

/// Block widget import for optional border
const Block = @import("block.zig").Block;

/// ContextMenu widget
pub const ContextMenu = struct {
    /// Item type for the menu
    pub const Item = union(enum) {
        action: Action,
        separator: void,
        submenu: Submenu,
    };

    /// Action menu item
    pub const Action = struct {
        label: []const u8,
        shortcut: ?[]const u8 = null,
        enabled: bool = true,
    };

    /// Submenu item
    pub const Submenu = struct {
        label: []const u8,
        items: []const Item,
    };

    items: []const Item,
    cursor: usize = 0,
    origin_x: u16 = 0,
    origin_y: u16 = 0,
    block: ?Block = null,
    item_style: Style = .{},
    selected_style: Style = .{ .bold = true, .reverse = true },
    disabled_style: Style = .{ .dim = true },
    shortcut_style: Style = .{},

    /// Initialize a ContextMenu with items
    pub fn init(items: []const Item) ContextMenu {
        return ContextMenu{
            .items = items,
            .cursor = 0,
            .origin_x = 0,
            .origin_y = 0,
            .block = null,
            .item_style = .{},
            .selected_style = .{ .bold = true, .reverse = true },
            .disabled_style = .{ .dim = true },
            .shortcut_style = .{},
        };
    }

    /// Set the origin position where the menu should render
    pub fn withOrigin(self: ContextMenu, x: u16, y: u16) ContextMenu {
        var result = self;
        result.origin_x = x;
        result.origin_y = y;
        return result;
    }

    /// Set the optional block (border) for the menu
    pub fn withBlock(self: ContextMenu, block: Block) ContextMenu {
        var result = self;
        result.block = block;
        return result;
    }

    /// Set the style for unselected items
    pub fn withItemStyle(self: ContextMenu, style: Style) ContextMenu {
        var result = self;
        result.item_style = style;
        return result;
    }

    /// Set the style for the selected item
    pub fn withSelectedStyle(self: ContextMenu, style: Style) ContextMenu {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Set the style for disabled items
    pub fn withDisabledStyle(self: ContextMenu, style: Style) ContextMenu {
        var result = self;
        result.disabled_style = style;
        return result;
    }

    /// Set the style for shortcut text
    pub fn withShortcutStyle(self: ContextMenu, style: Style) ContextMenu {
        var result = self;
        result.shortcut_style = style;
        return result;
    }

    /// Set the cursor position
    pub fn withCursor(self: ContextMenu, cursor: usize) ContextMenu {
        var result = self;
        result.cursor = cursor;
        return result;
    }

    /// Move cursor down, skipping separators and wrapping around
    pub fn moveDown(self: ContextMenu) ContextMenu {
        var result = self;
        if (self.items.len == 0) return result;

        var next_cursor = (self.cursor + 1) % self.items.len;
        while (next_cursor != self.cursor) : (next_cursor = (next_cursor + 1) % self.items.len) {
            if (self.isSelectableAt(next_cursor)) {
                result.cursor = next_cursor;
                return result;
            }
        }
        return result;
    }

    /// Move cursor up, skipping separators and wrapping around
    pub fn moveUp(self: ContextMenu) ContextMenu {
        var result = self;
        if (self.items.len == 0) return result;

        var next_cursor = if (self.cursor == 0) self.items.len - 1 else self.cursor - 1;
        while (next_cursor != self.cursor) : (next_cursor = if (next_cursor == 0) self.items.len - 1 else next_cursor - 1) {
            if (self.isSelectableAt(next_cursor)) {
                result.cursor = next_cursor;
                return result;
            }
        }
        return result;
    }

    /// Count non-separator items
    pub fn actionCount(self: ContextMenu) usize {
        var count: usize = 0;
        for (self.items) |item| {
            switch (item) {
                .separator => {},
                else => count += 1,
            }
        }
        return count;
    }

    /// Get the current item
    pub fn currentItem(self: ContextMenu) ?Item {
        if (self.cursor < self.items.len) {
            return self.items[self.cursor];
        }
        return null;
    }

    /// Check if the current item is selectable (enabled action/submenu)
    pub fn isCurrentSelectable(self: ContextMenu) bool {
        if (self.cursor >= self.items.len) return false;
        return self.isSelectableAt(self.cursor);
    }

    /// Check if an item at index is selectable
    fn isSelectableAt(self: ContextMenu, idx: usize) bool {
        if (idx >= self.items.len) return false;
        const item = self.items[idx];
        switch (item) {
            .action => |action| return action.enabled,
            .submenu => return true,
            .separator => return false,
        }
    }

    /// Get the preferred area to render the menu, auto-positioning within bounds
    pub fn fittingArea(self: ContextMenu, screen: Rect) Rect {
        // Calculate preferred width
        var preferred_width: u16 = 10; // minimum width

        for (self.items) |item| {
            switch (item) {
                .action => |action| {
                    var item_width = @as(u16, @intCast(action.label.len)) + 4; // label + padding
                    if (action.shortcut) |shortcut| {
                        item_width += @as(u16, @intCast(shortcut.len)) + 1; // shortcut + separator
                    }
                    if (item_width > preferred_width) {
                        preferred_width = item_width;
                    }
                },
                .submenu => |submenu| {
                    const item_width = @as(u16, @intCast(submenu.label.len)) + 3; // label + " >" + padding
                    if (item_width > preferred_width) {
                        preferred_width = item_width;
                    }
                },
                .separator => {
                    // Separators don't affect width
                },
            }
        }

        // Cap width at screen width
        if (preferred_width > screen.width) {
            preferred_width = screen.width;
        }

        // Calculate preferred height (items + 2 for borders, minimum 3)
        var preferred_height = @as(u16, @intCast(@min(self.items.len + 2, 255)));
        if (preferred_height < 3) {
            preferred_height = 3;
        }

        // Cap height at screen height
        if (preferred_height > screen.height) {
            preferred_height = screen.height;
        }

        var area = Rect{
            .x = self.origin_x,
            .y = self.origin_y,
            .width = preferred_width,
            .height = preferred_height,
        };

        // Clamp to screen bounds
        if (area.x + area.width > screen.x + screen.width) {
            area.x = @as(u16, @intCast(@max(0, @as(i32, screen.x) + @as(i32, screen.width) - @as(i32, area.width))));
        }
        if (area.y + area.height > screen.y + screen.height) {
            area.y = @as(u16, @intCast(@max(0, @as(i32, screen.y) + @as(i32, screen.height) - @as(i32, area.height))));
        }

        return area;
    }

    /// Render the context menu into a buffer
    pub fn render(self: ContextMenu, buf: *Buffer, area: Rect) void {
        // Early return if area is too small
        if (area.height == 0 or area.width == 0) return;

        // Draw optional border block
        if (self.block) |block| {
            block.render(buf, area);
        }

        // Calculate content area (inside borders if block exists)
        var content_area = area;
        if (self.block != null) {
            // If block exists, content is inside the borders
            if (content_area.height > 2) content_area.height -= 2;
            if (content_area.width > 2) content_area.width -= 2;
            content_area.x += 1;
            content_area.y += 1;
        }

        // Render each item
        var row: u16 = 0;
        for (self.items, 0..) |item, idx| {
            if (row >= content_area.height) break;

            const item_y = content_area.y + row;
            const is_current = (self.cursor == idx);

            switch (item) {
                .separator => {
                    // Draw separator line
                    const sep_char: u21 = if (content_area.width > 5) '─' else '-';
                    for (0..content_area.width) |col| {
                        buf.set(@intCast(content_area.x + col), item_y, .{
                            .char = sep_char,
                            .style = self.item_style,
                        });
                    }
                },
                .action => |action| {
                    // Determine style
                    const item_style = if (is_current)
                        self.selected_style
                    else if (!action.enabled)
                        self.disabled_style
                    else
                        self.item_style;

                    // Draw label with proper UTF-8 handling
                    var x: u16 = 1; // 1-char left padding
                    var label_idx: usize = 0;
                    while (label_idx < action.label.len and x < content_area.width) {
                        const byte = action.label[label_idx];
                        const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

                        if (label_idx + char_len > action.label.len) break;

                        const codepoint = if (char_len == 1)
                            @as(u21, byte)
                        else
                            std.unicode.utf8Decode(action.label[label_idx .. label_idx + char_len]) catch @as(u21, byte);

                        buf.set(@intCast(content_area.x + x), item_y, .{
                            .char = codepoint,
                            .style = item_style,
                        });
                        label_idx += char_len;
                        x += 1;
                    }

                    // Draw shortcut if present, right-aligned
                    if (action.shortcut) |shortcut| {
                        if (content_area.width > 5 and shortcut.len + 1 < content_area.width) {
                            const shortcut_x = @as(i16, @intCast(content_area.width)) - @as(i16, @intCast(shortcut.len)) - 1;
                            if (shortcut_x > 0) {
                                var sx: u16 = @intCast(shortcut_x);
                                var shortcut_idx: usize = 0;
                                while (shortcut_idx < shortcut.len and sx < content_area.width) {
                                    const byte = shortcut[shortcut_idx];
                                    const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

                                    if (shortcut_idx + char_len > shortcut.len) break;

                                    const codepoint = if (char_len == 1)
                                        @as(u21, byte)
                                    else
                                        std.unicode.utf8Decode(shortcut[shortcut_idx .. shortcut_idx + char_len]) catch @as(u21, byte);

                                    buf.set(@intCast(content_area.x + sx), item_y, .{
                                        .char = codepoint,
                                        .style = self.shortcut_style,
                                    });
                                    shortcut_idx += char_len;
                                    sx += 1;
                                }
                            }
                        }
                    }
                },
                .submenu => |submenu| {
                    // Determine style
                    const item_style = if (is_current)
                        self.selected_style
                    else
                        self.item_style;

                    // Draw label with proper UTF-8 handling
                    var x: u16 = 1; // 1-char left padding
                    var label_idx: usize = 0;
                    while (label_idx < submenu.label.len and x < content_area.width) {
                        const byte = submenu.label[label_idx];
                        const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

                        if (label_idx + char_len > submenu.label.len) break;

                        const codepoint = if (char_len == 1)
                            @as(u21, byte)
                        else
                            std.unicode.utf8Decode(submenu.label[label_idx .. label_idx + char_len]) catch @as(u21, byte);

                        buf.set(@intCast(content_area.x + x), item_y, .{
                            .char = codepoint,
                            .style = item_style,
                        });
                        label_idx += char_len;
                        x += 1;
                    }

                    // Draw submenu indicator (">") at right edge if space
                    if (content_area.width > 2) {
                        buf.set(@intCast(content_area.x + content_area.width - 1), item_y, .{
                            .char = '>',
                            .style = item_style,
                        });
                    }
                },
            }

            row += 1;
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

test "ContextMenu init creates menu with default values" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Save", .enabled = true } },
        .{ .action = .{ .label = "Exit", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.cursor);
    try testing.expectEqual(@as(u16, 0), menu.origin_x);
    try testing.expectEqual(@as(u16, 0), menu.origin_y);
    try testing.expectEqual(null, menu.block);
    try testing.expectEqual(false, menu.item_style.bold);
}

test "ContextMenu init with empty items" {
    const items: [0]ContextMenu.Item = .{};
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.cursor);
    try testing.expectEqual(@as(usize, 0), menu.items.len);
}

test "ContextMenu withOrigin sets x and y" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(10, 5);
    try testing.expectEqual(@as(u16, 10), menu.origin_x);
    try testing.expectEqual(@as(u16, 5), menu.origin_y);
}

test "ContextMenu withBlock sets block" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    var menu = ContextMenu.init(&items);
    const block = Block{};
    menu = menu.withBlock(block);
    try testing.expect(menu.block != null);
}

test "ContextMenu withItemStyle sets item_style" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    var menu = ContextMenu.init(&items);
    const style = Style{ .bold = true };
    menu = menu.withItemStyle(style);
    try testing.expectEqual(true, menu.item_style.bold);
}

test "ContextMenu withSelectedStyle sets selected_style" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    var menu = ContextMenu.init(&items);
    const style = Style{ .bold = false };
    menu = menu.withSelectedStyle(style);
    try testing.expectEqual(false, menu.selected_style.bold);
}

test "ContextMenu withDisabledStyle sets disabled_style" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    var menu = ContextMenu.init(&items);
    const style = Style{ .dim = false };
    menu = menu.withDisabledStyle(style);
    try testing.expectEqual(false, menu.disabled_style.dim);
}

test "ContextMenu withShortcutStyle sets shortcut_style" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    var menu = ContextMenu.init(&items);
    const style = Style{ .bold = true };
    menu = menu.withShortcutStyle(style);
    try testing.expectEqual(true, menu.shortcut_style.bold);
}

test "ContextMenu withCursor sets cursor position" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withCursor(1);
    try testing.expectEqual(@as(usize, 1), menu.cursor);
}

test "ContextMenu actionCount excludes separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 2), menu.actionCount());
}

test "ContextMenu actionCount with only actions" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 3), menu.actionCount());
}

test "ContextMenu actionCount with submenus" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 2), menu.actionCount());
}

test "ContextMenu actionCount empty list" {
    const items: [0]ContextMenu.Item = .{};
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.actionCount());
}

test "ContextMenu actionCount all separators" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items);
    try testing.expectEqual(@as(usize, 0), menu.actionCount());
}

test "ContextMenu moveDown basic advances cursor" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 1), menu.cursor);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

test "ContextMenu moveDown wraps from last to first" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(1);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown skips separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

test "ContextMenu moveDown skips disabled items" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = false } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 2), menu.cursor);
}

test "ContextMenu moveUp basic moves cursor back" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(2);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 1), menu.cursor);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp wraps from first to last" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(0);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 1), menu.cursor);
}

test "ContextMenu moveUp skips separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(2);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp skips disabled items" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = false } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items).withCursor(2);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown with empty items stays at cursor" {
    const items: [0]ContextMenu.Item = .{};
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp with empty items stays at cursor" {
    const items: [0]ContextMenu.Item = .{};
    var menu = ContextMenu.init(&items);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown with single action item stays at zero" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Only", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp with single action item stays at zero" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Only", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveDown with all separators stays at cursor" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .separator = {} },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveDown();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu moveUp with all separators stays at cursor" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .separator = {} },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.moveUp();
    try testing.expectEqual(@as(usize, 0), menu.cursor);
}

test "ContextMenu currentItem returns action item" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "First", .enabled = true } },
        .{ .action = .{ .label = "Second", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    const item = menu.currentItem();
    try testing.expect(item != null);
    try testing.expectEqual(ContextMenu.Item.action, @as(@TypeOf(item.?), @enumFromInt(@intFromEnum(item.?))));
}

test "ContextMenu currentItem returns separator" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items);
    const item = menu.currentItem();
    try testing.expect(item != null);
}

test "ContextMenu currentItem returns submenu" {
    const items = [_]ContextMenu.Item{
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);
    const item = menu.currentItem();
    try testing.expect(item != null);
}

test "ContextMenu currentItem returns null when out of bounds" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu.cursor = 10;
    const item = menu.currentItem();
    try testing.expectEqual(null, item);
}

test "ContextMenu isCurrentSelectable true for enabled action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable false for disabled action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = false } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(!menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable true for submenu" {
    const items = [_]ContextMenu.Item{
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable false for separator" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(!menu.isCurrentSelectable());
}

test "ContextMenu isCurrentSelectable false when cursor out of bounds" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu.cursor = 100;
    try testing.expect(!menu.isCurrentSelectable());
}

test "ContextMenu fittingArea at origin within screen" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(5, 5);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    try testing.expectEqual(@as(u16, 5), area.x);
    try testing.expectEqual(@as(u16, 5), area.y);
}

test "ContextMenu fittingArea height includes items and border" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    try testing.expectEqual(@as(u16, 5), area.height); // 3 items + 2 for borders
}

test "ContextMenu fittingArea clamps to screen width" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(80, 10);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    // Should clamp x so x + width <= screen.width
    try testing.expect(area.x + area.width <= screen.x + screen.width);
}

test "ContextMenu fittingArea clamps to screen height" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(10, 90);
    const screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const area = menu.fittingArea(screen);
    // Should clamp y so y + height <= screen.height
    try testing.expect(area.y + area.height <= screen.y + screen.height);
}

test "ContextMenu fittingArea with zero area size" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    var menu = ContextMenu.init(&items);
    menu = menu.withOrigin(0, 0);
    const screen = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const area = menu.fittingArea(screen);
    // Should handle gracefully without crashing
    try testing.expectEqual(@as(u16, 0), area.x);
}

test "ContextMenu render does not crash with empty buffer" {
    const items: [0]ContextMenu.Item = .{};
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit(testing.allocator);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);
}

test "ContextMenu render does not crash with narrow area" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 3, 10);
    defer buf.deinit(testing.allocator);
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 5 };
    menu.render(&buf, area);
}

test "ContextMenu render does not crash with single action" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Single Action", .shortcut = "Ctrl+S", .enabled = true } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit(testing.allocator);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    menu.render(&buf, area);
}

test "ContextMenu render does not crash with multiple items and separators" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Cut", .shortcut = "Ctrl+X", .enabled = true } },
        .{ .action = .{ .label = "Copy", .shortcut = "Ctrl+C", .enabled = true } },
        .{ .separator = {} },
        .{ .action = .{ .label = "Paste", .shortcut = "Ctrl+V", .enabled = false } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 80, 20);
    defer buf.deinit(testing.allocator);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 20 };
    menu.render(&buf, area);
}

test "ContextMenu render with submenu" {
    const sub_items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Sub1", .enabled = true } },
    };
    const items = [_]ContextMenu.Item{
        .{ .submenu = .{ .label = "Submenu", .items = &sub_items } },
    };
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 50, 10);
    defer buf.deinit(testing.allocator);
    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 10 };
    menu.render(&buf, area);
}

test "ContextMenu builder pattern fluent chaining" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    const menu = ContextMenu.init(&items)
        .withOrigin(10, 20)
        .withCursor(1)
        .withItemStyle(.{ .bold = true });

    try testing.expectEqual(@as(u16, 10), menu.origin_x);
    try testing.expectEqual(@as(u16, 20), menu.origin_y);
    try testing.expectEqual(@as(usize, 1), menu.cursor);
    try testing.expect(menu.item_style.bold);
}

test "ContextMenu Action with shortcut" {
    const action = ContextMenu.Action{ .label = "Save", .shortcut = "Ctrl+S", .enabled = true };
    try testing.expectEqualStrings("Save", action.label);
    try testing.expect(action.shortcut != null);
    try testing.expectEqualStrings("Ctrl+S", action.shortcut.?);
}

test "ContextMenu Action without shortcut" {
    const action = ContextMenu.Action{ .label = "Delete", .enabled = true };
    try testing.expectEqualStrings("Delete", action.label);
    try testing.expectEqual(null, action.shortcut);
}

test "ContextMenu Submenu with items" {
    const sub_items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Sub1", .enabled = true } },
    };
    const submenu = ContextMenu.Submenu{ .label = "Edit", .items = &sub_items };
    try testing.expectEqualStrings("Edit", submenu.label);
    try testing.expectEqual(@as(usize, 1), submenu.items.len);
}
