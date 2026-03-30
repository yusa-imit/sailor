const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const symbols = @import("../symbols.zig");

/// Radio button group for mutually exclusive selection
pub const RadioGroup = struct {
    items: []const []const u8,
    selected: ?usize = null, // Index of selected item, null if none
    focused: usize = 0, // Currently focused item
    block: ?Block = null,
    style: Style = .{},
    selected_style: Style = .{ .fg = .green },
    focused_style: Style = .{ .bold = true, .reversed = true },
    show_help: bool = true,

    /// Creates a new radio group from a slice of item labels.
    /// No item is selected initially. Focus starts on the first item.
    pub fn init(items: []const []const u8) RadioGroup {
        return .{ .items = items };
    }

    /// Sets the initially selected item by index.
    /// If index is out of bounds, no selection is made.
    /// Returns a new group instance for method chaining.
    pub fn withSelected(self: RadioGroup, index: usize) RadioGroup {
        var result = self;
        if (index < result.items.len) {
            result.selected = index;
        }
        return result;
    }

    /// Sets an optional border block around the radio group.
    /// Returns a new group instance for method chaining.
    pub fn withBlock(self: RadioGroup, block: Block) RadioGroup {
        var result = self;
        result.block = block;
        return result;
    }

    /// Sets the default style for unselected, unfocused items.
    /// Returns a new group instance for method chaining.
    pub fn withStyle(self: RadioGroup, style: Style) RadioGroup {
        var result = self;
        result.style = style;
        return result;
    }

    /// Sets the style applied to the selected item.
    /// Default: green foreground. Returns a new group instance for method chaining.
    pub fn withSelectedStyle(self: RadioGroup, style: Style) RadioGroup {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Sets the style applied to the focused item.
    /// Default: bold + reversed. Returns a new group instance for method chaining.
    pub fn withFocusedStyle(self: RadioGroup, style: Style) RadioGroup {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Controls whether to display keyboard shortcut help text at the bottom.
    /// Help text: "↑/↓: Navigate | Enter/Space: Select | Esc: Clear"
    /// Returns a new group instance for method chaining.
    pub fn withHelp(self: RadioGroup, show: bool) RadioGroup {
        var result = self;
        result.show_help = show;
        return result;
    }

    /// Get currently focused item
    pub fn focusedItem(self: RadioGroup) ?[]const u8 {
        if (self.focused < self.items.len) {
            return self.items[self.focused];
        }
        return null;
    }

    /// Get currently selected item
    pub fn selectedItem(self: RadioGroup) ?[]const u8 {
        if (self.selected) |idx| {
            if (idx < self.items.len) {
                return self.items[idx];
            }
        }
        return null;
    }

    /// Get index of selected item
    pub fn selectedIndex(self: RadioGroup) ?usize {
        return self.selected;
    }

    /// Move focus to next item
    pub fn focusNext(self: *RadioGroup) void {
        if (self.items.len == 0) return;
        self.focused = (self.focused + 1) % self.items.len;
    }

    /// Move focus to previous item
    pub fn focusPrev(self: *RadioGroup) void {
        if (self.items.len == 0) return;
        if (self.focused == 0) {
            self.focused = self.items.len - 1;
        } else {
            self.focused -= 1;
        }
    }

    /// Select currently focused item
    pub fn selectFocused(self: *RadioGroup) void {
        if (self.focused < self.items.len) {
            self.selected = self.focused;
        }
    }

    /// Select item by index
    pub fn select(self: *RadioGroup, index: usize) void {
        if (index < self.items.len) {
            self.selected = index;
            self.focused = index;
        }
    }

    /// Clear selection
    pub fn clearSelection(self: *RadioGroup) void {
        self.selected = null;
    }

    /// Renders the radio group to the given buffer within the specified area.
    /// Displays all items vertically with radio indicators (◉ for selected, ○ for unselected).
    /// The focused item is visually highlighted. Optional border block and help text are rendered.
    pub fn render(self: RadioGroup, buf: *Buffer, area: Rect) void {
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

        // Render items
        var y: u16 = 0;
        for (self.items, 0..) |item, i| {
            if (y >= items_height) break;

            const is_focused = (i == self.focused);
            const is_selected = if (self.selected) |sel| sel == i else false;

            // Determine style
            const item_style = if (is_focused)
                self.focused_style
            else if (is_selected)
                self.selected_style
            else
                self.style;

            const item_y = render_area.y + y;

            // Render radio button indicator
            const indicator = if (is_selected) symbols.radio.selected else symbols.radio.unselected;
            buf.set(render_area.x, item_y, .{
                .char = indicator,
                .style = item_style,
            });

            buf.set(render_area.x + 1, item_y, .{
                .char = ' ',
                .style = item_style,
            });

            // Render item text
            var x: u16 = 2;
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

        // Render help text
        if (self.show_help and render_area.height > 0) {
            const help_y = render_area.y + render_area.height - 1;
            const help_text = "↑/↓: Navigate | Enter/Space: Select | Esc: Clear";
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

test "RadioGroup: init" {
    const items = [_][]const u8{ "Option A", "Option B", "Option C" };
    const group = RadioGroup.init(&items);

    try std.testing.expectEqual(3, group.items.len);
    try std.testing.expectEqual(null, group.selected);
    try std.testing.expectEqual(0, group.focused);
}

test "RadioGroup: withSelected" {
    const items = [_][]const u8{ "First", "Second", "Third" };
    const group = RadioGroup.init(&items).withSelected(1);

    try std.testing.expectEqual(1, group.selected.?);
}

test "RadioGroup: focus navigation" {
    const items = [_][]const u8{ "A", "B", "C" };
    var group = RadioGroup.init(&items);

    try std.testing.expectEqual(0, group.focused);

    group.focusNext();
    try std.testing.expectEqual(1, group.focused);

    group.focusNext();
    try std.testing.expectEqual(2, group.focused);

    group.focusNext(); // wraps around
    try std.testing.expectEqual(0, group.focused);

    group.focusPrev();
    try std.testing.expectEqual(2, group.focused);

    group.focusPrev();
    try std.testing.expectEqual(1, group.focused);
}

test "RadioGroup: focusedItem" {
    const items = [_][]const u8{ "Apple", "Banana", "Cherry" };
    var group = RadioGroup.init(&items);

    const item1 = group.focusedItem();
    try std.testing.expect(item1 != null);
    try std.testing.expectEqualStrings("Apple", item1.?);

    group.focusNext();
    const item2 = group.focusedItem();
    try std.testing.expectEqualStrings("Banana", item2.?);
}

test "RadioGroup: selectFocused" {
    const items = [_][]const u8{ "Red", "Green", "Blue" };
    var group = RadioGroup.init(&items);

    // Initially nothing selected
    try std.testing.expectEqual(null, group.selected);

    // Select first item
    group.selectFocused();
    try std.testing.expectEqual(0, group.selected.?);

    // Move and select second item
    group.focusNext();
    group.selectFocused();
    try std.testing.expectEqual(1, group.selected.?); // first deselected automatically
}

test "RadioGroup: selectedItem" {
    const items = [_][]const u8{ "X", "Y", "Z" };
    var group = RadioGroup.init(&items);

    // Initially nothing selected
    try std.testing.expectEqual(null, group.selectedItem());

    // Select middle item
    group.focused = 1;
    group.selectFocused();

    const selected = group.selectedItem();
    try std.testing.expect(selected != null);
    try std.testing.expectEqualStrings("Y", selected.?);
}

test "RadioGroup: select by index" {
    const items = [_][]const u8{ "One", "Two", "Three" };
    var group = RadioGroup.init(&items);

    group.select(2);
    try std.testing.expectEqual(2, group.selected.?);
    try std.testing.expectEqual(2, group.focused); // focus follows selection
}

test "RadioGroup: clearSelection" {
    const items = [_][]const u8{ "A", "B" };
    var group = RadioGroup.init(&items).withSelected(1);

    try std.testing.expectEqual(1, group.selected.?);

    group.clearSelection();
    try std.testing.expectEqual(null, group.selected);
}

test "RadioGroup: mutual exclusion" {
    const items = [_][]const u8{ "Option 1", "Option 2", "Option 3" };
    var group = RadioGroup.init(&items);

    // Select first
    group.selectFocused();
    try std.testing.expectEqual(0, group.selected.?);

    // Select second - first should be deselected
    group.focusNext();
    group.selectFocused();
    try std.testing.expectEqual(1, group.selected.?);

    // Select third - second should be deselected
    group.focusNext();
    group.selectFocused();
    try std.testing.expectEqual(2, group.selected.?);
}

test "RadioGroup: selectedIndex" {
    const items = [_][]const u8{ "Foo", "Bar", "Baz" };
    var group = RadioGroup.init(&items);

    try std.testing.expectEqual(null, group.selectedIndex());

    group.select(1);
    try std.testing.expectEqual(1, group.selectedIndex().?);
}

test "RadioGroup: render basic" {
    const items = [_][]const u8{ "Choice A", "Choice B" };
    const group = RadioGroup.init(&items);

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    group.render(&buf, area);

    // Check radio button indicator
    const radio = buf.get(0, 0);
    try std.testing.expectEqual(symbols.radio.unselected, radio.char);

    // Check first item text
    const first_char = buf.get(2, 0);
    try std.testing.expectEqual('C', first_char.char);
}

test "RadioGroup: render with selection" {
    const items = [_][]const u8{ "Unselected", "Selected" };
    const group = RadioGroup.init(&items).withSelected(1);

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    group.render(&buf, area);

    // Check second item has selected indicator
    const selected_radio = buf.get(0, 1);
    try std.testing.expectEqual(symbols.radio.selected, selected_radio.char);
}

test "RadioGroup: render with block" {
    const items = [_][]const u8{ "Option" };
    const block = Block.init().withTitle("Choose one");
    const group = RadioGroup.init(&items).withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    group.render(&buf, area);

    // Check block border
    const top_left = buf.get(0, 0);
    try std.testing.expectEqual(symbols.border.plain.top_left, top_left.char);
}
