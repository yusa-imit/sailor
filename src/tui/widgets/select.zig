//! Select/Dropdown widget for single- or multi-select from a list of items.
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;
const assert = std.debug.assert;

/// Select/Dropdown widget for single or multi-select
pub const Select = struct {
    items: []const []const u8,
    selected: []bool, // For multi-select
    current: usize = 0, // Currently highlighted item
    multi: bool = false,
    block: ?Block = null,
    style: Style = .{},
    highlight_style: Style = .{ .bold = true, .underline = true },
    selected_style: Style = .{ .fg = .green },
    max_visible: ?usize = null, // Max items visible before scrolling
    scroll_offset: usize = 0,
    show_help: bool = true,

    /// Creates a new select widget with the given items and mode.
    /// Allocates a selection state array. Must be freed with `.deinit()`.
    /// `multi`: true for multi-select (checkboxes), false for single-select (radio buttons).
    pub fn init(allocator: std.mem.Allocator, items: []const []const u8, multi: bool) !Select {
        const selected = try allocator.alloc(bool, items.len);
        @memset(selected, false);
        return .{
            .items = items,
            .selected = selected,
            .multi = multi,
        };
    }

    /// Frees the internal selection state array.
    pub fn deinit(self: *Select, allocator: std.mem.Allocator) void {
        allocator.free(self.selected);
    }

    /// Sets an optional border block around the select widget.
    /// Returns a new select instance for method chaining.
    pub fn withBlock(self: Select, block: Block) Select {
        var result = self;
        result.block = block;
        return result;
    }

    /// Sets the default style for unhighlighted, unselected items.
    /// Returns a new select instance for method chaining.
    pub fn withStyle(self: Select, style: Style) Select {
        var result = self;
        result.style = style;
        return result;
    }

    /// Sets the style applied to the currently highlighted item.
    /// Default: bold + reversed. Returns a new select instance for method chaining.
    pub fn withHighlightStyle(self: Select, style: Style) Select {
        var result = self;
        result.highlight_style = style;
        return result;
    }

    /// Sets the style applied to selected items (when not highlighted).
    /// Default: green foreground. Returns a new select instance for method chaining.
    pub fn withSelectedStyle(self: Select, style: Style) Select {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Sets the maximum number of visible items before scrolling.
    /// If not set, all items are visible (no scrolling).
    /// Returns a new select instance for method chaining.
    pub fn withMaxVisible(self: Select, max: usize) Select {
        var result = self;
        result.max_visible = max;
        return result;
    }

    /// Controls whether to display keyboard shortcut help text at the bottom.
    /// Help text varies by mode (multi-select vs single-select).
    /// Returns a new select instance for method chaining.
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
    pub fn adjustScroll(self: *Select) void {
        if (self.max_visible) |max| {
            if (self.current < self.scroll_offset) {
                self.scroll_offset = self.current;
            } else if (self.current >= self.scroll_offset + max) {
                self.scroll_offset = self.current - max + 1;
            }
        }
    }

    /// Draws `text` at (x, y) clipped to the cells left of `x_end`; returns the next free column.
    /// Cell-wise: wide characters take two cells and are never split at the clip edge.
    fn putText(buf: *Buffer, x: u16, y: u16, x_end: u16, text: []const u8, style: Style) u16 {
        const limit: usize = x_end -| x;
        const len = UnicodeWidth.truncate(text, limit);
        assert(len <= text.len);
        assert(UnicodeWidth.stringWidth(text[0..len]) <= limit);
        buf.setString(x, y, text[0..len], style);
        return x +| @as(u16, @intCast(@min(UnicodeWidth.stringWidth(text[0..len]), limit)));
    }

    /// Renders the select widget to the given buffer within the specified area.
    /// Items show an indicator: checkbox (multi-select) or radio button (single-select).
    /// Scrolls when items exceed max visible count. The highlighted item is visually distinct.
    pub fn render(self: Select, buf: *Buffer, area: Rect) void {
        assert(self.selected.len == self.items.len);
        buf.fill(area, ' ', self.style);

        var render_area = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }
        if (render_area.width == 0 or render_area.height == 0) return;

        // Reserve space for help text
        const help_height: u16 = if (self.show_help) 1 else 0;
        const items_height = render_area.height -| help_height;
        const x_end = render_area.x +| render_area.width;

        // Calculate visible range
        const max_visible = if (self.max_visible) |max|
            @min(max, items_height)
        else
            items_height;

        const visible_start = @min(self.scroll_offset, self.items.len);
        const visible_end = @min(visible_start +| max_visible, self.items.len);
        assert(visible_start <= visible_end);

        // Render items
        var y: u16 = 0;
        for (visible_start..visible_end) |i| {
            if (y >= items_height) break;

            const is_current = (i == self.current);
            const is_selected = self.selected[i];

            // Determine style
            const item_style = if (is_current)
                self.highlight_style
            else if (is_selected)
                self.selected_style
            else
                self.style;

            const item_y = render_area.y +| y;
            const indicator: []const u8 = if (self.multi)
                (if (is_selected) "[✓] " else "[ ] ")
            else if (is_selected)
                "● "
            else
                "○ ";

            const text_x = putText(buf, render_area.x, item_y, x_end, indicator, item_style);
            _ = putText(buf, text_x, item_y, x_end, self.items[i], item_style);

            y += 1;
        }

        // Render scroll indicators
        if (self.max_visible != null and items_height > 0) {
            const arrow_x = x_end - 1;
            if (visible_start > 0) {
                buf.set(arrow_x, render_area.y, .{ .char = '↑', .style = self.style });
            }
            if (visible_end < self.items.len) {
                const arrow_y = render_area.y +| (items_height - 1);
                buf.set(arrow_x, arrow_y, .{ .char = '↓', .style = self.style });
            }
        }

        // Render help text
        if (self.show_help) {
            const help_y = render_area.y +| (render_area.height - 1);
            const help_text = if (self.multi)
                "↑/↓: Navigate | Space: Toggle | Enter: Confirm"
            else
                "↑/↓: Navigate | Enter: Select";
            const help_style = Style{ .fg = .bright_black };
            _ = putText(buf, render_area.x, help_y, x_end, help_text, help_style);
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
    select.selectCurrent();

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit();

    select.render(&buf, Rect{ .x = 0, .y = 0, .width = 30, .height = 5 });

    try std.testing.expectEqual(@as(u21, '●'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, 'O'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, 'A'), buf.getChar(9, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(10, 0));
    try std.testing.expectEqual(@as(u21, '○'), buf.getChar(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), buf.getChar(9, 1));
    try std.testing.expectEqual(@as(u21, '↑'), buf.getChar(0, 4));
    try std.testing.expectEqual(@as(u21, 'E'), buf.getChar(16, 4));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 2));
}

test "Select: render multi shows checkbox cells" {
    const items = [_][]const u8{ "ab", "cd" };
    var select = try Select.init(std.testing.allocator, &items, true);
    defer select.deinit(std.testing.allocator);
    select.toggleCurrent();

    var buf = try Buffer.init(std.testing.allocator, 12, 3);
    defer buf.deinit();

    select.withHelp(false).render(&buf, Rect{ .x = 0, .y = 0, .width = 12, .height = 3 });

    try std.testing.expectEqual(@as(u21, '['), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, '✓'), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, ']'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, 'a'), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, 'b'), buf.getChar(5, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(1, 1));
    try std.testing.expectEqual(@as(u21, 'c'), buf.getChar(4, 1));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(0, 2));
}

