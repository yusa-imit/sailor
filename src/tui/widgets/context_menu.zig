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
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
const assert = std.debug.assert;

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

    /// Move cursor down, skipping separators and wrapping around. Visits each item at most
    /// once, so a menu with nothing selectable (or an out-of-range cursor) terminates.
    pub fn moveDown(self: ContextMenu) ContextMenu {
        var result = self;
        if (self.items.len == 0) return result;

        for (1..self.items.len + 1) |step| {
            const next_cursor = (self.cursor % self.items.len + step) % self.items.len;
            if (self.isSelectableAt(next_cursor)) {
                result.cursor = next_cursor;
                return result;
            }
        }
        return result;
    }

    /// Move cursor up, skipping separators and wrapping around. Bounded like `moveDown`.
    pub fn moveUp(self: ContextMenu) ContextMenu {
        var result = self;
        if (self.items.len == 0) return result;

        for (1..self.items.len + 1) |step| {
            const next_cursor = (self.cursor % self.items.len + self.items.len - step) %
                self.items.len;
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
        // Calculate preferred width in cells; saturating so huge labels cannot overflow u16.
        var preferred_width: u16 = 10; // minimum width

        for (self.items) |item| {
            const item_width: u16 = switch (item) {
                .action => |action| blk: {
                    var w = cellsU16(action.label) +| 4; // label + padding
                    if (action.shortcut) |shortcut| {
                        w +|= cellsU16(shortcut) +| 1; // shortcut + separator
                    }
                    break :blk w;
                },
                .submenu => |submenu| cellsU16(submenu.label) +| 4, // label + padding + ">"
                .separator => 0, // Separators don't affect width
            };
            preferred_width = @max(preferred_width, item_width);
        }

        // Cap width at screen width
        preferred_width = @min(preferred_width, screen.width);

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
        if (area.x +| area.width > screen.x +| screen.width) {
            const right: i32 = @as(i32, screen.x) + @as(i32, screen.width);
            area.x = @intCast(@max(0, right - @as(i32, area.width)));
        }
        if (area.y +| area.height > screen.y +| screen.height) {
            const bottom: i32 = @as(i32, screen.y) + @as(i32, screen.height);
            area.y = @intCast(@max(0, bottom - @as(i32, area.height)));
        }

        return area;
    }

    /// Render the context menu into a buffer
    pub fn render(self: ContextMenu, buf: *Buffer, area: Rect) void {
        // Early return if area is too small
        if (area.height == 0 or area.width == 0) return;

        // Draw optional border block; content lives inside it (empty if the area is too small)
        var content_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            content_area = block.inner(area);
        }

        // Render each item
        const visible = @min(self.items.len, content_area.height);
        for (self.items[0..visible], 0..) |item, idx| {
            const item_y = content_area.y +| @as(u16, @intCast(idx));
            const is_current = (self.cursor == idx);
            switch (item) {
                .separator => {
                    const sep_char: u21 = if (content_area.width > 5) '─' else '-';
                    const row = Rect{
                        .x = content_area.x,
                        .y = item_y,
                        .width = content_area.width,
                        .height = 1,
                    };
                    buf.fill(row, sep_char, self.item_style);
                },
                .action => |action| {
                    self.renderAction(buf, content_area, item_y, action, is_current);
                },
                .submenu => |submenu| {
                    const item_style = if (is_current) self.selected_style else self.item_style;
                    const has_arrow = content_area.width > 2;
                    // Label starts after 1 cell of padding; leave the last cell for ">".
                    const room = content_area.width -| (if (has_arrow) @as(u16, 2) else 1);
                    const label_x = content_area.x +| 1;
                    _ = drawClipped(buf, label_x, item_y, submenu.label, room, item_style);
                    if (has_arrow) {
                        const arrow_x = content_area.x +| content_area.width -| 1;
                        buf.set(arrow_x, item_y, .{ .char = '>', .style = item_style });
                    }
                },
            }
        }
    }

    fn renderAction(
        self: ContextMenu,
        buf: *Buffer,
        content: Rect,
        item_y: u16,
        action: Action,
        is_current: bool,
    ) void {
        const item_style = if (is_current)
            self.selected_style
        else if (!action.enabled)
            self.disabled_style
        else
            self.item_style;

        // Label after 1 cell of left padding
        const label_x = content.x +| 1;
        const room = content.width -| 1;
        const label_cells = drawClipped(buf, label_x, item_y, action.label, room, item_style);

        // Shortcut right-aligned with 1 cell of right padding, only if it clears the label
        const shortcut = action.shortcut orelse return;
        if (content.width <= 5) return;
        const sc_cells: u16 = cellsU16(shortcut);
        if (@as(u32, sc_cells) + 1 >= content.width) return;
        const sx: u16 = content.width - sc_cells - 1;
        assert(sx < content.width);
        if (sx <= 1 +| label_cells) return; // would touch or overwrite the label
        const sc_x = content.x +| sx;
        _ = drawClipped(buf, sc_x, item_y, shortcut, content.width - sx, self.shortcut_style);
    }
};

