//! Menu widget: hierarchical dropdown/popup menus with keyboard navigation.
const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

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
        // An out-of-range selection re-enters the menu at the first item.
        if (self.selected >= self.items.len) {
            self.selected = 0;
            return;
        }
        self.selected = (self.selected + 1) % self.items.len;
    }

    /// Move selection up (wraps around)
    pub fn moveUp(self: *Menu) void {
        if (self.items.len == 0) return;
        // An out-of-range selection re-enters the menu at the last item.
        if (self.selected == 0 or self.selected > self.items.len) {
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

    /// Render the menu widget. Output is clipped to `area` and to the buffer.
    pub fn render(self: Menu, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        std.debug.assert(area.width > 0);
        std.debug.assert(area.height > 0);

        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }
        if (inner_area.width == 0 or inner_area.height == 0) return;

        self.renderItems(buf, inner_area, self.items, self.selected);
        self.renderSubmenu(buf, inner_area);
    }

    /// Render the open submenu (if any) to the right of the main item column.
    fn renderSubmenu(self: Menu, buf: *Buffer, inner: Rect) void {
        std.debug.assert(inner.width > 0);
        std.debug.assert(inner.height > 0);
        const idx = self.submenu_open orelse return;
        if (idx >= self.items.len) return;
        const sub_items = self.items[idx].submenu orelse return;

        var column_width: usize = 0;
        for (self.items) |item| {
            var w = UnicodeWidth.stringWidth(item.label);
            if (item.submenu != null) w += UnicodeWidth.stringWidth(self.submenu_indicator);
            column_width = @max(column_width, w);
        }

        // +1 column of spacing; all arithmetic in usize so no u16 wrap near the edge.
        const offset = column_width + 1;
        if (offset >= inner.width) return;
        const row: u16 = @intCast(@min(idx, inner.height));
        const submenu_area = Rect{
            .x = inner.x +| @as(u16, @intCast(offset)),
            .y = inner.y +| row,
            .width = inner.width - @as(u16, @intCast(offset)),
            .height = inner.height - row,
        };
        // No item is selected inside the submenu.
        self.renderItems(buf, submenu_area, sub_items, std.math.maxInt(usize));
    }

    /// Render one column of menu items, one per row, clipped to `area` and the buffer.
    fn renderItems(
        self: Menu,
        buf: *Buffer,
        area: Rect,
        items: []const MenuItem,
        selected_idx: usize,
    ) void {
        const x_end = @min(area.x +| area.width, buf.width);
        if (area.x >= x_end) return;
        const rows_max: usize = @min(area.height, items.len);
        std.debug.assert(rows_max <= area.height);
        std.debug.assert(x_end <= buf.width);

        for (items[0..rows_max], 0..) |item, i| {
            const y = area.y +| @as(u16, @intCast(i));
            if (y >= buf.height) break;
            const base_style = if (i == selected_idx) self.selected_style else self.item_style;
            var x = self.drawLabel(buf, item, y, .{ .x = area.x, .end = x_end }, base_style);
            if (item.submenu != null) {
                x = drawText(buf, self.submenu_indicator, y, .{ .x = x, .end = x_end }, base_style);
            }
            // Selected row: full-width highlight.
            while (i == selected_idx and x < x_end) : (x += 1) {
                buf.set(x, y, .{ .char = ' ', .style = base_style });
            }
        }
    }

    /// Horizontal span `[x, end)` a draw call may write into.
    const Span = struct { x: u16, end: u16 };

    /// Draw `item.label`, styling the first character matching the hotkey (case-insensitive).
    /// Returns the x after the last drawn cell.
    fn drawLabel(
        self: Menu,
        buf: *Buffer,
        item: MenuItem,
        y: u16,
        span: Span,
        base_style: Style,
    ) u16 {
        std.debug.assert(span.x <= span.end);
        std.debug.assert(span.end <= buf.width);
        const hotkey_lower = if (item.hotkey) |hk| toLower(hk) else null;
        var hotkey_pending = hotkey_lower != null;
        var x = span.x;
        var i: usize = 0;
        while (i < item.label.len) {
            const step = decode(item.label[i..]);
            i += step.len;
            const w = UnicodeWidth.charWidth(step.codepoint);
            if (w == 0) continue;
            if (@as(u32, x) + w > span.end) break;
            var style = base_style;
            const is_hotkey = step.codepoint < 128 and hotkey_pending and
                toLower(@intCast(step.codepoint)) == hotkey_lower.?;
            if (is_hotkey) {
                style = mergeStyles(base_style, self.hotkey_style);
                hotkey_pending = false;
            }
            buf.set(x, y, .{ .char = step.codepoint, .style = style });
            x += w;
        }
        return x;
    }

    /// Draw `text` in one style. Returns the x after the last drawn cell.
    fn drawText(buf: *Buffer, text: []const u8, y: u16, span: Span, style: Style) u16 {
        std.debug.assert(span.x <= span.end);
        std.debug.assert(span.end <= buf.width);
        var x = span.x;
        var i: usize = 0;
        while (i < text.len) {
            const step = decode(text[i..]);
            i += step.len;
            const w = UnicodeWidth.charWidth(step.codepoint);
            if (w == 0) continue;
            if (@as(u32, x) + w > span.end) break;
            buf.set(x, y, .{ .char = step.codepoint, .style = style });
            x += w;
        }
        return x;
    }

    /// Decode the first codepoint of non-empty `text`; malformed bytes decode as themselves.
    fn decode(text: []const u8) struct { codepoint: u21, len: u3 } {
        std.debug.assert(text.len > 0);
        const len: u3 = std.unicode.utf8ByteSequenceLength(text[0]) catch return .{
            .codepoint = text[0],
            .len = 1,
        };
        if (len > text.len) return .{ .codepoint = text[0], .len = 1 };
        const cp = std.unicode.utf8Decode(text[0..len]) catch
            return .{ .codepoint = text[0], .len = 1 };
        return .{ .codepoint = cp, .len = len };
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
    const blk = (Block{}).withTitle("Menu", .top_left);

    const menu = Menu.init(&items).withBlock(blk);
    try std.testing.expectEqualStrings("Menu", menu.block.?.title.?);
}

test "menu withItemStyle sets item style" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const style = Style{ .fg = .{ .indexed = 1 } };

    const menu = Menu.init(&items).withItemStyle(style);
    try std.testing.expectEqual(@as(?Color, .{ .indexed = 1 }), menu.item_style.fg);
    try std.testing.expectEqual(@as(?Color, null), menu.selected_style.fg);
}

