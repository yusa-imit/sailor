const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const symbols = @import("../symbols.zig");

/// Select/Dropdown widget for single or multi-select
pub const Select = struct {
    items: []const []const u8,
    selected: []bool, // For multi-select
    current: usize = 0, // Currently highlighted item
    multi: bool = false,
    block: ?Block = null,
    style: Style = .{},
    highlight_style: Style = .{ .bold = true, .reversed = true },
    selected_style: Style = .{ .fg = .green },
    max_visible: ?usize = null, // Max items visible before scrolling
    scroll_offset: usize = 0,
    show_help: bool = true,

    pub fn init(allocator: std.mem.Allocator, items: []const []const u8, multi: bool) !Select {
        const selected = try allocator.alloc(bool, items.len);
        @memset(selected, false);
        return .{
            .items = items,
            .selected = selected,
            .multi = multi,
        };
    }

    pub fn deinit(self: *Select, allocator: std.mem.Allocator) void {
        allocator.free(self.selected);
    }

    pub fn withBlock(self: Select, block: Block) Select {
        var result = self;
        result.block = block;
        return result;
    }

    pub fn withStyle(self: Select, style: Style) Select {
        var result = self;
        result.style = style;
        return result;
    }

    pub fn withHighlightStyle(self: Select, style: Style) Select {
        var result = self;
        result.highlight_style = style;
        return result;
    }

    pub fn withSelectedStyle(self: Select, style: Style) Select {
        var result = self;
        result.selected_style = style;
        return result;
    }

    pub fn withMaxVisible(self: Select, max: usize) Select {
        var result = self;
        result.max_visible = max;
        return result;
    }

    pub fn withHelp(self: Select, show: bool) Select {
        var result = self;
        result.show_help = show;
        return result;
    }

    /// Get currently highlighted item
    pub fn currentItem(self: Select) ?[]const u8 {
        if (self.current < self.items.len) {
            return self.items[self.current];
        }
        return null;
    }

    /// Get all selected items (multi-select mode)
    pub fn selectedItems(self: Select, allocator: std.mem.Allocator) ![][]const u8 {
        var count: usize = 0;
        for (self.selected) |s| {
            if (s) count += 1;
        }

        var result = try allocator.alloc([]const u8, count);
        var idx: usize = 0;
        for (self.items, 0..) |item, i| {
            if (self.selected[i]) {
                result[idx] = item;
                idx += 1;
            }
        }
        return result;
    }

    /// Toggle selection of current item (multi-select mode)
    pub fn toggleCurrent(self: *Select) void {
        if (self.multi and self.current < self.selected.len) {
            self.selected[self.current] = !self.selected[self.current];
        }
    }

    /// Select current item (single-select mode)
    pub fn selectCurrent(self: *Select) void {
        if (!self.multi and self.current < self.selected.len) {
            // Clear all selections
            @memset(self.selected, false);
            // Select current
            self.selected[self.current] = true;
        }
    }

    /// Move highlight down
    pub fn next(self: *Select) void {
        if (self.items.len == 0) return;
        self.current = (self.current + 1) % self.items.len;
        self.adjustScroll();
    }

    /// Move highlight up
    pub fn prev(self: *Select) void {
        if (self.items.len == 0) return;
        if (self.current == 0) {
            self.current = self.items.len - 1;
        } else {
            self.current -= 1;
        }
        self.adjustScroll();
    }

    /// Adjust scroll offset to keep current item visible
    fn adjustScroll(self: *Select) void {
        if (self.max_visible) |max| {
            if (self.current < self.scroll_offset) {
                self.scroll_offset = self.current;
            } else if (self.current >= self.scroll_offset + max) {
                self.scroll_offset = self.current - max + 1;
            }
        }
    }

    pub fn render(self: Select, buf: *Buffer, area: Rect) void {
        // Clear area
        for (0..area.height) |y| {
            for (0..area.width) |x| {
                buf.set(@intCast(area.x + x), @intCast(area.y + y), .{
                    .char = ' ',
                    .style = self.style,
                });
            }
        }

        var render_area = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        // Reserve space for help text
        const help_height: u16 = if (self.show_help) 1 else 0;
        const items_height = if (render_area.height > help_height)
            render_area.height - help_height
        else
            0;

        // Calculate visible range
        const max_visible = if (self.max_visible) |max|
            @min(max, items_height)
        else
            items_height;

        const visible_start = self.scroll_offset;
        const visible_end = @min(visible_start + max_visible, self.items.len);

        // Render items
        var y: u16 = 0;
        for (visible_start..visible_end) |i| {
            if (y >= items_height) break;

            const item = self.items[i];
            const is_current = (i == self.current);
            const is_selected = self.selected[i];

            // Determine style
            const item_style = if (is_current)
                self.highlight_style
            else if (is_selected)
                self.selected_style
            else
                self.style;

            const item_y = render_area.y + y;

            // Render selection indicator
            var x: u16 = 0;
            if (self.multi) {
                const indicator: u21 = if (is_selected) '✓' else ' ';
                buf.set(render_area.x, item_y, .{
                    .char = '[',
                    .style = item_style,
                });
                buf.set(render_area.x + 1, item_y, .{
                    .char = indicator,
                    .style = item_style,
                });
                buf.set(render_area.x + 2, item_y, .{
                    .char = ']',
                    .style = item_style,
                });
                buf.set(render_area.x + 3, item_y, .{
                    .char = ' ',
                    .style = item_style,
                });
                x = 4;
            } else if (is_selected) {
                buf.set(render_area.x, item_y, .{
                    .char = symbols.radio.selected,
                    .style = item_style,
                });
                buf.set(render_area.x + 1, item_y, .{
                    .char = ' ',
                    .style = item_style,
                });
                x = 2;
            } else {
                buf.set(render_area.x, item_y, .{
                    .char = symbols.radio.unselected,
                    .style = item_style,
                });
                buf.set(render_area.x + 1, item_y, .{
                    .char = ' ',
                    .style = item_style,
                });
                x = 2;
            }

            // Render item text
            for (item) |ch| {
                if (x >= render_area.width) break;
                buf.set(@intCast(render_area.x + x), item_y, .{
                    .char = @intCast(ch),
                    .style = item_style,
                });
                x += 1;
            }

            y += 1;
        }

        // Render scroll indicators
        if (self.max_visible != null and items_height > 0) {
            if (visible_start > 0) {
                // Up arrow
                const arrow_y = render_area.y;
                buf.set(@intCast(render_area.x + render_area.width - 1), arrow_y, .{
                    .char = '↑',
                    .style = self.style,
                });
            }
            if (visible_end < self.items.len) {
                // Down arrow
                const arrow_y = render_area.y + items_height - 1;
                buf.set(@intCast(render_area.x + render_area.width - 1), arrow_y, .{
                    .char = '↓',
                    .style = self.style,
                });
            }
        }

        // Render help text
        if (self.show_help and render_area.height > 0) {
            const help_y = render_area.y + render_area.height - 1;
            const help_text = if (self.multi)
                "↑/↓: Navigate | Space: Toggle | Enter: Confirm"
            else
                "↑/↓: Navigate | Enter: Select";
            const help_style = Style{ .fg = .gray };

            for (help_text, 0..) |ch, x| {
                if (x >= render_area.width) break;
                buf.set(@intCast(render_area.x + x), help_y, .{
                    .char = @intCast(ch),
                    .style = help_style,
                });
            }
        }
    }
};