/// Display width of `text` in terminal cells, saturated to u16.
fn cellsU16(text: []const u8) u16 {
    return @intCast(@min(UnicodeWidth.stringWidth(text), std.math.maxInt(u16)));
}

/// Draw `text` at (x, y) clipped to `max_cells` cells without splitting a UTF-8 character.
/// Returns the number of cells occupied.
fn drawClipped(buf: *Buffer, x: u16, y: u16, text: []const u8, max_cells: u16, style: Style) u16 {
    const end = UnicodeWidth.truncate(text, max_cells);
    assert(end <= text.len);
    buf.setString(x, y, text[0..end], style);
    const used = UnicodeWidth.stringWidth(text[0..end]);
    assert(used <= max_cells);
    return @intCast(used);
}

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
    const item = menu.currentItem().?;
    try testing.expect(item == .action);
    try testing.expectEqualStrings("First", item.action.label);
    const second = menu.withCursor(1).currentItem().?;
    try testing.expectEqualStrings("Second", second.action.label);
}

test "ContextMenu currentItem returns separator" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items);
    try testing.expect(menu.currentItem().? == .separator);
}

test "ContextMenu currentItem returns submenu" {
    const items = [_]ContextMenu.Item{
        .{ .submenu = .{ .label = "Sub", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);
    const item = menu.currentItem().?;
    try testing.expect(item == .submenu);
    try testing.expectEqualStrings("Sub", item.submenu.label);
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

const big_screen = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };

test "ContextMenu fittingArea at origin within screen" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(5, 5);
    const area = menu.fittingArea(big_screen);
    // Minimum width 10; height = 2 items + 2 borders.
    try testing.expectEqual(Rect{ .x = 5, .y = 5, .width = 10, .height = 4 }, area);
}

test "ContextMenu fittingArea height includes items and border" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    const area = ContextMenu.init(&items).fittingArea(big_screen);
    try testing.expectEqual(@as(u16, 5), area.height); // 3 items + 2 for borders
}

test "ContextMenu fittingArea shifts left so the menu ends at the screen edge" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    const menu = ContextMenu.init(&items).withOrigin(95, 10);
    const area = menu.fittingArea(big_screen);
    try testing.expectEqual(Rect{ .x = 90, .y = 10, .width = 10, .height = 3 }, area);
}

test "ContextMenu fittingArea shifts up so the menu ends at the screen edge" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .enabled = true } },
        .{ .action = .{ .label = "B", .enabled = true } },
        .{ .action = .{ .label = "C", .enabled = true } },
    };
    const menu = ContextMenu.init(&items).withOrigin(10, 98);
    const area = menu.fittingArea(big_screen);
    try testing.expectEqual(Rect{ .x = 10, .y = 95, .width = 10, .height = 5 }, area);
}

test "ContextMenu fittingArea honours a screen that does not start at the origin" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    const menu = ContextMenu.init(&items).withOrigin(25, 25);
    const screen = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };
    const area = menu.fittingArea(screen);
    // Right edge 35 > 30 so x moves to 30 - 10 = 20; bottom edge 28 fits so y stays.
    try testing.expectEqual(Rect{ .x = 20, .y = 25, .width = 10, .height = 3 }, area);
}

test "ContextMenu fittingArea with zero-size screen collapses to an empty rect" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A", .enabled = true } }};
    const menu = ContextMenu.init(&items).withOrigin(0, 0);
    const screen = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const expected = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    try testing.expectEqual(expected, menu.fittingArea(screen));
}

test "ContextMenu fittingArea width covers label, shortcut and padding" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Save", .shortcut = "Ctrl+S", .enabled = true } },
    };
    const area = ContextMenu.init(&items).fittingArea(big_screen);
    try testing.expectEqual(@as(u16, 15), area.width); // 4 + 4 + 6 + 1
}