test "menu withSelectedStyle sets selected style" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const style = Style{ .bg = .{ .indexed = 4 } };

    const menu = Menu.init(&items).withSelectedStyle(style);
    try std.testing.expectEqual(@as(?Color, .{ .indexed = 4 }), menu.selected_style.bg);
    try std.testing.expectEqual(@as(?Color, null), menu.item_style.bg);
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

fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try std.testing.expectEqual(@as(u21, ' '), cell.char);
}

test "menu render with zero width area draws nothing" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items).withBlock(Block{});

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 10 });
    try expectBlank(buf);
}

test "menu render with zero height area draws nothing" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items).withBlock(Block{});

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    try expectBlank(buf);
}

test "menu render into an empty buffer is a no-op" {
    const items = [_]Menu.MenuItem{.{ .label = "File" }};
    const menu = Menu.init(&items).withSelected(0);

    var buf = try Buffer.init(std.testing.allocator, 0, 0);
    defer buf.deinit();

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    try std.testing.expectEqual(@as(usize, 0), buf.cells.len);
}

test "menu render items without selection styling" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{
        .{ .label = "File" },
        .{ .label = "Edit" },
    };

    const menu = Menu.init(&items).withSelected(0);
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);

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

    const selected_style = Style{ .bg = .{ .indexed = 4 } };
    const menu = Menu.init(&items).withSelected(0).withSelectedStyle(selected_style);

    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);

    // Check selected item has background color
    const style = buf.getStyle(0, 0);
    try std.testing.expect(style.bg != null);
    try std.testing.expectEqual(@as(u8, 4), style.bg.?.indexed);

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
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);

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
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);

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

    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);

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

    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);

    // Check lowercase 'f' matches uppercase 'F' hotkey
    const f_style = buf.getStyle(0, 0);
    try std.testing.expect(f_style.bold);
}

