const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const symbols = @import("../symbols.zig");

/// Single checkbox widget
pub const Checkbox = struct {
    label: []const u8,
    checked: bool = false,
    style: Style = .{},
    checked_style: Style = .{ .fg = .green },
    focused_style: Style = .{ .bold = true },
    is_focused: bool = false,

    /// Creates a new checkbox with the given label.
    /// Default state: unchecked, unfocused, default styles.
    pub fn init(label: []const u8) Checkbox {
        return .{ .label = label };
    }

    /// Sets the checked state of the checkbox.
    /// Returns a new checkbox instance for method chaining.
    pub fn withChecked(self: Checkbox, checked: bool) Checkbox {
        var result = self;
        result.checked = checked;
        return result;
    }

    /// Sets the default style applied when the checkbox is neither checked nor focused.
    /// Returns a new checkbox instance for method chaining.
    pub fn withStyle(self: Checkbox, style: Style) Checkbox {
        var result = self;
        result.style = style;
        return result;
    }

    /// Sets the style applied when the checkbox is checked.
    /// Default: green foreground. Returns a new checkbox instance for method chaining.
    pub fn withCheckedStyle(self: Checkbox, style: Style) Checkbox {
        var result = self;
        result.checked_style = style;
        return result;
    }

    /// Sets the style applied when the checkbox has focus.
    /// Default: bold. Returns a new checkbox instance for method chaining.
    pub fn withFocusedStyle(self: Checkbox, style: Style) Checkbox {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Sets the focus state of the checkbox.
    /// Used by CheckboxGroup to highlight the currently selected item.
    /// Returns a new checkbox instance for method chaining.
    pub fn withFocus(self: Checkbox, focused: bool) Checkbox {
        var result = self;
        result.is_focused = focused;
        return result;
    }

    /// Toggles the checkbox state between checked and unchecked.
    pub fn toggle(self: *Checkbox) void {
        self.checked = !self.checked;
    }

    /// Renders the checkbox to the given buffer within the specified area.
    /// Format: `[✓] Label` or `[ ] Label` depending on checked state.
    /// Applies appropriate style based on focus and checked state.
    pub fn render(self: Checkbox, buf: *Buffer, area: Rect) void {
        if (area.width < 4 or area.height == 0) return;

        const display_style = if (self.is_focused)
            self.focused_style
        else if (self.checked)
            self.checked_style
        else
            self.style;

        // Render checkbox indicator [✓] or [ ]
        buf.set(area.x, area.y, .{
            .char = '[',
            .style = display_style,
        });

        const indicator = if (self.checked) symbols.checkbox.checked else symbols.checkbox.unchecked;
        buf.set(area.x + 1, area.y, .{
            .char = indicator,
            .style = display_style,
        });

        buf.set(area.x + 2, area.y, .{
            .char = ']',
            .style = display_style,
        });

        buf.set(area.x + 3, area.y, .{
            .char = ' ',
            .style = display_style,
        });

        // Render label
        var x: u16 = 4;
        for (self.label) |ch| {
            if (x >= area.width) break;
            buf.set(@intCast(area.x + x), area.y, .{
                .char = @intCast(ch),
                .style = display_style,
            });
            x += 1;
        }
    }
};

/// Checkbox group for managing multiple related checkboxes
pub const CheckboxGroup = struct {
    items: []Checkbox,
    focused: usize = 0,
    block: ?Block = null,
    style: Style = .{},
    show_help: bool = true,

    /// Creates a new checkbox group from a slice of checkboxes.
    /// Focus starts on the first item. Help text is shown by default.
    pub fn init(items: []Checkbox) CheckboxGroup {
        return .{ .items = items };
    }

    /// Sets an optional border block around the checkbox group.
    /// Returns a new group instance for method chaining.
    pub fn withBlock(self: CheckboxGroup, block: Block) CheckboxGroup {
        var result = self;
        result.block = block;
        return result;
    }

    /// Sets the default style for the checkbox group background.
    /// Returns a new group instance for method chaining.
    pub fn withStyle(self: CheckboxGroup, style: Style) CheckboxGroup {
        var result = self;
        result.style = style;
        return result;
    }

    /// Controls whether to display keyboard shortcut help text at the bottom.
    /// Help text: "↑/↓: Navigate | Space: Toggle | A: All | N: None"
    /// Returns a new group instance for method chaining.
    pub fn withHelp(self: CheckboxGroup, show: bool) CheckboxGroup {
        var result = self;
        result.show_help = show;
        return result;
    }

    /// Get currently focused checkbox
    pub fn focusedItem(self: *CheckboxGroup) ?*Checkbox {
        if (self.focused < self.items.len) {
            return &self.items[self.focused];
        }
        return null;
    }

    /// Move focus to next checkbox
    pub fn focusNext(self: *CheckboxGroup) void {
        if (self.items.len == 0) return;
        self.focused = (self.focused + 1) % self.items.len;
    }

    /// Move focus to previous checkbox
    pub fn focusPrev(self: *CheckboxGroup) void {
        if (self.items.len == 0) return;
        if (self.focused == 0) {
            self.focused = self.items.len - 1;
        } else {
            self.focused -= 1;
        }
    }

    /// Toggle currently focused checkbox
    pub fn toggleFocused(self: *CheckboxGroup) void {
        if (self.focusedItem()) |item| {
            item.toggle();
        }
    }

    /// Get all checked items
    pub fn checkedItems(self: CheckboxGroup, allocator: std.mem.Allocator) ![][]const u8 {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.checked) count += 1;
        }

        var result = try allocator.alloc([]const u8, count);
        var idx: usize = 0;
        for (self.items) |item| {
            if (item.checked) {
                result[idx] = item.label;
                idx += 1;
            }
        }
        return result;
    }

    /// Check all checkboxes
    pub fn checkAll(self: *CheckboxGroup) void {
        for (self.items) |*item| {
            item.checked = true;
        }
    }

    /// Uncheck all checkboxes
    pub fn uncheckAll(self: *CheckboxGroup) void {
        for (self.items) |*item| {
            item.checked = false;
        }
    }

    /// Renders the checkbox group to the given buffer within the specified area.
    /// Displays all checkboxes vertically with optional border block and help text.
    /// The focused checkbox is visually highlighted.
    pub fn render(self: CheckboxGroup, buf: *Buffer, area: Rect) void {
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

        // Render checkboxes
        var y: u16 = 0;
        for (self.items, 0..) |item, i| {
            if (y >= items_height) break;

            const is_focused = (i == self.focused);
            const checkbox = item.withFocus(is_focused);

            const item_area = Rect{
                .x = render_area.x,
                .y = render_area.y + y,
                .width = render_area.width,
                .height = 1,
            };
            checkbox.render(buf, item_area);
            y += 1;
        }

        // Render help text
        if (self.show_help and render_area.height > 0) {
            const help_y = render_area.y + render_area.height - 1;
            const help_text = "↑/↓: Navigate | Space: Toggle | A: All | N: None";
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

test "Checkbox: init" {
    const cb = Checkbox.init("Accept terms");
    try std.testing.expectEqualStrings("Accept terms", cb.label);
    try std.testing.expect(!cb.checked);
}

test "Checkbox: withChecked" {
    const cb = Checkbox.init("Option").withChecked(true);
    try std.testing.expect(cb.checked);
}

test "Checkbox: toggle" {
    var cb = Checkbox.init("Toggle me");
    try std.testing.expect(!cb.checked);

    cb.toggle();
    try std.testing.expect(cb.checked);

    cb.toggle();
    try std.testing.expect(!cb.checked);
}

test "Checkbox: render unchecked" {
    const cb = Checkbox.init("Test");
    var buf = try Buffer.init(std.testing.allocator, 20, 1);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    cb.render(&buf, area);

    // Check indicator
    const indicator = buf.get(1, 0);
    try std.testing.expectEqual(symbols.checkbox.unchecked, indicator.char);
}

test "Checkbox: render checked" {
    const cb = Checkbox.init("Test").withChecked(true);
    var buf = try Buffer.init(std.testing.allocator, 20, 1);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 };
    cb.render(&buf, area);

    // Check indicator
    const indicator = buf.get(1, 0);
    try std.testing.expectEqual(symbols.checkbox.checked, indicator.char);
}

test "CheckboxGroup: init" {
    var items = [_]Checkbox{
        Checkbox.init("Option 1"),
        Checkbox.init("Option 2"),
    };

    const group = CheckboxGroup.init(&items);
    try std.testing.expectEqual(2, group.items.len);
    try std.testing.expectEqual(0, group.focused);
}

test "CheckboxGroup: focus navigation" {
    var items = [_]Checkbox{
        Checkbox.init("First"),
        Checkbox.init("Second"),
        Checkbox.init("Third"),
    };

    var group = CheckboxGroup.init(&items);

    try std.testing.expectEqual(0, group.focused);

    group.focusNext();
    try std.testing.expectEqual(1, group.focused);

    group.focusNext();
    try std.testing.expectEqual(2, group.focused);

    group.focusNext(); // wraps
    try std.testing.expectEqual(0, group.focused);

    group.focusPrev();
    try std.testing.expectEqual(2, group.focused);
}

test "CheckboxGroup: toggleFocused" {
    var items = [_]Checkbox{
        Checkbox.init("A"),
        Checkbox.init("B"),
    };

    var group = CheckboxGroup.init(&items);

    // Toggle first
    group.toggleFocused();
    try std.testing.expect(items[0].checked);
    try std.testing.expect(!items[1].checked);

    // Move and toggle second
    group.focusNext();
    group.toggleFocused();
    try std.testing.expect(items[0].checked);
    try std.testing.expect(items[1].checked);

    // Toggle first off
    group.focusPrev();
    group.toggleFocused();
    try std.testing.expect(!items[0].checked);
    try std.testing.expect(items[1].checked);
}

test "CheckboxGroup: checkedItems" {
    var items = [_]Checkbox{
        Checkbox.init("Red").withChecked(true),
        Checkbox.init("Green"),
        Checkbox.init("Blue").withChecked(true),
    };

    const group = CheckboxGroup.init(&items);
    const checked = try group.checkedItems(std.testing.allocator);
    defer std.testing.allocator.free(checked);

    try std.testing.expectEqual(2, checked.len);
    try std.testing.expectEqualStrings("Red", checked[0]);
    try std.testing.expectEqualStrings("Blue", checked[1]);
}

test "CheckboxGroup: checkAll and uncheckAll" {
    var items = [_]Checkbox{
        Checkbox.init("A"),
        Checkbox.init("B"),
        Checkbox.init("C"),
    };

    var group = CheckboxGroup.init(&items);

    group.checkAll();
    try std.testing.expect(items[0].checked);
    try std.testing.expect(items[1].checked);
    try std.testing.expect(items[2].checked);

    group.uncheckAll();
    try std.testing.expect(!items[0].checked);
    try std.testing.expect(!items[1].checked);
    try std.testing.expect(!items[2].checked);
}

test "CheckboxGroup: render" {
    var items = [_]Checkbox{
        Checkbox.init("Item 1"),
        Checkbox.init("Item 2"),
    };

    const group = CheckboxGroup.init(&items);
    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    group.render(&buf, area);

    // Check first item rendered
    const bracket = buf.get(0, 0);
    try std.testing.expectEqual('[', bracket.char);
}

test "CheckboxGroup: render with block" {
    var items = [_]Checkbox{
        Checkbox.init("Option"),
    };

    const block = (Block{}).withTitle("Choose options");
    const group = CheckboxGroup.init(&items).withBlock(block);

    var buf = try Buffer.init(std.testing.allocator, 30, 5);
    defer buf.deinit(std.testing.allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 5 };
    group.render(&buf, area);

    // Check block border
    const top_left = buf.get(0, 0);
    try std.testing.expectEqual(symbols.border.plain.top_left, top_left.char);
}