test "ContextMenu fittingArea submenu width leaves room for label and arrow" {
    const items = [_]ContextMenu.Item{.{ .submenu = .{ .label = "Submenu", .items = &.{} } }};
    const area = ContextMenu.init(&items).fittingArea(big_screen);
    try testing.expectEqual(@as(u16, 11), area.width); // 7 + 4
}

test "ContextMenu fittingArea measures multibyte labels in cells, not bytes" {
    const label = "日本語日本語";
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = label, .enabled = true } }};
    const area = ContextMenu.init(&items).fittingArea(big_screen);
    try testing.expectEqual(@as(u16, 16), area.width); // 12 cells + 4
}

test "ContextMenu fittingArea caps width and height at the screen size" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "a very long label indeed, longer than the screen" } },
        .{ .action = .{ .label = "B" } },
        .{ .action = .{ .label = "C" } },
    };
    const screen = Rect{ .x = 0, .y = 0, .width = 20, .height = 4 };
    const area = ContextMenu.init(&items).fittingArea(screen);
    try testing.expectEqual(Rect{ .x = 0, .y = 0, .width = 20, .height = 4 }, area);
}

test "ContextMenu fittingArea survives a label wider than u16" {
    const huge = try testing.allocator.alloc(u8, 70_000);
    defer testing.allocator.free(huge);
    @memset(huge, 'x');
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = huge, .shortcut = huge } }};
    const area = ContextMenu.init(&items).fittingArea(big_screen);
    try testing.expectEqual(@as(u16, 100), area.width);
}

test "ContextMenu fittingArea height saturates for very long menus" {
    const items = try testing.allocator.alloc(ContextMenu.Item, 400);
    defer testing.allocator.free(items);
    @memset(items, .{ .separator = {} });
    const tall = Rect{ .x = 0, .y = 0, .width = 100, .height = 1000 };
    const area = ContextMenu.init(items).fittingArea(tall);
    try testing.expectEqual(@as(u16, 255), area.height);
}

/// Assert the narrow glyphs of `expected` occupy consecutive cells starting at (x, y).
fn expectRow(buf: *const Buffer, x: u16, y: u16, expected: []const u8) !void {
    var it = (try std.unicode.Utf8View.init(expected)).iterator();
    var col = x;
    while (it.nextCodepoint()) |cp| : (col += 1) {
        try testing.expectEqual(cp, buf.getChar(col, y));
    }
}

test "ContextMenu render with empty items leaves the buffer untouched" {
    const items: [0]ContextMenu.Item = .{};
    const menu = ContextMenu.init(&items);
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });

    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

test "ContextMenu render with a zero-size area draws nothing" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "A" } }};
    const menu = ContextMenu.init(&items).withBlock(.{});
    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();

    menu.render(&buf, .{ .x = 2, .y = 2, .width = 0, .height = 5 });
    menu.render(&buf, .{ .x = 2, .y = 2, .width = 5, .height = 0 });

    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

test "ContextMenu render narrow area clips label to the content width" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "ABC" } }};
    var buf = try Buffer.init(testing.allocator, 10, 3);
    defer buf.deinit();

    ContextMenu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 3, .height = 2 });

    // Content is 3 cells: 1 padding then 2 label cells; nothing leaks into x=3.
    try expectRow(&buf, 0, 0, " AB");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(3, 0));
}

test "ContextMenu render places label, right-aligned shortcut and styles per state" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Cut", .shortcut = "Ctrl+X" } },
        .{ .action = .{ .label = "Copy", .shortcut = "Ctrl+C" } },
        .{ .separator = {} },
        .{ .action = .{ .label = "Paste", .shortcut = "Ctrl+V", .enabled = false } },
    };
    const menu = ContextMenu.init(&items).withShortcutStyle(.{ .italic = true });
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 5 });

    // Content width 20: label from col 1, shortcut starts at 20 - 6 - 1 = 13.
    try expectRow(&buf, 0, 0, " Cut");
    try expectRow(&buf, 13, 0, "Ctrl+X");
    try expectRow(&buf, 0, 1, " Copy");
    try expectRow(&buf, 13, 1, "Ctrl+C");
    try expectRow(&buf, 0, 3, " Paste");
    try expectRow(&buf, 13, 3, "Ctrl+V");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(19, 0));
    for (0..20) |col| try testing.expectEqual(@as(u21, '─'), buf.getChar(@intCast(col), 2));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(20, 2));
    // Row 4 has no item.
    try expectRow(&buf, 0, 4, "                    ");
    // Styles: cursor row selected, other enabled row plain, disabled dim, shortcut italic.
    try testing.expect(buf.getStyle(1, 0).bold and buf.getStyle(1, 0).reverse);
    try testing.expect(!buf.getStyle(1, 1).bold and !buf.getStyle(1, 1).dim);
    try testing.expect(buf.getStyle(1, 3).dim);
    try testing.expect(buf.getStyle(13, 0).italic and !buf.getStyle(13, 0).bold);
    try testing.expect(buf.getStyle(13, 3).italic);
}