test "menu render with block consumes space" {
    const allocator = std.testing.allocator;
    const items = [_]Menu.MenuItem{.{ .label = "File" }};

    const blk = (Block{}).withBorders(.{ .top = true, .left = true });
    const menu = Menu.init(&items).withBlock(blk);

    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    menu.render(&buf, area);

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
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 3 };
    menu.render(&buf, area);

    // Only first 3 items render; rows 3 and 4 stay blank.
    try std.testing.expectEqual('3', buf.getChar(4, 2));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 3));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 4));
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

    var buf = try Buffer.init(allocator, 20, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    menu.render(&buf, area);

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

    var buf = try Buffer.init(allocator, 5, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 10 };
    menu.render(&buf, area);

    // Submenu won't fit (column is 6 wide, area 5): only "File" + clipped indicator.
    try std.testing.expectEqual('F', buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
    for (buf.cells) |cell| try std.testing.expect(cell.char != 'N');
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
    const base = Style{ .fg = .{ .indexed = 1 } };
    const overlay = Style{ .fg = .{ .indexed = 2 } };
    const result = Menu.mergeStyles(base, overlay);
    try std.testing.expectEqual(@as(u8, 2), result.fg.?.indexed);
}

test "menu mergeStyles keeps base fg when overlay fg is null" {
    const base = Style{ .fg = .{ .indexed = 1 } };
    const overlay = Style{ .bg = .{ .indexed = 2 } };
    const result = Menu.mergeStyles(base, overlay);
    try std.testing.expectEqual(@as(u8, 1), result.fg.?.indexed);
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

test "menu render clips label to the area, not the buffer" {
    const items = [_]Menu.MenuItem{.{ .label = "Filename" }};
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    Menu.init(&items).render(&buf, .{ .x = 2, .y = 0, .width = 4, .height = 2 });

    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, 'F'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, 'e'), buf.getChar(5, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(6, 0));
}

test "menu render draws multibyte labels one codepoint per cell" {
    const items = [_]Menu.MenuItem{.{ .label = "Éditer" }};
    var buf = try Buffer.init(std.testing.allocator, 10, 1);
    defer buf.deinit();

    Menu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try std.testing.expectEqual(@as(u21, 'É'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, 'd'), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, 'r'), buf.getChar(5, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(6, 0));
}

test "menu render advances two cells for wide characters" {
    const items = [_]Menu.MenuItem{.{ .label = "漢字x" }};
    var buf = try Buffer.init(std.testing.allocator, 10, 1);
    defer buf.deinit();

    Menu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });
    try std.testing.expectEqual(@as(u21, '漢'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, '字'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, 'x'), buf.getChar(4, 0));

    // A wide character that straddles the right edge is dropped whole.
    buf.clear();
    Menu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 3, .height = 1 });
    try std.testing.expectEqual(@as(u21, '漢'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(2, 0));
}

test "menu render skips control bytes and keeps malformed bytes visible" {
    const items = [_]Menu.MenuItem{.{ .label = "a\x1bb\xffc" }};
    var buf = try Buffer.init(std.testing.allocator, 10, 1);
    defer buf.deinit();

    Menu.init(&items).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try std.testing.expectEqual(@as(u21, 'a'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, 0xff), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, 'c'), buf.getChar(3, 0));
}

test "menu render survives labels longer than a u16" {
    const long_label = "a" ** 70_000;
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{.{ .label = long_label, .submenu = &subitems }};
    var menu = Menu.init(&items);
    menu.openSubmenu();
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 2 });

    try std.testing.expectEqual(@as(u21, 'a'), buf.getChar(9, 0));
    // The submenu column starts beyond the area, so nothing is drawn on row 1.
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 1));
}

test "menu render at the u16 edge does not overflow" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .hotkey = 'f', .submenu = &subitems },
        .{ .label = "Edit" },
    };
    var menu = Menu.init(&items).withSelected(1).withBlock(Block{});
    menu.submenu_open = 0;
    var buf = try Buffer.init(std.testing.allocator, 8, 4);
    defer buf.deinit();
    const edge: u16 = std.math.maxInt(u16);

    menu.render(&buf, .{ .x = edge - 3, .y = edge - 3, .width = edge, .height = edge });
    menu.render(&buf, .{ .x = 0, .y = 0, .width = edge, .height = edge });

    try std.testing.expectEqual(@as(u21, 'F'), buf.getChar(1, 1));
    try std.testing.expectEqual(@as(u21, 'E'), buf.getChar(1, 2));
}

test "menu render ignores a stale or out-of-range open submenu" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{
        .{ .label = "File", .submenu = &subitems },
        .{ .label = "Edit" },
    };
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();
    var menu = Menu.init(&items);

    menu.submenu_open = 9;
    menu.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 3 });
    // Index 1 is in range but "Edit" has no submenu.
    menu.submenu_open = 1;
    menu.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 3 });
    // Submenu row beyond the area height: nothing to draw, nothing to crash.
    menu.submenu_open = 0;
    menu.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 1 });

    try std.testing.expectEqual(@as(u21, 'F'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), buf.getChar(0, 1));
    try std.testing.expectEqual(@as(u21, 'N'), buf.getChar(7, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(7, 1));
}