test "Select: render with block" {
    const items = [_][]const u8{"Item 1"};
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    const block = (Block{}).withTitle("Choose", .top_left);
    select = select.withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 25, 5);
    defer buf.deinit();

    select.render(&buf, Rect{ .x = 0, .y = 0, .width = 25, .height = 5 });

    try std.testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, '┐'), buf.getChar(24, 0));
    try std.testing.expectEqual(@as(u21, '○'), buf.getChar(1, 1));
    try std.testing.expectEqual(@as(u21, 'I'), buf.getChar(3, 1));
    try std.testing.expectEqual(@as(u21, '└'), buf.getChar(0, 4));
}

test "Select: render clips to narrow area (regression: wrote past area)" {
    const items = [_][]const u8{"abcdef"};
    var select = try Select.init(std.testing.allocator, &items, true);
    defer select.deinit(std.testing.allocator);

    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();
    buf.fill(Rect{ .x = 0, .y = 0, .width = 10, .height = 2 }, '#', .{});

    select.withHelp(false).render(&buf, Rect{ .x = 0, .y = 0, .width = 3, .height = 2 });

    try std.testing.expectEqual(@as(u21, '['), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(1, 0));
    try std.testing.expectEqual(@as(u21, ']'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(3, 0));
    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(3, 1));
}

test "Select: render draws wide characters by cell (regression: byte-wise)" {
    const items = [_][]const u8{"你好x"};
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);

    var buf = try Buffer.init(std.testing.allocator, 12, 1);
    defer buf.deinit();

    select.withHelp(false).render(&buf, Rect{ .x = 0, .y = 0, .width = 12, .height = 1 });
    try std.testing.expectEqual(@as(u21, '你'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, '好'), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, 'x'), buf.getChar(6, 0));

    // Width 5: text gets 3 cells; the second wide char must not be cut in half.
    buf.fill(Rect{ .x = 0, .y = 0, .width = 12, .height = 1 }, '#', .{});
    select.withHelp(false).render(&buf, Rect{ .x = 0, .y = 0, .width = 5, .height = 1 });
    try std.testing.expectEqual(@as(u21, '你'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, ' '), buf.getChar(4, 0));
    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(5, 0));
}

test "Select: scroll_offset past end renders nothing (regression: range panic)" {
    const items = [_][]const u8{ "a", "b" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);
    select.scroll_offset = std.math.maxInt(usize);

    var buf = try Buffer.init(std.testing.allocator, 8, 3);
    defer buf.deinit();

    select.withHelp(false).render(&buf, Rect{ .x = 0, .y = 0, .width = 8, .height = 3 });

    for (0..3) |row| {
        for (0..8) |col| {
            try std.testing.expectEqual(@as(u21, ' '), buf.getChar(@intCast(col), @intCast(row)));
        }
    }
}