test "ContextMenu render inside a block uses the border and offsets content by one" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Cut", .shortcut = "Ctrl+X" } },
        .{ .separator = {} },
        .{ .action = .{ .label = "Paste", .shortcut = "Ctrl+V" } },
    };
    const menu = ContextMenu.init(&items).withBlock(.{}).withOrigin(2, 1);
    const area = menu.fittingArea(big_screen);
    try testing.expectEqual(Rect{ .x = 2, .y = 1, .width = 16, .height = 5 }, area);
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    menu.render(&buf, area);

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(2, 1));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(17, 1));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(2, 5));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(17, 5));
    // Content x=3..16 (14 cells), y=2..4. Shortcut column = 14 - 6 - 1 = 7.
    try expectRow(&buf, 3, 2, " Cut");
    try expectRow(&buf, 10, 2, "Ctrl+X");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(2, 2));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(17, 2));
    for (3..17) |col| try testing.expectEqual(@as(u21, '─'), buf.getChar(@intCast(col), 3));
    try expectRow(&buf, 3, 4, " Paste");
    try expectRow(&buf, 10, 4, "Ctrl+V");
}

test "ContextMenu render submenu draws label then arrow in the last content cell" {
    const sub_items = [_]ContextMenu.Item{.{ .action = .{ .label = "Sub1" } }};
    const items = [_]ContextMenu.Item{.{ .submenu = .{ .label = "Submenu", .items = &sub_items } }};
    const menu = ContextMenu.init(&items).withBlock(.{});
    const area = menu.fittingArea(big_screen);
    var buf = try Buffer.init(testing.allocator, 30, 10);
    defer buf.deinit();

    menu.render(&buf, area);

    // Area width 11: border x=0 and x=10, content x=1..9, label from x=2, arrow at x=9.
    try expectRow(&buf, 2, 1, "Submenu>");
    try testing.expectEqual(@as(u21, '│'), buf.getChar(10, 1));
    try testing.expect(buf.getStyle(9, 1).bold and buf.getStyle(9, 1).reverse);
}

test "ContextMenu render submenu label is clipped so the arrow stays visible" {
    const items = [_]ContextMenu.Item{.{ .submenu = .{ .label = "Submenu", .items = &.{} } }};
    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();

    ContextMenu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 6, .height = 1 });

    try expectRow(&buf, 0, 0, " Subm>");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(6, 0));
}

test "ContextMenu render wide-character labels advance two cells per glyph" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "日本語" } }};
    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();

    ContextMenu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 5, .height = 1 });

    // Room is 4 cells after the padding: two wide glyphs fit, the third is cut whole.
    try testing.expectEqual(@as(u21, '日'), buf.getChar(1, 0));
    try testing.expectEqual(@as(u21, '本'), buf.getChar(3, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(5, 0));
}

test "ContextMenu render drops a shortcut that would overwrite the label" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "Long label here", .shortcut = "Ctrl+Shift+X" } },
    };
    var buf = try Buffer.init(testing.allocator, 30, 1);
    defer buf.deinit();

    ContextMenu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 1 });

    try expectRow(&buf, 0, 0, " Long label here");
    try expectRow(&buf, 16, 0, "    ");
}

test "ContextMenu render block too short for content keeps the bottom border intact" {
    const items = [_]ContextMenu.Item{ .{ .action = .{ .label = "A" } }, .{ .separator = {} } };
    var buf = try Buffer.init(testing.allocator, 12, 6);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 8, .height = 2 };
    ContextMenu.init(&items).withBlock(.{}).render(&buf, area);

    try testing.expectEqual(@as(u21, '└'), buf.getChar(0, 1));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(3, 1));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(7, 1));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(1, 2)); // nothing below the area
}

test "ContextMenu render stops at the area height" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A" } },
        .{ .action = .{ .label = "B" } },
        .{ .action = .{ .label = "C" } },
    };
    var buf = try Buffer.init(testing.allocator, 8, 4);
    defer buf.deinit();

    ContextMenu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });

    try expectRow(&buf, 0, 0, " A");
    try expectRow(&buf, 0, 1, " B");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(1, 2));
}