test "menu render highlights only the first hotkey occurrence" {
    const items = [_]Menu.MenuItem{.{ .label = "Save as", .hotkey = 'a' }};
    var buf = try Buffer.init(std.testing.allocator, 10, 1);
    defer buf.deinit();
    const menu = Menu.init(&items).withHotkeyStyle(.{ .bold = true });

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try std.testing.expect(!buf.getStyle(0, 0).bold); // S
    try std.testing.expect(buf.getStyle(1, 0).bold); // first a
    try std.testing.expect(!buf.getStyle(5, 0).bold); // "a" in "as"
    try std.testing.expectEqual(@as(u21, 'a'), buf.getChar(5, 0));
}

test "menu render highlights hotkey over the selected style" {
    const items = [_]Menu.MenuItem{.{ .label = "File", .hotkey = 'i' }};
    var buf = try Buffer.init(std.testing.allocator, 8, 1);
    defer buf.deinit();
    const menu = Menu.init(&items)
        .withSelectedStyle(.{ .bg = .blue, .fg = .white })
        .withHotkeyStyle(.{ .fg = .red, .bold = true });

    menu.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 1 });

    const hot = buf.getStyle(1, 0);
    try std.testing.expectEqual(@as(?Color, .red), hot.fg);
    try std.testing.expectEqual(@as(?Color, .blue), hot.bg);
    try std.testing.expect(hot.bold);
    try std.testing.expectEqual(@as(?Color, .white), buf.getStyle(0, 0).fg);
    try std.testing.expectEqual(@as(?Color, .blue), buf.getStyle(7, 0).bg);
}

test "menu render selected highlight is clipped to the area" {
    const items = [_]Menu.MenuItem{ .{ .label = "File" }, .{ .label = "Edit" } };
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();
    const menu = Menu.init(&items).withSelected(1).withSelectedStyle(.{ .bg = .blue });

    menu.render(&buf, .{ .x = 1, .y = 0, .width = 5, .height = 2 });

    try std.testing.expectEqual(@as(?Color, null), buf.getStyle(1, 0).bg);
    try std.testing.expectEqual(@as(?Color, null), buf.getStyle(0, 1).bg);
    try std.testing.expectEqual(@as(?Color, .blue), buf.getStyle(1, 1).bg);
    try std.testing.expectEqual(@as(?Color, .blue), buf.getStyle(5, 1).bg);
    try std.testing.expectEqual(@as(?Color, null), buf.getStyle(6, 1).bg);
}

test "menu render draws a multibyte submenu indicator and tolerates invalid utf8" {
    const subitems = [_]Menu.MenuItem{.{ .label = "New" }};
    const items = [_]Menu.MenuItem{.{ .label = "File", .submenu = &subitems }};
    var buf = try Buffer.init(std.testing.allocator, 12, 1);
    defer buf.deinit();

    const arrow = Menu.init(&items).withSubmenuIndicator(" ▶");
    arrow.render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });
    try std.testing.expectEqual(@as(u21, '▶'), buf.getChar(5, 0));

    // Invalid UTF-8 in the indicator no longer aborts rendering of the menu.
    buf.clear();
    const bad = Menu.init(&items).withSubmenuIndicator("\xff\xfe");
    bad.render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });
    try std.testing.expectEqual(@as(u21, 'e'), buf.getChar(3, 0));
    try std.testing.expectEqual(@as(u21, 0xff), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, 0xfe), buf.getChar(5, 0));
}

test "menu moveDown and moveUp survive an out-of-range selection" {
    const items = [_]Menu.MenuItem{ .{ .label = "A" }, .{ .label = "B" }, .{ .label = "C" } };
    const max = std.math.maxInt(usize);

    var down = Menu.init(&items).withSelected(max);
    down.moveDown();
    try std.testing.expectEqual(@as(usize, 0), down.selected);

    var up = Menu.init(&items).withSelected(max);
    up.moveUp();
    try std.testing.expectEqual(@as(usize, 2), up.selected);

    var edge = Menu.init(&items).withSelected(3);
    edge.moveUp();
    try std.testing.expectEqual(@as(usize, 2), edge.selected);
}