test "Select: zero width area with height does not touch buffer (regression: underflow)" {
    const items = [_][]const u8{ "a", "b", "c" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);
    select = select.withMaxVisible(2);
    select.scroll_offset = 1;

    var buf = try Buffer.init(std.testing.allocator, 6, 3);
    defer buf.deinit();
    buf.fill(Rect{ .x = 0, .y = 0, .width = 6, .height = 3 }, '#', .{});

    select.render(&buf, Rect{ .x = 2, .y = 0, .width = 0, .height = 3 });

    for (0..3) |row| {
        for (0..6) |col| {
            try std.testing.expectEqual(@as(u21, '#'), buf.getChar(@intCast(col), @intCast(row)));
        }
    }
}

test "Select: render near u16 max does not overflow (regression)" {
    const items = [_][]const u8{"abc"};
    var select = try Select.init(std.testing.allocator, &items, true);
    defer select.deinit(std.testing.allocator);

    var buf = try Buffer.init(std.testing.allocator, 4, 2);
    defer buf.deinit();
    buf.fill(Rect{ .x = 0, .y = 0, .width = 4, .height = 2 }, '#', .{});

    const max = std.math.maxInt(u16);
    select.render(&buf, Rect{ .x = max - 1, .y = max - 1, .width = 100, .height = 100 });

    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(0, 0));
    try std.testing.expectEqual(@as(u21, '#'), buf.getChar(3, 1));
}

test "Select: scroll indicators sit in the last column" {
    const items = [_][]const u8{ "1", "2", "3", "4", "5" };
    var select = try Select.init(std.testing.allocator, &items, false);
    defer select.deinit(std.testing.allocator);
    select = select.withMaxVisible(2).withHelp(false);
    select.scroll_offset = 1;

    var buf = try Buffer.init(std.testing.allocator, 6, 2);
    defer buf.deinit();

    select.render(&buf, Rect{ .x = 0, .y = 0, .width = 6, .height = 2 });

    try std.testing.expectEqual(@as(u21, '↑'), buf.getChar(5, 0));
    try std.testing.expectEqual(@as(u21, '↓'), buf.getChar(5, 1));
    try std.testing.expectEqual(@as(u21, '2'), buf.getChar(2, 0));
    try std.testing.expectEqual(@as(u21, '3'), buf.getChar(2, 1));
}

test "Select: withStyle builder" {
    const items = [_][]const u8{"Item 1"};
    var select1 = try Select.init(std.testing.allocator, &items, false);
    defer select1.deinit(std.testing.allocator);

    const custom_style = Style{ .fg = Color.fromRgb(128, 128, 128), .dim = true };
    const select2 = select1.withStyle(custom_style);

    try std.testing.expect(select2.style.fg != null);
    if (select2.style.fg) |fg| {
        try std.testing.expectEqual(Color.fromRgb(128, 128, 128), fg);
    }
    try std.testing.expect(select2.style.dim);
}

test "Select: withHighlightStyle builder" {
    const items = [_][]const u8{"Item 1"};
    var select1 = try Select.init(std.testing.allocator, &items, false);
    defer select1.deinit(std.testing.allocator);

    const highlight_style = Style{ .fg = .cyan, .bold = true };
    const select2 = select1.withHighlightStyle(highlight_style);

    try std.testing.expect(select2.highlight_style.fg != null);
    if (select2.highlight_style.fg) |fg| {
        try std.testing.expectEqual(@as(Color, .cyan), fg);
    }
    try std.testing.expect(select2.highlight_style.bold);
}

test "Select: withSelectedStyle builder" {
    const items = [_][]const u8{"Item 1"};
    var select1 = try Select.init(std.testing.allocator, &items, false);
    defer select1.deinit(std.testing.allocator);

    const selected_style = Style{ .fg = .green, .italic = true };
    const select2 = select1.withSelectedStyle(selected_style);

    try std.testing.expect(select2.selected_style.fg != null);
    if (select2.selected_style.fg) |fg| {
        try std.testing.expectEqual(@as(Color, .green), fg);
    }
    try std.testing.expect(select2.selected_style.italic);
}

test "Select: withMaxVisible builder" {
    const items = [_][]const u8{ "Item 1", "Item 2", "Item 3" };
    var select1 = try Select.init(std.testing.allocator, &items, false);
    defer select1.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?usize, null), select1.max_visible);

    const select2 = select1.withMaxVisible(5);
    try std.testing.expectEqual(@as(?usize, 5), select2.max_visible);

    const select3 = select2.withMaxVisible(3);
    try std.testing.expectEqual(@as(?usize, 3), select3.max_visible);
}

test "Select: withHelp builder" {
    const items = [_][]const u8{"Item 1"};
    var select1 = try Select.init(std.testing.allocator, &items, false);
    defer select1.deinit(std.testing.allocator);

    try std.testing.expect(select1.show_help);

    const select2 = select1.withHelp(false);
    try std.testing.expect(!select2.show_help);

    const select3 = select2.withHelp(true);
    try std.testing.expect(select3.show_help);
}