test "ContextMenu render clips at the buffer edge without writing elsewhere" {
    const items = [_]ContextMenu.Item{.{ .action = .{ .label = "Hello" } }};
    var buf = try Buffer.init(testing.allocator, 5, 2);
    defer buf.deinit();

    ContextMenu.init(&items).render(&buf, .{ .x = 3, .y = 0, .width = 20, .height = 5 });

    try testing.expectEqual(@as(u21, 'H'), buf.getChar(4, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(3, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
}

test "ContextMenu render near the u16 limit does not overflow" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A", .shortcut = "S" } },
        .{ .separator = {} },
    };
    var buf = try Buffer.init(testing.allocator, 4, 4);
    defer buf.deinit();

    const area = Rect{ .x = 65530, .y = 65530, .width = 65535, .height = 65535 };
    ContextMenu.init(&items).withBlock(.{}).render(&buf, area);

    for (buf.cells) |cell| try testing.expect(cell.eql(.{}));
}

test "ContextMenu moveDown with out-of-range cursor and nothing selectable terminates" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .action = .{ .label = "off", .enabled = false } },
    };
    const menu = ContextMenu.init(&items).withCursor(10);

    try testing.expectEqual(@as(usize, 10), menu.moveDown().cursor);
    try testing.expectEqual(@as(usize, 10), menu.moveUp().cursor);
}

test "ContextMenu move with only disabled items stays put" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "a", .enabled = false } },
        .{ .action = .{ .label = "b", .enabled = false } },
    };
    const menu = ContextMenu.init(&items).withCursor(1);

    try testing.expectEqual(@as(usize, 1), menu.moveDown().cursor);
    try testing.expectEqual(@as(usize, 1), menu.moveUp().cursor);
}

test "ContextMenu move from out-of-range cursor lands on a selectable in-range item" {
    const items = [_]ContextMenu.Item{
        .{ .separator = {} },
        .{ .action = .{ .label = "A" } },
        .{ .separator = {} },
    };
    const menu = ContextMenu.init(&items).withCursor(10);

    try testing.expectEqual(@as(usize, 1), menu.moveDown().cursor);
    try testing.expectEqual(@as(usize, 1), menu.moveUp().cursor);
}

test "ContextMenu move reaches submenus" {
    const items = [_]ContextMenu.Item{
        .{ .action = .{ .label = "A" } },
        .{ .separator = {} },
        .{ .submenu = .{ .label = "S", .items = &.{} } },
    };
    const menu = ContextMenu.init(&items);

    try testing.expectEqual(@as(usize, 2), menu.moveDown().cursor);
    try testing.expectEqual(@as(usize, 2), menu.moveUp().cursor);
}

/// Reference model: index of the next selectable item strictly after (down) or before (up)
/// `cursor`, wrapping; `cursor` itself if no other item is selectable.
fn modelMove(items: []const ContextMenu.Item, cursor: usize, down: bool) usize {
    var selectable: [32]usize = undefined;
    var n: usize = 0;
    for (items, 0..) |item, i| {
        const ok = switch (item) {
            .action => |a| a.enabled,
            .submenu => true,
            .separator => false,
        };
        if (ok) {
            selectable[n] = i;
            n += 1;
        }
    }
    if (n == 0) return cursor;
    if (down) {
        for (selectable[0..n]) |i| if (i > cursor) return i;
        return selectable[0];
    }
    var k = n;
    while (k > 0) {
        k -= 1;
        if (selectable[k] < cursor) return selectable[k];
    }
    return selectable[n - 1];
}

test "ContextMenu seeded random menus move like the sorted-index reference model" {
    var prng = std.Random.DefaultPrng.init(0xc0ffee);
    const random = prng.random();
    var storage: [12]ContextMenu.Item = undefined;

    for (0..200) |_| {
        const len = random.intRangeAtMost(usize, 1, storage.len);
        for (storage[0..len]) |*item| {
            item.* = switch (random.uintLessThan(u8, 4)) {
                0 => .{ .separator = {} },
                1 => .{ .action = .{ .label = "off", .enabled = false } },
                2 => .{ .submenu = .{ .label = "sub", .items = &.{} } },
                else => .{ .action = .{ .label = "on" } },
            };
        }
        var menu = ContextMenu.init(storage[0..len]).withCursor(random.uintLessThan(usize, len));
        for (0..20) |_| {
            const down = random.boolean();
            const expected = modelMove(menu.items, menu.cursor, down);
            menu = if (down) menu.moveDown() else menu.moveUp();
            try testing.expectEqual(expected, menu.cursor);
        }
    }
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
