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