// Tests

test "Select: init single" {
    const items = [_][]const u8{ "Option 1", "Option 2", "Option 3" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    try std.testing.expectEqual(3, select.items.len);
    try std.testing.expect(!select.multi);
    try std.testing.expectEqual(0, select.current);
}

test "Select: init multi" {
    const items = [_][]const u8{ "Item A", "Item B" };
    var select = try Select.init(std.testing.allocator, &items, true);
    defer select.deinit(std.testing.allocator);

    try std.testing.expect(select.multi);
    try std.testing.expectEqual(2, select.selected.len);
}

test "Select: navigation" {
    const items = [_][]const u8{ "First", "Second", "Third" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    try std.testing.expectEqual(0, select.current);

    select.next();
    try std.testing.expectEqual(1, select.current);

    select.next();
    try std.testing.expectEqual(2, select.current);

    select.next(); // wraps around
    try std.testing.expectEqual(0, select.current);

    select.prev();
    try std.testing.expectEqual(2, select.current);

    select.prev();
    try std.testing.expectEqual(1, select.current);
}

test "Select: currentItem" {
    const items = [_][]const u8{ "Apple", "Banana", "Cherry" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    const item1 = select.currentItem();
    try std.testing.expect(item1 != null);
    try std.testing.expectEqualStrings("Apple", item1.?);

    select.next();
    const item2 = select.currentItem();
    try std.testing.expectEqualStrings("Banana", item2.?);
}

test "Select: single select" {
    const items = [_][]const u8{ "A", "B", "C" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    // Initially nothing selected
    try std.testing.expect(!select.selected[0]);

    // Select first item
    select.selectCurrent();
    try std.testing.expect(select.selected[0]);
    try std.testing.expect(!select.selected[1]);

    // Move and select second item
    select.next();
    select.selectCurrent();
    try std.testing.expect(!select.selected[0]); // first deselected
    try std.testing.expect(select.selected[1]); // second selected
}

test "Select: multi select toggle" {
    const items = [_][]const u8{ "X", "Y", "Z" };
    var select = try Select.init(std.testing.allocator, &items, true);
    defer select.deinit(std.testing.allocator);

    // Toggle first item
    select.toggleCurrent();
    try std.testing.expect(select.selected[0]);

    // Move and toggle second item
    select.next();
    select.toggleCurrent();
    try std.testing.expect(select.selected[0]); // still selected
    try std.testing.expect(select.selected[1]); // also selected

    // Toggle first item off
    select.prev();
    select.toggleCurrent();
    try std.testing.expect(!select.selected[0]); // deselected
    try std.testing.expect(select.selected[1]); // still selected
}

test "Select: selectedItems" {
    const items = [_][]const u8{ "Red", "Green", "Blue" };
    var select = try Select.init(std.testing.allocator, &items, true);
    defer select.deinit(std.testing.allocator);

    select.toggleCurrent(); // Select "Red"
    select.next();
    select.next();
    select.toggleCurrent(); // Select "Blue"

    const selected = try select.selectedItems(std.testing.allocator);
    defer std.testing.allocator.free(selected);

    try std.testing.expectEqual(2, selected.len);
    try std.testing.expectEqualStrings("Red", selected[0]);
    try std.testing.expectEqualStrings("Blue", selected[1]);
}

test "Select: scrolling" {
    const items = [_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    select = select.withMaxVisible(3);

    // Initially at top
    try std.testing.expectEqual(0, select.scroll_offset);

    // Navigate down
    select.next(); // current=1
    select.next(); // current=2
    try std.testing.expectEqual(0, select.scroll_offset);

    select.next(); // current=3, should scroll
    try std.testing.expectEqual(1, select.scroll_offset);

    select.next(); // current=4
    try std.testing.expectEqual(2, select.scroll_offset);

    // Navigate back up
    select.prev(); // current=3
    select.prev(); // current=2, should scroll back
    try std.testing.expectEqual(2, select.scroll_offset);
}

test "Select: render basic" {
    const items = [_][]const u8{ "Option A", "Option B" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    select.render(&buf, area);

    // Check first item is rendered
    const first_char = buf.get(2, 0); // After radio button
    try std.testing.expectEqual('O', first_char.char);
}

test "Select: render with block" {
    const items = [_][]const u8{ "Item 1" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    const block = Block.init().withTitle("Choose");
    select = select.withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 25, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 25, .height = 5 };
    select.render(&buf, area);

    // Check block border
    const top_left = buf.get(0, 0);
    try std.testing.expectEqual(symbols.border.plain.top_left, top_left.char);
}
